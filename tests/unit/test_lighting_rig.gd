extends GutTest
## The light rig: budget, retinting, pulse envelope and caching.


func before_each() -> void:
	LightingRig.clear_cache()


func after_each() -> void:
	LightingRig.clear_cache()
	Settings.reduce_motion = false


func _make_rig(root: Node2D, pulse_bpm: float = 0.0) -> LightingRig:
	return LightingRig.build(root, pulse_bpm)


func test_build_stays_within_the_light_budget() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var rig := _make_rig(root)
	assert_true(rig.lights().size() <= LightingRig.MAX_LIGHTS, "UX_BIBLE §3.5: ≤ 8 emitters")
	assert_true(rig.lights().size() >= 6, "four pools + chute + spawn fill")
	assert_eq(rig.pools().size(), 4, "one pool per washer")


func test_room_tint_is_cool_and_dark() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var rig := _make_rig(root)
	var tint := rig.room_tint()
	assert_not_null(tint)
	assert_eq(tint.color, LightingRig.ROOM_TINT)
	assert_lt(tint.color.get_luminance(), 0.85, "the room is dimmed, not lit")
	assert_gt(tint.color.b, tint.color.r, "the room is cooled toward blue")


func test_radial_texture_is_cached() -> void:
	var first := LightingRig.radial_texture()
	assert_same(first, LightingRig.radial_texture())
	assert_eq(first.get_width(), LightingRig.GRADIENT_RADIUS * 2)


func test_set_phase_palette_retints_the_pools() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var rig := _make_rig(root)
	var wanted: Array[StringName] = [&"red", &"blue", &"yellow", &"red"]
	rig.set_phase_palette(wanted)
	var pools := rig.pools()
	var red := pools[0].self_modulate
	var blue := pools[1].self_modulate
	var yellow := pools[2].self_modulate
	assert_gt(red.r, red.b, "first pool is crimson")
	assert_gt(blue.b, blue.r, "second pool is nebula blue")
	assert_gt(yellow.r, yellow.b, "third pool is solar yellow")
	assert_almost_eq(yellow.g, Palette.YEL_2.g, 0.01, "retint uses the deeper palette ramp")


func test_set_phase_palette_accepts_a_short_list() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var rig := _make_rig(root)
	var only_blue: Array[StringName] = [&"blue"]
	rig.set_phase_palette(only_blue)
	for pool in rig.pools():
		assert_gt(pool.self_modulate.b, pool.self_modulate.r, "all pools fall back to blue")
	var empty: Array[StringName] = []
	rig.set_phase_palette(empty)
	assert_gt(rig.pools()[0].self_modulate.r, rig.pools()[0].self_modulate.b, "default palette")


func test_reduce_motion_pins_the_pulse() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var rig := _make_rig(root, 90.0)
	Settings.reduce_motion = false
	rig._clock = 0.0
	assert_almost_eq(rig.beat_envelope(), 1.0, 0.001, "pulse peaks on the beat")
	rig._clock = 0.2
	assert_lt(rig.beat_envelope(), 0.5, "and decays")
	Settings.reduce_motion = true
	assert_eq(rig.beat_envelope(), 0.0)


func test_intensity_scales_every_emitter() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var rig := _make_rig(root, 90.0)
	rig._clock = 0.0
	rig.intensity = 0.5
	rig._update_energy()
	var dimmed := rig.pools()[0].self_modulate.a
	rig.intensity = 1.0
	rig._update_energy()
	var full := rig.pools()[0].self_modulate.a
	assert_almost_eq(dimmed * 2.0, full, 0.01)
	assert_gt(full, LightingRig.WASHER_ENERGY, "the beat adds energy on top of the base")


func test_reduce_motion_stops_the_atmosphere() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var atmosphere := Atmosphere.build(root, 90.0)
	var glow := Atmosphere.build_belt_glow(root, 90.0)
	Settings.reduce_motion = false
	atmosphere._apply_reduce_motion()
	assert_true(atmosphere.particles_active(), "particles run when motion is allowed")
	assert_not_null(glow)
	Settings.reduce_motion = true
	atmosphere._apply_reduce_motion()
	assert_false(atmosphere.particles_active(), "reduce motion stops the emitters")
	assert_almost_eq(glow.call("beat_envelope"), 0.0, 0.001, "and pins the neon to its base")


func test_light_budget_is_eight_emitters_and_zero_point_lights() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var rig := _make_rig(root)
	assert_lte(rig.lights().size(), 8, "never more than the light budget")
	var point_lights := 0
	for light: CanvasItem in rig.lights():
		if light is PointLight2D:
			point_lights += 1
	if LightingRig.USE_POINT_LIGHTS:
		assert_true(point_lights <= 8, "≤ 8 PointLight2D when the flag is on")
	else:
		assert_eq(point_lights, 0, "the default path uses no PointLight2D at all")


func test_coloured_light_stays_near_the_machines() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var rig := _make_rig(root)
	assert_lte(LightingRig.WASHER_RADIUS, 180.0, "pools stay inside 180 px")
	assert_lte(LightingRig.WASHER_ENERGY, 0.45, "energy budget")
	assert_lte(LightingRig.CHUTE_ENERGY, 0.45, "energy budget")
	var anchors: Array[Vector2] = [RoomBuilder.layout_rect("chute").get_center()]
	for washer: Dictionary in RoomBuilder.layout().get("washers", []):
		anchors.append(RoomBuilder.point_world(washer.get("mouth", [0, 0])))
	anchors.append(RoomBuilder.player_spawn())
	for light: CanvasItem in rig.lights():
		var nearest := INF
		for anchor: Vector2 in anchors:
			nearest = minf(nearest, light.position.distance_to(anchor))
		assert_lt(nearest, 8.0, "%s is anchored to a machine" % light.name)


func test_atmosphere_has_no_hard_edged_light_shafts() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var atmosphere := Atmosphere.build(root, 90.0)
	assert_null(atmosphere.get_node_or_null(^"LightShafts"), "lamp shafts were removed")
	for child in atmosphere.get_children():
		if child is Node2D and not (child is CPUParticles2D) and not (child is Timer):
			fail_test("unexpected hand-drawn light quad: %s" % child.name)


func test_five_builds_do_not_leak_a_texture_each() -> void:
	var texture := LightingRig.radial_texture()
	for index in range(5):
		var root := Node2D.new()
		add_child_autofree(root)
		_make_rig(root)
		assert_same(texture, LightingRig.radial_texture(), "build %d reused the gradient" % index)

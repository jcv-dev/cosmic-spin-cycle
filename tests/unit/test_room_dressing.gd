extends GutTest
## Floor story, machine dressing and foreground (`docs/UX_BIBLE.md` §3.4/§3.6).
##
## The specs are pure functions so the tests can assert the properties the renderer relies
## on: deterministic layout for a seed, integer world coordinates, a foreground that never
## obscures the play lane, and cached generated textures.

const LANE := Rect2(120.0, 120.0, 1040.0, 480.0)


func before_each() -> void:
	RoomDressing.clear_cache()


func after_each() -> void:
	RoomDressing.clear_cache()


func _floats_are_integers(specs: Array[Dictionary]) -> bool:
	for spec: Dictionary in specs:
		for key in ["points", "rect", "center"]:
			if not spec.has(key):
				continue
			var value: Variant = spec[key]
			if value is PackedVector2Array:
				for point: Vector2 in value:
					if point.x != floorf(point.x) or point.y != floorf(point.y):
						return false
			elif value is Vector2:
				var vector: Vector2 = value
				if vector.x != floorf(vector.x) or vector.y != floorf(vector.y):
					return false
			elif value is Rect2:
				var rect: Rect2 = value
				if rect.position.x != floorf(rect.position.x):
					return false
				if rect.position.y != floorf(rect.position.y):
					return false
				if rect.size.x != floorf(rect.size.x) or rect.size.y != floorf(rect.size.y):
					return false
	return true


func test_floor_specs_are_deterministic_for_a_seed() -> void:
	var first := RoomDressing.floor_specs(1234)
	var second := RoomDressing.floor_specs(1234)
	assert_gt(first.size(), 40, "the floor story is not two decals")
	assert_eq(first.size(), second.size(), "same seed, same element count")
	for index in range(first.size()):
		assert_eq(first[index], second[index], "spec %d must be identical" % index)


func test_floor_specs_change_with_the_seed() -> void:
	var first := RoomDressing.floor_specs(1234)
	var other := RoomDressing.floor_specs(9876)
	assert_ne(first, other, "the seeded smear must move")


func test_floor_specs_land_on_whole_pixels() -> void:
	assert_true(_floats_are_integers(RoomDressing.floor_specs()), "no sub-pixel decals")


func test_floor_specs_avoid_obscuring_the_chute_approach() -> void:
	var chute := RoomBuilder.layout_rect("chute")
	for spec: Dictionary in RoomDressing.floor_specs():
		if String(spec.get("kind", "")) != "poly":
			continue
		for point: Vector2 in spec["points"] as PackedVector2Array:
			var inside := chute.grow(-8.0).has_point(point)
			assert_false(inside, "no polygon over the chute mouth")


func test_dressing_specs_are_deterministic_and_integral() -> void:
	var first := RoomDressing.dressing_specs(77)
	var second := RoomDressing.dressing_specs(77)
	assert_gt(first.size(), 20)
	assert_eq(first, second)
	assert_true(_floats_are_integers(first))


func test_dressing_keeps_the_play_lane_calm() -> void:
	# Props may hug the lane edges, but nothing may sit on top of the player spawn.
	var spawn := RoomBuilder.player_spawn()
	for spec: Dictionary in RoomDressing.dressing_specs():
		var rect: Variant = spec.get("rect")
		if rect is Rect2:
			var box: Rect2 = rect
			assert_false(
				box.grow(-1.0).has_point(spawn), "dressing %s covers the spawn" % spec.get("kind")
			)


func test_foreground_specs_never_cover_the_play_lane() -> void:
	for spec: Dictionary in RoomDressing.foreground_specs():
		var rect: Variant = spec.get("rect")
		if not (rect is Rect2):
			continue
		var box: Rect2 = rect
		var overlap := box.intersection(LANE)
		assert_true(
			overlap.size.x <= 0.0 or overlap.size.y <= 0.0,
			"foreground geometry must stay outside the lane: %s" % str(box),
		)


func test_overlay_texture_is_cached_and_lane_safe() -> void:
	var first := RoomDressing.overlay_texture()
	var second := RoomDressing.overlay_texture()
	assert_same(first, second, "the overlay must be cached")
	var image := first.get_image()
	assert_eq(image.get_size(), Vector2i(320, 180))
	# The lane is x 30…289, y 30…149 in art pixels: only dust may touch it.
	for y in range(32, 148, 7):
		for x in range(32, 288, 7):
			var pixel := image.get_pixel(x, y)
			assert_lt(pixel.a, 0.08, "lane pixel (%d,%d) alpha %.3f" % [x, y, pixel.a])
	assert_gt(image.get_pixel(2, 90).a, 0.2, "the frame edge is vignetted")


func test_overlay_never_covers_the_chute_ring_or_the_drums() -> void:
	var image := RoomDressing.overlay_texture().get_image()
	var chute := RoomBuilder.layout_rect("chute")
	var centre := chute.get_center() / float(Config.ART_SCALE)
	var radius := 108.0 / float(Config.ART_SCALE)
	# Sample the beacon ring circle itself (world radius 108 → 27 art px).
	for step in range(24):
		var angle := TAU * float(step) / 24.0
		var at := centre + Vector2(cos(angle), sin(angle)) * radius
		var pixel := image.get_pixel(int(at.x), int(at.y))
		assert_lt(pixel.a, 0.07, "chute ring sample %d is shaded" % step)
	for washer: Dictionary in RoomBuilder.layout().get("washers", []):
		var rect := RoomBuilder.rect_world(washer)
		# Drum window: machine centre, 22 art px below the top edge.
		var drum := Vector2(rect.get_center().x, rect.position.y + 88.0)
		var art := drum / float(Config.ART_SCALE)
		for offset in [Vector2.ZERO, Vector2(-8, 0), Vector2(8, 0), Vector2(0, -8), Vector2(0, 8)]:
			var pixel := image.get_pixel(int(art.x + offset.x), int(art.y + offset.y))
			assert_lt(pixel.a, 0.07, "drum sample of %s is shaded" % washer.get("id"))


func test_room_layers_have_the_documented_z_order() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var nodes := RoomBuilder.build(root)
	assert_not_null(root.get_node_or_null("RoomBackground"))
	var background := root.get_node("RoomBackground") as CanvasItem
	var backdrop := nodes["backdrop"] as CanvasItem
	var floor_layer := nodes["floor"] as CanvasItem
	var dressing := nodes["dressing"] as CanvasItem
	var foreground := nodes["foreground"] as CanvasItem
	assert_eq(background.z_index, -100)
	assert_eq(backdrop.z_index, -95)
	assert_eq(floor_layer.z_index, -90)
	assert_eq(dressing.z_index, -80)
	assert_eq(foreground.z_index, 20)
	assert_true(backdrop.z_index > background.z_index)
	assert_true(floor_layer.z_index > backdrop.z_index)
	assert_true(dressing.z_index > floor_layer.z_index)
	assert_true(foreground.z_index > dressing.z_index)


func test_floor_decals_are_a_child_of_the_floor_layer() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var nodes := RoomBuilder.build(root)
	var floor_layer := nodes["floor"] as Node2D
	var decals := floor_layer.get_node_or_null("FloorDecals") as RoomDressing
	assert_not_null(decals, "decals ride inside the z −90 Floor layer")
	assert_gt(decals.element_count(), 40)


func test_five_builds_share_the_cached_textures() -> void:
	var overlay := RoomDressing.overlay_texture()
	for index in range(5):
		var root := Node2D.new()
		add_child_autofree(root)
		RoomBuilder.build(root)
		assert_same(
			overlay,
			RoomDressing.overlay_texture(),
			"build %d must reuse the overlay texture" % index,
		)


func test_display_machinery_places_four_washers_and_a_chute() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var machines := RoomDressing.build_machines_for_display(root)
	var washers: Dictionary = machines["washers"]
	assert_eq(washers.size(), 4)
	for key: StringName in washers.keys():
		var sprite := washers[key] as AnimatedSprite2D
		assert_not_null(sprite)
		assert_eq(sprite.scale, Vector2(4, 4), "art is only ever scaled ×4")
		assert_eq(sprite.rotation, 0.0, "art sprites never rotate")
	assert_not_null(machines["chute"])

extends GutTest
## The living title diorama: it must instantiate standalone, frame the room, freeze on
## `set_paused` and settle the camera on `play_intro` (CONTRACTS §9).

const SCENE := "res://scenes/main/Diorama.tscn"


func _spawn() -> Diorama:
	var packed := load(SCENE) as PackedScene
	assert_not_null(packed, "Diorama.tscn must exist")
	if packed == null:
		return null
	var node := packed.instantiate() as Diorama
	add_child_autofree(node)
	return node


func test_scene_instantiates_and_builds_the_room() -> void:
	var diorama := _spawn()
	await wait_frames(2)
	assert_not_null(diorama)
	assert_true(diorama.is_inside_tree())
	assert_not_null(diorama.get_node_or_null("RoomBackground"))
	assert_not_null(diorama.get_node_or_null("Backdrop"))
	assert_not_null(diorama.get_node_or_null("Floor"))
	assert_not_null(diorama.get_node_or_null("Foreground"))
	assert_not_null(diorama.get_node_or_null("Belts"))


func test_has_a_zoomed_camera_at_the_room_centre() -> void:
	var diorama := _spawn()
	await wait_frames(2)
	var camera := diorama.camera_node()
	assert_not_null(camera)
	assert_true(camera.is_current())
	assert_eq(camera.zoom, Vector2(Diorama.CAMERA_ZOOM, Diorama.CAMERA_ZOOM))
	assert_almost_eq(camera.position.x, Diorama.CAMERA_HOME.x, 20.0)
	assert_almost_eq(camera.position.y, Diorama.CAMERA_HOME.y, 20.0)


func test_machines_and_pip_are_present() -> void:
	var diorama := _spawn()
	await wait_frames(2)
	var washers: Dictionary = diorama.machines.get("washers", {})
	assert_eq(washers.size(), 4, "four washer sprites")
	var chute := diorama.machines.get("chute") as AnimatedSprite2D
	assert_not_null(chute)
	assert_eq(chute.animation, &"open")
	var pip := diorama.get_node_or_null(^"Pip") as AnimatedSprite2D
	assert_not_null(pip, "Pip idles by the chute")
	assert_eq(pip.animation, &"idle_down")
	assert_almost_eq(pip.sprite_frames.get_animation_speed(&"idle_down"), 3.0, 0.01)


func test_art_sprites_keep_whole_scale_and_no_rotation() -> void:
	var diorama := _spawn()
	await wait_frames(2)
	for node in diorama.find_children("*", "AnimatedSprite2D", true, false):
		var sprite := node as AnimatedSprite2D
		assert_eq(sprite.rotation, 0.0, "%s must not rotate" % sprite.name)
		assert_eq(sprite.scale.x, floorf(sprite.scale.x), "%s scale" % sprite.name)
		assert_eq(sprite.scale.y, floorf(sprite.scale.y), "%s scale" % sprite.name)
	for node in diorama.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		if not (sprite.texture is AtlasTexture):
			continue
		assert_eq(sprite.rotation, 0.0, "%s must not rotate" % sprite.name)
		assert_eq(sprite.scale.x, floorf(sprite.scale.x), "%s art scale" % sprite.name)


func test_set_paused_freezes_tweens_and_animations() -> void:
	var diorama := _spawn()
	await wait_frames(2)
	var camera := diorama.camera_node()
	var items: Array[AnimatedSprite2D] = diorama._items
	assert_gt(items.size(), 0, "the diorama needs moving laundry")
	diorama.set_paused(true)
	assert_true(diorama.is_paused())
	var camera_before := camera.position
	var item_before := items[0].position.x
	await wait_frames(12)
	assert_eq(camera.position, camera_before, "the pan must stop while paused")
	assert_eq(items[0].position.x, item_before, "item tweens must pause")
	assert_eq(items[0].speed_scale, 0.0)
	for belt: ConveyorBelt in diorama._belts:
		assert_false(belt.is_active(), "belts stop while paused")
	diorama.set_paused(false)
	assert_false(diorama.is_paused())
	assert_gt(items[0].speed_scale, 0.0)


func test_play_intro_settles_the_camera() -> void:
	var diorama := _spawn()
	await wait_frames(2)
	var camera := diorama.camera_node()
	diorama.play_intro()
	assert_eq(camera.zoom, Vector2(1.0, 1.0), "the intro starts wide")
	var tween := diorama._intro_tween
	assert_not_null(tween)
	assert_true(tween.is_running())
	await wait_seconds(0.4)
	assert_gt(camera.zoom.x, 1.0, "and eases in")
	await wait_seconds(1.1)
	assert_almost_eq(camera.zoom.x, Diorama.CAMERA_ZOOM, 0.02, "settles at the menu zoom")
	assert_almost_eq(diorama._intro_offset.length(), 0.0, 0.5)


func test_items_ride_the_belt_baseline() -> void:
	var diorama := _spawn()
	await wait_frames(2)
	var belt := RoomBuilder.layout_rect("belt_north")
	assert_gt(diorama._items.size(), 0)
	for item: AnimatedSprite2D in diorama._items:
		assert_almost_eq(
			item.position.y,
			belt.position.y + 40.0,
			0.01,
			"items stand on the belt deck, not above it",
		)
		assert_true(
			item.position.y > belt.position.y and item.position.y < belt.end.y,
			"item baseline inside the belt band",
		)


func test_scrim_stops_before_the_chute_ring() -> void:
	var diorama := _spawn()
	await wait_frames(2)
	var scrim := diorama.camera_node().get_node_or_null("MenuScrim") as Node2D
	assert_not_null(scrim, "the scrim is anchored to the camera")
	var chute := RoomBuilder.layout_rect("chute")
	var ring_radius := Diorama.CHUTE_RING_RADIUS
	# Worst case: the camera pushed as far right as the pan allows moves the ring left.
	var camera_x := Diorama.CAMERA_HOME.x + Diorama.PAN_X
	var zoom := Diorama.CAMERA_ZOOM
	# On-screen left edge of the outer beacon ring, in the same space as SCRIM_STEPS.
	var ring_left := (chute.get_center().x - (ring_radius + 14.0) - camera_x) * zoom + 640.0
	var last_edge: float = Diorama.SCRIM_STEPS[Diorama.SCRIM_STEPS.size() - 1]
	assert_lt(last_edge, ring_left, "the scrim must not touch the chute ring")
	assert_gt(last_edge, 320.0, "but it must cover the menu column")


func test_diorama_keeps_the_washer_cabinets_secondary() -> void:
	var diorama := _spawn()
	await wait_frames(2)
	var washers: Dictionary = diorama.machines.get("washers", {})
	for key: StringName in washers.keys():
		var sprite := washers[key] as AnimatedSprite2D
		assert_almost_eq(sprite.self_modulate.r, RoomDressing.MACHINE_ALBEDO.r, 0.001)
		assert_lt(sprite.self_modulate.r, 0.95, "cabinets are dimmed below full albedo")
	var readouts := diorama.get_node_or_null(^"PanelReadouts") as RoomDressing
	assert_not_null(readouts, "the bright LED square is replaced by a deliberate readout")
	assert_eq(readouts.element_count(), 4)


func test_diorama_never_starts_the_shift_clock() -> void:
	var was_playing := BeatConductor.is_playing
	var diorama := _spawn()
	await wait_frames(2)
	assert_not_null(diorama)
	assert_eq(
		BeatConductor.is_playing,
		was_playing,
		"the diorama owns a local 90 BPM clock instead of the shift clock",
	)

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

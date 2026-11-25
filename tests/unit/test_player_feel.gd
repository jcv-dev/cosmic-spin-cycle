extends GutTest
## Player game-feel guarantees: art-grid snapping, reversal boost, short braking stop,
## 8-way aim assist and the sticky compatible-washer reticle.

const MOVEMENT_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]

var _player: Player = null


class FakeWasher:
	extends Node2D
	var requirement: StringName = &""

	func get_mouth_position() -> Vector2:
		return global_position


func before_each() -> void:
	GameState.reset(1234)
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)
	BeatConductor.start(120)
	BeatConductor.set_process(false)
	_player = (load(Config.SCENE_PLAYER) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.global_position = Vector2(400.0, 400.0)
	_player.set_aim_direction(Vector2.RIGHT)


func after_each() -> void:
	BeatConductor.stop()
	BeatConductor.set_process(true)
	for action in MOVEMENT_ACTIONS:
		Input.action_release(action)


func _add_item(item_id: StringName, position_hint: Vector2) -> LaundryItem:
	var item := (load(Config.SCENE_LAUNDRY_ITEM) as PackedScene).instantiate() as LaundryItem
	item.setup(item_id, &"red", &"solid", false)
	add_child_autofree(item)
	item.global_position = position_hint
	return item


func _add_washer(position_hint: Vector2, requirement: StringName = &"") -> FakeWasher:
	var washer := FakeWasher.new()
	washer.requirement = requirement
	washer.global_position = position_hint
	add_child_autofree(washer)
	washer.add_to_group(Config.GROUP_WASHERS)
	return washer


func test_sprite_stays_on_the_four_pixel_art_grid() -> void:
	_player.global_position = Vector2(401.3, 398.7)
	Input.action_press(&"move_right")
	await wait_physics_frames(40)
	var position := _player.visual.global_position
	assert_almost_eq(position.x / 4.0, roundf(position.x / 4.0), 0.0001, "x snaps to art px")
	assert_almost_eq(position.y / 4.0, roundf(position.y / 4.0), 0.0001, "y snaps to art px")


func test_animation_offsets_are_whole_art_pixels() -> void:
	Input.action_press(&"move_right")
	await wait_physics_frames(30)
	var base := (_player.global_position / 4.0).round() * 4.0
	var offset := _player.visual.global_position - base
	assert_almost_eq(offset.x / 4.0, roundf(offset.x / 4.0), 0.0001, "run lean is art-aligned")
	assert_almost_eq(offset.y / 4.0, roundf(offset.y / 4.0), 0.0001, "run bob is art-aligned")
	assert_lte(absf(offset.x) + absf(offset.y), 8.0, "lean never exceeds one art pixel per axis")


func test_idle_breathing_moves_in_whole_art_pixels_only() -> void:
	await wait_physics_frames(45)
	var base := (_player.global_position / 4.0).round() * 4.0
	var offset := _player.visual.global_position - base
	assert_almost_eq(offset.x / 4.0, roundf(offset.x / 4.0), 0.0001)
	assert_true(offset.y == 0.0 or offset.y == -4.0, "breath is exactly one art pixel up")


func test_reversal_is_faster_than_unboosted_acceleration() -> void:
	assert_gt(Player.FEEL_REVERSAL_BOOST, 1.0)
	_player.velocity = Vector2(Config.PLAYER_MAX_SPEED, 0.0)
	var start_frame := Engine.get_physics_frames()
	Input.action_press(&"move_left")
	while _player.velocity.x > -Config.PLAYER_MAX_SPEED * 0.9:
		await wait_physics_frames(1)
	var frames := Engine.get_physics_frames() - start_frame
	# Unboosted would need ~17 frames for 1.8 × max speed at PLAYER_ACCEL.
	assert_lte(frames, 14, "the 1.6× reversal boost turns around in ≤ 14 frames")
	assert_gt(frames, 5, "the turnaround still takes real time")


func test_braking_stops_the_player_in_about_two_hundred_ms() -> void:
	_player.velocity = Vector2(Config.PLAYER_MAX_SPEED, 0.0)
	var start_frame := Engine.get_physics_frames()
	while _player.velocity.length() > Config.PLAYER_MAX_SPEED * 0.02:
		await wait_physics_frames(1)
	var frames := Engine.get_physics_frames() - start_frame
	assert_lte(frames, 16, "ease-out braking reaches rest within 16 frames (~267 ms)")
	assert_gte(frames, 8, "braking keeps some weight instead of stopping instantly")


func _measure_turnaround(boost: float, window: float) -> int:
	_player._reversal_boost = boost
	_player._turn_boost_s = window
	_player.velocity = Vector2(Config.PLAYER_MAX_SPEED, 0.0)
	var start_frame := Engine.get_physics_frames()
	Input.action_press(&"move_left")
	while _player.velocity.x > -Config.PLAYER_MAX_SPEED * 0.9:
		await wait_physics_frames(1)
	var frames := Engine.get_physics_frames() - start_frame
	Input.action_release(&"move_left")
	_player.velocity = Vector2.ZERO
	await wait_physics_frames(2)
	return frames


func test_reversal_boost_is_faster_than_unboosted_acceleration_directly() -> void:
	var unboosted := await _measure_turnaround(1.0, 0.0)
	var boosted := await _measure_turnaround(Player.FEEL_REVERSAL_BOOST, Player.FEEL_TURN_BOOST_S)
	assert_lt(boosted, unboosted, "the boosted turnaround uses fewer physics frames")
	assert_gt(boosted, 2, "the boosted turnaround still takes real frames")
	_player._reversal_boost = Player.FEEL_REVERSAL_BOOST
	_player._turn_boost_s = Player.FEEL_TURN_BOOST_S


func test_stick_aim_snaps_within_twelve_degrees() -> void:
	var near := _player._snap_to_eight(Vector2.from_angle(deg_to_rad(10.0)))
	assert_almost_eq(near.angle(), 0.0, 0.0001, "10° off the cardinal snaps to it")
	var far := _player._snap_to_eight(Vector2.from_angle(deg_to_rad(20.0)))
	assert_almost_eq(far.angle(), deg_to_rad(20.0), 0.0001, "20° stays analog")


func test_compatible_washer_becomes_the_assisted_target() -> void:
	var washer := _add_washer(_player.global_position + Vector2(200.0, 20.0))
	await wait_physics_frames(2)
	assert_eq(_player.get_assisted_target(), washer, "washer in the 18° cone is assisted")
	assert_almost_eq(
		_player.aim_indicator.position.length(),
		Player.FEEL_RETICLE_OFFSET,
		0.01,
		"reticle is offset by 2 px"
	)


func test_incompatible_washer_is_not_assisted() -> void:
	_add_washer(_player.global_position + Vector2(200.0, 20.0), &"red")
	var blue := _add_item(&"rocky", _player.global_position + Vector2(30.0, 0.0))
	blue.color = &"blue"
	_player.grab_or_throw()
	await wait_physics_frames(3)
	assert_eq(_player.held_item, blue)
	assert_null(_player.get_assisted_target(), "blue item does not snap to the red washer")


func test_washer_behind_the_aim_is_ignored() -> void:
	_add_washer(_player.global_position + Vector2(-200.0, 0.0))
	await wait_physics_frames(2)
	assert_null(_player.get_assisted_target(), "the cone is directional")


func test_aim_assist_resets_the_reticle_when_the_target_is_removed() -> void:
	var washer := _add_washer(_player.global_position + Vector2(200.0, 0.0))
	await wait_physics_frames(2)
	assert_eq(_player.get_assisted_target(), washer)
	washer.queue_free()
	await wait_physics_frames(2)
	assert_null(_player.get_assisted_target())
	assert_eq(_player.aim_indicator.position, Vector2.ZERO, "reticle returns to the aim line")

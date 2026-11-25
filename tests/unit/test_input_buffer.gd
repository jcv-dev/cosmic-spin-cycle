extends GutTest
## 120 ms input buffering: a press that becomes legal inside the window still fires, and
## pause / shift end / expired windows clear it.

var _player: Player = null


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


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	_player._input(event)


func _add_item(item_id: StringName, position_hint: Vector2) -> LaundryItem:
	var item := (load(Config.SCENE_LAUNDRY_ITEM) as PackedScene).instantiate() as LaundryItem
	item.setup(item_id, &"red", &"solid", false)
	add_child_autofree(item)
	item.global_position = position_hint
	return item


func test_grab_pressed_before_an_item_is_in_range_still_fires() -> void:
	_press(&"grab_throw")
	assert_eq(_player.get_buffered_action(), &"grab_throw", "empty grab is buffered")
	var item := _add_item(&"rocky", _player.global_position + Vector2(40.0, 0.0))
	await wait_physics_frames(3)
	assert_eq(_player.held_item, item, "buffered grab fired when the item entered range")
	assert_eq(_player.get_buffered_action(), &"", "buffer clears after firing")


func test_buffer_expires_after_the_window() -> void:
	_press(&"grab_throw")
	assert_eq(_player.get_buffered_action(), &"grab_throw")
	await wait_physics_frames(9)
	assert_eq(_player.get_buffered_action(), &"", "120 ms window expired")
	var item := _add_item(&"rocky", _player.global_position + Vector2(40.0, 0.0))
	await wait_physics_frames(3)
	assert_null(_player.held_item, "an expired press never fires late")
	assert_true(is_instance_valid(item))


func test_buffer_does_not_survive_a_shift_end() -> void:
	_press(&"grab_throw")
	assert_eq(_player.get_buffered_action(), &"grab_throw")
	GameState.end_shift(false, "test")
	await wait_physics_frames(2)
	assert_eq(_player.get_buffered_action(), &"", "ending the shift drops the buffered press")
	_add_item(&"rocky", _player.global_position + Vector2(40.0, 0.0))
	await wait_physics_frames(3)
	assert_null(_player.held_item)


func test_buffer_does_not_survive_pause() -> void:
	_press(&"grab_throw")
	assert_eq(_player.get_buffered_action(), &"grab_throw")
	_player._notification(Node.NOTIFICATION_PAUSED)
	assert_eq(_player.get_buffered_action(), &"", "pause clears the buffer")
	_add_item(&"rocky", _player.global_position + Vector2(40.0, 0.0))
	await wait_physics_frames(3)
	assert_null(_player.held_item)


func test_strike_pressed_during_dash_cooldown_fires_once_it_is_ready() -> void:
	var washer := Node2D.new()
	washer.add_to_group(Config.GROUP_WASHERS)
	add_child_autofree(washer)
	washer.global_position = _player.global_position + Vector2(50.0, 0.0)
	watch_signals(_player)
	_player.dash_cooldown_left = 0.05
	_press(&"rhythm_strike")
	assert_eq(_player.get_buffered_action(), &"rhythm_strike", "strike is buffered on cooldown")
	assert_eq(GameState.rhythm_actions, 1, "the press is still graded immediately")
	await wait_physics_frames(5)
	assert_eq(_player.get_buffered_action(), &"", "strike fired when the dash became ready")
	assert_true(_player.is_dashing, "the buffered strike started its dash")
	assert_signal_emitted_with_parameters(
		_player, "struck", [washer, RhythmEvaluator.Grade.PERFECT]
	)
	assert_eq(GameState.rhythm_actions, 1, "firing the buffer does not grade a second time")


func test_buffered_grab_never_double_grabs() -> void:
	_press(&"grab_throw")
	var first := _add_item(&"rocky", _player.global_position + Vector2(40.0, 0.0))
	await wait_physics_frames(3)
	assert_eq(_player.held_item, first)
	_add_item(&"sock", _player.global_position + Vector2(30.0, 0.0))
	await wait_physics_frames(3)
	assert_eq(_player.held_item, first, "only the buffered press fires; no repeat grabs")

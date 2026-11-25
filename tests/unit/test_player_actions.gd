extends GutTest
## Player actions: grab -> throw handshake, strike targeting and grade bookkeeping.

var _washer: Node2D = null


func before_each() -> void:
	GameState.reset(1234)
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)
	BeatConductor.start(120)
	# Freeze the free-run clock so a long GUT frame cannot drift the grade off PERFECT.
	BeatConductor.set_process(false)


func after_each() -> void:
	BeatConductor.stop()
	BeatConductor.set_process(true)


func _add_player(position_hint: Vector2) -> Player:
	var player := (load(Config.SCENE_PLAYER) as PackedScene).instantiate() as Player
	add_child_autofree(player)
	player.global_position = position_hint
	player.set_aim_direction(Vector2.RIGHT)
	return player


func _add_item(item_id: StringName, position_hint: Vector2) -> LaundryItem:
	var item := (load(Config.SCENE_LAUNDRY_ITEM) as PackedScene).instantiate() as LaundryItem
	item.setup(item_id, &"red", &"solid", false)
	add_child_autofree(item)
	item.global_position = position_hint
	return item


func _add_washer(position_hint: Vector2) -> Node2D:
	_washer = Node2D.new()
	_washer.add_to_group(Config.GROUP_WASHERS)
	add_child_autofree(_washer)
	_washer.global_position = position_hint
	return _washer


func test_grab_then_throw_is_one_graded_action() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	var item := _add_item(&"rocky", Vector2(440.0, 400.0))
	watch_signals(player)
	player.grab_or_throw()
	assert_eq(player.held_item, item, "nearest item is now held")
	assert_true(item.is_held)
	assert_signal_emitted(player, "grabbed")
	assert_eq(GameState.rhythm_actions, 0, "a grab is not a rhythm action")

	player.grab_or_throw()
	assert_signal_emitted(player, "thrown")
	assert_eq(GameState.rhythm_actions, 1, "exactly one grade per throw")
	assert_eq(player.last_grade, RhythmEvaluator.Grade.PERFECT)
	assert_null(player.held_item)
	assert_false(item.is_held)
	await wait_physics_frames(1)
	assert_gt(item.linear_velocity.length(), 1000.0, "throw impulse was applied")


func test_grab_with_nothing_in_range_does_nothing() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	watch_signals(player)
	player.grab_or_throw()
	assert_null(player.held_item)
	assert_eq(GameState.rhythm_actions, 0)
	assert_signal_emit_count(player, "grabbed", 0)


func test_second_grab_while_holding_throws_instead() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	var first := _add_item(&"rocky", Vector2(420.0, 400.0))
	var second := _add_item(&"sock", Vector2(430.0, 400.0))
	watch_signals(player)
	player.grab_or_throw()
	assert_eq(player.held_item, first, "nearest of two items wins")
	player.grab_or_throw()
	assert_signal_emit_count(player, "thrown", 1)
	assert_eq(GameState.rhythm_actions, 1)
	assert_false(first.is_held)
	assert_false(second.is_held, "only one item was ever held")


func test_strike_hits_washer_in_front_and_grades_once() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	var washer := _add_washer(Vector2(470.0, 400.0))
	watch_signals(player)
	player.do_strike()
	assert_signal_emitted_with_parameters(player, "struck", [washer, RhythmEvaluator.Grade.PERFECT])
	assert_eq(GameState.rhythm_actions, 1, "one strike, one grade")
	assert_eq(GameState.perfect_count, 1)
	assert_eq(player.last_grade, RhythmEvaluator.Grade.PERFECT)


func test_strike_ignores_washer_behind_the_aim() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	_add_washer(Vector2(330.0, 400.0))
	watch_signals(player)
	player.do_strike()
	assert_signal_emit_count(player, "struck", 0)
	assert_eq(GameState.rhythm_actions, 1, "a whiffed strike still costs a graded action")


func test_strike_ignores_washer_out_of_range() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	_add_washer(Vector2(400.0 + Config.STRIKE_RANGE_PX + 20.0, 400.0))
	watch_signals(player)
	player.do_strike()
	assert_signal_emit_count(player, "struck", 0)


func test_two_strikes_register_two_grades() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	_add_washer(Vector2(460.0, 400.0))
	player.do_strike()
	player.do_strike()
	assert_eq(GameState.rhythm_actions, 2, "one register_grade per action, never per target")


func test_strike_emits_once_per_washer_in_range() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	_add_washer(Vector2(450.0, 400.0))
	var second := _add_washer(Vector2(400.0, 450.0))
	player.set_aim_direction(Vector2(0.0, 1.0))
	watch_signals(player)
	player.do_strike()
	assert_eq(GameState.rhythm_actions, 1)
	assert_signal_emit_count(player, "struck", 1, "only the aimed-at washer is hit")
	assert_true(is_instance_valid(second))


func test_grabbed_item_follows_the_hold_point() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	var item := _add_item(&"moon", Vector2(450.0, 400.0))
	player.grab_or_throw()
	await wait_physics_frames(60)
	assert_almost_eq(
		item.global_position.distance_to(player.get_hold_position()),
		1.0,
		6.0,
		"held item settles at player + aim * hold clearance"
	)
	var expected_distance := Config.HOLD_DISTANCE + item.data.radius * float(Config.ART_SCALE)
	assert_almost_eq(
		item.global_position.distance_to(player.global_position), expected_distance, 6.0
	)

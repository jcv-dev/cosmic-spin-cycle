extends GutTest
## Throw impulse: grade scaling, gas-giant off-beat penalty, moon curve and safety clamps.

var _holder: Node2D = null
var _scratch: Array[LaundryItem] = []


func before_each() -> void:
	GameState.reset(1234)
	BeatConductor.stop()
	BeatConductor.start(120)
	_holder = Node2D.new()
	add_child_autofree(_holder)
	_holder.global_position = Vector2(900.0, 400.0)
	_scratch.clear()


func after_each() -> void:
	BeatConductor.stop()
	_scratch.clear()


func _add_item(item_id: StringName, position_hint: Vector2) -> LaundryItem:
	var item := (load(Config.SCENE_LAUNDRY_ITEM) as PackedScene).instantiate() as LaundryItem
	item.setup(item_id, &"red", &"solid", false)
	add_child_autofree(item)
	item.global_position = position_hint
	_scratch.append(item)
	return item


func _throw_once(
	item_id: StringName, grade: int, direction: Vector2 = Vector2.RIGHT
) -> LaundryItem:
	var lane := 80.0 + float(_scratch.size()) * 120.0
	var item := _add_item(item_id, Vector2(200.0, lane))
	await wait_physics_frames(2)
	item.begin_hold(_holder)
	assert_true(item.throw_with_impulse(direction, grade), "first throw is accepted")
	await wait_physics_frames(1)
	return item


func test_perfect_beats_good_and_good_equals_miss() -> void:
	var perfect := await _throw_once(&"rocky", RhythmEvaluator.Grade.PERFECT)
	var perfect_speed := perfect.linear_velocity.length()
	var good := await _throw_once(&"rocky", RhythmEvaluator.Grade.GOOD)
	var good_speed := good.linear_velocity.length()
	var miss := await _throw_once(&"rocky", RhythmEvaluator.Grade.MISS)
	var miss_speed := miss.linear_velocity.length()

	assert_gt(perfect_speed, good_speed * 1.2, "PERFECT adds the 40 % force bonus")
	assert_almost_eq(good_speed, miss_speed, 5.0, "GOOD and MISS use the same multiplier")
	assert_almost_eq(perfect_speed, Config.THROW_SPEED * 1.4, Config.THROW_SPEED * 0.05)
	assert_almost_eq(good_speed, Config.THROW_SPEED, Config.THROW_SPEED * 0.05)


func test_gas_giant_offbeat_throw_is_halved() -> void:
	var on_beat := await _throw_once(&"gas_giant", RhythmEvaluator.Grade.GOOD)
	var off_beat := await _throw_once(&"gas_giant", RhythmEvaluator.Grade.MISS)
	assert_almost_eq(
		off_beat.linear_velocity.length() * 2.0,
		on_beat.linear_velocity.length(),
		on_beat.linear_velocity.length() * 0.03,
		"MISS scales the gas giant by THROW_GAS_OFFBEAT_SCALE",
	)


func test_moon_offbeat_adds_a_perpendicular_curve() -> void:
	var curved := await _throw_once(&"moon", RhythmEvaluator.Grade.MISS)
	await wait_physics_frames(20)
	var straight := await _throw_once(&"moon", RhythmEvaluator.Grade.GOOD)
	await wait_physics_frames(20)
	assert_gt(absf(curved.linear_velocity.y), 50.0, "MISS bends the trajectory")
	assert_lt(absf(straight.linear_velocity.y), 10.0, "GOOD stays straight")
	assert_gt(curved.linear_velocity.x, 0.0, "curve keeps the forward component")


func test_second_throw_in_one_action_is_rejected() -> void:
	var item := _add_item(&"rocky", Vector2(600.0, 400.0))
	item.begin_hold(_holder)
	assert_true(item.throw_with_impulse(Vector2.RIGHT, RhythmEvaluator.Grade.GOOD))
	assert_false(
		item.throw_with_impulse(Vector2.LEFT, RhythmEvaluator.Grade.PERFECT), "no double impulses"
	)
	await wait_physics_frames(1)
	assert_almost_eq(item.linear_velocity.length(), Config.THROW_SPEED, Config.THROW_SPEED * 0.05)
	assert_gt(item.linear_velocity.x, 0.0, "second (rejected) direction never applied")
	assert_eq(item.throw_count, 1)


func test_speed_is_clamped_to_max_item_speed() -> void:
	var item := _add_item(&"rocky", Vector2(600.0, 400.0))
	item.linear_velocity = Vector2(Config.MAX_ITEM_SPEED + 500.0, 0.0)
	await wait_physics_frames(1)
	assert_lte(
		item.linear_velocity.length(),
		Config.MAX_ITEM_SPEED + 0.01,
		"integrate_forces clamps runaway speeds"
	)


func test_sock_grab_emits_squelch() -> void:
	var sock := _add_item(&"sock", Vector2(600.0, 400.0))

	watch_signals(sock)
	sock.begin_hold(_holder)
	assert_signal_emit_count(sock, "squelched", 1)
	var rocky := _add_item(&"rocky", Vector2(620.0, 400.0))
	watch_signals(rocky)
	rocky.begin_hold(_holder)
	assert_signal_emit_count(rocky, "squelched", 0, "only socks squelch")


func test_throw_requires_a_direction() -> void:
	var item := _add_item(&"rocky", Vector2(600.0, 400.0))
	item.begin_hold(_holder)
	assert_false(item.throw_with_impulse(Vector2.ZERO, RhythmEvaluator.Grade.GOOD))
	assert_true(item.is_held, "failed throw keeps the item held")

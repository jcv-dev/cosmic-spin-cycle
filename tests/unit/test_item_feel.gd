extends GutTest
## Throw weight and landing readability: follow-through, fake height, non-MISS guide and
## landing return-to-ground with no NaN.

var _holder: Node2D = null
var _player: Player = null


func before_each() -> void:
	GameState.reset(1234)
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)
	BeatConductor.start(120)
	BeatConductor.set_process(false)
	_holder = Node2D.new()
	add_child_autofree(_holder)
	_holder.global_position = Vector2(900.0, 400.0)
	_player = (load(Config.SCENE_PLAYER) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.global_position = Vector2(300.0, 400.0)
	_player.set_aim_direction(Vector2.RIGHT)


func after_each() -> void:
	BeatConductor.stop()
	BeatConductor.set_process(true)


func _add_item(item_id: StringName, position_hint: Vector2) -> LaundryItem:
	var item := (load(Config.SCENE_LAUNDRY_ITEM) as PackedScene).instantiate() as LaundryItem
	item.setup(item_id, &"red", &"solid", false)
	add_child_autofree(item)
	item.global_position = position_hint
	await wait_physics_frames(2)
	return item


func test_throw_arcs_up_and_returns_to_the_ground() -> void:
	var item: LaundryItem = await _add_item(&"rocky", Vector2(200.0, 300.0))
	item.begin_hold(_holder)
	assert_true(item.throw_with_impulse(Vector2.RIGHT, RhythmEvaluator.Grade.GOOD))
	await wait_physics_frames(6)
	assert_gt(item.height, 0.0, "the item leaves the floor")
	assert_lte(item.height, 24.0, "height is capped at 24 px")
	assert_true(item.is_airborne())
	await wait_physics_frames(24)
	assert_almost_eq(item.height, 0.0, 0.0001, "the shadow returns to the ground")
	assert_false(item.is_airborne())


func test_follow_through_carries_capped_player_velocity() -> void:
	var item: LaundryItem = await _add_item(&"rocky", Vector2(200.0, 400.0))
	item.begin_hold(_holder)
	assert_true(
		item.throw_with_impulse(
			Vector2.RIGHT, RhythmEvaluator.Grade.GOOD, Vector2(800.0, 0.0)
		)
	)
	await wait_physics_frames(1)
	assert_gt(item.linear_velocity.x, Config.THROW_SPEED, "carrier velocity is added")
	assert_lte(
		item.linear_velocity.x,
		Config.THROW_SPEED + LaundryItem.FOLLOW_THROUGH_MAX + 1.0,
		"follow-through is capped"
	)


func test_throw_is_independent_of_hold_spring_speed() -> void:
	var item: LaundryItem = await _add_item(&"rocky", Vector2(200.0, 400.0))
	item.begin_hold(_holder)
	item.linear_velocity = Vector2(1000.0, 0.0)
	assert_true(item.throw_with_impulse(Vector2.RIGHT, RhythmEvaluator.Grade.GOOD))
	await wait_physics_frames(1)
	assert_almost_eq(
		item.linear_velocity.length(), Config.THROW_SPEED, 45.0,
		"the launch speed does not depend on the hold spring"
	)


func test_good_throw_shows_the_dotted_guide() -> void:
	var washer := Node2D.new()
	washer.add_to_group(Config.GROUP_WASHERS)
	add_child_autofree(washer)
	washer.global_position = Vector2(500.0, 300.0)
	var item: LaundryItem = await _add_item(&"rocky", Vector2(200.0, 300.0))
	item.begin_hold(_holder)
	item.throw_with_impulse(Vector2.RIGHT, RhythmEvaluator.Grade.GOOD)
	assert_true(item.visual.is_guide_visible(), "a non-MISS throw teaches the assist target")


func test_miss_throw_never_shows_the_guide() -> void:
	var washer := Node2D.new()
	washer.add_to_group(Config.GROUP_WASHERS)
	add_child_autofree(washer)
	washer.global_position = Vector2(500.0, 300.0)
	var item: LaundryItem = await _add_item(&"rocky", Vector2(200.0, 300.0))
	item.begin_hold(_holder)
	item.throw_with_impulse(Vector2.RIGHT, RhythmEvaluator.Grade.MISS)
	assert_false(item.visual.is_guide_visible(), "MISS throws never show the guide")


func test_item_state_never_becomes_nan() -> void:
	var item: LaundryItem = await _add_item(&"moon", Vector2(200.0, 300.0))
	item.begin_hold(_holder)
	item.throw_with_impulse(Vector2.RIGHT, RhythmEvaluator.Grade.MISS)
	await wait_physics_frames(30)
	assert_false(is_nan(item.global_position.x))
	assert_false(is_nan(item.global_position.y))
	assert_false(is_nan(item.linear_velocity.x))
	assert_false(is_nan(item.linear_velocity.y))
	assert_false(is_nan(item.rotation))
	assert_false(is_nan(item.height))

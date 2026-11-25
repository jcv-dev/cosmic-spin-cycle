extends GutTest
## ConveyorBelt behaviour (GDD §5.3, CONTRACTS §4).
##
## The belt steers velocity toward `flow * belt_speed * item.belt_speed_scale` at
## `BELT_ACCEL` per second and never assigns it, so collisions survive. Reversal is phase 3
## only and is delegated to the pure BeltReversal schedule.

const SCENE_PATH := "res://scenes/environment/ConveyorBelt.tscn"
const TICK := 1.0 / 60.0

var belt: ConveyorBelt


class StubData:
	extends RefCounted
	var belt_speed_scale := 1.0


class StubItem:
	extends RigidBody2D
	var item_id: StringName = &"rocky"
	var data: RefCounted = null
	var is_held := false


func before_each() -> void:
	belt = load(SCENE_PATH).instantiate() as ConveyorBelt
	assert_not_null(belt, "ConveyorBelt.tscn must exist")
	add_child_autofree(belt)


func _make_item(p_item_id: StringName = &"rocky") -> StubItem:
	var item := StubItem.new()
	item.item_id = p_item_id
	add_child_autofree(item)
	return item


# --- steering ---------------------------------------------------------------


func test_steering_is_gradual_not_instant() -> void:
	var item := _make_item()
	item.linear_velocity = Vector2.ZERO
	assert_true(belt.apply_to_body(item, TICK))
	var expected := Config.BELT_ACCEL * TICK
	assert_almost_eq(item.linear_velocity.x, expected, 0.01, "one tick of acceleration")
	assert_almost_eq(item.linear_velocity.y, 0.0, 0.001)
	assert_true(item.linear_velocity.length() < Config.BELT_SPEED, "never snaps to belt speed")


func test_steering_converges_to_the_target_without_overshoot() -> void:
	var item := _make_item()
	item.linear_velocity = Vector2.ZERO
	var target := Vector2(Config.BELT_SPEED, 0.0)
	for _tick: int in range(60):
		belt.apply_to_body(item, TICK)
		assert_true(item.linear_velocity.length() <= target.length() + 0.01, "no overshoot")
	assert_almost_eq(item.linear_velocity.x, Config.BELT_SPEED, 0.01)
	assert_almost_eq(item.linear_velocity.y, 0.0, 0.001)


func test_reversed_flow_pushes_the_other_way() -> void:
	var item := _make_item()
	item.linear_velocity = Vector2(Config.BELT_SPEED, 0.0)
	belt.set_flow_direction(Vector2.LEFT)
	for _tick: int in range(60):
		belt.apply_to_body(item, TICK)
	assert_almost_eq(item.linear_velocity.x, -Config.BELT_SPEED, 0.01)


func test_vertical_flow_targets_the_vertical_axis() -> void:
	var item := _make_item()
	belt.set_flow_direction(Vector2.DOWN)
	item.linear_velocity = Vector2.ZERO
	for _tick: int in range(60):
		belt.apply_to_body(item, TICK)
	assert_almost_eq(item.linear_velocity.x, 0.0, 0.001)
	assert_almost_eq(item.linear_velocity.y, Config.BELT_SPEED, 0.01)


func test_sock_gets_the_fast_belt_multiplier() -> void:
	var sock := _make_item(&"sock")
	assert_almost_eq(belt.speed_scale_for(sock), Config.BELT_SOCK_SPEED_SCALE, 0.001)
	assert_almost_eq(
		belt.target_velocity_for(sock).x, Config.BELT_SPEED * Config.BELT_SOCK_SPEED_SCALE, 0.01
	)


func test_item_data_multiplier_wins_over_the_sock_fallback() -> void:
	var item := _make_item(&"sock")
	var data := StubData.new()
	data.belt_speed_scale = 0.5
	item.data = data
	assert_almost_eq(belt.speed_scale_for(item), 0.5, 0.001)


func test_other_items_use_the_plain_belt_speed() -> void:
	var item := _make_item(&"rocky")
	assert_almost_eq(belt.speed_scale_for(item), 1.0, 0.001)
	assert_almost_eq(belt.speed_scale_for(null), 1.0, 0.001)


func test_inactive_belt_does_not_steer() -> void:
	var item := _make_item()
	item.linear_velocity = Vector2.ZERO
	belt.set_active(false)
	assert_false(belt.is_active())
	assert_false(belt.apply_to_body(item, TICK), "inactive belt ignores bodies")
	assert_eq(item.linear_velocity, Vector2.ZERO, "velocity untouched")
	belt.set_active(true)
	assert_true(belt.apply_to_body(item, TICK), "reactivation resumes steering")


func test_held_item_is_ignored() -> void:
	var item := _make_item()
	item.is_held = true
	item.linear_velocity = Vector2.ZERO
	assert_false(belt.apply_to_body(item, TICK))
	assert_eq(item.linear_velocity, Vector2.ZERO)


func test_non_rigid_body_is_ignored() -> void:
	var plain := Node2D.new()
	add_child_autofree(plain)
	assert_false(belt.apply_to_body(plain, TICK))
	assert_false(belt.apply_to_body(null, TICK))


func test_steer_velocity_is_pure_and_clamped() -> void:
	assert_eq(
		ConveyorBelt.steer_velocity(Vector2.ZERO, Vector2(110.0, 0.0), 15.0), Vector2(15.0, 0.0)
	)
	assert_eq(
		ConveyorBelt.steer_velocity(Vector2.ZERO, Vector2(110.0, 0.0), 1000.0), Vector2(110.0, 0.0)
	)
	assert_eq(ConveyorBelt.steer_velocity(Vector2(5.0, 5.0), Vector2.ZERO, 0.0), Vector2(5.0, 5.0))

extends GutTest
## Shredder contract (GDD §5.3, CONTRACTS §4): an item that leaves a belt costs 8 points of
## stability, bumps the drop counter, tells the item it fell and is freed exactly once.

const SCENE_PATH := "res://scenes/environment/Shredder.tscn"

var shredder: Shredder


class StubItem:
	extends RigidBody2D
	signal fell_off_belt

	var item_id: StringName = &"rocky"


class PlainBody:
	extends RigidBody2D


func before_each() -> void:
	GameState.reset(1234)
	shredder = load(SCENE_PATH).instantiate() as Shredder
	assert_not_null(shredder, "Shredder.tscn must exist")
	add_child_autofree(shredder)


func _make_item() -> StubItem:
	var item := StubItem.new()
	add_child_autofree(item)
	return item


# --- scene contract ---------------------------------------------------------


func test_scene_contract() -> void:
	assert_true(shredder is Area2D, "root is an Area2D")
	assert_eq(shredder.collision_layer, Config.CollisionLayer.SHREDDER, "layer 16")
	assert_eq(shredder.collision_mask, Config.CollisionLayer.ITEMS, "mask 4")
	assert_false(shredder.monitorable, "items never detect the grinder as an area")
	assert_not_null(shredder.get_node_or_null(^"CollisionShape2D"))
	assert_true(shredder.is_in_group(Config.GROUP_SHREDDERS))


func test_configure_positions_it_from_art_pixels() -> void:
	shredder.configure(&"shredder_north", Rect2(236, 6, 32, 32))
	assert_eq(shredder.shredder_id, &"shredder_north")
	assert_almost_eq(shredder.position.x, (236.0 + 16.0) * 4.0, 0.001)
	assert_almost_eq(shredder.position.y, (6.0 + 16.0) * 4.0, 0.001)
	assert_almost_eq(shredder.radius(), 64.0, 0.001, "32 art px across at ×4")
	var shape := shredder.get_node(^"CollisionShape2D") as CollisionShape2D
	assert_almost_eq((shape.shape as CircleShape2D).radius, 64.0, 0.001)


# --- destruction ------------------------------------------------------------


func test_consume_applies_the_stability_penalty() -> void:
	var before := GameState.stability
	var item := _make_item()
	assert_true(shredder.consume(item))
	assert_almost_eq(
		GameState.stability, before + Config.STABILITY_FELL_OFF_BELT, 0.001, "config stability"
	)
	assert_eq(Config.STABILITY_FELL_OFF_BELT, -10.0, "owner: losing an item must hurt (D044)")


func test_consume_bumps_the_drop_counter() -> void:
	var before := GameState.dropped_count
	var item := _make_item()
	shredder.consume(item)
	assert_eq(GameState.dropped_count, before + 1, "GameState accounting")
	assert_eq(shredder.consumed_count, 1, "local accounting for the sandbox HUD")


func test_consume_tells_the_item_it_fell_and_frees_it() -> void:
	var item := _make_item()
	watch_signals(item)
	assert_true(shredder.consume(item))
	assert_signal_emitted(item, "fell_off_belt")
	assert_true(item.is_queued_for_deletion(), "the item is returned to the pool")


func test_double_entry_is_guarded() -> void:
	var item := _make_item()
	assert_true(shredder.consume(item))
	var after_first := GameState.stability
	var drops := GameState.dropped_count
	assert_false(shredder.consume(item), "second entry is rejected")
	assert_almost_eq(GameState.stability, after_first, 0.001, "no second penalty")
	assert_eq(GameState.dropped_count, drops, "no second count")
	assert_eq(shredder.consumed_count, 1)


func test_each_item_pays_once() -> void:
	var first := _make_item()
	var second := _make_item()
	var before := GameState.stability
	shredder.consume(first)
	shredder.consume(second)
	assert_almost_eq(GameState.stability, before + 2.0 * Config.STABILITY_FELL_OFF_BELT, 0.001)
	assert_eq(shredder.consumed_count, 2)


func test_non_items_are_ignored() -> void:
	var plain := PlainBody.new()
	add_child_autofree(plain)
	var before := GameState.stability
	assert_false(shredder.consume(plain), "a rigid body that is not an item is ignored")
	assert_false(shredder.consume(null))
	var plain_node := Node2D.new()
	add_child_autofree(plain_node)
	assert_false(shredder.consume(plain_node))
	assert_almost_eq(GameState.stability, before, 0.001)
	assert_eq(GameState.dropped_count, 0)


func test_stability_never_goes_below_zero() -> void:
	GameState.stability = 2.0
	var item := _make_item()
	shredder.consume(item)
	assert_almost_eq(GameState.stability, 0.0, 0.001, "clamped at zero")
	assert_true(GameState.is_ended, "zero stability ends the shift")


func test_signal_reports_the_consumed_body() -> void:
	var item := _make_item()
	watch_signals(shredder)
	shredder.consume(item)
	assert_signal_emitted_with_parameters(shredder, "item_consumed", [item])

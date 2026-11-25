extends GutTest
## DeliveryChute: clean items pay, dirty items bounce, and nothing pays twice.

const SCENE_PATH := "res://scenes/environment/DeliveryChute.tscn"

var chute: DeliveryChute


class StubItem:
	extends Node2D

	var item_id := &"rocky"
	var is_clean := false
	var points := 120
	var delivered_reported := false

	func report_delivered() -> void:
		delivered_reported = true


func before_each() -> void:
	GameState.reset(1234)
	GameState.stability = 50.0
	chute = load(SCENE_PATH).instantiate() as DeliveryChute
	assert_not_null(chute, "DeliveryChute.tscn must exist")
	add_child_autofree(chute)
	chute.set_process(false)
	chute.configure(Rect2(144, 74, 32, 32), Vector2(160, 90))


func _make_item(clean: bool, points: int = 120) -> StubItem:
	var item := StubItem.new()
	item.is_clean = clean
	item.points = points
	add_child_autofree(item)
	return item


func test_scene_contract() -> void:
	assert_true(chute is Area2D, "root is an Area2D")
	assert_eq(chute.collision_layer, Config.CollisionLayer.CHUTE, "layer 32")
	assert_eq(chute.collision_mask, Config.CollisionLayer.ITEMS, "mask 4")
	assert_false(chute.monitorable, "items never detect the chute as an area")
	assert_true(chute.is_in_group(Config.GROUP_CHUTE))
	assert_not_null(chute.get_node_or_null(^"Visual"), "hatch art")
	assert_not_null(chute.get_node_or_null(^"Beacon"), "procedural beacon")
	assert_not_null(chute.get_node_or_null(^"Audio"), "audio player")
	var shape := chute.get_node(^"CollisionShape2D") as CollisionShape2D
	assert_almost_eq((shape.shape as CircleShape2D).radius, DeliveryChute.HATCH_RADIUS, 0.001)


func test_configure_centres_the_hatch() -> void:
	assert_almost_eq(chute.position.x, 640.0, 0.001)
	assert_almost_eq(chute.position.y, 360.0, 0.001)
	assert_eq(chute.get_center_world(), chute.global_position)
	assert_eq(chute.get_label_text(), "TAPA VERDE", "idle beacon copy")
	assert_eq(chute.get_beacon_color(), Palette.METAL_2)


func test_clean_delivery_pays_points_stability_and_count() -> void:
	var item := _make_item(true)
	watch_signals(chute)
	assert_true(chute.try_deliver(item))
	assert_signal_emitted_with_parameters(chute, "delivered", [item, 120])
	assert_almost_eq(GameState.stability, 53.0, 0.001, "+3 stability")
	assert_eq(GameState.delivered_count, 1)
	assert_eq(GameState.score, 120, "points * x1")
	assert_true(item.delivered_reported, "the item hears it was delivered")
	assert_false(item.is_queued_for_deletion(), "the item shrinks into the iris first")
	var chip := chute.get_node_or_null(^"FeedbackChip")
	assert_not_null(chip, "the +3 stability chip is local to the chute")
	assert_eq(str(chip.get(&"text")), "+3")
	assert_true(bool(chip.get(&"gain")), "gain glyph, not colour alone")
	assert_not_null(chute.get_node_or_null(^"PointsPop"), "the +points label spawns")
	chute.tick(0.3)
	assert_true(item.is_queued_for_deletion(), "then it leaves the room")


func test_combo_multiplies_the_delivery() -> void:
	GameState.combo = 3
	var item := _make_item(true, 100)
	assert_true(chute.try_deliver(item))
	assert_eq(GameState.score, 300, "100 * x3")
	assert_almost_eq(GameState.stability, 53.0, 0.001)


func test_dirty_item_is_bounced_without_a_penalty() -> void:
	var item := _make_item(false)
	watch_signals(chute)
	assert_false(chute.try_deliver(item))
	assert_signal_emitted_with_parameters(chute, "dirty_rejected", [item])
	assert_almost_eq(GameState.stability, 50.0, 0.001, "the chute never punishes")
	assert_eq(GameState.delivered_count, 0)
	assert_eq(GameState.score, 0)
	assert_false(item.is_queued_for_deletion(), "the dirty item stays in play")
	assert_eq(chute.get_label_text(), "LAVA PRIMERO")
	assert_eq(chute.get_beacon_color(), Palette.HAZARD_ORANGE)
	assert_true(chute.is_rejecting())


func test_dirty_label_expires() -> void:
	var item := _make_item(false)
	assert_false(chute.try_deliver(item))
	chute.tick(1.3)
	assert_false(chute.is_rejecting())
	assert_eq(chute.get_label_text(), "TAPA VERDE", "back to idle copy")


func test_double_delivery_is_guarded() -> void:
	var item := _make_item(true)
	assert_true(chute.try_deliver(item))
	var score := GameState.score
	var delivered := GameState.delivered_count
	assert_false(chute.try_deliver(item), "the second call is a no-op")
	assert_eq(GameState.score, score)
	assert_eq(GameState.delivered_count, delivered)


func test_carry_hint_copies() -> void:
	var clean := _make_item(true)
	chute.set_carry_hint(clean)
	assert_eq(chute.get_label_text(), "TIRA AQUÍ")
	assert_eq(chute.get_beacon_color(), Palette.CLEAN_GREEN)
	assert_true(chute.has_clean_hint)
	var dirty := _make_item(false)
	chute.set_carry_hint(dirty)
	assert_eq(chute.get_label_text(), "LAVA PRIMERO")
	assert_eq(chute.get_beacon_color(), Palette.HAZARD_ORANGE)
	assert_true(chute.has_dirty_hint)
	chute.set_carry_hint(null)
	assert_eq(chute.get_label_text(), "TAPA VERDE")
	assert_eq(chute.get_beacon_color(), Palette.METAL_2)


func test_non_items_are_ignored() -> void:
	var plain := Node2D.new()
	add_child_autofree(plain)
	assert_false(chute.try_deliver(plain))
	assert_false(chute.try_deliver(null))
	assert_eq(GameState.delivered_count, 0)
	assert_almost_eq(GameState.stability, 50.0, 0.001)


func test_a_free_item_still_adds_stability() -> void:
	var item := _make_item(true, 0)
	assert_true(chute.try_deliver(item))
	assert_eq(GameState.score, 0, "zero points pay zero")
	assert_almost_eq(GameState.stability, 53.0, 0.001, "delivery is still worth +3")

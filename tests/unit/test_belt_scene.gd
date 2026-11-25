extends GutTest
## ConveyorBelt scene contract and placement (CONTRACTS §4, `data/layout.json`).
##
## The scene must be an Area2D on the belt layer that only senses items, and `configure()`
## must place it from the frozen art-pixel layout.

const SCENE_PATH := "res://scenes/environment/ConveyorBelt.tscn"

var belt: ConveyorBelt


func before_each() -> void:
	belt = load(SCENE_PATH).instantiate() as ConveyorBelt
	assert_not_null(belt, "ConveyorBelt.tscn must exist")
	add_child_autofree(belt)


# --- scene contract ---------------------------------------------------------


func test_scene_contract() -> void:
	assert_true(belt is Area2D, "root is an Area2D")
	assert_eq(belt.collision_layer, Config.CollisionLayer.BELT, "layer 8")
	assert_eq(belt.collision_mask, Config.CollisionLayer.ITEMS, "mask 4")
	assert_false(belt.monitorable, "items never detect the belt as an area")
	assert_not_null(belt.get_node_or_null(^"CollisionShape2D"), "has a collision shape")
	assert_true(belt.is_in_group(Config.GROUP_BELTS), "joins the belts group")


func test_scene_defaults_match_north_belt() -> void:
	assert_almost_eq(belt.belt_speed, Config.BELT_SPEED, 0.001)
	assert_eq(belt.flow_direction, Vector2.RIGHT)
	assert_true(belt.is_active(), "belts start running")


func test_configure_positions_the_belt_from_art_pixels() -> void:
	belt.configure(&"belt_north", Rect2(84, 10, 152, 16), Vector2.RIGHT)
	assert_eq(belt.belt_id, &"belt_north")
	assert_almost_eq(belt.position.x, 640.0, 0.001, "centre x = (84 + 152/2) * 4")
	assert_almost_eq(belt.position.y, 72.0, 0.001, "centre y = (10 + 16/2) * 4")
	assert_almost_eq(belt.world_size().x, 608.0, 0.001)
	assert_almost_eq(belt.world_size().y, 64.0, 0.001)
	var shape := belt.get_node(^"CollisionShape2D") as CollisionShape2D
	var rect := shape.shape as RectangleShape2D
	assert_almost_eq(rect.size.x, 608.0, 0.001)
	assert_almost_eq(rect.size.y, 64.0, 0.001)


# --- direction --------------------------------------------------------------


func test_zero_direction_is_rejected() -> void:
	belt.set_flow_direction(Vector2.ZERO)
	assert_eq(belt.flow_direction, Vector2.RIGHT, "a zero vector never stops the belt")


func test_flow_is_snapped_to_an_axis() -> void:
	belt.set_flow_direction(Vector2(0.8, -0.3))
	assert_eq(belt.flow_direction, Vector2.RIGHT, "dominant axis wins")
	belt.set_flow_direction(Vector2(-0.2, 0.9))
	assert_eq(belt.flow_direction, Vector2.DOWN)

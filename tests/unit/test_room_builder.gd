extends GutTest
## Static room shell from data/layout.json.


func _make_root() -> Node2D:
	var root := Node2D.new()
	add_child_autofree(root)
	return root


func test_layout_math() -> void:
	assert_almost_eq(RoomBuilder.art_to_world(10.0), 40.0, 0.001)
	var rect := RoomBuilder.rect_world({"x": 84, "y": 10, "w": 152, "h": 16})
	assert_eq(rect, Rect2(336, 40, 608, 64))
	assert_eq(RoomBuilder.player_spawn(), Vector2(640, 512))
	assert_eq(RoomBuilder.room_rect(), Rect2(0, 0, 1280, 720))


func test_builds_background_floor_and_four_walls() -> void:
	var root := _make_root()
	var nodes := RoomBuilder.build(root)
	assert_not_null(root.get_node_or_null("RoomBackground"))
	assert_not_null(root.get_node_or_null("Floor"))
	assert_not_null(nodes.walls)
	var walls: StaticBody2D = nodes.walls
	assert_eq(walls.get_child_count(), 4)
	assert_eq(walls.collision_layer, Config.CollisionLayer.WORLD)
	var total_area := 0.0
	for child in walls.get_children():
		var shape := child as CollisionShape2D
		var box := shape.shape as RectangleShape2D
		total_area += box.size.x * box.size.y
	assert_true(total_area > 0.0)


func test_wall_colliders_surround_room() -> void:
	var root := _make_root()
	var walls: StaticBody2D = RoomBuilder.build(root).walls
	var centers: Array[Vector2] = []
	for child in walls.get_children():
		centers.append((child as CollisionShape2D).position)
	assert_true(centers.has(Vector2(640, 16)), "top wall")
	assert_true(centers.has(Vector2(640, 704)), "bottom wall")
	assert_true(centers.has(Vector2(16, 360)), "left wall")
	assert_true(centers.has(Vector2(1264, 360)), "right wall")


func test_layout_rect_lookup() -> void:
	var north := RoomBuilder.layout_rect("belt_north")
	assert_eq(north, Rect2(336, 40, 608, 64))
	var chute := RoomBuilder.layout_rect("chute")
	assert_eq(chute, Rect2(576, 296, 128, 128))
	assert_eq(RoomBuilder.layout_rect("nope"), Rect2())

extends GutTest
## M2 acceptance: 20 items survive 3 s of physics inside a walled room with no tunnelling,
## no NaN, no absurd velocities and no bodies stuck in geometry; 40 bodies stay cheap.

const ROOM_SIZE := Vector2(1280.0, 720.0)
const WALL_THICKNESS := 32.0
const INNER_RECT := Rect2(
	WALL_THICKNESS,
	WALL_THICKNESS,
	ROOM_SIZE.x - WALL_THICKNESS * 2.0,
	ROOM_SIZE.y - WALL_THICKNESS * 2.0
)


func before_each() -> void:
	GameState.reset(4242)
	BeatConductor.stop()
	BeatConductor.start(120)


func after_each() -> void:
	BeatConductor.stop()


func _add_room() -> StaticBody2D:
	var room := StaticBody2D.new()
	room.collision_layer = Config.CollisionLayer.WORLD
	room.collision_mask = 0
	add_child_autofree(room)
	_add_wall(room, Rect2(0.0, 0.0, ROOM_SIZE.x, WALL_THICKNESS))
	_add_wall(room, Rect2(0.0, ROOM_SIZE.y - WALL_THICKNESS, ROOM_SIZE.x, WALL_THICKNESS))
	_add_wall(room, Rect2(0.0, 0.0, WALL_THICKNESS, ROOM_SIZE.y))
	_add_wall(room, Rect2(ROOM_SIZE.x - WALL_THICKNESS, 0.0, WALL_THICKNESS, ROOM_SIZE.y))
	return room


func _add_wall(room: StaticBody2D, rect: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	shape.position = rect.get_center()
	room.add_child(shape)


func _spawn_items(count: int, seed_value: int) -> Array[LaundryItem]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var items: Array[LaundryItem] = []
	var columns := 5
	for index in range(count):
		var column := index % columns
		var row := index / columns
		var item := (load(Config.SCENE_LAUNDRY_ITEM) as PackedScene).instantiate() as LaundryItem
		var item_id: StringName = Config.ITEM_IDS[index % Config.ITEM_IDS.size()]
		item.setup(
			item_id,
			Config.COLORS[index % Config.COLORS.size()],
			Config.PATTERNS[index % Config.PATTERNS.size()],
			false
		)
		add_child_autofree(item)
		item.global_position = Vector2(200.0 + column * 180.0, 150.0 + row * 120.0)
		item.linear_velocity = (
			Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(60.0, 420.0)
		)
		items.append(item)
	return items


func test_twenty_items_survive_three_seconds_of_physics() -> void:
	_add_room()
	var items := _spawn_items(20, 4242)
	var start_positions: Array[Vector2] = []
	for item in items:
		start_positions.append(item.global_position)

	await wait_physics_frames(180)

	var moved := 0
	for index in range(items.size()):
		var item := items[index]
		var position_hint := item.global_position
		var speed := item.linear_velocity.length()
		assert_true(
			is_finite(position_hint.x) and is_finite(position_hint.y),
			"%s has a finite position" % item.item_id
		)
		assert_true(
			is_finite(item.linear_velocity.x) and is_finite(item.linear_velocity.y),
			"%s has a finite velocity" % item.item_id
		)
		assert_lt(
			speed,
			Config.MAX_ITEM_SPEED + 100.0,
			"%s speed stays within the safety clamp" % item.item_id
		)
		assert_true(
			INNER_RECT.grow(2.0).has_point(position_hint),
			"%s stays inside the room (no tunnelling)" % item.item_id
		)
		if position_hint.distance_to(start_positions[index]) > 4.0:
			moved += 1
	assert_gte(moved, 10, "most items actually moved under physics")


func test_forty_bodies_stay_within_frame_budget() -> void:
	_add_room()
	var items := _spawn_items(40, 777)
	for item in items:
		item.linear_velocity = Vector2.from_angle(float(items.find(item))) * 120.0

	var start_usec := Time.get_ticks_usec()
	var physics_total := 0.0
	for _tick in range(600):
		await wait_physics_frames(1)
		physics_total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var wall_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0 / 600.0
	var physics_ms := physics_total / 600.0 * 1000.0
	print(
		(
			"PERF_M2 40 bodies / 600 ticks: physics %.3f ms/tick, wall %.3f ms/tick"
			% [physics_ms, wall_ms]
		)
	)
	assert_lt(physics_ms, 8.0, "physics stays well under the 16.7 ms frame budget")
	assert_lt(items[0].linear_velocity.length(), Config.MAX_ITEM_SPEED + 100.0)

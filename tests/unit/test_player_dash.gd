extends GutTest
## Dash: ~120 px of travel, collision safety against walls, and a short cooldown.

const WALL_LAYER := Config.CollisionLayer.WORLD


func before_each() -> void:
	GameState.reset(1234)
	BeatConductor.stop()
	BeatConductor.start(120)


func after_each() -> void:
	BeatConductor.stop()


func _add_player(position_hint: Vector2) -> Player:
	var player := (load(Config.SCENE_PLAYER) as PackedScene).instantiate() as Player
	add_child_autofree(player)
	player.global_position = position_hint
	return player


func _add_wall(rect: Rect2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = WALL_LAYER
	wall.collision_mask = 0
	add_child_autofree(wall)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	wall.add_child(shape)
	wall.global_position = rect.get_center()
	return wall


func test_dash_travels_about_one_hundred_twenty_pixels() -> void:
	var player := _add_player(Vector2(200.0, 400.0))
	assert_true(player.dash(Vector2.RIGHT), "fresh player can dash")
	await wait_physics_frames(14)
	assert_false(player.is_dashing, "dash finished")
	assert_almost_eq(
		player.last_dash_distance,
		Config.DASH_DISTANCE,
		12.0,
		"dash covers DASH_DISTANCE within tolerance"
	)
	assert_gt(player.global_position.x, 300.0, "player actually moved right")


func test_dash_stops_at_a_wall_without_tunnelling() -> void:
	var player := _add_player(Vector2(200.0, 400.0))
	_add_wall(Rect2(260.0, 300.0, 32.0, 200.0))
	assert_true(player.dash(Vector2.RIGHT))
	await wait_physics_frames(14)
	assert_false(player.is_dashing)
	assert_lt(player.last_dash_distance, Config.DASH_DISTANCE, "wall shortened the dash")
	assert_lte(player.global_position.x, 247.0, "player body stopped at the wall face")
	assert_gte(player.global_position.x, 240.0, "player actually reached the wall")


func test_dash_has_a_short_cooldown() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	assert_true(player.dash(Vector2.RIGHT))
	assert_false(player.dash(Vector2.RIGHT), "cannot dash while already dashing")
	await wait_physics_frames(14)
	assert_false(player.is_dash_ready(), "cooldown starts when the dash ends")
	assert_false(player.dash(Vector2.RIGHT), "dash rejected during cooldown")
	await wait_physics_frames(16)
	assert_true(player.is_dash_ready(), "cooldown expired after about 0.25 s")
	assert_true(player.dash(Vector2.LEFT), "dash available again")


func test_dash_keeps_state_consistent_without_input() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	player.dash(Vector2.UP)
	await wait_physics_frames(14)
	assert_false(player.is_dashing)
	assert_lt(
		player.velocity.length(),
		Config.DASH_DISTANCE / Config.DASH_DURATION_S + 0.01,
		"post-dash velocity is clamped to the walk speed"
	)

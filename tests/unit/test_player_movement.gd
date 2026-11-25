extends GutTest
## Player locomotion: 8-way normalisation, top speed, idle friction and aim plumbing.

const MOVEMENT_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]


func before_each() -> void:
	GameState.reset(1234)
	BeatConductor.stop()
	BeatConductor.start(120)


func after_each() -> void:
	BeatConductor.stop()
	for action in MOVEMENT_ACTIONS:
		Input.action_release(action)


func _add_player(position_hint: Vector2) -> Player:
	var player := (load(Config.SCENE_PLAYER) as PackedScene).instantiate() as Player
	add_child_autofree(player)
	player.global_position = position_hint
	return player


func test_eight_directions_are_normalised() -> void:
	var player := _add_player(Vector2(640.0, 360.0))
	Input.action_press(&"move_right")
	Input.action_press(&"move_down")
	await wait_physics_frames(90)
	var speed := player.velocity.length()
	assert_almost_eq(speed, Config.PLAYER_MAX_SPEED, 1.0, "diagonal speed equals max speed")
	var expected := Vector2(1.0, 1.0).normalized()
	assert_gt(player.velocity.normalized().dot(expected), 0.99, "diagonal direction is exact")


func test_top_speed_is_capped() -> void:
	var player := _add_player(Vector2(640.0, 360.0))
	Input.action_press(&"move_right")
	await wait_physics_frames(120)
	assert_lte(player.velocity.length(), Config.PLAYER_MAX_SPEED + 0.01)
	assert_gte(player.velocity.length(), Config.PLAYER_MAX_SPEED - 0.5)


func test_idle_friction_drops_below_two_percent_in_half_a_second() -> void:
	var player := _add_player(Vector2(640.0, 360.0))
	player.velocity = Vector2(Config.PLAYER_MAX_SPEED, 0.0)
	await wait_physics_frames(30)
	assert_lt(
		player.velocity.length(),
		Config.PLAYER_MAX_SPEED * 0.02,
		"0.12 linear friction is ~0.5 s to rest",
	)


func test_aim_override_sets_direction_and_hold_point() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	watch_signals(player)
	player.set_aim_direction(Vector2.RIGHT)
	assert_eq(player.get_aim_direction(), Vector2.RIGHT)
	assert_almost_eq(
		player.get_hold_position().distance_to(player.global_position), Config.HOLD_DISTANCE, 0.001
	)
	assert_eq(player.get_hold_position(), Vector2(448.0, 400.0))
	assert_signal_emitted(player, "aim_changed")
	player.set_aim_direction(Vector2.RIGHT)
	assert_signal_emit_count(player, "aim_changed", 1, "same direction does not re-emit")


func test_player_registers_in_the_player_group() -> void:
	var player := _add_player(Vector2(320.0, 240.0))
	assert_true(player.is_in_group(Config.GROUP_PLAYER))
	assert_eq(player.collision_layer, Config.CollisionLayer.PLAYER)
	assert_eq(player.collision_mask, Config.CollisionLayer.WORLD)

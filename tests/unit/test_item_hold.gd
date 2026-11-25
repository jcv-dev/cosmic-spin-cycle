extends GutTest
## LaundryItem data binding, grab radius boundary, single-item hold and upright visuals.

const INSIDE_RADIUS := 63.9
const OUTSIDE_RADIUS := 64.1


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


func _add_item(item_id: StringName, position_hint: Vector2) -> LaundryItem:
	var item := (load(Config.SCENE_LAUNDRY_ITEM) as PackedScene).instantiate() as LaundryItem
	item.setup(item_id, &"red", &"solid", false)
	add_child_autofree(item)
	item.global_position = position_hint
	return item


func test_setup_applies_item_data() -> void:
	var item := _add_item(&"gas_giant", Vector2(500.0, 500.0))
	assert_not_null(item.data)
	assert_eq(item.data.id, &"gas_giant")
	assert_almost_eq(item.mass, item.data.mass_kg, 0.0001)
	assert_almost_eq(item.linear_damp, item.data.linear_damp, 0.0001)
	assert_almost_eq(item.physics_material_override.bounce, item.data.bounce, 0.0001)
	assert_almost_eq(item.physics_material_override.friction, item.data.friction, 0.0001)
	var shape := item.get_node("CollisionShape2D").shape as CircleShape2D
	assert_almost_eq(shape.radius, item.data.radius * float(Config.ART_SCALE), 0.0001)
	assert_true(item.is_in_group(Config.GROUP_ITEMS))


func test_every_item_id_receives_its_own_collision_radius() -> void:
	for item_id in Config.ITEM_IDS:
		var item := _add_item(item_id, Vector2(300.0, 300.0))
		var shape := item.get_node("CollisionShape2D").shape as CircleShape2D
		assert_almost_eq(
			shape.radius,
			item.data.radius * float(Config.ART_SCALE),
			0.0001,
			"radius for %s" % item_id
		)


func test_grab_radius_includes_63_9_and_excludes_64_1() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	var inside := _add_item(&"rocky", Vector2(400.0 + INSIDE_RADIUS, 400.0))
	var found := player.grabber.find_target(player.global_position, Config.GRAB_RADIUS)
	assert_eq(found, inside, "63.9 px is inside GRAB_RADIUS")

	var outside := _add_item(&"rocky", Vector2(400.0 + OUTSIDE_RADIUS, 460.0))
	var probe := player.grabber.find_target(Vector2(400.0, 460.0), Config.GRAB_RADIUS)
	assert_null(probe, "64.1 px from its own origin is outside")
	assert_true(is_instance_valid(outside))
	var nothing := player.grabber.find_target(Vector2(0.0, 0.0), Config.GRAB_RADIUS)
	assert_null(nothing)


func test_only_one_item_can_be_held_at_a_time() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	var first := _add_item(&"rocky", Vector2(430.0, 400.0))
	var second := _add_item(&"sock", Vector2(440.0, 400.0))
	assert_true(player.grabber.grab(first))
	assert_false(player.grabber.grab(second), "second grab is rejected")
	assert_eq(player.grabber.held_item, first)
	assert_true(first.is_held)
	assert_false(second.is_held)
	assert_eq(
		player.grabber.find_target(player.global_position, Config.GRAB_RADIUS),
		second,
		"the free item is still a valid target; only holding is exclusive"
	)


func test_hold_switches_mask_to_world_and_release_restores_items() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	var item := _add_item(&"rocky", Vector2(440.0, 400.0))
	player.grabber.grab(item)
	assert_eq(item.collision_mask, Config.CollisionLayer.WORLD)
	assert_true(item.is_held)
	player.grabber.drop()
	assert_false(item.is_held)
	assert_eq(item.collision_mask, Config.CollisionLayer.WORLD | Config.CollisionLayer.ITEMS)


func test_held_item_settles_at_hold_distance() -> void:
	var player := _add_player(Vector2(400.0, 400.0))
	player.set_aim_direction(Vector2.RIGHT)
	var item := _add_item(&"rocky", Vector2(450.0, 400.0))
	player.grabber.grab(item)
	await wait_physics_frames(60)
	assert_almost_eq(item.global_position.distance_to(player.get_hold_position()), 1.0, 6.0)


func test_visual_never_rotates_with_the_body() -> void:
	var item := _add_item(&"rocky", Vector2(500.0, 400.0))
	item.rotation = 1.2
	await wait_physics_frames(2)
	assert_almost_eq(item.visual.rotation, 0.0, 0.0001, "sprite stays upright")
	assert_almost_eq(item.visual.global_position.distance_to(item.global_position), 0.0, 0.001)


func test_clean_state_reaches_the_visual() -> void:
	var item := _add_item(&"sock", Vector2(500.0, 400.0))
	assert_false(item.is_clean)
	item.mark_clean()
	assert_true(item.is_clean)
	assert_true(item.visual.is_clean())


func test_item_signals_exist_for_belt_and_chute() -> void:
	var item := _add_item(&"moon", Vector2(500.0, 400.0))
	watch_signals(item)
	item.report_fell_off_belt()
	item.report_delivered()
	assert_signal_emit_count(item, "fell_off_belt", 1)
	assert_signal_emit_count(item, "delivered", 1)

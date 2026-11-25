extends GutTest
## Per-item GDD §6 physics: sock slide, moon curve support data, core gravity, bounce.

var _holder: Node2D = null


func before_each() -> void:
	GameState.reset(1234)
	BeatConductor.stop()
	BeatConductor.start(120)
	_holder = Node2D.new()
	add_child_autofree(_holder)
	_holder.global_position = Vector2(900.0, 400.0)


func after_each() -> void:
	BeatConductor.stop()


func _add_item(item_id: StringName, position_hint: Vector2) -> LaundryItem:
	var item := (load(Config.SCENE_LAUNDRY_ITEM) as PackedScene).instantiate() as LaundryItem
	item.setup(item_id, &"red", &"solid", false)
	add_child_autofree(item)
	item.global_position = position_hint
	# Let the physics server pick up the item's mass before applying impulses/forces.
	await wait_physics_frames(2)
	return item


func test_bounce_matches_each_item_data() -> void:
	var rocky: LaundryItem = await _add_item(&"rocky", Vector2(400.0, 400.0))
	var gas: LaundryItem = await _add_item(&"gas_giant", Vector2(500.0, 400.0))
	assert_almost_eq(rocky.physics_material_override.bounce, 0.4, 0.0001)
	assert_almost_eq(gas.physics_material_override.bounce, 0.85, 0.0001)
	assert_gt(gas.physics_material_override.bounce, rocky.physics_material_override.bounce)


func test_sock_slides_after_being_dropped_unthrown() -> void:
	var sock: LaundryItem = await _add_item(&"sock", Vector2(500.0, 400.0))
	sock.begin_hold(_holder)
	await wait_physics_frames(2)
	sock.end_hold()
	await wait_physics_frames(30)
	assert_gt(sock.linear_velocity.length(), 50.0, "sock slides after SOCK_SLIDE_DELAY_S")


func test_thrown_sock_does_not_slide() -> void:
	var sock: LaundryItem = await _add_item(&"sock", Vector2(500.0, 400.0))
	sock.begin_hold(_holder)
	assert_true(sock.throw_with_impulse(Vector2.RIGHT, RhythmEvaluator.Grade.GOOD))
	await wait_physics_frames(40)
	assert_gt(sock.linear_velocity.x, 300.0, "throw direction survives the grace period")
	assert_lt(absf(sock.linear_velocity.y), 20.0, "no random slide after a throw")


func test_rocky_flies_straight() -> void:
	var rocky: LaundryItem = await _add_item(&"rocky", Vector2(300.0, 300.0))
	rocky.begin_hold(_holder)
	assert_true(rocky.throw_with_impulse(Vector2.RIGHT, RhythmEvaluator.Grade.GOOD))
	await wait_physics_frames(30)
	assert_almost_eq(rocky.global_position.y, 300.0, 0.5, "rocky keeps a stable trajectory")
	assert_gt(rocky.linear_velocity.x, 0.0)


func test_carried_core_pulls_nearby_socks() -> void:
	_holder.global_position = Vector2(600.0, 400.0)
	var core: LaundryItem = await _add_item(&"galaxy_core", Vector2(600.0, 400.0))
	var sock: LaundryItem = await _add_item(&"sock", Vector2(700.0, 400.0))
	core.begin_hold(_holder)
	await wait_physics_frames(60)
	assert_lt(sock.global_position.x, 690.0, "sock is attracted toward the carried core")


func test_core_outside_gravity_radius_leaves_socks_alone() -> void:
	_holder.global_position = Vector2(600.0, 400.0)
	var core: LaundryItem = await _add_item(&"galaxy_core", Vector2(600.0, 400.0))
	var sock: LaundryItem = await _add_item(
		&"sock", Vector2(600.0 + Config.CORE_GRAVITY_RADIUS + 30.0, 400.0)
	)
	var start := sock.global_position
	core.begin_hold(_holder)
	await wait_physics_frames(30)
	assert_almost_eq(
		sock.global_position.distance_to(start), 0.0, 2.0, "no pull beyond CORE_GRAVITY_RADIUS"
	)


func test_core_only_attracts_socks() -> void:
	_holder.global_position = Vector2(600.0, 400.0)
	var core: LaundryItem = await _add_item(&"galaxy_core", Vector2(600.0, 400.0))
	var rocky: LaundryItem = await _add_item(&"rocky", Vector2(700.0, 400.0))
	var start := rocky.global_position
	core.begin_hold(_holder)
	await wait_physics_frames(30)
	assert_almost_eq(
		rocky.global_position.distance_to(start), 0.0, 2.0, "rocky planets are not attracted"
	)


func test_uncarried_core_does_not_pull() -> void:
	_holder.global_position = Vector2(600.0, 400.0)
	var core: LaundryItem = await _add_item(&"galaxy_core", Vector2(600.0, 400.0))
	var sock: LaundryItem = await _add_item(&"sock", Vector2(700.0, 400.0))
	var start := sock.global_position
	await wait_physics_frames(30)
	assert_almost_eq(
		sock.global_position.distance_to(start),
		0.0,
		2.0,
		"the field only runs while the core is carried"
	)
	assert_false(core.is_held)

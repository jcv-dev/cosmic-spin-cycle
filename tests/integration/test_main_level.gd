extends GutTest
## Level assembly smoke: MainLevel must boot with the static room and UI even before the
## optional M2/M3 scenes land, and expose the shift spine.


func after_each() -> void:
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)


func _spawn_level() -> Node2D:
	var packed := load("res://scenes/main/MainLevel.tscn") as PackedScene
	var level := packed.instantiate() as Node2D
	add_child_autofree(level)
	return level


func test_level_assembles_core_layers() -> void:
	var level := _spawn_level()
	assert_not_null(level.get_node_or_null("Camera2D"))
	assert_not_null(level.get_node_or_null("RoomBackground"))
	assert_not_null(level.get_node_or_null("Floor"))
	assert_not_null(level.get_node_or_null("Walls"))
	assert_not_null(level.get_node_or_null("Environment"))
	assert_not_null(level.get_node_or_null("Items"))
	assert_not_null(level.get_node_or_null("Entities"))
	assert_not_null(level.get_node_or_null("UI"))
	assert_not_null(level.get_node_or_null("UI/HUD"))
	BeatConductor.stop()


func test_seed_is_recorded_and_phase_starts() -> void:
	var level := _spawn_level()
	assert_true(level.get_seed() > 0)
	assert_eq(level.get_phase_index(), 0)
	assert_true(BeatConductor.is_playing)
	BeatConductor.stop()


func test_clock_reaches_phase_two() -> void:
	var level := _spawn_level()
	level.shift_time = 120.1
	level._process(0.0)
	assert_eq(level.get_phase_index(), 1)
	BeatConductor.stop()


func test_environment_belts_and_shredders_from_layout() -> void:
	var level := _spawn_level()
	var env := level.get_node("Environment")
	var belts: Array[Node] = []
	var shredders: Array[Node] = []
	for child in env.get_children():
		if child is ConveyorBelt:
			belts.append(child)
		elif child is Shredder:
			shredders.append(child)
	assert_eq(belts.size(), 3, "north, south and west belts")
	assert_eq(shredders.size(), 3, "one shredder at each belt end")
	var west := env.get_node("BeltWest") as ConveyorBelt
	assert_eq(west.position, Vector2(72, 400), "west belt centred from layout")
	assert_eq(west.world_size(), Vector2(64, 320))
	assert_eq(west.flow_direction, Vector2.UP)
	BeatConductor.stop()


func test_spawner_emits_an_item_on_the_first_interval() -> void:
	var level := _spawn_level()
	level.shift_time = 9.9
	level._process(0.2)
	var spawner := level.get_node_or_null("SpawnDirector")
	assert_not_null(spawner)
	assert_gt(level.get_node("Items").get_child_count(), 0, "first item at 10 s (retuned cadence)")
	assert_gt(int(spawner.call("alive_count")), 0)
	spawner.call("stop")
	BeatConductor.stop()


func test_phase_two_activates_the_south_belt() -> void:
	var level := _spawn_level()
	level.shift_time = 120.1
	level._process(0.0)
	var env := level.get_node("Environment")
	var north := env.get_node("BeltNorth") as ConveyorBelt
	var south := env.get_node("BeltSouth") as ConveyorBelt
	var west := env.get_node("BeltWest") as ConveyorBelt
	assert_true(north.is_active())
	assert_true(south.is_active())
	assert_false(west.is_active())
	BeatConductor.stop()


func test_spawned_item_rides_the_north_belt() -> void:
	var level := _spawn_level()
	level.set_shift_time(10.1)
	var items := level.get_node("Items")
	assert_gt(items.get_child_count(), 0, "an item exists at t=10.1")
	var item := items.get_child(0) as Node2D
	var belt := level.get_node("Environment/BeltNorth") as ConveyorBelt
	assert_true(belt.is_active(), "phase 1 activates the north belt")
	var start_x := item.position.x
	await wait_physics_frames(30)
	assert_gt(item.position.x, start_x + 5.0, "belt carries the item east")
	var spawner := level.get_node_or_null("SpawnDirector")
	if spawner != null:
		spawner.call("stop")
	BeatConductor.stop()


func test_warp_skips_past_spawns() -> void:
	var level := _spawn_level()
	level.warp_to(300.0)
	assert_eq(level.get_node("Items").get_child_count(), 0, "history is not replayed")
	assert_eq(level.get_phase_index(), 2)
	var spawner := level.get_node("SpawnDirector")
	assert_almost_eq(float(spawner.get("time")), 300.0, 0.01)
	level._process(4.2)
	assert_eq(level.get_node("Items").get_child_count(), 1, "one interval after the warp")
	spawner.call("stop")
	BeatConductor.stop()


func test_stability_zero_stops_the_shift() -> void:
	var level := _spawn_level()
	var results: Array = []
	level.shift_finished.connect(func(result: Dictionary) -> void: results.append(result))
	assert_false(level.is_ended())
	GameState.add_stability(-500.0, "test")
	assert_true(level.is_ended())
	assert_false(BeatConductor.is_playing)
	assert_eq(results.size(), 1, "the level announces the end exactly once")
	assert_eq(String(results[0].get("reason", "")), "test")
	assert_false(bool(results[0].get("victory", true)))


func test_phase_three_beat_flips_the_north_belt() -> void:
	var level := _spawn_level()
	level.warp_to(270.0)
	var belt := level.get_node("Environment/BeltNorth") as ConveyorBelt
	assert_eq(level.get_phase_index(), 2)
	assert_eq(belt.get_flow_direction(), Vector2.RIGHT)
	var beat_s := 60.0 / float(Config.PHASE_BPM[2])
	BeatConductor.advance_clock(64.0 * beat_s + 0.001)
	assert_eq(BeatConductor.get_measure_index(), 16)
	assert_eq(belt.get_flow_direction(), Vector2.LEFT, "16-measure flip reaches the level")
	var spawner := level.get_node_or_null("SpawnDirector")
	if spawner != null:
		spawner.call("stop")
	BeatConductor.stop()


func test_phase_change_reaches_every_washer() -> void:
	var level := _spawn_level()
	level.warp_to(130.0)
	for washer in level.call("get_washers"):
		if washer.has_method("get_phase"):
			assert_eq(int(washer.call("get_phase")), 1, "washers follow the shift phase")
	BeatConductor.stop()

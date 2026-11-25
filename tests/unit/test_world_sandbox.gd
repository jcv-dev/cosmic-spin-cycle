extends GutTest
## WorldSandbox: the M3 greybox scene must build itself from `data/layout.json` and run a
## shift without M2, because it is the manual acceptance bed for belts and spawns.

const SCENE_PATH := "res://scenes/dev/WorldSandbox.tscn"

var sandbox: WorldSandbox


func before_each() -> void:
	GameState.reset(7)
	sandbox = load(SCENE_PATH).instantiate() as WorldSandbox
	assert_not_null(sandbox, "WorldSandbox.tscn must exist")
	add_child_autofree(sandbox)


# --- construction -----------------------------------------------------------


func test_scene_builds_every_environment_piece() -> void:
	assert_eq(sandbox.belts.size(), 3, "north, south and west belts")
	assert_eq(sandbox.shredders.size(), 3, "one grinder per belt")
	assert_not_null(sandbox.director, "the sandbox owns a spawn director")
	assert_not_null(sandbox.floor_node, "the floor is built from the layout")
	assert_not_null(sandbox.readout, "the debug readout exists")
	assert_not_null(sandbox.floor_node.get_node_or_null(^"Walls"), "items are contained")


func test_belts_match_the_frozen_layout() -> void:
	var north: ConveyorBelt = sandbox.belts["belt_north"]
	assert_eq(north.flow_direction, Vector2.RIGHT)
	assert_almost_eq(north.position.x, 640.0, 0.001)
	assert_almost_eq(north.position.y, 72.0, 0.001)

	var south: ConveyorBelt = sandbox.belts["belt_south"]
	assert_eq(south.flow_direction, Vector2.LEFT)

	var west: ConveyorBelt = sandbox.belts["belt_west"]
	assert_eq(west.flow_direction, Vector2.UP, "the west belt runs south to north")


func test_shredders_sit_at_the_belt_ends() -> void:
	var north: Shredder = sandbox.shredders["shredder_north"]
	assert_almost_eq(north.position.x, 1008.0, 0.001)
	assert_almost_eq(north.position.y, 88.0, 0.001)


func test_phase_one_runs_only_the_north_belt() -> void:
	assert_true((sandbox.belts["belt_north"] as ConveyorBelt).is_active())
	assert_false((sandbox.belts["belt_south"] as ConveyorBelt).is_active())
	assert_false((sandbox.belts["belt_west"] as ConveyorBelt).is_active())


# --- clock ------------------------------------------------------------------


func test_step_advances_the_shift_clock() -> void:
	sandbox.step(2.0)
	assert_almost_eq(sandbox.shift_time, 2.0, 0.001)
	assert_almost_eq(sandbox.director.time, 2.0, 0.001)
	assert_eq(sandbox.bpm, Config.PHASE_BPM[0])


func test_step_spawns_the_first_item_after_its_interval() -> void:
	sandbox.step(Config.PHASE_SPAWN_INTERVAL_S[0] - 0.5)
	assert_eq(sandbox.director.spawned_count_by_phase[0], 0, "nothing before the interval")
	sandbox.step(1.0)
	assert_eq(sandbox.director.spawned_count_by_phase[0], 1, "the first spawn lands on time")


func test_stub_items_are_tagged_and_layered() -> void:
	sandbox.step(Config.PHASE_SPAWN_INTERVAL_S[0] + 0.5)
	var items := sandbox.director.get_node_or_null(^"Items")
	assert_not_null(items)
	assert_eq(items.get_child_count(), 1)
	var item := items.get_child(0) as RigidBody2D
	assert_not_null(item, "stub items are rigid bodies")
	assert_eq(item.collision_layer, Config.CollisionLayer.ITEMS, "items live on layer 4")
	assert_true(item.has_meta(&"item_id"), "the stub carries the scheduled item id")
	assert_true(item.is_in_group(Config.GROUP_ITEMS))


func test_shift_restarts_at_the_end() -> void:
	sandbox.shift_time = Config.SHIFT_DURATION_S - 0.01
	sandbox.step(0.02)
	assert_true(sandbox.shift_time < 1.0, "the sandbox loops for demo purposes")
	assert_eq(sandbox.director.current_phase, 0, "a restart begins in phase 1")


# --- phase forcing ----------------------------------------------------------


func test_force_phase_jumps_and_activates_belts() -> void:
	sandbox.force_phase(2)
	assert_eq(sandbox.director.current_phase, 2)
	assert_eq(sandbox.bpm, Config.PHASE_BPM[2], "the beat clock follows the phase stem")
	assert_almost_eq(sandbox.shift_time, Config.PHASE_START_S[2], 0.01)
	assert_true((sandbox.belts["belt_west"] as ConveyorBelt).is_active())


func test_force_phase_does_not_replay_skipped_spawns() -> void:
	sandbox.force_phase(3)
	var total := 0
	for count in sandbox.director.spawned_count_by_phase:
		total += count
	assert_eq(total, 0, "a jump does not spawn the phases it skipped")


func test_forcing_phase_three_leaves_the_belts_forward() -> void:
	sandbox.force_phase(2)
	assert_eq((sandbox.belts["belt_north"] as ConveyorBelt).flow_direction, Vector2.RIGHT)
	assert_eq((sandbox.belts["belt_south"] as ConveyorBelt).flow_direction, Vector2.LEFT)
	assert_eq((sandbox.belts["belt_west"] as ConveyorBelt).flow_direction, Vector2.UP)


# --- readout ----------------------------------------------------------------


func test_readout_shows_clock_phase_and_hint() -> void:
	var text := sandbox.readout_text()
	assert_string_contains(text, Config.clock_string(0.0), "the clock is visible")
	assert_string_contains(text, "phase 1/4")
	assert_string_contains(text, "[1-4] force phase")
	assert_string_contains(text, str(sandbox.seed_value), "the seed is visible")


func test_readout_updates_after_stepping() -> void:
	var mid_phase_three := (Config.PHASE_START_S[2] + Config.PHASE_START_S[3]) * 0.5
	sandbox.step(mid_phase_three)
	var text := sandbox.readout_text()
	assert_string_contains(text, Config.clock_string(mid_phase_three), "the clock advanced")
	assert_string_contains(text, "phase 3/4", "the middle of 270-420 s is phase 3")

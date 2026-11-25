extends GutTest
## SpawnDirector: replays the pure schedule against game time (CONTRACTS §4).
##
## The director must be idempotent, respect `MAX_ALIVE_ITEMS`, activate the belts of the
## current phase and work without M2 by injecting a stub factory.

const SEED := 4242

var director: SpawnDirector
var spawned: Array[Node] = []


func before_each() -> void:
	spawned.clear()
	director = SpawnDirector.new()
	director.name = "SpawnDirector"
	add_child_autofree(director)
	director.stub_factory = _make_stub


func _make_stub(_event: Dictionary) -> Node:
	var item := RigidBody2D.new()
	item.name = "StubItem"
	spawned.append(item)
	return item


func _make_counted_stub(_event: Dictionary) -> Node:
	var item := RigidBody2D.new()
	return item


# --- lifecycle --------------------------------------------------------------


func test_start_builds_the_schedule_and_rewinds() -> void:
	director.start(SEED)
	assert_true(director.is_running)
	assert_gt(director.schedule.size(), 0)
	assert_eq(director.current_phase, 0)
	assert_eq(director.spawned_count_by_phase.size(), 4)


func test_advance_is_idempotent() -> void:
	director.start(SEED)
	director.advance_to(100.0)
	var first := director.spawned_count_by_phase.duplicate()
	director.advance_to(100.0)
	assert_eq(director.spawned_count_by_phase, first, "the same time never double-spawns")
	assert_eq(director.alive_count(), _sum(first))


func test_advancing_backwards_is_ignored() -> void:
	director.start(SEED)
	director.advance_to(200.0)
	var counts := director.spawned_count_by_phase.duplicate()
	director.advance_to(10.0)
	assert_eq(director.spawned_count_by_phase, counts, "time never runs backwards")
	assert_almost_eq(director.time, 200.0, 0.001)


func test_stop_blocks_further_spawns() -> void:
	director.start(SEED)
	director.advance_to(60.0)
	var counts := director.spawned_count_by_phase.duplicate()
	director.stop()
	director.advance_to(480.0)
	assert_eq(director.spawned_count_by_phase, counts, "a stopped director is inert")
	assert_false(director.is_running)


func test_advance_before_start_does_nothing() -> void:
	director.advance_to(480.0)
	assert_eq(director.alive_count(), 0)
	assert_eq(_sum(director.spawned_count_by_phase), 0)


# --- counts -----------------------------------------------------------------


func test_phase_one_spawns_its_interval_only() -> void:
	director.start(SEED)
	director.advance_to(120.0)
	var expected := int(floor(120.0 / Config.PHASE_SPAWN_INTERVAL_S[0]))
	assert_eq(director.spawned_count_by_phase[0], expected)
	assert_eq(director.spawned_count_by_phase[1], 0, "phase 2 has not started")


func test_full_shift_accounts_every_event() -> void:
	# Accounting mode: with a live item scene the cap would swallow the tail.
	director.stub_factory = Callable()
	director.start(SEED)
	director.advance_to(Config.SHIFT_DURATION_S)
	var expected := SpawnSchedule.counts_by_phase(director.schedule, 4)
	assert_eq(director.spawned_count_by_phase, expected, "every event becomes an item")
	assert_almost_eq(float(_sum(expected)), 197.0, 2.0)


func test_nothing_spawns_after_the_shift() -> void:
	director.start(SEED)
	director.advance_to(Config.SHIFT_DURATION_S)
	var final_counts := director.spawned_count_by_phase.duplicate()
	director.advance_to(Config.SHIFT_DURATION_S * 2.0)
	assert_eq(director.spawned_count_by_phase, final_counts, "the schedule ends at 480 s")


# --- cap and signals --------------------------------------------------------


func test_alive_cap_is_respected() -> void:
	director.stub_factory = _make_counted_stub
	director.start(SEED)
	director.advance_to(300.0)
	assert_true(director.alive_count() <= Config.MAX_ALIVE_ITEMS, "cap holds")
	assert_eq(director.alive_count(), Config.MAX_ALIVE_ITEMS, "the cap is actually reached")
	assert_gt(director.skipped_count, 0, "overflow events are reported, not queued")


func test_item_spawned_signal_carries_the_item() -> void:
	director.start(SEED)
	watch_signals(director)
	director.advance_to(10.0)
	assert_signal_emitted(director, "item_spawned")
	assert_gt(spawned.size(), 0)
	var item := spawned[0]
	assert_true(item.is_in_group(Config.GROUP_ITEMS), "spawned items join the items group")
	assert_eq(item.get_meta(&"item_id"), StringName(director.schedule[0].item_id))


func test_items_parent_is_created_under_the_director() -> void:
	director.start(SEED)
	director.advance_to(10.0)
	var parent := director.get_node_or_null(^"Items")
	assert_not_null(parent, "the director owns an Items parent")
	assert_eq(parent.get_child_count(), director.alive_count())


func test_items_parent_path_is_honoured() -> void:
	var custom := Node2D.new()
	custom.name = "CustomItems"
	add_child_autofree(custom)
	director.items_parent_path = ^"../CustomItems"
	director.start(SEED)
	director.advance_to(10.0)
	assert_eq(custom.get_child_count(), director.alive_count())


func test_position_resolver_places_items() -> void:
	director.position_resolver = func(_event: Dictionary, _phase: PhaseData) -> Vector2:
		return Vector2(1000.0, 500.0)
	director.start(SEED)
	director.advance_to(10.0)
	assert_gt(spawned.size(), 0)
	assert_eq((spawned[0] as Node2D).position, Vector2(1000.0, 500.0))


func test_fallback_spawn_position_is_used() -> void:
	director.spawn_position = Vector2(11.0, 22.0)
	director.start(SEED)
	director.advance_to(10.0)
	assert_eq((spawned[0] as Node2D).position, Vector2(11.0, 22.0))


# --- phases and belts -------------------------------------------------------


func test_phase_changes_are_emitted_at_the_boundaries() -> void:
	director.start(SEED)
	watch_signals(director)
	director.advance_to(Config.PHASE_START_S[1] + 0.1)
	assert_signal_emitted_with_parameters(director, "phase_changed", [1])
	director.advance_to(Config.PHASE_START_S[2] + 0.1)
	assert_eq(director.current_phase, 2)


func test_force_phase_jumps_without_moving_the_clock() -> void:
	director.start(SEED)
	director.force_phase(3)
	assert_eq(director.current_phase, 3)
	assert_almost_eq(director.time, 0.0, 0.001)


func test_belts_follow_the_active_phase() -> void:
	var north := _add_belt(&"belt_north")
	var south := _add_belt(&"belt_south")
	var west := _add_belt(&"belt_west")

	director.start(SEED)
	assert_true(north.is_active(), "phase 1 runs the north belt")
	assert_false(south.is_active(), "the south belt wakes in phase 2")
	assert_false(west.is_active(), "the west belt wakes in phase 3")

	director.advance_to(Config.PHASE_START_S[1] + 0.1)
	assert_true(south.is_active(), "phase 2 activates the south belt")
	assert_false(west.is_active())

	director.advance_to(Config.PHASE_START_S[2] + 0.1)
	assert_true(west.is_active(), "phase 3 activates the west belt")


func test_simulate_reports_the_run() -> void:
	var report := director.simulate(Config.SHIFT_DURATION_S, SEED)
	assert_eq(int(report.total), director.schedule.size())
	assert_eq(report.per_phase.size(), 4)
	assert_almost_eq(float(report.last_time), float(report.convoy[12].time), 0.001, "convoy tail")
	assert_true(float(report.last_time) < Config.SHIFT_DURATION_S)
	assert_eq(report.spawned, director.spawned_count_by_phase)


func test_simulate_works_without_any_scene() -> void:
	var headless := SpawnDirector.new()
	headless.stub_factory = Callable()
	var report := headless.simulate(Config.SHIFT_DURATION_S, SEED)
	headless.free()
	assert_eq(int(report.total), 197, "accounting mode counts the whole schedule")
	assert_eq(report.spawned, [34, 62, 88, 13])


# --- helpers ----------------------------------------------------------------


func _add_belt(belt_id: StringName) -> ConveyorBelt:
	var belt := ConveyorBelt.new()
	belt.name = String(belt_id)
	belt.belt_id = belt_id
	add_child_autofree(belt)
	return belt


func _sum(values: Array[int]) -> int:
	var total := 0
	for value in values:
		total += value
	return total

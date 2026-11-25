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
	var expected := int(floor(119.999 / Config.PHASE_SPAWN_INTERVAL_S[0]))
	assert_eq(director.spawned_count_by_phase[0], expected)
	assert_eq(director.spawned_count_by_phase[1], 0, "phase 2 has not started")


func test_full_shift_accounts_every_event() -> void:
	# Accounting mode: no item scene and no stub, so every event is only counted.
	director.item_scene = null
	director.stub_factory = Callable()
	director.start(SEED)
	director.advance_to(Config.SHIFT_DURATION_S)
	var expected := SpawnSchedule.counts_by_phase(director.schedule, 4)
	assert_eq(director.spawned_count_by_phase, expected, "every event becomes an item")
	assert_almost_eq(float(_sum(expected)), 83.0, 2.0)


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
	director.advance_to(480.0)
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


func test_seek_skips_without_spawning() -> void:
	director.start(SEED)
	director.seek(200.0)
	assert_eq(_sum(director.spawned_count_by_phase), 0, "skipped phases are not replayed")
	assert_almost_eq(director.time, 200.0, 0.001)
	assert_eq(director.current_phase, 1, "seeking lands in the right phase")
	director.advance_to(215.0)
	assert_gt(_sum(director.spawned_count_by_phase), 0, "the clock continues from there")


func _sum(values: Array[int]) -> int:
	var total := 0
	for value in values:
		total += value
	return total

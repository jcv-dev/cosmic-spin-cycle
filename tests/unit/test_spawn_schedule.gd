extends GutTest
## SpawnSchedule purity, determinism and bounds (GDD §2.5, AGENTS M3).
##
## The schedule is the headless heart of M3: one seed in, one sorted list of spawn events
## out, no scene involved. A 480 s run must never spawn at or after 480 s.

const SEED := 1234
const PHASE_COUNT := 4

var table: PhaseTable
var events: Array[Dictionary]


func before_each() -> void:
	table = PhaseTable.load_default()
	events = SpawnSchedule.build(table, SEED)


func _key(event: Dictionary) -> String:
	return (
		"%.3f|%s|%s|%s|%d"
		% [
			float(event.time),
			String(event.item_id),
			String(event.color),
			String(event.pattern),
			int(event.phase),
		]
	)


# --- shape ------------------------------------------------------------------


func test_build_returns_events() -> void:
	assert_not_null(table, "phase table must load")
	assert_gt(events.size(), 0, "a shift spawns something")


func test_event_shape_matches_the_contract() -> void:
	for event in events:
		assert_has(event, "time", "time field")
		assert_has(event, "item_id", "item_id field")
		assert_has(event, "color", "color field")
		assert_has(event, "pattern", "pattern field")
		assert_has(event, "phase", "phase field")
		assert_true(event.time is float or event.time is int, "time is numeric")
		assert_true(event.item_id is StringName, "item_id is a StringName")
		assert_true(event.color is StringName, "color is a StringName")
		assert_true(event.pattern is StringName, "pattern is a StringName")
		assert_true(event.phase is int, "phase is an int")


func test_every_item_id_is_a_known_item() -> void:
	for event in events:
		assert_true(Config.ITEM_IDS.has(event.item_id), "unknown item %s" % event.item_id)


# --- determinism ------------------------------------------------------------


func test_same_seed_rebuilds_the_identical_list() -> void:
	var again := SpawnSchedule.build(table, SEED)
	assert_eq(again.size(), events.size(), "same length")
	for index in range(mini(again.size(), events.size())):
		assert_eq(_key(again[index]), _key(events[index]), "event %d differs" % index)


func test_different_seed_changes_the_picks() -> void:
	var other := SpawnSchedule.build(table, SEED + 1)
	assert_eq(other.size(), events.size(), "counts stay deterministic")
	var differences := 0
	for index in range(mini(other.size(), events.size())):
		if _key(other[index]) != _key(events[index]):
			differences += 1
	assert_gt(differences, 0, "a different seed must change the variant/item stream")


func test_build_does_not_touch_the_global_rng() -> void:
	GameState.reset(SEED)
	var before := GameState.rng.seed
	SpawnSchedule.build(table, SEED)
	assert_eq(GameState.rng.seed, before, "the schedule owns a private RNG")


# --- ordering and bounds ----------------------------------------------------


func test_events_are_sorted_by_time() -> void:
	var previous := -1.0
	for event in events:
		assert_true(float(event.time) >= previous, "event at %.3f is out of order" % event.time)
		previous = float(event.time)


func test_nothing_spawns_at_or_after_the_shift_end() -> void:
	for event in events:
		assert_true(float(event.time) >= 0.0, "negative spawn time")
		assert_true(
			float(event.time) < Config.SHIFT_DURATION_S,
			"spawn at %.3f s would miss the shift" % event.time
		)


func test_events_stay_inside_their_phase_window() -> void:
	for event in events:
		var phase := table.phase(int(event.phase))
		assert_not_null(phase, "phase %d exists" % event.phase)
		if phase == null:
			continue
		assert_true(
			float(event.time) >= phase.start_s and float(event.time) < phase.end_s,
			"event at %.3f s is outside phase %d" % [event.time, event.phase]
		)


# --- counts -----------------------------------------------------------------


func test_per_phase_counts_follow_the_intervals() -> void:
	var counts := SpawnSchedule.counts_by_phase(events, PHASE_COUNT)
	assert_eq(counts.size(), PHASE_COUNT)
	for index in range(3):
		# Slots start one interval after the phase opens, so the last slot is excluded.
		var expected := int(
			floor((table.phase(index).duration_s() - 0.001) / table.phase(index).spawn_interval_s)
		)
		assert_eq(counts[index], expected, "phase %d count" % index)
	var convoy_expected := Config.FINAL_LOAD_HEAVY_COUNT + Config.FINAL_LOAD_CORE_COUNT
	assert_eq(counts[3], convoy_expected, "phase 4 is the convoy")


func test_total_is_the_sum_of_the_phases() -> void:
	var counts := SpawnSchedule.counts_by_phase(events, PHASE_COUNT)
	var total := 0
	for count in counts:
		total += count
	assert_eq(events.size(), total)
	assert_almost_eq(float(events.size()), 98.0, 2.0, "retuned cadence: 98 +/- 2 spawns")


func test_counts_pad_to_the_requested_width() -> void:
	var wide := SpawnSchedule.counts_by_phase(events, PHASE_COUNT + 2)
	assert_eq(wide.size(), PHASE_COUNT + 2)
	assert_eq(wide[PHASE_COUNT], 0)


func test_empty_and_null_tables_build_nothing() -> void:
	var none: Array[Dictionary] = SpawnSchedule.build(null, SEED)
	assert_eq(none.size(), 0)
	var empty := PhaseTable.new()
	var empty_events: Array[Dictionary] = SpawnSchedule.build(empty, SEED)
	assert_eq(empty_events.size(), 0)

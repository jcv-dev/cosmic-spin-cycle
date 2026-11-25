extends GutTest
## The shipped phase table must match GDD §2.5 and `docs/CONTRACTS.md` §4/§5.
##
## These tests are the guard rail for "no magic numbers outside data": they compare the
## authored `data/phases.tres` against `Config` instead of restating the numbers.

const EPS := 0.001

var table: PhaseTable


func before_each() -> void:
	table = PhaseTable.load_default()


func test_default_table_loads_four_phases() -> void:
	assert_not_null(table, "data/phases.tres must load as a PhaseTable")
	if table == null:
		return
	assert_eq(table.size(), 4, "the shift is four continuous phases (GDD §2.5)")


func test_shipped_table_is_valid() -> void:
	if table == null:
		fail_test("phase table missing")
		return
	var problems := table.validate()
	assert_eq(problems.size(), 0, "validator problems: %s" % str(problems))


func test_windows_are_contiguous_and_cover_the_shift() -> void:
	if table == null:
		fail_test("phase table missing")
		return
	assert_almost_eq(table.phase(0).start_s, 0.0, EPS)
	for i in range(table.size()):
		var entry := table.phase(i)
		assert_eq(entry.index, i, "entry %d declares its own index" % i)
		assert_almost_eq(entry.start_s, Config.PHASE_START_S[i], EPS, "phase %d start" % i)
		assert_true(entry.end_s > entry.start_s, "phase %d has a positive window" % i)
		if i > 0:
			assert_almost_eq(
				entry.start_s, table.phase(i - 1).end_s, EPS, "no gap before phase %d" % i
			)
	assert_almost_eq(
		table.phase(table.size() - 1).end_s, Config.SHIFT_DURATION_S, EPS, "shift duration"
	)
	assert_almost_eq(table.total_duration_s(), Config.SHIFT_DURATION_S, EPS)


func test_bpm_matches_config() -> void:
	if table == null:
		fail_test("phase table missing")
		return
	for i in range(table.size()):
		assert_eq(table.phase(i).bpm, Config.PHASE_BPM[i], "phase %d tempo" % i)


func test_spawn_interval_matches_config() -> void:
	if table == null:
		fail_test("phase table missing")
		return
	for i in range(table.size()):
		var entry := table.phase(i)
		assert_almost_eq(
			entry.spawn_interval_s, Config.PHASE_SPAWN_INTERVAL_S[i], EPS, "phase %d interval" % i
		)
	assert_true(table.phase(3).convoy, "phase 4 is the scripted convoy, not a timed interval")


func test_phase_lookup_boundaries() -> void:
	if table == null:
		fail_test("phase table missing")
		return
	assert_eq(table.phase_index_at(0.0), 0)
	assert_eq(table.phase_index_at(119.999), 0, "end is exclusive")
	assert_eq(table.phase_index_at(120.0), 1)
	assert_eq(table.phase_index_at(269.999), 1)
	assert_eq(table.phase_index_at(270.0), 2)
	assert_eq(table.phase_index_at(419.999), 2)
	assert_eq(table.phase_index_at(420.0), 3)
	assert_eq(table.phase_index_at(479.999), 3)
	assert_eq(table.phase_index_at(480.0), 3, "past the shift clamps to the last phase")


func test_phase_lookup_agrees_with_config() -> void:
	if table == null:
		fail_test("phase table missing")
		return
	var t := 0.0
	while t < Config.SHIFT_DURATION_S:
		assert_eq(table.phase_index_at(t), Config.phase_index_at(t), "mismatch at %.2f s" % t)
		t += 0.5


func test_variant_allowance_matches_gdd_progression() -> void:
	if table == null:
		fail_test("phase table missing")
		return
	var opening := table.phase(0)
	var opening_colors: Array[StringName] = [&"red", &"blue"]
	var opening_patterns: Array[StringName] = [&"solid"]
	assert_eq(opening.allowed_colors, opening_colors)
	assert_eq(opening.allowed_patterns, opening_patterns)

	var rush := table.phase(1)
	assert_true(rush.allowed_patterns.has(&"ringed"), "phase 2 introduces ringed items")
	assert_false(rush.allowed_colors.has(&"yellow"), "yellow arrives in phase 3")

	var turbulence := table.phase(2)
	assert_true(turbulence.allowed_colors.has(&"yellow"), "phase 3 introduces yellow")
	assert_true(turbulence.allowed_patterns.has(&"spotted"), "phase 3 introduces spotted")


func test_every_phase_allows_at_least_one_legal_variant() -> void:
	if table == null:
		fail_test("phase table missing")
		return
	for i in range(table.size()):
		var entry := table.phase(i)
		assert_true(entry.allowed_colors.size() > 0, "phase %d colours" % i)
		assert_true(entry.allowed_patterns.size() > 0, "phase %d patterns" % i)
		for color in entry.allowed_colors:
			assert_true(Config.is_known_color(color), "phase %d colour %s" % [i, color])
		for pattern in entry.allowed_patterns:
			assert_true(Config.is_known_pattern(pattern), "phase %d pattern %s" % [i, pattern])


func test_item_weights_only_use_known_items() -> void:
	if table == null:
		fail_test("phase table missing")
		return
	for i in range(table.size()):
		var entry := table.phase(i)
		if entry.convoy:
			continue
		assert_true(entry.total_weight() > 0.0, "phase %d needs a positive weight" % i)
		for item_id in entry.item_weights.keys():
			assert_true(Config.ITEM_IDS.has(StringName(item_id)), "unknown item %s" % item_id)


func test_belt_activation_matches_layout() -> void:
	if table == null:
		fail_test("phase table missing")
		return
	var expected := _expected_belts_by_phase()
	for i in range(expected.size()):
		var at_start := table.phase(i).start_s
		assert_eq(table.active_belts_at(at_start), expected[i], "phase %d belts" % i)
	assert_eq(table.phase(3).active_belts.size(), 3, "the final load runs every belt")


func test_belt_ids_are_unique_and_stable() -> void:
	if table == null:
		fail_test("phase table missing")
		return
	var expected: Array[StringName] = [&"belt_north", &"belt_south", &"belt_west"]
	assert_eq(table.belt_ids(), expected)


# --- helpers ----------------------------------------------------------------


func _expected_belts_by_phase() -> Array:
	var layout := _load_layout()
	var out: Array = [[], [], [], []]
	for belt in layout.belts:
		var belt_id := StringName(belt.id)
		for phase_index in belt.active_phases:
			var bucket: Array = out[int(phase_index)]
			bucket.append(belt_id)
	return out


func _load_layout() -> Dictionary:
	var f := FileAccess.open("res://data/layout.json", FileAccess.READ)
	assert_not_null(f, "layout.json must exist")
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary, "layout.json must be an object")
	return parsed as Dictionary

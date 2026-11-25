extends GutTest
## WasherAssignments: the onboarding ramp, the lock flags and the (documented) coverage gap.


func test_phase_tables_match_the_ramp() -> void:
	var expected := [
		[[&"red", false], [&"blue", false], [&"solid", true], [&"spotted", true]],
		[[&"red", false], [&"blue", false], [&"solid", false], [&"spotted", true]],
		[[&"red", false], [&"blue", false], [&"solid", false], [&"spotted", false]],
		[[&"yellow", false], [&"red", false], [&"solid", false], [&"ringed", false]],
	]
	for phase in range(4):
		var rows := WasherAssignments.table(phase)
		assert_eq(rows.size(), 4, "phase %d has four washers" % phase)
		for index in range(4):
			var row := rows[index]
			assert_eq(
				StringName(str(row["washer_id"])),
				WasherAssignments.WASHER_IDS[index],
				"phase %d row %d id" % [phase, index]
			)
			assert_eq(
				StringName(str(row["requirement"])),
				expected[phase][index][0],
				"phase %d row %d requirement" % [phase, index]
			)
			assert_eq(
				bool(row["locked"]),
				expected[phase][index][1],
				"phase %d row %d locked" % [phase, index]
			)


func test_lookup_helpers() -> void:
	assert_eq(WasherAssignments.requirement_for(0, &"washer_nw"), &"red")
	assert_eq(WasherAssignments.requirement_for(3, &"washer_nw"), &"yellow")
	assert_eq(WasherAssignments.requirement_for(3, &"washer_se"), &"ringed")
	assert_true(WasherAssignments.is_locked(0, &"washer_sw"))
	assert_false(WasherAssignments.is_locked(2, &"washer_sw"))
	assert_true(WasherAssignments.is_locked(1, &"washer_se"))
	assert_false(WasherAssignments.is_locked(3, &"washer_se"))


func test_unknown_washers_are_safe_defaults() -> void:
	assert_eq(WasherAssignments.requirement_for(0, &"washer_nowhere"), &"wild")
	assert_true(WasherAssignments.is_locked(0, &"washer_nowhere"), "unknown is offline")


func test_locked_rows_are_skipped_by_coverage() -> void:
	# P2 keeps the only spotted washer locked, so yellow_spotted has no home yet.
	assert_false(WasherAssignments.has_home(1, &"yellow", &"spotted"))
	assert_true(WasherAssignments.has_home(2, &"yellow", &"spotted"), "P3 unlocks it")


func test_has_home_examples() -> void:
	assert_true(WasherAssignments.has_home(0, &"red", &"solid"), "red washer")
	assert_true(WasherAssignments.has_home(0, &"blue", &"solid"), "blue washer")
	assert_true(WasherAssignments.has_home(1, &"blue", &"ringed"), "blue fits blue")
	assert_true(WasherAssignments.has_home(2, &"yellow", &"solid"), "solid washer")
	assert_true(WasherAssignments.has_home(2, &"yellow", &"spotted"), "spotted washer")
	assert_false(WasherAssignments.has_home(0, &"yellow", &"solid"))
	assert_false(WasherAssignments.has_home(2, &"yellow", &"ringed"), "the documented P3 gap")
	assert_false(WasherAssignments.has_home(3, &"blue", &"spotted"), "the documented P4 gap")


func test_allowed_variants_come_from_the_spawn_table() -> void:
	assert_eq(WasherAssignments.allowed_variants(0).size(), 2, "P1: red/blue solid")
	assert_eq(WasherAssignments.allowed_variants(1).size(), 4, "P2: + ringed")
	assert_eq(WasherAssignments.allowed_variants(2).size(), 9, "P3: all colours/patterns")
	assert_eq(WasherAssignments.allowed_variants(3).size(), 9, "P4 convoy variants")


func test_coverage_is_complete_for_phases_one_and_two() -> void:
	assert_true(WasherAssignments.coverage_ok(0))
	assert_true(WasherAssignments.coverage_ok(1))
	assert_eq(WasherAssignments.uncovered_variants(0), [] as Array[StringName])
	assert_eq(WasherAssignments.uncovered_variants(1), [] as Array[StringName])


## Known data conflict, reported in docs/M4_WASHERS.md: four washers split 2 colours + 2
## patterns can cover at most 8 of the 9 variants. If the frozen phase table (or the ramp)
## is amended, these assertions change with it.
func test_known_coverage_gap_for_phases_three_and_four() -> void:
	assert_false(WasherAssignments.coverage_ok(2))
	assert_eq(
		WasherAssignments.uncovered_variants(2),
		[&"yellow_ringed"] as Array[StringName],
		"P3 leaves yellow_ringed without a home"
	)
	assert_false(WasherAssignments.coverage_ok(3))
	assert_eq(
		WasherAssignments.uncovered_variants(3),
		[&"blue_spotted"] as Array[StringName],
		"P4 leaves blue_spotted without a home"
	)


func test_table_returns_copies() -> void:
	var rows := WasherAssignments.table(0)
	rows[0]["requirement"] = &"yellow"
	assert_eq(WasherAssignments.requirement_for(0, &"washer_nw"), &"red", "no shared state")

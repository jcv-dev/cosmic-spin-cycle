extends GutTest
## Clock/phase mapping from GDD §2.2 and §2.5.


func test_beat_seconds_for_all_phase_bpms() -> void:
	var expected := [0.5714285714, 0.5084745763, 0.4615384615, 0.4225352113]
	for i in range(Config.PHASE_BPM.size()):
		assert_almost_eq(Config.beat_seconds(float(Config.PHASE_BPM[i])), expected[i], 0.000001)


func test_phase_boundaries() -> void:
	assert_eq(Config.phase_index_at(0.0), 0)
	assert_eq(Config.phase_index_at(119.999), 0)
	assert_eq(Config.phase_index_at(120.0), 1)
	assert_eq(Config.phase_index_at(269.999), 1)
	assert_eq(Config.phase_index_at(270.0), 2)
	assert_eq(Config.phase_index_at(419.999), 2)
	assert_eq(Config.phase_index_at(420.0), 3)
	assert_eq(Config.phase_index_at(480.0), 3)


func test_phase_helpers_clamp() -> void:
	assert_eq(Config.phase_bpm(-3), 105)
	assert_eq(Config.phase_bpm(99), 142)
	assert_almost_eq(Config.phase_interval_s(99), 0.0, 0.0001)
	assert_almost_eq(Config.phase_start_s(2), 270.0, 0.0001)


func test_clock_strings_match_phase_table() -> void:
	assert_eq(Config.clock_string(0.0), "00:00")
	assert_eq(Config.clock_string(120.0), "01:30")
	assert_eq(Config.clock_string(270.0), "03:22")
	assert_eq(Config.clock_string(420.0), "05:15")
	assert_eq(Config.clock_string(480.0), "06:00")


func test_clock_clamps_outside_shift() -> void:
	assert_eq(Config.clock_string(-10.0), "00:00")
	assert_eq(Config.clock_string(9999.0), "06:00")


func test_variant_names() -> void:
	assert_eq(Config.variant_name(&"red", &"solid"), &"red_solid")
	assert_eq(Config.variant_name(&"yellow", &"spotted"), &"yellow_spotted")
	assert_true(Config.is_known_color(&"blue"))
	assert_false(Config.is_known_color(&"green"))
	assert_true(Config.is_known_pattern(&"ringed"))
	assert_false(Config.is_known_pattern(&"striped"))

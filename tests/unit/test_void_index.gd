extends GutTest
## VoidIndex (D046): pressure that never becomes a second fail state.


func test_rate_grows_with_the_shift() -> void:
	var difficulty := Config.Difficulty.STANDARD
	for phase in range(Config.VOID_RATE_BY_PHASE.size() - 1):
		assert_lt(
			VoidIndex.rate_per_second(phase, difficulty),
			VoidIndex.rate_per_second(phase + 1, difficulty),
			"phase %d is slower than the next one" % phase
		)


func test_difficulty_scales_the_rate() -> void:
	var calm := VoidIndex.rate_per_second(2, Config.Difficulty.CALM)
	var standard := VoidIndex.rate_per_second(2, Config.Difficulty.STANDARD)
	var chaos := VoidIndex.rate_per_second(2, Config.Difficulty.CHAOS)
	assert_lt(calm, standard)
	assert_lt(standard, chaos)


func test_advance_is_clamped_to_the_meter() -> void:
	var value := VoidIndex.advance(0.0, 1000.0, 3, Config.Difficulty.CHAOS)
	assert_eq(value, Config.VOID_MAX, "the meter never overshoots 100")
	assert_eq(VoidIndex.advance(10.0, 0.0, 0, 0), 10.0, "zero delta changes nothing")


func test_bump_is_clamped_between_zero_and_max() -> void:
	assert_eq(VoidIndex.bump(5.0, -50.0), Config.VOID_START, "relief never goes negative")
	assert_eq(VoidIndex.bump(95.0, 50.0), Config.VOID_MAX, "gain never overshoots")


func test_thresholds_are_inclusive() -> void:
	assert_false(VoidIndex.is_danger(Config.VOID_DANGER_AT - 0.01))
	assert_true(VoidIndex.is_danger(Config.VOID_DANGER_AT))
	assert_false(VoidIndex.is_collapse(Config.VOID_COLLAPSE_AT - 0.01))
	assert_true(VoidIndex.is_collapse(Config.VOID_COLLAPSE_AT))


func test_collapse_resets_above_zero() -> void:
	assert_eq(VoidIndex.after_collapse(), Config.VOID_COLLAPSE_RESET)
	assert_gt(VoidIndex.after_collapse(), Config.VOID_START, "the debt stays visible")
	assert_lt(VoidIndex.after_collapse(), Config.VOID_COLLAPSE_AT)


func test_fraction_is_the_hud_ratio() -> void:
	assert_eq(VoidIndex.fraction(0.0), 0.0)
	assert_eq(VoidIndex.fraction(Config.VOID_MAX), 1.0)
	assert_almost_eq(VoidIndex.fraction(50.0), 0.5, 0.0001)

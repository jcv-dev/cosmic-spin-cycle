extends GutTest
## GDD §5.1 window boundaries are inclusive on the good side.


func test_perfect_window_is_inclusive() -> void:
	assert_eq(RhythmEvaluator.evaluate(0.0), RhythmEvaluator.Grade.PERFECT)
	assert_eq(RhythmEvaluator.evaluate(0.065), RhythmEvaluator.Grade.PERFECT)
	assert_eq(RhythmEvaluator.evaluate(-0.065), RhythmEvaluator.Grade.PERFECT)


func test_good_window_is_inclusive() -> void:
	assert_eq(RhythmEvaluator.evaluate(0.0651), RhythmEvaluator.Grade.GOOD)
	assert_eq(RhythmEvaluator.evaluate(0.130), RhythmEvaluator.Grade.GOOD)
	assert_eq(RhythmEvaluator.evaluate(-0.130), RhythmEvaluator.Grade.GOOD)


func test_outside_good_is_miss() -> void:
	assert_eq(RhythmEvaluator.evaluate(0.1301), RhythmEvaluator.Grade.MISS)
	assert_eq(RhythmEvaluator.evaluate(1.0), RhythmEvaluator.Grade.MISS)


func test_window_scale_widens_windows() -> void:
	assert_eq(RhythmEvaluator.evaluate(0.130, 2.0), RhythmEvaluator.Grade.PERFECT)
	assert_eq(RhythmEvaluator.evaluate(0.260, 2.0), RhythmEvaluator.Grade.GOOD)
	assert_eq(RhythmEvaluator.evaluate(0.261, 2.0), RhythmEvaluator.Grade.MISS)


func test_scale_is_clamped_to_positive() -> void:
	assert_eq(RhythmEvaluator.evaluate(0.0, 0.0), RhythmEvaluator.Grade.PERFECT)
	assert_eq(RhythmEvaluator.evaluate(0.5, -1.0), RhythmEvaluator.Grade.MISS)


func test_rewards_match_gdd() -> void:
	assert_almost_eq(RhythmEvaluator.force_multiplier(RhythmEvaluator.Grade.PERFECT), 1.4, 0.0001)
	assert_almost_eq(RhythmEvaluator.force_multiplier(RhythmEvaluator.Grade.GOOD), 1.0, 0.0001)
	assert_almost_eq(RhythmEvaluator.force_multiplier(RhythmEvaluator.Grade.MISS), 1.0, 0.0001)
	assert_eq(RhythmEvaluator.combo_gain(RhythmEvaluator.Grade.PERFECT), 2)
	assert_eq(RhythmEvaluator.combo_gain(RhythmEvaluator.Grade.GOOD), 1)
	assert_eq(RhythmEvaluator.combo_gain(RhythmEvaluator.Grade.MISS), 0)
	assert_almost_eq(RhythmEvaluator.wash_reduction_s(RhythmEvaluator.Grade.PERFECT), 3.0, 0.0001)
	assert_almost_eq(RhythmEvaluator.wash_reduction_s(RhythmEvaluator.Grade.GOOD), 1.0, 0.0001)
	assert_almost_eq(RhythmEvaluator.wash_reduction_s(RhythmEvaluator.Grade.MISS), 0.0, 0.0001)


func test_only_good_or_better_resolves_turbulence() -> void:
	assert_true(RhythmEvaluator.resolves_turbulence(RhythmEvaluator.Grade.PERFECT))
	assert_true(RhythmEvaluator.resolves_turbulence(RhythmEvaluator.Grade.GOOD))
	assert_false(RhythmEvaluator.resolves_turbulence(RhythmEvaluator.Grade.MISS))


func test_grade_names() -> void:
	assert_eq(RhythmEvaluator.grade_name(RhythmEvaluator.Grade.PERFECT), "PERFECT")
	assert_eq(RhythmEvaluator.grade_name(RhythmEvaluator.Grade.GOOD), "GOOD")
	assert_eq(RhythmEvaluator.grade_name(RhythmEvaluator.Grade.MISS), "MISS")

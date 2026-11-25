extends GutTest
## CalibrationMath: circular wrap, median/MAD outlier rejection, clamp, ms↔s.

const T105 := 60.0 / 105.0


func test_wrap_signed_identity_inside_half_period() -> void:
	assert_almost_eq(CalibrationMath.wrap_signed(0.0, 0.5), 0.0, 0.0000001)
	assert_almost_eq(CalibrationMath.wrap_signed(0.2, 0.5), 0.2, 0.0000001)
	assert_almost_eq(CalibrationMath.wrap_signed(-0.2, 0.5), -0.2, 0.0000001)


func test_wrap_signed_across_period() -> void:
	assert_almost_eq(CalibrationMath.wrap_signed(0.6, 0.5), 0.1, 0.0000001)
	assert_almost_eq(CalibrationMath.wrap_signed(-0.6, 0.5), -0.1, 0.0000001)
	assert_almost_eq(CalibrationMath.wrap_signed(1.2, 0.5), 0.2, 0.0000001)
	assert_almost_eq(CalibrationMath.wrap_signed(1.3, 0.5), -0.2, 0.0000001)


func test_wrap_signed_at_exact_half_period_maps_to_negative_half() -> void:
	assert_almost_eq(CalibrationMath.wrap_signed(0.25, 0.5), -0.25, 0.0000001)


func test_wrap_signed_guards_against_zero_period() -> void:
	assert_eq(CalibrationMath.wrap_signed(0.3, 0.0), 0.0)


func test_beat_error_sign_is_positive_after_the_beat() -> void:
	assert_almost_eq(CalibrationMath.beat_error(3.0 * T105 + 0.02, T105), 0.02, 0.0000001)
	assert_almost_eq(CalibrationMath.beat_error(3.0 * T105 - 0.02, T105), -0.02, 0.0000001)


func test_beat_error_wraps_at_half_beat() -> void:
	var before := CalibrationMath.beat_error(T105 * 0.5 - 0.001, T105)
	var after := CalibrationMath.beat_error(T105 * 0.5 + 0.001, T105)
	assert_almost_eq(before, T105 * 0.5 - 0.001, 0.0000001)
	assert_almost_eq(after, -T105 * 0.5 + 0.001, 0.0000001)
	assert_almost_eq(absf(after), T105 * 0.5 - 0.001, 0.0000001)


func test_sample_offset_is_in_milliseconds() -> void:
	var sample := CalibrationMath.sample_offset_ms(2.0 * T105 + 0.05, T105)
	assert_almost_eq(sample, 50.0, 0.0001)


func test_samples_from_taps_folds_every_tap() -> void:
	var taps: Array[float] = [0.0, T105 + 0.1, 2.0 * T105 - 0.05]
	var samples := CalibrationMath.samples_from_taps(taps, T105)
	assert_eq(samples.size(), 3)
	assert_almost_eq(samples[0], 0.0, 0.0001)
	assert_almost_eq(samples[1], 100.0, 0.0001)
	assert_almost_eq(samples[2], -50.0, 0.0001)


func test_median_odd_even_and_empty() -> void:
	var odd: Array[float] = [30.0, 10.0, 20.0]
	var even: Array[float] = [40.0, 10.0, 30.0, 20.0]
	var empty: Array[float] = []
	assert_almost_eq(CalibrationMath.median(odd), 20.0, 0.0000001)
	assert_almost_eq(CalibrationMath.median(even), 25.0, 0.0000001)
	assert_almost_eq(CalibrationMath.median(empty), 0.0, 0.0000001)


func test_mad_of_constant_and_spread_sets() -> void:
	var constant: Array[float] = [7.0, 7.0, 7.0]
	var spread: Array[float] = [10.0, 20.0, 30.0]
	assert_almost_eq(CalibrationMath.mad(constant), 0.0, 0.0000001)
	assert_almost_eq(CalibrationMath.mad(spread), 10.0, 0.0000001)


func test_median_rejects_a_single_gross_outlier() -> void:
	var samples: Array[float] = [100.0, 102.0, 98.0, 101.0, 400.0]
	var kept := CalibrationMath.reject_outliers(samples)
	assert_eq(kept.size(), 4, "the 400 ms blunder is rejected")
	assert_almost_eq(CalibrationMath.median(kept), 100.5, 0.0001)
	assert_almost_eq(CalibrationMath.resolve_offset_ms(samples), 100.5, 0.0001)


func test_reject_outliers_keeps_small_sets_untouched() -> void:
	var pair: Array[float] = [10.0, 900.0]
	var kept := CalibrationMath.reject_outliers(pair)
	assert_eq(kept.size(), 2)


func test_reject_outliers_keeps_uniform_set() -> void:
	var uniform: Array[float] = [20.0, 20.0, 20.0, 20.0]
	var kept := CalibrationMath.reject_outliers(uniform)
	assert_eq(kept.size(), 4)


func test_resolve_empty_samples_is_zero() -> void:
	var empty: Array[float] = []
	assert_almost_eq(CalibrationMath.resolve_offset_ms(empty), 0.0, 0.0000001)


func test_offset_is_clamped_to_half_a_second() -> void:
	assert_almost_eq(CalibrationMath.clamp_offset_ms(900.0), 500.0, 0.0000001)
	assert_almost_eq(CalibrationMath.clamp_offset_ms(-900.0), -500.0, 0.0000001)
	assert_almost_eq(CalibrationMath.clamp_offset_ms(120.0), 120.0, 0.0000001)
	var wild: Array[float] = [2000.0, 2100.0, 2200.0]
	assert_almost_eq(CalibrationMath.resolve_offset_ms(wild), 500.0, 0.0000001)


func test_ms_seconds_round_trip() -> void:
	assert_almost_eq(CalibrationMath.ms_to_s(250.0), 0.25, 0.0000001)
	assert_almost_eq(CalibrationMath.s_to_ms(0.25), 250.0, 0.0000001)
	assert_almost_eq(CalibrationMath.ms_to_s(CalibrationMath.s_to_ms(0.137)), 0.137, 0.0000001)


func test_has_enough_samples_needs_three_taps() -> void:
	var two: Array[float] = [1.0, 2.0]
	var three: Array[float] = [1.0, 2.0, 3.0]
	assert_false(CalibrationMath.has_enough_samples(two))
	assert_true(CalibrationMath.has_enough_samples(three))

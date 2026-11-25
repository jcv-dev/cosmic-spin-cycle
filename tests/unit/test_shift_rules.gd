extends GutTest
## ShiftRules: defeat, victory at 480 s and the documented "Final Load never gates" override.


func test_shift_is_ongoing_before_the_end() -> void:
	var result := ShiftRules.evaluate(0.0, 100.0, 0, 0)
	assert_false(bool(result["ended"]))
	assert_false(bool(result["victory"]))
	assert_eq(str(result["reason"]), ShiftRules.REASON_ONGOING)


func test_zero_stability_is_a_defeat() -> void:
	var result := ShiftRules.evaluate(120.0, 0.0, 3, 1)
	assert_true(bool(result["ended"]))
	assert_false(bool(result["victory"]))
	assert_eq(str(result["reason"]), ShiftRules.REASON_STABILITY)


func test_negative_stability_is_a_defeat() -> void:
	var result := ShiftRules.evaluate(10.0, -4.0, 0, 0)
	assert_true(bool(result["ended"]))
	assert_eq(str(result["reason"]), ShiftRules.REASON_STABILITY)


func test_victory_exactly_at_the_shift_duration() -> void:
	var result := ShiftRules.evaluate(Config.SHIFT_DURATION_S, 1.0, 10, 2)
	assert_true(bool(result["ended"]))
	assert_true(bool(result["victory"]))
	assert_eq(str(result["reason"]), ShiftRules.REASON_TIME)

	var just_before := ShiftRules.evaluate(Config.SHIFT_DURATION_S - 0.001, 1.0, 10, 2)
	assert_false(bool(just_before["ended"]), "the last millisecond is still the shift")


func test_defeat_beats_victory_on_the_same_tick() -> void:
	var result := ShiftRules.evaluate(Config.SHIFT_DURATION_S, 0.0, 10, 2)
	assert_true(bool(result["ended"]))
	assert_false(bool(result["victory"]), "reaching zero at 480 s is a loss")
	assert_eq(str(result["reason"]), ShiftRules.REASON_STABILITY)


func test_final_load_never_gates_victory() -> void:
	for delivered: int in [0, 1, 5]:
		var result := ShiftRules.evaluate(Config.SHIFT_DURATION_S, 50.0, delivered, 0)
		assert_true(
			bool(result["victory"]), "surviving to 06:00 wins with %d delivered" % delivered
		)


func test_result_carries_the_summary_counters() -> void:
	var result := ShiftRules.evaluate(300.0, 42.0, 7, 3)
	assert_eq(int(result["delivered"]), 7)
	assert_eq(int(result["final_delivered"]), 3, "kept for the end screen, not used as a gate")
	assert_almost_eq(float(result["stability"]), 42.0, 0.001)
	assert_almost_eq(float(result["time"]), 300.0, 0.001)


func test_shift_progress_and_verdict_copy() -> void:
	assert_almost_eq(ShiftRules.shift_progress(0.0), 0.0, 0.001)
	assert_almost_eq(ShiftRules.shift_progress(240.0), 0.5, 0.001)
	assert_almost_eq(ShiftRules.shift_progress(480.0), 1.0, 0.001)
	assert_almost_eq(ShiftRules.shift_progress(9999.0), 1.0, 0.001, "clamped")
	assert_eq(ShiftRules.verdict_text(true), "TURNO COMPLETADO")
	assert_eq(ShiftRules.verdict_text(false), "DESGARRO UNIVERSAL")

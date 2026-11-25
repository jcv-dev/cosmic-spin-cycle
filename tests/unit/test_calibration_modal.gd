extends GutTest
## CalibrationModal: countdown, 10 s window, median, Apply/Reset/Cancel persistence.

var _modal: CalibrationModal
var _saved_offset_ms := 0.0
var _saved_samples: Array[float] = []


func before_each() -> void:
	_saved_offset_ms = Settings.calibration_offset_ms()
	_saved_samples = []
	_saved_samples.assign(Settings.calibration_samples)
	Settings.user_calibration_offset = 0.0
	Settings.calibration_samples.clear()
	_modal = preload("res://scenes/ui/CalibrationModal.tscn").instantiate()
	add_child_autofree(_modal)


func after_each() -> void:
	_modal.close()
	Settings.user_calibration_offset = _saved_offset_ms / 1000.0
	Settings.calibration_samples.assign(_saved_samples)
	Settings.save_settings()


func test_scene_instantiates_hidden() -> void:
	assert_true(_modal is Control)
	assert_false(_modal.visible)
	assert_eq(_modal.get_state(), CalibrationModal.State.IDLE)


func test_open_starts_a_three_second_countdown() -> void:
	_modal.open(118)
	assert_true(_modal.visible)
	assert_eq(_modal.get_session_bpm(), 118)
	assert_eq(_modal.get_state(), CalibrationModal.State.COUNTDOWN)
	assert_eq(_modal.get_sample_count(), 0)
	assert_false(_modal.is_apply_enabled())


func test_countdown_moves_into_the_ten_second_window() -> void:
	_modal.open(105)
	_modal.advance_time(3.0)
	assert_eq(_modal.get_state(), CalibrationModal.State.TAPPING)
	_modal.advance_time(9.9)
	assert_eq(_modal.get_state(), CalibrationModal.State.TAPPING)
	_modal.advance_time(0.1)
	assert_eq(_modal.get_state(), CalibrationModal.State.DONE)


func test_taps_are_folded_into_millisecond_samples() -> void:
	_modal.open(105, true)
	var beat_s := 60.0 / 105.0
	assert_true(_modal.tap_at(0.020))
	assert_true(_modal.tap_at(beat_s + 0.020))
	assert_true(_modal.tap_at(2.0 * beat_s + 0.020))
	assert_eq(_modal.get_sample_count(), 3)
	assert_almost_eq(CalibrationMath.median(_modal.get_samples_ms()), 20.0, 0.001)
	_modal.finish_session()
	assert_almost_eq(_modal.get_result_ms(), 20.0, 0.001)
	assert_true(_modal.is_apply_enabled())


func test_apply_persists_the_median_and_closes() -> void:
	_modal.open(130, true)
	var beat_s := 60.0 / 130.0
	for index in range(5):
		_modal.tap_at(float(index) * beat_s + 0.035)
	_modal.finish_session()
	watch_signals(_modal)
	assert_true(_modal.apply_result())
	assert_almost_eq(Settings.calibration_offset_ms(), 35.0, 0.01)
	assert_almost_eq(
		_modal.get_result_ms(), Settings.calibration_offset_ms(), 0.001, "shown == stored"
	)
	var applied: Array = get_signal_parameters(_modal, "offset_applied", 0)
	assert_almost_eq(float(applied[0]), 35.0, 0.001, "signal carries the measured offset")
	assert_false(_modal.visible)
	assert_eq(_modal.get_state(), CalibrationModal.State.IDLE)


func test_apply_needs_three_taps() -> void:
	_modal.open(105, true)
	_modal.tap_at(0.02)
	_modal.tap_at(60.0 / 105.0 + 0.02)
	_modal.finish_session()
	assert_false(_modal.is_apply_enabled())
	assert_false(_modal.apply_result())
	assert_almost_eq(Settings.calibration_offset_ms(), 0.0, 0.001)


func test_reset_writes_zero_and_closes() -> void:
	Settings.set_calibration_offset_ms(120.0)
	_modal.open(105, true)
	assert_almost_eq(_modal.reset_calibration(), 0.0, 0.001)
	assert_almost_eq(Settings.calibration_offset_ms(), 0.0, 0.001)
	assert_false(_modal.visible)


func test_cancel_leaves_the_stored_offset_untouched() -> void:
	Settings.set_calibration_offset_ms(55.0)
	_modal.open(105, true)
	_modal.cancel()
	assert_almost_eq(Settings.calibration_offset_ms(), 55.0, 0.001)
	assert_false(_modal.visible)


func test_taps_outside_the_window_are_ignored() -> void:
	_modal.open(105, true)
	_modal.finish_session()
	assert_false(_modal.tap_at(1.0))
	assert_eq(_modal.get_sample_count(), 0)


func test_outlier_tap_is_rejected_from_the_result() -> void:
	_modal.open(105, true)
	var beat_s := 60.0 / 105.0
	_modal.tap_at(0.100)
	_modal.tap_at(beat_s + 0.102)
	_modal.tap_at(2.0 * beat_s + 0.098)
	_modal.tap_at(3.0 * beat_s + 0.200)
	_modal.finish_session()
	assert_almost_eq(_modal.get_result_ms(), 100.0, 0.5, "the +200 ms tap is an outlier")


func test_unknown_bpm_falls_back_to_phase_one() -> void:
	_modal.open(999, true)
	assert_eq(_modal.get_session_bpm(), Config.PHASE_BPM[0])


func test_session_restart_clears_previous_samples() -> void:
	_modal.open(105, true)
	_modal.tap_at(0.02)
	assert_eq(_modal.get_sample_count(), 1)
	_modal.start_session(142, true)
	assert_eq(_modal.get_sample_count(), 0)
	assert_eq(_modal.get_session_bpm(), 142)
	assert_eq(_modal.get_state(), CalibrationModal.State.TAPPING)

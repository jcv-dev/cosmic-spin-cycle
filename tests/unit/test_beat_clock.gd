extends GutTest
## BeatConductor: deterministic clock, 4/4 measure events, Δt wrap, BPM changes.


func before_each() -> void:
	BeatConductor.stop()


func after_each() -> void:
	BeatConductor.stop()


func test_start_emits_downbeat_and_measure() -> void:
	watch_signals(BeatConductor)
	BeatConductor.start(120)
	assert_signal_emit_count(BeatConductor, "beat_hit", 1)
	assert_signal_emit_count(BeatConductor, "measure_hit", 1)


func test_beats_advance_with_clock() -> void:
	watch_signals(BeatConductor)
	BeatConductor.start(120)
	BeatConductor.advance_clock(0.25)
	assert_signal_emit_count(BeatConductor, "beat_hit", 1, "half a beat: no new beat")
	BeatConductor.advance_clock(0.25)
	assert_signal_emit_count(BeatConductor, "beat_hit", 2, "one full beat")
	assert_signal_emit_count(BeatConductor, "measure_hit", 1)
	BeatConductor.advance_clock(1.5)
	assert_signal_emit_count(BeatConductor, "beat_hit", 5)
	assert_signal_emit_count(BeatConductor, "measure_hit", 2, "measure at beat 4")


func test_beat_index_and_measure_index() -> void:
	BeatConductor.start(120)
	BeatConductor.advance_clock(2.0)
	assert_eq(BeatConductor.get_beat_index(), 4)
	assert_eq(BeatConductor.get_measure_index(), 1)
	assert_eq(BeatConductor.beats_until_next_measure(), 4)


func test_delta_to_nearest_beat_wraps() -> void:
	BeatConductor.start(120)
	assert_almost_eq(BeatConductor.delta_to_nearest_beat(0.0), 0.0, 0.000001)
	assert_almost_eq(BeatConductor.delta_to_nearest_beat(0.1), 0.1, 0.000001)
	assert_almost_eq(BeatConductor.delta_to_nearest_beat(0.4), 0.1, 0.000001)
	assert_almost_eq(BeatConductor.delta_to_nearest_beat(0.25), 0.25, 0.000001)


func test_delta_wrap_at_half_beat_for_105_bpm() -> void:
	BeatConductor.start(105)
	var t := BeatConductor.beat_seconds()
	assert_almost_eq(BeatConductor.delta_to_nearest_beat(t * 0.5), t * 0.5, 0.000001)
	assert_almost_eq(BeatConductor.delta_to_nearest_beat(t), 0.0, 0.000001)


func test_beat_phase() -> void:
	BeatConductor.start(120)
	BeatConductor.advance_clock(0.125)
	assert_almost_eq(BeatConductor.get_beat_phase(), 0.25, 0.0001)


func test_bpm_change_resets_musical_clock() -> void:
	BeatConductor.start(105)
	BeatConductor.advance_clock(1.0)
	BeatConductor.set_bpm(142)
	assert_eq(BeatConductor.bpm, 142)
	assert_almost_eq(BeatConductor.get_song_time(), 0.0, 0.0001)
	assert_eq(BeatConductor.get_beat_index(), 0)
	assert_almost_eq(BeatConductor.beat_seconds(), 60.0 / 142.0, 0.000001)


func test_stop_freezes_clock() -> void:
	BeatConductor.start(120)
	BeatConductor.advance_clock(0.5)
	var frozen := BeatConductor.get_song_time()
	BeatConductor.stop()
	BeatConductor.advance_clock(1.0)
	assert_almost_eq(BeatConductor.get_song_time(), frozen, 0.000001)


func test_advance_clock_ignores_zero_and_negative() -> void:
	BeatConductor.start(120)
	BeatConductor.advance_clock(0.0)
	BeatConductor.advance_clock(-1.0)
	assert_almost_eq(BeatConductor.get_song_time(), 0.0, 0.000001)


func test_105_bpm_thirty_two_beats_take_18_285714_s() -> void:
	watch_signals(BeatConductor)
	BeatConductor.start(105)
	var period := 60.0 / 105.0
	BeatConductor.advance_clock(32.0 * period)
	assert_almost_eq(BeatConductor.get_song_time(), 18.285714, 0.000001)
	assert_almost_eq(BeatConductor.beat_seconds(), period, 0.000001)
	assert_eq(BeatConductor.get_beat_index(), 32)
	assert_eq(BeatConductor.get_measure_index(), 8)
	assert_signal_emit_count(BeatConductor, "beat_hit", 33, "downbeat + 32 beats")
	assert_signal_emit_count(BeatConductor, "measure_hit", 9, "measure 0 + 8 bars")


func test_118_bpm_thirty_two_beats() -> void:
	watch_signals(BeatConductor)
	BeatConductor.start(118)
	BeatConductor.advance_clock(32.0 * (60.0 / 118.0))
	assert_eq(BeatConductor.get_beat_index(), 32)
	assert_eq(BeatConductor.get_measure_index(), 8)
	assert_signal_emit_count(BeatConductor, "beat_hit", 33)
	assert_signal_emit_count(BeatConductor, "measure_hit", 9)


func test_130_bpm_thirty_two_beats() -> void:
	watch_signals(BeatConductor)
	BeatConductor.start(130)
	BeatConductor.advance_clock(32.0 * (60.0 / 130.0))
	assert_eq(BeatConductor.get_beat_index(), 32)
	assert_eq(BeatConductor.get_measure_index(), 8)
	assert_signal_emit_count(BeatConductor, "beat_hit", 33)
	assert_signal_emit_count(BeatConductor, "measure_hit", 9)


func test_142_bpm_thirty_two_beats() -> void:
	watch_signals(BeatConductor)
	BeatConductor.start(142)
	BeatConductor.advance_clock(32.0 * (60.0 / 142.0))
	assert_eq(BeatConductor.get_beat_index(), 32)
	assert_eq(BeatConductor.get_measure_index(), 8)
	assert_signal_emit_count(BeatConductor, "beat_hit", 33)
	assert_signal_emit_count(BeatConductor, "measure_hit", 9)


func test_set_bpm_starts_a_fresh_clock_and_emits_downbeat() -> void:
	watch_signals(BeatConductor)
	BeatConductor.start(105)
	BeatConductor.advance_clock(2.5)
	BeatConductor.set_bpm(142)
	assert_signal_emit_count(BeatConductor, "bpm_changed", 1)
	assert_signal_emit_count(BeatConductor, "beat_hit", 6, "5 start + reset downbeat")
	assert_signal_emit_count(BeatConductor, "measure_hit", 3, "start + bar 1 + reset downbeat")
	assert_almost_eq(BeatConductor.get_song_time(), 0.0, 0.000001)
	assert_eq(BeatConductor.get_beat_index(), 0)
	assert_eq(BeatConductor.get_measure_index(), 0)
	assert_eq(BeatConductor.beats_until_next_measure(), 4)
	assert_almost_eq(BeatConductor.get_beat_phase(), 0.0, 0.000001)
	var period := 60.0 / 142.0
	BeatConductor.advance_clock(period)
	assert_eq(BeatConductor.get_beat_index(), 1)
	assert_eq(BeatConductor.beats_until_next_measure(), 3)
	BeatConductor.advance_clock(3.0 * period)
	assert_eq(BeatConductor.get_beat_index(), 4)
	assert_eq(BeatConductor.get_measure_index(), 1)
	assert_eq(BeatConductor.beats_until_next_measure(), 4)


func test_set_bpm_rejects_non_positive_tempo() -> void:
	BeatConductor.start(120)
	BeatConductor.set_bpm(0)
	assert_eq(BeatConductor.bpm, 120)
	BeatConductor.set_bpm(-5)
	assert_eq(BeatConductor.bpm, 120)

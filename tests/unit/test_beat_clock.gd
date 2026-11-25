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

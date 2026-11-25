extends GutTest
## BeatConductor: pure latency compensation and the monotonic clock policy.

const TWO_MS := 0.002
const JUST_UNDER_FIVE_MS := 0.004
const JUST_OVER_FIVE_MS := 0.006
const FIFTY_MS := 0.050


func test_compensation_subtracts_latency_calibration_and_stem_offset() -> void:
	var t := BeatConductor.compensated_song_time(2.0, 0.01, 0.02, 0.05, 0.1)
	assert_almost_eq(t, 1.84, 0.000001)


func test_compensation_with_zero_offsets_is_playback_plus_mix() -> void:
	var t := BeatConductor.compensated_song_time(1.25, 0.004, 0.0, 0.0, 0.0)
	assert_almost_eq(t, 1.254, 0.000001)


func test_compensation_never_returns_negative_time() -> void:
	assert_eq(BeatConductor.compensated_song_time(0.0, 0.0, 0.05, 0.05, 0.1), 0.0)
	assert_almost_eq(BeatConductor.compensated_song_time(0.001, 0.0, 0.2, 0.0, 0.0), 0.0, 0.000001)


func test_positive_calibration_delays_the_musical_clock() -> void:
	var raw := BeatConductor.compensated_song_time(10.0, 0.0, 0.0, 0.0, 0.0)
	var calibrated := BeatConductor.compensated_song_time(10.0, 0.0, 0.0, 0.120, 0.0)
	assert_almost_eq(raw - calibrated, 0.120, 0.000001, "the clock runs 120 ms behind")


func test_stem_offset_is_removed_from_the_audio_time() -> void:
	var without := BeatConductor.compensated_song_time(5.0, 0.0, 0.0, 0.0, 0.0)
	var with_offset := BeatConductor.compensated_song_time(5.0, 0.0, 0.0, 0.0, 0.25)
	assert_almost_eq(without - with_offset, 0.25, 0.000001)


func test_monotonic_forward_candidates_pass_through() -> void:
	assert_almost_eq(BeatConductor.monotonic_time(1.0, 1.016), 1.016, 0.000001)
	assert_almost_eq(BeatConductor.monotonic_time(0.0, 0.0), 0.0, 0.000001)


func test_monotonic_clamps_backward_jitter_under_five_ms() -> void:
	assert_almost_eq(BeatConductor.monotonic_time(1.0, 1.0 - TWO_MS), 1.0, 0.000001)
	assert_almost_eq(BeatConductor.monotonic_time(1.0, 1.0 - JUST_UNDER_FIVE_MS), 1.0, 0.000001)


func test_monotonic_accepts_a_reanchor_beyond_five_ms() -> void:
	assert_almost_eq(
		BeatConductor.monotonic_time(1.0, 1.0 - JUST_OVER_FIVE_MS),
		1.0 - JUST_OVER_FIVE_MS,
		0.000001
	)
	assert_almost_eq(BeatConductor.monotonic_time(18.2, 0.0), 0.0, 0.000001)


func test_monotonic_clamps_negative_candidates_to_zero() -> void:
	assert_eq(BeatConductor.monotonic_time(0.0, -0.25), 0.0)
	assert_eq(BeatConductor.monotonic_time(0.0, -0.003), 0.0)


func test_signed_delta_is_positive_when_late() -> void:
	BeatConductor.start(120)
	var beat_s := BeatConductor.beat_seconds()
	assert_almost_eq(BeatConductor.signed_delta_to_nearest_beat(beat_s + 0.02), 0.02, 0.000001)
	assert_almost_eq(BeatConductor.signed_delta_to_nearest_beat(beat_s - 0.02), -0.02, 0.000001)
	assert_almost_eq(BeatConductor.signed_delta_to_nearest_beat(0.0), 0.0, 0.000001)


func test_signed_and_absolute_delta_agree_on_magnitude() -> void:
	BeatConductor.start(105)
	var beat_s := BeatConductor.beat_seconds()
	var offsets: Array[float] = [0.0, 0.05, 0.2, beat_s * 0.5]
	for offset in offsets:
		var signed := BeatConductor.signed_delta_to_nearest_beat(3.0 * beat_s + offset)
		var absolute := BeatConductor.delta_to_nearest_beat(3.0 * beat_s + offset)
		assert_almost_eq(absf(signed), absolute, 0.000001)


func test_missing_audio_is_not_fatal() -> void:
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)
	assert_eq(BeatConductor.stem_first_beat_offset, 0.0)
	BeatConductor.set_stream(null, 0.125)
	assert_almost_eq(BeatConductor.stem_first_beat_offset, 0.125, 0.000001)
	BeatConductor.start(120)
	assert_true(BeatConductor.is_playing, "free-run clock still starts")
	BeatConductor.advance_clock(0.5)
	assert_almost_eq(BeatConductor.get_song_time(), 0.5, 0.000001)


func after_each() -> void:
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)

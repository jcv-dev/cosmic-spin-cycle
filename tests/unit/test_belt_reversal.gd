extends GutTest
## Phase-3 belt reversal boundaries (GDD §5.3, AGENTS §A6 #12).
##
## At 130 BPM (phase 3) the belts flip every 16 measures = 64 beats, with a 4-beat warning:
## warnings land on beats 60 / 124 / 188 and flips on 64 / 128 / 192. Nothing happens in
## any other phase.

const PHASE_3 := BeltReversal.ACTIVE_PHASE
const BPM_130 := 130

var reversal: BeltReversal


func before_each() -> void:
	reversal = BeltReversal.new()


func _beat_time(beat: int, bpm: int) -> float:
	return float(beat) * Config.beat_seconds(bpm)


func _measure(beat: int) -> int:
	return floori(float(beat) / float(Config.BEATS_PER_MEASURE))


func test_flip_interval_is_sixteen_measures() -> void:
	assert_eq(BeltReversal.beats_per_flip(), 64)
	assert_eq(BeltReversal.warning_beats(), 4)


func test_flip_interval_in_seconds_at_130_bpm() -> void:
	# 16 measures = 64 beats; at 130 BPM one beat is 60/130 s.
	assert_almost_eq(_beat_time(64, BPM_130), 29.5384, 0.01, "flip every ~29.5 s in phase 3")


func test_warnings_land_on_beats_60_124_188() -> void:
	var expected: Array[int] = [60, 124, 188]
	for beat in expected:
		var verdict := reversal.on_beat(beat, _measure(beat), PHASE_3)
		assert_true(verdict.warn, "beat %d must warn" % beat)
		assert_false(verdict.flip, "beat %d must not flip" % beat)
		assert_eq(verdict.beats_left, BeltReversal.warning_beats(), "beat %d countdown" % beat)


func test_flips_land_on_beats_64_128_192() -> void:
	var expected: Array[int] = [64, 128, 192]
	for beat in expected:
		var verdict := reversal.on_beat(beat, _measure(beat), PHASE_3)
		assert_true(verdict.flip, "beat %d must flip" % beat)
		assert_false(verdict.warn, "beat %d must not warn" % beat)


func test_each_warning_precedes_its_flip_by_four_beats() -> void:
	for flip_beat: int in [64, 128, 192]:
		var warn_beat := flip_beat - BeltReversal.warning_beats()
		var fresh := BeltReversal.new()
		assert_true(fresh.on_beat(warn_beat, _measure(warn_beat), PHASE_3).warn, "warning")
		assert_true(fresh.on_beat(flip_beat, _measure(flip_beat), PHASE_3).flip, "flip")


func test_no_reversal_outside_phase_three() -> void:
	for phase: int in [0, 1, 3]:
		var fresh := BeltReversal.new()
		for beat: int in [60, 64, 124, 128, 188, 192]:
			var verdict := fresh.on_beat(beat, _measure(beat), phase)
			assert_false(verdict.warn, "phase %d beat %d warns" % [phase, beat])
			assert_false(verdict.flip, "phase %d beat %d flips" % [phase, beat])
			assert_eq(verdict.beats_left, 0)
		assert_false(fresh.is_reversed, "phase %d never reverses" % phase)


func test_no_flip_before_the_first_measure() -> void:
	var verdict := reversal.on_beat(0, 0, PHASE_3)
	assert_false(verdict.flip, "beat 0 is not a reversal")
	assert_false(verdict.warn)
	assert_eq(verdict.beats_left, BeltReversal.beats_per_flip())


func test_direction_alternates_at_every_flip() -> void:
	assert_false(reversal.is_reversed, "belts start forward")
	assert_true(reversal.on_beat(64, 16, PHASE_3).flip)
	assert_true(reversal.is_reversed, "first flip reverses")
	assert_true(reversal.on_beat(128, 32, PHASE_3).flip)
	assert_false(reversal.is_reversed, "second flip restores the original flow")
	assert_true(reversal.on_beat(192, 48, PHASE_3).flip)
	assert_true(reversal.is_reversed)


func test_repeated_beat_does_not_flip_twice() -> void:
	assert_true(reversal.on_beat(64, 16, PHASE_3).flip)
	var again := reversal.on_beat(64, 16, PHASE_3)
	assert_false(again.flip, "a beat is consumed once: a repeat returns the idle verdict")
	assert_true(reversal.is_reversed, "direction did not toggle back")


func test_measure_helper_matches_beat_helper() -> void:
	var from_beat := BeltReversal.new().on_beat(60, 15, PHASE_3)
	var from_measure := BeltReversal.new().on_measure(15, PHASE_3)
	assert_eq(from_measure.warn, from_beat.warn)
	assert_eq(from_measure.flip, from_beat.flip)
	assert_eq(from_measure.beats_left, from_beat.beats_left)
	assert_true(from_measure.warn)


func test_countdown_is_monotonic_inside_a_cycle() -> void:
	for beat in range(65, 128):
		var verdict := BeltReversal.new().on_beat(beat, _measure(beat), PHASE_3)
		assert_false(verdict.flip, "beat %d inside the cycle" % beat)
		assert_eq(verdict.beats_left, 128 - beat, "beat %d countdown" % beat)


func test_reset_restores_forward_flow() -> void:
	reversal.on_beat(64, 16, PHASE_3)
	assert_true(reversal.is_reversed)
	reversal.reset()
	assert_false(reversal.is_reversed)
	assert_true(reversal.on_beat(64, 16, PHASE_3).flip, "the same beat flips again after reset")


func test_direction_sign_helper() -> void:
	assert_eq(BeltReversal.direction_sign_after(0), 1)
	assert_eq(BeltReversal.direction_sign_after(1), -1)
	assert_eq(BeltReversal.direction_sign_after(2), 1)


func test_negative_input_is_idle() -> void:
	var verdict := reversal.on_beat(-4, -1, PHASE_3)
	assert_false(verdict.warn)
	assert_false(verdict.flip)

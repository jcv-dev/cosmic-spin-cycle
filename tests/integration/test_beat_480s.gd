extends GutTest
## Integration: a full 480 s shift of the musical clock, stepped deterministically.

const PHASE_DURATIONS: Array[float] = [120.0, 150.0, 150.0, 60.0]

var _beats: Array[int] = []
var _phase_counts: Array[int] = []
var _current_phase := 0


func before_each() -> void:
	BeatConductor.set_stream(null, 0.0)
	BeatConductor.stop()
	_beats.clear()
	_phase_counts.clear()
	_current_phase = 0
	BeatConductor.beat_hit.connect(_on_beat)


func after_each() -> void:
	if BeatConductor.beat_hit.is_connected(_on_beat):
		BeatConductor.beat_hit.disconnect(_on_beat)
	BeatConductor.stop()


func _on_beat(beat: int) -> void:
	if beat <= 0:
		return  # forced downbeat on start()/set_bpm(), not a timed beat
	_beats.append(beat)
	while _phase_counts.size() <= _current_phase:
		_phase_counts.append(0)
	_phase_counts[_current_phase] += 1


func test_480_s_shift_matches_the_phase_table() -> void:
	BeatConductor.start(Config.PHASE_BPM[0])
	var expected_total := 0
	for phase in range(PHASE_DURATIONS.size()):
		_current_phase = phase
		if phase > 0:
			BeatConductor.set_bpm(Config.PHASE_BPM[phase])
		var expected := int(
			round(PHASE_DURATIONS[phase] / Config.beat_seconds(float(Config.PHASE_BPM[phase])))
		)
		expected_total += expected
		BeatConductor.advance_clock(PHASE_DURATIONS[phase])
		assert_between(
			_phase_counts[phase], expected - 1, expected + 1, "phase %d beat count" % (phase + 1)
		)
	assert_eq(Config.PHASE_START_S.size(), PHASE_DURATIONS.size())
	assert_between(_beats.size(), expected_total - 1, expected_total + 1)
	assert_eq(expected_total, 972, "210 + 295 + 325 + 142 musical beats")


func test_constant_105_bpm_for_480_s_is_840_beats() -> void:
	BeatConductor.start(105)
	BeatConductor.advance_clock(Config.SHIFT_DURATION_S)
	assert_between(_beats.size(), 839, 841)
	assert_almost_eq(BeatConductor.get_song_time(), 480.0, 0.000001)
	assert_eq(BeatConductor.get_beat_index(), 840)
	assert_eq(BeatConductor.get_measure_index(), 210)
	assert_eq(_beats[_beats.size() - 1], 840)
	for index in range(1, _beats.size()):
		assert_eq(_beats[index], _beats[index - 1] + 1, "no skipped or repeated beats")

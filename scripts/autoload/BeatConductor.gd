extends Node
## Musical clock, beat/measure events and latency compensation (GDD §5.1, §7.1).
##
## Emits beats from _process, never from a Timer. `advance_clock()` is the deterministic
## stepping hook used by tests and headless simulations. When no audio stream is playing
## the clock free-runs; the API is identical, so gameplay and tests share one path.

signal beat_hit(beat: int)
signal measure_hit(measure: int)
signal bpm_changed(bpm: int)

const BEATS_PER_MEASURE := Config.BEATS_PER_MEASURE
const MAX_BACKWARD_JUMP_S := 0.005

@export var start_bpm := Config.PHASE_BPM[0]

var bpm := Config.PHASE_BPM[0]
var is_playing := false
var stem_first_beat_offset := 0.0

var _player: AudioStreamPlayer
var _clock := 0.0
var _beat_index := 0
var _measure_index := 0
var _next_beat_time := 0.0


func _ready() -> void:
	process_priority = 100
	_player = get_node_or_null("AudioStreamPlayer") as AudioStreamPlayer
	bpm = start_bpm


func _process(delta: float) -> void:
	if not is_playing:
		return
	var t := _audio_time(delta)
	if t < _clock:
		if _clock - t > MAX_BACKWARD_JUMP_S:
			# Loop wrap or stem restart: accept the new origin rather than freezing.
			_clock = maxf(t, 0.0)
		else:
			t = _clock
	if t > _clock:
		_clock = t
	_advance_beats(_clock)


## Starts (or restarts) the musical clock. Emits beat 0 and measure 0 immediately.
func start(p_bpm: int = -1) -> void:
	if p_bpm > 0:
		bpm = p_bpm
	_clock = 0.0
	_beat_index = 0
	_measure_index = 0
	_next_beat_time = beat_seconds()
	is_playing = true
	if _player != null:
		if _player.stream != null:
			_player.play()
		else:
			_player.stop()
	beat_hit.emit(0)
	measure_hit.emit(0)


func stop() -> void:
	is_playing = false
	if _player != null:
		_player.stop()


## Phase boundary: new tempo implies a new stem and a fresh musical clock.
func set_bpm(p_bpm: int) -> void:
	if p_bpm <= 0:
		return
	bpm = p_bpm
	_clock = 0.0
	_beat_index = 0
	_measure_index = 0
	_next_beat_time = beat_seconds()
	bpm_changed.emit(bpm)
	beat_hit.emit(0)
	measure_hit.emit(0)


## Assigns the audio stream used by get_song_time(). Does not start playback.
func set_stream(stream: AudioStream, first_beat_offset: float = 0.0) -> void:
	stem_first_beat_offset = first_beat_offset
	if _player != null:
		_player.stream = stream


func get_song_time() -> float:
	return _clock


func beat_seconds() -> float:
	return Config.beat_seconds(float(bpm))


func delta_to_nearest_beat(t: float) -> float:
	var beat_s := beat_seconds()
	if beat_s <= 0.0:
		return 0.0
	var pos := fposmod(t, beat_s)
	return minf(pos, beat_s - pos)


func get_beat_phase() -> float:
	var beat_s := beat_seconds()
	if beat_s <= 0.0:
		return 0.0
	return fposmod(_clock, beat_s) / beat_s


func get_beat_index() -> int:
	return _beat_index


func get_measure_index() -> int:
	return _measure_index


func beats_until_next_measure() -> int:
	var within := _beat_index % BEATS_PER_MEASURE
	return BEATS_PER_MEASURE if within == 0 else BEATS_PER_MEASURE - within


## Deterministic stepping for tests and headless sims. Does not read wall-clock time.
func advance_clock(seconds: float) -> void:
	if not is_playing or seconds <= 0.0:
		return
	_clock += seconds
	_advance_beats(_clock)


func _advance_beats(t: float) -> void:
	var guard := 0
	while is_playing and t + 0.000001 >= _next_beat_time and guard < 4096:
		guard += 1
		_beat_index += 1
		_next_beat_time += beat_seconds()
		beat_hit.emit(_beat_index)
		if _beat_index % BEATS_PER_MEASURE == 0:
			_measure_index = _beat_index / BEATS_PER_MEASURE
			measure_hit.emit(_measure_index)


func _audio_time(delta: float) -> float:
	if _player != null and _player.playing:
		var t := _player.get_playback_position() + AudioServer.get_time_since_last_mix()
		t -= AudioServer.get_output_latency()
		t -= Settings.user_calibration_offset
		t -= stem_first_beat_offset
		return maxf(t, 0.0)
	return _clock + delta

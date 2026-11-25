class_name CalibrationModal
extends Control
## 10 s tap-along audio calibration wizard (GDD §5.1, docs/CALIBRATION.md).
##
## Flow: open() -> 3 s countdown -> 10 s click track -> median tap offset -> Apply.
## Taps are sampled from the compensated audio clock, so the resulting offset absorbs
## both unreported output latency and the player's own timing bias. Apply persists the
## median through Settings.set_calibration_offset_ms(); Reset clears it to zero; Cancel
## leaves the stored value untouched.

signal offset_applied(offset_ms: float)
signal closed

enum State { IDLE, COUNTDOWN, TAPPING, DONE }

const COUNTDOWN_S := 3.0
## Number of taps required before Apply is enabled (same threshold as the math helper).
const MIN_TAPS := CalibrationMath.MIN_SAMPLES
const BPM_FALLBACK := Config.PHASE_BPM[0]
const TITLE_TEXT := "AUDIO CALIBRATION"
const INTRO_TEXT := "Tap SPACE (or gamepad A) on every click. 10 seconds."
const DONE_TEXT := "Window closed. Apply to keep this offset."

var _state := State.IDLE
var _session_bpm := BPM_FALLBACK
var _countdown_left := COUNTDOWN_S
var _elapsed := 0.0
var _samples: Array[float] = []
var _result_ms := 0.0
var _free_run_start_us := 0

@onready var _title_label: Label = %TitleLabel
@onready var _status_label: Label = %StatusLabel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _result_label: Label = %ResultLabel
@onready var _apply_button: Button = %ApplyButton
@onready var _reset_button: Button = %ResetButton
@onready var _cancel_button: Button = %CancelButton
@onready var _click_player: AudioStreamPlayer = %ClickPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_button.pressed.connect(_on_apply_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	visible = false
	set_process(false)
	_refresh_labels()


func _process(delta: float) -> void:
	if not visible:
		return
	_advance(delta)


func _input(event: InputEvent) -> void:
	# Rhythm taps are evaluated in _input, never in _physics_process (AGENTS §A2.7).
	if not visible or _state != State.TAPPING:
		return
	if event.is_action_pressed("grab_throw"):
		tap_at(current_song_time())
		get_viewport().set_input_as_handled()


## Opens the wizard and starts the countdown. `skip_countdown` exists for tests.
func open(p_bpm: int = -1, skip_countdown: bool = false) -> void:
	_session_bpm = _valid_bpm(p_bpm)
	visible = true
	set_process(true)
	start_session(_session_bpm, skip_countdown)


func close() -> void:
	if not visible:
		return
	visible = false
	set_process(false)
	_stop_click()
	_state = State.IDLE
	closed.emit()


## Restarts the session at `p_bpm`. Emits nothing; the wizard stays open.
func start_session(p_bpm: int, skip_countdown: bool = false) -> void:
	_session_bpm = _valid_bpm(p_bpm)
	_samples.clear()
	_result_ms = 0.0
	_elapsed = 0.0
	_countdown_left = COUNTDOWN_S
	_title_label.text = TITLE_TEXT
	_status_label.text = INTRO_TEXT
	_apply_button.disabled = true
	_stop_click()
	_load_click_track()
	if skip_countdown:
		_begin_tapping()
	else:
		_state = State.COUNTDOWN
		_refresh_labels()


## Records one tap at an absolute song time. Returns false outside the tapping window.
func tap_at(song_time: float) -> bool:
	if _state != State.TAPPING:
		return false
	var beat_s := Config.beat_seconds(float(_session_bpm))
	_samples.append(CalibrationMath.sample_offset_ms(song_time, beat_s))
	_refresh_labels()
	return true


## Closes the tapping window and computes the result (used by the timer and tests).
func finish_session() -> void:
	if _state != State.TAPPING:
		return
	_stop_click()
	_state = State.DONE
	_result_ms = CalibrationMath.resolve_offset_ms(_samples)
	_apply_button.disabled = not CalibrationMath.has_enough_samples(_samples)
	_refresh_labels()


## Persists the measured offset. Returns false when there are not enough taps.
func apply_result() -> bool:
	if _state != State.DONE or not CalibrationMath.has_enough_samples(_samples):
		return false
	Settings.set_calibration_samples(_samples)
	Settings.set_calibration_offset_ms(_result_ms)
	offset_applied.emit(_result_ms)
	close()
	return true


## Clears the stored offset to zero (persisted). Returns the value that was written.
func reset_calibration() -> float:
	var empty: Array[float] = []
	Settings.set_calibration_samples(empty)
	Settings.set_calibration_offset_ms(0.0)
	offset_applied.emit(0.0)
	close()
	return 0.0


func cancel() -> void:
	close()


func get_state() -> int:
	return _state


func get_sample_count() -> int:
	return _samples.size()


func get_samples_ms() -> Array[float]:
	var copy: Array[float] = []
	copy.assign(_samples)
	return copy


func get_result_ms() -> float:
	return _result_ms


func get_session_bpm() -> int:
	return _session_bpm


func is_apply_enabled() -> bool:
	return not _apply_button.disabled


## Song time used for the next tap: compensated audio clock, or a monotonic fallback.
func current_song_time() -> float:
	if _click_player.playing:
		var t := (
			_click_player.get_playback_position()
			+ AudioServer.get_time_since_last_mix()
			- AudioServer.get_output_latency()
		)
		return maxf(t, 0.0)
	var elapsed := float(Time.get_ticks_usec() - _free_run_start_us) / 1000000.0
	return maxf(elapsed, 0.0)


## Advances the countdown/window without waiting for real frames. Used by tests.
func advance_time(seconds: float) -> void:
	if seconds > 0.0:
		_advance(seconds)


func _advance(delta: float) -> void:
	match _state:
		State.COUNTDOWN:
			_countdown_left -= delta
			if _countdown_left <= 0.0:
				_begin_tapping()
			else:
				_refresh_labels()
		State.TAPPING:
			_elapsed += delta
			if _elapsed >= Config.CALIBRATION_DURATION_S:
				finish_session()
			else:
				_refresh_labels()
		_:
			pass


func _begin_tapping() -> void:
	_state = State.TAPPING
	_elapsed = 0.0
	_samples.clear()
	_result_ms = 0.0
	_free_run_start_us = Time.get_ticks_usec()
	if _click_player.stream != null:
		_click_player.play()
	_apply_button.disabled = true
	_refresh_labels()


func _load_click_track() -> void:
	var path := BeatConductor.click_track_path(_session_bpm)
	if not ResourceLoader.exists(path):
		_click_player.stream = null
		return
	_click_player.stream = load(path) as AudioStream


func _stop_click() -> void:
	if _click_player.playing:
		_click_player.stop()


func _valid_bpm(p_bpm: int) -> int:
	if p_bpm > 0 and Config.PHASE_BPM.has(p_bpm):
		return p_bpm
	return BPM_FALLBACK


func _refresh_labels() -> void:
	match _state:
		State.IDLE:
			_countdown_label.text = ""
			_stats_label.text = ""
			_result_label.text = ""
		State.COUNTDOWN:
			_countdown_label.text = str(maxi(1, int(ceil(_countdown_left))))
			_stats_label.text = "Get ready: %d BPM" % _session_bpm
			_result_label.text = ""
		State.TAPPING:
			_countdown_label.text = "TAP!"
			_stats_label.text = ("Taps: %d    %.1f s left" % [_samples.size(), _remaining_s()])
			_result_label.text = _live_median_text()
		State.DONE:
			_countdown_label.text = "DONE"
			_stats_label.text = "Taps: %d" % _samples.size()
			_result_label.text = _result_text()
	_status_label.text = DONE_TEXT if _state == State.DONE else INTRO_TEXT


func _remaining_s() -> float:
	return maxf(Config.CALIBRATION_DURATION_S - _elapsed, 0.0)


func _live_median_text() -> String:
	if _samples.is_empty():
		return "Median: —"
	return "Median: %+.1f ms" % CalibrationMath.median(_samples)


func _result_text() -> String:
	if not CalibrationMath.has_enough_samples(_samples):
		return "Need at least %d taps" % MIN_TAPS
	var outliers := _samples.size() - CalibrationMath.reject_outliers(_samples).size()
	return "Median: %+.1f ms    (%d taps, %d outlier)" % [_result_ms, _samples.size(), outliers]


func _on_apply_pressed() -> void:
	apply_result()


func _on_reset_pressed() -> void:
	reset_calibration()


func _on_cancel_pressed() -> void:
	cancel()

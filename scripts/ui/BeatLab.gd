class_name BeatLab
extends Control
## Dev scene for M1: metronome tempos, the rhythm overlay and the calibration wizard.
##
## Keys: 1-4 pick the phase tempo and play its click track, SPACE starts/stops,
## C opens calibration, R restarts the current tempo. F3 (toggle_debug) flips the overlay.
## It uses the existing BeatConductor autoload, so no autoload changes are required.

const BPM_KEYS: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4]
const STATUS_IDLE := "Stopped — press 1-4 to start a click track"
const HINT_TEXT := "1-4 tempo · SPACE start/stop · C calibration · R restart · F3 overlay"

var _bpm := Config.PHASE_BPM[0]
var _was_playing_before_calibration := false

@onready var _status_label: Label = %StatusLabel
@onready var _overlay: DebugOverlay = %DebugOverlay
@onready var _modal: CalibrationModal = %CalibrationModal


func _ready() -> void:
	if not _overlay.visible:
		_overlay.toggle_debug()
	_modal.closed.connect(_on_calibration_closed)
	_update_status(STATUS_IDLE)


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var key := key_event.keycode
	if key == KEY_ESCAPE and _modal.visible:
		_modal.cancel()
		get_viewport().set_input_as_handled()
		return
	if _modal.visible:
		return
	for index in range(BPM_KEYS.size()):
		if key == BPM_KEYS[index]:
			select_bpm(index)
			get_viewport().set_input_as_handled()
			return
	match key:
		KEY_SPACE:
			toggle_playback()
			get_viewport().set_input_as_handled()
		KEY_C:
			open_calibration()
			get_viewport().set_input_as_handled()
		KEY_R:
			select_bpm(_bpm_index())
			get_viewport().set_input_as_handled()
		_:
			pass


## Picks a phase tempo (0-3) and plays its generated click track.
func select_bpm(index: int) -> void:
	var safe_index := clampi(index, 0, Config.PHASE_BPM.size() - 1)
	_bpm = Config.PHASE_BPM[safe_index]
	var path := BeatConductor.click_track_path(_bpm)
	if ResourceLoader.exists(path):
		BeatConductor.set_stream(load(path) as AudioStream, 0.0)
	else:
		BeatConductor.set_stream(null, 0.0)
	if BeatConductor.is_playing:
		BeatConductor.set_bpm(_bpm)
	else:
		BeatConductor.start(_bpm)
	_update_status("Playing %d BPM — %s" % [_bpm, path.get_file()])


func toggle_playback() -> void:
	if BeatConductor.is_playing:
		BeatConductor.stop()
		_update_status(STATUS_IDLE)
	else:
		select_bpm(_bpm_index())


func open_calibration() -> void:
	if _modal.visible:
		return
	_was_playing_before_calibration = BeatConductor.is_playing
	if BeatConductor.is_playing:
		BeatConductor.stop()
	_modal.open(_bpm)
	_update_status("Calibrating at %d BPM" % _bpm)


func get_bpm() -> int:
	return _bpm


func get_overlay() -> DebugOverlay:
	return _overlay


func get_modal() -> CalibrationModal:
	return _modal


func _bpm_index() -> int:
	var index := Config.PHASE_BPM.find(_bpm)
	return 0 if index < 0 else index


func _update_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _on_calibration_closed() -> void:
	if _was_playing_before_calibration:
		_was_playing_before_calibration = false
		select_bpm(_bpm_index())
	else:
		_update_status("Calibration closed — press 1-4 to play a click track")

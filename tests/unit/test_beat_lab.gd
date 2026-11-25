extends GutTest
## BeatLab dev scene: overlay wiring, tempo keys, playback and calibration hand-off.

var _lab: BeatLab
var _overlay: DebugOverlay
var _modal: CalibrationModal


func before_each() -> void:
	BeatConductor.stop()
	_lab = preload("res://scenes/dev/BeatLab.tscn").instantiate()
	add_child_autofree(_lab)
	_overlay = _lab.get_overlay()
	_modal = _lab.get_modal()


func after_each() -> void:
	BeatConductor.stop()


func test_scene_builds_with_overlay_and_modal() -> void:
	assert_not_null(_overlay)
	assert_not_null(_modal)
	assert_true(_overlay.visible, "the overlay starts visible in the dev scene")
	assert_false(_modal.visible)
	assert_eq(_lab.get_bpm(), Config.PHASE_BPM[0])


func test_every_tempo_key_selects_its_phase_bpm() -> void:
	for index in range(Config.PHASE_BPM.size()):
		var event := InputEventKey.new()
		event.pressed = true
		event.keycode = [KEY_1, KEY_2, KEY_3, KEY_4][index]
		_lab._unhandled_input(event)
		assert_eq(_lab.get_bpm(), Config.PHASE_BPM[index])
		assert_eq(BeatConductor.bpm, Config.PHASE_BPM[index])
		assert_true(BeatConductor.is_playing)


func test_select_bpm_plays_the_matching_click_track() -> void:
	_lab.select_bpm(3)
	assert_eq(_lab.get_bpm(), 142)
	assert_eq(BeatConductor.bpm, 142)
	assert_true(BeatConductor.is_playing)
	var player := BeatConductor.get_node("AudioStreamPlayer") as AudioStreamPlayer
	assert_not_null(player.stream)
	assert_eq(player.stream.resource_path, BeatConductor.click_track_path(142))


func test_space_toggles_playback() -> void:
	_lab.select_bpm(0)
	assert_true(BeatConductor.is_playing)
	_lab.toggle_playback()
	assert_false(BeatConductor.is_playing)
	_lab.toggle_playback()
	assert_true(BeatConductor.is_playing)


func test_calibration_stops_the_click_then_resumes_on_close() -> void:
	_lab.select_bpm(1)
	assert_true(BeatConductor.is_playing)
	_lab.open_calibration()
	assert_false(BeatConductor.is_playing, "one click source at a time")
	assert_true(_modal.visible)
	assert_eq(_modal.get_session_bpm(), 118)
	_modal.cancel()
	assert_false(_modal.visible)
	assert_true(BeatConductor.is_playing, "playback resumes after calibration closes")


func test_overlay_and_modal_are_children_of_the_scene() -> void:
	assert_eq(_lab.get_node("%DebugOverlay"), _overlay)
	assert_eq(_lab.get_node("%CalibrationModal"), _modal)

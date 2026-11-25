extends GutTest
## DebugOverlay: scene wiring, toggle, live Δt and grade colour mapping.

var _overlay: DebugOverlay


func before_each() -> void:
	BeatConductor.stop()
	_overlay = preload("res://scenes/ui/DebugOverlay.tscn").instantiate()
	add_child_autofree(_overlay)


func after_each() -> void:
	BeatConductor.stop()


func test_scene_is_a_control_with_the_overlay_script() -> void:
	assert_true(_overlay is Control)
	assert_eq(_overlay.get_script(), preload("res://scripts/ui/DebugOverlay.gd"))


func test_overlay_finds_the_autoloaded_conductor() -> void:
	assert_not_null(_overlay.conductor, "dev scene needs no autoload changes")
	assert_eq(_overlay.conductor, BeatConductor)


func test_overlay_starts_hidden_and_toggles() -> void:
	assert_false(_overlay.visible)
	_overlay.toggle_debug()
	assert_true(_overlay.visible)
	assert_true(_overlay.is_processing())
	_overlay.toggle_debug()
	assert_false(_overlay.visible)
	assert_false(_overlay.is_processing())


func test_refresh_reports_song_time_beat_and_delta() -> void:
	BeatConductor.start(120)
	BeatConductor.advance_clock(0.52)
	var state := _overlay.refresh()
	assert_almost_eq(state["song_time"], 0.52, 0.000001)
	assert_eq(state["bpm"], 120)
	assert_eq(state["beat"], 1)
	assert_eq(state["measure"], 0)
	assert_almost_eq(state["delta_ms"], 20.0, 0.01, "0.52 s is 20 ms past beat 1")
	assert_almost_eq(_overlay.get_signed_delta_ms(), 20.0, 0.01)


func test_refresh_reports_the_stem_offset() -> void:
	BeatConductor.set_stream(null, 0.25)
	_overlay.refresh()
	assert_almost_eq(_overlay.refresh()["stem_offset_ms"], 250.0, 0.001)
	BeatConductor.set_stream(null, 0.0)


func test_signed_delta_is_negative_before_the_beat() -> void:
	BeatConductor.start(120)
	BeatConductor.advance_clock(0.48)
	_overlay.refresh()
	assert_almost_eq(_overlay.get_signed_delta_ms(), -20.0, 0.01)


func test_grade_colours_match_the_palette() -> void:
	assert_eq(DebugOverlay.color_for_grade(RhythmEvaluator.Grade.PERFECT), Color("#E040FB"))
	assert_eq(DebugOverlay.color_for_grade(RhythmEvaluator.Grade.GOOD), Color("#19E3D1"))
	assert_eq(DebugOverlay.color_for_grade(RhythmEvaluator.Grade.MISS), Color("#FF7A1A"))
	assert_ne(DebugOverlay.color_for_grade(RhythmEvaluator.Grade.PERFECT), DebugOverlay.GOOD_COLOR)


func test_report_grade_survives_refresh() -> void:
	BeatConductor.start(120)
	_overlay.refresh()
	_overlay.report_grade(RhythmEvaluator.Grade.GOOD)
	_overlay.refresh()
	assert_eq(_overlay.get_display_grade(), RhythmEvaluator.Grade.GOOD)


func test_set_conductor_reconnects_without_errors() -> void:
	var replacement := Node.new()
	add_child_autofree(replacement)
	_overlay.set_conductor(replacement)
	assert_eq(_overlay.conductor, replacement)
	_overlay.set_conductor(BeatConductor)
	assert_eq(_overlay.conductor, BeatConductor)


func test_beat_signal_resets_the_flash_timer() -> void:
	_overlay.toggle_debug()
	BeatConductor.start(120)
	BeatConductor.advance_clock(0.5)
	_overlay.refresh()
	assert_eq(_overlay.get_display_grade(), RhythmEvaluator.Grade.PERFECT)

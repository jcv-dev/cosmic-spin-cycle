extends GutTest
## HUD is the only player-facing surface in M3; verify it binds state and clock correctly.

const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")


func before_each() -> void:
	GameState.reset(99)


func test_hud_builds_and_formats_clock() -> void:
	var hud := HUD_SCENE.instantiate() as Control
	add_child_autofree(hud)
	hud.set_shift_time(270.0)
	assert_eq(hud.clock_text(), "03:22")
	assert_not_null(hud.get_node_or_null("ClockLabel"))
	assert_eq(hud.get_node("ClockLabel").text, "03:22")


func test_hud_reflects_game_state() -> void:
	var hud := HUD_SCENE.instantiate() as Control
	add_child_autofree(hud)
	GameState.add_score(1250)
	GameState.add_stability(-50.0)
	GameState.register_grade(RhythmEvaluator.Grade.PERFECT)
	assert_eq(hud.get_node("ScoreLabel").text, "001250")
	assert_eq(hud.get_node("ComboLabel").text, "×3")


func test_hud_grade_and_phase_text() -> void:
	var hud := HUD_SCENE.instantiate() as Control
	add_child_autofree(hud)
	hud.show_grade(RhythmEvaluator.Grade.PERFECT)
	assert_eq(hud.get_node("GradeLabel").text, "PERFECTO")
	hud.show_grade(RhythmEvaluator.Grade.MISS)
	assert_eq(hud.get_node("GradeLabel").text, "FUERA DE RITMO")
	hud.set_phase(2, 130)
	assert_string_contains(hud.get_node("PhaseLabel").text, "130 BPM")

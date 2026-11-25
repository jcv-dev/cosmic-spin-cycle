extends GutTest
## HUD contract: it binds shift state, formats the numbers and never shows the dead
## instruction strip (docs/HUD.md, docs/UX_BIBLE.md §5).

const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")


func before_each() -> void:
	GameState.reset(99)


func _open_hud() -> Control:
	var hud := HUD_SCENE.instantiate() as Control
	add_child_autofree(hud)
	return hud


func test_hud_builds_and_formats_clock() -> void:
	var hud := _open_hud()
	hud.set_shift_time(270.0)
	assert_eq(hud.clock_text(), "03:22")
	assert_not_null(hud.get_node_or_null("PlaqueA/ClockLabel"))
	assert_eq(hud.get_node("PlaqueA/ClockLabel").text, "03:22")


func test_hud_reflects_game_state() -> void:
	var hud := _open_hud()
	GameState.add_score(1250)
	GameState.add_stability(-50.0)
	GameState.register_grade(RhythmEvaluator.Grade.PERFECT)
	assert_eq(hud.get_node("PlaqueB/ScoreLabel").text, "001 250")
	assert_eq(hud.get_node("PlaqueB/ComboLabel").text, "×3")
	assert_eq(hud.get_node("PlaqueB/StabilityValue").text, "50")


func test_hud_grade_text_is_kept_for_tests_but_never_drawn() -> void:
	var hud := _open_hud()
	var grade_label := hud.get_node("GradeLabel") as Label
	assert_false(grade_label.visible, "grades are world-space now, not a centred label")
	hud.show_grade(RhythmEvaluator.Grade.PERFECT)
	assert_eq(grade_label.text, "PERFECTO")
	hud.show_grade(RhythmEvaluator.Grade.MISS)
	assert_eq(grade_label.text, "FUERA DE RITMO")
	assert_false(grade_label.visible)


func test_hud_phase_caption_replaces_phase_number_with_the_name() -> void:
	var hud := _open_hud()
	hud.set_phase(2, 130)
	assert_eq(hud.get_node("PlaqueA/BpmLabel").text, "130 BPM")
	assert_string_contains(hud.readout()["caption"], "FASE 3")
	assert_string_contains(hud.readout()["caption"], "MAREJADA")
	hud.tick(5.0)
	assert_eq(hud.readout()["caption"], "TURNO · FASE 3", "the phase name is a 4 s announcement")


func test_hud_clock_warns_in_the_last_ten_seconds() -> void:
	var hud := _open_hud()
	hud.set_shift_time(Config.SHIFT_DURATION_S - 20.0)
	var calm: Color = hud.get_node("PlaqueA/ClockLabel").get_theme_color("font_color")
	hud.set_shift_time(Config.SHIFT_DURATION_S - 5.0)
	var warn: Color = hud.get_node("PlaqueA/ClockLabel").get_theme_color("font_color")
	assert_eq(calm, Palette.METAL_4)
	assert_eq(warn, Palette.YEL_3)

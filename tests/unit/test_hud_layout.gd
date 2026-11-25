extends GutTest
## HUD layout contract: exact plaque rects, the deleted instruction strip, colour bands and
## number formatting (docs/UX_BIBLE.md §5, docs/HUD.md).

const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")
const OLD_HINT_FRAGMENTS := ["WASD", "ratón", "raton", "ESPACIO agarrar", "leyenda"]


func before_each() -> void:
	GameState.reset(7)


func _open_hud() -> Control:
	var hud := HUD_SCENE.instantiate() as Control
	add_child_autofree(hud)
	return hud


func _all_text(node: Node, out: Array[String]) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for child in node.get_children():
		_all_text(child, out)


func test_plaques_sit_at_the_exact_rects() -> void:
	var hud := _open_hud()
	assert_eq(hud.plaque_rect("PlaqueA"), Rect2(0, 0, 312, 104))
	assert_eq(hud.plaque_rect("PlaqueB"), Rect2(968, 0, 312, 104))


func test_play_field_is_clear_of_hud_controls() -> void:
	var hud := _open_hud()
	var field := Rect2(104, 108, 1176 - 104, 612 - 108)
	for control in hud.find_children("*", "Control", true, false):
		var box := control as Control
		if box.get_parent() == hud and box.name == "GradeLabel":
			continue
		if not box.visible:
			continue
		var rect := Rect2(box.global_position, box.size * box.scale)
		assert_false(
			rect.intersects(field) and rect.size.x > 8.0,
			"%s intrudes into the play field" % box.name
		)


func test_the_instruction_strip_is_gone() -> void:
	var hud := _open_hud()
	assert_null(hud.find_child("HintLabel", true, false), "no instruction strip node may exist")
	var texts: Array[String] = []
	_all_text(hud, texts)
	for text in texts:
		for fragment in OLD_HINT_FRAGMENTS:
			assert_false(
				text.to_lower().contains(fragment.to_lower()),
				"leftover control legend in %s: %s" % [hud.name, text]
			)


func test_stability_colour_bands() -> void:
	var hud := _open_hud()
	assert_eq(hud.stability_color(), Palette.CLEAN_GREEN, "100 % is clean")
	GameState.add_stability(-39.0)
	assert_eq(hud.stability_color(), Palette.CLEAN_GREEN, "61 % is still clean")
	GameState.add_stability(-1.0)
	assert_eq(hud.stability_color(), Palette.YEL_2, "60 % is caution")
	GameState.add_stability(-25.0)
	assert_eq(hud.stability_color(), Palette.YEL_2, "35 % is still caution")
	GameState.add_stability(-0.5)
	assert_eq(hud.stability_color(), Palette.HAZARD_ORANGE, "34.5 % is hazard")


func test_stability_keeps_a_number_and_a_glyph() -> void:
	var hud := _open_hud()
	GameState.add_stability(-78.0)
	assert_eq(hud.stability_text(), "22")
	# The diamond is drawn, not a Label: assert the colour channel redundancy exists.
	assert_true(hud.has_method("draw_slot"))


func test_combo_and_score_formatting() -> void:
	var hud := _open_hud()
	assert_eq(hud.combo_text(), "×1")
	GameState.add_score(1240)
	assert_eq(hud.score_text(), "001 240")
	GameState.add_score(9)
	assert_eq(hud.score_text(), "001 249")


func test_combo_turns_magenta_at_four() -> void:
	var hud := _open_hud()
	GameState.combo = 3
	GameState.combo_changed.emit(3)
	var calm: Color = hud.get_node("PlaqueB/ComboLabel").get_theme_color("font_color")
	GameState.combo = 4
	GameState.combo_changed.emit(4)
	var hot: Color = hud.get_node("PlaqueB/ComboLabel").get_theme_color("font_color")
	assert_eq(calm, Palette.METAL_3)
	assert_eq(hot, Palette.FUNK_MAGENTA)


func test_mission_ribbon_default_and_fade() -> void:
	var hud := _open_hud()
	assert_eq(hud.objective_text(), "OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00")
	assert_almost_eq(hud.objective_alpha(), 1.0, 0.001, "fresh objective shouts")
	hud.tick(7.9)
	assert_almost_eq(hud.objective_alpha(), 1.0, 0.001, "still 100 % before 8 s")
	hud.tick(1.1)
	assert_almost_eq(hud.objective_alpha(), 0.55, 0.001, "settles to 55 % and stays")
	assert_eq(hud.objective_text(), "OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00")
	hud.set_objective("LLEVA LA PIEZA LIMPIA AL DUCTO")
	assert_almost_eq(hud.objective_alpha(), 1.0, 0.001, "a new objective re-shouts")


func test_objective_is_capped_at_46_characters() -> void:
	var hud := _open_hud()
	hud.set_objective("X".repeat(80))
	assert_eq(hud.objective_text().length(), 46)


func test_feedback_is_one_toast_not_a_log() -> void:
	var hud := _open_hud()
	assert_eq(hud.toast_text(), "", "no toast before any feedback")
	GameState.emit_feedback("+350", &"success")
	assert_eq(hud.toast_text(), "+350")
	assert_eq(hud.get_node("ToastLabel").get_theme_color("font_color"), Palette.CLEAN_GREEN)
	GameState.emit_feedback("LAVADORA EQUIVOCADA", &"danger")
	assert_eq(hud.toast_text(), "LAVADORA EQUIVOCADA", "the newest toast replaces the old one")
	assert_eq(hud.get_node("ToastLabel").get_theme_color("font_color"), Palette.HAZARD_ORANGE)
	hud.tick(1.5)
	assert_eq(hud.toast_text(), "", "the toast expires after 1.4 s")

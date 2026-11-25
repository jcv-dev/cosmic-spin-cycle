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
	assert_eq(hud.plaque_rect("PlaqueA"), Rect2(0, 0, 300, 86))
	assert_eq(hud.plaque_rect("PlaqueB"), Rect2(980, 0, 300, 86))


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
	assert_eq(hud.readout()["stability"], "22")
	# Colour is not the only channel: the number stays, and the value text carries the band
	# colour while the paint slot draws the matching diamond.
	assert_eq(
		hud.get_node("PlaqueB/StabilityValue").get_theme_color("font_color"), Palette.HAZARD_ORANGE
	)


func test_combo_and_score_formatting() -> void:
	var hud := _open_hud()
	assert_eq(hud.readout()["combo"], "×1")
	GameState.add_score(1240)
	assert_eq(hud.readout()["score"], "001 240")
	GameState.add_score(9)
	assert_eq(hud.readout()["score"], "001 249")


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
	assert_eq(hud.readout()["objective"], "OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00")
	assert_almost_eq(hud.readout()["objective_alpha"], 1.0, 0.001, "fresh objective shouts")
	hud.tick(7.9)
	assert_almost_eq(hud.readout()["objective_alpha"], 1.0, 0.001, "still 100 % before 8 s")
	hud.tick(1.1)
	assert_almost_eq(hud.readout()["objective_alpha"], 0.55, 0.001, "settles to 55 % and stays")
	assert_eq(hud.readout()["objective"], "OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00")
	hud.set_objective("LLEVA LA PIEZA LIMPIA AL DUCTO")
	assert_almost_eq(hud.readout()["objective_alpha"], 1.0, 0.001, "a new objective re-shouts")


func test_objective_is_capped_at_46_characters() -> void:
	var hud := _open_hud()
	hud.set_objective("X".repeat(80))
	assert_eq(hud.readout()["objective"].length(), 46)


func test_feedback_is_one_toast_not_a_log() -> void:
	var hud := _open_hud()
	assert_eq(hud.readout()["toast"], "", "no toast before any feedback")
	GameState.emit_feedback("+350", &"success")
	assert_eq(hud.readout()["toast"], "+350")
	assert_eq(hud.get_node("ToastLabel").get_theme_color("font_color"), Palette.CLEAN_GREEN)
	GameState.emit_feedback("LAVADORA EQUIVOCADA", &"danger")
	assert_eq(
		hud.readout()["toast"], "LAVADORA EQUIVOCADA", "the newest toast replaces the old one"
	)
	assert_eq(hud.get_node("ToastLabel").get_theme_color("font_color"), Palette.HAZARD_ORANGE)
	hud.tick(1.5)
	assert_eq(hud.readout()["toast"], "", "the toast expires after 1.4 s")


func test_reward_float_lives_near_plaque_b_and_expires() -> void:
	Settings.reduce_motion = false
	var hud := _open_hud()
	assert_eq(hud.readout()["reward"], "")
	hud.flash_reward(350)
	assert_eq(hud.readout()["reward"], "+350")
	var start: Vector2 = hud.get_node("RewardFloat").position
	hud.tick(0.3)
	assert_true(hud.get_node("RewardFloat").position.y < start.y, "the reward floats upward")
	hud.tick(0.4)
	assert_eq(hud.readout()["reward"], "", "the reward expires after 600 ms")


func test_reward_float_does_not_move_under_reduce_motion() -> void:
	Settings.reduce_motion = true
	var hud := _open_hud()
	hud.flash_reward(120)
	var start: Vector2 = hud.get_node("RewardFloat").position
	hud.tick(0.3)
	assert_eq(hud.get_node("RewardFloat").position, start, "reduce motion keeps it static")
	assert_eq(hud.readout()["reward"], "+120", "the number is still readable")
	Settings.reduce_motion = false


func test_danger_flag_pulses_but_is_readable_statically() -> void:
	Settings.reduce_motion = true
	var hud := _open_hud()
	assert_false(hud.danger)
	hud.set_danger(true)
	assert_true(hud.danger)
	Settings.reduce_motion = false


func test_tutorial_mode_hides_tempo_and_score_but_keeps_stability() -> void:
	var hud := _open_hud()
	hud.set_tutorial_mode(true)
	var state: Dictionary = hud.readout()
	assert_false(state["bpm_visible"], "tempo is noise while learning")
	assert_false(state["score_visible"], "score is noise while learning")
	assert_true(state["stability_visible"], "stability teaches the fail state")


func test_tutorial_step_replaces_the_clock() -> void:
	var hud := _open_hud()
	hud.set_shift_time(270.0)
	hud.set_tutorial_mode(true)
	assert_eq(hud.readout()["clock"], "03:22", "no step yet: the fail-safe keeps the clock")
	hud.set_step(2, 7)
	assert_eq(hud.readout()["clock"], "PASO 2/7")
	hud.set_tutorial_mode(false)
	assert_eq(hud.readout()["clock"], "03:22", "leaving the tutorial restores the clock")
	assert_true(hud.readout()["bpm_visible"])
	assert_true(hud.readout()["score_visible"])


func test_hud_scale_scales_only_the_plaques() -> void:
	var hud := _open_hud()
	assert_almost_eq(hud.scale_factor(), 1.0, 0.001)
	Settings.ui_scale = 1.25
	Settings.settings_changed.emit()
	assert_almost_eq(hud.scale_factor(), 1.25, 0.001)
	assert_eq(hud.get_node("PlaqueA").pivot_offset, Vector2.ZERO, "plaque A grows from the corner")
	assert_eq(
		hud.get_node("PlaqueB").pivot_offset,
		Vector2(300, 0),
		"plaque B grows toward the field, never off-screen"
	)
	assert_eq(hud.get_node("Ribbon").scale, Vector2.ONE, "the ribbon never scales")
	Settings.ui_scale = 1.0
	Settings.settings_changed.emit()


func test_hud_scale_is_clamped_to_the_offered_options() -> void:
	var hud := _open_hud()
	hud.set_hud_scale(4.0)
	assert_almost_eq(hud.scale_factor(), 1.25, 0.001)
	hud.set_hud_scale(0.1)
	assert_almost_eq(hud.scale_factor(), 1.0, 0.001)


func test_the_toast_may_dip_into_the_field_but_never_past_128_px() -> void:
	# The only transient that enters the play field: it hangs under the ribbon, clear of the
	# north belt lane, and stops 20 px into the field's top edge (docs/HUD.md §1.4).
	var hud := _open_hud()
	assert_false(hud.get_node("ToastLabel").visible, "no toast at rest")
	GameState.emit_feedback("PIEZA PERDIDA", &"danger")
	var toast := hud.get_node("ToastLabel") as Label
	assert_true(toast.visible)
	assert_gte(toast.position.y, 100.0, "never over the belt lane")
	assert_lte(toast.position.y + toast.size.y, 128.0, "never deeper than 20 px into the field")

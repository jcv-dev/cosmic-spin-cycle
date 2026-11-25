extends GutTest
## End screen contract (§12.5): `setup()` fills the screen, the four ranks each get their
## own colour, the ledger formats the numbers and every button emits its intent.

const END_SCENE := preload("res://scenes/ui/EndScreen.tscn")
const CONTRACT_SIGNALS := ["retry_requested", "menu_requested", "new_seed_requested"]

var _screen: Control


func before_each() -> void:
	Settings.reset_to_defaults()


func after_each() -> void:
	Settings.reset_to_defaults()
	Settings.db_seed = 0


func _open(result: Dictionary) -> Control:
	_screen = END_SCENE.instantiate() as Control
	_screen.call("setup", result)
	add_child_autofree(_screen)
	await wait_process_frames(2)
	return _screen


func _result(overrides: Dictionary = {}) -> Dictionary:
	var result := {
		"victory": true,
		"reason": "shift_complete",
		"score": 18450,
		"accuracy": 0.93,
		"perfect": 64,
		"good": 12,
		"miss": 5,
		"max_combo": 7,
		"delivered": 41,
		"washed": 58,
		"exploded": 1,
		"seed": 7001,
		"rank": "S",
	}
	result.merge(overrides, true)
	return result


func test_declares_every_contract_signal() -> void:
	await _open(_result())
	for signal_name in CONTRACT_SIGNALS:
		assert_true(_screen.has_signal(signal_name), "missing signal %s" % signal_name)


func test_plaque_is_720x560_and_centred() -> void:
	await _open(_result())
	var plaque := _screen.get_node("Plaque") as Panel
	assert_eq(plaque.size, Vector2(720, 560))
	assert_eq(plaque.position, Vector2(280, 80))


func test_victory_verdict_is_green_and_states_the_reason() -> void:
	await _open(_result())
	var verdict := _screen.get_node("Plaque/Verdict") as Label
	assert_eq(verdict.text, "TURNO COMPLETADO")
	assert_eq(verdict.get_theme_color("font_color"), Palette.CLEAN_GREEN)
	assert_string_contains(_screen.get_node("Plaque/Reason").text, "06:00")


func test_defeat_verdict_is_orange_and_forces_rank_c() -> void:
	await _open(_result({"victory": false, "reason": "stability", "rank": "S"}))
	var verdict := _screen.get_node("Plaque/Verdict") as Label
	assert_eq(verdict.text, "DESGARRO UNIVERSAL")
	assert_eq(verdict.get_theme_color("font_color"), Palette.HAZARD_ORANGE)
	assert_eq((_screen.get_node("Plaque/Rank") as Label).text, "C")


func test_every_rank_letter_uses_its_colour() -> void:
	var expected := {
		"S": Palette.FUNK_MAGENTA,
		"A": Palette.FUNK_CYAN,
		"B": Palette.METAL_3,
		"C": Palette.METAL_1,
	}
	for rank in expected:
		var screen := END_SCENE.instantiate() as Control
		screen.call("setup", _result({"rank": rank}))
		add_child_autofree(screen)
		await wait_process_frames(1)
		var label := screen.get_node("Plaque/Rank") as Label
		assert_eq(label.text, rank)
		assert_eq(label.get_theme_color("font_color"), expected[rank], "rank %s colour" % rank)


func test_ledger_formats_score_accuracy_combo_and_seed() -> void:
	await _open(_result())
	var plaque := _screen.get_node("Plaque")
	assert_eq((plaque.get_node("Stat0Value") as Label).text, "58")
	assert_eq((plaque.get_node("Stat1Value") as Label).text, "41")
	assert_eq((plaque.get_node("Stat2Value") as Label).text, "93/100")
	assert_eq((plaque.get_node("Stat3Value") as Label).text, "×7")
	assert_eq((plaque.get_node("Stat4Value") as Label).text, "18 450")
	assert_eq((plaque.get_node("Stat5Value") as Label).text, "#07001")


func test_ledger_captions_are_the_six_contract_stats() -> void:
	await _open(_result())
	var plaque := _screen.get_node("Plaque")
	var captions: Array[String] = []
	for index in range(6):
		captions.append((plaque.get_node("Stat%dCaption" % index) as Label).text)
	assert_eq(captions, ["LAVADAS", "ENTREGADAS", "PRECISIÓN", "COMBO MÁX", "PUNTOS", "SEMILLA"])


func test_four_primary_stats_are_bigger_than_the_secondary_pair() -> void:
	await _open(_result())
	var plaque := _screen.get_node("Plaque")
	for index in [0, 2, 3, 4]:
		var label := plaque.get_node("Stat%dValue" % index) as Label
		assert_eq(
			label.get_theme_font_size("font_size"),
			UITheme.FONT_H1,
			"primary stat %d uses the headline size" % index
		)
	for index in [1, 5]:
		var label := plaque.get_node("Stat%dValue" % index) as Label
		assert_eq(
			label.get_theme_font_size("font_size"),
			UITheme.FONT_LABEL,
			"secondary stat %d uses the label size" % index
		)
		assert_lt(
			label.get_theme_font_size("font_size"),
			UITheme.FONT_H1,
			"secondary stat %d is never as loud as a primary one" % index
		)


func test_secondary_stats_sit_inline_with_their_caption() -> void:
	await _open(_result())
	var plaque := _screen.get_node("Plaque")
	var caption := plaque.get_node("Stat5Caption") as Label
	var value := plaque.get_node("Stat5Value") as Label
	assert_gt(value.position.x, caption.position.x + 40.0, "SEMILLA and its value share a line")
	assert_eq(value.position.y, caption.position.y)


func test_buttons_carry_the_measured_ring() -> void:
	await _open(_result())
	for name in ["RetryButton", "MenuButton", "NewSeedButton"]:
		var button := _screen.get_node("Plaque/%s" % name) as Button
		assert_not_null(button.get_node_or_null("FocusRing"), "%s needs a focus ring" % name)
		var box := button.get_theme_stylebox("normal") as StyleBoxFlat
		assert_eq(box.border_color, Palette.METAL_1, "%s border must clear 3:1" % name)


func test_no_text_below_the_type_floor() -> void:
	await _open(_result())
	assert_gte(_min_font_size(_screen), 12, "no player-facing text below 12 px")


func test_rhythm_line_reports_grades() -> void:
	await _open(_result())
	var rhythm := _screen.get_node("Plaque/Rhythm") as Label
	assert_string_contains(rhythm.text, "PERFECTOS 64")
	assert_string_contains(rhythm.text, "FALLOS 5")


func test_default_focus_is_retry() -> void:
	await _open(_result())
	_screen.focus_first()
	await wait_process_frames(1)
	assert_true((_screen.get_node("Plaque/RetryButton") as Button).has_focus())


func test_each_button_emits_its_intent() -> void:
	await _open(_result())
	watch_signals(_screen)
	for index in range(3):
		var names := ["RetryButton", "MenuButton", "NewSeedButton"]
		var button := _screen.get_node("Plaque/%s" % names[index]) as Button
		assert_not_null(button, "missing %s" % names[index])
		button.emit_signal("pressed")
		assert_signal_emitted(_screen, CONTRACT_SIGNALS[index])


func test_buttons_are_the_contract_labels() -> void:
	await _open(_result())
	var plaque := _screen.get_node("Plaque")
	assert_eq((plaque.get_node("RetryButton") as Button).text, "REPETIR")
	assert_eq((plaque.get_node("MenuButton") as Button).text, "MENÚ")
	assert_eq((plaque.get_node("NewSeedButton") as Button).text, "NUEVA SEMILLA")


func test_rank_is_96px_and_skips_the_scale_in_with_reduce_motion() -> void:
	Settings.reduce_motion = true
	await _open(_result())
	var rank := _screen.get_node("Plaque/Rank") as Label
	assert_eq(rank.get_theme_font_size("font_size"), 96, "rank sits in the 48-96 px band")
	assert_eq(rank.scale, Vector2.ONE, "reduce motion must skip the 240 ms scale-in")


func test_escape_returns_to_the_menu() -> void:
	await _open(_result())
	watch_signals(_screen)
	_screen.cancel()
	assert_signal_emitted(_screen, "menu_requested")


func test_score_grouping_matches_the_title_screen() -> void:
	assert_eq(END_SCENE.instantiate()._format_score(12500), "12 500")


## Walks the screen and returns the smallest font size in use (UX_RESEARCH §9: floor 12 px).
func _min_font_size(node: Node) -> int:
	var smallest := 999
	if node is Label or node is Button:
		smallest = mini(smallest, (node as Control).get_theme_font_size("font_size"))
	for child in node.get_children():
		smallest = mini(smallest, _min_font_size(child))
	return smallest

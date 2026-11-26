extends GutTest
## Title screen contract (docs/UX_BIBLE.md §12.1): the six intent signals, the focus
## order, the record plaque rule ("never invent data") and the never-black backdrop.

const TITLE_SCENE := preload("res://scenes/ui/TitleScreen.tscn")
const CONTRACT_SIGNALS := [
	"start_requested",
	"tutorial_requested",
	"calibration_requested",
	"records_requested",
	"options_requested",
	"quit_requested",
]
const ROW_NAMES := [
	"StartButton",
	"TutorialButton",
	"CalibrationButton",
	"RecordsButton",
	"OptionsButton",
	"QuitButton",
]

var _screen: Control


func _row(index: int) -> Button:
	return _screen.find_child(ROW_NAMES[index], true, false) as Button


func before_each() -> void:
	Settings.reset_to_defaults()
	Settings.db_seed = 0
	_screen = TITLE_SCENE.instantiate() as Control
	add_child_autofree(_screen)
	await wait_process_frames(2)


func after_each() -> void:
	Settings.reset_to_defaults()
	Settings.db_seed = 0


func test_declares_every_contract_signal() -> void:
	for signal_name in CONTRACT_SIGNALS:
		assert_true(_screen.has_signal(signal_name), "missing signal %s" % signal_name)


func test_focus_first_lands_on_start() -> void:
	_screen.focus_first()
	await wait_process_frames(1)
	var start := _row(0)
	assert_true(start.has_focus(), "INICIAR TURNO must own the default focus")


func test_each_row_emits_its_intent() -> void:
	watch_signals(_screen)
	for index in range(ROW_NAMES.size()):
		var row := _row(index)
		assert_not_null(row, "row %s missing" % ROW_NAMES[index])
		row.emit_signal("pressed")
		assert_signal_emitted(_screen, CONTRACT_SIGNALS[index])


func test_escape_lands_on_quit_without_quitting() -> void:
	_screen.focus_first()
	await wait_process_frames(1)
	_screen.focus_quit()
	await wait_process_frames(1)
	var quit_row := _row(5)
	assert_true(quit_row.has_focus())


func test_record_plaque_is_hidden_without_a_run() -> void:
	Settings.best_score = 0
	Settings.best_rank = ""
	_screen._refresh_record()
	assert_null(_screen.get_node_or_null("RecordPlaque"), "no record must mean no plaque")


func test_record_plaque_shows_rank_and_grouped_score() -> void:
	Settings.best_score = 12480
	Settings.best_rank = "A"
	_screen._refresh_record()
	var plaque := _screen.get_node_or_null("RecordPlaque")
	assert_not_null(plaque, "a real run must show the plaque")
	assert_eq(plaque.get_node("BestRank").text, "A")
	assert_eq(plaque.get_node("BestScore").text, "12 480")


func test_menu_rows_are_the_six_contract_labels() -> void:
	var labels: Array[String] = []
	for index in range(ROW_NAMES.size()):
		labels.append(_row(index).text)
	assert_eq(
		labels,
		["INICIAR TURNO", "TUTORIAL", "CALIBRACIÓN DE AUDIO", "RÉCORDS", "OPCIONES", "SALIR"]
	)


func test_backdrop_is_a_room_not_a_black_screen() -> void:
	# Either the living diorama (preferred) or the static room plate; never black.
	var diorama := _screen.get_node_or_null("Diorama") as TextureRect
	if diorama != null:
		assert_not_null(diorama.texture, "the diorama viewport texture must exist")
		assert_eq(diorama.size, Vector2(1280, 720))
		assert_not_null(_screen.get_node_or_null("DioramaViewport"))
		return
	var room := _screen.get_node_or_null("Room") as TextureRect
	assert_not_null(room, "a backdrop must exist")
	assert_not_null(room.texture, "the room texture must load")
	assert_eq(room.size, Vector2(1280, 720))


func test_focus_neighbours_wrap_vertically() -> void:
	var first := _row(0)
	var last := _row(5)
	assert_eq(
		first.focus_neighbor_top, first.get_path_to(last), "↑ on the first row wraps to SALIR"
	)
	assert_eq(last.focus_neighbor_bottom, last.get_path_to(first), "↓ on SALIR wraps to the top")


func test_type_tiers_descend_from_primary_to_tertiary() -> void:
	var sizes: Array[int] = []
	for index in range(ROW_NAMES.size()):
		sizes.append(_row(index).get_theme_font_size("font_size"))
	assert_eq(sizes, [28, 20, 20, 16, 16, 16], "one primary, two secondary, three tertiary rows")


func test_focused_row_draws_the_measured_ring() -> void:
	_screen.focus_first()
	await wait_process_frames(1)
	var start := _row(0)
	var ring := start.get_node_or_null("FocusRing") as Control
	assert_not_null(ring, "every menu row owns a focus ring")
	assert_eq(
		ring.size,
		Vector2(512, start.size.y) + Vector2(6, 6),
		"2 px ring + 1 px gap on both sides"
	)


func test_no_text_below_the_type_floor() -> void:
	assert_gte(_min_font_size(_screen), 12, "no player-facing text below 12 px")


func test_score_grouping_handles_short_and_long_values() -> void:
	assert_eq(_screen._format_score(0), "0")
	assert_eq(_screen._format_score(350), "350")
	assert_eq(_screen._format_score(12480), "12 480")
	assert_eq(_screen._format_score(1234567), "1 234 567")


## Walks the screen and returns the smallest font size in use (UX_RESEARCH §9: floor 12 px).
func _min_font_size(node: Node) -> int:
	var smallest := 999
	if node is Label or node is Button:
		smallest = mini(smallest, (node as Control).get_theme_font_size("font_size"))
	for child in node.get_children():
		smallest = mini(smallest, _min_font_size(child))
	return smallest

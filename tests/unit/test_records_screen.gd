extends GutTest
## Records screen (addendum §12, D059): three tabs, ten rows, the empty state and ESC.

const SCENE := preload("res://scenes/ui/RecordsScreen.tscn")
const PATH := "user://test_records_screen.json"

var _screen: Control


func before_each() -> void:
	DirAccess.remove_absolute(PATH)
	(
		Leaderboard
		. submit(
			{
				"score": 1234,
				"rank": "A",
				"accuracy": 0.75,
				"max_combo": 4,
				"delivered": 9,
				"seed": 77,
			},
			Config.Difficulty.STANDARD,
			PATH,
			1700000000
		)
	)
	_screen = SCENE.instantiate() as Control
	add_child_autofree(_screen)
	await wait_process_frames(2)
	_screen.call("set_path", PATH)


func after_each() -> void:
	DirAccess.remove_absolute(PATH)


func _plaque() -> Control:
	return _screen.get_node("Plaque") as Control


func test_three_difficulty_tabs_exist() -> void:
	for index in range(Config.DIFFICULTY_KEYS.size()):
		var tab := _plaque().get_node_or_null("Tab%d" % index) as Button
		assert_not_null(tab, "tab %d exists" % index)
	assert_eq(int(_screen.call("current_tab")), Config.Difficulty.CALM, "opens on the first tab")


func test_the_selected_bar_is_centred_on_its_label() -> void:
	for index in range(Config.DIFFICULTY_KEYS.size()):
		var tab := _plaque().get_node("Tab%d" % index) as Button
		var bar := tab.get_node("Underline") as ColorRect
		assert_gt(bar.size.x, 0.0, "tab %d has a measurable bar" % index)
		assert_almost_eq(
			bar.position.x + bar.size.x * 0.5,
			tab.size.x * 0.5,
			0.01,
			"tab %d bar is centred on the text" % index
		)


func test_hover_cannot_resize_a_tab() -> void:
	# Different content margins per state used to grow the button and clip the label.
	for index in range(Config.DIFFICULTY_KEYS.size()):
		var tab := _plaque().get_node("Tab%d" % index) as Button
		for state: String in ["normal", "hover", "pressed", "focus"]:
			var box := tab.get_theme_stylebox(state)
			assert_eq(box.get_margin(SIDE_LEFT), 0.0, "tab %d %s left margin" % [index, state])
			assert_eq(box.get_margin(SIDE_RIGHT), 0.0, "tab %d %s right margin" % [index, state])


func test_the_stored_run_is_shown_in_its_own_table() -> void:
	var standard := Config.Difficulty.STANDARD
	_screen.call("set_tab", standard)
	var points := _plaque().get_node("Points0") as Label
	assert_true(points.visible, "one row is visible")
	assert_eq(points.text, "1 234")
	assert_eq((_plaque().get_node("Rank0") as Label).text, "A")
	assert_eq((_plaque().get_node("Accuracy0") as Label).text, "75 %")
	assert_eq((_plaque().get_node("Pos0") as Label).text, "01")


func test_rows_beyond_the_table_are_hidden() -> void:
	_screen.call("set_tab", Config.Difficulty.STANDARD)
	assert_false((_plaque().get_node("Points1") as Label).visible, "only one stored run")
	assert_eq(Config.LEADERBOARD_SIZE, 10, "the table has ten slots")


func test_tables_are_separate_per_difficulty() -> void:
	_screen.call("set_tab", Config.Difficulty.CHAOS)
	assert_true((_plaque().get_node("Empty") as Label).visible, "chaos has no runs yet")
	assert_false((_plaque().get_node("Points0") as Label).visible)


func test_escape_asks_to_close() -> void:
	watch_signals(_screen)
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	_screen.call("_input", event)
	assert_signal_emitted(_screen, "close_requested")


func test_points_are_grouped_in_thousands() -> void:
	assert_eq(_screen.call("_format_points", 0), "0")
	assert_eq(_screen.call("_format_points", 999), "999")
	assert_eq(_screen.call("_format_points", 1234), "1 234")
	assert_eq(_screen.call("_format_points", 18450), "18 450")

extends GutTest
## Pause overlay contract (§12.3): always-on while paused, resume as default focus,
## four intents, and the reduce-motion note only when the setting is on.

const PAUSE_SCENE := preload("res://scenes/ui/PauseOverlay.tscn")
const CONTRACT_SIGNALS := [
	"resume_requested", "restart_requested", "options_requested", "menu_requested"
]
const ROW_NAMES := ["ResumeButton", "RestartButton", "OptionsButton", "MenuButton"]

var _screen: Control


func before_each() -> void:
	Settings.reset_to_defaults()
	_screen = PAUSE_SCENE.instantiate() as Control
	add_child_autofree(_screen)
	await wait_process_frames(2)


func after_each() -> void:
	Settings.reset_to_defaults()
	Settings.db_seed = 0


func test_declares_every_contract_signal() -> void:
	for signal_name in CONTRACT_SIGNALS:
		assert_true(_screen.has_signal(signal_name), "missing signal %s" % signal_name)


func test_runs_while_the_tree_is_paused() -> void:
	assert_eq(_screen.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_plaque_is_560x470_and_centred() -> void:
	var plaque := _screen.get_node("Plaque") as Panel
	assert_eq(plaque.size, Vector2(560, 470))
	assert_eq(plaque.position, Vector2(360, 125))


func test_default_focus_is_resume() -> void:
	_screen.focus_first()
	await wait_process_frames(1)
	assert_true((_screen.get_node("Plaque/ResumeButton") as Button).has_focus())


func test_each_row_emits_its_intent() -> void:
	watch_signals(_screen)
	for index in range(ROW_NAMES.size()):
		var row := _screen.get_node("Plaque/%s" % ROW_NAMES[index]) as Button
		assert_not_null(row, "row %s missing" % ROW_NAMES[index])
		row.emit_signal("pressed")
		assert_signal_emitted(_screen, CONTRACT_SIGNALS[index])


func test_rows_are_the_four_contract_labels() -> void:
	var labels: Array[String] = []
	for name in ROW_NAMES:
		labels.append((_screen.get_node("Plaque/%s" % name) as Button).text)
	assert_eq(labels, ["REANUDAR", "REINICIAR", "OPCIONES", "MENÚ"])


func test_reduce_motion_note_only_when_enabled() -> void:
	assert_null(
		_screen.get_node_or_null("Plaque/ReduceMotionNote"), "no note when reduce motion is off"
	)
	Settings.reduce_motion = true
	var with_note := PAUSE_SCENE.instantiate() as Control
	add_child_autofree(with_note)
	await wait_process_frames(2)
	assert_not_null(with_note.get_node_or_null("Plaque/ReduceMotionNote"))


func test_focus_neighbours_wrap_vertically() -> void:
	var first := _screen.get_node("Plaque/ResumeButton") as Button
	var last := _screen.get_node("Plaque/MenuButton") as Button
	assert_eq(first.focus_neighbor_top, first.get_path_to(last))
	assert_eq(last.focus_neighbor_bottom, last.get_path_to(first))


func test_controls_block_lists_every_action() -> void:
	var texts: Array[String] = []
	for node in _screen.get_node("Plaque").get_children():
		if node is Label:
			texts.append((node as Label).text)
	for expected in ["MOVER", "APUNTAR", "AGARRAR · LANZAR", "GOLPE RÍTMICO", "PAUSA"]:
		assert_true(texts.has(expected), "controls block must list %s" % expected)

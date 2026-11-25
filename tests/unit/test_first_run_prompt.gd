extends GutTest
## First-run prompt contract (§12.2): exact copy, tutorial recommended by default, ESC closes.

const PROMPT_SCENE := preload("res://scenes/ui/FirstRunPrompt.tscn")
const CONTRACT_SIGNALS := ["tutorial_selected", "skip_selected", "closed"]

var _screen: Control


func before_each() -> void:
	Settings.reset_to_defaults()
	_screen = PROMPT_SCENE.instantiate() as Control
	add_child_autofree(_screen)
	await wait_process_frames(2)


func after_each() -> void:
	Settings.reset_to_defaults()
	Settings.db_seed = 0


func test_declares_every_contract_signal() -> void:
	for signal_name in CONTRACT_SIGNALS:
		assert_true(_screen.has_signal(signal_name), "missing signal %s" % signal_name)


func test_copy_matches_the_bible() -> void:
	var plaque := _screen.get_node("Plaque")
	assert_eq(plaque.get_node("Title").text, "¿PRIMERA VEZ?")
	assert_eq(plaque.get_node("Body0").text, "El tutorial dura 3 minutos y te enseña")
	assert_eq(plaque.get_node("Body1").text, "a lavar y entregar.")
	assert_eq(plaque.get_node("TutorialButton").text, "HACER EL TUTORIAL")
	assert_eq(plaque.get_node("SkipButton").text, "EMPEZAR EL TURNO")


func test_plaque_is_640x280_and_centred() -> void:
	var plaque := _screen.get_node("Plaque") as Panel
	assert_eq(plaque.size, Vector2(640, 280))
	assert_eq(plaque.position, Vector2(320, 220))


func test_default_focus_is_the_tutorial() -> void:
	_screen.focus_first()
	await wait_process_frames(1)
	assert_true((_screen.get_node("Plaque/TutorialButton") as Button).has_focus())


func test_tutorial_button_emits_tutorial_selected() -> void:
	watch_signals(_screen)
	(_screen.get_node("Plaque/TutorialButton") as Button).emit_signal("pressed")
	assert_signal_emitted(_screen, "tutorial_selected")


func test_skip_button_emits_skip_selected() -> void:
	watch_signals(_screen)
	(_screen.get_node("Plaque/SkipButton") as Button).emit_signal("pressed")
	assert_signal_emitted(_screen, "skip_selected")


func test_skip_persists_first_run_done() -> void:
	Settings.first_run_done = false
	(_screen.get_node("Plaque/SkipButton") as Button).emit_signal("pressed")
	assert_true(Settings.first_run_done, "EMPEZAR EL TURNO must not make the prompt nag")


func test_focus_pair_stays_inside_the_modal() -> void:
	var tutorial := _screen.get_node("Plaque/TutorialButton") as Button
	var skip := _screen.get_node("Plaque/SkipButton") as Button
	assert_eq(tutorial.focus_neighbor_right, tutorial.get_path_to(skip))
	assert_eq(skip.focus_neighbor_left, skip.get_path_to(tutorial))
	assert_eq(tutorial.focus_neighbor_top, tutorial.get_path_to(tutorial))


func test_close_emits_closed() -> void:
	watch_signals(_screen)
	_screen.close()
	assert_signal_emitted(_screen, "closed")

# gdlint: disable=max-public-methods
extends GutTest
## End-to-end: `Tutorial.tscn` boots the real MainLevel, gates the seven steps and re-emits
## the intents `App.gd` listens for (docs/UX_BIBLE.md §16.1).

const TUTORIAL_SCENE := preload("res://scenes/main/Tutorial.tscn")
const CHUTE_SCENE := "res://scenes/environment/DeliveryChute.tscn"

var _settings_snapshot: Dictionary = {}


func before_each() -> void:
	_settings_snapshot = {
		"completed": Settings.tutorial_completed,
		"skipped": Settings.tutorial_skipped,
		"first_run": Settings.first_run_done,
	}


func after_each() -> void:
	Settings.tutorial_completed = bool(_settings_snapshot.get("completed", false))
	Settings.tutorial_skipped = bool(_settings_snapshot.get("skipped", false))
	Settings.first_run_done = bool(_settings_snapshot.get("first_run", false))
	Settings.save_settings()
	GameState.stability_protected = false
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)


func _spawn() -> TutorialRoot:
	var root := TUTORIAL_SCENE.instantiate() as TutorialRoot
	add_child_autofree(root)
	return root


func _frames(director: TutorialDirector, count: int, delta: float = 0.016) -> void:
	for _i in range(count):
		director._process(delta)


# --- Assembly ---------------------------------------------------------------


func test_tutorial_scene_boots_the_real_level_in_tutorial_mode() -> void:
	var root := _spawn()
	var level: Node = root.level()
	assert_not_null(level, "MainLevel must be instanced by the tutorial scene")
	assert_true(bool(level.call("is_tutorial")))
	assert_eq(root.current_scene_mode(), &"tutorial")
	assert_not_null(root.get_node_or_null("Overlay"))
	assert_not_null(root.get_node_or_null("Director"))


func test_director_starts_on_gate_one_with_the_chip() -> void:
	var root := _spawn()
	var director := root.director()
	assert_eq(director.current_step(), 0)
	assert_true(director.is_active())
	assert_eq(root.overlay().chip_step_text(), "PASO 1/7")
	assert_eq(root.overlay().chip_title_text(), "MUÉVETE")
	assert_true(root.overlay().prompt_visible(), "gate 1 must show its prompt immediately")


func test_stability_protection_is_on_then_off_at_the_last_gate() -> void:
	var root := _spawn()
	assert_true(GameState.stability_protected, "gates 1-6 cannot lose stability")
	root.director().debug_goto(6)
	assert_false(GameState.stability_protected, "gate 7 restores the real stakes")
	GameState.add_stability(-10.0, "test")
	assert_almost_eq(GameState.stability, 90.0, 0.01)


func test_no_gate_auto_advances_without_its_success_event() -> void:
	var root := _spawn()
	_frames(root.director(), 240, 0.05)
	assert_eq(root.director().current_step(), 0)
	assert_false(bool(root.director().current_state()["granted"]))


# --- Skip -------------------------------------------------------------------


func test_pause_opens_the_skip_plaque_and_no_cancels_it() -> void:
	var root := _spawn()
	root.director().set_process(false)
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	root._input(event)
	assert_true(root.overlay().is_skip_open())
	root.overlay().skip_cancelled.emit()
	assert_false(root.overlay().is_skip_open())
	assert_false(root.is_complete())


func test_skip_confirm_emits_tutorial_skipped_and_persists() -> void:
	Settings.tutorial_skipped = false
	Settings.tutorial_completed = true
	var root := _spawn()
	watch_signals(root)
	root.overlay().skip_confirmed.emit()
	assert_signal_emitted(root, "tutorial_skipped")
	assert_true(Settings.tutorial_skipped)
	assert_true(root.is_complete())
	assert_false(root.director().is_active())
	assert_false(GameState.stability_protected, "skipping must never leave the guard on")


# --- Completion -------------------------------------------------------------


func test_last_gate_shows_the_completion_plaque() -> void:
	var root := _spawn()
	root.director().debug_goto(TutorialSteps.STEP_COUNT)
	assert_true(root.overlay().is_completion_open())
	assert_false(root.director().is_active())


func test_continue_completes_the_tutorial_and_re_emits() -> void:
	Settings.tutorial_completed = false
	var root := _spawn()
	watch_signals(root)
	root.director().debug_goto(TutorialSteps.STEP_COUNT)
	root.overlay().accept_completion()
	assert_signal_emitted(root, "tutorial_completed")
	assert_true(Settings.tutorial_completed)
	assert_true(root.is_complete())
	assert_false(GameState.stability_protected)


func test_completion_plaque_cannot_continue_twice() -> void:
	Settings.tutorial_completed = false
	var root := _spawn()
	watch_signals(root)
	root.director().debug_goto(TutorialSteps.STEP_COUNT)
	root.overlay().accept_completion()
	root.overlay().accept_completion()
	assert_signal_emit_count(root, "tutorial_completed", 1)


func test_replay_is_always_available_and_never_gated() -> void:
	Settings.tutorial_completed = true
	var root := _spawn()
	assert_true(root.director().is_active(), "completion never blocks a replay")
	assert_eq(root.director().current_step(), 0)


func test_autoplay_walks_the_real_scene_to_the_completion_plaque() -> void:
	var root := _spawn()
	var director := root.director()
	director.autoplay = true
	for _i in range(600):
		director._process(0.05)
		if not director.is_active():
			break
	assert_false(director.is_active(), "autoplay must clear all seven gates")
	assert_true(root.overlay().is_completion_open())
	assert_eq(root.overlay().chip_step_text(), "PASO 7/7")


# --- Input routing ----------------------------------------------------------


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func test_completion_plaque_ignores_input_inside_the_grace_window() -> void:
	var root := _spawn()
	watch_signals(root)
	root.director().debug_goto(TutorialSteps.STEP_COUNT)
	assert_true(root.overlay().is_completion_open())
	root._input(_key(KEY_SPACE))
	assert_signal_not_emitted(root, "tutorial_completed", "a held key must not skip the plaque")
	assert_true(root.overlay().is_completion_open())


func test_completion_plaque_accepts_input_after_the_grace_window() -> void:
	var root := _spawn()
	watch_signals(root)
	root.director().debug_goto(TutorialSteps.STEP_COUNT)
	root.debug_arm_completion()
	root._input(_key(KEY_SPACE))
	assert_signal_emitted(root, "tutorial_completed")


func test_tab_soft_skips_only_once_the_gate_is_stuck() -> void:
	var root := _spawn()
	var director := root.director()
	root._input(_key(KEY_TAB))
	assert_eq(director.current_step(), 0, "TAB before the 12 s grace does nothing")
	director.debug_set_elapsed(Config.TUTORIAL_SOFT_SKIP_S + 0.1)
	director._process(0.016)
	root._input(_key(KEY_TAB))
	for _i in range(60):
		director._process(0.016)
	assert_eq(director.current_step(), 1, "TAB grants the stuck gate and moves on")


func test_pause_never_reaches_the_pause_menu_while_the_tutorial_runs() -> void:
	var root := _spawn()
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	root._input(event)
	assert_true(root.overlay().is_skip_open(), "ESC opens the skip plaque, not pause")
	assert_true(root.get_viewport().is_input_handled())


# --- Real washer integration (pending until the M4 merge) -------------------


func test_full_wash_strike_deliver_cycle_on_the_real_washers() -> void:
	if not ResourceLoader.exists(Config.SCENE_WASHER) or not ResourceLoader.exists(CHUTE_SCENE):
		pending(
			(
				"CosmicWasher/DeliveryChute are owned by the core-loop workstream and are "
				+ "absent from this worktree; re-run this test after the M4 merge."
			)
		)
		return
	var root := _spawn()
	var level: Node = root.level()
	var washers: Array = level.call("get_washers")
	assert_eq(washers.size(), Config.WASHER_COUNT)
	var director := root.director()
	director.debug_goto(4)
	assert_not_null(director.target_washer())
	var mouth: Vector2 = director.target_washer().call("get_mouth_world")
	assert_true(mouth.length() > 0.0)

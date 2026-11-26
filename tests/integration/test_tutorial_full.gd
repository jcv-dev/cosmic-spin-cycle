extends GutTest
## The tutorial must run the real level, gate every step, grant completion and be skippable.

const TUTORIAL_SCENE := preload("res://scenes/main/Tutorial.tscn")

var _root: Node2D


func before_each() -> void:
	Settings.tutorial_completed = false
	Settings.tutorial_skipped = false
	_root = TUTORIAL_SCENE.instantiate() as Node2D
	add_child_autofree(_root)
	await wait_process_frames(2)


func after_each() -> void:
	Settings.tutorial_completed = false
	Settings.tutorial_skipped = false
	GameState.stability_protected = false
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)


func test_it_uses_the_real_level_in_tutorial_mode() -> void:
	var level := _root.call("level") as Node
	assert_not_null(level, "the tutorial drives a real MainLevel")
	assert_eq(StringName(level.get("mode")), &"tutorial")
	assert_eq(int(level.call("get_seed")), Config.TUTORIAL_SEED, "the tutorial is deterministic")
	assert_true(bool(GameState.stability_protected), "negative stability is disabled until gate 7")
	var director := _root.call("director") as Node
	assert_eq(int(director.call("current_step")), 0, "it starts on the move gate")


func test_every_gate_advances_and_completion_persists() -> void:
	var director := _root.call("director") as Node
	watch_signals(_root)
	for step in range(8):
		assert_eq(int(director.call("current_step")), step, "gate %d is active" % step)
		# Wait past the soft-skip threshold, then grant the gate: this exercises the same
		# path a stuck player gets, not a test-only bypass.
		director.call("debug_set_elapsed", Config.TUTORIAL_SOFT_SKIP_S + 1.0)
		director.call("debug_advance")
		# The gate-granted transition has a ~0.35 s feedback delay before the next step.
		await wait_seconds(0.6)
	assert_true(bool(_root.get("_all_gates_done")), "eight gates ran and the plaque is up")
	assert_false(bool(GameState.stability_protected), "stability protection ends at gate 7")
	_root.call("_on_completion_continued")
	await wait_process_frames(2)
	assert_true(bool(_root.call("is_complete")), "the completion plaque closes the tutorial")
	assert_true(Settings.tutorial_completed, "completion persists in Settings")
	assert_signal_emitted(_root, "tutorial_completed")


func test_skipping_persists_and_returns_to_the_menu() -> void:
	watch_signals(_root)
	_root.call("_on_skip_confirmed")
	await wait_process_frames(2)
	assert_true(Settings.tutorial_skipped, "a skip persists")
	assert_false(Settings.tutorial_completed, "a skip is not a completion")
	assert_signal_emitted(_root, "tutorial_skipped")
	assert_false(bool(GameState.stability_protected), "skipping restores stability rules")

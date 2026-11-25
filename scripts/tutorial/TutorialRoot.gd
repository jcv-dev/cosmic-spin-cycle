class_name TutorialRoot
extends Node2D
## Root of `scenes/main/Tutorial.tscn` (docs/UX_BIBLE.md §7, §16.1).
##
## Owns nothing but wiring: it re-emits the completion/skip intents `App.gd` listens for,
## routes input (pause → skip plaque, TAB → soft-skip, any input → continue) and applies the
## debug/evidence arguments the screenshot harness passes through.
##
## The tutorial is always skippable and always replayable; completion only stops the
## first-run recommendation (`Settings.tutorial_completed`).

signal tutorial_completed
signal tutorial_skipped
signal shift_finished(result: Dictionary)

const STEP_ARG := "--tutorial-step="
const ELAPSED_ARG := "--tutorial-elapsed="
const AUTOPLAY_ARG := "--tutorial-autoplay"
const PLAQUE_ARG := "--tutorial-plaque="
const COMPLETE_INPUT_GRACE_S := 0.35
const SOFT_SKIP_KEY := KEY_TAB

## App.gd writes this before the node enters the tree; the tutorial only ever runs in
## tutorial mode, so it is re-asserted in `_ready`.
var mode: StringName = &"tutorial"

var _level: Node
var _overlay: TutorialOverlay
var _director: TutorialDirector
var _complete := false
var _all_gates_done := false
var _complete_armed_at := 0.0


func _ready() -> void:
	_level = get_node_or_null("MainLevel")
	_overlay = get_node_or_null("Overlay") as TutorialOverlay
	_director = get_node_or_null("Director") as TutorialDirector
	if _level == null or _overlay == null or _director == null:
		push_error("TUTORIAL: scene is missing MainLevel/Overlay/Director")
		return
	_level.set("mode", &"tutorial")
	_level.set("clock_running", true)
	_director.level = _level
	_director.overlay = _overlay
	if _level.has_signal("tutorial_completed"):
		_level.connect("tutorial_completed", _on_level_tutorial_completed)
	if _level.has_signal("shift_finished"):
		_level.connect("shift_finished", _on_level_shift_finished)
	_overlay.skip_confirmed.connect(_on_skip_confirmed)
	_overlay.skip_cancelled.connect(_on_skip_cancelled)
	_overlay.completion_continued.connect(_on_completion_continued)
	_director.finished.connect(_on_all_gates_done)
	_director.start()
	_apply_debug_args()


func _exit_tree() -> void:
	# The guard must never outlive the tutorial, whatever path ended it.
	GameState.stability_protected = false
	if _director != null:
		_director.exit()


func _input(event: InputEvent) -> void:
	if _overlay == null or _director == null:
		return
	if _all_gates_done and _overlay.is_completion_open():
		if _is_any_input(event) and _input_armed():
			_overlay.accept_completion()
			get_viewport().set_input_as_handled()
		return
	if _overlay.is_skip_open():
		if event.is_action_pressed("pause"):
			_close_skip()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and _director.is_active():
		_open_skip()
		get_viewport().set_input_as_handled()
		return
	if _is_soft_skip_key(event) and _director.can_soft_skip():
		_director.soft_skip()
		get_viewport().set_input_as_handled()


# --- Flow -------------------------------------------------------------------


func _open_skip() -> void:
	_overlay.open_skip()
	_director.set_plaque(true)


func _close_skip() -> void:
	_overlay.close_skip()
	_director.set_plaque(false)


func _on_skip_confirmed() -> void:
	if _complete:
		return
	_complete = true
	_close_skip()
	_director.exit()
	Settings.mark_tutorial_skipped()
	tutorial_skipped.emit()


func _on_skip_cancelled() -> void:
	_close_skip()


func _on_all_gates_done() -> void:
	if _all_gates_done:
		return
	_all_gates_done = true
	_complete_armed_at = _now()
	_overlay.show_completion()


func _on_completion_continued() -> void:
	if _complete:
		return
	_complete = true
	_director.exit()
	_overlay.hide_completion()
	if _level != null and _level.has_method("complete_tutorial"):
		_level.call("complete_tutorial")
	else:
		tutorial_completed.emit()


func _on_level_tutorial_completed() -> void:
	tutorial_completed.emit()


func _on_level_shift_finished(result: Dictionary) -> void:
	shift_finished.emit(result)


# --- Helpers ----------------------------------------------------------------


func director() -> TutorialDirector:
	return _director


func overlay() -> TutorialOverlay:
	return _overlay


func level() -> Node:
	return _level


func is_complete() -> bool:
	return _complete


func current_scene_mode() -> StringName:
	return mode


func _is_any_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed and not (event as InputEventKey).echo
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) > 0.6
	return false


func _is_soft_skip_key(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	return key.pressed and not key.echo and key.keycode == SOFT_SKIP_KEY


## Test/evidence hook: pretend the completion plaque has been readable for a while.
func debug_arm_completion() -> void:
	_complete_armed_at = _now() - COMPLETE_INPUT_GRACE_S - 0.1


func _input_armed() -> bool:
	return _now() - _complete_armed_at >= COMPLETE_INPUT_GRACE_S


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## Evidence hooks (tools/screenshot.gd passes user args straight through):
##   --tutorial-step=N       jump to gate N (0-based)
##   --tutorial-elapsed=S    pretend the gate has been running S seconds
##   --tutorial-autoplay     walk every gate on a timer
func _apply_debug_args() -> void:
	var step := -1
	var elapsed := -1.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(STEP_ARG):
			step = int(argument.trim_prefix(STEP_ARG))
		elif argument.begins_with(ELAPSED_ARG):
			elapsed = float(argument.trim_prefix(ELAPSED_ARG))
		elif argument == AUTOPLAY_ARG:
			_director.autoplay = true
		elif argument.begins_with(PLAQUE_ARG):
			call_deferred("_debug_plaque", argument.trim_prefix(PLAQUE_ARG))
	if step < 0:
		return
	call_deferred("_debug_stage", step, elapsed)


## Evidence hook: open the skip plaque (or the completion plaque) without playing.
func _debug_plaque(kind: String) -> void:
	if kind == "skip":
		_open_skip()
	elif kind == "complete":
		_all_gates_done = true
		_complete_armed_at = _now() - COMPLETE_INPUT_GRACE_S
		_overlay.set_step(TutorialSteps.STEP_COUNT - 1, 1.0)
		_overlay.show_completion()


func _debug_stage(step: int, elapsed: float) -> void:
	if _director == null:
		return
	_director.debug_goto(step)
	if elapsed >= 0.0:
		_director.debug_set_elapsed(elapsed)

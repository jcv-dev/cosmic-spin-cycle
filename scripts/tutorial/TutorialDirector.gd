# gdlint: disable=max-public-methods
class_name TutorialDirector
extends Node
## Drives the seven gates against the *real* `MainLevel` (docs/UX_BIBLE.md §7, §16.1).
##
## The gate logic lives in `TutorialSteps` (pure, unit-tested); this node is the thin
## adapter: it stages each gate's world state, listens to the real player/washer/chute
## systems, and feeds one event (or one tick) per frame into the step machine.
##
## Every system the M4 loop owns is optional at runtime (`has_method` / `has_signal`
## guards) so the tutorial boots and is screenshot-able before the washers land; gates that
## need a washer stay open and the soft-skip covers them.

signal step_started(index: int)
signal step_completed(index: int)
signal finished

const ADVANCE_DELAY_S := 0.45
const AUTOPLAY_STEP_S := 0.9
## Spawn spot for scripted items: far enough right that the world prompt never covers Pip.
const ITEM_OFFSET := Vector2(200, 0)
## Pip's sprite is 96 px tall with a feet pivot; the prompt hangs above the head, not on it.
const PLAYER_HEAD_OFFSET := Vector2(0, -96)
const CLEAN_FALLBACK_S := 8.0
const WASHER_FORCE_FINISH_S := 4.0
const PROMPT_AVOID_X := 170.0

## Debug/evidence hook: walk the gates on a timer so a screenshot can be deterministic.
@export var autoplay := false
## Test/evidence hook: pin Δt instead of sampling the song clock (negative = sample it).
var debug_delta_t := -1.0

var level: Node
var overlay: TutorialOverlay
var state: Dictionary = {}
var active := false

var _step_index := 0
var _gate_time := 0.0
var _advance_left := -1.0
var _last_player_pos := Vector2.ZERO
var _player: Node
var _camera: Camera2D
var _camera_base_zoom := Vector2.ONE
var _zoom_tween: Tween

var _gate_item: Node = null
var _respawn_left := -1.0
var _target_washer: Node = null
var _target_washer_id: StringName = &""
var _washer_counts: Dictionary = {}
var _locked_by_director: Dictionary = {}
var _clean_item: Node = null
var _clean_wait := 0.0
var _finish_asked := false
var _strike_stage := 0
var _autoplay_left := 0.0
var _hint_shown := false
var _plaque_open := false


func _ready() -> void:
	set_process(false)
	if level == null:
		level = get_parent().get_node_or_null("MainLevel")
	if overlay == null:
		overlay = get_parent().get_node_or_null("Overlay") as TutorialOverlay


func _process(delta: float) -> void:
	if not active:
		return
	_gate_time += float(delta)
	if _advance_left >= 0.0:
		_advance_left -= delta
		if _advance_left <= 0.0:
			_advance_left = -1.0
			_go_to_step(_step_index + 1)
		return
	_poll_inserts()
	_feed({"kind": &"tick", "delta": delta})
	_track_travel()
	_update_gate(delta)
	_update_overlay()
	if autoplay:
		_autoplay_left -= delta
		if _autoplay_left <= 0.0:
			debug_advance()


# --- Lifecycle --------------------------------------------------------------


func start() -> void:
	if active:
		return
	if level == null or overlay == null:
		push_warning("TUTORIAL: director started without a level/overlay")
		return
	active = true
	set_process(true)
	GameState.stability_protected = true
	level.set("clock_running", true)
	_camera = level.get_camera() if level.has_method("get_camera") else null
	if _camera != null:
		_camera_base_zoom = _camera.zoom
		overlay.camera = _camera
	_player = level.get_player() if level.has_method("get_player") else null
	_connect_player()
	_connect_washers()
	_connect_chute()
	clear_gate_items()
	_go_to_step(0)


func exit() -> void:
	active = false
	set_process(false)
	GameState.stability_protected = false
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	if _camera != null and is_instance_valid(_camera):
		_camera.zoom = _camera_base_zoom
	if overlay != null:
		overlay.hide_prompt()
		overlay.hide_hint_circle()
		overlay.hide_beacon()
	_unlock_washers()


func is_active() -> bool:
	return active


func current_step() -> int:
	return _step_index


func current_state() -> Dictionary:
	return state


func is_last_step() -> bool:
	return _step_index >= TutorialSteps.STEP_COUNT - 1


func can_soft_skip() -> bool:
	return active and not _plaque_open and bool(state.get("soft_skip_ready", false))


## TAB: grants the gate the player is stuck on, so nobody is ever trapped (§7).
func soft_skip() -> void:
	if not active:
		return
	_feed({"kind": &"skip"})


## Debug/evidence: grants the current gate immediately.
func debug_advance() -> void:
	if not active:
		return
	_feed({"kind": &"skip"})


## Debug/evidence: jump straight to a gate (used by the screenshot harness).
func debug_goto(index: int) -> void:
	if not active:
		return
	_go_to_step(index)


## Debug/evidence: pretend the current gate has already been running for `seconds`.
func debug_set_elapsed(seconds: float) -> void:
	var hint_after := float(TutorialSteps.step(_step_index).get("hint_after_s", 4.0))
	state["elapsed"] = seconds
	state["hint"] = seconds >= hint_after
	state["soft_skip_ready"] = seconds >= Config.TUTORIAL_SOFT_SKIP_S
	_gate_time = seconds
	_update_overlay()


## While the skip plaque is open the gate clock stops, so the soft-skip timer stays honest.
func set_plaque(open: bool) -> void:
	_plaque_open = open
	set_process(not open)


func target_washer() -> Node:
	return _target_washer


func gate_item() -> Node:
	return _gate_item


# --- Gate staging -----------------------------------------------------------


func _go_to_step(index: int) -> void:
	if index >= TutorialSteps.STEP_COUNT:
		_finish()
		return
	_step_index = TutorialSteps.clamp_index(index)
	state = TutorialSteps.new_state(_step_index)
	_gate_time = 0.0
	_advance_left = -1.0
	_autoplay_left = AUTOPLAY_STEP_S
	_hint_shown = false
	_strike_stage = 0
	_respawn_left = -1.0
	_clean_item = null
	_clean_wait = 0.0
	_finish_asked = false
	_last_player_pos = _player_anchor()
	_washer_counts = _sample_washer_counts()
	_stage_gate(_step_index)
	overlay.set_step(_step_index, 0.0)
	step_started.emit(_step_index)


func _stage_gate(index: int) -> void:
	match TutorialSteps.kind_for(index):
		&"travel":
			clear_gate_items()
			show_gate_prompt(_player_anchor())
		&"grab":
			clear_gate_items()
			_gate_item = _spawn_dirty(_anchor_in_front())
			show_gate_prompt(_item_anchor())
		&"throw":
			_ensure_gate_item()
			show_gate_prompt(_item_anchor())
		&"grade":
			clear_gate_items()
			_gate_item = _spawn_dirty(_anchor_in_front())
			show_gate_prompt(_item_anchor())
		&"insert":
			_stage_insert()
		&"strike":
			_stage_strike()
		&"deliver":
			_stage_deliver()
		_:
			pass


## Gate 5: only the compatible washer is lit; the rest stay locked.
func _stage_insert() -> void:
	clear_gate_items()
	_target_washer = _pick_match_washer()
	_lock_washers_except(_target_washer)
	_free_washer(_target_washer)
	_gate_item = _spawn_dirty(_anchor_in_front())
	show_gate_prompt(_washer_anchor(_target_washer))
	overlay.pulse_at(_washer_anchor(_target_washer), UITheme.ACCENT)


## Gate 6: a scripted turbulent washer that cannot explode.
func _stage_strike() -> void:
	if _target_washer == null or not is_instance_valid(_target_washer):
		_target_washer = _pick_match_washer()
	_lock_washers_except(_target_washer)
	_free_washer(_target_washer)
	if _target_washer != null and _target_washer.has_method("force_turbulent"):
		_target_washer.call("force_turbulent")
	show_gate_prompt(_washer_anchor(_target_washer))
	overlay.pulse_at(_washer_anchor(_target_washer), UITheme.DANGER)


## Gate 7: stability protection ends here; the clean item must reach the chute.
func _stage_deliver() -> void:
	GameState.stability_protected = false
	_unlock_washers()
	_clean_wait = 0.0
	_clean_item = _find_clean_item()
	if _clean_item == null and _target_washer != null and _target_washer.has_method("force_finish"):
		_target_washer.call("force_finish")
		_finish_asked = true
		_clean_item = _find_clean_item()
	if _clean_item == null and _washers().is_empty():
		# No washer scene in this build: stage the clean item directly instead of stranding
		# the player in front of a machine that cannot finish. The wash still happened for
		# every build that ships CosmicWasher.
		_spawn_clean_fallback()
		_clean_item = _gate_item
	_gate_item = _clean_item
	show_gate_prompt(_item_anchor())
	overlay.show_beacon(_chute_anchor())


func _finish() -> void:
	active = false
	set_process(false)
	overlay.hide_prompt()
	overlay.hide_hint_circle()
	overlay.hide_beacon()
	overlay.set_step(TutorialSteps.STEP_COUNT - 1, 1.0)
	step_completed.emit(TutorialSteps.STEP_COUNT - 1)
	finished.emit()


# --- Per-frame gate behaviour ----------------------------------------------


func _update_gate(delta: float) -> void:
	if bool(state.get("granted", false)):
		overlay.set_beat_marker(Vector2.ZERO, false)
		return
	match TutorialSteps.kind_for(_step_index):
		&"travel":
			_update_travel()
		&"grab":
			_update_grab(delta)
		&"grade":
			_update_grade(delta)
		&"insert":
			_update_insert()
		&"strike":
			_update_strike()
		&"deliver":
			_update_deliver(delta)
		_:
			pass
	_sync_beat_marker()


func _update_travel() -> void:
	if not bool(state.get("hint", false)):
		return
	_hint_shown = true
	# Re-issued every frame: the ring must stay glued to Pip while they keep walking.
	overlay.show_hint_circle(_player_anchor(), TutorialSteps.TRAVEL_HINT_RADIUS_PX)


## Gate 2 fail-forward: steer the item inside the grab radius instead of shouting louder.
func _update_grab(delta: float) -> void:
	if _gate_item == null or not is_instance_valid(_gate_item):
		return
	if not bool(state.get("hint", false)):
		return
	_hint_shown = true
	# The item is being steered toward Pip, so the ring follows it instead of lagging behind.
	overlay.show_hint_circle(_raw_item_pos(), Config.GRAB_RADIUS)
	if not (_gate_item is Node2D) or not (_player is Node2D):
		return
	var item_pos := (_gate_item as Node2D).global_position
	var player_pos := (_player as Node2D).global_position
	if item_pos.distance_to(player_pos) <= Config.GRAB_RADIUS * 1.5:
		return
	var dir := (player_pos - item_pos).normalized()
	(_gate_item as Node2D).global_position = item_pos + dir * 90.0 * delta


## Gates 4 and 6 are the only places the beat matters, so they own the pulse marker.
func _sync_beat_marker() -> void:
	if TutorialSteps.is_rhythm_gate(_step_index) and not bool(state.get("granted", false)):
		# On the floor under Pip for the throw gate, on the drum for the strike gate.
		var anchor := _player_body()
		if TutorialSteps.kind_for(_step_index) == &"strike":
			anchor = _washer_anchor(_target_washer)
		overlay.set_beat_marker(anchor, true, float(BeatConductor.call("get_beat_phase")))
	else:
		overlay.set_beat_marker(Vector2.ZERO, false)


## Feet-centre of Pip: diegetic rings belong on the floor, not on the character sprite.
func _player_body() -> Vector2:
	if _player is Node2D:
		return (_player as Node2D).global_position
	return Vector2(640, 512)


func _update_grade(delta: float) -> void:
	if _respawn_left < 0.0:
		return
	_respawn_left -= delta
	if _respawn_left <= 0.0:
		_respawn_left = -1.0
		_respawn_gate_item()


func _update_insert() -> void:
	if bool(state.get("hint", false)) and not _hint_shown:
		_hint_shown = true
		overlay.pulse_at(_washer_anchor(_target_washer), UITheme.WARNING)


## Gate 6 cannot fail: re-force turbulence, then let the director land the rescue strike.
func _update_strike() -> void:
	if _target_washer == null or not is_instance_valid(_target_washer):
		return
	if bool(state.get("hint", false)) and not _hint_shown:
		_hint_shown = true
		overlay.pulse_at(_washer_anchor(_target_washer), UITheme.DANGER)
	if _strike_stage == 0 and _gate_time >= TutorialSteps.STRIKE_HINT_AFTER_S:
		_strike_stage = 1
		if _target_washer.has_method("force_turbulent"):
			_target_washer.call("force_turbulent")
		GameState.emit_feedback(tr("SIGUE EL PULSO"), &"info")
	if _strike_stage == 1 and _gate_time >= TutorialSteps.STRIKE_ASSIST_AFTER_S:
		_strike_stage = 2
		# Fail-forward, not a lie: the director lands a GOOD strike on the same washer so
		# the turbulence resolves and the loop continues. That hit grants the gate.
		if _target_washer.has_method("strike"):
			_target_washer.call("strike", RhythmEvaluator.Grade.GOOD)
		_feed({"kind": &"strike", "grade": RhythmEvaluator.Grade.GOOD, "assisted": true})


func _update_deliver(delta: float) -> void:
	if _clean_item == null or not is_instance_valid(_clean_item):
		_clean_item = _find_clean_item()
		if _clean_item != null:
			_gate_item = _clean_item
	if _clean_item != null:
		return
	_clean_wait += delta
	if not _finish_asked and _clean_wait >= WASHER_FORCE_FINISH_S:
		_finish_asked = true
		if _target_washer != null and _target_washer.has_method("force_finish"):
			_target_washer.call("force_finish")
	if _clean_wait >= CLEAN_FALLBACK_S:
		_clean_wait = 0.0
		_spawn_clean_fallback()


# --- Events -----------------------------------------------------------------


func _feed(event: Dictionary) -> void:
	if not active:
		return
	var before := _step_index
	TutorialSteps.advance(state, event)
	var feedback := StringName(state.get("feedback", &""))
	if feedback != &"":
		_on_feedback(feedback)
	if bool(state.get("granted", false)) and int(state.get("index", -1)) == before:
		_on_granted()


func _on_feedback(feedback: StringName) -> void:
	match feedback:
		&"good":
			GameState.emit_feedback(tr("BIEN"), &"rhythm")
		&"miss":
			GameState.emit_feedback(tr("FUERA DE RITMO"), &"info")
		&"wrong_mouth":
			GameState.emit_feedback(tr("NO ES ESA"), &"danger")
			overlay.pulse_at(_washer_anchor(_target_washer), UITheme.DANGER)
		&"dirty":
			GameState.emit_feedback(tr("LAVA PRIMERO"), &"danger")
		_:
			pass


func _on_granted() -> void:
	if _advance_left >= 0.0:
		return
	_advance_left = 0.0 if autoplay else ADVANCE_DELAY_S
	overlay.set_progress(1.0)
	overlay.hide_hint_circle()
	overlay.hide_beacon()
	overlay.set_beat_marker(Vector2.ZERO, false)
	var anchor := _success_anchor()
	overlay.pulse_at(anchor, UITheme.SUCCESS)
	if (
		TutorialSteps.is_rhythm_gate(_step_index)
		or TutorialSteps.kind_for(_step_index) == &"deliver"
	):
		focus_camera(anchor)
	GameState.emit_feedback(tr("LISTO"), &"success")
	step_completed.emit(_step_index)


func _connect_player() -> void:
	if _player == null:
		return
	if _player.has_signal("grabbed"):
		_player.connect("grabbed", _on_player_grabbed)
	if _player.has_signal("thrown"):
		_player.connect("thrown", _on_player_thrown)
	if _player.has_signal("struck"):
		_player.connect("struck", _on_player_struck)


func _connect_washers() -> void:
	for washer in _washers():
		if washer.has_signal("item_loaded"):
			washer.connect("item_loaded", _on_washer_item_loaded.bind(washer))
		if washer.has_signal("cycle_done"):
			washer.connect("cycle_done", _on_washer_cycle_done.bind(washer))


func _connect_chute() -> void:
	var chute: Node = level.get_chute() if level.has_method("get_chute") else null
	if chute != null and chute.has_signal("delivered"):
		chute.connect("delivered", _on_chute_delivered)


func _on_player_grabbed(item: Node) -> void:
	if item != null and is_instance_valid(item):
		_gate_item = item
	overlay.hide_hint_circle()
	_feed({"kind": &"grab"})


func _on_player_thrown(item: Node, player_grade: int) -> void:
	var left_hold := true
	if item != null and is_instance_valid(item) and item is Node2D and _player is Node2D:
		var body := (_player as Node2D).global_position
		left_hold = (item as Node2D).global_position.distance_to(body) > Config.GRAB_RADIUS
	var delta_t := _beat_delta()
	# The gate is never stricter than the grade the player already saw: the tutorial window
	# may rescue a borderline throw, never downgrade a GOOD one.
	var tuned := mini(player_grade, TutorialSteps.grade_throw(delta_t, int(state.get("misses", 0))))
	_feed({"kind": &"throw", "left_hold": left_hold, "delta_t": delta_t, "grade": tuned})
	match TutorialSteps.kind_for(_step_index):
		&"grade":
			_gate_item = null
			_respawn_left = 0.8
		&"throw":
			_gate_item = item
		_:
			pass


func _on_player_struck(washer: Node, player_grade: int) -> void:
	var grade := mini(player_grade, TutorialSteps.grade_strike(_beat_delta()))
	if washer != null and washer == _target_washer:
		overlay.pulse_at(_washer_anchor(washer), UITheme.SUCCESS)
	_feed({"kind": &"strike", "grade": grade})


func _on_washer_item_loaded(item: Node, washer: Node) -> void:
	_report_insert(washer, item)


func _on_washer_cycle_done(_items: Array, _washer: Node) -> void:
	if _clean_item == null:
		_clean_item = _find_clean_item()


func _on_chute_delivered(item: Node, _points: int) -> void:
	var clean := item != null and is_instance_valid(item) and bool(item.get("is_clean"))
	_feed({"kind": &"deliver", "clean": clean})


## Poll fallback for washers without `item_loaded`: a growing load count is an insert.
func _poll_inserts() -> void:
	for washer in _washers():
		if not washer.has_method("get_loaded_items"):
			continue
		var id := _washer_id(washer)
		var loaded: Variant = washer.call("get_loaded_items")
		var count := (loaded as Array).size() if loaded is Array else 0
		var previous := int(_washer_counts.get(id, 0))
		if count > previous:
			var item: Node = null
			if loaded is Array and not (loaded as Array).is_empty():
				item = (loaded as Array)[(loaded as Array).size() - 1]
			_report_insert(washer, item)
		_washer_counts[id] = count


func _report_insert(washer: Node, item: Node) -> void:
	if washer == null or not is_instance_valid(washer):
		return
	var correct := washer == _target_washer
	if correct and item != null and is_instance_valid(item):
		_gate_item = item
	_feed({"kind": &"insert", "correct": correct})


# --- Anchors ----------------------------------------------------------------


func _player_anchor() -> Vector2:
	if _player is Node2D:
		return (_player as Node2D).global_position + PLAYER_HEAD_OFFSET
	return Vector2(640, 360)


func _item_anchor() -> Vector2:
	if _gate_item != null and is_instance_valid(_gate_item) and _gate_item is Node2D:
		return _prompt_safe((_gate_item as Node2D).global_position + Vector2(0, -24))
	return _anchor_in_front()


## Never let the world prompt sit on Pip's head: when the anchor is over the sprite, slide
## the prompt sideways instead of up (the room always has more room to the right).
## Raw item position: fail-forward rings sit on the object, never on the shifted prompt.
func _raw_item_pos() -> Vector2:
	if _gate_item != null and is_instance_valid(_gate_item) and _gate_item is Node2D:
		return (_gate_item as Node2D).global_position
	return _anchor_in_front()


func _prompt_safe(world_pos: Vector2) -> Vector2:
	if not (_player is Node2D):
		return world_pos
	var body := (_player as Node2D).global_position
	if absf(world_pos.x - body.x) < 120.0 and absf(world_pos.y - (body.y - 48.0)) < 150.0:
		return Vector2(body.x + PROMPT_AVOID_X, world_pos.y)
	return world_pos


func _anchor_in_front() -> Vector2:
	if _player is Node2D:
		return (_player as Node2D).global_position + ITEM_OFFSET
	return _player_anchor() + ITEM_OFFSET


func _washer_anchor(washer: Node) -> Vector2:
	if washer != null and is_instance_valid(washer):
		if washer.has_method("get_mouth_world"):
			return washer.call("get_mouth_world")
		if washer is Node2D:
			return (washer as Node2D).global_position
	return _layout_washer_mouth(&"washer_nw")


func _chute_anchor() -> Vector2:
	var chute: Node = level.get_chute() if level.has_method("get_chute") else null
	if chute is Node2D:
		return (chute as Node2D).global_position
	return _layout_chute_center()


func _success_anchor() -> Vector2:
	match TutorialSteps.kind_for(_step_index):
		&"insert", &"strike":
			return _washer_anchor(_target_washer)
		&"deliver":
			return _chute_anchor()
		_:
			return _player_anchor()


## Fallback anchors from `data/layout.json`, used when the M4 scenes are absent so the
## prompts still point at the right place in the room.
func _layout_washer_mouth(washer_id: StringName) -> Vector2:
	for entry in RoomBuilder.layout().get("washers", []):
		if StringName(entry.get("id", "")) != washer_id:
			continue
		var mouth: Array = entry.get("mouth", [])
		if mouth.size() == 2:
			return RoomBuilder.point_world(mouth)
	return Vector2(240, 320)


func _layout_chute_center() -> Vector2:
	var entry: Dictionary = RoomBuilder.layout().get("chute", {})
	return RoomBuilder.point_world(entry.get("center", [160, 90]))


# --- World helpers ----------------------------------------------------------


func _washers() -> Array:
	if level == null or not level.has_method("get_washers"):
		return []
	return level.get_washers()


func _washer_id(washer: Node) -> StringName:
	if washer.has_method("get_washer_id"):
		return StringName(washer.call("get_washer_id"))
	var raw: Variant = washer.get("washer_id")
	if raw != null and String(raw) != "":
		return StringName(raw)
	return StringName(String(washer.name).to_snake_case())


func _washer_by_id(id: StringName) -> Node:
	if level != null and level.has_method("get_washer"):
		return level.call("get_washer", id)
	return null


func _sample_washer_counts() -> Dictionary:
	var counts := {}
	for washer in _washers():
		if not washer.has_method("get_loaded_items"):
			continue
		var loaded: Variant = washer.call("get_loaded_items")
		counts[_washer_id(washer)] = (loaded as Array).size() if loaded is Array else 0
	return counts


## The compatible washer is the one whose requirement matches the tutorial item.
func _pick_match_washer() -> Node:
	var candidates := _washers()
	if candidates.is_empty():
		_target_washer = null
		_target_washer_id = &"washer_nw"
		return null
	for washer in candidates:
		if not washer.has_method("get_requirement"):
			continue
		if StringName(washer.call("get_requirement")) == Config.STARTER_ITEM_COLOR:
			_target_washer = washer
			_target_washer_id = _washer_id(washer)
			return washer
	var fallback: Node = candidates[0]
	_target_washer = fallback
	_target_washer_id = _washer_id(fallback)
	return fallback


func _lock_washers_except(target: Node) -> void:
	if target == null:
		return
	for washer in _washers():
		var id := _washer_id(washer)
		if not _locked_by_director.has(id):
			_locked_by_director[id] = _baseline_lock(id)
		if washer.has_method("set_locked"):
			washer.call("set_locked", washer != target)


func _unlock_washers() -> void:
	for id in _locked_by_director:
		var washer := _washer_by_id(StringName(id))
		if washer != null and washer.has_method("set_locked"):
			washer.call("set_locked", bool(_locked_by_director[id]))
	_locked_by_director.clear()


func _baseline_lock(id: StringName) -> bool:
	if level != null and level.has_method("_is_locked"):
		return bool(level.call("_is_locked", id))
	return false


func _free_washer(washer: Node) -> void:
	if washer == null or not is_instance_valid(washer):
		return
	if not washer.has_method("get_state"):
		return
	var state_now := int(washer.call("get_state"))
	# WASHING/TURBULENT would block the staged insert: finish it so the gate is fair.
	if (state_now == 1 or state_now == 2) and washer.has_method("force_finish"):
		washer.call("force_finish")


func _spawn_dirty(position: Vector2) -> Node:
	if level == null or not level.has_method("spawn_item"):
		return null
	return level.call(
		"spawn_item",
		Config.STARTER_ITEM_ID,
		Config.STARTER_ITEM_COLOR,
		Config.STARTER_ITEM_PATTERN,
		position,
		false
	)


func _spawn_clean_fallback() -> void:
	if level == null or not level.has_method("spawn_item"):
		return
	var item: Node = level.call(
		"spawn_item",
		Config.STARTER_ITEM_ID,
		Config.STARTER_ITEM_COLOR,
		Config.STARTER_ITEM_PATTERN,
		_anchor_in_front(),
		true
	)
	if item != null:
		_clean_item = item
		_gate_item = item


func _ensure_gate_item() -> void:
	if _gate_item != null and is_instance_valid(_gate_item):
		return
	var held: Variant = _player.get("held_item") if _player != null else null
	if held != null and is_instance_valid(held):
		_gate_item = held
		return
	_gate_item = _spawn_dirty(_anchor_in_front())


func _respawn_gate_item() -> void:
	var held: Variant = _player.get("held_item") if _player != null else null
	if held != null and is_instance_valid(held):
		_gate_item = held
		return
	if _gate_item != null and is_instance_valid(_gate_item) and _gate_item is Node2D:
		var item_pos := (_gate_item as Node2D).global_position
		if item_pos.distance_to(_anchor_in_front()) < 260.0:
			return
	_gate_item = _spawn_dirty(_anchor_in_front())


func _find_clean_item() -> Node:
	for item in _items():
		if is_instance_valid(item) and bool(item.get("is_clean")):
			return item
	return null


func _items() -> Array:
	if level == null or not level.has_method("get_items_layer"):
		return []
	var layer: Node = level.call("get_items_layer")
	if layer == null:
		return []
	return layer.get_children()


func clear_gate_items() -> void:
	if level != null and level.has_method("clear_items"):
		level.call("clear_items")
	_gate_item = null
	_clean_item = null


# --- Bookkeeping ------------------------------------------------------------


func _track_travel() -> void:
	if _player == null or not (_player is Node2D):
		return
	var pos := (_player as Node2D).global_position
	var delta := pos.distance_to(_last_player_pos)
	_last_player_pos = pos
	if delta > 0.01:
		_feed({"kind": &"travel", "delta": delta})


func _update_overlay() -> void:
	var granted := bool(state.get("granted", false))
	overlay.set_step(_step_index, TutorialSteps.progress(state))
	overlay.set_soft_skip_available(not granted and bool(state.get("soft_skip_ready", false)))
	if granted:
		return
	match TutorialSteps.kind_for(_step_index):
		&"grab", &"throw", &"grade", &"deliver":
			overlay.move_prompt(_item_anchor())
		_:
			pass


func show_gate_prompt(anchor: Vector2) -> void:
	overlay.show_prompt(TutorialSteps.prompt_for(_step_index), anchor)


func _beat_delta() -> float:
	if debug_delta_t >= 0.0:
		return debug_delta_t
	if not BeatConductor.has_method("delta_to_nearest_beat"):
		return 0.0
	var song_time := float(BeatConductor.call("get_song_time"))
	return float(BeatConductor.call("delta_to_nearest_beat", song_time))


## Camera nudge on the active object: 1.0 → 1.06 → 1.0 in 300 ms, never under reduce motion.
func focus_camera(world_pos: Vector2) -> void:
	if _camera == null or not is_instance_valid(_camera) or Settings.reduce_motion:
		return
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	var target := _camera_base_zoom * 1.06
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(_camera, "zoom", target, 0.14)
	_zoom_tween.tween_property(_camera, "zoom", _camera_base_zoom, 0.16)
	overlay.pulse_at(world_pos, UITheme.ACCENT)

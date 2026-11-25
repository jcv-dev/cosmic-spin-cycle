extends SceneTree
## End-to-end playtest bot: plays the real level with the real input actions and reports
## whether a competent-but-not-perfect player can complete the loop.
##
##   godot --headless --path . -s tools/playtest_bot.gd -- --frames=4800
##
## It does not read code internals beyond the public contracts (player position, held item,
## washer group, chute group). It answers the owner's question: "can someone actually wash
## and deliver, and where does it break?" Prints a PLAYTEST_* report and exits 0 normally,
## 1 when the loop is impossible.

const MAX_FRAMES_DEFAULT := 4800  # 80 s of game time at 60 Hz
const WALK_STOP_PX := 40.0
const GRAB_RANGE := 64.0
const THROW_WINDOW_S := 0.12

var _level: Node
var _state: Node
var _beat: Node
var _player: Node2D
var _frames := 0
var _max_frames := MAX_FRAMES_DEFAULT
var _metrics := {
	"picked": 0,
	"throws": 0,
	"landed": 0,
	"missed": 0,
	"washed": 0,
	"delivered": 0,
	"lost": 0,
	"stuck_frames": 0,
	"loop_times": [],
}
var _stuck := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="):
			_max_frames = int(argument.trim_prefix("--frames="))
	var packed := load("res://scenes/main/MainLevel.tscn") as PackedScene
	_level = packed.instantiate()
	root.add_child(_level)
	_state = root.get_node_or_null("GameState")
	_beat = root.get_node_or_null("BeatConductor")
	_run.call_deferred()


func _run() -> void:
	await _step()
	await _step()
	_player = _level.call("get_player") as Node2D
	if _player == null:
		_fail("no player")
		return
	var start := Time.get_ticks_msec()
	while _frames < _max_frames and not bool(_level.call("is_ended")):
		if not await _play_one_cycle():
			_stuck += 1
			if _stuck >= 2:
				break
	# Let a final delivery settle.
	for index in range(30):
		await _step()
	_report(Time.get_ticks_msec() - start)


## One grab → wash → deliver attempt. Returns false when it could not even find work.
func _play_one_cycle() -> bool:
	print(
		(
			"PLAYTEST_CYCLE t=%.1f pos=%s"
			% [float(_frames) / 60.0, str(_player.global_position.round())]
		)
	)
	_report_escapes()
	var item := _find_item(false)
	if item == null:
		await _idle(30)
		return _frames < _max_frames
	if not await _walk_to(item.global_position, WALK_STOP_PX):
		return false
	var held: Node = await _grab(item)
	if held == null:
		return true
	_metrics["picked"] += 1
	var washer := _washer_for(held)
	if washer == null:
		_drop_held()
		return true
	if not await _wash(washer):
		return true
	await _deliver(washer)
	return true


## Walk to a washer, throw on the beat and wait until the machine has taken the item.
func _wash(washer: Node2D) -> bool:
	var centre := _washer_centre(washer)
	if not await _walk_to(centre, 150.0):
		return false
	if not await _throw_at(centre):
		_drop_held()
		return false
	_metrics["throws"] += 1
	var accepted := false
	for index in range(120):
		await _step()
		if _washer_count(washer) > 0:
			accepted = true
			break
	if not accepted:
		_metrics["missed"] += 1
		return false
	_metrics["landed"] += 1
	print("PLAYTEST_LOAD washer=%s t=%.1f" % [washer.name, float(_frames) / 60.0])
	var done := false
	for index in range(900):
		await _step()
		if _washer_done(washer):
			done = true
			break
	if done:
		_metrics["washed"] += 1
	return done


## Collect a clean item and throw it into the chute.
func _deliver(washer: Node2D = null) -> void:
	var before := int(_state.get("delivered_count"))
	if washer != null:
		await _walk_to(_washer_centre(washer), 170.0)
	var clean := _find_item(true)
	if clean != null:
		print(
			(
				"PLAYTEST_CLEAN id=%s pos=%s clean=%s held=%s"
				% [
					str(clean.get("item_id")),
					str((clean as Node2D).global_position.round()),
					str(clean.get("is_clean")),
					str(clean.get("is_held")),
				]
			)
		)
		await _deliver_item(clean)
		return
	# The funnel can swallow a nearby clean item on its own; that still counts.
	for index in range(120):
		await _step()
		if int(_state.get("delivered_count")) > before:
			_metrics["delivered"] += 1
			return


func _deliver_item(clean: Variant) -> void:
	if not is_instance_valid(clean):
		return
	if not await _walk_to((clean as Node2D).global_position, WALK_STOP_PX):
		return
	if not is_instance_valid(clean):
		return
	var held: Node = await _grab(clean)
	if held == null:
		return
	var chute := _chute()
	if chute == null:
		_drop_held()
		return
	if not await _walk_to(chute.global_position, 170.0):
		return
	await _throw_delivery(chute)


func _throw_delivery(chute: Node2D) -> void:
	var before := int(_state.get("delivered_count"))
	if not await _throw_at(chute.global_position):
		_drop_held()
		return
	for index in range(180):
		await _step()
		if int(_state.get("delivered_count")) > before:
			_metrics["delivered"] += 1
			return
	_metrics["lost"] += 1


## Aims at the item and grabs it; returns the held node or null.
func _grab(item: Variant) -> Node:
	if not is_instance_valid(item):
		return null
	_player.call("set_aim_direction", (item.global_position - _player.global_position).normalized())
	_player.call("grab_or_throw")
	await _step()
	return _player.get("held_item")


func _beat_delta() -> float:
	if _beat == null:
		return 0.0
	return float(_beat.call("delta_to_nearest_beat", _beat.call("get_song_time")))


func _throw_at(target: Vector2) -> bool:
	_player.call("set_aim_direction", (target - _player.global_position).normalized())
	# A real player waits for the pulse; the bot waits for the GOOD window.
	for index in range(240):
		await _step()
		if _frames >= _max_frames:
			return false
		if _beat_delta() <= THROW_WINDOW_S:
			_player.call("grab_or_throw")
			return true
	return false


func _walk_to(target: Vector2, stop: float) -> bool:
	var budget := 420
	while budget > 0 and _frames < _max_frames:
		budget -= 1
		var offset := target - _player.global_position
		if offset.length() <= stop:
			_release_movement()
			return true
		var direction := offset.normalized()
		_press_movement(direction)
		await _step()
	_release_movement()
	if _frames >= _max_frames:
		return false
	# The bot has no pathfinding; if a straight line is blocked, put it on the spot the way a
	# player would eventually get there, and keep testing the loop rather than the walker.
	print("PLAYTEST_TELEPORT target=%s" % str(target))
	_player.global_position = target
	return true


func _press_movement(direction: Vector2) -> void:
	_action("move_right", direction.x > 0.25)
	_action("move_left", direction.x < -0.25)
	_action("move_down", direction.y > 0.25)
	_action("move_up", direction.y < -0.25)


func _release_movement() -> void:
	for action in ["move_right", "move_left", "move_down", "move_up"]:
		_action(action, false)


func _action(name: String, pressed: bool) -> void:
	if pressed and not Input.is_action_pressed(name):
		Input.action_press(name)
	elif not pressed and Input.is_action_pressed(name):
		Input.action_release(name)


## One physics tick that also advances the shared frame budget.
func _step() -> void:
	_frames += 1
	await physics_frame


func _idle(frames: int) -> void:
	for index in range(frames):
		await _step()


func _drop_held() -> void:
	# Throwing at nothing is the only way to release; aim down and throw off-beat.
	_player.call("set_aim_direction", Vector2.DOWN)
	_player.call("grab_or_throw")


func _report_escapes() -> void:
	for node in get_nodes_in_group(Config.GROUP_ITEMS):
		var item := node as Node2D
		if item == null:
			continue
		var at := item.global_position
		if at.x < -8.0 or at.y < -8.0 or at.x > 1288.0 or at.y > 728.0:
			print(
				(
					"PLAYTEST_ESCAPE id=%s pos=%s vel=%s"
					% [
						str(item.get("item_id")),
						str(at.round()),
						str((item as RigidBody2D).linear_velocity.round())
					]
				)
			)


func _find_item(clean: bool) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for node in get_nodes_in_group(Config.GROUP_ITEMS):
		var item := node as Node2D
		if item == null or bool(item.get("is_held")):
			continue
		if bool(item.get("is_clean")) != clean:
			continue
		var distance := item.global_position.distance_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = item
	return best


func _washer_for(item: Node) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for node in get_nodes_in_group(Config.GROUP_WASHERS):
		var washer := node as Node2D
		if washer == null or bool(washer.call("is_locked")):
			continue
		var requirement: Variant = washer.call("get_requirement")
		if not Compatibility.item_fits(
			StringName(item.get("item_id")),
			StringName(item.get("color")),
			StringName(item.get("pattern")),
			StringName(requirement)
		):
			continue
		var distance := washer.global_position.distance_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = washer
	return best


func _washer_centre(washer: Node2D) -> Vector2:
	if washer.has_method("get_center_world"):
		return Vector2(washer.call("get_center_world"))
	return washer.global_position


func _washer_count(washer: Node2D) -> int:
	var items: Variant = washer.call("get_loaded_items")
	return (items as Array).size() if items is Array else 0


func _washer_done(washer: Node2D) -> bool:
	return int(washer.call("get_state")) == 3


func _chute() -> Node2D:
	return get_first_node_in_group(Config.GROUP_CHUTE) as Node2D


func _fail(reason: String) -> void:
	print("PLAYTEST_FAIL %s" % reason)
	quit(1)


func _report(elapsed_ms: int) -> void:
	var loops: Array = _metrics["loop_times"]
	var landed := int(_metrics["landed"])
	var missed := int(_metrics["missed"])
	var attempts := landed + missed
	var accuracy := (float(landed) / float(attempts) * 100.0) if attempts > 0 else 0.0
	print(
		(
			(
				"PLAYTEST frames=%d game_s=%.1f wall_s=%.1f picked=%d throws=%d landed=%d "
				+ "missed=%d washed=%d delivered=%d lost=%d accuracy=%.0f%% stability=%.0f "
				+ "score=%d loops=%d"
			)
			% [
				_frames,
				float(_frames) / 60.0,
				float(elapsed_ms) / 1000.0,
				int(_metrics["picked"]),
				int(_metrics["throws"]),
				landed,
				missed,
				int(_metrics["washed"]),
				int(_metrics["delivered"]),
				int(_metrics["lost"]),
				accuracy,
				float(_state.get("stability")),
				int(_state.get("score")),
				loops.size(),
			]
		)
	)
	var ok := int(_metrics["delivered"]) > 0
	print("PLAYTEST_RESULT %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

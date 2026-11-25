class_name Player
extends CharacterBody2D
## Pip: 8-way top-down movement, dash, magnetic grab/throw. Stabilising a washer is a hold.
##
## Rhythm is graded in `_input()` only (AGENTS §A2.7): a 60 Hz `_physics_process` would
## quantise Δt by 16.7 ms against a ±65 ms PERFECT window. Every player action that the
## scoring layer cares about emits exactly one `GameState.register_grade()`.
##
## Game-feel contract (this pass): the body keeps a float position while the art is snapped
## to the 4 px art grid, braking is a ~200 ms ease-out instead of a half-second glide,
## direction reversals get a 1.6× accel boost, presses buffer for 120 ms, and aim gets an
## 8-way assist plus a sticky compatible-washer reticle.

signal grabbed(item: Node)
signal thrown(item: Node, grade: int)
signal aim_changed(dir: Vector2)

## A/B tuning profiles. Change `FEEL_PRESET` below to compare them by hand; `SNAPPY` is
## the recommended default (measured turnaround 167 ms, stop 200 ms).
enum FeelPreset { SNAPPY, WEIGHTED, FLOATY }

const AIM_EPSILON := 0.0001
const AIM_TURN_DOT := 0.9999
const STICK_DEADZONE := 0.2
const ART_SPRITE_ID := "char_pip"

# --- Feel tunables (owned here until the lead promotes them to Config) -----------------
## Extra acceleration while the input opposes current velocity, so turnarounds snap.
const FEEL_REVERSAL_BOOST := 1.6
## The boost outlives the opposing half of the turnaround so the new direction bites too.
const FEEL_TURN_BOOST_S := 0.16
## Multiplier on the frozen Config.PLAYER_FRICTION decay: 2.5 gives a ~200 ms ease-out.
const FEEL_BRAKE_GAIN := 2.5
## A buffered press fires if it becomes legal inside this window.
const FEEL_BUFFER_S := 0.12
## Stick directions within this angle of a cardinal/diagonal snap to it.
const FEEL_SNAP_ASSIST_DEG := 12.0
## The reticle sticks to a compatible washer inside this cone and range.
const FEEL_ASSIST_ANGLE_DEG := 18.0
const FEEL_ASSIST_RANGE_PX := 420.0
## Sticky reticle offset in world px while a target is assisted.
const FEEL_RETICLE_OFFSET := 2.0
## One step every N world px of travel; dust every second step (≤ 24 particles alive).
const FEEL_STEP_DISTANCE_PX := 48.0
const FEEL_STEP_MIN_SPEED := 40.0
const FEEL_IDLE_BREATH_S := 0.62
const FEEL_RUN_LEAN_S := 0.09
const FEEL_SHADOW_FRAME_S := 0.09
const FEEL_DASH_RUMBLE_MS := 70
const FEEL_PRESET := FeelPreset.SNAPPY
## `reversal_boost`, `brake_gain`, `turn_boost_s` and `accel_scale` per profile.
const FEEL_PROFILES := {
	FeelPreset.SNAPPY:
	{"reversal_boost": 1.6, "brake_gain": 2.5, "turn_boost_s": 0.16, "accel_scale": 1.0},
	FeelPreset.WEIGHTED:
	{"reversal_boost": 1.35, "brake_gain": 1.5, "turn_boost_s": 0.12, "accel_scale": 0.9},
	FeelPreset.FLOATY:
	{"reversal_boost": 1.15, "brake_gain": 0.8, "turn_boost_s": 0.08, "accel_scale": 0.78},
}

## A cooldown keeps the dash from being spammed.
## Config has no constant for it yet, so it is an exported tunable instead of a literal.
@export var dash_cooldown_s := 0.24
## Below this fraction of max speed the idle friction snaps to rest (sub-pixel drift).
@export var rest_speed_ratio := 0.025
## Mouse aim is sticky: once the mouse has been used it stays authoritative until the right
## stick is moved. The old 1.2 s timeout silently reverted aim and made the reticle feel
## like it stopped following the mouse.
var mouse_seen := false

var held_item: Node = null
var aim_direction := Vector2.DOWN
var is_dashing := false
var dash_cooldown_left := 0.0
var last_dash_distance := 0.0
var last_grade := -1
## Gravity-pocket effect (D045): movement axes are flipped while true.
var input_inverted := false
## Active A/B profile; `set_feel_preset()` lets a debug menu swap it live.
var feel_preset := FEEL_PRESET

var _dash_time := 0.0
var _dash_direction := Vector2.ZERO
var _dash_origin := Vector2.ZERO
var _aim_override := Vector2.ZERO
var _has_aim_override := false
var _pip: AnimatedSprite2D
var _art_action := ""
var _art_time := 0.0
var _anim_clock := 0.0
var _shadow_polygon: Polygon2D = null
var _shadow_frames: Array[PackedVector2Array] = []
var _shadow_frame := -1
var _shadow_clock := 0.0
var _step_accum := 0.0
var _step_count := 0
var _buffered_action: StringName = &""
var _buffer_left := 0.0
var _buffered_grade := -1
var _turn_boost_left := 0.0
var _assisted_target: Node = null
var _assisted_target_pos := Vector2.ZERO
var _foot_fx: FootFX = null
var _reversal_boost := FEEL_REVERSAL_BOOST
var _brake_gain := FEEL_BRAKE_GAIN
var _turn_boost_s := FEEL_TURN_BOOST_S
var _accel_scale := 1.0

@onready var visual: Node2D = $Visual
@onready var grabber: MagneticGrabber = $Grabber
@onready var aim_indicator: Node2D = $AimIndicator


func _ready() -> void:
	add_to_group(Config.GROUP_PLAYER)
	_apply_feel_preset(feel_preset)
	_foot_fx = get_node_or_null("FX") as FootFX
	_setup_art()
	if aim_indicator != null:
		aim_indicator.rotation = aim_direction.angle()


func _notification(what: int) -> void:
	# A buffered press must never survive a pause, an unpause or a shift end.
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		_clear_buffer()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		mouse_seen = true
	if event.is_action_pressed("grab_throw"):
		_request_action(&"grab_throw")
	elif event.is_action_pressed("rhythm_strike"):
		_request_action(&"rhythm_strike")


func _physics_process(delta: float) -> void:
	dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
	_turn_boost_left = maxf(_turn_boost_left - delta, 0.0)
	_prune_held_item()
	_update_aim()
	_update_assisted_target()
	_tick_buffer(delta)
	_update_art(delta)

	if is_dashing:
		_dash_time += delta
		move_and_slide()
		_sync_visual(delta)
		if _dash_time >= Config.DASH_DURATION_S:
			_finish_dash()
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_inverted:
		input = -input
	if input == Vector2.ZERO:
		_brake(delta)
	else:
		_accelerate(input, delta)
	move_and_slide()
	_track_steps(delta)
	_sync_visual(delta)


## Grades the current action. Kept as the single grading path so tests and gameplay agree.
## The window scale comes from the shift difficulty (D047): CALM widens, CHAOS tightens.
func get_throw_grade() -> int:
	var delta_t: float = BeatConductor.delta_to_nearest_beat(BeatConductor.get_song_time())
	return RhythmEvaluator.evaluate(delta_t, Settings.window_scale())


## Gravity pocket: flipping the axes is disorientation, never damage (D045).
func set_input_inverted(on: bool) -> void:
	input_inverted = on


func grab_or_throw() -> void:
	_try_grab_or_throw()


## Dash-only action (docs/DECISIONS.md D043). The old rhythm strike used to grade and hit
## washers; stabilising a machine is now a 3 s hold of the interact action next to it.
func do_dash() -> void:
	if GameState.is_ended:
		return
	_play_action_art("strike")
	dash(aim_direction)


## Kept as an alias so older sandboxes and tests still compile.
func do_strike() -> void:
	do_dash()


## Starts a collision-safe dash. Travel is done by `move_and_slide`, so walls stop it early.
func dash(direction: Vector2 = Vector2.ZERO) -> bool:
	if is_dashing or dash_cooldown_left > 0.0:
		return false
	var dir := direction
	if dir.length() < AIM_EPSILON:
		dir = aim_direction
	if dir.length() < AIM_EPSILON:
		dir = Vector2.DOWN
	_dash_direction = dir.normalized()
	_dash_origin = global_position
	_dash_time = 0.0
	is_dashing = true
	last_dash_distance = 0.0
	velocity = _dash_direction * (Config.DASH_DISTANCE / Config.DASH_DURATION_S)
	_play_dash_feel()
	return true


func is_dash_ready() -> bool:
	return not is_dashing and dash_cooldown_left <= 0.0


func get_aim_direction() -> Vector2:
	return aim_direction


## Sticky compatible washer the reticle is currently snapping to, or null (HUD stream).
func get_assisted_target() -> Node:
	return _assisted_target


## Hold point: `pos + aim * (HOLD_DISTANCE + item radius)`, so large items clear Pip.
func get_hold_position() -> Vector2:
	var distance := Config.HOLD_DISTANCE
	if held_item != null and is_instance_valid(held_item):
		var data: Variant = held_item.get(&"data")
		if data != null:
			distance += float(data.radius) * float(Config.ART_SCALE)
	return global_position + aim_direction * distance


## Deterministic aim for tests/tools. Mouse and stick input keep priority when cleared.
func set_aim_direction(direction: Vector2) -> void:
	if direction.length() < AIM_EPSILON:
		return
	_aim_override = direction.normalized()
	_has_aim_override = true
	_apply_aim(_aim_override)


func clear_aim_override() -> void:
	_has_aim_override = false


## Swaps the movement profile at runtime (debug menu / A-B playtests).
func set_feel_preset(preset: int) -> void:
	feel_preset = clampi(preset, 0, FEEL_PROFILES.size() - 1)
	_apply_feel_preset(feel_preset)


func get_buffered_action() -> StringName:
	return _buffered_action


func get_buffer_left() -> float:
	return _buffer_left


func _accelerate(input: Vector2, delta: float) -> void:
	var acceleration := Config.PLAYER_ACCEL * _accel_scale
	if _turn_boost_left > 0.0:
		acceleration *= _reversal_boost
	elif velocity.length() > 1.0 and input.dot(velocity.normalized()) < -0.1:
		_turn_boost_left = _turn_boost_s
		acceleration *= _reversal_boost
	velocity = velocity.move_toward(input * Config.PLAYER_MAX_SPEED, acceleration * delta)


func _brake(delta: float) -> void:
	velocity *= pow(1.0 - Config.PLAYER_FRICTION, 60.0 * delta * _brake_gain)
	if velocity.length() < Config.PLAYER_MAX_SPEED * rest_speed_ratio:
		velocity = Vector2.ZERO


func _track_steps(delta: float) -> void:
	var speed := velocity.length()
	if speed < FEEL_STEP_MIN_SPEED or _foot_fx == null:
		return
	_step_accum += speed * delta
	while _step_accum >= FEEL_STEP_DISTANCE_PX:
		_step_accum -= FEEL_STEP_DISTANCE_PX
		_step_count += 1
		if _step_count % 2 == 0:
			_foot_fx.step_puff(velocity.normalized())


func _apply_feel_preset(preset: int) -> void:
	var profile: Dictionary = FEEL_PROFILES.get(preset, {})
	if profile.is_empty():
		return
	_reversal_boost = float(profile.get("reversal_boost", FEEL_REVERSAL_BOOST))
	_brake_gain = float(profile.get("brake_gain", FEEL_BRAKE_GAIN))
	_turn_boost_s = float(profile.get("turn_boost_s", FEEL_TURN_BOOST_S))
	_accel_scale = float(profile.get("accel_scale", 1.0))


func _request_action(action: StringName) -> void:
	if GameState.is_ended:
		return
	if _try_action(action):
		_clear_buffer()
		return
	_buffered_grade = -1
	_buffered_action = action
	_buffer_left = FEEL_BUFFER_S


func _try_action(action: StringName) -> bool:
	match action:
		&"grab_throw":
			return _try_grab_or_throw()
		&"rhythm_strike":
			if not is_dash_ready():
				return false
			_play_action_art("strike")
			dash(aim_direction)
			return true
	return false


func _tick_buffer(delta: float) -> void:
	if _buffered_action == &"":
		return
	if GameState.is_ended or get_tree().paused:
		_clear_buffer()
		return
	_buffer_left -= delta
	if _buffer_left <= 0.0:
		_clear_buffer()
		return
	_fire_buffered_action()


func _fire_buffered_action() -> void:
	if _buffered_action == &"rhythm_strike":
		if not is_dash_ready():
			return
		_play_action_art("strike")
		dash(aim_direction)
		_clear_buffer()
		return
	if _try_action(_buffered_action):
		_clear_buffer()


func _clear_buffer() -> void:
	_buffered_action = &""
	_buffer_left = 0.0
	_buffered_grade = -1


func _update_aim() -> void:
	var target := aim_direction
	if _has_aim_override:
		target = _aim_override
	else:
		var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		if stick.length() > STICK_DEADZONE:
			target = _snap_to_eight(stick)
		elif mouse_seen:
			target = get_global_mouse_position() - global_position
	if target.length() < AIM_EPSILON:
		return
	_apply_aim(target.normalized())


## Gamepad aim assist: within 12° of a cardinal/diagonal, snap to it.
func _snap_to_eight(direction: Vector2) -> Vector2:
	var angle := direction.angle()
	var step := TAU / 8.0
	var snapped_angle := roundf(angle / step) * step
	var difference := absf(wrapf(angle - snapped_angle, -PI, PI))
	if difference <= deg_to_rad(FEEL_SNAP_ASSIST_DEG):
		return Vector2.from_angle(snapped_angle)
	return direction


func _apply_aim(direction: Vector2) -> void:
	if direction.dot(aim_direction) < AIM_TURN_DOT:
		aim_direction = direction
		aim_changed.emit(aim_direction)
	_update_reticle()


func _update_assisted_target() -> void:
	var previous := _assisted_target
	_assisted_target = null
	_assisted_target_pos = Vector2.ZERO
	var cone := cos(deg_to_rad(FEEL_ASSIST_ANGLE_DEG))
	var best_distance := INF
	var best_target: Node = null
	var best_position := Vector2.ZERO
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group(Config.GROUP_WASHERS):
		var washer := node as Node2D
		if washer == null or not is_instance_valid(washer):
			continue
		if not _washer_accepts(washer):
			continue
		var mouth := _mouth_position(washer)
		var offset := mouth - global_position
		var distance := offset.length()
		if distance < 1.0 or distance > FEEL_ASSIST_RANGE_PX:
			continue
		if (offset / distance).dot(aim_direction) < cone:
			continue
		if washer == previous:
			best_target = washer
			best_position = mouth
			best_distance = distance
			break
		if distance < best_distance:
			best_distance = distance
			best_target = washer
			best_position = mouth
	_assisted_target = best_target
	_assisted_target_pos = best_position
	_update_reticle()


func _update_reticle() -> void:
	if aim_indicator == null:
		return
	if _assisted_target != null and is_instance_valid(_assisted_target):
		var offset := _assisted_target_pos - global_position
		if offset.length() > AIM_EPSILON:
			aim_indicator.rotation = offset.angle()
			aim_indicator.position = offset.normalized() * FEEL_RETICLE_OFFSET
			return
	aim_indicator.position = Vector2.ZERO
	aim_indicator.rotation = aim_direction.angle()


func _washer_accepts(washer: Node2D) -> bool:
	var requirement := &""
	if washer.has_method("get_requirement"):
		var value: Variant = washer.call("get_requirement")
		if value is StringName or value is String:
			requirement = StringName(value)
	else:
		var property: Variant = washer.get("requirement")
		if property is StringName or property is String:
			requirement = StringName(property)
	if requirement == &"" or requirement == &"wild":
		return true
	var item := held_item as LaundryItem
	if item == null:
		return true
	return Compatibility.item_fits(item.item_id, item.color, item.pattern, requirement)


func _mouth_position(washer: Node2D) -> Vector2:
	if washer.has_method("get_mouth_position"):
		var value: Variant = washer.call("get_mouth_position")
		if value is Vector2:
			return value
	var property: Variant = washer.get("mouth_position")
	if property is Vector2:
		return property
	return washer.global_position


func _throw_held_item() -> void:
	var item := grabber.held_item
	if item == null:
		return
	var grade := get_throw_grade()
	var applied := false
	if item.has_method("throw_with_impulse"):
		applied = bool(item.throw_with_impulse(aim_direction, grade, velocity))
	if not applied:
		grabber.drop()
		return
	GameState.register_grade(grade)
	last_grade = grade
	_play_action_art("throw")
	held_item = null
	grabber.drop()
	thrown.emit(item, grade)


func _try_grab_or_throw() -> bool:
	if GameState.is_ended:
		return false
	if grabber.held_item != null:
		_throw_held_item()
		return true
	var target := grabber.find_target(global_position, Config.GRAB_RADIUS)
	if target == null:
		return false
	if not grabber.grab(target):
		return false
	held_item = target
	_play_grab_feel(target)
	grabbed.emit(target)
	return true


func _play_grab_feel(item: Node) -> void:
	if item.has_method("play_grab_pull"):
		item.call("play_grab_pull", get_hold_position())
	if _foot_fx != null:
		_foot_fx.grab_tracer(global_position, (item as Node2D).global_position)
		_foot_fx.play_click()


func _play_dash_feel() -> void:
	if _foot_fx != null:
		_foot_fx.dash_trail(_pip, 3, 0.06)
		_foot_fx.floor_streak(global_position, _dash_direction)
	_juice_call("shake", 0.58, 0.09)
	_juice_call("punch_zoom", 0.012, 0.1)
	if get_node_or_null("/root/Juice") != null:
		_juice_call("rumble", 0.35, 0.0, FEEL_DASH_RUMBLE_MS)
	else:
		_dash_rumble()


func _dash_rumble() -> void:
	if Settings.reduce_motion or Input.get_connected_joypads().is_empty():
		return
	Input.start_joy_vibration(0, 0.35, 0.0, float(FEEL_DASH_RUMBLE_MS) / 1000.0)


func _juice_call(
	method: StringName, a: Variant = null, b: Variant = null, c: Variant = null
) -> void:
	var juice := get_node_or_null("/root/Juice")
	if juice == null or not juice.has_method(method):
		return
	if c != null:
		juice.call(method, a, b, c)
	elif b != null:
		juice.call(method, a, b)
	elif a != null:
		juice.call(method, a)
	else:
		juice.call(method)


func _finish_dash() -> void:
	is_dashing = false
	dash_cooldown_left = dash_cooldown_s
	last_dash_distance = _dash_origin.distance_to(global_position)
	velocity = velocity.limit_length(Config.PLAYER_MAX_SPEED)


func _prune_held_item() -> void:
	if held_item != null and not is_instance_valid(held_item):
		held_item = null


func _setup_art() -> void:
	_build_shadow_frames()
	_shadow_polygon = visual.get_node_or_null("Shadow") as Polygon2D
	if _shadow_polygon != null:
		_shadow_polygon.scale = Vector2.ONE
		_apply_shadow_frame(0)
	if not SpriteSheet.has_sheet(ART_SPRITE_ID):
		return
	_pip = AnimatedSprite2D.new()
	_pip.name = "Pip"
	visual.add_child(_pip)
	if not SpriteSheet.configure(_pip, ART_SPRITE_ID, &"idle_down"):
		_pip.queue_free()
		_pip = null
		return
	_pip.animation_finished.connect(_on_pip_animation_finished)
	_pip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for child in visual.get_children():
		if child == _pip:
			continue
		var polygon := child as Polygon2D
		if polygon == null:
			continue
		polygon.visible = polygon.name == "Shadow"


## Four shadow silhouettes cycled by frame, never by scale: pixel art must not squash.
func _build_shadow_frames() -> void:
	_shadow_frames.clear()
	for frame in range(4):
		var radius_x := 36.0 + float(frame % 2) * 2.0
		var radius_y := 8.0 + float((frame + 1) % 2) * 2.0
		var points := PackedVector2Array()
		for index in range(20):
			var angle := TAU * float(index) / 20.0
			points.append(
				Vector2(roundf(cos(angle) * radius_x), 12.0 + roundf(sin(angle) * radius_y))
			)
		_shadow_frames.append(points)


func _apply_shadow_frame(index: int) -> void:
	if _shadow_polygon == null or _shadow_frames.is_empty():
		return
	var clamped := clampi(index, 0, _shadow_frames.size() - 1)
	if clamped == _shadow_frame:
		return
	_shadow_frame = clamped
	_shadow_polygon.polygon = _shadow_frames[clamped]


func _sync_visual(delta: float) -> void:
	if visual == null:
		return
	_anim_clock += delta
	var art := float(Config.ART_SCALE)
	var base := (global_position / art).round() * art
	var offset := Vector2.ZERO
	var moving := velocity.length() > 12.0
	if moving:
		var lean_frame := int(_anim_clock / FEEL_RUN_LEAN_S) % 2
		if lean_frame == 0:
			var lean := velocity.normalized()
			offset = Vector2(roundf(lean.x), roundf(lean.y)) * art
	else:
		var breath_frame := int(_anim_clock / FEEL_IDLE_BREATH_S) % 2
		if breath_frame == 1:
			offset.y -= art
	visual.position = base - global_position + offset
	if _shadow_polygon != null:
		_shadow_polygon.position = -offset
		_shadow_clock += delta
		if _shadow_clock >= FEEL_SHADOW_FRAME_S:
			_shadow_clock = 0.0
			_apply_shadow_frame((_shadow_frame + 1) % _shadow_frames.size())


func _play_action_art(action: String) -> void:
	if _pip == null:
		return
	_art_action = action
	_art_time = 0.35
	_apply_art_animation()


func _update_art(delta: float) -> void:
	if _pip == null:
		return
	if _art_time > 0.0:
		_art_time = maxf(_art_time - delta, 0.0)
		if _art_time <= 0.0:
			_art_action = ""
	_apply_art_animation()


func _apply_art_animation() -> void:
	if _pip == null or _pip.sprite_frames == null:
		return
	var dir := _facing_suffix()
	var animation: StringName
	var run_speed := clampf(velocity.length() / Config.PLAYER_MAX_SPEED, 0.55, 1.35)
	if _art_action != "":
		animation = StringName("%s_%s" % [_art_action, dir])
		_pip.speed_scale = 1.0
	elif velocity.length() > 12.0:
		animation = StringName("run_%s" % dir)
		_pip.speed_scale = run_speed
	else:
		animation = StringName("idle_%s" % dir)
		_pip.speed_scale = 1.0
	if not _pip.sprite_frames.has_animation(animation):
		return
	if _pip.animation != animation:
		_pip.play(animation)
	_pip.flip_h = dir == "side" and aim_direction.x < 0.0


func _facing_suffix() -> String:
	if absf(aim_direction.x) > absf(aim_direction.y):
		return "side"
	return "up" if aim_direction.y < 0.0 else "down"


func _on_pip_animation_finished() -> void:
	if _art_action != "":
		_art_action = ""
		_art_time = 0.0
		_apply_art_animation()

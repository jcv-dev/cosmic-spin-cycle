class_name Player
extends CharacterBody2D
## Pip: 8-way top-down movement, dash, magnetic grab/throw and the rhythm strike.
##
## Rhythm is graded in `_input()` only (AGENTS §A2.7): a 60 Hz `_physics_process` would
## quantise Δt by 16.7 ms against a ±65 ms PERFECT window. Every player action that the
## scoring layer cares about emits exactly one `GameState.register_grade()`.

signal grabbed(item: Node)
signal thrown(item: Node, grade: int)
signal struck(washer: Node, grade: int)
signal aim_changed(dir: Vector2)

const AIM_EPSILON := 0.0001
const AIM_TURN_DOT := 0.9999
const STICK_DEADZONE := 0.2
const STRIKE_CONE_DOT := 0.5
const ART_TARGET_HEIGHT_PX := 34.0
const ART_SPRITE_ID := "char_pip"

## A cooldown keeps dash from being spammed while a strike is already the beat action.
## Config has no constant for it yet, so it is an exported tunable instead of a literal.
@export var dash_cooldown_s := 0.24
## Below this fraction of max speed the idle friction snaps to rest (sub-pixel drift).
@export var rest_speed_ratio := 0.025
## Mouse aim keeps priority for this long after the last mouse motion, then stick wins.
@export var mouse_aim_timeout_ms := 1200

var held_item: Node = null
var aim_direction := Vector2.DOWN
var is_dashing := false
var dash_cooldown_left := 0.0
var last_dash_distance := 0.0
var last_grade := -1

var _dash_time := 0.0
var _dash_direction := Vector2.ZERO
var _dash_origin := Vector2.ZERO
var _mouse_active_until := 0
var _aim_override := Vector2.ZERO
var _has_aim_override := false

@onready var visual: Node2D = $Visual
@onready var grabber: MagneticGrabber = $Grabber
@onready var aim_indicator: Node2D = $AimIndicator
@onready var art_sprite: Sprite2D = $Visual/Art


func _ready() -> void:
	add_to_group(Config.GROUP_PLAYER)
	_setup_art()
	if aim_indicator != null:
		aim_indicator.rotation = aim_direction.angle()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_mouse_active_until = Time.get_ticks_msec() + mouse_aim_timeout_ms
	if event.is_action_pressed("grab_throw"):
		grab_or_throw()
	elif event.is_action_pressed("rhythm_strike"):
		do_strike()


func _physics_process(delta: float) -> void:
	dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
	_prune_held_item()
	_update_aim()

	if is_dashing:
		_dash_time += delta
		move_and_slide()
		if _dash_time >= Config.DASH_DURATION_S:
			_finish_dash()
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input == Vector2.ZERO:
		velocity *= pow(1.0 - Config.PLAYER_FRICTION, 60.0 * delta)
		if velocity.length() < Config.PLAYER_MAX_SPEED * rest_speed_ratio:
			velocity = Vector2.ZERO
	else:
		velocity = velocity.move_toward(
			input * Config.PLAYER_MAX_SPEED, Config.PLAYER_ACCEL * delta
		)
	move_and_slide()


## Grades the current action. Kept as the single grading path so tests and gameplay agree.
func get_throw_grade() -> int:
	var delta_t: float = BeatConductor.delta_to_nearest_beat(BeatConductor.get_song_time())
	return RhythmEvaluator.evaluate(delta_t)


func grab_or_throw() -> void:
	if GameState.is_ended:
		return
	if grabber.held_item != null:
		_throw_held_item()
		return
	var target := grabber.find_target(global_position, Config.GRAB_RADIUS)
	if target == null:
		return
	if grabber.grab(target):
		held_item = target
		grabbed.emit(target)


## Rhythm strike: grade once, dash toward the aim, then report every washer in front.
func do_strike() -> void:
	if GameState.is_ended:
		return
	var grade := get_throw_grade()
	GameState.register_grade(grade)
	last_grade = grade
	dash(aim_direction)
	for node in get_tree().get_nodes_in_group(Config.GROUP_WASHERS):
		var washer := node as Node2D
		if washer == null:
			continue
		var offset := washer.global_position - global_position
		var distance := offset.length()
		if distance > Config.STRIKE_RANGE_PX:
			continue
		if distance > AIM_EPSILON and offset.normalized().dot(aim_direction) < STRIKE_CONE_DOT:
			continue
		struck.emit(washer, grade)


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
	return true


func is_dash_ready() -> bool:
	return not is_dashing and dash_cooldown_left <= 0.0


func get_aim_direction() -> Vector2:
	return aim_direction


## Hold point for the grabbed item: `pos + aim * HOLD_DISTANCE` (AGENTS §A7).
func get_hold_position() -> Vector2:
	return global_position + aim_direction * Config.HOLD_DISTANCE


## Deterministic aim for tests/tools. Mouse and stick input keep priority when cleared.
func set_aim_direction(direction: Vector2) -> void:
	if direction.length() < AIM_EPSILON:
		return
	_aim_override = direction.normalized()
	_has_aim_override = true
	_apply_aim(_aim_override)


func clear_aim_override() -> void:
	_has_aim_override = false


func _update_aim() -> void:
	var target := aim_direction
	if _has_aim_override:
		target = _aim_override
	elif Time.get_ticks_msec() <= _mouse_active_until:
		target = get_global_mouse_position() - global_position
	else:
		var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		if stick.length() > STICK_DEADZONE:
			target = stick
	if target.length() < AIM_EPSILON:
		return
	_apply_aim(target.normalized())


func _apply_aim(direction: Vector2) -> void:
	if direction.dot(aim_direction) < AIM_TURN_DOT:
		aim_direction = direction
		aim_changed.emit(aim_direction)
	if aim_indicator != null:
		aim_indicator.rotation = aim_direction.angle()


func _throw_held_item() -> void:
	var item := grabber.held_item
	if item == null:
		return
	var grade := get_throw_grade()
	var applied := false
	if item.has_method("throw_with_impulse"):
		applied = bool(item.throw_with_impulse(aim_direction, grade))
	if not applied:
		grabber.drop()
		return
	GameState.register_grade(grade)
	last_grade = grade
	held_item = null
	grabber.drop()
	thrown.emit(item, grade)


func _finish_dash() -> void:
	is_dashing = false
	dash_cooldown_left = dash_cooldown_s
	last_dash_distance = _dash_origin.distance_to(global_position)
	velocity = velocity.limit_length(Config.PLAYER_MAX_SPEED)


func _prune_held_item() -> void:
	if held_item != null and not is_instance_valid(held_item):
		held_item = null


func _setup_art() -> void:
	var texture := ItemVisual.frame_texture(ART_SPRITE_ID, &"idle_down")
	if texture == null or art_sprite == null:
		return
	art_sprite.texture = texture
	var size := texture.get_size()
	if size.y > 0.0:
		art_sprite.scale = Vector2.ONE * (ART_TARGET_HEIGHT_PX / size.y)
	art_sprite.visible = true
	for child in visual.get_children():
		var polygon := child as Polygon2D
		if polygon != null:
			polygon.visible = false

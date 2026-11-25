class_name LaundryItem
extends RigidBody2D
## A laundry item driven entirely by `data/items.tres` (GDD §6).
##
## Ownership: the grabber decides *who* is held, the player decides *when* it is thrown,
## and this body owns *how* it moves. All game-feel numbers come from Config or ItemData;
## the two greybox-only tunables (sock slide delay/speed) are named constants below until
## the lead promotes them to Config.

signal fell_off_belt
signal delivered
signal squelched

## GDD §6: a sock dropped un-thrown slides randomly after a short grace period.
const SOCK_SLIDE_DELAY_S := 0.4
const SOCK_SLIDE_SPEED := 120.0
const MIN_INPUT_LENGTH := 0.0001

@export var item_id: StringName = &"rocky"
@export var color: StringName = &"red"
@export var pattern: StringName = &"solid"

var data: ItemData = null
var is_held := false
var is_clean := false
var throw_count := 0

var _holder: Node2D = null
var _throw_armed := false
var _shape_owned := false
var _sock_slide_timer := 0.0
var _boomerang_time := 0.0
var _boomerang_direction := Vector2.ZERO
var _rng := RandomNumberGenerator.new()

@onready var visual: ItemVisual = get_node_or_null("Visual") as ItemVisual
@onready
var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready
var squelch_player: AudioStreamPlayer2D = get_node_or_null("SquelchPlayer") as AudioStreamPlayer2D


func _ready() -> void:
	add_to_group(Config.GROUP_ITEMS)
	_rng.randomize()
	if visual != null:
		visual.top_level = true
		visual.z_index = 1
	if data == null:
		data = _lookup(item_id)
	_apply_data()
	_sync_visual()


## Public factory hook. Safe before or after the node enters the tree.
func setup(
	p_id: StringName, p_color: StringName, p_pattern: StringName, clean: bool = false
) -> void:
	item_id = p_id
	color = p_color
	pattern = p_pattern
	is_clean = clean
	data = _lookup(p_id)
	if is_node_ready():
		_apply_data()
		_sync_visual()


func begin_hold(holder: Node) -> void:
	if is_held:
		return
	is_held = true
	_holder = holder as Node2D
	_throw_armed = false
	_sock_slide_timer = 0.0
	_boomerang_time = 0.0
	collision_mask = Config.CollisionLayer.WORLD
	sleeping = false
	gravity_scale = 0.0
	if data != null and data.special == ItemData.Special.SQUELCH:
		_play_squelch()


func end_hold() -> void:
	if not is_held:
		return
	is_held = false
	_holder = null
	collision_mask = Config.CollisionLayer.WORLD | Config.CollisionLayer.ITEMS
	_throw_armed = true
	if data != null and data.special == ItemData.Special.SQUELCH:
		_sock_slide_timer = SOCK_SLIDE_DELAY_S


## Applies exactly one throw impulse. Returns false when there is nothing to throw, which
## is what makes a second call in the same action a no-op (no double impulses).
func throw_with_impulse(direction: Vector2, grade: int) -> bool:
	if direction.length() < MIN_INPUT_LENGTH:
		return false
	if is_held:
		end_hold()
	if not _throw_armed:
		return false
	_throw_armed = false
	_sock_slide_timer = 0.0

	var dir := direction.normalized()
	var multiplier := RhythmEvaluator.force_multiplier(grade)
	if data != null and data.id == &"gas_giant" and grade == RhythmEvaluator.Grade.MISS:
		multiplier *= Config.THROW_GAS_OFFBEAT_SCALE
	apply_central_impulse(dir * Config.THROW_SPEED * multiplier * mass)
	if (
		data != null
		and data.special == ItemData.Special.BOOMERANG
		and grade == RhythmEvaluator.Grade.MISS
	):
		_boomerang_direction = Vector2(-dir.y, dir.x)
		_boomerang_time = Config.BOOMERANG_DURATION_S
	throw_count += 1
	return true


func mark_clean() -> void:
	is_clean = true
	if visual != null:
		visual.set_clean(true)


func report_fell_off_belt() -> void:
	fell_off_belt.emit()


func report_delivered() -> void:
	delivered.emit()


func get_item_id() -> StringName:
	return item_id


func _process(_delta: float) -> void:
	if visual != null:
		visual.global_position = global_position
		visual.rotation = 0.0


func _physics_process(delta: float) -> void:
	if is_held:
		sleeping = false
	if _sock_slide_timer > 0.0 and not is_held:
		_sock_slide_timer = maxf(_sock_slide_timer - delta, 0.0)
		if _sock_slide_timer <= 0.0:
			_apply_sock_slide()
	if _boomerang_time > 0.0:
		_boomerang_time = maxf(_boomerang_time - delta, 0.0)
		var falloff := _boomerang_time / Config.BOOMERANG_DURATION_S
		apply_central_force(_boomerang_direction * Config.BOOMERANG_ACCEL * mass * falloff)
	if is_held and data != null and data.special == ItemData.Special.GRAVITY_FIELD:
		_attract_socks()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if is_held and _holder != null:
		var desired := (_hold_target() - global_position) * Config.HOLD_SPRING
		if _holder is CharacterBody2D:
			desired += (_holder as CharacterBody2D).velocity
		state.linear_velocity = desired.limit_length(Config.HOLD_MAX_SPEED)
		return
	# Throws queue an impulse; clamp after the solver has applied it (no tunnelling at speed).
	if state.linear_velocity.length() > Config.MAX_ITEM_SPEED:
		state.linear_velocity = state.linear_velocity.normalized() * Config.MAX_ITEM_SPEED


func _hold_target() -> Vector2:
	if _holder == null:
		return global_position
	if _holder.has_method("get_hold_position"):
		var value: Variant = _holder.call("get_hold_position")
		if value is Vector2:
			return value
	return _holder.global_position


func _apply_sock_slide() -> void:
	if data == null:
		return
	var direction := Vector2.from_angle(_rng.randf_range(0.0, TAU))
	var speed := SOCK_SLIDE_SPEED * data.belt_speed_scale
	apply_central_impulse(direction * speed * mass)


func _attract_socks() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group(Config.GROUP_ITEMS):
		var sock := node as LaundryItem
		if sock == null or sock == self or sock.is_held:
			continue
		if sock.data == null or sock.data.id != &"sock":
			continue
		var offset := global_position - sock.global_position
		var distance := offset.length()
		if distance <= MIN_INPUT_LENGTH or distance > Config.CORE_GRAVITY_RADIUS:
			continue
		var falloff := 1.0 - distance / Config.CORE_GRAVITY_RADIUS
		sock.apply_central_force(
			offset.normalized() * Config.CORE_GRAVITY_ACCEL * sock.mass * falloff
		)


func _play_squelch() -> void:
	squelched.emit()
	if squelch_player != null and squelch_player.stream != null:
		squelch_player.play()


func _lookup(id: StringName) -> ItemData:
	var db := ItemDatabase.load_default()
	if db == null:
		return null
	return db.get_item(id)


func _apply_data() -> void:
	if data == null:
		return
	mass = data.mass_kg
	linear_damp = data.linear_damp
	var material := PhysicsMaterial.new()
	material.bounce = data.bounce
	material.friction = data.friction
	physics_material_override = material
	if collision_shape == null:
		return
	var source := collision_shape.shape as CircleShape2D
	if source == null:
		return
	var own := source
	if not _shape_owned:
		own = source.duplicate() as CircleShape2D
		_shape_owned = true
	own.radius = data.radius
	collision_shape.shape = own


func _sync_visual() -> void:
	if visual != null and data != null:
		visual.configure(data, color, pattern, is_clean)

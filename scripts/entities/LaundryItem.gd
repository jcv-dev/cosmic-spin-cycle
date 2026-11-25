class_name LaundryItem
extends RigidBody2D
## A laundry item driven entirely by `data/items.tres` (GDD §6).
##
## Ownership: the grabber decides *who* is held, the player decides *when* it is thrown,
## and this body owns *how* it moves. All game-feel numbers come from Config or ItemData;
## the greybox-only tunables (sock slide delay/speed, throw follow-through, fake height,
## landing feedback) are named constants below until the lead promotes them to Config.

signal fell_off_belt
signal delivered
signal squelched
signal landed

## GDD §6: a sock dropped un-thrown slides randomly after a short grace period.
const SOCK_SLIDE_DELAY_S := 0.4
const SOCK_SLIDE_SPEED := 120.0
const MIN_INPUT_LENGTH := 0.0001
## Homing window and strength after a throw (deliberately short: it forgives, not aims).
const HOME_IN_TIME_S := 0.55
const HOME_IN_RANGE_PX := 460.0
const HOME_IN_ACCEL := 1900.0
## Items that stop moving outside a washer (for example at the end of a reversed belt) are
## nudged back toward the room centre, so nothing can sit in a corner forever.
const STUCK_SPEED := 10.0
const STUCK_LIMIT_S := 3.0
const STUCK_NUDGE := 320.0

# --- Feel tunables (owned here until promoted) -----------------------------------------
## Fraction of the player's velocity carried into the throw, and its cap in px/s.
const FOLLOW_THROUGH_SCALE := 0.35
const FOLLOW_THROUGH_MAX := 120.0
## The carried component bleeds off over this window so the aim line wins long-term.
const FOLLOW_THROUGH_DECAY_S := 0.05
## Fake 2.5D height: 0 on the ground, `sin` arc peaking at 24 px.
const AIR_ARC_PX := 24.0
const AIR_TIME_S := 0.34
## The sock gets a tiny arc on every throw; the moon keeps its GDD boomerang.
const SOCK_ARC_ACCEL := 120.0
const SOCK_ARC_DURATION_S := 0.22
const HEAVY_IDS: Array[StringName] = [&"gas_giant", &"galaxy_core"]
const THROW_PITCH_HEAVY := 0.85
const THROW_PITCH_SOCK := 1.1
const THROW_STREAM := "res://assets/audio/sfx/throw_whoosh.ogg"
const GUIDE_RANGE_PX := 700.0
const GUIDE_DURATION_S := 0.18
const HEAVY_SHAKE := 0.58
const HEAVY_SHAKE_S := 0.09

@export var item_id: StringName = &"rocky"
@export var color: StringName = &"red"
@export var pattern: StringName = &"solid"

var data: ItemData = null
## Real catalogue name displayed under the item (washers take worlds, not clothes).
var celestial_name := ""
var is_held := false
var is_clean := false
var throw_count := 0
## Fake 2.5D height above the floor in world px; read by `ItemVisual` for the shadow.
var height := 0.0

var _holder: Node2D = null
var _throw_armed := false
var _shape_owned := false
var _sock_slide_timer := 0.0
var _boomerang_time := 0.0
var _boomerang_direction := Vector2.ZERO
var _boomerang_accel := Config.BOOMERANG_ACCEL
var _boomerang_duration := Config.BOOMERANG_DURATION_S
var _carry_velocity := Vector2.ZERO
var _carry_time := 0.0
var _air_time := 0.0
var _air_active := false
## Short homing window after a throw: the player aims the machine, the game covers the last
## few pixels (the owner's "aiming exactly at the door is near impossible").
var _home_time := 0.0
var _throw_direction := Vector2.ZERO
var _stuck_time := 0.0
var _throw_grade := -1
var _rng := RandomNumberGenerator.new()
var _throw_player: AudioStreamPlayer2D = null

@onready var visual: ItemVisual = get_node_or_null("Visual") as ItemVisual
@onready
var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready
var squelch_player: AudioStreamPlayer2D = get_node_or_null("SquelchPlayer") as AudioStreamPlayer2D


func _ready() -> void:
	add_to_group(Config.GROUP_ITEMS)
	if squelch_player != null and AudioServer.get_bus_index("SFX") >= 0:
		squelch_player.bus = "SFX"
	_rng.randomize()
	if visual != null:
		visual.top_level = true
		visual.z_index = 1
	if data == null:
		data = _lookup(item_id)
	_apply_data()
	_ensure_squelch_stream()
	_ensure_feel_players()
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
		_ensure_squelch_stream()
		_sync_visual()


func begin_hold(holder: Node) -> void:
	if is_held:
		return
	is_held = true
	# An item ejected from a jammed machine may still carry a deferred freeze; a held item
	# must always be steerable (owner: "it shows as picked but it does not move").
	set_deferred(&"freeze", false)
	sleeping = false
	_holder = holder as Node2D
	_throw_armed = false
	_sock_slide_timer = 0.0
	_boomerang_time = 0.0
	_air_active = false
	_air_time = 0.0
	height = 0.0
	_carry_time = 0.0
	_carry_velocity = Vector2.ZERO
	collision_mask = Config.CollisionLayer.WORLD
	# A carried item is not a physical obstacle for other laundry: the core's gravity
	# field must pull socks in, not shove them away. It still collides with walls via mask.
	collision_layer = 0
	sleeping = false
	gravity_scale = 0.0
	if data != null and data.special == ItemData.Special.SQUELCH:
		_play_squelch()


func end_hold() -> void:
	if not is_held:
		return
	is_held = false
	_holder = null
	collision_layer = Config.CollisionLayer.ITEMS
	collision_mask = Config.CollisionLayer.WORLD | Config.CollisionLayer.ITEMS
	_throw_armed = true
	if data != null and data.special == ItemData.Special.SQUELCH:
		_sock_slide_timer = SOCK_SLIDE_DELAY_S


## Applies exactly one throw impulse. Returns false when there is nothing to throw, which
## is what makes a second call in the same action a no-op (no double impulses).
##
## `carrier_velocity` is the thrower's velocity: a capped fraction joins the launch for a
## short follow-through and then bleeds off, so aim stays readable. The hold-spring speed
## is cancelled first, which is what makes every throw leave at the same base speed.
func throw_with_impulse(
	direction: Vector2, grade: int, carrier_velocity: Vector2 = Vector2.ZERO
) -> bool:
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
	linear_velocity = Vector2.ZERO
	var carry := carrier_velocity * FOLLOW_THROUGH_SCALE
	carry = carry.limit_length(FOLLOW_THROUGH_MAX)
	apply_central_impulse((dir * Config.THROW_SPEED * multiplier + carry) * mass)
	_carry_velocity = carry
	_carry_time = FOLLOW_THROUGH_DECAY_S
	_boomerang_accel = Config.BOOMERANG_ACCEL
	if (
		data != null
		and data.special == ItemData.Special.BOOMERANG
		and grade == RhythmEvaluator.Grade.MISS
	):
		_boomerang_direction = Vector2(-dir.y, dir.x)
		_boomerang_time = Config.BOOMERANG_DURATION_S
		_boomerang_duration = Config.BOOMERANG_DURATION_S
	elif data != null and data.special == ItemData.Special.SQUELCH:
		_boomerang_direction = Vector2(-dir.y, dir.x)
		_boomerang_time = SOCK_ARC_DURATION_S
		_boomerang_duration = SOCK_ARC_DURATION_S
		_boomerang_accel = SOCK_ARC_ACCEL
	_start_air(grade)
	_throw_direction = dir
	_home_time = HOME_IN_TIME_S
	_play_throw_feedback(dir, grade)
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


func is_airborne() -> bool:
	return _air_active


func _process(_delta: float) -> void:
	if visual != null:
		visual.global_position = global_position
		visual.rotation = 0.0
		visual.set_height(height)


func _physics_process(delta: float) -> void:
	if is_held:
		sleeping = false
	if _sock_slide_timer > 0.0 and not is_held:
		_sock_slide_timer = maxf(_sock_slide_timer - delta, 0.0)
		if _sock_slide_timer <= 0.0:
			_apply_sock_slide()
	if _boomerang_time > 0.0:
		_boomerang_time = maxf(_boomerang_time - delta, 0.0)
		var falloff := _boomerang_time / maxf(_boomerang_duration, 0.001)
		apply_central_force(_boomerang_direction * _boomerang_accel * mass * falloff)
	if _air_active:
		_tick_air(delta)
	if is_held and data != null and data.special == ItemData.Special.GRAVITY_FIELD:
		_attract_socks()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if is_held and _holder != null:
		var desired := (_hold_target() - global_position) * Config.HOLD_SPRING
		if _holder is CharacterBody2D:
			desired += (_holder as CharacterBody2D).velocity
		state.linear_velocity = desired.limit_length(Config.HOLD_MAX_SPEED)
		return
	if _carry_time > 0.0:
		var step := maxf(state.step, 0.0)
		var decay := minf(step / FOLLOW_THROUGH_DECAY_S, 1.0)
		state.linear_velocity -= _carry_velocity * decay
		_carry_velocity *= 1.0 - decay
		_carry_time = maxf(_carry_time - step, 0.0)
	_apply_home_in(state)
	_rescue_if_stuck(state)
	# Throws queue an impulse; clamp after the solver has applied it (no tunnelling at speed).
	if state.linear_velocity.length() > Config.MAX_ITEM_SPEED:
		state.linear_velocity = state.linear_velocity.normalized() * Config.MAX_ITEM_SPEED


## Gentle homing toward the nearest valid destination for a short window after release.
## Never snaps: it adds lateral acceleration so the arc still reads as a throw.
func _apply_home_in(state: PhysicsDirectBodyState2D) -> void:
	if _home_time <= 0.0:
		return
	var step := maxf(state.step, 0.0)
	_home_time = maxf(_home_time - step, 0.0)
	var target := _home_target()
	if target == Vector2.INF:
		return
	var offset := target - global_position
	var distance := offset.length()
	if distance <= 12.0 or distance > HOME_IN_RANGE_PX:
		return
	var speed := state.linear_velocity.length()
	if speed < 40.0:
		return
	var to_target := offset.normalized()
	if state.linear_velocity.normalized().dot(to_target) < 0.15:
		return
	var closeness := 1.0 - distance / HOME_IN_RANGE_PX
	state.linear_velocity += to_target * HOME_IN_ACCEL * (0.35 + 0.65 * closeness) * step


## Corner rescue: a free item that has not moved for a few seconds gets a gentle push toward
## the middle of the room (never teleported, never silently deleted).
func _rescue_if_stuck(state: PhysicsDirectBodyState2D) -> void:
	if is_held or is_queued_for_deletion():
		_stuck_time = 0.0
		return
	var step := maxf(state.step, 0.0)
	if state.linear_velocity.length() > STUCK_SPEED:
		_stuck_time = 0.0
		return
	_stuck_time += step
	if _stuck_time < STUCK_LIMIT_S:
		return
	_stuck_time = 0.0
	var to_centre := Vector2(640.0, 360.0) - global_position
	if to_centre.length() < 40.0:
		return
	state.linear_velocity += to_centre.normalized() * STUCK_NUDGE
	if visual != null:
		FootFX.burst(self, global_position, Color("#9AA4C4"), 3)


func _home_target() -> Vector2:
	if is_clean:
		var tree := get_tree()
		if tree != null:
			var chute := tree.get_first_node_in_group(Config.GROUP_CHUTE) as Node2D
			if chute != null:
				var to_chute := chute.global_position - global_position
				if to_chute.length() > 1.0 and _throw_direction.dot(to_chute.normalized()) > 0.35:
					return chute.global_position
		return Vector2.INF
	var target: Variant = _nearest_compatible_mouth()
	if target is Vector2:
		return target
	return Vector2.INF


func _hold_target() -> Vector2:
	if _holder == null:
		return global_position
	if _holder.has_method("get_hold_position"):
		var value: Variant = _holder.call("get_hold_position")
		if value is Vector2:
			return value
	return _holder.global_position


func _start_air(_grade: int) -> void:
	_air_time = 0.0
	_air_active = true
	height = 0.0


func _tick_air(delta: float) -> void:
	_air_time += delta
	var ratio := clampf(_air_time / AIR_TIME_S, 0.0, 1.0)
	height = AIR_ARC_PX * sin(PI * ratio)
	if ratio >= 1.0:
		_air_active = false
		height = 0.0
		_land()


func _land() -> void:
	var on_beat := (
		BeatConductor.delta_to_nearest_beat(BeatConductor.get_song_time()) <= Config.WINDOW_GOOD_S
	)
	var heavy := data != null and HEAVY_IDS.has(data.id)
	if visual != null:
		visual.play_landing(on_beat, heavy)
	else:
		FootFX.burst(self, global_position, Color("#9AA4C4"), 5)
	landed.emit()


func _play_throw_feedback(direction: Vector2, grade: int) -> void:
	if visual != null:
		visual.play_smear(direction)
		visual.show_throw_guide(_aimed_compatible_mouth(), grade)
	_play_throw_sound()
	if data != null and HEAVY_IDS.has(data.id):
		_juice_shake(HEAVY_SHAKE, HEAVY_SHAKE_S)


## Homing target: the compatible machine the player is actually throwing toward. Choosing the
## nearest one made throws curve into a different washer than the reticle showed.
func _aimed_compatible_mouth() -> Variant:
	var tree := get_tree()
	if tree == null or _throw_direction.length() < 0.01:
		return null
	var best: Node2D = null
	var best_score := -1.0
	for node in tree.get_nodes_in_group(Config.GROUP_WASHERS):
		var washer := node as Node2D
		if washer == null or not is_instance_valid(washer):
			continue
		if not _washer_accepts(washer):
			continue
		var point := _mouth_position(washer)
		var offset := point - global_position
		var distance := offset.length()
		if distance < 1.0 or distance > HOME_IN_RANGE_PX:
			continue
		var alignment := _throw_direction.dot(offset.normalized())
		if alignment < 0.55:
			continue
		var score := alignment - distance / (HOME_IN_RANGE_PX * 4.0)
		if score > best_score:
			best_score = score
			best = washer
	if best == null:
		return null
	return _mouth_position(best)


func _nearest_compatible_mouth() -> Variant:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_distance := GUIDE_RANGE_PX
	for node in tree.get_nodes_in_group(Config.GROUP_WASHERS):
		var washer := node as Node2D
		if washer == null or not is_instance_valid(washer):
			continue
		if not _washer_accepts(washer):
			continue
		var mouth := _mouth_position(washer)
		var distance := global_position.distance_to(mouth)
		if distance < best_distance:
			best_distance = distance
			best = washer
	if best == null:
		return null
	return _mouth_position(best)


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
	return Compatibility.item_fits(item_id, color, pattern, requirement)


func _mouth_position(washer: Node2D) -> Vector2:
	if washer.has_method("get_center_world"):
		var centre: Variant = washer.call("get_center_world")
		if centre is Vector2:
			return centre
	if washer.has_method("get_mouth_position"):
		var value: Variant = washer.call("get_mouth_position")
		if value is Vector2:
			return value
	var property: Variant = washer.get("mouth_position")
	if property is Vector2:
		return property
	return washer.global_position


func _ensure_feel_players() -> void:
	if _throw_player == null:
		_throw_player = AudioStreamPlayer2D.new()
		_throw_player.name = "ThrowPlayer"
		_throw_player.volume_db = -7.0
		if AudioServer.get_bus_index("SFX") >= 0:
			_throw_player.bus = "SFX"
		add_child(_throw_player)
	if _throw_player.stream == null and ResourceLoader.exists(THROW_STREAM):
		_throw_player.stream = load(THROW_STREAM) as AudioStream


func _play_throw_sound() -> void:
	if _throw_player == null or _throw_player.stream == null:
		return
	var pitch := 1.0
	if data != null and HEAVY_IDS.has(data.id):
		pitch = THROW_PITCH_HEAVY
	elif data != null and data.special == ItemData.Special.SQUELCH:
		pitch = THROW_PITCH_SOCK
	_throw_player.pitch_scale = pitch
	_throw_player.play()


func _juice_shake(amount: float, duration: float) -> void:
	var juice := get_node_or_null("/root/Juice")
	if juice != null and juice.has_method("shake"):
		juice.call("shake", amount, duration)


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


## The sock is the only item with a grab sound (GDD §6). A2 ships the SFX; wire it once.
func _ensure_squelch_stream() -> void:
	if data == null or data.special != ItemData.Special.SQUELCH:
		return
	if squelch_player == null or squelch_player.stream != null:
		return
	var path := "res://assets/audio/sfx/squelch_grab.ogg"
	if ResourceLoader.exists(path):
		squelch_player.stream = load(path) as AudioStream


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
	own.radius = data.radius * float(Config.ART_SCALE)
	collision_shape.shape = own


func _sync_visual() -> void:
	if visual != null and data != null:
		visual.configure(data, color, pattern, is_clean)
		if celestial_name == "":
			celestial_name = CelestialNames.next_name(item_id)
		visual.set_caption(celestial_name)

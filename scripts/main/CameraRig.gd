class_name CameraRig
extends Camera2D
## Game-feel camera: smooth follow with aim/velocity lead, a deadzone, trauma shake,
## directional kicks and an optional zoom-out when the play field gets busy.
##
## The lead replaces `MainLevel`'s bare `Camera2D` with this node (`setup(player)` once the
## player exists). It never renders sprites itself: every offset is rounded to a whole pixel
## so pixel art stays crisp, and reduce motion halves the lead and disables shake/kick.
##
## Shake is shared through the `Juice` autoload when present; without it the rig keeps a
## small local trauma so dev scenes and unit tests still shake.

const MAX_LEAD_PX := 54.0
const LEAD_VELOCITY_GAIN := 0.16
const LEAD_AIM_GAIN := 18.0
const DEADZONE_PX := 24.0
const FOLLOW_SHARPNESS := 10.0
const KICK_DECAY := 9.0
const MAX_KICK_PX := 8.0
const ZOOM_MIN := 0.97
const ZOOM_SHARPNESS := 3.5
const FLIGHT_ZOOM_THRESHOLD := 4
const FLIGHT_SCAN_INTERVAL_S := 0.25
const CENTER := Vector2(640.0, 360.0)
const MAX_SHAKE_PX := 6.0
const SHAKE_PHASE_X := 17.31
const SHAKE_PHASE_Y := 41.77
const SHAKE_FREQ_X := 37.7
const SHAKE_FREQ_Y := 29.3

@export var zoom_out_enabled := true
@export var zoom_out_amount := 0.03

var target: Node2D = null
var reduce_motion := false
## Number of free-flying items, refreshed by `refresh_flight_count()`; the zoom-out uses it.
var flight_count := 0

var _smooth_position := CENTER
var _kick_offset := Vector2.ZERO
var _scan_timer := 0.0
var _fallback_trauma := 0.0
var _fallback_decay := 1.0
var _shake_time := 0.0
var _juice: Node = null
var _settings: Node = null


func _ready() -> void:
	enabled = true
	add_to_group(&"camera_rig")
	_juice = get_node_or_null("/root/Juice")
	_settings = get_node_or_null("/root/Settings")
	if _settings != null and _settings.has_signal("settings_changed"):
		_settings.connect("settings_changed", _on_settings_changed)
	reduce_motion = _settings_reduce_motion()
	if global_position == Vector2.ZERO:
		global_position = CENTER
	_smooth_position = global_position
	refresh_flight_count()


## Binds the followed node and snaps the rig to it so the first frame does not pan.
func setup(follow_target: Node) -> void:
	target = follow_target as Node2D
	if target != null:
		_smooth_position = target.global_position
		global_position = _pixel(_smooth_position)
	refresh_flight_count()


## Adds trauma through `Juice` when it exists, otherwise locally. Never stacks past 1.
func shake(amount: float, duration: float = 0.25) -> void:
	if reduce_motion or amount <= 0.0:
		return
	if _juice != null and _juice.has_method("shake"):
		_juice.call("shake", amount, duration)
		return
	_fallback_trauma = clampf(_fallback_trauma + clampf(amount, 0.0, 1.0), 0.0, 1.0)
	var span := clampf(duration, 0.04, 2.0)
	_fallback_decay = maxf(_fallback_decay, 1.0 / span)


## Directional impulse (throws, explosions). Decays exponentially; capped at `MAX_KICK_PX`.
func kick(direction: Vector2, amount: float) -> void:
	if reduce_motion or amount <= 0.0 or direction.length() < 0.0001:
		return
	_kick_offset = (_kick_offset + direction.normalized() * amount).limit_length(MAX_KICK_PX)


func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	if value:
		_kick_offset = Vector2.ZERO
		_fallback_trauma = 0.0


## Whole-pixel shake offset, shared from `Juice` or computed locally.
func get_shake_offset() -> Vector2:
	if reduce_motion:
		return Vector2.ZERO
	if _juice != null and _juice.has_method("get_shake_offset"):
		var shared: Variant = _juice.call("get_shake_offset")
		if shared is Vector2:
			return shared
	if _fallback_trauma <= 0.0:
		return Vector2.ZERO
	var amplitude := _fallback_trauma * _fallback_trauma * MAX_SHAKE_PX
	var x := sin(_shake_time * SHAKE_FREQ_X + SHAKE_PHASE_X) * amplitude
	var y := cos(_shake_time * SHAKE_FREQ_Y + SHAKE_PHASE_Y) * amplitude
	var offset := Vector2(roundf(x), roundf(y))
	if offset.length() > MAX_SHAKE_PX:
		offset = offset.normalized() * MAX_SHAKE_PX
		offset = offset.sign() * offset.abs().floor()
	return offset


## Lead vector actually applied this frame, clamped to `MAX_LEAD_PX` (halved when reduced).
func get_lead_offset() -> Vector2:
	return _compute_lead()


func refresh_flight_count() -> int:
	var count := 0
	var tree := get_tree()
	if tree != null:
		for node in tree.get_nodes_in_group(Config.GROUP_ITEMS):
			var item := node as Node2D
			if item == null or not is_instance_valid(item):
				continue
			var held: Variant = item.get("is_held")
			if held is bool and held:
				continue
			var velocity: Variant = item.get("linear_velocity")
			if velocity is Vector2 and (velocity as Vector2).length() > 120.0:
				count += 1
	flight_count = count
	return count


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_acquire_target()
	if target != null and is_instance_valid(target):
		_update_follow(delta)
	_update_kick(delta)
	_update_fallback_trauma(delta)
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = FLIGHT_SCAN_INTERVAL_S
		refresh_flight_count()
	_update_zoom(delta)
	global_position = _pixel(_smooth_position + get_shake_offset() + _kick_offset)


## Order-independent binding: `MainLevel` builds the camera before the player, so the rig
## adopts the first node in the `player` group as soon as one exists.
func _acquire_target() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var node := tree.get_first_node_in_group(Config.GROUP_PLAYER)
	if node != null:
		setup(node)


func _update_follow(delta: float) -> void:
	var desired := target.global_position + _compute_lead()
	var offset := desired - _smooth_position
	if offset.length() <= DEADZONE_PX:
		return
	var goal := desired - offset.normalized() * DEADZONE_PX
	var weight := 1.0 - exp(-FOLLOW_SHARPNESS * delta)
	_smooth_position = _smooth_position.lerp(goal, weight)


func _compute_lead() -> Vector2:
	if target == null:
		return Vector2.ZERO
	var velocity := Vector2.ZERO
	var aim := Vector2.ZERO
	var velocity_value: Variant = target.get("velocity")
	if velocity_value is Vector2:
		velocity = velocity_value
	var aim_value: Variant = target.get("aim_direction")
	if aim_value is Vector2:
		aim = aim_value
	var lead := velocity * LEAD_VELOCITY_GAIN + aim * LEAD_AIM_GAIN
	if reduce_motion:
		lead *= 0.5
	return lead.limit_length(MAX_LEAD_PX)


func _update_kick(delta: float) -> void:
	if _kick_offset == Vector2.ZERO:
		return
	_kick_offset *= exp(-KICK_DECAY * delta)
	if _kick_offset.length() < 0.05:
		_kick_offset = Vector2.ZERO


func _update_fallback_trauma(delta: float) -> void:
	if _fallback_trauma <= 0.0:
		return
	_shake_time += delta
	_fallback_trauma = maxf(_fallback_trauma - _fallback_decay * delta, 0.0)
	if _fallback_trauma <= 0.0:
		_fallback_decay = 1.0


func _update_zoom(delta: float) -> void:
	var goal := 1.0
	if zoom_out_enabled and flight_count >= FLIGHT_ZOOM_THRESHOLD:
		goal = maxf(1.0 - zoom_out_amount, ZOOM_MIN)
	var punch := 0.0
	if _juice != null and _juice.has_method("get_zoom_punch"):
		var value: Variant = _juice.call("get_zoom_punch")
		if value is float:
			punch = value
	var weight := 1.0 - exp(-ZOOM_SHARPNESS * delta)
	var base := lerpf(zoom.x, goal, weight)
	var next := base + punch
	zoom = Vector2(next, next)


func _settings_reduce_motion() -> bool:
	if _settings == null:
		return false
	var value: Variant = _settings.get("reduce_motion")
	return value is bool and value


func _on_settings_changed() -> void:
	set_reduce_motion(_settings_reduce_motion())


func _pixel(value: Vector2) -> Vector2:
	return Vector2(roundf(value.x), roundf(value.y))

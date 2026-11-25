extends Node
## Shared impact layer: screen shake, hitstop, flash, zoom punch and rumble.
##
## Autoload as `Juice="*res://scripts/autoload/Juice.gd"` (after `Settings`). Every caller
## tests for the singleton with `get_node_or_null("/root/Juice")`, so gameplay scenes keep
## working when the autoload is absent (tests, dev sandboxes, a stripped export).
##
## Hitstop scales `Engine.time_scale`. It is released from `_process` against
## `Time.get_ticks_msec()` (unscaled wall clock), so the slowed engine cannot extend its own
## hitstop, and `BeatConductor` keeps steering the beat grid from audio position.
## Shake is trauma-based: `amplitude = trauma² * MAX_SHAKE_PX`, offsets rounded to whole
## pixels because a 0.5 px camera offset shimmers pixel art. Reduce motion disables shake,
## hitstop, flash and zoom punch at the source.

signal hit_stopped(duration: float)

const MAX_TRAUMA := 1.0
const MAX_SHAKE_PX := 6.0
const MIN_SHAKE_DURATION_S := 0.04
const MAX_SHAKE_DURATION_S := 2.0
const MAX_HITSTOP_S := 0.09
const MIN_HITSTOP_SCALE := 0.01
const MAX_PUNCH_ZOOM := 0.05
const FLASH_LAYER := 128
## Deterministic, non-repeating-looking phase offsets for the two shake axes.
const SHAKE_PHASE_X := 17.31
const SHAKE_PHASE_Y := 41.77
const SHAKE_FREQ_X := 37.7
const SHAKE_FREQ_Y := 29.3

var reduce_motion := false
var trauma := 0.0
var zoom_punch := 0.0
var last_hitstop_duration := 0.0
var hitstop_count := 0
var last_rumble := Vector3.ZERO

var _trauma_decay := 1.0
var _shake_time := 0.0
var _zoom_amount := 0.0
var _zoom_duration := 0.1
var _zoom_left := 0.0
var _hitstop_active := false
var _hitstop_until_ms := 0
var _flash_stamp := -1
var _flash_layer: CanvasLayer = null
var _flash_rect: ColorRect = null
var _settings: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_build_flash()
	_settings = get_node_or_null("/root/Settings")
	if _settings != null and _settings.has_signal("settings_changed"):
		_settings.connect("settings_changed", _on_settings_changed)
	reduce_motion = _settings_reduce_motion()


## Adds trauma. `amount` is the 0..1 trauma headroom; `duration` is how long a full
## 1.0 trauma would take to decay. Trauma never exceeds 1.
func shake(amount: float, duration: float = 0.25) -> void:
	if reduce_motion or amount <= 0.0:
		return
	var added := clampf(amount, 0.0, MAX_TRAUMA)
	trauma = clampf(trauma + added, 0.0, MAX_TRAUMA)
	var span := clampf(duration, MIN_SHAKE_DURATION_S, MAX_SHAKE_DURATION_S)
	_trauma_decay = maxf(_trauma_decay, MAX_TRAUMA / span)


## Freezes the world for `duration` seconds at `time_scale`. Never stacks: a second call
## while active is ignored, so two simultaneous explosions cannot create a 180 ms freeze.
func hitstop(duration: float, time_scale: float = 0.05) -> void:
	if reduce_motion or _hitstop_active or duration <= 0.0:
		return
	var clamped := clampf(duration, 0.0, MAX_HITSTOP_S)
	_hitstop_active = true
	last_hitstop_duration = clamped
	hitstop_count += 1
	_hitstop_until_ms = Time.get_ticks_msec() + int(ceil(clamped * 1000.0))
	Engine.time_scale = clampf(time_scale, MIN_HITSTOP_SCALE, 1.0)
	hit_stopped.emit(clamped)


## Full-screen 1-frame flash. The play field is never covered for longer than one frame;
## `duration` is kept for callers that want to fade an accompanying effect.
func flash(color: Color, duration: float = 0.08) -> void:
	if reduce_motion or _flash_rect == null or duration <= 0.0:
		return
	_flash_rect.color = Color(color.r, color.g, color.b, 1.0)
	_flash_stamp = Engine.get_process_frames()
	_flash_layer.visible = true


## Camera zoom punch, read by `CameraRig` through `get_zoom_punch()`. Positive amount
## pushes the zoom in by that fraction.
func punch_zoom(amount: float = 0.02, duration: float = 0.12) -> void:
	if reduce_motion:
		return
	_zoom_amount = clampf(amount, 0.0, MAX_PUNCH_ZOOM)
	_zoom_duration = maxf(duration, 0.01)
	_zoom_left = _zoom_duration
	zoom_punch = _zoom_amount


## Pad rumble, silently ignored when no pad is connected or reduce motion is on.
func rumble(weak: float, strong: float, duration_ms: int) -> void:
	last_rumble = Vector3(clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), float(duration_ms))
	if reduce_motion or duration_ms <= 0:
		return
	if Input.get_connected_joypads().is_empty():
		return
	Input.start_joy_vibration(0, last_rumble.x, last_rumble.y, float(duration_ms) / 1000.0)


func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	if value:
		release_motion()


## Cancels every motion effect currently in flight and restores `Engine.time_scale`.
## Used by reduce motion, scene teardown and tests.
func release_motion() -> void:
	trauma = 0.0
	_trauma_decay = 1.0
	zoom_punch = 0.0
	_zoom_amount = 0.0
	_zoom_left = 0.0
	_flash_stamp = -1
	_hide_flash()
	_end_hitstop()


func get_shake_offset() -> Vector2:
	if reduce_motion or trauma <= 0.0:
		return Vector2.ZERO
	var amplitude := trauma * trauma * MAX_SHAKE_PX
	if amplitude < 0.01:
		return Vector2.ZERO
	var x := sin(_shake_time * SHAKE_FREQ_X + SHAKE_PHASE_X) * amplitude
	var y := cos(_shake_time * SHAKE_FREQ_Y + SHAKE_PHASE_Y) * amplitude
	var offset := Vector2(roundf(x), roundf(y))
	# Per-axis rounding can push the diagonal past the cap; step down without leaving the grid.
	if offset.length() > MAX_SHAKE_PX:
		offset = offset.normalized() * MAX_SHAKE_PX
		offset = offset.sign() * offset.abs().floor()
	return offset


func get_zoom_punch() -> float:
	return 0.0 if reduce_motion else zoom_punch


func is_hitstopping() -> bool:
	return _hitstop_active


func is_flash_visible() -> bool:
	return _flash_layer != null and _flash_layer.visible


func _process(delta: float) -> void:
	_tick_flash()
	_tick_hitstop()
	_tick_trauma(delta)
	_tick_zoom(delta)


func _tick_flash() -> void:
	# The overlay is armed for the frame it was requested on and retired before the next
	# draw, so it can never cover the play field for two frames.
	if _flash_layer == null or not _flash_layer.visible:
		return
	# Hide on the next process pass: the overlay is drawn for exactly the frame it was
	# requested on. `>=` because the frame counter may not advance during the same tick.
	if Engine.get_process_frames() >= _flash_stamp:
		_hide_flash()


func _tick_hitstop() -> void:
	if _hitstop_active and Time.get_ticks_msec() >= _hitstop_until_ms:
		_end_hitstop()


func _tick_trauma(delta: float) -> void:
	if trauma <= 0.0:
		_trauma_decay = 1.0
		return
	_shake_time += delta
	trauma = maxf(trauma - _trauma_decay * delta, 0.0)


func _tick_zoom(delta: float) -> void:
	if _zoom_left <= 0.0:
		zoom_punch = 0.0
		return
	_zoom_left = maxf(_zoom_left - delta, 0.0)
	zoom_punch = _zoom_amount * (_zoom_left / _zoom_duration)


func _end_hitstop() -> void:
	if not _hitstop_active:
		return
	_hitstop_active = false
	Engine.time_scale = 1.0


func _build_flash() -> void:
	_flash_layer = CanvasLayer.new()
	_flash_layer.name = "JuiceFlash"
	_flash_layer.layer = FLASH_LAYER
	_flash_layer.visible = false
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.name = "Flash"
	_flash_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_layer.add_child(_flash_rect)


func _hide_flash() -> void:
	if _flash_layer != null and is_instance_valid(_flash_layer):
		_flash_layer.visible = false


func _settings_reduce_motion() -> bool:
	if _settings == null:
		return false
	var value: Variant = _settings.get("reduce_motion")
	return value is bool and value


func _on_settings_changed() -> void:
	set_reduce_motion(_settings_reduce_motion())


func _exit_tree() -> void:
	_end_hitstop()

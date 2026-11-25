extends Node
## Central impact layer: screen shake, hitstop, flash, zoom punch and gamepad rumble.
##
## Owned by the game-feel workstream; this file starts as the contracted API so the rest of
## the game can call it before the feel pass lands. `reduce_motion` disables every effect
## that can nauseate or obscure the play field (docs/UX_BIBLE.md §11).

signal hit_stopped(duration: float)

const MAX_SHAKE_PX := 6.0
const MAX_HITSTOP_S := 0.09
const FLASH_MAX_S := 0.08

var reduce_motion := false
var trauma := 0.0
var _shake_decay := 2.4
var _hitstop_left := 0.0
var _hitstop_until_ms := 0
var _flash_left := 0.0
var _flash_color := Color(1, 1, 1, 0)
var _zoom_punch := 0.0
var _zoom_left := 0.0
var _zoom_total := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Settings.has_signal("settings_changed"):
		Settings.settings_changed.connect(_on_settings_changed)
	_on_settings_changed()


func _process(delta: float) -> void:
	var real_delta := delta
	trauma = maxf(trauma - _shake_decay * real_delta, 0.0)
	if _hitstop_left > 0.0:
		# `delta` is scaled by Engine.time_scale, so use wall-clock time to end the freeze.
		if Time.get_ticks_msec() >= _hitstop_until_ms:
			_hitstop_left = 0.0
			Engine.time_scale = 1.0
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - real_delta, 0.0)
	if _zoom_left > 0.0:
		_zoom_left = maxf(_zoom_left - real_delta, 0.0)
		_zoom_punch = 0.0 if _zoom_left <= 0.0 else _zoom_punch


## Adds trauma (0..1). Amplitude is trauma², capped, so small hits stay small.
func shake(amount: float, _duration: float = 0.25) -> void:
	if reduce_motion:
		return
	trauma = clampf(trauma + absf(amount), 0.0, 1.0)


func shake_offset() -> Vector2:
	if reduce_motion or trauma <= 0.0:
		return Vector2.ZERO
	var amplitude := MAX_SHAKE_PX * trauma * trauma
	return Vector2(
		roundf(randf_range(-amplitude, amplitude)), roundf(randf_range(-amplitude, amplitude))
	)


## Freezes the game briefly. Never stacks, never exceeds MAX_HITSTOP_S.
func hitstop(duration: float, time_scale: float = 0.05) -> void:
	if reduce_motion or duration <= 0.0:
		return
	var clamped := minf(duration, MAX_HITSTOP_S)
	if _hitstop_left >= clamped:
		return
	_hitstop_left = clamped
	_hitstop_until_ms = Time.get_ticks_msec() + int(clamped * 1000.0)
	Engine.time_scale = clampf(time_scale, 0.0, 1.0)
	hit_stopped.emit(clamped)


func flash(color: Color, duration: float = 0.05) -> void:
	if reduce_motion:
		return
	_flash_color = color
	_flash_left = minf(duration, FLASH_MAX_S)


func flash_alpha() -> float:
	return clampf(_flash_left / FLASH_MAX_S, 0.0, 1.0)


func flash_color() -> Color:
	return _flash_color


func punch_zoom(amount: float = 0.02, duration: float = 0.12) -> void:
	if reduce_motion:
		return
	_zoom_punch = clampf(amount, 0.0, 0.04)
	_zoom_total = maxf(duration, 0.001)
	_zoom_left = _zoom_total


func zoom_punch() -> float:
	if _zoom_left <= 0.0 or _zoom_total <= 0.0:
		return 0.0
	return _zoom_punch * (_zoom_left / _zoom_total)


func rumble(weak: float, strong: float, duration_ms: int) -> void:
	if reduce_motion or not Settings.haptics:
		return
	Input.start_joy_vibration(0, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration_ms)


func _on_settings_changed() -> void:
	reduce_motion = Settings.reduce_motion
	if reduce_motion:
		trauma = 0.0
		_hitstop_left = 0.0
		Engine.time_scale = 1.0

class_name Diorama
extends Node2D
## Living title-screen diorama: the real room, zoomed and breathing behind the menu.
##
## `docs/UX_BIBLE.md` §3.7 asks for *the world*, not a jpeg, so this scene reuses the same
## builders as the shift (`RoomBuilder`, `RoomDressing.build_machines_for_display`,
## `LightingRig`, `Atmosphere`) and only adds the menu-specific life: four machines in
## different states, two scrolling belts, laundry sliding by, a rotating chute beacon, Pip
## asleep on a basket and a slow camera drift.
##
## The app-flow session instances this scene and calls:
##   * [method play_intro] when returning from a shift (1.2 s camera settle),
##   * [method set_paused] to freeze every tween and animation when the diorama is hidden.
##
## The scene is self-contained: it never touches BeatConductor, so it cannot disturb the
## shift clock. Its ambient pulse is the 90 BPM menu loop from the UX bible.

## Menu ambient tempo (UX_BIBLE §3.7).
const AMBIENT_BPM := 90.0
## Camera zoom. 1.25 keeps every art pixel exactly five screen pixels wide; the spec's 1.15
## would make pixels uneven (1 art px = 4.6 screen px) and shimmer on llvmpipe.
const CAMERA_ZOOM := 1.25
## Half-width of the slow pan in world pixels (UX_BIBLE §3.7: ±18 px).
const PAN_X := 18.0
const PAN_Y := 6.0
## Pan period in seconds.
const PAN_PERIOD_S := 24.0
## Intro settle duration in seconds.
const INTRO_S := 1.2
## Camera home position: the room centre.
const CAMERA_HOME := Vector2(640.0, 344.0)
## Seconds between the washing machine's turbulent spins.
const TURBULENT_EVERY_S := 12.0
## Pip's breathing period in seconds (1 art px of travel).
const BREATH_PERIOD_S := 2.6

var camera: Camera2D
var nodes: Dictionary = {}
var machines: Dictionary = {}
var rig: LightingRig
var atmosphere: Atmosphere

var _paused := false
var _elapsed := 0.0
var _clock := 0.0
var _beat_index := 0
var _intro_tween: Tween
var _breath_phase := 0.0
var _turbulent_timer := 0.0
var _turbulent_on := false
var _tweens: Array[Tween] = []
var _items: Array[AnimatedSprite2D] = []
var _intro_offset := Vector2.ZERO
var _window_applied := false
var _pip: AnimatedSprite2D
var _beacon: BeaconRing
var _z_glyph: SleepGlyph
var _belts: Array[ConveyorBelt] = []


func _ready() -> void:
	_build_camera()
	nodes = RoomBuilder.build(self)
	rig = nodes.get("lighting") as LightingRig
	atmosphere = nodes.get("atmosphere") as Atmosphere
	if rig != null:
		rig.pulse_bpm = AMBIENT_BPM
	if atmosphere != null:
		atmosphere.pulse_bpm = AMBIENT_BPM
		var glow := get_node_or_null(^"BeltGlow") as Node2D
		if glow != null and "pulse_bpm" in glow:
			glow.set("pulse_bpm", AMBIENT_BPM)
	machines = RoomDressing.build_machines_for_display(self)
	_build_belts()
	_build_items()
	_build_beacon()
	_build_pip()
	_paint_machines()


func _process(delta: float) -> void:
	if not _window_applied:
		_window_applied = true
		_force_shot_window()
	if _paused:
		return
	_elapsed += delta
	_clock += delta
	_advance_beat()
	_drift_camera()
	_breathe_pip(delta)
	_advance_turbulence(delta)


## The screenshot harness can start with a compositor-scaled window; force the exact canvas
## so the diorama screenshot is pixel-exact. Only in `--out=` runs, never in the game.
func _force_shot_window() -> void:
	if not _is_screenshot_run() or DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if window == null:
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.size = Config.ART_CANVAS * Config.ART_SCALE


# --- public API (CONTRACTS §9) ----------------------------------------------


## Freezes (or resumes) every tween, animation, particle emitter and belt in the diorama.
func set_paused(value: bool) -> void:
	_paused = value
	for tween: Tween in _tweens:
		if tween == null:
			continue
		if value:
			tween.pause()
		else:
			tween.play()
	for belt: ConveyorBelt in _belts:
		belt.set_active(not value)
	for sprite: AnimatedSprite2D in _all_animated_sprites():
		sprite.speed_scale = 0.0 if value else 1.0
	if atmosphere != null:
		atmosphere.visible = not value
	if _beacon != null:
		_beacon.set_process(not value)


## True while the diorama is frozen.
func is_paused() -> bool:
	return _paused


## 1.2 s camera settle, used when the player returns from a shift.
func play_intro() -> void:
	if camera == null:
		return
	if _intro_tween != null:
		_intro_tween.kill()
	_intro_offset = Vector2(0.0, -56.0)
	camera.zoom = Vector2(1.0, 1.0)
	_intro_tween = create_tween()
	_intro_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(camera, "zoom", Vector2(CAMERA_ZOOM, CAMERA_ZOOM), INTRO_S)
	_intro_tween.parallel().tween_property(self, "_intro_offset", Vector2.ZERO, INTRO_S)
	_tweens.append(_intro_tween)


## Camera node (tests assert it exists and is zoomed).
func camera_node() -> Camera2D:
	return camera


# --- build ------------------------------------------------------------------


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "DioramaCamera"
	camera.position = CAMERA_HOME
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(RoomBuilder.room_rect().size.x)
	camera.limit_bottom = int(RoomBuilder.room_rect().size.y)
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()


func _build_belts() -> void:
	var scene := load("res://scenes/environment/ConveyorBelt.tscn") as PackedScene
	if scene == null:
		return
	var layout := RoomBuilder.layout()
	var layer := Node2D.new()
	layer.name = "Belts"
	layer.z_index = -5
	add_child(layer)
	for belt: Dictionary in layout.get("belts", []):
		var belt_id := String(belt.get("id", ""))
		if belt_id == "belt_west":
			continue
		var node := scene.instantiate() as ConveyorBelt
		node.name = belt_id
		layer.add_child(node)
		var flow: Array = belt.get("flow", [1, 0])
		node.configure(
			StringName(belt_id), RoomBuilder.art_rect(belt), Vector2(float(flow[0]), float(flow[1]))
		)
		_belts.append(node)


func _build_items() -> void:
	var layer := Node2D.new()
	layer.name = "DioramaItems"
	layer.z_index = 5
	add_child(layer)
	var entries := [
		{"id": "item_rocky", "variant": &"blue_solid", "y": 86.0, "from": 420.0, "to": 900.0},
		{"id": "item_sock", "variant": &"yellow_ringed", "y": 86.0, "from": 260.0, "to": 640.0},
		{"id": "item_moon", "variant": &"red_solid", "y": 86.0, "from": 960.0, "to": 480.0},
	]
	for entry: Dictionary in entries:
		var sprite := AnimatedSprite2D.new()
		sprite.name = String(entry.get("id", "item"))
		sprite.position = Vector2(float(entry.get("from", 400.0)), float(entry.get("y", 72.0)))
		layer.add_child(sprite)
		if not SpriteSheet.configure(
			sprite, String(entry.get("id", "")), entry.get("variant", &"")
		):
			sprite.queue_free()
			continue
		_items.append(sprite)
		var tween := create_tween().set_loops()
		var duration := absf(float(entry.get("to", 900.0)) - float(entry.get("from", 400.0))) / 34.0
		tween.tween_property(
			sprite, "position:x", float(entry.get("to", 900.0)), maxf(duration, 4.0)
		)
		tween.tween_callback(sprite.hide)
		tween.tween_interval(0.8)
		tween.tween_property(sprite, "position:x", float(entry.get("from", 400.0)), 0.01)
		tween.tween_callback(sprite.show)
		tween.tween_interval(0.6)
		_tweens.append(tween)


func _build_beacon() -> void:
	var chute := RoomBuilder.layout_rect("chute")
	_beacon = BeaconRing.new()
	_beacon.name = "ChuteBeacon"
	_beacon.z_index = 2
	_beacon.position = chute.get_center()
	add_child(_beacon)


func _build_pip() -> void:
	# A single basket next to the chute, painted by the same dressing painter as the rest.
	var basket := RoomDressing.new()
	basket.name = "PipBasket"
	basket.z_index = -1
	basket.setup([{"kind": &"baskets", "rect": Rect2(748.0, 464.0, 96.0, 56.0)}])
	add_child(basket)
	_pip = AnimatedSprite2D.new()
	_pip.name = "Pip"
	_pip.position = Vector2(800.0, 464.0)
	_pip.z_index = 3
	add_child(_pip)
	if SpriteSheet.configure(_pip, "char_pip", &"idle_down"):
		# UX_BIBLE §3.7: asleep at 3 fps, one art pixel of breathing.
		_pip.sprite_frames.set_animation_speed(&"idle_down", 3.0)
		_pip.play(&"idle_down")
	_z_glyph = SleepGlyph.new()
	_z_glyph.name = "SleepGlyph"
	_z_glyph.z_index = 4
	_z_glyph.position = Vector2(824.0, 400.0)
	add_child(_z_glyph)


func _paint_machines() -> void:
	var washers: Dictionary = machines.get("washers", {})
	for key: StringName in washers.keys():
		var sprite := washers[key] as AnimatedSprite2D
		if sprite == null or sprite.sprite_frames == null:
			continue
		var anim: StringName = &"idle"
		match String(key):
			"washer_nw":
				anim = &"washing"
		if sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
	var chute := machines.get("chute") as AnimatedSprite2D
	if chute != null and chute.sprite_frames != null:
		chute.play(&"open")


# --- motion -----------------------------------------------------------------


func _advance_beat() -> void:
	var beat_s := 60.0 / AMBIENT_BPM
	var beat := int(_clock / beat_s)
	if beat == _beat_index:
		return
	_beat_index = beat
	if _beacon != null and not Settings.reduce_motion:
		_beacon.advance()


func _drift_camera() -> void:
	if camera == null:
		return
	var phase := TAU * _elapsed / PAN_PERIOD_S
	var offset := Vector2(roundf(sin(phase) * PAN_X), roundf(sin(phase * 0.7) * PAN_Y))
	camera.position = (CAMERA_HOME + offset + _intro_offset).round()
	if _intro_tween == null or not _intro_tween.is_running():
		camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)


func _breathe_pip(delta: float) -> void:
	if _pip == null:
		return
	_breath_phase = fposmod(_breath_phase + delta, BREATH_PERIOD_S)
	var lift := 0.0
	if _breath_phase > BREATH_PERIOD_S * 0.5:
		lift = float(Config.ART_SCALE)
	_pip.position.y = 464.0 - lift
	if _z_glyph != null:
		_z_glyph.alpha = 0.0 if Settings.reduce_motion else 0.35


func _advance_turbulence(delta: float) -> void:
	if Settings.reduce_motion:
		return
	_turbulent_timer += delta
	if _turbulent_timer < TURBULENT_EVERY_S:
		return
	_turbulent_timer = 0.0
	_turbulent_on = not _turbulent_on
	var washers: Dictionary = machines.get("washers", {})
	var sprite := washers.get(&"washer_se") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return
	var anim: StringName = &"turbulent" if _turbulent_on else &"idle"
	if sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
	if atmosphere != null:
		atmosphere.set_steam_boosted(_turbulent_on)


func _all_animated_sprites() -> Array[AnimatedSprite2D]:
	var out: Array[AnimatedSprite2D] = []
	for child in find_children("*", "AnimatedSprite2D", true, false):
		out.append(child as AnimatedSprite2D)
	return out


func _exit_tree() -> void:
	for tween: Tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()


static func _is_screenshot_run() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return true
	return false


# --- inner visuals -----------------------------------------------------------


## Rotating dashed beacon around the chute: one segment per menu beat, snapped to 45°.
class BeaconRing:
	extends Node2D

	const RADIUS := 96.0
	const SEGMENTS := 8
	const SEGMENT_ARC := 0.20

	var _step := 0

	func advance() -> void:
		_step = (_step + 1) % SEGMENTS
		queue_redraw()

	func _draw() -> void:
		var color := Color(
			Palette.CLEAN_GREEN.r, Palette.CLEAN_GREEN.g, Palette.CLEAN_GREEN.b, 0.55
		)
		for index in range(SEGMENTS):
			var start := TAU * float(index) / float(SEGMENTS)
			var offset := TAU * float(_step) / float(SEGMENTS)
			draw_arc(
				Vector2.ZERO,
				RADIUS,
				start + offset,
				start + offset + SEGMENT_ARC,
				6,
				color,
				4.0,
				false
			)


## A 3×5 pixel "Z" that floats up and fades: Pip is asleep, and the menu keeps it subtle.
class SleepGlyph:
	extends Node2D

	var alpha := 0.35

	func _draw() -> void:
		if alpha <= 0.0:
			return
		var ink := Color(Palette.METAL_3.r, Palette.METAL_3.g, Palette.METAL_3.b, alpha)
		var pixel := float(Config.ART_SCALE)
		var rows := ["111", "001", "010", "100", "111"]
		for row in range(rows.size()):
			var bits: String = rows[row]
			for column in range(bits.length()):
				if bits[column] != "1":
					continue
				draw_rect(
					Rect2(
						Vector2(float(column) * pixel, float(row) * pixel), Vector2(pixel, pixel)
					),
					ink
				)

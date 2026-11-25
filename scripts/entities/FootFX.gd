class_name FootFX
extends Node2D
## Player-local, pooled game-feel effects: step dust, dash afterimages, floor streaks,
## grab tracers and a quiet grab click.
##
## One node lives under `Player`; laundry landings call the static `burst()` so items do not
## need their own emitter scene. Particle budget stays under the UX bible cap of 24: a step
## puff is 6 particles and an item landing is 5, and the emitter restarts instead of
## stacking. Afterimages are sprite copies and never touch the real sprite transform.

const MAX_PARTICLES := 24
const DUST_AMOUNT := 6
const DUST_LIFETIME := 0.36
const DUST_SPEED_MIN := 16.0
const DUST_SPEED_MAX := 44.0
const GHOST_ALPHA := 0.35
const GHOST_LIFETIME := 0.18
const STREAK_LENGTH := 40.0
const STREAK_WIDTH := 4.0
const STREAK_LIFETIME := 0.12
const TRACER_LIFETIME := 0.07
const CLICK_VOLUME_DB := -11.0
const CLICK_STREAM := "res://assets/audio/sfx/ui_click.ogg"
const DUST_COLOR := Color("#6B7599")

static var _shared_texture: Texture2D = null

var _dust: CPUParticles2D = null
var _click: AudioStreamPlayer = null
var _pending: Array[Dictionary] = []
var _ghosts: Array[Dictionary] = []
var _fades: Array[Dictionary] = []


func _ready() -> void:
	_build_dust()
	_build_click()


func _process(delta: float) -> void:
	_tick_ghost_requests(delta)
	_tick_ghosts(delta)
	_tick_fades(delta)


## One dust puff at Pip's feet, angled away from travel.
func step_puff(travel_direction: Vector2) -> void:
	if _dust == null:
		return
	var direction := Vector2.UP
	if travel_direction.length() > 0.001:
		direction = -travel_direction.normalized()
	_dust.position = Vector2(0.0, 10.0)
	_dust.direction = direction
	_dust.restart()
	_dust.emitting = true


## Schedules `count` additive sprite copies `interval` seconds apart.
func dash_trail(source: Node2D, count: int = 3, interval: float = 0.06) -> void:
	if source == null:
		return
	for index in range(count):
		_pending.append({"left": float(index) * interval, "source": source})


func floor_streak(origin: Vector2, direction: Vector2) -> void:
	if direction.length() < 0.001:
		return
	var line := Line2D.new()
	line.width = STREAK_WIDTH
	line.default_color = Color(0.098, 0.890, 0.819, 0.45)
	line.top_level = true
	line.z_index = 1
	add_child(line)
	line.global_position = origin
	line.points = PackedVector2Array([Vector2.ZERO, direction.normalized() * STREAK_LENGTH])
	_fades.append({"node": line, "left": STREAK_LIFETIME, "life": STREAK_LIFETIME, "alpha": 0.45})


## 1 px cyan line from Pip to a freshly grabbed item.
func grab_tracer(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.width = 1.0
	line.default_color = Color(0.098, 0.890, 0.819, 0.8)
	line.top_level = true
	line.z_index = 2
	add_child(line)
	line.global_position = from
	line.points = PackedVector2Array([Vector2.ZERO, to - from])
	_fades.append({"node": line, "left": TRACER_LIFETIME, "life": TRACER_LIFETIME, "alpha": 0.8})


func play_click(pitch: float = 1.0) -> void:
	if _click == null or _click.stream == null:
		return
	_click.pitch_scale = clampf(pitch, 0.5, 2.0)
	_click.play()


## One-shot landing dust owned by the item that landed. Self-frees; no per-frame cost.
static func burst(parent: Node, at: Vector2, color: Color, amount: int = 5) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var emitter := CPUParticles2D.new()
	emitter.one_shot = true
	emitter.amount = clampi(amount, 1, MAX_PARTICLES / 2)
	emitter.lifetime = 0.32
	emitter.explosiveness = 1.0
	emitter.randomness = 0.7
	emitter.direction = Vector2.UP
	emitter.spread = 85.0
	emitter.gravity = Vector2.ZERO
	emitter.initial_velocity_min = 12.0
	emitter.initial_velocity_max = 34.0
	emitter.scale_amount_min = 0.7
	emitter.scale_amount_max = 1.3
	emitter.color = color
	emitter.texture = dust_texture()
	emitter.top_level = true
	emitter.z_index = 1
	parent.add_child(emitter)
	emitter.global_position = at
	emitter.emitting = true
	# A child timer cannot outlive the emitter, so freeing the item never leaves a
	# dangling callable behind (GUT treats engine errors as test failures).
	var life := Timer.new()
	life.one_shot = true
	life.wait_time = 0.8
	emitter.add_child(life)
	life.timeout.connect(emitter.queue_free)
	life.start()


## Shared 4×4 white particle texture; generated once, no shipped raster needed.
static func dust_texture() -> Texture2D:
	if _shared_texture != null:
		return _shared_texture
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_shared_texture = ImageTexture.create_from_image(image)
	return _shared_texture


func _build_dust() -> void:
	_dust = CPUParticles2D.new()
	_dust.name = "StepDust"
	_dust.emitting = false
	_dust.one_shot = true
	_dust.amount = DUST_AMOUNT
	_dust.lifetime = DUST_LIFETIME
	_dust.explosiveness = 1.0
	_dust.randomness = 0.6
	_dust.direction = Vector2.UP
	_dust.spread = 70.0
	_dust.gravity = Vector2.ZERO
	_dust.initial_velocity_min = DUST_SPEED_MIN
	_dust.initial_velocity_max = DUST_SPEED_MAX
	_dust.scale_amount_min = 0.75
	_dust.scale_amount_max = 1.5
	_dust.color = DUST_COLOR
	_dust.texture = dust_texture()
	_dust.local_coords = false
	_dust.z_index = 1
	add_child(_dust)


func _build_click() -> void:
	_click = AudioStreamPlayer.new()
	_click.name = "GrabClick"
	_click.volume_db = CLICK_VOLUME_DB
	if AudioServer.get_bus_index("SFX") >= 0:
		_click.bus = "SFX"
	if ResourceLoader.exists(CLICK_STREAM):
		_click.stream = load(CLICK_STREAM) as AudioStream
	add_child(_click)


func _tick_ghost_requests(delta: float) -> void:
	if _pending.is_empty():
		return
	for index in range(_pending.size() - 1, -1, -1):
		var entry := _pending[index]
		entry["left"] = float(entry["left"]) - delta
		if float(entry["left"]) > 0.0:
			continue
		var source: Variant = entry["source"]
		if source is Node2D and is_instance_valid(source):
			_spawn_ghost(source as Node2D)
		_pending.remove_at(index)


func _tick_ghosts(delta: float) -> void:
	if _ghosts.is_empty():
		return
	for index in range(_ghosts.size() - 1, -1, -1):
		var entry := _ghosts[index]
		var node: Variant = entry["node"]
		if not (node is Node) or not is_instance_valid(node):
			_ghosts.remove_at(index)
			continue
		entry["left"] = float(entry["left"]) - delta
		var remaining := float(entry["left"])
		if remaining <= 0.0:
			(node as Node).queue_free()
			_ghosts.remove_at(index)
			continue
		(node as CanvasItem).modulate.a = GHOST_ALPHA * (remaining / GHOST_LIFETIME)


func _tick_fades(delta: float) -> void:
	if _fades.is_empty():
		return
	for index in range(_fades.size() - 1, -1, -1):
		var entry := _fades[index]
		var node: Variant = entry["node"]
		if not (node is Node) or not is_instance_valid(node):
			_fades.remove_at(index)
			continue
		entry["left"] = float(entry["left"]) - delta
		var remaining := float(entry["left"])
		if remaining <= 0.0:
			(node as Node).queue_free()
			_fades.remove_at(index)
			continue
		var ratio := remaining / maxf(float(entry.get("life", 1.0)), 0.001)
		(node as CanvasItem).modulate.a = clampf(ratio, 0.0, 1.0)


func _spawn_ghost(source: Node2D) -> void:
	var sprite := source as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = texture
	ghost.centered = sprite.centered
	ghost.offset = sprite.offset
	ghost.scale = sprite.scale
	ghost.flip_h = sprite.flip_h
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ghost.material = material
	ghost.modulate = Color(1.0, 1.0, 1.0, GHOST_ALPHA)
	ghost.top_level = true
	ghost.z_index = 2
	add_child(ghost)
	ghost.global_transform = sprite.global_transform
	_ghosts.append({"node": ghost, "left": GHOST_LIFETIME})

class_name Atmosphere
extends Node2D
## Air and beat life for the room: steam, dust, embers, belt glow and drum shimmer.
##
## Budget (`docs/UX_BIBLE.md` §3.5/§14): at most three `CPUParticles2D` emitters and well
## under 120 particles. Steam therefore uses **one** emitter with one emission point per
## washer instead of one emitter per machine. Every texture is generated in code and cached
## in `static var`; no raster asset is added.
##
## The additive belt rails and drum windows are drawn by one node with one additive
## material, so the whole neon layer costs a handful of tiny quads.

## Soft 16×16 puffer used by steam, dust and embers (generated once).
const PUFF_SIZE := 16
## Particles emitted by the steam emitter in the calm state (4 washers × 9).
const STEAM_AMOUNT := 36
## Steam amount while a washer is TURBULENT.
const STEAM_BOOSTED := 60
## Dust motes in the light.
const DUST_AMOUNT := 24
## Ember particles per burst.
const SPARK_AMOUNT := 4
## Seconds between ember bursts.
const SPARK_INTERVAL_S := 6.5
## Belt rail thickness in world pixels (1 art px, so the glow stays on the pixel grid).
const RAIL_THICKNESS := 4.0
## Default washer requirement order (NW, NE, SW, SE).
const DEFAULT_PALETTE: Array[StringName] = [&"red", &"blue", &"red", &"blue"]
## Additive rail brightness range.
const RAIL_ALPHA_MIN := 0.05
const RAIL_ALPHA_MAX := 0.16
## Drum window brightness range.
const DRUM_ALPHA_MIN := 0.04
const DRUM_ALPHA_MAX := 0.13

static var _puff: ImageTexture = null

## When > 0 the glow free-runs its own clock at this BPM instead of using BeatConductor.
@export var pulse_bpm := 0.0

var _steam: CPUParticles2D
var _dust: CPUParticles2D
var _spark: CPUParticles2D
var _spark_timer: Timer
var _glow: BeltGlow
var _clock := 0.0


## Adds the particle layer (z 8) under `root` and returns it.
static func build(root: Node2D, p_pulse_bpm: float = 0.0) -> Atmosphere:
	var atmosphere := Atmosphere.new()
	atmosphere.name = "Atmosphere"
	atmosphere.z_index = 8
	atmosphere.pulse_bpm = p_pulse_bpm
	root.add_child(atmosphere)
	atmosphere._setup_particles()
	return atmosphere


## Adds the additive neon layer (belt rails + drum windows) under `root` and returns it.
static func build_belt_glow(root: Node2D, p_pulse_bpm: float = 0.0) -> Node2D:
	var glow := BeltGlow.new()
	glow.name = "BeltGlow"
	glow.z_index = 9
	glow.pulse_bpm = p_pulse_bpm
	root.add_child(glow)
	glow.setup()
	return glow


## Generated 16×16 soft puff with a hard alpha falloff (no AA, no blur filter).
static func puff_texture() -> ImageTexture:
	if _puff != null:
		return _puff
	var image := Image.create(PUFF_SIZE, PUFF_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var center := float(PUFF_SIZE - 1) * 0.5
	for y in range(PUFF_SIZE):
		for x in range(PUFF_SIZE):
			var distance := Vector2(float(x) - center, float(y) - center).length()
			var alpha := clampf(1.0 - distance / center, 0.0, 1.0)
			# Quantise so the puff reads as pixel art instead of a smear.
			alpha = roundf(alpha * 4.0) / 4.0
			if alpha <= 0.0:
				continue
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_puff = ImageTexture.create_from_image(image)
	return _puff


## Drops the cached puff (tests only).
static func clear_cache() -> void:
	_puff = null


# --- particles ---------------------------------------------------------------


func _setup_particles() -> void:
	_steam = _make_particles("Steam")
	_steam.amount = STEAM_AMOUNT
	_steam.lifetime = 2.4
	_steam.preprocess = 1.0
	_steam.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	var tops := PackedVector2Array()
	for washer: Dictionary in RoomBuilder.layout().get("washers", []):
		var rect := RoomBuilder.rect_world(washer)
		tops.append(Vector2(rect.get_center().x, rect.position.y + 8.0))
	_steam.emission_points = tops
	_steam.direction = Vector2(0.0, -1.0)
	_steam.spread = 12.0
	_steam.initial_velocity_min = 10.0
	_steam.initial_velocity_max = 26.0
	_steam.gravity = Vector2(0.0, -12.0)
	_steam.scale_amount_min = 1.5
	_steam.scale_amount_max = 3.2
	_steam.color = Color(0.78, 0.86, 1.0, 1.0)
	_steam.color_ramp = _fade_ramp(0.22)

	_dust = _make_particles("Dust")
	_dust.amount = DUST_AMOUNT
	_dust.lifetime = 9.0
	_dust.preprocess = 4.0
	_dust.position = Vector2(640.0, 360.0)
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = Vector2(560.0, 260.0)
	_dust.direction = Vector2(1.0, 0.0)
	_dust.spread = 180.0
	_dust.initial_velocity_min = 2.0
	_dust.initial_velocity_max = 7.0
	_dust.gravity = Vector2(0.0, -1.0)
	_dust.scale_amount_min = 0.4
	_dust.scale_amount_max = 1.1
	_dust.color = Color(0.86, 0.92, 1.0, 1.0)
	_dust.color_ramp = _fade_ramp(0.12)

	_spark = _make_particles("Spark")
	_spark.amount = SPARK_AMOUNT
	_spark.lifetime = 1.2
	_spark.emitting = false
	_spark.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_spark.emission_rect_extents = Vector2(420.0, 160.0)
	_spark.position = Vector2(640.0, 300.0)
	_spark.direction = Vector2(0.0, -1.0)
	_spark.spread = 60.0
	_spark.initial_velocity_min = 16.0
	_spark.initial_velocity_max = 34.0
	_spark.gravity = Vector2(0.0, 24.0)
	_spark.scale_amount_min = 0.5
	_spark.scale_amount_max = 1.0
	_spark.color = Color(1.0, 0.74, 0.36, 1.0)
	_spark.color_ramp = _fade_ramp(0.7)

	_spark_timer = Timer.new()
	_spark_timer.name = "SparkTimer"
	_spark_timer.wait_time = SPARK_INTERVAL_S
	_spark_timer.autostart = true
	_spark_timer.timeout.connect(_on_spark_timeout)
	add_child(_spark_timer)
	var falloff := CeilingFalloff.new()
	falloff.name = "CeilingFalloff"
	falloff.z_index = -2
	add_child(falloff)
	falloff.setup()
	var shafts := LightShafts.new()
	shafts.name = "LightShafts"
	shafts.z_index = -1
	shafts.pulse_bpm = pulse_bpm
	add_child(shafts)
	shafts.setup()
	_apply_reduce_motion()


func _make_particles(node_name: String) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.name = node_name
	particles.texture = puff_texture()
	particles.emitting = true
	particles.local_coords = false
	add_child(particles)
	return particles


static func _fade_ramp(peak: float) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.62, 1.0])
	gradient.colors = PackedColorArray(
		[
			Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, peak),
			Color(1.0, 1.0, 1.0, peak * 0.55),
			Color(1.0, 1.0, 1.0, 0.0),
		]
	)
	return gradient


func _on_spark_timeout() -> void:
	if _spark == null or Settings.reduce_motion:
		return
	_spark.restart()


func _apply_reduce_motion() -> void:
	var calm := Settings.reduce_motion
	for particles: CPUParticles2D in [_steam, _dust, _spark]:
		if particles == null:
			continue
		particles.emitting = not calm
	if _spark_timer != null:
		_spark_timer.paused = calm


## More steam while a washer is TURBULENT (UX_BIBLE §6.7). Safe to call any time.
func set_steam_boosted(value: bool) -> void:
	if _steam == null:
		return
	_steam.amount = STEAM_BOOSTED if value else STEAM_AMOUNT


## True while the particle emitters are running (false under reduce motion).
func particles_active() -> bool:
	return _steam != null and _steam.emitting


func _process(delta: float) -> void:
	if pulse_bpm > 0.0:
		_clock += maxf(delta, 0.0)


# --- additive neon -----------------------------------------------------------


## Additive belt rails at each belt's outer edge plus a shimmer bar on every drum window.
class BeltGlow:
	extends Node2D

	const DRUM_SIZE := Vector2(64.0, 16.0)

	var pulse_bpm := 0.0

	var _rails: Array[Rect2] = []
	var _drums: Array[Rect2] = []
	var _colors: Array[Color] = []
	var _clock := 0.0
	var _last_envelope := -1.0

	func setup() -> void:
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive
		for belt: Dictionary in RoomBuilder.layout().get("belts", []):
			var rect := RoomBuilder.rect_world(belt)
			if rect.size.x >= rect.size.y:
				_rails.append(
					Rect2(rect.position.x, rect.position.y - Atmosphere.RAIL_THICKNESS, rect.size.x, Atmosphere.RAIL_THICKNESS)
				)
				_rails.append(
					Rect2(
						rect.position.x,
						rect.end.y,
						rect.size.x,
						Atmosphere.RAIL_THICKNESS
					)
				)
			else:
				_rails.append(
					Rect2(rect.position.x - Atmosphere.RAIL_THICKNESS, rect.position.y, Atmosphere.RAIL_THICKNESS, rect.size.y)
				)
				_rails.append(
					Rect2(rect.end.x, rect.position.y, Atmosphere.RAIL_THICKNESS, rect.size.y)
				)
		var index := 0
		for washer: Dictionary in RoomBuilder.layout().get("washers", []):
			var washer_rect := RoomBuilder.rect_world(washer)
			var center := Vector2(washer_rect.get_center().x, washer_rect.position.y + 88.0)
			_drums.append(Rect2(center - DRUM_SIZE * 0.5, DRUM_SIZE))
			var requirement: StringName = Atmosphere.DEFAULT_PALETTE[index % Atmosphere.DEFAULT_PALETTE.size()]
			_colors.append(Atmosphere.requirement_color(requirement))
			index += 1
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		if pulse_bpm > 0.0:
			_clock += maxf(delta, 0.0)
		var envelope := beat_envelope()
		if absf(envelope - _last_envelope) < 0.02:
			return
		_last_envelope = envelope
		queue_redraw()

	func _draw() -> void:
		var envelope := beat_envelope()
		var rail := Color(
			Palette.FUNK_CYAN.r,
			Palette.FUNK_CYAN.g,
			Palette.FUNK_CYAN.b,
			Atmosphere.RAIL_ALPHA_MIN + (Atmosphere.RAIL_ALPHA_MAX - Atmosphere.RAIL_ALPHA_MIN) * envelope
		)
		for rect: Rect2 in _rails:
			draw_rect(rect, rail, true)
		var drum_alpha := (
			Atmosphere.DRUM_ALPHA_MIN
			+ (Atmosphere.DRUM_ALPHA_MAX - Atmosphere.DRUM_ALPHA_MIN) * envelope
		)
		for index in range(_drums.size()):
			var color: Color = _colors[index]
			draw_rect(
				_drums[index],
				Color(color.r, color.g, color.b, drum_alpha),
				true
			)

	func beat_envelope() -> float:
		if Settings.reduce_motion:
			return 0.0
		var elapsed := 0.0
		if pulse_bpm > 0.0:
			elapsed = fposmod(_clock, 60.0 / pulse_bpm)
		elif BeatConductor.is_playing:
			elapsed = BeatConductor.get_beat_phase() * BeatConductor.beat_seconds()
		return maxf(0.0, 1.0 - elapsed / 0.28)

	## Retints the drum shimmer bars from washer requirement names.
	func set_phase_palette(requirements: Array[StringName]) -> void:
		if requirements.is_empty():
			return
		for index in range(_colors.size()):
			_colors[index] = Atmosphere.requirement_color(
				requirements[index % requirements.size()]
			)
		queue_redraw()


## Additive light falloff from the ceiling: ten stacked bands that fade out by y ≈ 420.
## This is what makes the floor read as a lit plane instead of a flat fill.
class CeilingFalloff:
	extends Node2D

	const BANDS := 10
	const HEIGHT := 420.0

	func setup() -> void:
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive
		queue_redraw()

	func _draw() -> void:
		var band_height := HEIGHT / float(BANDS)
		for index in range(BANDS):
			var fraction := 1.0 - float(index) / float(BANDS)
			var alpha := 0.055 * fraction * fraction
			draw_rect(
				Rect2(0.0, float(index) * band_height, 1280.0, band_height),
				Color(Palette.SPACE_HAZE.r, Palette.SPACE_HAZE.g, Palette.SPACE_HAZE.b, alpha),
				true
			)


## Two soft additive shafts under the ceiling lamps: cheap volumetric light that gives the
## room a lit-from-above read without a shader or a new light.
class LightShafts:
	extends Node2D

	var pulse_bpm := 0.0

	var _quads: Array[PackedVector2Array] = []
	var _clock := 0.0
	var _last := -1.0

	func setup() -> void:
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive
		for x in [320.0, 980.0]:
			_quads.append(
				PackedVector2Array(
					[
						Vector2(x - 16.0, 96.0),
						Vector2(x + 16.0, 96.0),
						Vector2(x + 84.0, 320.0),
						Vector2(x - 84.0, 320.0),
					]
				)
			)
		queue_redraw()

	func _process(delta: float) -> void:
		if pulse_bpm > 0.0:
			_clock += maxf(delta, 0.0)
		var envelope := beat_envelope()
		if absf(envelope - _last) < 0.05:
			return
		_last = envelope
		queue_redraw()

	func _draw() -> void:
		var alpha := 0.045 + 0.02 * beat_envelope()
		var color := Color(Palette.YEL_3.r, Palette.YEL_3.g, Palette.YEL_3.b, alpha)
		for quad: PackedVector2Array in _quads:
			draw_colored_polygon(quad, color)

	func beat_envelope() -> float:
		if Settings.reduce_motion:
			return 0.0
		var elapsed := 0.0
		if pulse_bpm > 0.0:
			elapsed = fposmod(_clock, 60.0 / pulse_bpm)
		elif BeatConductor.is_playing:
			elapsed = BeatConductor.get_beat_phase() * BeatConductor.beat_seconds()
		return maxf(0.0, 1.0 - elapsed / 0.28)


## Palette colour for a washer requirement name.
static func requirement_color(name: StringName) -> Color:
	match name:
		&"red":
			return Palette.RED_3
		&"blue":
			return Palette.BLUE_3
		&"yellow":
			return Palette.YEL_3
		_:
			return Palette.FUNK_CYAN

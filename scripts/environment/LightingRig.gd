class_name LightingRig
extends Node2D
## Tint-and-pool lighting for the room (`docs/UX_BIBLE.md` §3.5).
##
## We cannot author normal maps for 176 frames, so light is a dark [CanvasModulate] plus
## additive [PointLight2D] pools fed by one generated radial gradient. The rig is capped at
## [constant MAX_LIGHTS] lights with shadows off, which is the llvmpipe budget.
##
## Pulses follow [BeatConductor] (instant attack, ~0.28 s decay). When the conductor is not
## running — the dev sandbox, the title diorama — the rig free-runs at [member pulse_bpm]
## instead, so the room never looks dead. `Settings.reduce_motion` pins every energy to its
## base value.

## Hard cap from the performance budget; `build()` never creates more than this.
const MAX_LIGHTS := 8
## Washer pool radius in world pixels (UX_BIBLE §3.5).
const WASHER_RADIUS := 260.0
## Washer pool energy and its pulse amplitude (0.42…0.58).
const WASHER_ENERGY := 0.34
const WASHER_PULSE := 0.07
## Chute light energy (UX_BIBLE §3.5).
const CHUTE_ENERGY := 0.45
## Cold overhead lamp energy and radius.
const COLD_ENERGY := 0.18
const COLD_RADIUS := 420.0
## Warm lamp over the player spawn.
const WARM_ENERGY := 0.16
const WARM_RADIUS := 280.0
## Room tint: cool and ~55 % brightness (UX_BIBLE §3.5).
const ROOM_TINT := Color(0.70, 0.72, 0.84)
## Pulse decay in seconds after each beat.
const PULSE_DECAY := 0.28
## Radius of the generated gradient texture, in pixels.
const GRADIENT_RADIUS := 256

## Washer requirement order used when no palette has been pushed yet.
const DEFAULT_PALETTE: Array[StringName] = [&"red", &"blue", &"red", &"blue"]

static var _radial: GradientTexture2D = null

## When > 0 the rig free-runs its own beat clock at this BPM instead of using BeatConductor.
@export var pulse_bpm := 0.0
## Light intensity multiplier, used by the diorama to sit behind a title overlay.
@export var intensity := 1.0

var _modulate: CanvasModulate
var _pools: Array[PointLight2D] = []
var _chute: PointLight2D
var _cold: Array[PointLight2D] = []
var _warm: PointLight2D
var _floor_pools: Array[Sprite2D] = []
var _base_energy: Dictionary = {}
var _amplitude: Dictionary = {}
var _all: Array[PointLight2D] = []
var _clock := 0.0


## Adds the rig under `root` and returns it. `pulse_bpm` > 0 free-runs the pulse clock.
static func build(root: Node2D, p_pulse_bpm: float = 0.0) -> LightingRig:
	var rig := LightingRig.new()
	rig.name = "Lighting"
	rig.pulse_bpm = p_pulse_bpm
	root.add_child(rig)
	rig._setup()
	return rig


## Cached radial gradient used by every light. One texture, no image asset.
static func radial_texture() -> GradientTexture2D:
	if _radial != null:
		return _radial
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 0.72, 1.0])
	gradient.colors = PackedColorArray(
		[
			Color(1.0, 1.0, 1.0, 0.72),
			Color(1.0, 1.0, 1.0, 0.44),
			Color(1.0, 1.0, 1.0, 0.16),
			Color(1.0, 1.0, 1.0, 0.0),
		]
	)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = GRADIENT_RADIUS * 2
	texture.height = GRADIENT_RADIUS * 2
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_radial = texture
	return _radial


## Drops the cached gradient (tests only).
static func clear_cache() -> void:
	_radial = null


func _setup() -> void:
	_modulate = CanvasModulate.new()
	_modulate.name = "RoomTint"
	_modulate.color = ROOM_TINT
	add_child(_modulate)
	var palette := DEFAULT_PALETTE
	var mouths := [
		Vector2(60, 80),
		Vector2(260, 80),
		Vector2(60, 144),
		Vector2(260, 144),
	]
	for index in range(mouths.size()):
		var light := _add_light(
			"WasherPool%d" % index,
			RoomBuilder.point_world([mouths[index].x, mouths[index].y]),
			WASHER_RADIUS,
			WASHER_ENERGY,
			palette[index % palette.size()]
		)
		_pools.append(light)
	_build_floor_pools(palette)
	_chute = _add_light(
		"ChuteCone",
		RoomBuilder.layout_rect("chute").get_center(),
		220.0,
		CHUTE_ENERGY,
		&"clean_green"
	)
	for index in range(2):
		var x := 240.0 if index == 0 else 1040.0
		_cold.append(
			_add_light(
				"ColdLamp%d" % index, Vector2(x, 104.0), COLD_RADIUS, COLD_ENERGY, &"funk_cyan"
			)
		)
	_warm = _add_light("SpawnWarm", RoomBuilder.player_spawn(), WARM_RADIUS, WARM_ENERGY, &"yel_3")
	_update_energy()


## Coloured light spill painted on the floor itself (z −89): it tints the decals and the
## concrete without washing out the machine sprites, which sit above it.
func _build_floor_pools(palette: Array[StringName]) -> void:
	var layer := Node2D.new()
	layer.name = "FloorPools"
	layer.z_index = -89
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	layer.material = additive
	add_child(layer)
	var mouths := [
		Vector2(60, 80),
		Vector2(260, 80),
		Vector2(60, 144),
		Vector2(260, 144),
	]
	for index in range(mouths.size()):
		var pool := Sprite2D.new()
		pool.name = "WasherSpill%d" % index
		pool.texture = radial_texture()
		pool.centered = true
		pool.position = RoomBuilder.point_world([mouths[index].x, mouths[index].y])
		var tint := _tint_color(palette[index % palette.size()])
		pool.self_modulate = Color(tint.r, tint.g, tint.b, 0.16)
		layer.add_child(pool)
		_floor_pools.append(pool)
	var chute_pool := Sprite2D.new()
	chute_pool.name = "ChuteSpill"
	chute_pool.texture = radial_texture()
	chute_pool.position = RoomBuilder.layout_rect("chute").get_center()
	chute_pool.scale = Vector2(0.8, 0.8)
	chute_pool.self_modulate = Color(
		Palette.CLEAN_GREEN.r, Palette.CLEAN_GREEN.g, Palette.CLEAN_GREEN.b, 0.16
	)
	layer.add_child(chute_pool)
	_floor_pools.append(chute_pool)


func _add_light(
	light_name: String, at: Vector2, radius: float, energy: float, tint: StringName
) -> PointLight2D:
	var light := PointLight2D.new()
	light.name = light_name
	light.texture = radial_texture()
	light.texture_scale = radius / float(GRADIENT_RADIUS)
	light.position = Vector2(roundf(at.x), roundf(at.y))
	light.color = _tint_color(tint)
	light.energy = energy
	light.shadow_enabled = false
	light.blend_mode = Light2D.BLEND_MODE_ADD
	add_child(light)
	_base_energy[light] = energy
	_amplitude[light] = WASHER_PULSE if light_name.begins_with("WasherPool") else WASHER_PULSE * 0.3
	_all.append(light)
	return light


func _process(delta: float) -> void:
	if pulse_bpm > 0.0:
		_clock += maxf(delta, 0.0)
	_update_energy()


## Retints the four washer pools from requirement names (`red`, `blue`, `yellow`).
## Unknown or missing entries keep the previous colour, so a partial list is safe.
func set_phase_palette(requirements: Array[StringName]) -> void:
	if requirements.is_empty():
		requirements = DEFAULT_PALETTE.duplicate()
	for index in range(_pools.size()):
		var requirement: StringName = requirements[index % requirements.size()]
		var tint := _tint_color(requirement)
		_pools[index].color = tint
		if index < _floor_pools.size():
			_floor_pools[index].self_modulate = Color(tint.r, tint.g, tint.b, 0.16)


## Every light the rig created (tests assert the budget).
func lights() -> Array[PointLight2D]:
	var out: Array[PointLight2D] = []
	out.append_array(_all)
	return out


## Light pools only, in washer order (NW, NE, SW, SE).
func pools() -> Array[PointLight2D]:
	return _pools


## Room tint node.
func room_tint() -> CanvasModulate:
	return _modulate


## Current pulse envelope in [0, 1]; 0 when reduce motion is on.
func beat_envelope() -> float:
	if Settings.reduce_motion:
		return 0.0
	return maxf(0.0, 1.0 - _beat_elapsed() / PULSE_DECAY)


func _beat_elapsed() -> float:
	if pulse_bpm > 0.0:
		var beat_s := 60.0 / pulse_bpm
		return fposmod(_clock, beat_s)
	if not BeatConductor.is_playing:
		return 0.0
	return BeatConductor.get_beat_phase() * BeatConductor.beat_seconds()


func _update_energy() -> void:
	var envelope := beat_envelope()
	for light: PointLight2D in _all:
		var base: float = float(_base_energy.get(light, light.energy))
		var amplitude: float = float(_amplitude.get(light, 0.0))
		light.energy = (base + amplitude * envelope) * intensity


static func _tint_color(name: StringName) -> Color:
	match name:
		&"red", &"red_3":
			return Palette.RED_3
		&"blue", &"blue_3":
			return Palette.BLUE_3
		&"yellow", &"yel_3":
			return Palette.YEL_3
		&"clean_green":
			return Palette.CLEAN_GREEN
		&"funk_cyan":
			return Palette.FUNK_CYAN
		_:
			return Palette.METAL_2

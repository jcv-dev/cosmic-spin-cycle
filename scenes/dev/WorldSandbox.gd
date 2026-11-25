class_name WorldSandbox
extends Node2D
## M3 greybox playground: belts, shredders, floor and a seeded spawner, no M2 needed.
##
## The scene builds itself from `data/layout.json` (art px × `Config.ART_SCALE`), spawns
## stub items through [SpawnDirector] and drives its own deterministic shift clock, so it
## runs headlessly and in the editor without the audio/beat stack. Keys 1-4 force a phase,
## R restarts the shift with a new seed.
##
## This is a development scene: the stub items (flat palette discs) are replaced by
## `LaundryItem` once M2 lands, and `SpawnDirector.item_scene` then takes over.

const LAYOUT_PATH := "res://data/layout.json"
const SCENE_BELT := "res://scenes/environment/ConveyorBelt.tscn"
const SCENE_SHREDDER := "res://scenes/environment/Shredder.tscn"

## Inset of the dispenser from the belt end, in world pixels.
const SPAWN_INSET := 4.0 * float(Config.ART_SCALE)
## Inset of the room walls, in art pixels (`layout.room.wall`).
const WALL_ART := 8.0

## Radius of a stub item body, in world pixels (matches the LaundryItem greybox).
@export var stub_item_radius := 14.0
## Seed of the current shift; set before `start_shift()` to reproduce a run.
@export var seed_value := 1234
## Simulated seconds per real second; 1.0 is a real-time shift.
@export var time_scale := 1.0

var layout: Dictionary = {}
## belt id -> ConveyorBelt
var belts: Dictionary = {}
## shredder id -> Shredder
var shredders: Dictionary = {}
var director: SpawnDirector
var floor_node: Node2D
var readout: Label

var shift_time := 0.0
var bpm := Config.PHASE_BPM[0]
var beat := 0
var measure := 0

var _beat_accum := 0.0
var _readout_accum := 0.0


func _ready() -> void:
	layout = _load_layout()
	_build_floor()
	_build_belts()
	_build_shredders()
	_build_director()
	_build_readout()
	start_shift()


func _process(delta: float) -> void:
	step(delta * time_scale)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_4:
		force_phase(int(key - KEY_1))
	elif key == KEY_R:
		seed_value += 1
		start_shift()


# --- public API -------------------------------------------------------------


## Advances the sandbox clock by `delta` seconds of shift time.
func step(delta: float) -> void:
	if delta <= 0.0 or director == null:
		return
	shift_time += delta
	director.advance_to(shift_time)
	_advance_beat_clock(delta)
	_readout_accum += delta
	if _readout_accum >= 0.1:
		_readout_accum = 0.0
		_update_readout()
	if shift_time >= Config.SHIFT_DURATION_S:
		start_shift()


## Restarts the shift at t = 0 with the current seed.
func start_shift() -> void:
	shift_time = 0.0
	_beat_accum = 0.0
	beat = 0
	measure = 0
	for belt: ConveyorBelt in belts.values():
		belt.reversal.reset()
		belt.set_flow_direction(_layout_flow(String(belt.belt_id)))
	if director != null:
		director.current_phase = -1
		director.start(seed_value)
	_update_readout()


## Jumps to the start of `index` (sandbox keys 1-4).
func force_phase(index: int) -> void:
	if director == null:
		return
	director.force_phase(index)
	shift_time = Config.phase_start_s(index) + 0.001
	_beat_accum = 0.0
	beat = 0
	measure = 0
	for belt: ConveyorBelt in belts.values():
		belt.reversal.reset()
		belt.set_flow_direction(_layout_flow(String(belt.belt_id)))
	director.seek(shift_time)
	_update_readout()


## Current clock/phase/counter line(s) shown in the corner.
func readout_text() -> String:
	if director == null:
		return ""
	var counts := director.spawned_count_by_phase
	var padded: Array[int] = [0, 0, 0, 0]
	for index in range(mini(counts.size(), padded.size())):
		padded[index] = counts[index]
	var total := 0
	for count in padded:
		total += count
	var drops := 0
	if GameState != null:
		drops = GameState.dropped_count
	return (
		(
			"%s  phase %d/4  %d BPM  beat %d  measure %d\n"
			% [Config.clock_string(shift_time), director.current_phase + 1, bpm, beat, measure]
		)
		+ (
			"spawned %d/%d/%d/%d  total %d  alive %d  dropped %d\n"
			% [padded[0], padded[1], padded[2], padded[3], total, director.alive_count(), drops]
		)
		+ "[1-4] force phase   [R] restart seed %d" % seed_value
	)


# --- construction -----------------------------------------------------------


func _load_layout() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_PATH):
		push_warning("WorldSandbox: %s is missing" % LAYOUT_PATH)
		return {}
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _build_floor() -> void:
	floor_node = Node2D.new()
	floor_node.name = "Floor"
	add_child(floor_node)
	var room: Dictionary = layout.get("room", {})
	var width := float(room.get("w", Config.ART_CANVAS.x)) * Config.ART_SCALE
	var height := float(room.get("h", Config.ART_CANVAS.y)) * Config.ART_SCALE
	_add_rect(floor_node, "Room", Rect2(0.0, 0.0, width, height), "space_deep")
	var inset := WALL_ART * Config.ART_SCALE
	_add_rect(
		floor_node,
		"PlayArea",
		Rect2(inset, inset, width - inset * 2.0, height - inset * 2.0),
		"space_void"
	)
	_build_walls(width, height, inset)


func _build_walls(width: float, height: float, inset: float) -> void:
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	walls.collision_layer = Config.CollisionLayer.WORLD
	walls.collision_mask = Config.CollisionLayer.ITEMS
	floor_node.add_child(walls)
	var thickness := inset
	_add_wall(walls, "Top", Rect2(-inset, -thickness, width + inset * 2.0, thickness))
	_add_wall(walls, "Bottom", Rect2(-inset, height, width + inset * 2.0, thickness))
	_add_wall(walls, "Left", Rect2(-inset, -inset, thickness, height + inset * 2.0))
	_add_wall(walls, "Right", Rect2(width, -inset, thickness, height + inset * 2.0))


func _add_wall(parent: Node, wall_name: String, rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.name = wall_name
	collision.shape = shape
	collision.position = rect.position + rect.size * 0.5
	parent.add_child(collision)


func _add_rect(parent: Node, rect_name: String, rect: Rect2, palette_name: String) -> void:
	var polygon := Polygon2D.new()
	polygon.name = rect_name
	polygon.color = EnvironmentPalette.color(palette_name)
	polygon.polygon = PackedVector2Array(
		[
			rect.position,
			rect.position + Vector2(rect.size.x, 0.0),
			rect.position + rect.size,
			rect.position + Vector2(0.0, rect.size.y),
		]
	)
	parent.add_child(polygon)


func _build_belts() -> void:
	var scene := load(SCENE_BELT) as PackedScene
	if scene == null:
		return
	var belt_entries: Array = layout.get("belts", [])
	for entry: Dictionary in belt_entries:
		var belt := scene.instantiate() as ConveyorBelt
		belt.name = String(entry.id)
		add_child(belt)
		belt.configure(
			StringName(entry.id), _art_rect(entry), _vector_from(entry.get("flow", [1, 0]))
		)
		belts[String(entry.id)] = belt


func _build_shredders() -> void:
	var scene := load(SCENE_SHREDDER) as PackedScene
	if scene == null:
		return
	var shredder_entries: Array = layout.get("shredders", [])
	for entry: Dictionary in shredder_entries:
		var shredder := scene.instantiate() as Shredder
		shredder.name = String(entry.id)
		add_child(shredder)
		shredder.configure(StringName(entry.id), _art_rect(entry))
		shredders[String(entry.id)] = shredder


func _build_director() -> void:
	director = SpawnDirector.new()
	director.name = "SpawnDirector"
	add_child(director)
	director.stub_factory = _make_stub_item
	director.position_resolver = _resolve_spawn_position
	director.phase_changed.connect(_on_phase_changed)


func _build_readout() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	readout = Label.new()
	readout.name = "Readout"
	readout.position = Vector2(16.0, 12.0)
	readout.add_theme_font_size_override("font_size", 18)
	readout.add_theme_color_override("font_color", EnvironmentPalette.color("funk_cyan"))
	layer.add_child(readout)


# --- clock and beats --------------------------------------------------------


func _advance_beat_clock(delta: float) -> void:
	var seconds_per_beat := Config.beat_seconds(float(bpm))
	if seconds_per_beat <= 0.0:
		return
	_beat_accum += delta
	while _beat_accum >= seconds_per_beat:
		_beat_accum -= seconds_per_beat
		beat += 1
		measure = floori(float(beat) / float(Config.BEATS_PER_MEASURE))
		_on_beat()


func _on_beat() -> void:
	var phase := 0
	if director != null:
		phase = director.current_phase
	for belt: ConveyorBelt in belts.values():
		belt.on_beat(beat, measure, phase)


func _on_phase_changed(index: int) -> void:
	var entry: PhaseData = null
	if director != null and director.phase_table != null:
		entry = director.phase_table.phase(index)
	if entry != null:
		bpm = entry.bpm
	_beat_accum = 0.0
	beat = 0
	measure = 0
	for belt: ConveyorBelt in belts.values():
		belt.reversal.reset()
		belt.set_flow_direction(_layout_flow(String(belt.belt_id)))
	_update_readout()


# --- items ------------------------------------------------------------------


func _make_stub_item(event: Dictionary) -> Node:
	var item_id := StringName(str(event.get("item_id", "")))
	var body := RigidBody2D.new()
	body.name = "Stub_%s" % item_id
	body.collision_layer = Config.CollisionLayer.ITEMS
	body.collision_mask = Config.CollisionLayer.WORLD | Config.CollisionLayer.ITEMS
	body.gravity_scale = 0.0
	body.linear_damp = 2.0
	body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	var shape := CircleShape2D.new()
	shape.radius = stub_item_radius
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = shape
	body.add_child(collision)
	var speed_scale := Config.BELT_SOCK_SPEED_SCALE if item_id == &"sock" else 1.0
	body.set_meta(&"belt_speed_scale", speed_scale)
	body.set_meta(&"is_stub", true)
	_add_stub_visual(
		body, StringName(str(event.get("color", ""))), StringName(str(event.get("pattern", "")))
	)
	return body


func _add_stub_visual(body: Node, color_id: StringName, pattern: StringName) -> void:
	var polygon := Polygon2D.new()
	polygon.name = "Visual"
	polygon.color = _color_for(color_id)
	polygon.polygon = _disc(stub_item_radius)
	body.add_child(polygon)
	if pattern == &"":
		polygon.color = EnvironmentPalette.color("funk_magenta")
		return
	if pattern == &"ringed":
		var ring := Polygon2D.new()
		ring.name = "Pattern"
		ring.color = EnvironmentPalette.color("metal_3")
		ring.polygon = _disc(stub_item_radius * 0.45)
		body.add_child(ring)
	elif pattern == &"spotted":
		var dots := Polygon2D.new()
		dots.name = "Pattern"
		dots.color = EnvironmentPalette.color("metal_4")
		dots.polygon = _disc(stub_item_radius * 0.25)
		dots.position = Vector2(stub_item_radius * 0.35, -stub_item_radius * 0.35)
		body.add_child(dots)


func _color_for(color_id: StringName) -> Color:
	match color_id:
		&"red":
			return EnvironmentPalette.color("red_2")
		&"blue":
			return EnvironmentPalette.color("blue_2")
		&"yellow":
			return EnvironmentPalette.color("yel_2")
		_:
			return EnvironmentPalette.color("metal_2")


func _disc(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments := 12
	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _resolve_spawn_position(_event: Dictionary, phase: PhaseData) -> Vector2:
	if phase == null or phase.active_belts.is_empty():
		return director.spawn_position
	var belt_id := String(phase.active_belts[0])
	var belt: ConveyorBelt = belts.get(belt_id)
	if belt == null:
		return director.spawn_position
	return _belt_spawn_point(belt)


func _belt_spawn_point(belt: ConveyorBelt) -> Vector2:
	var entry := _belt_layout_entry(String(belt.belt_id))
	var rect := _art_rect(entry)
	var center := rect.position + rect.size * 0.5
	if absf(belt.flow_direction.x) > 0.0:
		var x := rect.position.x + SPAWN_INSET / Config.ART_SCALE
		if belt.flow_direction.x < 0.0:
			x = rect.end.x - SPAWN_INSET / Config.ART_SCALE
		center.x = x
	else:
		var y := rect.position.y + SPAWN_INSET / Config.ART_SCALE
		if belt.flow_direction.y > 0.0:
			y = rect.end.y - SPAWN_INSET / Config.ART_SCALE
		center.y = y
	return center * float(Config.ART_SCALE)


# --- layout helpers ---------------------------------------------------------


func _belt_layout_entry(belt_id: String) -> Dictionary:
	var belt_entries: Array = layout.get("belts", [])
	for entry: Dictionary in belt_entries:
		if String(entry.id) == belt_id:
			return entry
	return {}


func _layout_flow(belt_id: String) -> Vector2:
	var entry := _belt_layout_entry(belt_id)
	if entry.is_empty():
		return Vector2.RIGHT
	return _vector_from(entry.get("flow", [1, 0]))


func _art_rect(entry: Dictionary) -> Rect2:
	if entry.is_empty():
		return Rect2()
	return Rect2(
		float(entry.get("x", 0.0)),
		float(entry.get("y", 0.0)),
		float(entry.get("w", 0.0)),
		float(entry.get("h", 0.0))
	)


func _vector_from(values: Variant) -> Vector2:
	if not (values is Array):
		return Vector2.RIGHT
	var list: Array = values
	if list.size() < 2:
		return Vector2.RIGHT
	return Vector2(float(list[0]), float(list[1]))


func _update_readout() -> void:
	if readout != null:
		readout.text = readout_text()

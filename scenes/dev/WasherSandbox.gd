class_name WasherSandbox
extends Node2D
## M4/M5 dev playground and screenshot scene: four washers in every visual state, the
## delivery chute holding its `ENTREGAR` beacon, a few items and Pip.
##
## Keys: 1-4 swap the phase assignments, T forces turbulence on the south-west machine,
## R resets the demonstration. It runs headless (tests instantiate it) and needs no input.

const LAYOUT_PATH := "res://data/layout.json"
const SCENE_WASHER := "res://scenes/entities/CosmicWasher.tscn"
const SCENE_CHUTE := "res://scenes/environment/DeliveryChute.tscn"

## Phase used by the screenshot: P2 keeps the south-east machine locked, which shows the
## `FUERA DE SERVICIO` encoding next to a washing and a turbulent machine.
const DEMO_PHASE := 1
const CAPTION := "M4 · LEE EL HOLOGRAMA · LANZA AL RITMO · ENTREGA LIMPIO EN EL DUCTO"

var layout: Dictionary = {}
var washers: Dictionary = {}
var chute: DeliveryChute
var phase := DEMO_PHASE
var caption: Label

var _items_parent: Node2D


func _ready() -> void:
	layout = _load_layout()
	_build_room()
	_items_parent = Node2D.new()
	_items_parent.name = "Items"
	add_child(_items_parent)
	_build_washers()
	_build_chute()
	_build_actor()
	_build_caption()
	_pose_demo()


func _process(delta: float) -> void:
	# Keep the demonstration alive if it is left running (editor / long screenshots).
	chute.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_4:
		phase = int(key - KEY_1)
		_apply_phase()
	elif key == KEY_T:
		var south_west := washers.get(&"washer_sw") as CosmicWasher
		if south_west != null:
			south_west.force_turbulent()
	elif key == KEY_R:
		_pose_demo()


# --- demo states ------------------------------------------------------------


func _pose_demo() -> void:
	_apply_phase()
	var north_west := washers.get(&"washer_nw") as CosmicWasher
	var north_east := washers.get(&"washer_ne") as CosmicWasher
	var south_west := washers.get(&"washer_sw") as CosmicWasher
	if north_west != null:
		north_west.set_carry_hint(_spawn_item(&"rocky", &"red", &"solid", false, Vector2(500, 426)))
	if north_east != null:
		north_east.try_accept(_spawn_item(&"sock", &"blue", &"solid", false, Vector2(760, 470)))
		north_east.strike(RhythmEvaluator.Grade.GOOD)
		north_east.tick(2.2)
	if south_west != null:
		south_west.try_accept(_spawn_item(&"moon", &"yellow", &"solid", false, Vector2(430, 560)))
		south_west.strike(RhythmEvaluator.Grade.PERFECT)
		south_west.force_turbulent()
	if chute != null:
		var carried := _spawn_item(&"gas_giant", &"blue", &"ringed", true, Vector2(408, 470))
		if carried != null:
			carried.visible = false
		chute.set_carry_hint(carried)
	_spawn_item(&"moon", &"yellow", &"spotted", false, Vector2(470, 640))
	_spawn_item(&"rocky", &"blue", &"solid", false, Vector2(790, 640))
	_spawn_item(&"sock", &"red", &"solid", false, Vector2(360, 640))


func _apply_phase() -> void:
	var assignments := WasherAssignments.for_phase(phase)
	for washer_id: String in assignments:
		var row: Dictionary = assignments[washer_id]
		var washer := washers.get(StringName(washer_id)) as CosmicWasher
		if washer == null:
			continue
		washer.set_phase(phase)
		washer.set_requirement(StringName(str(row["requirement"])))
		washer.set_locked(bool(row["locked"]))


# --- construction -----------------------------------------------------------


func _build_room() -> void:
	var background := Sprite2D.new()
	background.name = "RoomBackground"
	background.texture = ArtCatalog.texture("env_room")
	background.centered = false
	background.scale = Vector2.ONE * float(Config.ART_SCALE)
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.z_index = -100
	add_child(background)


func _build_washers() -> void:
	var layer := Node2D.new()
	layer.name = "Washers"
	layer.z_index = 0
	add_child(layer)
	var scene := load(SCENE_WASHER) as PackedScene
	if scene == null:
		push_error("WasherSandbox: cannot load %s" % SCENE_WASHER)
		return
	for row in _washers_layout():
		var washer := scene.instantiate() as CosmicWasher
		washer.name = String(row["id"])
		layer.add_child(washer)
		var rect := Rect2(float(row["x"]), float(row["y"]), float(row["w"]), float(row["h"]))
		var mouth := Vector2(float(row["mouth"][0]), float(row["mouth"][1]))
		washer.configure(StringName(str(row["id"])), rect, mouth, &"wild")
		washers[StringName(str(row["id"]))] = washer


func _build_chute() -> void:
	var scene := load(SCENE_CHUTE) as PackedScene
	if scene == null:
		push_error("WasherSandbox: cannot load %s" % SCENE_CHUTE)
		return
	chute = scene.instantiate() as DeliveryChute
	chute.name = "DeliveryChute"
	add_child(chute)
	var data: Dictionary = layout.get("chute", {})
	var center_data: Array = data.get("center", [160, 90])
	var rect := Rect2(
		float(data.get("x", 144)),
		float(data.get("y", 74)),
		float(data.get("w", 32)),
		float(data.get("h", 32))
	)
	chute.configure(rect, Vector2(float(center_data[0]), float(center_data[1])))


func _build_actor() -> void:
	var scene := load(Config.SCENE_PLAYER) as PackedScene
	if scene == null:
		return
	var player := scene.instantiate() as Player
	player.name = "Player"
	add_child(player)
	var spawn: Array = layout.get("player_spawn", [160, 128])
	player.global_position = (
		Vector2(float(spawn[0]), float(spawn[1])) * float(Config.ART_SCALE) + Vector2(-140.0, 48.0)
	)
	player.set_aim_direction(Vector2.UP)


func _build_caption() -> void:
	caption = Label.new()
	caption.name = "Caption"
	caption.text = CAPTION
	caption.add_theme_font_override("font", Fonts.pixel_font())
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", Palette.METAL_3)
	caption.add_theme_color_override("font_outline_color", Palette.SPACE_VOID)
	caption.add_theme_constant_override("outline_size", 5)
	caption.position = Vector2(360.0, 690.0)
	caption.z_index = 20
	add_child(caption)


func _spawn_item(
	id: StringName, color: StringName, pattern: StringName, clean: bool, at: Vector2
) -> LaundryItem:
	var scene := load(Config.SCENE_LAUNDRY_ITEM) as PackedScene
	if scene == null:
		return null
	var item := scene.instantiate() as LaundryItem
	item.setup(id, color, pattern, clean)
	_items_parent.add_child(item)
	item.global_position = at
	item.freeze = true
	return item


func _washers_layout() -> Array:
	var rows: Array = layout.get("washers", [])
	return rows if not rows.is_empty() else _fallback_washers()


func _fallback_washers() -> Array:
	return [
		{"id": "washer_nw", "x": 36, "y": 32, "w": 48, "h": 48, "mouth": [60, 80]},
		{"id": "washer_ne", "x": 236, "y": 32, "w": 48, "h": 48, "mouth": [260, 80]},
		{"id": "washer_sw", "x": 36, "y": 96, "w": 48, "h": 48, "mouth": [60, 144]},
		{"id": "washer_se", "x": 236, "y": 96, "w": 48, "h": 48, "mouth": [260, 144]},
	]


func _load_layout() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}

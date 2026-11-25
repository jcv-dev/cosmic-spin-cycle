class_name EnvironmentSandbox
extends Node2D
## Dev scene for the environment pass: the real room plus display machinery, at 1× zoom.
##
## It exists to take honest screenshots of the layered room and to feed `tools/fps_probe.gd`
## with a fixed, weight-stable frame. Nothing here is shipped: the sandbox only instances
## the same builders the level uses (`RoomBuilder`, `RoomDressing`, `LightingRig`,
## `Atmosphere`) plus the shipped belt/shredder scenes, so what you see is what `MainLevel`
## will show once it is wired.
##
## Keys: 1–4 retint the washer pools, R replays the intro beat, H toggles the dressing layer,
## L toggles the light rig (for A/B cost measurements).

const BELT_SCENE := "res://scenes/environment/ConveyorBelt.tscn"
const SHREDDER_SCENE := "res://scenes/environment/Shredder.tscn"
## Items placed on the north belt for scale and colour.
const BELT_ITEMS := [
	{"id": "item_rocky", "variant": &"red_solid", "offset": Vector2(180.0, 32.0)},
	{"id": "item_sock", "variant": &"blue_ringed", "offset": Vector2(430.0, 32.0)},
	{"id": "item_moon", "variant": &"yellow_solid", "offset": Vector2(700.0, 32.0)},
]

var layout: Dictionary = {}
var nodes: Dictionary = {}
var machines: Dictionary = {}
var belts: Dictionary = {}
var rig: LightingRig
var atmosphere: Atmosphere

var _items: Array[AnimatedSprite2D] = []
var _elapsed := 0.0
var _window_applied := false


func _ready() -> void:
	layout = RoomBuilder.layout()
	nodes = RoomBuilder.build(self)
	rig = nodes.get("lighting") as LightingRig
	atmosphere = nodes.get("atmosphere") as Atmosphere
	if not BeatConductor.is_playing:
		BeatConductor.start(Config.PHASE_BPM[0])
	machines = RoomDressing.build_machines_for_display(self)
	_build_belts()
	_build_shredders()
	_build_items()
	_paint_washers()
	if _has_arg("--bare"):
		_apply_bare()
	if _has_arg("--no-lights") and rig != null:
		rig.visible = false
	if _has_arg("--no-pointlights") and rig != null:
		for child in rig.get_children():
			if child is PointLight2D:
				(child as PointLight2D).visible = false
	if _has_arg("--no-atmosphere"):
		var atmo := nodes.get("atmosphere") as CanvasItem
		if atmo != null:
			atmo.visible = false
	if _has_arg("--no-backdrop"):
		var backdrop := nodes.get("backdrop") as CanvasItem
		if backdrop != null:
			backdrop.visible = false
	if _has_arg("--no-floordecals"):
		var floor_node := get_node_or_null(^"Floor") as Node2D
		if floor_node != null:
			var decals := floor_node.get_node_or_null(^"FloorDecals") as CanvasItem
			if decals != null:
				decals.visible = false
	if _has_arg("--no-beltshade"):
		var shade := nodes.get("belt_shadow") as CanvasItem
		if shade != null:
			shade.visible = false
	if _has_arg("--no-glow"):
		var glow_node := nodes.get("belt_glow") as CanvasItem
		if glow_node != null:
			glow_node.visible = false
	if _has_arg("--no-dressing"):
		for key in ["dressing", "foreground"]:
			var node := nodes.get(key) as CanvasItem
			if node != null:
				node.visible = false


func _process(delta: float) -> void:
	_elapsed += delta
	if not _window_applied and _is_screenshot_run():
		_window_applied = true
		_force_shot_window()
	_animate_items(delta)


## 1280×720 is required for pixel-exact screenshots; the harness window may come up larger
## under the compositor's fractional scaling.
func _force_shot_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if window == null:
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.size = Config.ART_CANVAS * Config.ART_SCALE


static func _is_screenshot_run() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return true
	return false


static func _has_arg(flag: String) -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == flag:
			return true
	return false


## `--bare` disables this workstream's layers so `docs/media/env_before.png` is the same
## scene and framing as the after shot, isolating the environment pass.
func _apply_bare() -> void:
	for key in ["backdrop", "dressing", "foreground", "atmosphere", "belt_glow", "belt_shadow"]:
		var node := nodes.get(key) as CanvasItem
		if node != null:
			node.visible = false
	var dressing := get_node_or_null(^"FloorDecals") as CanvasItem
	if dressing != null:
		dressing.visible = false
	var floor := get_node_or_null(^"Floor") as Node2D
	if floor != null:
		var decals := floor.get_node_or_null(^"FloorDecals") as CanvasItem
		if decals != null:
			decals.visible = false
	if rig != null:
		rig.visible = false
		var tint := rig.room_tint()
		if tint != null:
			tint.color = Color.WHITE
	# The display machinery also carries the pass's albedo trim and panel readouts; strip
	# both so `--bare` is the untouched greybox.
	var readouts := get_node_or_null(^"PanelReadouts") as CanvasItem
	if readouts != null:
		readouts.visible = false
	var washers: Dictionary = machines.get("washers", {})
	for key: StringName in washers.keys():
		var sprite := washers[key] as CanvasItem
		if sprite != null:
			sprite.self_modulate = Color.WHITE


func _build_belts() -> void:
	var layer := Node2D.new()
	layer.name = "Belts"
	layer.z_index = -5
	add_child(layer)
	var scene := load(BELT_SCENE) as PackedScene
	if scene == null:
		return
	for belt: Dictionary in layout.get("belts", []):
		var node := scene.instantiate() as ConveyorBelt
		node.name = String(belt.get("id", "belt"))
		layer.add_child(node)
		var flow: Array = belt.get("flow", [1, 0])
		node.configure(
			StringName(belt.get("id", "")),
			RoomBuilder.art_rect(belt),
			Vector2(float(flow[0]), float(flow[1]))
		)
		belts[StringName(node.name)] = node


func _build_shredders() -> void:
	var layer := Node2D.new()
	layer.name = "Shredders"
	layer.z_index = -4
	add_child(layer)
	var scene := load(SHREDDER_SCENE) as PackedScene
	if scene == null:
		return
	for entry: Dictionary in layout.get("shredders", []):
		var node := scene.instantiate() as Shredder
		node.name = String(entry.get("id", "shredder"))
		layer.add_child(node)
		node.configure(StringName(entry.get("id", "")), RoomBuilder.art_rect(entry))


func _build_items() -> void:
	var layer := Node2D.new()
	layer.name = "Items"
	layer.z_index = 5
	add_child(layer)
	for entry: Dictionary in BELT_ITEMS:
		var sprite := AnimatedSprite2D.new()
		sprite.name = String(entry.get("id", "item"))
		sprite.position = (
			RoomBuilder.layout_rect("belt_north").position + (entry.get("offset") as Vector2)
		)
		layer.add_child(sprite)
		if SpriteSheet.configure(sprite, String(entry.get("id", "")), entry.get("variant", &"")):
			_items.append(sprite)


## One washer mid-wash, one done, two idle: the room should read as alive at a glance.
func _paint_washers() -> void:
	var washers: Dictionary = machines.get("washers", {})
	var states := {
		&"washer_nw": &"washing",
		&"washer_ne": &"idle",
		&"washer_sw": &"idle",
		&"washer_se": &"done",
	}
	for key: StringName in washers.keys():
		var sprite := washers[key] as AnimatedSprite2D
		if sprite == null or sprite.sprite_frames == null:
			continue
		var anim: StringName = states.get(key, &"idle")
		if sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)


func _animate_items(_delta: float) -> void:
	var belt := RoomBuilder.layout_rect("belt_north")
	for index in range(_items.size()):
		var sprite := _items[index]
		var travel := fposmod(_elapsed * 26.0 + float(index) * 240.0, belt.size.x - 80.0)
		sprite.position = Vector2(belt.position.x + 40.0 + travel, belt.position.y + 32.0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_4:
		var palettes := [
			[&"red", &"blue", &"red", &"blue"],
			[&"blue", &"red", &"yellow", &"blue"],
			[&"yellow", &"yellow", &"red", &"blue"],
			[&"red", &"blue", &"yellow", &"red"],
		]
		rig.set_phase_palette(palettes[key - KEY_1])
	elif key == KEY_H:
		var dressing := get_node_or_null(^"RoomDressing") as Node2D
		if dressing != null:
			dressing.visible = not dressing.visible
	elif key == KEY_L:
		if rig != null:
			rig.visible = not rig.visible

extends Node2D
## Main level assembly and the M0–M3 "shift spine".
##
## Builds the static room, environment, player, spawner and UI from the frozen contracts
## and drives the 480 s clock + phase changes. Systems land progressively: every optional
## node is loaded behind a `ResourceLoader.exists()` guard so the level always boots.
##
## M5 will replace the lightweight clock/win logic with ShiftManager; M6 replaces the end
## label with the real screen flow. The node graph and anchors are already final.

const HUD_SCENE := "res://scenes/ui/HUD.tscn"
const DEBUG_OVERLAY_SCENE := "res://scenes/ui/DebugOverlay.tscn"
const BELT_SCENE := "res://scenes/environment/ConveyorBelt.tscn"
const SHREDDER_SCENE := "res://scenes/environment/Shredder.tscn"
const SPAWN_DIRECTOR_SCRIPT := "res://scripts/components/SpawnDirector.gd"
const MUSIC_MANIFEST := "res://assets/audio/music.json"
const MUSIC_DIR := "res://assets/audio/music/"

var shift_time := 0.0
var phase_index := 0
var run_seed := 0

var _ended := false
var _belts: Dictionary = {}
var _spawner: Node
var _hud: Control
var _end_label: Label
var _ui_layer: CanvasLayer
var _entities: Node2D
var _items: Node2D
var _environment: Node2D
var _stems: Array = []


func _ready() -> void:
	run_seed = Settings.db_seed
	GameState.reset(run_seed)
	run_seed = GameState.seed_value
	GameState.shift_ended.connect(_on_shift_ended)

	_build_camera()
	RoomBuilder.build(self)
	_environment = _layer("Environment")
	_items = _layer("Items")
	_items.y_sort_enabled = true
	_items.z_index = 5
	_entities = _layer("Entities")
	_entities.y_sort_enabled = true

	_build_environment()
	_build_player()
	_build_spawner()
	_build_ui()
	_setup_music()
	BeatConductor.start(Config.PHASE_BPM[0])
	_apply_phase(0, true)
	print(
		(
			"LEVEL_READY seed=%d phase=%d belts=%d player=%s spawner=%s"
			% [
				run_seed,
				phase_index,
				_belts.size(),
				str(_entities.get_child_count() > 0),
				str(_spawner != null),
			]
		)
	)


func _process(delta: float) -> void:
	if _ended:
		return
	shift_time += delta
	if _hud != null:
		_hud.set_shift_time(shift_time)
	var next_phase := Config.phase_index_at(shift_time)
	if next_phase != phase_index:
		_apply_phase(next_phase, false)
	if shift_time >= Config.SHIFT_DURATION_S:
		_finish(GameState.stability > 0.0, "shift_complete")


func _unhandled_input(event: InputEvent) -> void:
	if _ended and event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()


func _layer(node_name: String) -> Node2D:
	var node := Node2D.new()
	node.name = node_name
	add_child(node)
	return node


func _build_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = Vector2(640, 360)
	camera.enabled = true
	add_child(camera)


func _build_environment() -> void:
	var layout := RoomBuilder.layout()
	for belt in layout.get("belts", []):
		var node := _spawn_area(BELT_SCENE, belt)
		if node == null:
			continue
		var belt_id := StringName(belt.get("id", ""))
		node.name = String(belt_id).to_pascal_case()
		node.set("belt_id", belt_id)
		var flow: Array = belt.get("flow", [1, 0])
		node.set("flow_direction", Vector2(float(flow[0]), float(flow[1])))
		node.set("active", false)
		node.z_index = -5
		_environment.add_child(node)
		_belts[belt_id] = node
	for shredder in layout.get("shredders", []):
		var node := _spawn_area(SHREDDER_SCENE, shredder)
		if node == null:
			continue
		node.name = String(StringName(shredder.get("id", ""))).to_pascal_case()
		node.z_index = 6
		_environment.add_child(node)


## Instantiates an Area2D scene centred on a layout rect and sizes its rectangle shape.
func _spawn_area(scene_path: String, entry: Dictionary) -> Node:
	if not ResourceLoader.exists(scene_path):
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Area2D
	var rect := RoomBuilder.rect_world(entry)
	node.position = rect.get_center()
	for child in node.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var shape := child.shape.duplicate() as RectangleShape2D
			shape.size = rect.size
			child.shape = shape
			child.position = Vector2.ZERO
	return node


func _build_player() -> void:
	if not ResourceLoader.exists(Config.SCENE_PLAYER):
		return
	var packed := load(Config.SCENE_PLAYER) as PackedScene
	if packed == null:
		return
	var player := packed.instantiate() as Node2D
	player.position = RoomBuilder.player_spawn()
	_entities.add_child(player)


func _build_spawner() -> void:
	if not ResourceLoader.exists(SPAWN_DIRECTOR_SCRIPT):
		return
	var script := load(SPAWN_DIRECTOR_SCRIPT) as Script
	if script == null:
		return
	var node := Node.new()
	node.name = "SpawnDirector"
	node.set_script(script)
	if ResourceLoader.exists(Config.SCENE_LAUNDRY_ITEM):
		node.set("item_scene", load(Config.SCENE_LAUNDRY_ITEM))
	node.set("items_parent_path", NodePath("../Items"))
	add_child(node)
	_spawner = node
	if node.has_method("start"):
		node.call("start", run_seed)


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	_ui_layer.layer = 10
	add_child(_ui_layer)
	if ResourceLoader.exists(HUD_SCENE):
		var hud_packed := load(HUD_SCENE) as PackedScene
		_hud = hud_packed.instantiate() as Control
		_ui_layer.add_child(_hud)
	if ResourceLoader.exists(DEBUG_OVERLAY_SCENE):
		var overlay_packed := load(DEBUG_OVERLAY_SCENE) as PackedScene
		if overlay_packed != null:
			_ui_layer.add_child(overlay_packed.instantiate())
	_end_label = Label.new()
	_end_label.name = "EndLabel"
	_end_label.visible = false
	_end_label.position = Vector2(0, 300)
	_end_label.size = Vector2(1280, 120)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_label.add_theme_font_override("font", Fonts.pixel_font())
	_end_label.add_theme_font_size_override("font_size", 28)
	_end_label.add_theme_color_override("font_color", Palette.METAL_4)
	_end_label.add_theme_color_override("font_shadow_color", Palette.SPACE_VOID)
	_end_label.add_theme_constant_override("shadow_offset_x", 2)
	_end_label.add_theme_constant_override("shadow_offset_y", 2)
	_ui_layer.add_child(_end_label)


func _apply_phase(index: int, initial: bool) -> void:
	phase_index = clampi(index, 0, Config.PHASE_BPM.size() - 1)
	GameState.set_phase(phase_index)
	if not initial:
		BeatConductor.set_bpm(Config.PHASE_BPM[phase_index])
	_activate_belts(phase_index)
	if _hud != null:
		_hud.set_phase(phase_index, Config.PHASE_BPM[phase_index])
	if _spawner != null and _spawner.has_method("on_phase_changed"):
		_spawner.call("on_phase_changed", phase_index)
	_apply_stem(phase_index)
	print(
		(
			"PHASE %d clock=%s bpm=%d"
			% [phase_index + 1, Config.clock_string(shift_time), Config.PHASE_BPM[phase_index]]
		)
	)


func _activate_belts(index: int) -> void:
	var layout := RoomBuilder.layout()
	for belt in layout.get("belts", []):
		var belt_id := StringName(belt.get("id", ""))
		if not _belts.has(belt_id):
			continue
		var node: Node = _belts[belt_id]
		var active := (belt.get("active_phases", []) as Array).has(index)
		if node.has_method("set_active"):
			node.call("set_active", active)
		else:
			node.set("active", active)


func _setup_music() -> void:
	if not FileAccess.file_exists(MUSIC_MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_MANIFEST))
	if not (parsed is Dictionary):
		return
	_stems = (parsed as Dictionary).get("stems", [])
	if not _stems.is_empty():
		_apply_stem(0)


func _apply_stem(index: int) -> void:
	if index < 0 or index >= _stems.size():
		return
	if not BeatConductor.has_method("set_stream"):
		return
	var stem: Dictionary = _stems[index]
	var path := MUSIC_DIR + String(stem.get("file", ""))
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	BeatConductor.set_stream(stream, float(stem.get("first_beat_offset_s", 0.0)))


func _finish(victory: bool, reason: String) -> void:
	if _ended:
		return
	_ended = true
	BeatConductor.stop()
	if _spawner != null and _spawner.has_method("stop"):
		_spawner.call("stop")
	GameState.end_shift(victory, reason)
	var summary := "TURNO COMPLETADO" if victory else "TURNO FALLIDO"
	if not victory:
		summary = "DESGARRO UNIVERSAL"
	var stats := (
		"\n%s\nlavadas %d · precisión %d%% · combo máx ×%d · puntos %d\nsemilla %d · R para reiniciar"
		% [
			summary,
			GameState.washed_count,
			int(round(GameState.accuracy() * 100.0)),
			GameState.max_combo,
			GameState.score,
			run_seed,
		]
	)
	_end_label.text = stats
	_end_label.visible = true


func _on_shift_ended(result: Dictionary) -> void:
	if _end_label == null:
		return
	_end_label.visible = true
	if _end_label.text == "":
		_end_label.text = "FIN DEL TURNO\nsemilla %d" % int(result.get("seed", 0))


func get_shift_time() -> float:
	return shift_time


func get_phase_index() -> int:
	return phase_index


func get_seed() -> int:
	return run_seed

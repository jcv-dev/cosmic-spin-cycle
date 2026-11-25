extends Node2D
## Main level assembly and the shift spine (M0–M6).
##
## Builds the static room, environment, washers/chute, player, spawner and UI from the
## frozen contracts and drives the 480 s clock + phase changes. Every optional system is
## loaded behind a `ResourceLoader.exists()` guard so the level always boots, even while a
## workstream is mid-flight.
##
## Screen flow is owned by `App.gd`; this node never changes scenes. It announces the end
## of a shift through `shift_finished` and the tutorial through `tutorial_completed`.

signal shift_finished(result: Dictionary)
signal tutorial_completed

const HUD_SCENE := "res://scenes/ui/HUD.tscn"
const DEBUG_OVERLAY_SCENE := "res://scenes/ui/DebugOverlay.tscn"
const BELT_SCENE := "res://scenes/environment/ConveyorBelt.tscn"
const SHREDDER_SCENE := "res://scenes/environment/Shredder.tscn"
const WASHER_SCENE := "res://scenes/entities/CosmicWasher.tscn"
const CHUTE_SCENE := "res://scenes/environment/DeliveryChute.tscn"
const SPAWN_DIRECTOR_SCRIPT := "res://scripts/components/SpawnDirector.gd"
const WASHER_ASSIGNMENTS := "res://scripts/logic/WasherAssignments.gd"
const MUSIC_MANIFEST := "res://assets/audio/music.json"
const MUSIC_DIR := "res://assets/audio/music/"
const REQUIREMENT_FALLBACK := {
	&"washer_nw": &"red",
	&"washer_ne": &"blue",
	&"washer_sw": &"solid",
	&"washer_se": &"spotted",
}
const LOCKED_IN_PHASE_ONE: Array[StringName] = [&"washer_sw", &"washer_se"]

## "shift" runs the 480 s clock and the seeded spawner; "tutorial" runs the same systems
## with scripted items and no clock end (docs/UX_BIBLE.md §7).
@export var mode: StringName = &"shift"
@export var clock_running := true
@export var hud_enabled := true

var shift_time := 0.0
var phase_index := 0
var run_seed := 0

var _ended := false
var _belts: Dictionary = {}
var _washers: Dictionary = {}
var _spawner: Node
var _chute: Node
var _player: Node
var _camera: Camera2D
var _hud: Control
var _ui_layer: CanvasLayer
var _entities: Node2D
var _items: Node2D
var _environment: Node2D
var _stems: Array = []
var _spawn_turn := 0
var _warning_sfx: AudioStreamPlayer
var _ready_done := false
var _pending_warp := -1.0
var _starter_spawned := false
var _finished_emitted := false
var _last_stability_band := -1


func _ready() -> void:
	run_seed = Settings.db_seed
	if mode == &"tutorial":
		run_seed = Config.TUTORIAL_SEED
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
	_build_washers()
	_build_chute()
	_build_player()
	_build_spawner()
	_build_ui()
	_build_warning_audio()
	_setup_music()
	BeatConductor.beat_hit.connect(_on_beat)
	BeatConductor.start(Config.PHASE_BPM[0])
	_apply_phase(0, true)
	if _hud != null and _hud.has_method("set_tutorial_mode"):
		_hud.call("set_tutorial_mode", mode == &"tutorial")
	_ready_done = true
	if _pending_warp >= 0.0:
		var pending := _pending_warp
		_pending_warp = -1.0
		warp_to(pending)
	print(
		(
			"LEVEL_READY seed=%d phase=%d belts=%d player=%s spawner=%s washers=%d chute=%s mode=%s"
			% [
				run_seed,
				phase_index,
				_belts.size(),
				str(_player != null),
				str(_spawner != null),
				_washers.size(),
				str(_chute != null),
				mode,
			]
		)
	)


func _exit_tree() -> void:
	# The level owns the music it attached to the autoload; don't leak it into tests or a
	# subsequent shift/reload.
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)


func _process(delta: float) -> void:
	if _ended:
		return
	if clock_running:
		shift_time += delta
	if _hud != null:
		_hud.set_shift_time(shift_time)
	if clock_running and mode != &"tutorial":
		var next_phase := Config.phase_index_at(shift_time)
		if next_phase != phase_index:
			_apply_phase(next_phase, false)
		if shift_time >= Config.SHIFT_DURATION_S:
			_finish(GameState.stability > 0.0, "shift_complete")
	if _spawner != null and _spawner.has_method("advance_to"):
		_spawner.call("advance_to", shift_time)
	if mode == &"shift":
		_maybe_spawn_starter_item()
	_refresh_low_stability()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not (event is InputEventKey) or not event.pressed:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_F1:
		warp_to(minf(shift_time + 60.0, Config.SHIFT_DURATION_S))
	elif key == KEY_F2:
		GameState.add_stability(25.0, "cheat")
	elif key == KEY_F3:
		GameState.add_score(500)
	elif key == KEY_F4 and _player != null:
		spawn_item(
			Config.STARTER_ITEM_ID,
			Config.STARTER_ITEM_COLOR,
			Config.STARTER_ITEM_PATTERN,
			(_player as Node2D).global_position + Vector2(0, -96),
			false
		)


func _layer(node_name: String) -> Node2D:
	var node := Node2D.new()
	node.name = node_name
	add_child(node)
	return node


# --- Camera -----------------------------------------------------------------


func _build_camera() -> void:
	if ResourceLoader.exists("res://scripts/main/CameraRig.gd"):
		var rig_script := load("res://scripts/main/CameraRig.gd") as Script
		var rig := rig_script.new() as Camera2D
		if rig != null:
			rig.name = "Camera2D"
			rig.position = Vector2(640, 360)
			add_child(rig)
			_camera = rig
			return
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = Vector2(640, 360)
	camera.enabled = true
	add_child(camera)
	_camera = camera


# --- Environment ------------------------------------------------------------


func _build_environment() -> void:
	var layout := RoomBuilder.layout()
	for belt in layout.get("belts", []):
		var node := _instantiate_scene(BELT_SCENE)
		if node == null:
			continue
		var belt_id := StringName(belt.get("id", ""))
		node.name = String(belt_id).to_pascal_case()
		var flow: Array = belt.get("flow", [1, 0])
		var flow_vector := Vector2(float(flow[0]), float(flow[1]))
		if node.has_method("configure"):
			node.call("configure", belt_id, RoomBuilder.art_rect(belt), flow_vector)
		else:
			_configure_area_fallback(node, RoomBuilder.rect_world(belt))
			node.set("belt_id", belt_id)
			node.set("flow_direction", flow_vector)
		node.set("active", false)
		node.z_index = -5
		_environment.add_child(node)
		if node.has_signal("reverse_warning"):
			node.connect("reverse_warning", _on_belt_warning)
		_belts[belt_id] = node
	for shredder in layout.get("shredders", []):
		var node := _instantiate_scene(SHREDDER_SCENE)
		if node == null:
			continue
		var shredder_id := StringName(shredder.get("id", ""))
		node.name = String(shredder_id).to_pascal_case()
		if node.has_method("configure"):
			node.call("configure", shredder_id, RoomBuilder.art_rect(shredder))
		else:
			_configure_area_fallback(node, RoomBuilder.rect_world(shredder))
		node.z_index = 6
		_environment.add_child(node)


## Washers sit in the four inner corners (layout.json). They live in the y-sorted Entities
## layer so Pip can walk behind a machine without breaking depth.
func _build_washers() -> void:
	if not ResourceLoader.exists(WASHER_SCENE):
		return
	var packed := load(WASHER_SCENE) as PackedScene
	if packed == null:
		return
	var layout := RoomBuilder.layout()
	for entry in layout.get("washers", []):
		var node := packed.instantiate()
		if node == null:
			continue
		var washer_id := StringName(entry.get("id", ""))
		node.name = String(washer_id).to_pascal_case()
		var mouth: Array = entry.get("mouth", [])
		var mouth_point := Vector2(
			float(entry.get("x", 0)) + float(entry.get("w", 48)) * 0.5,
			float(entry.get("y", 0)) + float(entry.get("h", 48))
		)
		if mouth.size() == 2:
			mouth_point = Vector2(float(mouth[0]), float(mouth[1]))
		if node.has_method("configure"):
			node.call(
				"configure",
				washer_id,
				RoomBuilder.art_rect(entry),
				mouth_point,
				_requirement_for(washer_id)
			)
		if node.has_method("set_locked"):
			node.call("set_locked", _is_locked(washer_id))
		if node.has_signal("state_changed"):
			node.connect("state_changed", _on_washer_state_changed)
		_entities.add_child(node)
		_washers[washer_id] = node


func _build_chute() -> void:
	var node := _instantiate_scene(CHUTE_SCENE)
	if node == null:
		return
	var layout := RoomBuilder.layout()
	var entry: Dictionary = layout.get("chute", {})
	node.name = "DeliveryChute"
	if node.has_method("configure"):
		node.call(
			"configure",
			RoomBuilder.art_rect(entry),
			RoomBuilder.point_world(entry.get("center", [160, 90]))
		)
	if node.has_signal("delivered"):
		node.connect("delivered", _on_chute_delivered)
	if node.has_signal("dirty_rejected"):
		node.connect("dirty_rejected", _on_chute_dirty)
	_entities.add_child(node)
	_chute = node


func _instantiate_scene(scene_path: String) -> Node:
	if not ResourceLoader.exists(scene_path):
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate()


## Fallback for a scene that does not implement `configure()`: centre it on the rect and
## resize its first rectangle or circle shape.
func _configure_area_fallback(node: Node, rect: Rect2) -> void:
	if node is Node2D:
		(node as Node2D).position = rect.get_center()
	if not (node is Area2D):
		return
	for child in node.get_children():
		if not (child is CollisionShape2D):
			continue
		var shape := (child as CollisionShape2D).shape
		if shape is RectangleShape2D:
			var box := shape.duplicate() as RectangleShape2D
			box.size = rect.size
			(child as CollisionShape2D).shape = box
			(child as CollisionShape2D).position = Vector2.ZERO
		elif shape is CircleShape2D:
			var circle := shape.duplicate() as CircleShape2D
			circle.radius = minf(rect.size.x, rect.size.y) * 0.5
			(child as CollisionShape2D).shape = circle
			(child as CollisionShape2D).position = Vector2.ZERO


# --- Player -----------------------------------------------------------------


func _build_player() -> void:
	if not ResourceLoader.exists(Config.SCENE_PLAYER):
		return
	var packed := load(Config.SCENE_PLAYER) as PackedScene
	if packed == null:
		return
	var player := packed.instantiate() as Node2D
	player.position = RoomBuilder.player_spawn()
	_entities.add_child(player)
	_player = player
	if _camera != null and _camera.has_method("setup"):
		_camera.call("setup", player)
	_wire_player()


func _wire_player() -> void:
	if _player == null:
		return
	if _player.has_signal("grabbed"):
		_player.connect("grabbed", _on_player_grabbed)
	if _player.has_signal("thrown"):
		_player.connect("thrown", _on_player_thrown)
	if _player.has_signal("struck"):
		_player.connect("struck", _on_player_struck)
	if _player.has_signal("aim_changed"):
		_player.connect("aim_changed", _on_player_aim_changed)


func _on_player_grabbed(_item: Node) -> void:
	_update_carry_hints()
	_set_objective_for_carry()


func _on_player_thrown(_item: Node, grade: int) -> void:
	_update_carry_hints()
	_show_grade(grade)
	_set_objective_for_carry()


func _on_player_struck(washer: Node, grade: int) -> void:
	_show_grade(grade)
	if washer != null and washer.has_method("strike"):
		var mattered := bool(washer.call("strike", grade))
		if mattered:
			Juice.shake(0.18)
			Juice.hitstop(0.04)
			GameState.emit_feedback(tr("ESTABILIZADA"), &"success")


func _on_player_aim_changed(_direction: Vector2) -> void:
	pass


func _update_carry_hints() -> void:
	var item: Node = _player.get("held_item") if _player != null else null
	for washer_id in _washers:
		var washer: Node = _washers[washer_id]
		if washer.has_method("set_carry_hint"):
			washer.call("set_carry_hint", item)
	if _chute != null and _chute.has_method("set_carry_hint"):
		var clean := item != null and bool(item.get("is_clean"))
		_chute.call("set_carry_hint", item if clean else null)


func _set_objective_for_carry() -> void:
	if _hud == null or not _hud.has_method("set_objective"):
		return
	var item: Node = _player.get("held_item") if _player != null else null
	if item == null:
		_hud.call("set_objective", tr("LAVA Y ENTREGA HASTA LAS 06:00"))
		return
	if bool(item.get("is_clean")):
		_hud.call("set_objective", tr("LLEVA LA PIEZA LIMPIA AL DUCTO"))
		return
	var color := StringName(item.get("color"))
	var pattern := StringName(item.get("pattern"))
	_hud.call(
		"set_objective",
		"%s %s · %s" % [tr("LAVADORA"), _color_label(color), _pattern_label(pattern)]
	)


func _color_label(color: StringName) -> String:
	match color:
		&"red":
			return tr("ROJA")
		&"blue":
			return tr("AZUL")
		&"yellow":
			return tr("AMARILLA")
		_:
			return tr("CUALQUIERA")


func _pattern_label(pattern: StringName) -> String:
	match pattern:
		&"solid":
			return tr("LISA")
		&"ringed":
			return tr("ANILLADA")
		&"spotted":
			return tr("MOTEADA")
		_:
			return tr("CUALQUIERA")


# --- Washer/chute events ----------------------------------------------------


func _on_washer_state_changed(_old_state: int, new_state: int) -> void:
	# 4 == DONE, 2 == TURBULENT, 4/BROKEN are the states the HUD cares about; the washer owns
	# its own audio/particles, so this only adds camera-level punctuation.
	match new_state:
		2:
			Juice.shake(0.22)
		3:
			Juice.shake(0.5)
			Juice.hitstop(0.08)
		_:
			pass


func _on_chute_delivered(_item: Node, points: int) -> void:
	Juice.punch_zoom(0.012, 0.10)
	if _hud != null and _hud.has_method("flash_reward"):
		_hud.call("flash_reward", points)
	GameState.emit_feedback("+%d" % points, &"success")


func _on_chute_dirty(_item: Node) -> void:
	GameState.emit_feedback(tr("LAVA PRIMERO"), &"danger")


func _show_grade(grade: int) -> void:
	if _hud != null and _hud.has_method("show_grade"):
		_hud.call("show_grade", grade)
	if grade == RhythmEvaluator.Grade.PERFECT:
		Juice.shake(0.10)
		Juice.punch_zoom(0.01, 0.08)
	elif grade == RhythmEvaluator.Grade.MISS:
		Juice.shake(0.06)


# --- Spawning ---------------------------------------------------------------


func _build_spawner() -> void:
	if mode == &"tutorial" or not ResourceLoader.exists(SPAWN_DIRECTOR_SCRIPT):
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
	node.set("position_resolver", Callable(self, "_resolve_spawn_position"))
	add_child(node)
	_spawner = node
	if node.has_method("start"):
		node.call("start", run_seed)


## First 20 s onboarding (docs/UX_BIBLE.md §2): one dirty item on the floor, close enough
## that the first useful action is a grab, not a walk across the room.
func _maybe_spawn_starter_item() -> void:
	if _starter_spawned or shift_time < Config.STARTER_ITEM_AT_S:
		return
	if _player == null:
		return
	_starter_spawned = true
	var position := (_player as Node2D).global_position + Vector2(0, -96)
	var item := spawn_item(
		Config.STARTER_ITEM_ID,
		Config.STARTER_ITEM_COLOR,
		Config.STARTER_ITEM_PATTERN,
		position,
		false
	)
	if item == null:
		return
	GameState.emit_feedback(tr("AGARRA LA PIEZA"), &"info")


## Public factory used by the tutorial, cheats and QA scripts.
func spawn_item(
	item_id: StringName,
	color: StringName,
	pattern: StringName,
	position: Vector2,
	clean: bool = false
) -> Node:
	if not ResourceLoader.exists(Config.SCENE_LAUNDRY_ITEM):
		return null
	var packed := load(Config.SCENE_LAUNDRY_ITEM) as PackedScene
	if packed == null:
		return null
	var item := packed.instantiate()
	if item == null:
		return null
	if item.has_method("setup"):
		item.call("setup", item_id, color, pattern, clean)
	item.position = position
	_items.add_child(item)
	return item


func clear_items() -> void:
	for child in _items.get_children():
		child.queue_free()


## Deterministic belt choice for the current phase: cycles the belts active in that phase.
func _resolve_spawn_position(event: Dictionary, _phase: PhaseData) -> Vector2:
	var layout := RoomBuilder.layout()
	var phase := int(event.get("phase", 0))
	var candidates: Array = []
	for belt in layout.get("belts", []):
		if _belt_active_in_phase(belt, phase):
			candidates.append(belt)
	if candidates.is_empty():
		candidates = layout.get("belts", [])
	if candidates.is_empty():
		return Vector2(336, 72)
	var entry: Dictionary = candidates[_spawn_turn % candidates.size()]
	_spawn_turn += 1
	return RoomBuilder.point_world(entry.get("spawn", [84, 18]))


## JSON numbers arrive as floats; compare phase ids as ints.
func _belt_active_in_phase(belt: Dictionary, index: int) -> bool:
	for phase_value in belt.get("active_phases", []):
		if int(phase_value) == index:
			return true
	return false


# --- UI ---------------------------------------------------------------------


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	_ui_layer.layer = 10
	add_child(_ui_layer)
	if hud_enabled and ResourceLoader.exists(HUD_SCENE):
		var hud_packed := load(HUD_SCENE) as PackedScene
		_hud = hud_packed.instantiate() as Control
		_ui_layer.add_child(_hud)
	if ResourceLoader.exists(DEBUG_OVERLAY_SCENE):
		var overlay_packed := load(DEBUG_OVERLAY_SCENE) as PackedScene
		if overlay_packed != null:
			_ui_layer.add_child(overlay_packed.instantiate())


func _refresh_low_stability() -> void:
	var band := 0
	if GameState.stability < 25.0:
		band = 2
	elif GameState.stability < 35.0:
		band = 1
	if band == _last_stability_band:
		return
	_last_stability_band = band
	if band >= 1 and _hud != null and _hud.has_method("set_danger"):
		_hud.call("set_danger", band >= 2)


# --- Phase + clock ----------------------------------------------------------


func _apply_phase(index: int, initial: bool) -> void:
	phase_index = clampi(index, 0, Config.PHASE_BPM.size() - 1)
	GameState.set_phase(phase_index)
	if not initial and clock_running:
		BeatConductor.set_bpm(Config.PHASE_BPM[phase_index])
	_activate_belts(phase_index)
	_apply_washer_requirements()
	if _hud != null:
		_hud.set_phase(phase_index, Config.PHASE_BPM[phase_index])
	if _spawner != null and _spawner.has_method("on_phase_changed"):
		_spawner.call("on_phase_changed", phase_index)
	_apply_stem(phase_index)
	if _camera != null and _camera.has_method("set_phase_colors"):
		_camera.call("set_phase_colors", _phase_requirements())
	print(
		(
			"PHASE %d clock=%s bpm=%d"
			% [phase_index + 1, Config.clock_string(shift_time), Config.PHASE_BPM[phase_index]]
		)
	)


func _phase_requirements() -> Array:
	var colors: Array = []
	for washer_id in _washers:
		var requirement := _requirement_for(washer_id)
		colors.append(requirement)
	return colors


func _apply_washer_requirements() -> void:
	for washer_id in _washers:
		var washer: Node = _washers[washer_id]
		if washer.has_method("set_requirement"):
			washer.call("set_requirement", _requirement_for(washer_id))
		if washer.has_method("set_locked"):
			washer.call("set_locked", _is_locked(washer_id))


func _requirement_for(washer_id: StringName) -> StringName:
	if ResourceLoader.exists(WASHER_ASSIGNMENTS):
		var script := load(WASHER_ASSIGNMENTS) as Script
		if script != null and script.has_method("requirement_for"):
			return StringName(script.call("requirement_for", phase_index, washer_id))
	return StringName(REQUIREMENT_FALLBACK.get(washer_id, &"red"))


func _is_locked(washer_id: StringName) -> bool:
	if ResourceLoader.exists(WASHER_ASSIGNMENTS):
		var script := load(WASHER_ASSIGNMENTS) as Script
		if script != null and script.has_method("is_locked"):
			return bool(script.call("is_locked", phase_index, washer_id))
	return phase_index == 0 and LOCKED_IN_PHASE_ONE.has(washer_id)


func _activate_belts(index: int) -> void:
	var layout := RoomBuilder.layout()
	for belt in layout.get("belts", []):
		var belt_id := StringName(belt.get("id", ""))
		if not _belts.has(belt_id):
			continue
		var node: Node = _belts[belt_id]
		var active := _belt_active_in_phase(belt, index)
		var flow: Array = belt.get("flow", [1, 0])
		var base_flow := Vector2(float(flow[0]), float(flow[1]))
		if node.has_method("set_flow_direction"):
			node.call("set_flow_direction", base_flow)
		else:
			node.set("flow_direction", base_flow)
		if node.has_method("set_active"):
			node.call("set_active", active)
		else:
			node.set("active", active)


func _build_warning_audio() -> void:
	var path := "res://assets/audio/sfx/turbulent_alarm.ogg"
	if not ResourceLoader.exists(path):
		return
	_warning_sfx = AudioStreamPlayer.new()
	_warning_sfx.name = "WarningSfx"
	_warning_sfx.stream = load(path) as AudioStream
	_warning_sfx.volume_db = -7.0
	if AudioServer.get_bus_index("SFX") >= 0:
		_warning_sfx.bus = "SFX"
	add_child(_warning_sfx)


func _on_belt_warning(beats_left: int) -> void:
	if _warning_sfx == null or beats_left != Config.BELT_REVERSE_WARNING_BEATS:
		return
	_warning_sfx.play()


func _on_beat(beat: int) -> void:
	if _ended:
		return
	var measure := int(beat / Config.BEATS_PER_MEASURE)
	for belt_id in _belts:
		var node: Node = _belts[belt_id]
		if node == null or not is_instance_valid(node):
			continue
		var active := bool(node.get("active")) if node.get("active") != null else false
		if not active:
			continue
		if node.has_method("on_beat"):
			node.call("on_beat", beat, measure, phase_index)


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
	GameState.end_shift(victory, reason)
	_on_shift_ended(GameState.get_end_result())


func _on_shift_ended(result: Dictionary) -> void:
	_ended = true
	BeatConductor.stop()
	if _spawner != null and _spawner.has_method("stop"):
		_spawner.call("stop")
	if _finished_emitted:
		return
	_finished_emitted = true
	shift_finished.emit(result)


# --- Public API -------------------------------------------------------------


## Debug/QA hook: jump the shift clock and immediately consume spawns/phase changes.
func set_shift_time(t: float) -> void:
	shift_time = clampf(t, 0.0, Config.SHIFT_DURATION_S)
	_process(0.0)


## QA/cheat warp: jump to `t` without replaying every past spawn, then continue live.
## Used by screenshots and the F1 debug cheat; tests use set_shift_time for replay.
func warp_to(t: float) -> void:
	if not _ready_done:
		_pending_warp = t
		return
	shift_time = clampf(t, 0.0, Config.SHIFT_DURATION_S)
	_apply_phase(Config.phase_index_at(shift_time), false)
	if _spawner != null and _spawner.has_method("seek"):
		_spawner.call("seek", shift_time)
		print("WARP seek items=%d time=%s" % [_items.get_child_count(), str(_spawner.get("time"))])
	if _hud != null:
		_hud.set_shift_time(shift_time)
	_starter_spawned = true


func is_ended() -> bool:
	return _ended


func get_shift_time() -> float:
	return shift_time


func get_phase_index() -> int:
	return phase_index


func get_seed() -> int:
	return run_seed


func get_mode() -> StringName:
	return mode


func is_tutorial() -> bool:
	return mode == &"tutorial"


func get_player() -> Node:
	return _player


func get_washers() -> Array:
	return _washers.values()


func get_washer(id: StringName) -> Node:
	return _washers.get(id, null)


func get_chute() -> Node:
	return _chute


func get_hud() -> Control:
	return _hud


func get_camera() -> Camera2D:
	return _camera


func get_items_layer() -> Node2D:
	return _items


## Ends the tutorial from the director (kept here so the tutorial never needs to know how
## persistence works).
func complete_tutorial() -> void:
	Settings.mark_tutorial_completed()
	tutorial_completed.emit()

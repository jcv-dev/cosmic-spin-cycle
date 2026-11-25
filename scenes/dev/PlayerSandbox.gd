extends Node2D
## M2 dev sandbox: a playable 1280x720 room with one of every item, a HUD and hotkeys.
##
## Not part of the shipped game loop. It exists so player/item physics can be judged by
## hand (and screenshotted) before belts, washers and the shift flow land in M3-M5.
## Room geometry comes from `data/layout.json` so the greybox matches the frozen layout.

const LAYOUT_PATH := "res://data/layout.json"
const HUD_REFRESH_S := 0.1
const SPAWN_MARGIN := 70.0
const DEFAULT_SEED := 4242

const COLOR_VOID := Color("#0B0C10")
const COLOR_FLOOR := Color("#14172A")
const COLOR_GRID := Color("#1F2340")
const COLOR_GRID_MAJOR := Color("#2E3460")
const COLOR_WALL := Color("#2E3460")
const COLOR_WALL_TRIM := Color("#4A5278")
const COLOR_METAL := Color("#6B7599")
const COLOR_TEXT := Color("#CDD3E8")
const COLOR_CYAN := Color("#19E3D1")
const COLOR_TEAL := Color("#0B7F86")
const COLOR_HAZARD := Color("#FF7A1A")
const COLOR_PERFECT := Color("#E040FB")

var _layout: Dictionary = {}
var _room_inner := Rect2()
var _wall_thickness := 0.0
var _player: Player = null
var _items_root: Node2D = null
var _info: Label = null
var _spawn_index := 0
var _hud_timer := 0.0
var _fps := 0


func _ready() -> void:
	_load_layout()
	var canvas := Vector2(Config.ART_CANVAS) * float(Config.ART_SCALE)
	_room_inner = Rect2(
		Vector2(_wall_thickness, _wall_thickness),
		canvas - Vector2(_wall_thickness, _wall_thickness) * 2.0
	)
	_items_root = $Items as Node2D
	_player = $Player as Player
	_player.global_position = _world(_player_spawn())
	_build_walls()
	GameState.reset(DEFAULT_SEED)
	BeatConductor.start(Config.PHASE_BPM[0])
	_info = $HUD/Info as Label
	_reset_scene()
	queue_redraw()


func _process(delta: float) -> void:
	if _player == null:
		return
	_fps = Engine.get_frames_per_second()
	_hud_timer += delta
	if _hud_timer >= HUD_REFRESH_S:
		_hud_timer = 0.0
		_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.physical_keycode:
		KEY_1:
			_spawn_from_key(0)
		KEY_2:
			_spawn_from_key(1)
		KEY_3:
			_spawn_from_key(2)
		KEY_4:
			_spawn_from_key(3)
		KEY_5:
			_spawn_from_key(4)
		KEY_R:
			_reset_scene()


func _draw() -> void:
	var canvas := Vector2(Config.ART_CANVAS) * float(Config.ART_SCALE)
	draw_rect(Rect2(Vector2.ZERO, canvas), COLOR_VOID)
	_room_inner = Rect2(
		Vector2(_wall_thickness, _wall_thickness),
		canvas - Vector2(_wall_thickness, _wall_thickness) * 2.0
	)
	draw_rect(_room_inner, COLOR_FLOOR)
	_draw_grid(_room_inner)
	_draw_walls(canvas)
	_draw_washers()
	_draw_chute()
	_draw_spawn_pad()


func _draw_grid(area: Rect2) -> void:
	var step := 64.0
	var x := area.position.x
	var index := 0
	while x <= area.end.x:
		var color := COLOR_GRID_MAJOR if index % 4 == 0 else COLOR_GRID
		draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), color, 1.0)
		x += step
		index += 1
	var y := area.position.y
	index = 0
	while y <= area.end.y:
		var color := COLOR_GRID_MAJOR if index % 4 == 0 else COLOR_GRID
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), color, 1.0)
		y += step
		index += 1


func _draw_walls(canvas: Vector2) -> void:
	var thickness := _wall_thickness
	draw_rect(Rect2(0.0, 0.0, canvas.x, thickness), COLOR_WALL)
	draw_rect(Rect2(0.0, canvas.y - thickness, canvas.x, thickness), COLOR_WALL)
	draw_rect(Rect2(0.0, 0.0, thickness, canvas.y), COLOR_WALL)
	draw_rect(Rect2(canvas.x - thickness, 0.0, thickness, canvas.y), COLOR_WALL)
	var inner := Rect2(Vector2(thickness, thickness), canvas - Vector2(thickness, thickness) * 2.0)
	draw_rect(inner, COLOR_WALL_TRIM, false, 2.0)
	draw_rect(inner.grow(6.0), COLOR_VOID, false, 4.0)


func _draw_washers() -> void:
	for washer in _layout.get("washers", []):
		var rect := _world_rect(washer)
		draw_rect(rect, COLOR_GRID)
		draw_rect(rect, COLOR_WALL_TRIM, false, 2.0)
		var center := rect.get_center()
		draw_circle(center, rect.size.x * 0.28, COLOR_VOID)
		draw_arc(center, rect.size.x * 0.28, 0.0, TAU, 28, COLOR_METAL, 2.0)
		draw_arc(center, rect.size.x * 0.16, 0.0, TAU, 20, COLOR_HAZARD, 2.0)
		draw_rect(
			Rect2(
				rect.position + Vector2(10.0, rect.size.y - 14.0), Vector2(rect.size.x - 20.0, 5.0)
			),
			COLOR_HAZARD
		)


func _draw_chute() -> void:
	var chute: Dictionary = _layout.get("chute", {})
	if chute.is_empty():
		return
	var center := _world(chute.get("center", [160, 90]))
	draw_circle(center, 54.0, COLOR_GRID)
	draw_arc(center, 54.0, 0.0, TAU, 40, COLOR_METAL, 2.0)
	draw_arc(center, 42.0, 0.0, TAU, 36, COLOR_HAZARD, 3.0)
	draw_circle(center, 26.0, COLOR_VOID)
	draw_arc(center, 18.0, 0.0, TAU, 28, COLOR_CYAN, 2.0)


func _draw_spawn_pad() -> void:
	if _player == null:
		return
	var center := _world(_player_spawn())
	draw_arc(center, 34.0, 0.0, TAU, 32, Color(COLOR_CYAN, 0.35), 2.0)
	draw_line(
		center - Vector2(10.0, 0.0), center + Vector2(10.0, 0.0), Color(COLOR_CYAN, 0.35), 2.0
	)
	draw_line(
		center - Vector2(0.0, 10.0), center + Vector2(0.0, 10.0), Color(COLOR_CYAN, 0.35), 2.0
	)


func _build_walls() -> void:
	var canvas := Vector2(Config.ART_CANVAS) * float(Config.ART_SCALE)
	var thickness := _wall_thickness
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	walls.collision_layer = Config.CollisionLayer.WORLD
	walls.collision_mask = 0
	add_child(walls)
	_add_wall(walls, Rect2(0.0, 0.0, canvas.x, thickness))
	_add_wall(walls, Rect2(0.0, canvas.y - thickness, canvas.x, thickness))
	_add_wall(walls, Rect2(0.0, 0.0, thickness, canvas.y))
	_add_wall(walls, Rect2(canvas.x - thickness, 0.0, thickness, canvas.y))


func _add_wall(body: StaticBody2D, rect: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	shape.position = rect.get_center()
	body.add_child(shape)


func _reset_scene() -> void:
	for child in _items_root.get_children():
		child.queue_free()
	_spawn_index = 0
	_player.held_item = null
	_player.velocity = Vector2.ZERO
	_player.global_position = _world(_player_spawn())
	_player.set_aim_direction(Vector2.DOWN)
	_player.clear_aim_override()
	_player.last_grade = -1
	var defaults := [
		[&"rocky", Vector2(480.0, 280.0), &"red", &"solid"],
		[&"sock", Vector2(800.0, 280.0), &"blue", &"ringed"],
		[&"moon", Vector2(480.0, 460.0), &"yellow", &"spotted"],
		[&"gas_giant", Vector2(800.0, 460.0), &"yellow", &"solid"],
		[&"galaxy_core", Vector2(640.0, 230.0), &"red", &"solid"],
	]
	for entry in defaults:
		_spawn_item(entry[0], entry[1], entry[2], entry[3])
	GameState.reset(DEFAULT_SEED)
	_update_hud()


func _spawn_from_key(index: int) -> void:
	if index < 0 or index >= Config.ITEM_IDS.size():
		return
	var position_hint := get_global_mouse_position()
	position_hint.x = clampf(
		position_hint.x, _room_inner.position.x + SPAWN_MARGIN, _room_inner.end.x - SPAWN_MARGIN
	)
	position_hint.y = clampf(
		position_hint.y, _room_inner.position.y + SPAWN_MARGIN, _room_inner.end.y - SPAWN_MARGIN
	)
	var color: StringName = Config.COLORS[_spawn_index % Config.COLORS.size()]
	var pattern: StringName = Config.PATTERNS[(_spawn_index / 3) % Config.PATTERNS.size()]
	_spawn_item(Config.ITEM_IDS[index], position_hint, color, pattern)
	_spawn_index += 1


func _spawn_item(
	item_id: StringName, position_hint: Vector2, item_color: StringName, item_pattern: StringName
) -> LaundryItem:
	var item := (load(Config.SCENE_LAUNDRY_ITEM) as PackedScene).instantiate() as LaundryItem
	item.setup(item_id, item_color, item_pattern, false)
	_items_root.add_child(item)
	item.global_position = position_hint
	return item


func _update_hud() -> void:
	if _info == null:
		return
	var held := "—"
	if _player.held_item != null and is_instance_valid(_player.held_item):
		var item := _player.held_item as LaundryItem
		held = "%s (%s/%s)" % [item.item_id, item.color, item.pattern]
	var grade := "—"
	if _player.last_grade >= 0:
		grade = RhythmEvaluator.grade_name(_player.last_grade)
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var beat_ms := BeatConductor.delta_to_nearest_beat(BeatConductor.get_song_time()) * 1000.0
	_info.text = (
		"COSMIC SPIN CYCLE · M2 SANDBOX\n"
		+ "Held: %s    Last grade: %s    Beat Δt: %.0f ms\n" % [held, grade, beat_ms]
		+ (
			"FPS %d    Physics %.2f ms    Objects %d\n"
			% [_fps, physics_ms, _items_root.get_child_count()]
		)
		+ "1-5 spawn at cursor · R reset · LMB grab/throw · RMB strike · mouse aim"
	)


func _load_layout() -> void:
	var text := FileAccess.get_file_as_string(LAYOUT_PATH)
	var parsed: Variant = JSON.parse_string(text)
	_layout = parsed as Dictionary if parsed is Dictionary else {}
	var room: Dictionary = _layout.get("room", {})
	_wall_thickness = float(room.get("wall", 8)) * float(Config.ART_SCALE)


func _player_spawn() -> Array:
	var spawn: Array = _layout.get("player_spawn", [160, 128])
	return spawn


func _world(art_point: Array) -> Vector2:
	return Vector2(float(art_point[0]), float(art_point[1])) * float(Config.ART_SCALE)


func _world_rect(entry: Dictionary) -> Rect2:
	return Rect2(
		_world([entry.get("x", 0), entry.get("y", 0)]),
		Vector2(float(entry.get("w", 0)), float(entry.get("h", 0))) * float(Config.ART_SCALE)
	)

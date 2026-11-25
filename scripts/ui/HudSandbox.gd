extends Node2D
## Design-time sandbox for the HUD and the world-space layer (docs/HUD.md).
##
## Not shipped: it exists so the diegetic states can be reviewed in one frame without running
## a shift. It fakes exactly the frame the UX bible asks to be legible: Pip carrying a red
## ringed piece, a compatible red washer, an incompatible blue one, a clean chute, stability 22
## and combo ×5 — plus a schematic room so the HUD can be judged against real world clutter.
##
##   godot --path . -s tools/screenshot.gd -- --scene=res://scenes/dev/HudSandbox.tscn \
##         --out=res://docs/media/hud_diegetic.png --frames=90
##   add `--tutorial` (after the `--`) for the tutorial variant.

const HUD_SCENE := "res://scenes/ui/HUD.tscn"
const DIEGETIC_SCENE := "res://scenes/ui/DiegeticLayer.tscn"

const PLAYER_POS := Vector2(640, 392)
const RED_WASHER_POS := Vector2(452, 248)
const BLUE_WASHER_POS := Vector2(884, 248)
const CHUTE_POS := Vector2(640, 548)
const PIP_SHEET := "res://assets/sprites/char_pip.png"
const WASHER_SHEET := "res://assets/sprites/mach_washer.png"
const CHUTE_SHEET := "res://assets/sprites/env_chute.png"
const ROCKY_SHEET := "res://assets/sprites/item_rocky.png"
const HUD_TIME := 270.0
const DEMO_STABILITY := 22.0
const DEMO_COMBO := 5
const DEMO_SCORE := 1240

var _tutorial := false


## One frame of a shipped sheet as a world-space sprite (art px × ART_SCALE).
static func sheet_sprite(
	parent: Node2D, sheet: String, cell: Vector2i, pivot: Vector2, row: int = 0
) -> Sprite2D:
	var sprite := Sprite2D.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load(sheet) as Texture2D
	atlas.region = Rect2(0, float(cell.y) * float(row), float(cell.x), float(cell.y))
	sprite.texture = atlas
	sprite.centered = false
	sprite.scale = Vector2(Config.ART_SCALE, Config.ART_SCALE)
	sprite.offset = -pivot
	parent.add_child(sprite)
	return sprite


class FakePlayer:
	extends Node2D
	var held_item: Node = null
	var aim_direction := Vector2.RIGHT

	func _ready() -> void:
		add_to_group(Config.GROUP_PLAYER)

	func get_aim_direction() -> Vector2:
		return aim_direction

	func get_hold_position() -> Vector2:
		# Mirrors the real Player: hold distance + the item radius (docs/DECISIONS.md D018).
		return global_position + aim_direction * (Config.HOLD_DISTANCE + 8.0 * Config.ART_SCALE)


class FakeWasher:
	extends Node2D
	var requirement: StringName = &"red"
	var state := 0

	func _ready() -> void:
		add_to_group(Config.GROUP_WASHERS)

	func get_requirement() -> StringName:
		return requirement

	func get_state() -> int:
		return state

	func is_locked() -> bool:
		return false

	func get_progress() -> float:
		return 0.0

	func get_mouth_world() -> Vector2:
		return global_position + Vector2(0.0, -24.0)

	func strike(_grade: int) -> void:
		pass


class FakeChute:
	extends Node2D

	func _ready() -> void:
		add_to_group(Config.GROUP_CHUTE)

	func try_deliver(_item: Node) -> bool:
		return true


class FakeItem:
	extends Node2D
	var item_id: StringName = &"rocky"
	var color: StringName = &"red"
	var pattern: StringName = &"ringed"
	var is_held := true
	var is_clean := false
	var data: ItemData = null

	func _ready() -> void:
		add_to_group(Config.GROUP_ITEMS)


## The shipped room plate plus tinted washer pools: the HUD is then judged against the real
## background instead of a flat mock-up.
class FakeRoom:
	extends Node2D
	var pads: Array[Dictionary] = []

	func _ready() -> void:
		var room := Sprite2D.new()
		room.name = "RoomPlate"
		room.texture = load("res://assets/sprites/env_room.png") as Texture2D
		room.centered = false
		room.scale = Vector2(Config.ART_SCALE, Config.ART_SCALE)
		add_child(room)

	func _draw() -> void:
		for pad in pads:
			_draw_pool(pad["center"], pad["ink"])

	## A tinted light pool plus the requirement glyph, so the two machines read as different
	## colours even though the shipped washer art is shared (docs/UX_BIBLE.md §3.5, §6.1).
	func _draw_pool(center: Vector2, ink: Color) -> void:
		var mid := center + Vector2(0, -88)
		draw_circle(mid, 108.0, Color(ink, 0.10))
		draw_circle(mid, 108.0, Color(ink, 0.28), false, 2.0)


func _ready() -> void:
	_tutorial = _wants_tutorial()
	GameState.reset(2026)
	GameState.add_score(DEMO_SCORE)
	GameState.combo = DEMO_COMBO
	GameState.combo_changed.emit(DEMO_COMBO)
	GameState.set_phase(2)
	var room := FakeRoom.new()
	room.name = "Room"
	room.pads = [
		{"center": RED_WASHER_POS, "ink": Palette.RED_3, "requirement": &"red"},
		{"center": BLUE_WASHER_POS, "ink": Palette.BLUE_3, "requirement": &"blue"},
	]
	add_child(room)
	var red_washer := _washer(RED_WASHER_POS, &"red")
	var blue_washer := _washer(BLUE_WASHER_POS, &"blue")
	blue_washer.name = "IncompatibleWasher"
	red_washer.name = "CompatibleWasher"
	var chute := FakeChute.new()
	chute.name = "Chute"
	chute.position = CHUTE_POS
	add_child(chute)
	sheet_sprite(chute, CHUTE_SHEET, Vector2i(32, 32), Vector2(16, 16), 2)
	var player := FakePlayer.new()
	player.name = "Pip"
	player.position = PLAYER_POS
	player.aim_direction = (RED_WASHER_POS - PLAYER_POS).normalized()
	add_child(player)
	sheet_sprite(player, PIP_SHEET, Vector2i(24, 24), Vector2(12, 22))
	var item := FakeItem.new()
	item.name = "HeldItem"
	item.position = player.get_hold_position()
	item.data = _rocky_data()
	add_child(item)
	sheet_sprite(item, ROCKY_SHEET, Vector2i(16, 16), Vector2(8, 8), 1)
	player.held_item = item
	_build_layer()
	_build_hud()
	# The real conductor drives the beat dots and the pulse ring; the sandbox runs it so the
	# still frame shows a live beat state instead of four dark dots.
	BeatConductor.start(Config.PHASE_BPM[2])


func _washer(at: Vector2, requirement: StringName) -> FakeWasher:
	var washer := FakeWasher.new()
	washer.position = at
	washer.requirement = requirement
	add_child(washer)
	sheet_sprite(washer, WASHER_SHEET, Vector2i(48, 48), Vector2(24, 46))
	return washer


func _rocky_data() -> ItemData:
	var data := ItemData.new()
	data.id = &"rocky"
	data.points = 100
	return data


func _build_layer() -> void:
	if not ResourceLoader.exists(DIEGETIC_SCENE):
		return
	var packed := load(DIEGETIC_SCENE) as PackedScene
	if packed == null:
		return
	var layer := packed.instantiate() as Node2D
	layer.name = "DiegeticLayer"
	add_child(layer)


func _build_hud() -> void:
	if not ResourceLoader.exists(HUD_SCENE):
		return
	var packed := load(HUD_SCENE) as PackedScene
	if packed == null:
		return
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	canvas.layer = 10
	add_child(canvas)
	var hud := packed.instantiate() as Control
	canvas.add_child(hud)
	hud.set_shift_time(HUD_TIME)
	hud.set_phase(2, Config.PHASE_BPM[2])
	GameState.add_stability(DEMO_STABILITY - GameState.stability)
	if _tutorial:
		hud.set_tutorial_mode(true)
		hud.set_step(3, 7)
		hud.set_objective(tr("ROJO · LISO — así se lee el planeta"))


## `--tutorial` (after the tool's own `--`) renders the tutorial variant.
func _wants_tutorial() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument == "--tutorial":
			return true
	return false

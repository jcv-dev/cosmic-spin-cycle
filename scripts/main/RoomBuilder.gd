class_name RoomBuilder
extends RefCounted
## Builds the static room shell (background, floor, collision walls) from data/layout.json.
## Belts, shredders, washers and the player are added by MainLevel so each system stays
## independently testable.

const LAYOUT_PATH := "res://data/layout.json"
const TILE_WORLD := 64
const GRID_LINE_COLOR := Color(0.29, 0.32, 0.47, 0.30)

static var _layout_cache: Dictionary = {}


static func layout() -> Dictionary:
	if not _layout_cache.is_empty():
		return _layout_cache
	if not FileAccess.file_exists(LAYOUT_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if parsed is Dictionary:
		_layout_cache = parsed
	return _layout_cache


static func art_to_world(value: float) -> float:
	return value * float(Config.ART_SCALE)


## Untransformed art-pixel rect, for helpers that multiply by ART_SCALE themselves.
static func art_rect(rect: Dictionary) -> Rect2:
	return Rect2(float(rect.x), float(rect.y), float(rect.w), float(rect.h))


static func rect_world(rect: Dictionary) -> Rect2:
	return Rect2(
		art_to_world(float(rect.x)),
		art_to_world(float(rect.y)),
		art_to_world(float(rect.w)),
		art_to_world(float(rect.h))
	)


static func point_world(point: Array) -> Vector2:
	if point.size() != 2:
		return Vector2.ZERO
	return Vector2(art_to_world(float(point[0])), art_to_world(float(point[1])))


static func player_spawn() -> Vector2:
	var layout_data := layout()
	var spawn: Array = layout_data.get("player_spawn", [160, 128])
	return point_world(spawn)


static func room_rect() -> Rect2:
	return Rect2(0.0, 0.0, art_to_world(320.0), art_to_world(180.0))


## Builds the full layered room under `root` and returns the created Nodes keyed by name.
##
## Layer order is `docs/UX_BIBLE.md` §3.4: RoomBackground −100, Backdrop −95, Floor −90
## (with its decals), RoomDressing −80, the additive neon, the particle layer, the light rig
## and RoomForeground 20. Every optional painter degrades to a flat palette fallback when a
## sheet is missing, so the room never fails to build.
static func build(root: Node2D) -> Dictionary:
	var nodes := {}
	_build_background(root)
	# `--env-bare` is the A/B and before/after switch: it builds the shipped greybox room
	# only, so `docs/media/env_before.png` and the perf probe describe the same camera.
	var layered := not _has_cli_flag("--env-bare")
	if layered:
		nodes["backdrop"] = Backdrop.build(root)
	nodes["floor"] = _build_floor(root, layered)
	if layered:
		nodes["dressing"] = RoomDressing.build_dressing(root)
		nodes["belt_shadow"] = _build_belt_shadow(root)
		nodes["belt_glow"] = Atmosphere.build_belt_glow(root)
		nodes["atmosphere"] = Atmosphere.build(root)
		nodes["lighting"] = LightingRig.build(root)
		nodes["foreground"] = RoomDressing.build_foreground(root)
	nodes["walls"] = _build_walls(root)
	return nodes


static func _has_cli_flag(flag: String) -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == flag:
			return true
	return false


static func _build_background(root: Node2D) -> void:
	var sprite_id := "env_room"
	if ArtCatalog.has_sprite(sprite_id):
		var sprite := Sprite2D.new()
		sprite.name = "RoomBackground"
		sprite.texture = ArtCatalog.texture(sprite_id)
		sprite.centered = false
		sprite.position = Vector2.ZERO
		sprite.scale = Vector2.ONE * float(Config.ART_SCALE)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.z_index = -100
		root.add_child(sprite)
		return
	var bg := ColorRect.new()
	bg.name = "RoomBackground"
	bg.color = Palette.SPACE_VOID
	bg.position = Vector2.ZERO
	bg.size = room_rect().size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -100
	root.add_child(bg)


static func _build_floor(root: Node2D, layered: bool = true) -> Node2D:
	var floor_layer := Node2D.new()
	floor_layer.name = "Floor"
	floor_layer.z_index = -90
	root.add_child(floor_layer)
	var size := room_rect().size
	# A shipped env_room already contains its floor; never paint an opaque plate over it.
	var has_room_art := ArtCatalog.has_sprite("env_room")
	if not has_room_art:
		var plate := ColorRect.new()
		plate.name = "FloorPlate"
		plate.color = Palette.SPACE_DEEP
		plate.position = Vector2.ZERO
		plate.size = size
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		floor_layer.add_child(plate)
	# A shipped room already includes its floor. Only fall back to tiles when there is no
	# room art, otherwise the small tile motif repeats across the whole play area.
	if not has_room_art and SpriteSheet.has_sheet("env_floor"):
		_build_tiled_floor(floor_layer)

	if has_room_art:
		# The floor story rides on top of the shipped floor plate.
		if layered:
			RoomDressing.build_floor_decals(floor_layer)
		return floor_layer

	var x := 0.0
	while x <= size.x:
		var line := ColorRect.new()
		line.color = GRID_LINE_COLOR
		line.position = Vector2(x, 0.0)
		line.size = Vector2(1.0, size.y)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		floor_layer.add_child(line)
		x += float(TILE_WORLD)
	var y := 0.0
	while y <= size.y:
		var line := ColorRect.new()
		line.color = GRID_LINE_COLOR
		line.position = Vector2(0.0, y)
		line.size = Vector2(size.x, 1.0)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		floor_layer.add_child(line)
		y += float(TILE_WORLD)
	RoomDressing.build_floor_decals(floor_layer)
	return floor_layer


## Dims the belt decks so the washers and the chute stay the brightest things in the room.
## Drawn above the belts (-5) but below items (5), so items never lose contrast.
static func _build_belt_shadow(root: Node2D) -> Node2D:
	var layer := Node2D.new()
	layer.name = "BeltShade"
	layer.z_index = -3
	root.add_child(layer)
	for belt: Dictionary in layout().get("belts", []):
		var rect := rect_world(belt)
		var shade := ColorRect.new()
		shade.name = "%sShade" % String(belt.get("id", "belt"))
		shade.position = rect.position
		shade.size = rect.size
		shade.color = Color(Palette.SPACE_VOID.r, Palette.SPACE_VOID.g, Palette.SPACE_VOID.b, 0.30)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(shade)
	return layer


## Tiles the shipped env_floor sheet across the room (nearest, integer positions).
static func _build_tiled_floor(floor_layer: Node2D) -> void:
	var names := SpriteSheet.animation_names("env_floor")
	if names.is_empty():
		return
	var cell := SpriteSheet.frame_size("env_floor")
	if cell.x <= 0 or cell.y <= 0:
		return
	var cell_world := cell * Config.ART_SCALE
	var cols := int(ceil(room_rect().size.x / float(cell_world.x)))
	var rows := int(ceil(room_rect().size.y / float(cell_world.y)))
	for ty in range(rows):
		for tx in range(cols):
			var anim: StringName = names[(tx + ty * 2) % names.size()]
			var tex := SpriteSheet.frame_texture("env_floor", anim, 0)
			if tex == null:
				continue
			var tile := Sprite2D.new()
			tile.texture = tex
			tile.centered = false
			tile.position = Vector2(float(tx * cell_world.x), float(ty * cell_world.y))
			tile.scale = Vector2.ONE * float(Config.ART_SCALE)
			tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			floor_layer.add_child(tile)


static func _build_walls(root: Node2D) -> StaticBody2D:
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	walls.collision_layer = Config.CollisionLayer.WORLD
	walls.collision_mask = 0
	root.add_child(walls)
	var size := room_rect().size
	var thickness := art_to_world(float(layout().get("room", {}).get("wall", 8)))
	var rects := [
		Rect2(0.0, 0.0, size.x, thickness),
		Rect2(0.0, size.y - thickness, size.x, thickness),
		Rect2(0.0, thickness, thickness, size.y - thickness * 2.0),
		Rect2(size.x - thickness, thickness, thickness, size.y - thickness * 2.0),
	]
	for i in range(rects.size()):
		var rect: Rect2 = rects[i]
		var shape := CollisionShape2D.new()
		shape.name = "Wall%d" % i
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		walls.add_child(shape)

		var visual := ColorRect.new()
		visual.name = "WallVis%d" % i
		visual.color = Palette.SPACE_MID
		visual.position = rect.position
		visual.size = rect.size
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(visual)
	return walls


## World-space rect for a named belt/shredder/washer in layout.json.
static func layout_rect(id: String) -> Rect2:
	var data := layout()
	for key in ["belts", "shredders", "washers"]:
		for entry in data.get(key, []):
			if StringName(entry.get("id", "")) == StringName(id):
				return rect_world(entry)
	if id == "chute":
		return rect_world(data.get("chute", {}))
	return Rect2()

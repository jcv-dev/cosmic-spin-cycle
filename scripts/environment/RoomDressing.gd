class_name RoomDressing
extends Node2D
## Hand-authored density for the room: floor story, machine dressing and foreground.
##
## The layer list and z-order come from `docs/UX_BIBLE.md` §3.4: `FloorDecals` sits inside
## the z −90 `Floor` layer, `RoomDressing` is z −80 and `Foreground` is z 20. Every element
## is integer-positioned in world pixels and comes from a `*_specs()` pure function, so the
## layout is deterministic for a seed and testable without a renderer.
##
## Nothing here loads a raster asset: decals are `_draw()` polygons and rects, the vignette
## and dust are generated textures, and the display machinery reuses the shipped sheets.

## Grid the decal vertices snap to, in world pixels (1 art px).
const SNAP := 4.0
## Default seed of the room dressing; stable across runs so the room always looks the same.
const SEED := 20261124
## Number of grime decals on the floor.
const GRIME_COUNT := 6
## Puddle centres in art pixels (`data/layout.json` space).
const PUDDLES := [Vector2(112, 62), Vector2(206, 130)]

## Albedo multiplier for the display machines: the cabinets must stay secondary to the chute.
const MACHINE_ALBEDO := Color(0.87, 0.88, 0.93)

## 4×5 pixel font for the wall sign. Only the six glyphs the sign needs.
const GLYPHS := {
	"T": ["1111", "0010", "0010", "0010", "0010"],
	"U": ["1001", "1001", "1001", "1001", "0110"],
	"R": ["1110", "1001", "1110", "1010", "1001"],
	"N": ["1001", "1101", "1011", "1001", "1001"],
	"O": ["0110", "1001", "1001", "1001", "0110"],
	"S": ["0111", "1000", "0110", "0001", "1110"],
}

static var _overlay_texture: ImageTexture = null

var _specs: Array[Dictionary] = []

# --- builders ---------------------------------------------------------------


## Adds the floor decals inside the existing `Floor` layer (z −90) and returns the node.
static func build_floor_decals(floor_layer: Node2D, seed_value: int = SEED) -> RoomDressing:
	var node := RoomDressing.new()
	node.name = "FloorDecals"
	node.setup(floor_specs(seed_value))
	floor_layer.add_child(node)
	return node


## Adds the z −80 dressing layer under `root` and returns the node.
static func build_dressing(root: Node2D, seed_value: int = SEED) -> RoomDressing:
	var node := RoomDressing.new()
	node.name = "RoomDressing"
	node.z_index = -80
	node.setup(dressing_specs(seed_value))
	root.add_child(node)
	return node


## Adds the z 20 foreground. The vignette/dust overlay and the props are two nodes, so the
## whole foreground costs two draw calls for the overlay plus one per prop element.
static func build_foreground(root: Node2D) -> Node2D:
	var layer := Node2D.new()
	layer.name = "Foreground"
	layer.z_index = 20
	root.add_child(layer)
	_add_texture_sprite(layer, "Overlay", overlay_texture())
	var props := RoomDressing.new()
	props.name = "ForegroundProps"
	props.setup(foreground_specs())
	layer.add_child(props)
	return layer


static func _add_texture_sprite(parent: Node2D, node_name: String, texture: Texture2D) -> void:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2.ONE * float(Config.ART_SCALE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(sprite)


## Generated 320×180 atmosphere overlay: frame vignette, floor falloff and dust speckle in
## one texture, so the whole foreground costs a single blended quad instead of four.
## The play lane keeps ≤ 8 % alpha (dust only) so it can never hide an item.
static func overlay_texture() -> ImageTexture:
	if _overlay_texture != null:
		return _overlay_texture
	var width := 320
	var height := 180
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var shade := Palette.SPACE_VOID
	for y in range(height):
		for x in range(width):
			# Smooth ramp from the frame edge inwards; it reaches zero exactly at the play
			# lane boundary, so there is no hard rectangle around the lane.
			var distance := _edge_distance(x, y, width, height)
			var alpha := 0.48 * clampf(1.0 - float(distance) / 30.0, 0.0, 1.0)
			# The ceiling is the light source, so the bottom of the frame sinks instead.
			alpha = maxf(alpha, 0.22 * clampf((float(y) - 140.0) / 40.0, 0.0, 1.0))
			if alpha <= 0.0:
				continue
			image.set_pixel(x, y, Color(shade.r, shade.g, shade.b, alpha))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	var mote := Palette.METAL_3
	for index in range(150):
		var x := rng.randi_range(1, 318)
		var y := rng.randi_range(1, 178)
		var mote_alpha := 0.05 if index % 3 == 0 else 0.03
		var merged := _alpha_over(image.get_pixel(x, y), Color(mote.r, mote.g, mote.b, mote_alpha))
		image.set_pixel(x, y, merged)
	_overlay_texture = ImageTexture.create_from_image(image)
	return _overlay_texture


## Straight-alpha "source over" for two pixel colours.
static func _alpha_over(destination: Color, source: Color) -> Color:
	var out_alpha := source.a + destination.a * (1.0 - source.a)
	if out_alpha <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var red := (source.r * source.a + destination.r * destination.a * (1.0 - source.a)) / out_alpha
	var green := (
		(source.g * source.a + destination.g * destination.a * (1.0 - source.a)) / out_alpha
	)
	var blue := (source.b * source.a + destination.b * destination.a * (1.0 - source.a)) / out_alpha
	return Color(red, green, blue, out_alpha)


## Distance in art px from the nearest frame edge.
static func _edge_distance(x: int, y: int, width: int, height: int) -> int:
	return mini(mini(x, width - 1 - x), mini(y, height - 1 - y))


## Drops the generated foreground overlay (tests only).
static func clear_cache() -> void:
	_overlay_texture = null


## Installs a spec list and triggers the first paint.
func setup(specs: Array[Dictionary]) -> void:
	_specs = specs
	queue_redraw()


## Spec list currently drawn (tests read this instead of parsing `_draw`).
func specs() -> Array[Dictionary]:
	return _specs


## Number of drawn elements; stable for a seed (determinism test).
func element_count() -> int:
	return _specs.size()


# --- spec constructors ------------------------------------------------------


static func _box(rect: Rect2, color: Color, alpha: float) -> Dictionary:
	return {"kind": &"rect", "rect": rect, "color": color, "alpha": alpha}


static func _poly(points: PackedVector2Array, color: Color, alpha: float) -> Dictionary:
	return {"kind": &"poly", "points": points, "color": color, "alpha": alpha}


static func _line(points: PackedVector2Array, color: Color, alpha: float) -> Dictionary:
	return {"kind": &"line", "points": points, "color": color, "alpha": alpha, "width": 4.0}


static func _ring(
	center: Vector2, radius: float, color: Color, alpha: float, width: float = 4.0
) -> Dictionary:
	return {
		"kind": &"arc",
		"center": center,
		"radius": radius,
		"from": 0.0,
		"to": TAU,
		"segments": 48,
		"color": color,
		"alpha": alpha,
		"width": width,
	}


# --- drawing ----------------------------------------------------------------


func _draw() -> void:
	for spec: Dictionary in _specs:
		_draw_spec(spec)


func _draw_spec(spec: Dictionary) -> void:
	var kind: StringName = spec.get("kind", &"")
	var color: Color = spec.get("color", Color.WHITE)
	var alpha: float = float(spec.get("alpha", 1.0))
	var tinted := Color(color.r, color.g, color.b, alpha)
	match kind:
		&"rect":
			draw_rect(spec["rect"] as Rect2, tinted, true)
		&"poly":
			draw_colored_polygon(spec["points"] as PackedVector2Array, tinted)
		&"line":
			draw_polyline(
				spec["points"] as PackedVector2Array, tinted, float(spec.get("width", 4.0)), false
			)
		&"arc":
			draw_arc(
				spec["center"] as Vector2,
				float(spec["radius"]),
				float(spec["from"]),
				float(spec["to"]),
				int(spec.get("segments", 16)),
				tinted,
				float(spec.get("width", 4.0)),
				false
			)
		&"vent":
			_draw_vent(spec["rect"] as Rect2, color)
		&"valve":
			_draw_valve(spec["center"] as Vector2, float(spec["radius"]), color)
		&"sign":
			_draw_sign(spec["rect"] as Rect2, str(spec.get("text", "TURNOS")))
		&"drain":
			_draw_drain(spec["rect"] as Rect2)
		&"bucket":
			_draw_bucket(spec["rect"] as Rect2)
		&"baskets":
			_draw_baskets(spec["rect"] as Rect2)
		&"readout":
			_draw_readout(spec["rect"] as Rect2)


# --- floor story (§3.6.2) ---------------------------------------------------


## Deterministic floor decal list: grime, puddles, hazard stripes, painted routes, scuffs.
static func floor_specs(seed_value: int = SEED) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_floor_grime(specs, rng)
	_floor_puddles(specs)
	_floor_streaks(specs)
	_floor_hazard(specs)
	_floor_routes(specs)
	_floor_scuffs(specs)
	_floor_chute_zone(specs)
	_floor_wall_shadow(specs)
	_floor_contact_shadows(specs)
	return specs


static func _floor_grime(specs: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	# Free floor zones between the machines: the play lane keeps its middle clear.
	var zones := [
		Vector2(100, 44),
		Vector2(206, 46),
		Vector2(96, 116),
		Vector2(196, 142),
		Vector2(122, 148),
		Vector2(210, 62),
	]
	var colors := [Palette.METAL_0, Palette.SPACE_HAZE]
	var scale := float(Config.ART_SCALE)
	for index in range(GRIME_COUNT):
		var center: Vector2 = zones[index % zones.size()] * scale
		center += Vector2(rng.randi_range(-5, 5), rng.randi_range(-4, 4)) * scale
		var radius := float(rng.randi_range(11, 18)) * scale
		var points := PackedVector2Array()
		var verts := rng.randi_range(7, 9)
		for vertex in range(verts):
			var angle := TAU * float(vertex) / float(verts) + rng.randf_range(-0.16, 0.16)
			var reach := radius * rng.randf_range(0.62, 1.0)
			points.append(_snap(center + Vector2(cos(angle), sin(angle)) * reach))
		specs.append(_poly(points, colors[index % colors.size()], 0.16 if index % 2 == 0 else 0.13))


static func _floor_puddles(specs: Array[Dictionary]) -> void:
	var radius := Vector2(11.0, 6.0) * float(Config.ART_SCALE)
	for center_art: Vector2 in PUDDLES:
		var center := center_art * float(Config.ART_SCALE)
		var points := PackedVector2Array()
		for vertex in range(18):
			var angle := TAU * float(vertex) / 18.0
			points.append(_snap(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)))
		specs.append(_poly(points, Palette.SPACE_HAZE, 0.9))
		# 1 art-px specular highlight along the top-left rim, as if a lamp is reflected.
		var gloss := PackedVector2Array()
		for step in range(9):
			var angle := PI * (1.05 + 0.5 * float(step) / 8.0)
			gloss.append(_snap(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)))
		specs.append(_line(gloss, Palette.METAL_3, 0.75))


## Two long specular streaks from the ceiling lamps: the floor reads as wet concrete.
static func _floor_streaks(specs: Array[Dictionary]) -> void:
	var streaks := [
		[Vector2(300.0, 210.0), Vector2(430.0, 250.0)],
		[Vector2(960.0, 250.0), Vector2(1090.0, 212.0)],
		[Vector2(520.0, 470.0), Vector2(650.0, 500.0)],
	]
	for entry: Array in streaks:
		var from: Vector2 = entry[0]
		var to: Vector2 = entry[1]
		specs.append(
			_poly(
				PackedVector2Array([from, to, to + Vector2(2.0, 8.0), from + Vector2(2.0, 8.0)]),
				Palette.METAL_2,
				0.10
			)
		)


static func _floor_hazard(specs: Array[Dictionary]) -> void:
	for washer: Dictionary in RoomBuilder.layout().get("washers", []):
		var art := RoomBuilder.art_rect(washer)
		var rect := _rect_world(
			Rect2(art.position.x + 6.0, art.end.y + 1.0, art.size.x - 12.0, 5.0)
		)
		specs.append(_box(rect, Palette.SPACE_VOID, 0.35))
		var stripe := 7.0 * float(Config.ART_SCALE)
		for index in range(int(rect.size.x / stripe)):
			var x := rect.position.x + float(index) * stripe
			var points := PackedVector2Array(
				[
					Vector2(x, rect.end.y),
					Vector2(x + stripe * 0.5, rect.position.y),
					Vector2(x + stripe, rect.position.y),
					Vector2(x + stripe * 0.5, rect.end.y),
				]
			)
			specs.append(_poly(points, Palette.HAZARD_ORANGE, 0.20))


static func _floor_routes(specs: Array[Dictionary]) -> void:
	var chute := RoomBuilder.layout_rect("chute")
	var scale := float(Config.ART_SCALE)
	var mouths := {
		"washer_nw": [Vector2(60, 80) * scale, Vector2(chute.position.x, 80.0 * scale)],
		"washer_ne": [Vector2(260, 80) * scale, Vector2(chute.end.x, 80.0 * scale)],
		"washer_sw":
		[
			Vector2(60, 144) * scale,
			Vector2(chute.position.x - 32.0, 144.0 * scale),
			Vector2(chute.position.x - 32.0, chute.end.y),
		],
		"washer_se":
		[
			Vector2(260, 144) * scale,
			Vector2(chute.end.x + 32.0, 144.0 * scale),
			Vector2(chute.end.x + 32.0, chute.end.y),
		],
	}
	for key: String in mouths.keys():
		var path := PackedVector2Array()
		for entry: Vector2 in mouths[key] as Array:
			path.append(_snap(entry))
		# Walk the polyline in 4 art-px dashes with a 4 art-px gap.
		for segment in range(path.size() - 1):
			var from := path[segment]
			var to := path[segment + 1]
			var length := from.distance_to(to)
			if length < 1.0:
				continue
			var direction := (to - from) / length
			var travelled := 0.0
			while travelled < length:
				var run := minf(16.0, length - travelled)
				var start := from + direction * travelled
				specs.append(_dash_rect(start, start + direction * run))
				travelled += 32.0


## Axis-aligned 1 art-px thick dash between two points (both are integer world pixels).
static func _dash_rect(from: Vector2, to: Vector2) -> Dictionary:
	var thickness := 4.0
	if absf(to.x - from.x) >= absf(to.y - from.y):
		var rect := Rect2(
			minf(from.x, to.x), from.y - thickness * 0.5, absf(to.x - from.x), thickness
		)
		return _box(rect, Palette.METAL_1, 0.32)
	var tall := Rect2(from.x - thickness * 0.5, minf(from.y, to.y), thickness, absf(to.y - from.y))
	return _box(tall, Palette.METAL_1, 0.32)


static func _floor_scuffs(specs: Array[Dictionary]) -> void:
	var spots := [
		Rect2(78, 30, 10, 3),
		Rect2(234, 30, 10, 3),
		Rect2(78, 144, 10, 3),
		Rect2(234, 144, 10, 3),
		Rect2(60, 58, 8, 3),
		Rect2(250, 58, 8, 3),
	]
	for spot: Rect2 in spots:
		specs.append(_box(_rect_world(spot), Palette.METAL_1, 0.16))


## Painted delivery zone around the chute: the one place the floor says "put it here".
static func _floor_chute_zone(specs: Array[Dictionary]) -> void:
	var center := RoomBuilder.layout_rect("chute").get_center()
	specs.append(_ring(center, 88.0, Palette.CLEAN_GREEN, 0.20))
	specs.append(_ring(center, 104.0, Palette.METAL_1, 0.14))
	for index in range(8):
		var angle := TAU * float(index) / 8.0 + PI / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		var tick := PackedVector2Array(
			[_snap(center + direction * 88.0), _snap(center + direction * 108.0)]
		)
		specs.append(_line(tick, Palette.CLEAN_GREEN, 0.22))


## Grounding shadows: a cast shadow plus a flat ellipse under every machine.
static func _floor_contact_shadows(specs: Array[Dictionary]) -> void:
	for washer: Dictionary in RoomBuilder.layout().get("washers", []):
		var rect := RoomBuilder.rect_world(washer)
		specs.append(
			_box(
				Rect2(rect.position.x + 12.0, rect.end.y - 8.0, rect.size.x, 16.0),
				Palette.SPACE_VOID,
				0.30
			)
		)
		specs.append(
			_shadow_ellipse(Vector2(rect.get_center().x, rect.end.y - 4.0), rect.size.x * 0.46)
		)
	var chute := RoomBuilder.layout_rect("chute")
	specs.append(_shadow_ellipse(Vector2(chute.get_center().x, chute.end.y - 4.0), 26.0))
	for belt: Dictionary in RoomBuilder.layout().get("belts", []):
		var rect := RoomBuilder.rect_world(belt)
		if rect.size.x >= rect.size.y:
			specs.append(
				_box(Rect2(rect.position.x, rect.end.y, rect.size.x, 8.0), Palette.SPACE_VOID, 0.35)
			)
		else:
			specs.append(
				_box(Rect2(rect.end.x, rect.position.y, 8.0, rect.size.y), Palette.SPACE_VOID, 0.35)
			)


## Flat octagonal shadow (never a smooth gradient: this is pixel art). The outline is built
## from explicit points so no two vertices can snap onto each other.
static func _shadow_ellipse(center: Vector2, radius_x: float, radius_y: float = 6.0) -> Dictionary:
	var rx := radius_x
	var ry := radius_y
	var points := PackedVector2Array(
		[
			_snap(center + Vector2(-rx, 0.0)),
			_snap(center + Vector2(-rx * 0.68, -ry)),
			_snap(center + Vector2(0.0, -ry)),
			_snap(center + Vector2(rx * 0.68, -ry)),
			_snap(center + Vector2(rx, 0.0)),
			_snap(center + Vector2(rx * 0.68, ry)),
			_snap(center + Vector2(0.0, ry)),
			_snap(center + Vector2(-rx * 0.68, ry)),
		]
	)
	return _poly(points, Palette.SPACE_VOID, 0.42)


## Soft contact shadow where the floor meets the walls: three stepped strips per wall.
static func _floor_wall_shadow(specs: Array[Dictionary]) -> void:
	var bands := [0.28, 0.16, 0.07]
	for step in range(bands.size()):
		var inset := 32.0 + float(step) * 8.0
		var alpha: float = bands[step]
		specs.append(_box(Rect2(32.0, inset, 1216.0, 8.0), Palette.SPACE_VOID, alpha))
		specs.append(_box(Rect2(32.0, 688.0 - inset, 1216.0, 8.0), Palette.SPACE_VOID, alpha))
		specs.append(_box(Rect2(inset, 32.0, 8.0, 656.0), Palette.SPACE_VOID, alpha))
		specs.append(_box(Rect2(1248.0 - inset, 32.0, 8.0, 656.0), Palette.SPACE_VOID, alpha))


# --- machine dressing (§3.6.3) ----------------------------------------------


## Deterministic dressing list: cable runs, vent grilles, props, sign, valves, drain.
static func dressing_specs(seed_value: int = SEED) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1
	var specs: Array[Dictionary] = []
	_dressing_cables(specs)
	_dressing_vents(specs)
	_dressing_props(specs)
	_dressing_sign(specs)
	_dressing_valves(specs)
	_dressing_drain(specs)
	_dressing_walls(specs)
	# One grease smear changes with the seed so the layer is provably seed-driven.
	var smear := Vector2(150, 100) + Vector2(rng.randi_range(-8, 8), rng.randi_range(-6, 6))
	specs.append(
		_box(_rect_world(Rect2(smear, Vector2(rng.randi_range(6, 12), 2))), Palette.METAL_0, 0.12)
	)
	return specs


static func _dressing_cables(specs: Array[Dictionary]) -> void:
	var scale := float(Config.ART_SCALE)
	var runs := [
		[Vector2(36, 44), Vector2(20, 44), Vector2(20, 16)],
		[Vector2(284, 44), Vector2(300, 44), Vector2(300, 16)],
		[Vector2(36, 110), Vector2(20, 110), Vector2(20, 150)],
		[Vector2(284, 110), Vector2(300, 110), Vector2(300, 150)],
	]
	for run: Array in runs:
		var points := PackedVector2Array()
		for point: Vector2 in run:
			points.append(_snap(point * scale))
		specs.append(_line(points, Palette.METAL_0, 0.75))
		var plug := points[points.size() - 1]
		specs.append(_box(Rect2(plug.x - 8.0, plug.y - 8.0, 16.0, 16.0), Palette.METAL_2, 0.85))


static func _dressing_vents(specs: Array[Dictionary]) -> void:
	var vents := [Rect2(12, 146, 16, 8), Rect2(292, 120, 16, 8), Rect2(148, 2, 24, 5)]
	for vent: Rect2 in vents:
		specs.append({"kind": &"vent", "rect": _rect_world(vent), "color": Palette.METAL_0})


static func _dressing_props(specs: Array[Dictionary]) -> void:
	specs.append({"kind": &"bucket", "rect": _rect_world(Rect2(30, 8, 16, 16))})
	specs.append({"kind": &"baskets", "rect": _rect_world(Rect2(248, 150, 28, 20))})


static func _dressing_sign(specs: Array[Dictionary]) -> void:
	specs.append({"kind": &"sign", "rect": _rect_world(Rect2(104, 28, 40, 16)), "text": "TURNOS"})


static func _dressing_valves(specs: Array[Dictionary]) -> void:
	var scale := float(Config.ART_SCALE)
	for center: Vector2 in [Vector2(20, 30), Vector2(300, 30)]:
		(
			specs
			. append(
				{
					"kind": &"valve",
					"center": _snap(center * scale),
					"radius": 9.0 * scale,
					"color": Palette.METAL_2,
				}
			)
		)


static func _dressing_drain(specs: Array[Dictionary]) -> void:
	specs.append({"kind": &"drain", "rect": _rect_world(Rect2(286, 150, 20, 12))})


## Panel seams and bolts along the two side walls: density at the edges, calm in the lane.
static func _dressing_walls(specs: Array[Dictionary]) -> void:
	for y in range(48, 700, 96):
		specs.append(_box(Rect2(2.0, float(y), 28.0, 2.0), Palette.METAL_0, 0.45))
		specs.append(_box(Rect2(1250.0, float(y), 28.0, 2.0), Palette.METAL_0, 0.45))
	for y in range(88, 700, 192):
		specs.append(_box(Rect2(8.0, float(y), 4.0, 4.0), Palette.METAL_1, 0.5))
		specs.append(_box(Rect2(1268.0, float(y), 4.0, 4.0), Palette.METAL_1, 0.5))


# --- individual dressing painters -------------------------------------------


func _draw_vent(rect: Rect2, color: Color) -> void:
	draw_rect(rect, Color(Palette.SPACE_VOID.r, Palette.SPACE_VOID.g, Palette.SPACE_VOID.b, 0.55))
	var tint := Color(color.r, color.g, color.b, 0.7)
	var slat := rect.size.y / 4.0
	for index in range(3):
		var y := rect.position.y + slat * (0.35 + float(index))
		draw_rect(Rect2(rect.position.x + 4.0, roundf(y), rect.size.x - 8.0, 4.0), tint)


func _draw_valve(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(
		center,
		radius,
		Color(Palette.SPACE_DEEP.r, Palette.SPACE_DEEP.g, Palette.SPACE_DEEP.b, 0.95)
	)
	draw_arc(center, radius, 0.0, TAU, 24, color, 4.0, false)
	var hub := Color(Palette.METAL_1.r, Palette.METAL_1.g, Palette.METAL_1.b, 0.95)
	for index in range(3):
		var angle := TAU * float(index) / 3.0 + PI * 0.5
		var offset := Vector2(cos(angle), sin(angle))
		draw_line(center + offset * 4.0, center + offset * (radius - 2.0), hub, 2.0, false)
	draw_circle(center, 4.0, Color(Palette.METAL_2.r, Palette.METAL_2.g, Palette.METAL_2.b, 0.95))


func _draw_sign(rect: Rect2, text: String) -> void:
	draw_rect(rect, Color(Palette.SPACE_DEEP.r, Palette.SPACE_DEEP.g, Palette.SPACE_DEEP.b, 0.95))
	draw_rect(rect, Color(Palette.METAL_1.r, Palette.METAL_1.g, Palette.METAL_1.b, 0.9), false, 2.0)
	var pixel := 4.0
	var origin := Vector2(rect.position.x + 6.0, rect.position.y + 6.0)
	var ink := Color(Palette.YEL_3.r, Palette.YEL_3.g, Palette.YEL_3.b, 0.92)
	for index in range(text.length()):
		var glyph: Array = GLYPHS.get(text.substr(index, 1), [])
		for row in range(glyph.size()):
			var bits: String = glyph[row]
			for column in range(bits.length()):
				if bits[column] != "1":
					continue
				var at := Vector2(
					float(column) * pixel + float(index) * 5.0 * pixel, float(row) * pixel
				)
				draw_rect(Rect2(origin + at, Vector2(pixel, pixel)), ink)


func _draw_drain(rect: Rect2) -> void:
	draw_rect(rect, Color(Palette.SPACE_VOID.r, Palette.SPACE_VOID.g, Palette.SPACE_VOID.b, 0.8))
	draw_rect(rect, Color(Palette.METAL_1.r, Palette.METAL_1.g, Palette.METAL_1.b, 0.7), false, 2.0)
	for index in range(4):
		var y := rect.position.y + 4.0 + float(index) * 4.0
		draw_rect(
			Rect2(rect.position.x + 4.0, y, rect.size.x - 8.0, 2.0),
			Color(Palette.METAL_2.r, Palette.METAL_2.g, Palette.METAL_2.b, 0.55)
		)


func _draw_bucket(rect: Rect2) -> void:
	var body := Rect2(rect.position + Vector2(0.0, 8.0), Vector2(rect.size.x, rect.size.y - 8.0))
	var points := PackedVector2Array(
		[
			body.position + Vector2(4.0, 0.0),
			Vector2(body.end.x - 4.0, body.position.y),
			Vector2(body.end.x - 8.0, body.end.y),
			Vector2(body.position.x + 6.0, body.end.y),
		]
	)
	draw_colored_polygon(
		points, Color(Palette.METAL_1.r, Palette.METAL_1.g, Palette.METAL_1.b, 0.95)
	)
	draw_rect(
		Rect2(body.position + Vector2(2.0, 0.0), Vector2(body.size.x - 4.0, 4.0)),
		Color(Palette.METAL_2.r, Palette.METAL_2.g, Palette.METAL_2.b, 0.95)
	)
	draw_rect(
		Rect2(body.position + Vector2(6.0, 4.0), Vector2(body.size.x - 12.0, 4.0)),
		Color(Palette.SPACE_VOID.r, Palette.SPACE_VOID.g, Palette.SPACE_VOID.b, 0.8)
	)
	# Mop leaning out of the bucket, kept inside the prop footprint.
	var handle_top := rect.position + Vector2(rect.size.x - 4.0, 0.0)
	var handle_bottom := rect.position + Vector2(rect.size.x - 12.0, 12.0)
	draw_line(handle_top, handle_bottom, Palette.METAL_0, 4.0, false)
	draw_rect(
		Rect2(handle_bottom - Vector2(6.0, 4.0), Vector2(12.0, 8.0)),
		Color(Palette.METAL_2.r, Palette.METAL_2.g, Palette.METAL_2.b, 0.8)
	)


func _draw_baskets(rect: Rect2) -> void:
	var colors := [Palette.METAL_0, Palette.METAL_1, Palette.SPACE_HAZE]
	var box_height := rect.size.y / 3.0
	for index in range(3):
		var offset := Vector2(float(index) * 2.0, float(index) * box_height)
		var box := Rect2(
			rect.position + offset, Vector2(rect.size.x - float(index) * 4.0, box_height - 2.0)
		)
		draw_rect(box, Color(colors[index].r, colors[index].g, colors[index].b, 0.9))
		draw_rect(
			Rect2(box.position, Vector2(box.size.x, 2.0)),
			Color(Palette.METAL_3.r, Palette.METAL_3.g, Palette.METAL_3.b, 0.6)
		)


## Small status display in the washer's dark panel. The shipped sheet bakes a bright LED
## square there; this plate replaces it with a deliberate recessed readout (three dim bars)
## so it reads as a display instead of a missing-sprite artefact.
func _draw_readout(rect: Rect2) -> void:
	draw_rect(rect, Color(Palette.SPACE_VOID.r, Palette.SPACE_VOID.g, Palette.SPACE_VOID.b, 0.96))
	draw_rect(
		rect, Color(Palette.METAL_0.r, Palette.METAL_0.g, Palette.METAL_0.b, 0.55), false, 2.0
	)
	var inks := [Palette.FUNK_CYAN, Palette.CLEAN_GREEN, Palette.METAL_2]
	var widths := [0.75, 0.5, 0.62]
	var alphas := [0.5, 0.4, 0.45]
	for index in range(3):
		var bar := Rect2(
			rect.position + Vector2(4.0, 4.0 + float(index) * 8.0),
			Vector2(rect.size.x * float(widths[index]) - 8.0, 4.0)
		)
		var ink: Color = inks[index]
		draw_rect(bar, Color(ink.r, ink.g, ink.b, float(alphas[index])))


# --- foreground (§3.6.6) ----------------------------------------------------


## Deterministic foreground props: ceiling pipes, lamp cords and their glow rings.
static func foreground_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	_foreground_pipes(specs)
	_foreground_lamps(specs)
	return specs


static func _foreground_pipes(specs: Array[Dictionary]) -> void:
	specs.append(_box(Rect2(0.0, 2.0, 1280.0, 8.0), Palette.SPACE_MID, 1.0))
	specs.append(_box(Rect2(0.0, 2.0, 1280.0, 2.0), Palette.METAL_0, 0.9))
	specs.append(_box(Rect2(0.0, 14.0, 1280.0, 6.0), Palette.SPACE_MID, 1.0))
	specs.append(_box(Rect2(0.0, 14.0, 1280.0, 2.0), Palette.METAL_0, 0.7))
	for x in [180.0, 520.0, 860.0, 1180.0]:
		specs.append(_box(Rect2(x, 0.0, 12.0, 22.0), Palette.METAL_0, 0.95))


static func _foreground_lamps(specs: Array[Dictionary]) -> void:
	for x in [320.0, 980.0]:
		specs.append(_box(Rect2(x - 2.0, 24.0, 4.0, 62.0), Palette.SPACE_VOID, 0.85))
		specs.append(_box(Rect2(x - 12.0, 82.0, 24.0, 8.0), Palette.METAL_1, 0.95))
		# Three flat rings stand in for a soft glow without a shader or a big quad.
		for ring: Array in [[40.0, 0.07], [26.0, 0.09], [12.0, 0.14]]:
			specs.append(
				_ring(Vector2(x, 92.0), float(ring[0]), Palette.YEL_3, float(ring[1]), 8.0)
			)


# --- display-only machinery (dev sandbox + title diorama) -------------------


## Reusable display room used by the title diorama and the dev sandbox.
##
## The real shift builds its washers and chute from the M4 entities; until then (and for
## the menu) this places the shipped sheets so the diorama is the real room, not a mockup.
## Returns `{"washers": {id: AnimatedSprite2D}, "chute": AnimatedSprite2D}`.
static func build_machines_for_display(root: Node2D) -> Dictionary:
	var machines: Node2D = Node2D.new()
	machines.name = "Machines"
	machines.z_index = 0
	root.add_child(machines)
	var readouts := RoomDressing.new()
	readouts.name = "PanelReadouts"
	readouts.z_index = 2
	root.add_child(readouts)
	var readout_specs: Array[Dictionary] = []
	var washers := {}
	for washer: Dictionary in RoomBuilder.layout().get("washers", []):
		var washer_id := String(washer.get("id", "washer"))
		var rect := RoomBuilder.rect_world(washer)
		var sprite := AnimatedSprite2D.new()
		sprite.name = washer_id
		sprite.position = Vector2(rect.get_center().x, rect.end.y)
		sprite.z_index = 0
		# The cabinets are large bright shapes; 13 % down keeps them secondary to the chute.
		sprite.self_modulate = MACHINE_ALBEDO
		machines.add_child(sprite)
		(
			readout_specs
			. append(
				{
					"kind": &"readout",
					"rect": Rect2(rect.position.x + 28.0, rect.position.y + 28.0, 32.0, 32.0),
				}
			)
		)
		if not SpriteSheet.configure(sprite, "mach_washer", &"idle"):
			_placeholder_rect(machines, rect, Palette.METAL_1)
		washers[StringName(washer_id)] = sprite
	var chute_rect := RoomBuilder.layout_rect("chute")
	var chute := AnimatedSprite2D.new()
	chute.name = "chute"
	chute.position = chute_rect.get_center()
	chute.z_index = 1
	machines.add_child(chute)
	if not SpriteSheet.configure(chute, "env_chute", &"open"):
		_placeholder_rect(machines, chute_rect, Palette.METAL_2)
	readouts.setup(readout_specs)
	return {"washers": washers, "chute": chute}


static func _placeholder_rect(parent: Node2D, rect: Rect2, color: Color) -> void:
	var box := ColorRect.new()
	box.position = rect.position
	box.size = rect.size
	box.color = Color(color.r, color.g, color.b, 0.85)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)


# --- small helpers ----------------------------------------------------------


static func _snap(point: Vector2) -> Vector2:
	return Vector2(roundf(point.x / SNAP) * SNAP, roundf(point.y / SNAP) * SNAP)


static func _rect_world(art_rect: Rect2) -> Rect2:
	var scale := float(Config.ART_SCALE)
	return Rect2(art_rect.position * scale, art_rect.size * scale)

class_name RoomDressing
extends Node2D
## Hand-authored density for the room: floor story, machine dressing and foreground.
##
## The layer list and z-order come from `docs/UX_BIBLE.md` §3.4:
## `FloorDecals` sits inside the z −90 `Floor` layer, `RoomDressing` is z −80 and
## `Foreground` is z 20. Every element is integer-positioned in world pixels and comes from
## a `*_specs()` pure function, so the layout is deterministic for a seed and testable
## without a renderer.
##
## Nothing here loads a raster asset: the decals are `_draw()` polygons and rects, and the
## only image is the display-only machinery that reuses the shipped sprite sheets.

## Grid the decal vertices snap to, in world pixels (1 art px).
const SNAP := 4.0
## Default seed of the room dressing; stable across runs so the room always looks the same.
const SEED := 20261124
## Number of grime decals on the floor.
const GRIME_COUNT := 6
## Puddle centres in art pixels (`data/layout.json` space).
const PUDDLES := [Vector2(112, 62), Vector2(206, 130)]
## Margin kept clear of decoration around the play lane, in world pixels.
const LANE_MARGIN := 8.0

## 4×5 pixel font for the wall sign. Only the six glyphs the sign needs.
const GLYPHS := {
	"T": ["1111", "0010", "0010", "0010", "0010"],
	"U": ["1001", "1001", "1001", "1001", "0110"],
	"R": ["1110", "1001", "1110", "1010", "1001"],
	"N": ["1001", "1101", "1011", "1001", "1001"],
	"O": ["0110", "1001", "1001", "1001", "0110"],
	"S": ["0111", "1000", "0110", "0001", "1110"],
}

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


## Adds the z 20 foreground (vignette, lamps, ceiling pipes, dust) and returns the node.
static func build_foreground(root: Node2D) -> RoomDressing:
	var node := RoomDressing.new()
	node.name = "Foreground"
	node.z_index = 20
	node.setup(foreground_specs())
	root.add_child(node)
	return node


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
				spec["points"] as PackedVector2Array,
				tinted,
				float(spec.get("width", 4.0)),
				false
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
		Vector2(106, 46),
		Vector2(204, 50),
		Vector2(98, 118),
		Vector2(202, 124),
		Vector2(150, 56),
		Vector2(152, 138),
	]
	var colors := [Palette.METAL_0, Palette.SPACE_HAZE]
	for index in range(GRIME_COUNT):
		var center_art: Vector2 = zones[index % zones.size()]
		var center := (
			center_art * float(Config.ART_SCALE)
			+ Vector2(rng.randi_range(-5, 5), rng.randi_range(-4, 4)) * float(Config.ART_SCALE)
		)
		var radius := float(rng.randi_range(11, 18)) * float(Config.ART_SCALE)
		var verts := rng.randi_range(7, 9)
		var points := PackedVector2Array()
		for vertex in range(verts):
			var angle := TAU * float(vertex) / float(verts) + rng.randf_range(-0.18, 0.18)
			var reach := radius * rng.randf_range(0.55, 1.0)
			var point := center + Vector2(cos(angle), sin(angle)) * reach
			points.append(_snap(point))
		specs.append(
			{
				"kind": &"poly",
				"points": points,
				"color": colors[index % colors.size()],
				"alpha": 0.20 if index % 2 == 0 else 0.16,
			}
		)


static func _floor_puddles(specs: Array[Dictionary]) -> void:
	var radius := Vector2(11.0, 6.0) * float(Config.ART_SCALE)
	for center_art: Vector2 in PUDDLES:
		var center := center_art * float(Config.ART_SCALE)
		var points := PackedVector2Array()
		for vertex in range(18):
			var angle := TAU * float(vertex) / 18.0
			points.append(_snap(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)))
		specs.append({"kind": &"poly", "points": points, "color": Palette.SPACE_HAZE, "alpha": 0.9})
		# 1 art-px specular highlight along the top-left rim, as if a lamp is reflected.
		var gloss := PackedVector2Array()
		for step in range(9):
			var angle := PI * (1.05 + 0.5 * float(step) / 8.0)
			gloss.append(_snap(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)))
		specs.append(
			{
				"kind": &"line",
				"points": gloss,
				"color": Palette.METAL_3,
				"alpha": 0.75,
				"width": 4.0,
			}
		)


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
		var points := PackedVector2Array(
			[from, to, to + Vector2(2.0, 8.0), from + Vector2(2.0, 8.0)]
		)
		specs.append(
			{"kind": &"poly", "points": points, "color": Palette.METAL_2, "alpha": 0.10}
		)


static func _floor_hazard(specs: Array[Dictionary]) -> void:
	for washer: Dictionary in RoomBuilder.layout().get("washers", []):
		var art := RoomBuilder.art_rect(washer)
		var band := Rect2(art.position.x + 6.0, art.end.y + 1.0, art.size.x - 12.0, 5.0)
		var rect := _rect_world(band)
		specs.append({"kind": &"rect", "rect": rect, "color": Palette.SPACE_VOID, "alpha": 0.35})
		var stripe := 7.0 * float(Config.ART_SCALE)
		var count := int(rect.size.x / stripe)
		for index in range(count):
			var x := rect.position.x + float(index) * stripe
			var points := PackedVector2Array(
				[
					Vector2(x, rect.end.y),
					Vector2(x + stripe * 0.5, rect.position.y),
					Vector2(x + stripe, rect.position.y),
					Vector2(x + stripe * 0.5, rect.end.y),
				]
			)
			specs.append(
				{
					"kind": &"poly",
					"points": points,
					"color": Palette.HAZARD_ORANGE,
					"alpha": 0.20,
				}
			)


static func _floor_routes(specs: Array[Dictionary]) -> void:
	var chute := RoomBuilder.layout_rect("chute")
	var mouths := {
		"washer_nw": [Vector2(60, 80), Vector2(chute.position.x, 80.0)],
		"washer_ne": [Vector2(260, 80), Vector2(chute.end.x, 80.0)],
		"washer_sw": [
			Vector2(60, 144),
			Vector2(chute.position.x - 8.0, 144.0),
			Vector2(chute.position.x - 8.0, chute.end.y),
		],
		"washer_se": [
			Vector2(260, 144),
			Vector2(chute.end.x + 8.0, 144.0),
			Vector2(chute.end.x + 8.0, chute.end.y),
		],
	}
	for key: String in mouths.keys():
		var raw: Array = mouths[key]
		var path := PackedVector2Array()
		for entry: Vector2 in raw:
			path.append(_snap(entry * float(Config.ART_SCALE)))
		# Walk the polyline in 4 art-px dashes with a 4 art-px gap.
		var dash := 16.0
		var gap := 16.0
		for segment in range(path.size() - 1):
			var from := path[segment]
			var to := path[segment + 1]
			var length := from.distance_to(to)
			if length < 1.0:
				continue
			var direction := (to - from) / length
			var travelled := 0.0
			while travelled < length:
				var run := minf(dash, length - travelled)
				var start := from + direction * travelled
				var end := start + direction * run
				specs.append(_dash_rect(start, end))
				travelled += dash + gap


## Axis-aligned 1 art-px thick dash between two points (both are integer world pixels).
static func _dash_rect(from: Vector2, to: Vector2) -> Dictionary:
	var thickness := 4.0
	var rect: Rect2
	if absf(to.x - from.x) >= absf(to.y - from.y):
		rect = Rect2(minf(from.x, to.x), from.y - thickness * 0.5, absf(to.x - from.x), thickness)
	else:
		rect = Rect2(from.x - thickness * 0.5, minf(from.y, to.y), thickness, absf(to.y - from.y))
	return {
		"kind": &"rect",
		"rect": rect,
		"color": Palette.METAL_1,
		"alpha": 0.32,
	}


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
		specs.append(
			{
				"kind": &"rect",
				"rect": _rect_world(spot),
				"color": Palette.METAL_1,
				"alpha": 0.16,
			}
		)


## Painted delivery zone around the chute: the one place the floor says "put it here".
static func _floor_chute_zone(specs: Array[Dictionary]) -> void:
	var chute := RoomBuilder.layout_rect("chute")
	var center := chute.get_center()
	specs.append(
		{
			"kind": &"arc",
			"center": center,
			"radius": 88.0,
			"from": 0.0,
			"to": TAU,
			"segments": 48,
			"color": Palette.CLEAN_GREEN,
			"alpha": 0.20,
			"width": 4.0,
		}
	)
	specs.append(
		{
			"kind": &"arc",
			"center": center,
			"radius": 104.0,
			"from": 0.0,
			"to": TAU,
			"segments": 48,
			"color": Palette.METAL_1,
			"alpha": 0.14,
			"width": 4.0,
		}
	)
	for index in range(8):
		var angle := TAU * float(index) / 8.0 + PI / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		var from := center + direction * 88.0
		var to := center + direction * 108.0
		specs.append(
			{
				"kind": &"line",
				"points": PackedVector2Array([from, to]),
				"color": Palette.CLEAN_GREEN,
				"alpha": 0.22,
				"width": 4.0,
			}
		)


## Grounding shadows: one flat ellipse under every machine and a lip under each belt.
static func _floor_contact_shadows(specs: Array[Dictionary]) -> void:
	for washer: Dictionary in RoomBuilder.layout().get("washers", []):
		var rect := RoomBuilder.rect_world(washer)
		# Cast shadow: light comes from the top-left, so the shadow falls bottom-right.
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(rect.position.x + 12.0, rect.end.y - 8.0, rect.size.x, 16.0),
				"color": Palette.SPACE_VOID,
				"alpha": 0.30,
			}
		)
		specs.append(_shadow_ellipse(Vector2(rect.get_center().x, rect.end.y - 4.0), rect.size.x * 0.46, 4.0))
	var chute := RoomBuilder.layout_rect("chute")
	specs.append(_shadow_ellipse(Vector2(chute.get_center().x, chute.end.y - 4.0), 26.0, 4.0))
	for belt: Dictionary in RoomBuilder.layout().get("belts", []):
		var rect := RoomBuilder.rect_world(belt)
		if rect.size.x >= rect.size.y:
			specs.append(
				{
					"kind": &"rect",
					"rect": Rect2(rect.position.x, rect.end.y, rect.size.x, 8.0),
					"color": Palette.SPACE_VOID,
					"alpha": 0.35,
				}
			)
		else:
			specs.append(
				{
					"kind": &"rect",
					"rect": Rect2(rect.end.x, rect.position.y, 8.0, rect.size.y),
					"color": Palette.SPACE_VOID,
					"alpha": 0.35,
				}
			)


## Flat 16-vertex shadow ellipse (never a smooth gradient: this is pixel art).
static func _shadow_ellipse(center: Vector2, radius_x: float, radius_y: float) -> Dictionary:
	var points := PackedVector2Array()
	for vertex in range(16):
		var angle := TAU * float(vertex) / 16.0
		points.append(_snap(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)))
	return {"kind": &"poly", "points": points, "color": Palette.SPACE_VOID, "alpha": 0.42}


## Soft contact shadow where the floor meets the walls: three stepped strips per wall.
static func _floor_wall_shadow(specs: Array[Dictionary]) -> void:
	var band := [0.28, 0.16, 0.07]
	for step in range(band.size()):
		var inset := 32.0 + float(step) * 8.0
		var alpha: float = band[step]
		var color := Palette.SPACE_VOID
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(32.0, inset, 1216.0, 8.0),
				"color": color,
				"alpha": alpha,
			}
		)
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(32.0, 688.0 - inset, 1216.0, 8.0),
				"color": color,
				"alpha": alpha,
			}
		)
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(inset, 32.0, 8.0, 656.0),
				"color": color,
				"alpha": alpha,
			}
		)
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(1248.0 - inset, 32.0, 8.0, 656.0),
				"color": color,
				"alpha": alpha,
			}
		)


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
	var smear_center := Vector2(150, 100) + Vector2(rng.randi_range(-8, 8), rng.randi_range(-6, 6))
	specs.append(
		{
			"kind": &"rect",
			"rect": _rect_world(Rect2(smear_center, Vector2(rng.randi_range(6, 12), 2))),
			"color": Palette.METAL_0,
			"alpha": 0.12,
		}
	)
	return specs


static func _dressing_cables(specs: Array[Dictionary]) -> void:
	var runs := [
		[Vector2(36, 44), Vector2(20, 44), Vector2(20, 16)],
		[Vector2(284, 44), Vector2(300, 44), Vector2(300, 16)],
		[Vector2(36, 110), Vector2(20, 110), Vector2(20, 150)],
		[Vector2(284, 110), Vector2(300, 110), Vector2(300, 150)],
	]
	for run: Array in runs:
		var points := PackedVector2Array()
		for point: Vector2 in run:
			points.append(_snap(point * float(Config.ART_SCALE)))
		specs.append(
			{"kind": &"line", "points": points, "color": Palette.METAL_0, "alpha": 0.75, "width": 4.0}
		)
		var plug := points[points.size() - 1]
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(plug.x - 8.0, plug.y - 8.0, 16.0, 16.0),
				"color": Palette.METAL_2,
				"alpha": 0.85,
			}
		)


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
	var valves := [Vector2(20, 30), Vector2(300, 30)]
	for center: Vector2 in valves:
		specs.append(
			{
				"kind": &"valve",
				"center": _snap(center * float(Config.ART_SCALE)),
				"radius": 9.0 * float(Config.ART_SCALE),
				"color": Palette.METAL_2,
			}
		)


## Panel seams and bolts along the two side walls: density at the edges, calm in the lane.
static func _dressing_walls(specs: Array[Dictionary]) -> void:
	for y in range(48, 700, 96):
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(2.0, float(y), 28.0, 2.0),
				"color": Palette.METAL_0,
				"alpha": 0.45,
			}
		)
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(1250.0, float(y), 28.0, 2.0),
				"color": Palette.METAL_0,
				"alpha": 0.45,
			}
		)
	for y in range(88, 700, 192):
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(8.0, float(y), 4.0, 4.0),
				"color": Palette.METAL_1,
				"alpha": 0.5,
			}
		)
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(1268.0, float(y), 4.0, 4.0),
				"color": Palette.METAL_1,
				"alpha": 0.5,
			}
		)


static func _dressing_drain(specs: Array[Dictionary]) -> void:
	specs.append({"kind": &"drain", "rect": _rect_world(Rect2(286, 150, 20, 12))})


# --- individual dressing painters -------------------------------------------


func _draw_vent(rect: Rect2, color: Color) -> void:
	draw_rect(rect, Color(Palette.SPACE_VOID.r, Palette.SPACE_VOID.g, Palette.SPACE_VOID.b, 0.55))
	var tint := Color(color.r, color.g, color.b, 0.7)
	var slat := rect.size.y / 4.0
	for index in range(3):
		var y := rect.position.y + slat * (0.35 + float(index))
		draw_rect(Rect2(rect.position.x + 4.0, roundf(y), rect.size.x - 8.0, 4.0), tint)


func _draw_valve(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, Color(Palette.SPACE_DEEP.r, Palette.SPACE_DEEP.g, Palette.SPACE_DEEP.b, 0.95))
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
	var pitch := 5.0 * pixel
	var origin := Vector2(rect.position.x + 6.0, rect.position.y + 6.0)
	var ink := Color(Palette.YEL_3.r, Palette.YEL_3.g, Palette.YEL_3.b, 0.92)
	for index in range(text.length()):
		var glyph: Array = GLYPHS.get(text.substr(index, 1), [])
		if glyph.is_empty():
			continue
		for row in range(glyph.size()):
			var bits: String = glyph[row]
			for column in range(bits.length()):
				if bits[column] != "1":
					continue
				draw_rect(
					Rect2(
						origin + Vector2(float(column) * pixel + float(index) * pitch, float(row) * pixel),
						Vector2(pixel, pixel)
					),
					ink
				)


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
	draw_colored_polygon(points, Color(Palette.METAL_1.r, Palette.METAL_1.g, Palette.METAL_1.b, 0.95))
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
	for index in range(3):
		var offset := Vector2(float(index) * 4.0 - 4.0, float(index) * 8.0)
		var box := Rect2(rect.position + offset, Vector2(rect.size.x - 8.0, 8.0))
		draw_rect(box, Color(colors[index].r, colors[index].g, colors[index].b, 0.9))
		draw_rect(
			Rect2(box.position, Vector2(box.size.x, 2.0)),
			Color(Palette.METAL_3.r, Palette.METAL_3.g, Palette.METAL_3.b, 0.6)
		)


# --- foreground (§3.6.6) ----------------------------------------------------


## Deterministic foreground list: vignette bands, ceiling pipes, lamp cords and dust.
static func foreground_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	_foreground_vignette(specs)
	_foreground_pipes(specs)
	_foreground_lamps(specs)
	_foreground_dust(specs)
	return specs


static func _foreground_vignette(specs: Array[Dictionary]) -> void:
	# Four margin bands; the play lane (x 120…1160, y 120…600) stays completely clear.
	var steps := 12
	var band := 120.0
	for step in range(steps):
		var fraction := float(step) / float(steps)
		var alpha := 0.48 * (1.0 - fraction)
		var thickness := band / float(steps)
		var offset := float(step) * thickness
		var color := Palette.SPACE_VOID
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(0.0, offset, 1280.0, thickness),
				"color": color,
				"alpha": alpha,
			}
		)
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(0.0, 720.0 - offset - thickness, 1280.0, thickness),
				"color": color,
				"alpha": alpha,
			}
		)
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(offset, band, thickness, 480.0),
				"color": color,
				"alpha": alpha,
			}
		)
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(1280.0 - offset - thickness, band, thickness, 480.0),
				"color": color,
				"alpha": alpha,
			}
		)


static func _foreground_pipes(specs: Array[Dictionary]) -> void:
	specs.append(
		{
			"kind": &"rect",
			"rect": Rect2(0.0, 2.0, 1280.0, 8.0),
			"color": Palette.SPACE_MID,
			"alpha": 1.0,
		}
	)
	specs.append(
		{
			"kind": &"rect",
			"rect": Rect2(0.0, 2.0, 1280.0, 2.0),
			"color": Palette.METAL_0,
			"alpha": 0.9,
		}
	)
	specs.append(
		{
			"kind": &"rect",
			"rect": Rect2(0.0, 14.0, 1280.0, 6.0),
			"color": Palette.SPACE_MID,
			"alpha": 1.0,
		}
	)
	specs.append(
		{
			"kind": &"rect",
			"rect": Rect2(0.0, 14.0, 1280.0, 2.0),
			"color": Palette.METAL_0,
			"alpha": 0.7,
		}
	)
	for x in [180.0, 520.0, 860.0, 1180.0]:
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(x, 0.0, 12.0, 22.0),
				"color": Palette.METAL_0,
				"alpha": 0.95,
			}
		)


static func _foreground_lamps(specs: Array[Dictionary]) -> void:
	for x in [320.0, 980.0]:
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(x - 2.0, 24.0, 4.0, 62.0),
				"color": Palette.SPACE_VOID,
				"alpha": 0.85,
			}
		)
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(x - 12.0, 82.0, 24.0, 8.0),
				"color": Palette.METAL_1,
				"alpha": 0.95,
			}
		)
		# Three flat rings stand in for a soft glow without a shader or a big quad.
		var rings := [[40.0, 0.07], [26.0, 0.09], [12.0, 0.14]]
		for ring: Array in rings:
			specs.append(
				{
					"kind": &"arc",
					"center": Vector2(x, 92.0),
					"radius": float(ring[0]),
					"from": 0.0,
					"to": TAU,
					"segments": 20,
					"color": Palette.YEL_3,
					"alpha": float(ring[1]),
					"width": 8.0,
				}
			)


static func _foreground_dust(specs: Array[Dictionary]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	for index in range(150):
		var x := float(rng.randi_range(1, 318)) * float(Config.ART_SCALE)
		var y := float(rng.randi_range(1, 178)) * float(Config.ART_SCALE)
		specs.append(
			{
				"kind": &"rect",
				"rect": Rect2(x, y, 4.0, 4.0),
				"color": Palette.METAL_3,
				"alpha": 0.03 if index % 3 != 0 else 0.05,
			}
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
	var washers := {}
	for washer: Dictionary in RoomBuilder.layout().get("washers", []):
		var washer_id := String(washer.get("id", "washer"))
		var rect := RoomBuilder.rect_world(washer)
		var sprite := AnimatedSprite2D.new()
		sprite.name = washer_id
		sprite.position = Vector2(rect.get_center().x, rect.end.y)
		sprite.z_index = 0
		machines.add_child(sprite)
		if SpriteSheet.configure(sprite, "mach_washer", &"idle"):
			sprite.speed_scale = 1.0
		else:
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

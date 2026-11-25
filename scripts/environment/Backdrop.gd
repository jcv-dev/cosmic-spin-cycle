class_name Backdrop
extends Node2D
## Deep-space backdrop behind the laundromat floor: starfield, two nebula bands and a
## planet limb in the top-right corner (UX_BIBLE §3.4/§3.6).
##
## Everything is generated in code — no raster asset is added — and cached in `static var`
## so rebuilding the room in the same session reuses one texture instead of leaking a new
## one. The star sheet is one 320 art-px tile repeated twice: the drift wraps at a whole
## tile, so the loop point is invisible and no seam is ever drawn. Positions are rounded to
## whole world pixels, which is the pixel-integrity rule for this layer.

## Star tile width in art pixels (the room canvas width).
const TILE_ART_W := 320
## Star sheet = two identical tiles, so the drift can wrap without a visible jump.
const SHEET_ART_W := 640
## Room canvas height in art pixels.
const SHEET_ART_H := 180
## Number of stars in one tile (UX_BIBLE §4.2 asks for ~90).
const STAR_COUNT := 90
## Stars never sit on the tile border so the repeated half has no clipped pixel.
const STAR_MARGIN := 2
## Backdrop drift in world pixels per second (UX_BIBLE §3.4: 1–3 px/s).
const DRIFT_PX_S := 2.0
## One room width of travel; the sheet is two tiles wide, so this wraps invisibly.
const DRIFT_WRAP := 1280.0
## Deterministic seed for the star layout.
const SEED := 522023

## Star colours by brightness class (palette ramps only).
const STAR_COLORS := [Palette.METAL_1, Palette.METAL_2, Palette.METAL_3]

## First nebula band: a wide diagonal wash that runs off every screen edge, so only its
## soft interior is visible and no hard polygon border is ever on screen.
const BAND_A := [
	Vector2(-320.0, -120.0),
	Vector2(1600.0, 40.0),
	Vector2(1600.0, 460.0),
	Vector2(-320.0, 300.0),
]

## Third band: a low warm haze under the south belt, the only plum in the room.
const BAND_C := [
	Vector2(-320.0, 640.0),
	Vector2(1600.0, 520.0),
	Vector2(1600.0, 900.0),
	Vector2(-320.0, 980.0),
]

## Second band, crossing the first at a shallower angle.
const BAND_B := [
	Vector2(-320.0, 430.0),
	Vector2(1600.0, 210.0),
	Vector2(1600.0, 540.0),
	Vector2(-320.0, 760.0),
]

static var _star_texture: ImageTexture = null

var _stars: Sprite2D
var _drift := 0.0


## Adds the backdrop under `root` (z −95) and returns the node.
static func build(root: Node2D) -> Backdrop:
	var backdrop := Backdrop.new()
	backdrop.name = "Backdrop"
	backdrop.z_index = -95
	root.add_child(backdrop)
	backdrop._setup()
	return backdrop


## Generated 640×180 star sheet (two seamless 320-wide tiles). Cached for the session.
static func star_texture() -> ImageTexture:
	if _star_texture != null:
		return _star_texture
	var image := generate_stars(TILE_ART_W, SHEET_ART_H, STAR_COUNT, SEED)
	var sheet := Image.create(SHEET_ART_W, SHEET_ART_H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.0, 0.0, 0.0, 0.0))
	sheet.blit_rect(image, Rect2i(0, 0, TILE_ART_W, SHEET_ART_H), Vector2i.ZERO)
	sheet.blit_rect(image, Rect2i(0, 0, TILE_ART_W, SHEET_ART_H), Vector2i(TILE_ART_W, 0))
	_star_texture = ImageTexture.create_from_image(sheet)
	return _star_texture


## Deterministic RGBA starfield `w × h` art pixels, transparent between the stars.
static func generate_stars(w: int, h: int, count: int, seed_value: int) -> Image:
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in range(count):
		var x := rng.randi_range(STAR_MARGIN, w - STAR_MARGIN - 1)
		var y := rng.randi_range(STAR_MARGIN, h - STAR_MARGIN - 1)
		# Three brightness classes: most stars are dim, a handful are highlights.
		var class_index := 0
		var roll := rng.randf()
		if roll > 0.82:
			class_index = 2
		elif roll > 0.55:
			class_index = 1
		var color: Color = STAR_COLORS[class_index]
		image.set_pixel(x, y, color)
		# The brightest stars get a 1 px cross so the field does not read as noise.
		if class_index == 2 and index % 3 == 0:
			if x + 1 < w - STAR_MARGIN:
				image.set_pixel(x + 1, y, color * Color(1.0, 1.0, 1.0, 0.55))
			if y + 1 < h - STAR_MARGIN:
				image.set_pixel(x, y + 1, color * Color(1.0, 1.0, 1.0, 0.55))
	return image


## Drops the cached sheet (tests only).
static func clear_cache() -> void:
	_star_texture = null


func _setup() -> void:
	_stars = Sprite2D.new()
	_stars.name = "Stars"
	_stars.texture = star_texture()
	_stars.centered = false
	_stars.scale = Vector2.ONE * float(Config.ART_SCALE)
	_stars.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stars.position = Vector2.ZERO
	add_child(_stars)
	add_child(_make_band(BAND_A, Palette.BLUE_1, 0.18))
	add_child(_make_band(BAND_B, Palette.SPACE_HAZE, 0.14))
	add_child(_make_band(BAND_C, Palette.FUNK_PLUM, 0.07))
	add_child(_make_limb())


func _process(delta: float) -> void:
	if _stars == null:
		return
	_drift = fposmod(_drift + DRIFT_PX_S * delta, DRIFT_WRAP)
	# Whole pixels only: a fractional star sprite shimmers on llvmpipe.
	_stars.position.x = -float(roundi(_drift))


# --- nebula bands ------------------------------------------------------------


func _make_band(points: Array, color: Color, alpha: float) -> Node2D:
	var band := BandLayer.new()
	band.name = "Nebula"
	band.setup(PackedVector2Array(points), color, alpha)
	return band


# --- planet limb -------------------------------------------------------------


func _make_limb() -> Node2D:
	var limb := PlanetLimb.new()
	limb.name = "PlanetLimb"
	return limb


## Flat alpha nebula polygon. Dither-free by design (UX_BIBLE §3.4).
class BandLayer:
	extends Node2D

	var _points := PackedVector2Array()
	var _color := Color.WHITE
	var _alpha := 0.1

	func setup(points: PackedVector2Array, color: Color, alpha: float) -> void:
		_points = points
		_color = color
		_alpha = alpha
		queue_redraw()

	func _draw() -> void:
		draw_colored_polygon(_points, Color(_color.r, _color.g, _color.b, _alpha))


## A distant planet in the top-right: three concentric rim arcs plus a 5 % body tint. Only
## the limb is drawn strongly so the play field keeps its contrast.
class PlanetLimb:
	extends Node2D

	const CENTER := Vector2(1380.0, -560.0)
	const RADIUS := 720.0

	func _draw() -> void:
		draw_circle(
			CENTER, RADIUS, Color(Palette.BLUE_1.r, Palette.BLUE_1.g, Palette.BLUE_1.b, 0.07)
		)
		var rims := [
			[0.0, 0.30, 6.0],
			[-12.0, 0.16, 8.0],
			[-26.0, 0.08, 10.0],
			[-44.0, 0.05, 12.0],
		]
		for rim: Array in rims:
			var radius: float = RADIUS + float(rim[0])
			var alpha: float = float(rim[1])
			var width: float = float(rim[2])
			var color := Color(Palette.BLUE_3.r, Palette.BLUE_3.g, Palette.BLUE_3.b, alpha)
			draw_arc(CENTER, radius, 0.0, TAU, 96, color, width, false)

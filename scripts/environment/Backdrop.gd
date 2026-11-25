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

static var _star_texture: ImageTexture = null
static var _nebula_texture: ImageTexture = null
static var _nebula_tile: Image = null

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


## Generated 640×180 backdrop sheet (two seamless 320-wide tiles, stars over the nebula).
## One texture means the whole backdrop is a single blended quad; cached for the session.
static func star_texture() -> ImageTexture:
	if _star_texture != null:
		return _star_texture
	var tile := nebula_tile()
	var stars := generate_stars(TILE_ART_W, SHEET_ART_H, STAR_COUNT, SEED)
	tile.blend_rect(stars, Rect2i(0, 0, TILE_ART_W, SHEET_ART_H), Vector2i.ZERO)
	var sheet := Image.create(SHEET_ART_W, SHEET_ART_H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.0, 0.0, 0.0, 0.0))
	sheet.blit_rect(tile, Rect2i(0, 0, TILE_ART_W, SHEET_ART_H), Vector2i.ZERO)
	sheet.blit_rect(tile, Rect2i(0, 0, TILE_ART_W, SHEET_ART_H), Vector2i(TILE_ART_W, 0))
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
	_nebula_texture = null
	_nebula_tile = null


## Generated 320×180 nebula image: two diagonal bands, a low plum haze and the planet limb,
## composited per art pixel. Baking it (instead of four large polygons) is what keeps the
## backdrop at one blended quad.
static func nebula_tile() -> Image:
	if _nebula_tile != null:
		return _nebula_tile
	var image := Image.create(TILE_ART_W, SHEET_ART_H, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var bands := [
		[Palette.BLUE_1, 0.18, 0.05, 15.0, 75.0],
		[Palette.SPACE_HAZE, 0.13, -0.06, 150.0, 65.0],
		[Palette.FUNK_PLUM, 0.07, 0.02, 200.0, 50.0],
	]
	for y in range(SHEET_ART_H):
		for x in range(TILE_ART_W):
			var colour := Color(0.0, 0.0, 0.0, 0.0)
			for band: Array in bands:
				var tint: Color = band[0]
				var peak: float = band[1]
				var slope: float = band[2]
				var offset: float = band[3]
				var reach: float = band[4]
				var centre := slope * float(x) + offset
				var alpha := peak * clampf(1.0 - absf(float(y) - centre) / reach, 0.0, 1.0)
				if alpha > 0.0:
					colour = _blend(colour, tint, alpha)
			var limb := _planet_limb_alpha(x, y)
			if limb > 0.0:
				colour = _blend(colour, Palette.BLUE_3, limb)
			image.set_pixel(x, y, colour)
	_nebula_tile = image
	return _nebula_tile


## Nebula-only sheet (two tiles) for previews and tests.
static func nebula_texture() -> ImageTexture:
	if _nebula_texture != null:
		return _nebula_texture
	var tile := nebula_tile()
	var sheet := Image.create(SHEET_ART_W, SHEET_ART_H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.0, 0.0, 0.0, 0.0))
	sheet.blit_rect(tile, Rect2i(0, 0, TILE_ART_W, SHEET_ART_H), Vector2i.ZERO)
	sheet.blit_rect(tile, Rect2i(0, 0, TILE_ART_W, SHEET_ART_H), Vector2i(TILE_ART_W, 0))
	_nebula_texture = ImageTexture.create_from_image(sheet)
	return _nebula_texture


## Alpha of the planet limb at one art pixel: a body tint plus three rim rings.
static func _planet_limb_alpha(x: int, y: int) -> float:
	var centre := Vector2(345.0, -140.0)
	var radius := 180.0
	var delta := Vector2(float(x), float(y)) - centre
	var distance := delta.length()
	if distance > radius + 12.0:
		return 0.0
	var rim := radius - distance
	if rim >= 0.0 and rim < 1.5:
		return 0.30
	if rim < 0.0 and rim > -1.5:
		return 0.12
	if rim < 0.0 and rim > -3.0:
		return 0.06
	if rim >= 1.5:
		# Planet body: a dim disc so the rim reads as a limb instead of a scratch.
		return 0.055
	return 0.0


## Straight-alpha "source over" onto a premultiplied-by-hand pixel colour.
static func _blend(destination: Color, source: Color, alpha: float) -> Color:
	var out_alpha := alpha + destination.a * (1.0 - alpha)
	if out_alpha <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var red := (source.r * alpha + destination.r * destination.a * (1.0 - alpha)) / out_alpha
	var green := (source.g * alpha + destination.g * destination.a * (1.0 - alpha)) / out_alpha
	var blue := (source.b * alpha + destination.b * destination.a * (1.0 - alpha)) / out_alpha
	return Color(red, green, blue, out_alpha)


func _setup() -> void:
	_stars = Sprite2D.new()
	_stars.name = "Stars"
	_stars.texture = star_texture()
	_stars.centered = false
	_stars.scale = Vector2.ONE * float(Config.ART_SCALE)
	_stars.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stars.position = Vector2.ZERO
	add_child(_stars)
	# Stars and nebula share one drifting sheet (both are "infinitely far" parallax).


func _process(delta: float) -> void:
	if _stars == null:
		return
	_drift = fposmod(_drift + DRIFT_PX_S * delta, DRIFT_WRAP)
	# Whole pixels only: a fractional star sprite shimmers on llvmpipe.
	_stars.position.x = -float(roundi(_drift))

# --- nebula bands ------------------------------------------------------------

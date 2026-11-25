class_name HudGlyphs
extends RefCounted
## Shared glyph and geometry language for the HUD plaques and the world-space layer.
##
## Colour is never the only channel (docs/UX_BIBLE.md §11): every colour-coded state also
## carries a shape. Red is a triangle, blue a circle, yellow a square; the three patterns reuse
## the bar / ring / dots trio. Both scripts/ui/HUD.gd and scripts/ui/DiegeticLayer.gd draw from
## here, so "the red washer" and "a red ringed item" look the same in every surface.
##
## Everything is flat, integer-snapped and antialias-free: this is a 1280×720 pixel-art game
## rendered with Nearest filtering, so a half-pixel line shimmers.

## Arc resolution for rings. 32 segments is smooth at the radii we use (≤ 70 px).
const RING_SEGMENTS := 32
const MIN_WIDTH := 1.0
const DASH := 6.0
const GAP := 4.0
const CHIP_BORDER := 1.0

const COLOR_KEYS := {
	&"red": &"ROJO",
	&"blue": &"AZUL",
	&"yellow": &"AMARILLO",
	&"wild": &"CUALQUIERA",
}
const PATTERN_KEYS := {
	&"solid": &"LISO",
	&"ringed": &"ANILLADO",
	&"spotted": &"MOTEADO",
	&"wild": &"CUALQUIERA",
}


## The bright ramp colour that identifies a washer requirement or an item.
static func ramp_color(color_name: StringName) -> Color:
	match color_name:
		&"red":
			return Palette.RED_3
		&"blue":
			return Palette.BLUE_3
		&"yellow":
			return Palette.YEL_3
		_:
			return Palette.METAL_3


## Body colour of an item (the `*_2` ramp step, per docs/UX_BIBLE.md §3.3).
static func body_color(color_name: StringName) -> Color:
	match color_name:
		&"red":
			return Palette.RED_2
		&"blue":
			return Palette.BLUE_2
		&"yellow":
			return Palette.YEL_2
		_:
			return Palette.METAL_2


## Spanish label for a colour requirement ("ROJO"), already translated.
static func color_text(color_name: StringName) -> String:
	var key: StringName = COLOR_KEYS.get(color_name, &"CUALQUIERA")
	return String(TranslationServer.translate(key))


## Spanish label for a pattern requirement ("ANILLADO"), already translated.
static func pattern_text(pattern: StringName) -> String:
	var key: StringName = PATTERN_KEYS.get(pattern, &"CUALQUIERA")
	return String(TranslationServer.translate(key))


# --- Primitives -------------------------------------------------------------


## Filled diamond — the HUD's colour-blind shape for a numeric value.
static func draw_diamond(target: CanvasItem, center: Vector2, radius: float, ink: Color) -> void:
	var c := center.round()
	var r := maxf(radius, MIN_WIDTH)
	var points := PackedVector2Array(
		[
			c + Vector2(0.0, -r),
			c + Vector2(r, 0.0),
			c + Vector2(0.0, r),
			c + Vector2(-r, 0.0),
		]
	)
	target.draw_colored_polygon(points, ink)


## Filled triangle pointing up (the red glyph).
static func draw_triangle(target: CanvasItem, center: Vector2, half: float, ink: Color) -> void:
	var c := center.round()
	var h := maxf(half, MIN_WIDTH)
	var points := PackedVector2Array([c + Vector2(-h, h), c + Vector2(h, h), c + Vector2(0.0, -h)])
	target.draw_colored_polygon(points, ink)


## Filled square (the yellow glyph).
static func draw_square(target: CanvasItem, center: Vector2, half: float, ink: Color) -> void:
	var h := maxf(half, MIN_WIDTH)
	var rect := Rect2((center - Vector2(h, h)).round(), Vector2(h, h) * 2.0)
	target.draw_rect(rect, ink)


## Circle outline. `width` is in pixels.
static func draw_ring(
	target: CanvasItem, center: Vector2, radius: float, ink: Color, width: float = 2.0
) -> void:
	target.draw_arc(
		center.round(),
		maxf(radius, MIN_WIDTH),
		0.0,
		TAU,
		RING_SEGMENTS,
		ink,
		maxf(width, MIN_WIDTH)
	)


## A crosshair: two axis-aligned strokes, never diagonal (diagonals alias badly at 1 px).
static func draw_cross(
	target: CanvasItem, center: Vector2, arm: float, ink: Color, width: float = 2.0
) -> void:
	var c := center.round()
	target.draw_line(c - Vector2(arm, 0.0), c + Vector2(arm, 0.0), ink, width)
	target.draw_line(c - Vector2(0.0, arm), c + Vector2(0.0, arm), ink, width)


## Four L brackets around `center` — the "this is a valid destination" reticle state.
static func draw_brackets(
	target: CanvasItem, center: Vector2, radius: float, ink: Color, width: float = 2.0
) -> void:
	var c := center.round()
	var r := maxf(radius, MIN_WIDTH)
	var leg := maxf(r * 0.42, 3.0)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := c + Vector2(sx * r, sy * r)
			target.draw_line(corner, corner - Vector2(sx * leg, 0.0), ink, width)
			target.draw_line(corner, corner - Vector2(0.0, sy * leg), ink, width)


## An X inside a ring — the "wrong destination" reticle state.
static func draw_reject(
	target: CanvasItem, center: Vector2, radius: float, ink: Color, width: float = 2.0
) -> void:
	var c := center.round()
	var r := maxf(radius, MIN_WIDTH)
	var arm := r * 0.55
	target.draw_line(c + Vector2(-arm, -arm), c + Vector2(arm, arm), ink, width)
	target.draw_line(c + Vector2(-arm, arm), c + Vector2(arm, -arm), ink, width)


## A downward chevron, used to point from Pip toward the chute.
static func draw_chevron(
	target: CanvasItem, tip: Vector2, size: float, ink: Color, width: float = 2.0
) -> void:
	var c := tip.round()
	var s := maxf(size, 2.0)
	target.draw_line(c, c + Vector2(-s, -s), ink, width)
	target.draw_line(c, c + Vector2(s, -s), ink, width)


## Dashed straight line. Used for the tracer and the turbulence path.
static func draw_dashed_line(
	target: CanvasItem,
	from: Vector2,
	to: Vector2,
	ink: Color,
	dash: float = DASH,
	gap: float = GAP,
	width: float = 2.0
) -> void:
	var span := to - from
	var length := span.length()
	if length <= 0.5:
		return
	var direction := span / length
	var step := maxf(dash + gap, 1.0)
	var travel := 0.0
	while travel < length:
		var head := from + direction * travel
		var tail := from + direction * minf(travel + maxf(dash, 1.0), length)
		target.draw_line(head.round(), tail.round(), ink, width)
		travel += step


## A flat label chip: `space_void` fill + 1 px border, both snapped to whole pixels.
static func draw_chip(target: CanvasItem, rect: Rect2, fill_alpha: float, border: Color) -> void:
	var box := Rect2(rect.position.round(), rect.size.round())
	target.draw_rect(box, Color(Palette.SPACE_VOID, fill_alpha))
	target.draw_rect(box, border, false, CHIP_BORDER)


# --- Composite glyphs -------------------------------------------------------


## Colour glyph + tint: ▲ red, ● blue, ■ yellow, ◆ wild. The body is always drawn in a
## readable metal so the shape survives a desaturated screenshot.
static func draw_color_glyph(
	target: CanvasItem, center: Vector2, half: float, color_name: StringName
) -> void:
	var ink := ramp_color(color_name)
	match color_name:
		&"red":
			draw_triangle(target, center, half, ink)
		&"yellow":
			draw_square(target, center, half, ink)
		&"blue":
			target.draw_circle(center.round(), maxf(half, MIN_WIDTH), ink)
		_:
			draw_diamond(target, center, half, ink)


## Pattern glyph: LISO = one bar, ANILLADO = one ring, MOTEADO = three dots.
static func draw_pattern_glyph(
	target: CanvasItem, center: Vector2, half: float, pattern: StringName
) -> void:
	var c := center.round()
	var h := maxf(half, MIN_WIDTH)
	match pattern:
		&"ringed":
			draw_ring(target, c, h, Palette.METAL_3, maxf(h * 0.45, MIN_WIDTH))
		&"spotted":
			target.draw_circle(c + Vector2(-h * 0.7, 0.0), h * 0.3, Palette.METAL_3)
			target.draw_circle(c, h * 0.3, Palette.METAL_3)
			target.draw_circle(c + Vector2(h * 0.7, 0.0), h * 0.3, Palette.METAL_3)
		_:
			target.draw_rect(
				Rect2(c - Vector2(h, h * 0.22), Vector2(h, h * 0.44) * 2.0), Palette.METAL_3
			)

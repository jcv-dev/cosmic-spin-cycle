class_name WasherFX
extends RefCounted
## Procedural, asset-free feedback visuals shared by [CosmicWasher] and [DeliveryChute].
##
## Every class here is a tiny `Node2D` drawn with `_draw()`: the washer hologram, the drum
## ring/turbulence gauge, the floor light pool, the fallback machine, the stability chips and
## the floating text pop. Keeping them out of the gameplay scripts leaves those inside the
## linter's per-file budget and keeps the measured feedback timings in one place.

## Chip plaque (palette `space_void`, 85 %). The chip carries a glyph + number + colour.
const CHIP_BACKGROUND_ALPHA := 0.85
const CHIP_FONT_SIZE := 12


## Hologram: 128x56 plaque above the machine with one unambiguous requirement glyph.
##
## The sheet's `solid` icon is a cloud and its `spotted` icon is three plus signs (players
## read "+" as add/positive), so those two are drawn procedurally as a filled square and a
## dotted square. `ringed` keeps the shipped ring and the colours keep their triangle /
## circle / square glyphs; `wild` is a cyan diamond.
class HoloPanel:
	extends Node2D

	const PANEL := Rect2(-64.0, -56.0, 128.0, 56.0)
	const GLYPH := 36.0

	var requirement: StringName = &"wild"
	var label_text := ""
	var tint: Color = Palette.METAL_3
	var flash := 0.0
	var matched := false

	func _draw() -> void:
		draw_rect(PANEL, Color(Palette.SPACE_DEEP, 0.86), true)
		draw_rect(Rect2(-62.0, -54.0, 124.0, 52.0), Color(Palette.SPACE_HAZE, 0.35), true)
		var border := Palette.FUNK_CYAN if matched else tint
		draw_rect(PANEL, Color(border, 0.95), false, 3.0 if matched else 2.0)
		var tick := Color(Palette.METAL_4, 0.9)
		draw_rect(Rect2(-64.0, -56.0, 8.0, 2.0), tick, true)
		draw_rect(Rect2(-64.0, -56.0, 2.0, 8.0), tick, true)
		draw_rect(Rect2(56.0, -2.0, 8.0, 2.0), tick, true)
		draw_rect(Rect2(62.0, -10.0, 2.0, 8.0), tick, true)
		_draw_glyph()
		var font := Fonts.pixel_font()
		var size := 14
		if font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > 120.0:
			size = 9
		var width := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(
			font,
			Vector2(-width * 0.5, -5.0),
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			size,
			Palette.METAL_4
		)

	func _draw_glyph() -> void:
		var at := Vector2(-GLYPH * 0.5, -54.0)
		if _is_colour(requirement):
			var texture := SpriteSheet.frame_texture("ui_holo_icons", requirement, 0)
			if texture != null:
				draw_texture_rect(texture, Rect2(at, Vector2(GLYPH, GLYPH)), false)
				return
			_draw_square(at)
		elif requirement == &"solid":
			_draw_square(at)
		elif requirement == &"ringed":
			var ring := SpriteSheet.frame_texture("ui_holo_icons", &"ringed", 0)
			if ring != null:
				draw_texture_rect(ring, Rect2(at, Vector2(GLYPH, GLYPH)), false)
			else:
				_draw_ring(at)
		elif requirement == &"spotted":
			_draw_spotted(at)
		else:
			_draw_wild(at)

	func _draw_square(at: Vector2) -> void:
		draw_rect(Rect2(at, Vector2(GLYPH, GLYPH)), tint, true)
		draw_rect(Rect2(at, Vector2(GLYPH, GLYPH)), Palette.METAL_0, false, 2.0)

	func _draw_ring(at: Vector2) -> void:
		var center := at + Vector2(GLYPH * 0.5, GLYPH * 0.5)
		draw_circle(center, GLYPH * 0.5, tint)
		draw_circle(center, GLYPH * 0.28, Palette.SPACE_DEEP)

	func _draw_spotted(at: Vector2) -> void:
		_draw_square(at)
		for offset in [Vector2(9.0, 9.0), Vector2(22.0, 15.0), Vector2(13.0, 26.0)]:
			draw_rect(Rect2(at + offset, Vector2(6.0, 6.0)), Palette.SPACE_DEEP, true)

	func _draw_wild(at: Vector2) -> void:
		var center := at + Vector2(GLYPH * 0.5, GLYPH * 0.5)
		var radius := GLYPH * 0.5 - 2.0
		var diamond := PackedVector2Array(
			[
				center + Vector2(0.0, -radius),
				center + Vector2(radius, 0.0),
				center + Vector2(0.0, radius),
				center + Vector2(-radius, 0.0),
			]
		)
		draw_colored_polygon(diamond, Color(Palette.FUNK_CYAN, 0.25))
		for index in range(4):
			draw_line(diamond[index], diamond[(index + 1) % 4], Palette.FUNK_CYAN, 3.0, true)

	func _is_colour(value: StringName) -> bool:
		return value == &"red" or value == &"blue" or value == &"yellow"


## Gauge ring at the drum radius (54 px, 3 px thick) + the turbulence gauge.
##
## The ring is a gauge around the porthole, not a halo: it never crosses the cabinet.
class ProgressRing:
	extends Node2D

	## Porthole centre measured from the sheet: 30 art px below the frame top, pivot at 46.
	const DRUM_CENTER := Vector2(0.0, -64.0)
	## Just outside the 40 px glass, on the bezel: a gauge, not a halo.
	const DRUM_RADIUS := 52.0

	## 0 hidden, 1 wash/turbulent, 2 done, 3 repair.
	var mode := 0
	var progress := 0.0
	var ring_color: Color = Palette.FUNK_CYAN
	var turbulent := false
	var time_left := 0.0
	var time_total := 1.0
	## 1-frame porthole flash (wrong insert). `red_1` is decoration only; the chip carries
	## the meaning (glyph + number), never colour alone.
	var flash_color: Color = Palette.RED_1
	var flash_left := 0.0

	func _draw() -> void:
		var center := DRUM_CENTER
		if flash_left > 0.0:
			draw_circle(center, 38.0, Color(flash_color, 0.85))
		if turbulent:
			draw_circle(center, 38.0, Color(Palette.HAZARD_ORANGE, 0.16))
		if mode == 0 and not turbulent and flash_left <= 0.0:
			return
		draw_arc(center, DRUM_RADIUS, 0.0, TAU, 48, Color(Palette.SPACE_VOID, 0.7), 3.0, true)
		var start := -PI * 0.5
		var sweep := TAU * clampf(progress, 0.0, 1.0)
		if sweep > 0.001 and mode != 0:
			draw_arc(center, DRUM_RADIUS, start, start + sweep, 48, ring_color, 3.0, true)
			var tip := center + Vector2(cos(start + sweep), sin(start + sweep)) * DRUM_RADIUS
			draw_circle(tip, 3.0, ring_color)
		if mode == 2:
			draw_arc(center, DRUM_RADIUS + 2.0, 0.0, TAU, 48, Palette.CLEAN_GREEN, 1.0, true)
		if turbulent:
			_draw_turbulence_gauge(center)

	func _draw_turbulence_gauge(center: Vector2) -> void:
		var ratio := 0.0
		if time_total > 0.0:
			ratio = clampf(time_left / time_total, 0.0, 1.0)
		draw_arc(
			center,
			34.0,
			deg_to_rad(-150.0),
			deg_to_rad(-30.0),
			16,
			Color(Palette.SPACE_VOID, 0.6),
			8.0,
			true
		)
		for index in range(3):
			var threshold := 1.0 - float(index + 1) / 3.0
			var lit := ratio > threshold
			var color := Palette.HAZARD_ORANGE if lit else Palette.SPACE_HAZE
			var from := deg_to_rad(-150.0 + float(index) * 40.0)
			draw_arc(center, 34.0, from, from + deg_to_rad(34.0), 10, color, 4.0, true)
		var font := Fonts.pixel_font()
		var text := "%.1f" % time_left
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var at := center + Vector2(-width * 0.5, 18.0)
		draw_string_outline(
			font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 4, Palette.SPACE_VOID
		)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.HAZARD_ORANGE)


## Additive light pool on the floor; energy pulses on the beat.
class DrumGlow:
	extends Node2D

	var energy := 0.35
	var tint: Color = Palette.METAL_3

	func _draw() -> void:
		draw_set_transform(Vector2(0.0, 12.0), 0.0, Vector2(1.0, 0.34))
		for index in range(4):
			var radius := 120.0 - float(index) * 24.0
			var alpha := (0.05 + 0.05 * energy) * (1.0 + float(index) * 0.35)
			draw_circle(Vector2.ZERO, radius, Color(tint, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Procedural stand-in machine, drawn only when `mach_washer` is missing.
class FallbackBody:
	extends Node2D

	func _draw() -> void:
		draw_rect(Rect2(0.0, 0.0, 192.0, 184.0), Palette.METAL_0, true)
		draw_rect(Rect2(4.0, 4.0, 184.0, 176.0), Palette.METAL_2, true)
		draw_rect(Rect2(4.0, 4.0, 184.0, 12.0), Palette.METAL_3, true)
		draw_rect(Rect2(16.0, 22.0, 160.0, 26.0), Palette.SPACE_DEEP, true)
		draw_rect(Rect2(20.0, 26.0, 52.0, 8.0), Palette.FUNK_CYAN, true)
		for index in range(8):
			var color := Palette.YEL_2 if index % 2 == 0 else Palette.HAZARD_ORANGE
			draw_rect(Rect2(8.0 + float(index) * 22.0, 56.0, 12.0, 8.0), color, true)
		var drum := Vector2(96.0, 116.0)
		draw_circle(drum, 60.0, Palette.SPACE_VOID)
		draw_arc(drum, 60.0, 0.0, TAU, 40, Palette.METAL_1, 6.0, true)
		draw_circle(drum, 48.0, Palette.SPACE_DEEP)
		draw_arc(drum, 34.0, 0.5, 2.6, 24, Palette.FUNK_CYAN, 4.0, true)
		draw_circle(drum + Vector2(-14.0, -18.0), 5.0, Palette.BLUE_4)
		draw_rect(Rect2(150.0, 150.0, 30.0, 10.0), Palette.METAL_1, true)


## `-12` / `+3` stability chip: triangle glyph + number + colour, never colour alone.
##
## Two 4 px shakes over a lifetime shorter than `0.45 × T_beat` (190 ms at 142 BPM).
class FeedbackChip:
	extends Node2D

	var text := ""
	var gain := false
	var color: Color = Palette.HAZARD_ORANGE
	var lifetime := 0.18
	var age := 0.0
	var _start := Vector2.ZERO

	func _ready() -> void:
		_start = position

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		var t := clampf(age / lifetime, 0.0, 1.0)
		position = _start + Vector2(0.0, -10.0 * t)
		if not Settings.reduce_motion:
			position.x = _start.x + sin(age * TAU * 10.0) * 4.0 * (1.0 - t)
		queue_redraw()

	func _draw() -> void:
		var font := Fonts.pixel_font()
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT_SIZE).x
		var rect := Rect2(-width * 0.5 - 15.0, -11.0, width + 26.0, 20.0)
		draw_rect(rect, Color(Palette.SPACE_VOID, CHIP_BACKGROUND_ALPHA), true)
		draw_rect(rect, Color(color, 0.95), false, 1.0)
		var glyph := PackedVector2Array(
			[
				Vector2(rect.position.x + 5.0, -2.0),
				Vector2(rect.position.x + 13.0, -2.0),
				Vector2(rect.position.x + 9.0, -8.0 if gain else 4.0),
			]
		)
		draw_colored_polygon(glyph, color)
		draw_string(
			font,
			Vector2(rect.position.x + 17.0, 3.0),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			CHIP_FONT_SIZE,
			Palette.METAL_4
		)


## Floating world text (explosion shout, +points). Movement is capped by the caller.
class TextPop:
	extends Node2D

	var text := ""
	var color: Color = Palette.METAL_4
	var font_size := 24
	var travel := Vector2.ZERO
	var lifetime := 0.18
	var age := 0.0
	var _start := Vector2.ZERO

	func _ready() -> void:
		_start = position

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		var t := clampf(age / lifetime, 0.0, 1.0)
		position = _start + travel * t
		modulate.a = 1.0 - t * t
		queue_redraw()

	func _draw() -> void:
		var font := Fonts.pixel_font()
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var at := Vector2(-width * 0.5, 0.0)
		draw_string_outline(
			font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Palette.SPACE_VOID
		)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# --- node factories ---------------------------------------------------------
#
# Construction lives here so [CosmicWasher] stays a rules + wiring file.


## Hologram node on `parent` (creates it once, returns the existing one afterwards).
static func make_holo(parent: Node2D, origin: Vector2) -> Node2D:
	var existing := parent.get_node_or_null(^"Holo") as Node2D
	if existing != null:
		return existing
	var node := HoloPanel.new()
	node.name = "Holo"
	node.z_index = 2
	node.position = origin
	parent.add_child(node)
	return node


static func make_ring(parent: Node2D) -> Node2D:
	var existing := parent.get_node_or_null(^"ProgressRing") as Node2D
	if existing != null:
		return existing
	var node := ProgressRing.new()
	node.name = "ProgressRing"
	node.z_index = 1
	node.visible = false
	parent.add_child(node)
	return node


static func make_glow(parent: Node2D) -> Node2D:
	var existing := parent.get_node_or_null(^"Glow") as Node2D
	if existing != null:
		return existing
	var node := DrumGlow.new()
	node.name = "Glow"
	node.z_index = -1
	parent.add_child(node)
	return node


## Looping `fx_bubbles` sprite shown while the drum is DONE.
static func make_bubbles(parent: Node2D) -> AnimatedSprite2D:
	var node := AnimatedSprite2D.new()
	node.name = "Bubbles"
	if not SpriteSheet.configure(node, "fx_bubbles", &"play"):
		node.queue_free()
		return null
	node.z_index = 2
	node.position = Vector2(0.0, -72.0)
	node.visible = false
	parent.add_child(node)
	return node


## One-shot `fx_explosion` sprite (6 frames at 12 fps) that frees itself.
static func make_explosion(parent: Node2D, at: Vector2) -> AnimatedSprite2D:
	var node := AnimatedSprite2D.new()
	node.name = "ExplosionFX"
	if not SpriteSheet.configure(node, "fx_explosion", &"play"):
		node.queue_free()
		return null
	node.z_index = 4
	node.position = at
	parent.add_child(node)
	node.animation_finished.connect(node.queue_free)
	return node


## Stability chip: glyph + number + colour, `0.18 s` lifetime (under 0.45 x T_beat).
static func make_chip(parent: Node2D, text: String, gain: bool, color: Color) -> FeedbackChip:
	var chip := FeedbackChip.new()
	chip.name = "FeedbackChip"
	chip.text = text
	chip.gain = gain
	chip.color = color
	chip.lifetime = 0.18
	chip.position = Vector2(0.0, -36.0)
	chip.z_index = 5
	parent.add_child(chip)
	return chip


static func make_text(parent: Node2D, text: String, size: int, color: Color) -> TextPop:
	var pop := TextPop.new()
	pop.name = "ExplosionText"
	pop.text = text
	pop.color = color
	pop.font_size = size
	pop.travel = Vector2(0.0, -14.0)
	pop.lifetime = 0.18
	pop.position = Vector2(0.0, -150.0)
	pop.z_index = 6
	parent.add_child(pop)
	return pop

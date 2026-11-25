class_name UITheme
extends RefCounted
## The single design system for every player-facing surface (menu, HUD, overlays).
##
## Rules (docs/UX_BIBLE.md §5, §9, §12):
## - one font family (Silkscreen), seven sizes, no second typeface;
## - three ink levels + one accent per intent, never colour alone;
## - panels are flat, 2 px bordered, with one corner tick; no gradients, no shadows
##   beyond 2 px, no glow.
##
## Screens build their nodes with the factories here and assign `UITheme.theme()` to the
## screen root so every Control inherits the same type scale and focus language.

# --- Type scale (px) ---------------------------------------------------------
const FONT_DISPLAY := 56
const FONT_TITLE := 40
const FONT_H1 := 28
const FONT_H2 := 20
const FONT_BODY := 16
const FONT_LABEL := 14
const FONT_SMALL := 12
const FONT_MICRO := 10

# --- Ink --------------------------------------------------------------------
const INK := Palette.METAL_4
const INK_MUTED := Palette.METAL_2
const INK_DIM := Palette.METAL_1
const ACCENT := Palette.FUNK_CYAN
const REWARD := Palette.FUNK_MAGENTA
const SUCCESS := Palette.CLEAN_GREEN
const DANGER := Palette.HAZARD_ORANGE
const WARNING := Palette.YEL_3
const PANEL_FILL := Palette.SPACE_DEEP
const PANEL_DEEP := Palette.SPACE_VOID
const LINE := Palette.METAL_0

# --- Metrics ----------------------------------------------------------------
const BORDER := 2
const ROW_HEIGHT := 52
const CONTENT_MARGIN_X := 26
const CARET_INSET := 8
const PANEL_ALPHA := 0.94
const DIM_ALPHA := 0.58

const UI_SFX_PATH := "res://assets/audio/sfx/ui_click.ogg"

static var _theme: Theme
static var _bold: Font


## Shared Theme. Cached so screens never rebuild it.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var built := Theme.new()
	built.default_font = Fonts.pixel_font()
	built.default_font_size = FONT_LABEL
	built.set_font("font", "Button", font_bold())
	built.set_font_size("font_size", "Button", FONT_H2)
	built.set_color("font_color", "Button", INK_MUTED)
	built.set_color("font_hover_color", "Button", INK)
	built.set_color("font_pressed_color", "Button", ACCENT)
	built.set_color("font_focus_color", "Button", INK)
	built.set_color("font_disabled_color", "Button", LINE)
	built.set_stylebox("normal", "Button", _button_box(PANEL_DEEP, 0.55, LINE, 0))
	built.set_stylebox("hover", "Button", _button_box(Palette.SPACE_MID, 0.85, LINE, 0))
	built.set_stylebox("pressed", "Button", _button_box(Palette.SPACE_MID, 1.0, ACCENT, 2))
	built.set_stylebox("focus", "Button", _button_box(Color(0, 0, 0, 0), 0.0, ACCENT, 2))
	built.set_stylebox("disabled", "Button", _button_box(PANEL_DEEP, 0.35, LINE, 0))
	built.set_stylebox("panel", "Panel", _panel_box(PANEL_FILL, PANEL_ALPHA, LINE))
	built.set_color("font_color", "Label", INK)
	built.set_color("font_shadow_color", "Label", PANEL_DEEP)
	built.set_constant("shadow_offset_x", "Label", 0)
	built.set_constant("shadow_offset_y", "Label", 0)
	_theme = built
	return _theme


## Bold face when the pack ships one; otherwise the regular face (never a system font).
static func font_bold() -> Font:
	if _bold != null:
		return _bold
	_bold = Fonts.pixel_font_bold()
	return _bold


static func font() -> Font:
	return Fonts.pixel_font()


# --- Styleboxes -------------------------------------------------------------


static func _panel_box(fill: Color, alpha: float, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill.r, fill.g, fill.b, alpha)
	box.border_color = border
	box.set_border_width_all(BORDER)
	box.set_corner_radius_all(0)
	box.content_margin_left = CONTENT_MARGIN_X
	box.content_margin_right = CONTENT_MARGIN_X
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	return box


static func _button_box(fill: Color, alpha: float, border: Color, left: int) -> StyleBoxFlat:
	var box := _panel_box(fill, alpha, border)
	if left > 0:
		box.border_width_left = left
		box.border_color = border
	box.content_margin_left = CONTENT_MARGIN_X
	box.content_margin_right = CONTENT_MARGIN_X
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


# --- Labels -----------------------------------------------------------------


static func label(
	text: String, size: int = FONT_LABEL, color: Color = INK, bold: bool = false
) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", font_bold() if bold else font())
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## A title with an optional one-line caption under it (the standard screen header).
static func header(title_text: String, caption_text: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Header"
	box.add_theme_constant_override("separation", 6)
	box.add_child(label(title_text, FONT_TITLE, INK, true))
	if caption_text != "":
		box.add_child(label(caption_text, FONT_SMALL, INK_MUTED))
	return box


# --- Buttons ----------------------------------------------------------------


## A menu row: left-aligned label, caret on focus, click sound wired by `wire_audio`.
static func button(text: String, size: int = FONT_H2) -> Button:
	var node := Button.new()
	node.text = text
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	node.add_theme_font_override("font", font_bold())
	node.add_theme_font_size_override("font_size", size)
	node.focus_mode = Control.FOCUS_ALL
	var caret := label("▶", size, ACCENT, true)
	caret.name = "Caret"
	caret.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	caret.position = Vector2(CARET_INSET, -size * 0.5)
	caret.visible = false
	caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(caret)
	node.focus_entered.connect(caret.set_visible.bind(true))
	node.focus_exited.connect(caret.set_visible.bind(false))
	return node


## A compact action button for modals (centred text, fixed min width).
static func action(text: String, min_width: int = 240, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.custom_minimum_size = Vector2(min_width, 48)
	node.add_theme_font_override("font", font_bold())
	node.add_theme_font_size_override("font_size", FONT_BODY)
	if primary:
		node.add_theme_color_override("font_color", ACCENT)
		node.add_theme_color_override("font_focus_color", INK)
	return node


## A settings row that cycles through values: `LABEL   VALUE  ‹ ›`.
static func cycle_row(text_text: String, value_text: String) -> Button:
	var node := button("%s   %s" % [text_text, value_text], FONT_LABEL)
	node.custom_minimum_size = Vector2(0, 44)
	return node


## A left/right slider row for volumes.
static func slider() -> HSlider:
	var node := HSlider.new()
	node.min_value = -30.0
	node.max_value = 6.0
	node.step = 1.0
	node.custom_minimum_size = Vector2(220, 28)
	node.focus_mode = Control.FOCUS_ALL
	return node


# --- Panels -----------------------------------------------------------------


static func panel(rect: Rect2, tick: bool = true) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.add_theme_stylebox_override("panel", _panel_box(PANEL_FILL, PANEL_ALPHA, LINE))
	if tick:
		var accent := ColorRect.new()
		accent.name = "AccentTick"
		accent.color = ACCENT
		accent.position = Vector2(0, 0)
		accent.size = Vector2(12, BORDER)
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(accent)
		var accent_v := ColorRect.new()
		accent_v.name = "AccentTickV"
		accent_v.color = ACCENT
		accent_v.position = Vector2(0, 0)
		accent_v.size = Vector2(BORDER, 12)
		accent_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(accent_v)
	return node


static func dimmer(alpha: float = DIM_ALPHA) -> ColorRect:
	var node := ColorRect.new()
	node.name = "Dimmer"
	node.color = Color(Palette.SPACE_VOID, alpha)
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


# --- Drawing helpers --------------------------------------------------------


## Segmented bar. `target` is any CanvasItem; call from `_draw()`.
static func draw_segments(
	target: CanvasItem,
	rect: Rect2,
	ratio: float,
	segments: int,
	color: Color,
	empty: Color,
	gap: float = 2.0
) -> void:
	target.draw_rect(rect.grow(2.0), Palette.SPACE_VOID)
	target.draw_rect(rect.grow(2.0), LINE, false, 1.0)
	var count := maxi(segments, 1)
	var step := (rect.size.x - float(count - 1) * gap) / float(count)
	var filled := clampf(ratio, 0.0, 1.0) * float(count)
	for index in range(count):
		var cell := Rect2(
			rect.position + Vector2(float(index) * (step + gap), 0.0), Vector2(step, rect.size.y)
		)
		target.draw_rect(cell, color if float(index) < filled else empty)


## A pixel-perfect focus bracket used by custom (non-Button) focusables.
static func draw_focus_bracket(target: CanvasItem, rect: Rect2, color: Color = ACCENT) -> void:
	var length := 8.0
	target.draw_rect(Rect2(rect.position, Vector2(length, 2)), color)
	target.draw_rect(Rect2(rect.position, Vector2(2, length)), color)
	target.draw_rect(
		Rect2(rect.position + Vector2(rect.size.x - length, 0), Vector2(length, 2)), color
	)
	target.draw_rect(Rect2(rect.position + Vector2(rect.size.x - 2, 0), Vector2(2, length)), color)
	target.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 2), Vector2(length, 2)), color)
	target.draw_rect(
		Rect2(rect.position + Vector2(0, rect.size.y - length), Vector2(2, length)), color
	)
	target.draw_rect(
		Rect2(rect.position + rect.size - Vector2(length, 2), Vector2(length, 2)), color
	)
	target.draw_rect(
		Rect2(rect.position + rect.size - Vector2(2, length), Vector2(2, length)), color
	)


# --- UI audio ---------------------------------------------------------------


## Adds one pooled UI click player under `root` and wires every button below it.
## Safe to call twice (the second call is a no-op) and headless (no audio device).
static func wire_audio(root: Node) -> void:
	if root == null or root.has_meta("ui_audio_wired"):
		return
	root.set_meta("ui_audio_wired", true)
	if not ResourceLoader.exists(UI_SFX_PATH):
		return
	var player := AudioStreamPlayer.new()
	player.name = "UISfx"
	player.stream = load(UI_SFX_PATH) as AudioStream
	player.volume_db = -9.0
	if AudioServer.get_bus_index("UI") >= 0:
		player.bus = "UI"
	root.add_child(player)
	_wire_buttons(root, player)


static func _wire_buttons(node: Node, player: AudioStreamPlayer) -> void:
	for child in node.get_children():
		if child is BaseButton:
			var button := child as BaseButton
			button.focus_entered.connect(_play_ui.bind(player, 1.0))
			button.pressed.connect(_play_ui.bind(player, 1.16))
		_wire_buttons(child, player)


static func _play_ui(player: AudioStreamPlayer, pitch: float) -> void:
	if player == null or player.stream == null:
		return
	player.pitch_scale = pitch
	player.play()

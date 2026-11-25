extends Control
## Options screen (docs/UX_BIBLE.md §12.4).
##
## One plaque, three groups (AUDIO / VÍDEO / MANDO), every row a real control with a value
## readout. There is no Apply button: each change writes `Settings` and applies it at once,
## because a player who changes the volume expects to hear it. `App` decides when the screen
## closes; this screen only emits `closed` and `calibration_requested`.
##
## Focus order: three audio sliders → CALIBRAR AUDIO → fullscreen → reduce motion → HUD
## scale → haptics → RESTABLECER → VOLVER. ←/→ changes the value under the focus.

signal closed
signal calibration_requested

enum AudioParam { MASTER, MUSIC, SFX }

enum Toggle { FULLSCREEN, REDUCE_MOTION, HUD_SCALE, HAPTICS }

const TITLE_TEXT := "OPCIONES"
const HINT_TEXT := "← → CAMBIA VALORES · ESC CIERRA"
const CALIBRATE_TEXT := "CALIBRAR AUDIO"
const RESET_TEXT := "RESTABLECER"
const BACK_TEXT := "VOLVER"

## Ten controls, grouped so no column shows more than five rows at once: AUDIO (4) |
## VÍDEO+MANDO (4) | footer (2). One focus order walks them left-to-right, top-to-bottom.
const PLAQUE := Rect2(250, 90, 780, 540)
## Focus ring geometry: 2 px cyan + 1 px void gap (UX_RESEARCH §5, §8).
const RING_WIDTH := 2.0
const RING_GAP := 1.0
const CONTENT_X := 282.0
const CONTENT_RIGHT := 998.0
const LEFT_W := 348.0
const RIGHT_X := 654.0
const RIGHT_W := 344.0
const TITLE_Y := 112.0
const CAPTION_Y := 160.0
const HEADER_Y := 196.0
const ROW_1 := 218.0
const ROW_2 := 270.0
const ROW_3 := 322.0
const ROW_STEP := 52.0
const CALIBRATE_Y := 366.0
const MANUAL_HEADER_Y := 386.0
const MANUAL_ROW_Y := 408.0
const RULE_Y := 470.0
const LATENCY_Y := 484.0
const BUTTON_Y := 520.0
const BUTTON_H := 48
const BUTTON_W := 200
const HINT_Y := 584.0

## UITheme.slider() is 220 px wide; two columns need a 150 px track (reported, not edited).
const TRACK_W := 150.0
const TRACK_H := 24.0
const GRABBER_W := 8
const GRABBER_H := 18
const AUDIO_LABEL_W := 132.0
const AUDIO_READOUT_X := 292.0

var _from_pause := false
var _suppress_changes := false
var _sliders: Array[HSlider] = []
var _readouts: Array[Label] = []
var _toggles: Array[Button] = []
var _toggle_values: Array[Label] = []
var _focusables: Array[Control] = []
var _caption: Label
var _latency_value: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_from_pause = get_tree().paused
	_build()
	_refresh()
	UITheme.wire_audio(self)
	_refresh_caption()
	# Focus is taken on the first frame, not the second: the screen is interactive at once.
	focus_first()


## Called by `App` when it wants the screen to re-read the current values.
func open(from_pause: bool = false) -> void:
	_from_pause = from_pause or get_tree().paused
	_refresh()
	_refresh_caption()
	if is_inside_tree():
		focus_first()


## First interactive control: the master volume.
func focus_first() -> void:
	if not _focusables.is_empty():
		_focusables[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()


# --- Build ------------------------------------------------------------------


func _build() -> void:
	add_child(UITheme.dimmer(0.72))

	var plaque := _panel(PLAQUE)
	plaque.name = "Plaque"
	add_child(plaque)

	var title := UITheme.label(TITLE_TEXT, UITheme.FONT_TITLE, UITheme.INK, true)
	title.name = "Title"
	title.position = Vector2(CONTENT_X, TITLE_Y) - PLAQUE.position
	plaque.add_child(title)

	_caption = UITheme.label("", UITheme.FONT_LABEL, Palette.METAL_2)
	_caption.name = "Caption"
	_caption.position = Vector2(CONTENT_X, CAPTION_Y) - PLAQUE.position
	plaque.add_child(_caption)

	_section(plaque, "AUDIO", CONTENT_X, HEADER_Y, LEFT_W)
	_section(plaque, "VÍDEO", RIGHT_X, HEADER_Y, RIGHT_W)

	_audio_row(plaque, ROW_1, "MAESTRO", AudioParam.MASTER)
	_audio_row(plaque, ROW_2, "MÚSICA", AudioParam.MUSIC)
	_audio_row(plaque, ROW_3, "EFECTOS", AudioParam.SFX)

	var calibrate := UITheme.action(CALIBRATE_TEXT, int(LEFT_W), false)
	calibrate.name = "CalibrateButton"
	calibrate.position = Vector2(CONTENT_X, CALIBRATE_Y) - PLAQUE.position
	calibrate.custom_minimum_size = Vector2(LEFT_W, float(BUTTON_H))
	calibrate.pressed.connect(_on_calibrate_pressed)
	calibrate.mouse_entered.connect(calibrate.grab_focus)
	_style_action(calibrate)
	plaque.add_child(calibrate)
	_focus_ring(calibrate, Vector2(LEFT_W, float(BUTTON_H)))
	_focusables.append(calibrate)

	_toggle_row(plaque, ROW_1, "PANTALLA COMPLETA", Toggle.FULLSCREEN)
	_toggle_row(plaque, ROW_2, "REDUCIR MOVIMIENTO", Toggle.REDUCE_MOTION)
	_toggle_row(plaque, ROW_3, "ESCALA DEL HUD", Toggle.HUD_SCALE)

	_section(plaque, "MANDO", RIGHT_X, MANUAL_HEADER_Y, RIGHT_W)
	_toggle_row(plaque, MANUAL_ROW_Y, "VIBRACIÓN", Toggle.HAPTICS)

	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = Color(Palette.METAL_1, 0.9)
	rule.position = Vector2(CONTENT_X, RULE_Y) - PLAQUE.position
	rule.size = Vector2(CONTENT_RIGHT - CONTENT_X, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_child(rule)

	var latency_caption := UITheme.label("LATENCIA CALIBRADA", UITheme.FONT_SMALL, Palette.METAL_1)
	latency_caption.name = "LatencyCaption"
	latency_caption.position = Vector2(CONTENT_X, LATENCY_Y + 3) - PLAQUE.position
	plaque.add_child(latency_caption)

	_latency_value = UITheme.label("", UITheme.FONT_LABEL, Palette.METAL_4, true)
	_latency_value.name = "LatencyValue"
	_latency_value.position = Vector2(CONTENT_X + 186.0, LATENCY_Y) - PLAQUE.position
	plaque.add_child(_latency_value)

	var reset := UITheme.action(RESET_TEXT, BUTTON_W, false)
	reset.name = "ResetButton"
	reset.position = Vector2(CONTENT_X, BUTTON_Y) - PLAQUE.position
	reset.custom_minimum_size = Vector2(float(BUTTON_W), float(BUTTON_H))
	reset.pressed.connect(_on_reset_pressed)
	reset.mouse_entered.connect(reset.grab_focus)
	_style_action(reset)
	plaque.add_child(reset)
	_focus_ring(reset, Vector2(float(BUTTON_W), float(BUTTON_H)))
	_focusables.append(reset)

	var back := UITheme.action(BACK_TEXT, BUTTON_W, true)
	back.name = "BackButton"
	back.position = Vector2(CONTENT_RIGHT - float(BUTTON_W), BUTTON_Y) - PLAQUE.position
	back.custom_minimum_size = Vector2(float(BUTTON_W), float(BUTTON_H))
	back.pressed.connect(close)
	back.mouse_entered.connect(back.grab_focus)
	_style_action(back)
	plaque.add_child(back)
	_focus_ring(back, Vector2(float(BUTTON_W), float(BUTTON_H)))
	_focusables.append(back)

	var hint := UITheme.label(HINT_TEXT, UITheme.FONT_SMALL, Palette.METAL_1)
	hint.name = "Hint"
	hint.position = Vector2(CONTENT_X, HINT_Y) - PLAQUE.position
	plaque.add_child(hint)

	_wire_focus_neighbours()


func _section(parent: Control, caption: String, x: float, y: float, width: float) -> void:
	var label := UITheme.label(caption, UITheme.FONT_LABEL, Palette.METAL_3, true)
	label.position = Vector2(x, y) - PLAQUE.position
	parent.add_child(label)
	var line := ColorRect.new()
	line.color = Color(Palette.METAL_1, 0.8)
	line.position = Vector2(x, y + 18) - PLAQUE.position
	line.size = Vector2(width, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


func _audio_row(parent: Control, y: float, caption: String, index: int) -> void:
	var label := UITheme.label(caption, UITheme.FONT_LABEL, Palette.METAL_2)
	label.position = Vector2(CONTENT_X, y) - PLAQUE.position
	label.size = Vector2(AUDIO_LABEL_W, 20)
	parent.add_child(label)

	var slider := UITheme.slider()
	slider.name = "Slider%d" % index
	slider.position = Vector2(CONTENT_X, y + 22.0) - PLAQUE.position
	slider.size = Vector2(LEFT_W, TRACK_H)
	_style_slider(slider)
	slider.value_changed.connect(_on_audio_changed.bind(index))
	slider.focus_entered.connect(_on_row_focus.bind(label, true))
	slider.focus_exited.connect(_on_row_focus.bind(label, false))
	slider.mouse_entered.connect(slider.grab_focus)
	parent.add_child(slider)
	_sliders.append(slider)
	_focus_ring(slider, Vector2(LEFT_W, TRACK_H))

	var readout := UITheme.label("", UITheme.FONT_LABEL, Palette.METAL_4, true)
	readout.name = "Readout%d" % index
	readout.position = Vector2(CONTENT_X, y) - PLAQUE.position
	readout.size = Vector2(LEFT_W, 20)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(readout)
	_readouts.append(readout)
	_focusables.append(slider)


func _toggle_row(parent: Control, y: float, caption: String, toggle: Toggle) -> void:
	var row := UITheme.button("", UITheme.FONT_LABEL)
	row.name = "Toggle%d" % int(toggle)
	row.position = Vector2(RIGHT_X, y) - PLAQUE.position
	row.custom_minimum_size = Vector2(RIGHT_W, 44)
	row.size = Vector2(RIGHT_W, 44)
	row.add_theme_stylebox_override("normal", _row_box(Palette.SPACE_MID, 0.0, 0))
	row.add_theme_stylebox_override("hover", _row_box(Palette.SPACE_MID, 0.45, 0))
	row.add_theme_stylebox_override("pressed", _row_box(Palette.SPACE_MID, 0.6, 0))
	row.add_theme_stylebox_override("focus", _row_box(Palette.SPACE_MID, 0.0, 0))
	row.add_theme_color_override("font_color", Palette.METAL_2)
	var caret := row.get_node_or_null("Caret") as Control
	if caret != null:
		caret.position = Vector2(14, -9)
		(caret as Label).add_theme_font_size_override("font_size", UITheme.FONT_SMALL)

	var label := UITheme.label(caption, UITheme.FONT_LABEL, Palette.METAL_2)
	label.position = Vector2(44, 12)
	row.add_child(label)
	var value := UITheme.label("", UITheme.FONT_LABEL, Palette.METAL_4, true)
	value.name = "Value"
	value.position = Vector2(0, 12)
	value.size = Vector2(RIGHT_W - 18, 20)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_toggle_values.append(value)

	row.pressed.connect(_cycle_toggle.bind(toggle, 1))
	row.gui_input.connect(_on_row_gui_input.bind(toggle))
	row.focus_entered.connect(_on_row_focus.bind(label, true))
	row.focus_exited.connect(_on_row_focus.bind(label, false))
	row.mouse_entered.connect(row.grab_focus)
	row.add_theme_stylebox_override("focus", _empty_box())
	parent.add_child(row)
	_focus_ring(row, Vector2(RIGHT_W, 44.0))
	_toggles.append(row)
	_focusables.append(row)


## Panel border in `metal_1` (3.9:1): `metal_0` measures 2.34:1 and fails the 3:1 floor.
func _panel(rect: Rect2) -> Panel:
	var panel := UITheme.panel(rect)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UITheme.PANEL_FILL, UITheme.PANEL_ALPHA)
	box.border_color = Palette.METAL_1
	box.set_border_width_all(UITheme.BORDER)
	box.set_corner_radius_all(0)
	box.content_margin_left = UITheme.CONTENT_MARGIN_X
	box.content_margin_right = UITheme.CONTENT_MARGIN_X
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", box)
	return panel


## 2 px `funk_cyan` ring with a 1 px `space_void` gap (10.9:1 on `space_deep`). A Slider has
## no focus stylebox of its own, so the ring is its only focus signal.
func _focus_ring(control: Control, size: Vector2) -> void:
	var ring := Control.new()
	ring.name = "FocusRing"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.position = Vector2(-RING_GAP - RING_WIDTH, -RING_GAP - RING_WIDTH)
	ring.size = size + Vector2(RING_GAP + RING_WIDTH, RING_GAP + RING_WIDTH) * 2.0
	ring.draw.connect(_draw_focus_ring.bind(ring, control))
	control.focus_entered.connect(ring.queue_redraw)
	control.focus_exited.connect(ring.queue_redraw)
	control.add_child(ring)


func _draw_focus_ring(ring: Control, control: Control) -> void:
	if not control.has_focus():
		return
	var full := Rect2(Vector2.ZERO, ring.size)
	ring.draw_rect(full.grow(-(RING_WIDTH + RING_GAP)), Palette.SPACE_VOID, false, RING_GAP)
	ring.draw_rect(full.grow(-1.0), UITheme.ACCENT, false, RING_WIDTH)


## Action-button chrome with a `metal_1` border: the shared theme's `metal_0` border measures
## 2.34:1 on `space_deep` and fails the 3:1 non-text floor.
func _action_box(fill: Color, alpha: float, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill.r, fill.g, fill.b, alpha)
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(0)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


func _style_action(button: Button) -> void:
	button.add_theme_stylebox_override(
		"normal", _action_box(Palette.SPACE_VOID, 0.55, Palette.METAL_1, 2)
	)
	button.add_theme_stylebox_override(
		"hover", _action_box(Palette.SPACE_MID, 0.85, Palette.METAL_1, 2)
	)
	button.add_theme_stylebox_override(
		"pressed", _action_box(Palette.SPACE_MID, 1.0, UITheme.ACCENT, 2)
	)
	button.add_theme_stylebox_override("focus", _empty_box())


func _empty_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_border_width_all(0)
	return box


## ←/→ cycles the value of a focused toggle row; ↑/↓ keeps moving the focus.
func _on_row_gui_input(event: InputEvent, toggle: Toggle) -> void:
	if event.is_action_pressed("ui_left"):
		_cycle_toggle(toggle, -1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		_cycle_toggle(toggle, 1)
		accept_event()


func _wire_focus_neighbours() -> void:
	var count := _focusables.size()
	for index in range(count):
		var node := _focusables[index]
		node.focus_neighbor_top = node.get_path_to(_focusables[(index - 1 + count) % count])
		node.focus_neighbor_bottom = node.get_path_to(_focusables[(index + 1) % count])
		node.focus_neighbor_left = node.get_path_to(node)
		node.focus_neighbor_right = node.get_path_to(node)


# --- Values -----------------------------------------------------------------


func _refresh() -> void:
	_suppress_changes = true
	for index in range(_sliders.size()):
		_sliders[index].value = _audio_value(index)
		_readouts[index].text = _db_text(_audio_value(index))
	for index in range(_toggles.size()):
		_toggle_values[index].text = _toggle_text(index)
	_latency_value.text = "%+.0f ms" % Settings.calibration_offset_ms()
	_suppress_changes = false
	_refresh_caption()


func _refresh_caption() -> void:
	if _caption == null:
		return
	var where := "PAUSA" if _from_pause else "TÍTULO"
	_caption.text = "SE GUARDA AL CAMBIAR · ABIERTO DESDE %s" % where


func _audio_value(index: int) -> float:
	match index:
		AudioParam.MASTER:
			return Settings.master_volume_db
		AudioParam.MUSIC:
			return Settings.music_volume_db
		_:
			return Settings.sfx_volume_db


func _on_audio_changed(value: float, index: int) -> void:
	if _suppress_changes:
		return
	match index:
		AudioParam.MASTER:
			Settings.master_volume_db = value
		AudioParam.MUSIC:
			Settings.music_volume_db = value
		_:
			Settings.sfx_volume_db = value
	_readouts[index].text = _db_text(value)
	Settings.save_settings()
	Settings.apply()


func _toggle_text(index: int) -> String:
	match index:
		Toggle.FULLSCREEN:
			return "SÍ" if Settings.fullscreen else "NO"
		Toggle.REDUCE_MOTION:
			return "SÍ" if Settings.reduce_motion else "NO"
		Toggle.HUD_SCALE:
			return "%d %%" % int(round(Settings.ui_scale * 100.0))
		_:
			return "SÍ" if Settings.haptics else "NO"


func _cycle_toggle(toggle: Toggle, direction: int) -> void:
	if _suppress_changes:
		return
	match toggle:
		Toggle.FULLSCREEN:
			Settings.fullscreen = not Settings.fullscreen
			Settings.save_settings()
			Settings.apply()
		Toggle.REDUCE_MOTION:
			Settings.reduce_motion = not Settings.reduce_motion
			Settings.save_settings()
		Toggle.HUD_SCALE:
			var options := Config.HUD_SCALE_OPTIONS
			var current := options.find(Settings.ui_scale)
			if current < 0:
				current = 0
			var next_index := posmod(current + direction, options.size())
			Settings.set_ui_scale(options[next_index])
		_:
			Settings.set_haptics(not Settings.haptics)
	_refresh()


func _db_text(value: float) -> String:
	var rounded := int(round(value))
	if rounded > 0:
		return "+%d dB" % rounded
	return "%d dB" % rounded


## Brightens the row label while its control owns the focus.
func _on_row_focus(label: Label, focused: bool) -> void:
	label.add_theme_color_override("font_color", Palette.METAL_4 if focused else Palette.METAL_2)


# --- Actions ----------------------------------------------------------------


func _on_calibrate_pressed() -> void:
	calibration_requested.emit()


func _on_reset_pressed() -> void:
	Settings.reset_to_defaults()
	_refresh()


# --- Styling ----------------------------------------------------------------


func _style_slider(slider: HSlider) -> void:
	slider.add_theme_stylebox_override("slider", _bar_box(Palette.SPACE_VOID, 1))
	slider.add_theme_stylebox_override("grabber_area", _bar_box(UITheme.ACCENT, 0))
	slider.add_theme_stylebox_override("grabber_area_highlight", _bar_box(UITheme.ACCENT, 0))
	var grabber := _grabber_texture(Palette.METAL_3)
	var grabber_hot := _grabber_texture(Palette.METAL_4)
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber_hot)
	slider.add_theme_icon_override("grabber_disabled", grabber)
	slider.add_theme_stylebox_override("focus", _focus_box())


func _bar_box(color: Color, border: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Palette.METAL_1
	box.set_border_width_all(border)
	box.set_corner_radius_all(0)
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	return box


## The focus language of the rest of the UI, as a stylebox (sliders have no caret).
func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = UITheme.ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(0)
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	return box


## A pixel fader handle: solid, 1 px sel-out, no anti-aliasing anywhere.
func _grabber_texture(color: Color) -> Texture2D:
	var image := Image.create(GRABBER_W, GRABBER_H, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for x in range(GRABBER_W):
		for y in range(GRABBER_H):
			var edge := x == 0 or x == GRABBER_W - 1 or y == 0 or y == GRABBER_H - 1
			image.set_pixel(x, y, Palette.SPACE_VOID if edge else color)
	return ImageTexture.create_from_image(image)


func _row_box(fill: Color, alpha: float, left_border: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill.r, fill.g, fill.b, alpha)
	box.border_color = UITheme.ACCENT
	box.set_border_width_all(0)
	box.border_width_left = left_border
	box.content_margin_left = 40.0
	box.content_margin_right = 12.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box

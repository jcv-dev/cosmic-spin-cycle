# gdlint: disable=max-public-methods
class_name TutorialOverlay
extends CanvasLayer
## The tutorial's whole player-facing surface (docs/UX_BIBLE.md §7, §16.1).
##
## One step chip at the top, one world-anchored prompt at a time, a skip plaque and the
## completion plaque. Everything is built in code (like `HUD.gd`) so the scene file stays a
## single node and tests can instantiate it without a level.
##
## Safe rects (docs/UX_BIBLE.md §12): the chip lives in y 0–104 and the world prompt always
## sits 24 px above its anchor, so neither ever covers a washer mouth or the chute.
##
## Screen space contract: the level camera never pans, so a world point maps to
## `(world - centre) * zoom + viewport / 2`. The overlay converts explicitly instead of
## using `follow_viewport` so the chip never scales with the optional 1.06 zoom.

signal skip_confirmed
signal skip_cancelled
signal completion_continued

const LAYER := 25
## Below the 48 px HUD bar so the tutorial chip never fights the clock/stability readout,
## and still inside the y 0–104 safe band (docs/UX_BIBLE.md §12).
const CHIP_TOP := 56
const CHIP_HEIGHT := 46
const CHIP_PAD_X := 16
const CHIP_GAP := 10
const UNDERLINE_H := 2
const PROMPT_GAP_Y := 24.0
const PROMPT_PAD_X := 10
const PROMPT_HEIGHT := 28
const PROMPT_MIN_Y := 108.0
const FOOTER_Y := 664.0
const FADE_IN_S := 0.12
const FADE_OUT_S := 0.12
const PULSE_S := 0.26
const BEACON_RADIUS := 30.0
const SKIP_RECT := Rect2(360, 268, 560, 184)
const COMPLETE_RECT := Rect2(340, 252, 600, 216)
const PLAQUE_MARGIN := 26

var camera: Camera2D

var _root: Control
var _chip: Panel
var _step_label: Label
var _sep_label: Label
var _title_label: Label
var _skip_hint: Label
var _underline_track: ColorRect
var _underline_fill: ColorRect
var _prompt_layer: Control
var _prompt_chip: Panel
var _prompt_label: Label
var _fx_layer: Control
var _skip: Control
var _skip_no: Button
var _skip_yes: Button
var _complete: Control
var _complete_button: Button
var _complete_stat: Label

var _step_index := -1
var _progress := 0.0
var _prompt_world := Vector2.ZERO
var _prompt_active := false
var _hint_world := Vector2.ZERO
var _hint_radius := 0.0
var _hint_active := false
var _beat_world := Vector2.ZERO
var _beat_phase := 0.0
var _beat_active := false
var _beacon_world := Vector2.ZERO
var _beacon_active := false
var _beacon_t := 0.0
var _pulses: Array[Dictionary] = []
var _prompt_tween: Tween
var _completion_emitted := false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_root()
	_build_chip()
	_build_prompt()
	_build_fx()
	_build_skip()
	_build_complete()
	set_step(0, 0.0)


func _process(delta: float) -> void:
	if _beacon_active:
		_beacon_t = fmod(_beacon_t + delta, TutorialSteps.BEACON_PERIOD_S)
	if not _pulses.is_empty():
		for pulse in _pulses:
			pulse["t"] = float(pulse["t"]) + delta
		_pulses = _pulses.filter(_pulse_alive)
	if _prompt_active or _hint_active or _beacon_active or _beat_active or not _pulses.is_empty():
		_fx_layer.queue_redraw()
		_update_prompt_position()


func _pulse_alive(pulse: Dictionary) -> bool:
	return float(pulse["t"]) < PULSE_S


# --- Public API -------------------------------------------------------------


## Sets the chip to a gate. `ratio` fills the cyan underline (0..1).
func set_step(index: int, ratio: float = 0.0) -> void:
	var safe := TutorialSteps.clamp_index(index)
	_progress = clampf(ratio, 0.0, 1.0)
	if safe != _step_index:
		_step_index = safe
		_set_step_content()
		_layout_chip()
		return
	_layout_underline()


func set_progress(ratio: float) -> void:
	_progress = clampf(ratio, 0.0, 1.0)
	_layout_underline()


func step_index() -> int:
	return _step_index


## Shows the world prompt anchored 24 px above `world_pos` (fades in over 120 ms).
func show_prompt(text: String, world_pos: Vector2) -> void:
	_prompt_label.text = text
	_prompt_world = world_pos
	_prompt_active = true
	_size_prompt()
	_update_prompt_position()
	_prompt_chip.visible = true
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	if Settings.reduce_motion:
		_prompt_chip.modulate.a = 1.0
		return
	_prompt_chip.modulate.a = 0.0
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_chip, "modulate:a", 1.0, FADE_IN_S)


func move_prompt(world_pos: Vector2) -> void:
	_prompt_world = world_pos
	_update_prompt_position()


func hide_prompt() -> void:
	if not _prompt_active:
		return
	_prompt_active = false
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	if Settings.reduce_motion:
		_prompt_chip.visible = false
		return
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_chip, "modulate:a", 0.0, FADE_OUT_S)
	_prompt_tween.tween_callback(_hide_prompt_now)


## Gate 1 fail-forward: a dotted circle on the floor at `radius` px.
func show_hint_circle(world_pos: Vector2, radius: float) -> void:
	_hint_world = world_pos
	_hint_radius = radius
	_hint_active = true
	_fx_layer.queue_redraw()


func hide_hint_circle() -> void:
	_hint_active = false
	_fx_layer.queue_redraw()


## Gates 4 and 6 teach the beat: a ring that contracts into the next beat and flashes on
## it. Reduce motion freezes the radius and keeps the alpha step (docs/UX_BIBLE.md §11).
func set_beat_marker(world_pos: Vector2, active: bool, phase: float = 0.0) -> void:
	_beat_world = world_pos
	_beat_active = active
	_beat_phase = clampf(phase, 0.0, 1.0)


## Gate 7 fail-forward: the chute beacon pulses every 2 s.
func show_beacon(world_pos: Vector2) -> void:
	_beacon_world = world_pos
	_beacon_active = true
	_beacon_t = 0.0
	_fx_layer.queue_redraw()


func hide_beacon() -> void:
	_beacon_active = false
	_fx_layer.queue_redraw()


## One short success ring on a world object: the washer flash / chute accept / gate reward.
func pulse_at(world_pos: Vector2, color: Color = UITheme.SUCCESS) -> void:
	_pulses.append({"pos": world_pos, "t": 0.0, "color": color})
	_fx_layer.queue_redraw()


func open_skip() -> void:
	_skip.visible = true
	_skip_no.grab_focus()


func close_skip() -> void:
	_skip.visible = false


func is_skip_open() -> bool:
	return _skip != null and _skip.visible


func show_completion() -> void:
	_completion_emitted = false
	if _complete_stat != null:
		_complete_stat.text = _completion_line()
	_complete.visible = true
	_complete_button.grab_focus()


func hide_completion() -> void:
	_complete.visible = false


func is_completion_open() -> bool:
	return _complete != null and _complete.visible


func focus_default() -> void:
	if is_completion_open():
		_complete_button.grab_focus()
	elif is_skip_open():
		_skip_no.grab_focus()


## Called by the root on "any input" while the completion plaque is up. Idempotent.
func accept_completion() -> void:
	if _completion_emitted or not is_completion_open():
		return
	_completion_emitted = true
	completion_continued.emit()


# --- Test/debug getters -----------------------------------------------------


func chip_step_text() -> String:
	return _step_label.text if _step_label != null else ""


func chip_title_text() -> String:
	return _title_label.text if _title_label != null else ""


func prompt_text() -> String:
	return _prompt_label.text if _prompt_label != null else ""


func prompt_visible() -> bool:
	return _prompt_chip != null and _prompt_chip.visible


func underline_ratio() -> float:
	if _underline_track == null or _underline_track.size.x <= 0.0:
		return 0.0
	return _underline_fill.size.x / _underline_track.size.x


func chip_rect() -> Rect2:
	return Rect2(_chip.position, _chip.size)


func skip_rect() -> Rect2:
	return SKIP_RECT


func skip_default_button() -> Button:
	return _skip_no


# --- Building ---------------------------------------------------------------


func _build_root() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.theme()
	add_child(_root)


func _build_chip() -> void:
	_chip = UITheme.panel(Rect2(Vector2.ZERO, Vector2(10, CHIP_HEIGHT)), true)
	_chip.name = "StepChip"
	# metal_1 keeps a 3.9:1 border over the belt behind the chip (docs/UX_BIBLE.md §12.9).
	_chip.add_theme_stylebox_override("panel", _chip_stylebox())
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chip)
	_step_label = UITheme.label("PASO 1/7", UITheme.FONT_LABEL, UITheme.INK_MUTED)
	_step_label.name = "StepLabel"
	_chip.add_child(_step_label)
	_sep_label = UITheme.label("·", UITheme.FONT_LABEL, UITheme.INK_DIM)
	_sep_label.name = "SepLabel"
	_chip.add_child(_sep_label)
	_title_label = UITheme.label("MUÉVETE", UITheme.FONT_H2, UITheme.INK, true)
	_title_label.name = "TitleLabel"
	_chip.add_child(_title_label)
	_skip_hint = UITheme.label("TAB · SALTAR PASO", UITheme.FONT_MICRO, UITheme.INK_DIM)
	_skip_hint.name = "SoftSkipHint"
	_skip_hint.visible = false
	# Screen-space footer: it must not inherit the chip's local origin (it sits off the chip).
	_root.add_child(_skip_hint)
	_underline_track = ColorRect.new()
	_underline_track.name = "UnderlineTrack"
	_underline_track.color = Palette.SPACE_MID
	_underline_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.add_child(_underline_track)
	_underline_fill = ColorRect.new()
	_underline_fill.name = "UnderlineFill"
	_underline_fill.color = UITheme.ACCENT
	_underline_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.add_child(_underline_fill)


## A slightly brighter border than the default panel: the chip sits over the north belt.
func _chip_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UITheme.PANEL_FILL, UITheme.PANEL_ALPHA)
	box.border_color = Palette.METAL_1
	box.set_border_width_all(UITheme.BORDER)
	box.set_corner_radius_all(0)
	return box


func _build_prompt() -> void:
	_prompt_layer = Control.new()
	_prompt_layer.name = "WorldPrompts"
	_prompt_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prompt_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_prompt_layer)
	_prompt_chip = UITheme.panel(Rect2(Vector2.ZERO, Vector2(120, PROMPT_HEIGHT)), false)
	_prompt_chip.name = "PromptChip"
	_prompt_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_chip.visible = false
	_prompt_layer.add_child(_prompt_chip)
	_prompt_label = UITheme.label("", UITheme.FONT_LABEL, UITheme.INK)
	_prompt_label.name = "PromptLabel"
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_chip.add_child(_prompt_label)


func _build_fx() -> void:
	_fx_layer = FxCanvas.new()
	_fx_layer.name = "WorldFx"
	(_fx_layer as FxCanvas).overlay = self
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fx_layer)


func _build_skip() -> void:
	_skip = Control.new()
	_skip.name = "SkipPlaque"
	_skip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip.visible = false
	_root.add_child(_skip)
	_skip.add_child(UITheme.dimmer(0.62))
	var panel := UITheme.panel(SKIP_RECT, true)
	panel.name = "Plaque"
	_skip.add_child(panel)
	var box := _plaque_box(panel)
	box.add_child(UITheme.label("¿SALTAR TUTORIAL?", UITheme.FONT_H2, UITheme.INK, true))
	box.add_child(
		UITheme.label(
			"Puedes repetirlo desde el título cuando quieras.",
			UITheme.FONT_SMALL,
			UITheme.INK_MUTED
		)
	)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	box.add_child(spacer)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_skip_no = UITheme.action("NO, SEGUIR")
	_skip_no.name = "NoButton"
	_skip_yes = UITheme.action("SÍ, SALTAR")
	_skip_yes.name = "YesButton"
	row.add_child(_skip_no)
	row.add_child(_skip_yes)
	_skip_yes.pressed.connect(_on_skip_yes)
	_skip_no.pressed.connect(_on_skip_no)


func _build_complete() -> void:
	_complete = Control.new()
	_complete.name = "CompletePlaque"
	_complete.set_anchors_preset(Control.PRESET_FULL_RECT)
	_complete.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_complete.visible = false
	_root.add_child(_complete)
	_complete.add_child(UITheme.dimmer(0.55))
	var panel := UITheme.panel(COMPLETE_RECT, true)
	panel.name = "Plaque"
	_complete.add_child(panel)
	var box := _plaque_box(panel)
	var title := UITheme.label("TURNO DE PRUEBA COMPLETADO", UITheme.FONT_H2, UITheme.INK, true)
	title.name = "CompleteTitle"
	box.add_child(title)
	box.add_child(UITheme.label("Ya sabes lavar el cosmos.", UITheme.FONT_SMALL, UITheme.INK_MUTED))
	_complete_stat = UITheme.label("", UITheme.FONT_SMALL, UITheme.ACCENT)
	_complete_stat.name = "CompleteStat"
	box.add_child(_complete_stat)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	box.add_child(spacer)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_complete_button = UITheme.action("CONTINUAR", 260, true)
	_complete_button.name = "ContinueButton"
	row.add_child(_complete_button)
	_complete_button.pressed.connect(accept_completion)


func _plaque_box(panel: Panel) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Content"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = PLAQUE_MARGIN
	box.offset_right = -PLAQUE_MARGIN
	box.offset_top = 16
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box


# --- Layout -----------------------------------------------------------------


func _set_step_content() -> void:
	_step_label.text = "PASO %d/%d" % [_step_index + 1, TutorialSteps.STEP_COUNT]
	_title_label.text = TutorialSteps.title_for(_step_index)


func _layout_chip() -> void:
	if _chip == null:
		return
	var step_w := _text_width(_step_label.text, UITheme.FONT_LABEL, false)
	var sep_w := _text_width(_sep_label.text, UITheme.FONT_LABEL, false)
	var title_w := _text_width(_title_label.text, UITheme.FONT_H2, true)
	var width := CHIP_PAD_X * 2 + step_w + CHIP_GAP + sep_w + CHIP_GAP + title_w
	var view_w := _root.size.x if _root.size.x > 0.0 else 1280.0
	_chip.position = Vector2(roundf((view_w - width) * 0.5), CHIP_TOP)
	_chip.size = Vector2(width, CHIP_HEIGHT)
	var mid := CHIP_HEIGHT * 0.5
	_step_label.position = Vector2(CHIP_PAD_X, mid - UITheme.FONT_LABEL * 0.75)
	_step_label.size = Vector2(step_w, UITheme.FONT_LABEL + 6)
	_sep_label.position = Vector2(_step_label.position.x + step_w + CHIP_GAP, mid - 9)
	_sep_label.size = Vector2(sep_w, 18)
	_title_label.position = Vector2(_sep_label.position.x + sep_w + CHIP_GAP, mid - 15)
	_title_label.size = Vector2(title_w, 30)
	# A footer hint, not a second chip: keeps the y 0-104 band free of a second line.
	# Right-aligned inside a wide box so glyph rounding can never push it off-screen.
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.position = Vector2(view_w - 540.0, FOOTER_Y)
	_skip_hint.size = Vector2(514, 14)
	_underline_track.position = Vector2(0, CHIP_HEIGHT - UNDERLINE_H)
	_underline_track.size = Vector2(width, UNDERLINE_H)
	_layout_underline()


func _layout_underline() -> void:
	if _underline_track == null:
		return
	_underline_fill.position = _underline_track.position
	_underline_fill.size = Vector2(_underline_track.size.x * _progress, UNDERLINE_H)


## The TAB safety net only becomes visible once it is actually legal (12 s stuck).
func set_soft_skip_available(available: bool) -> void:
	if _skip_hint != null:
		_skip_hint.visible = available


func soft_skip_hint_visible() -> bool:
	return _skip_hint != null and _skip_hint.visible


func _skip_hint_text_width() -> float:
	return _text_width(_skip_hint.text, UITheme.FONT_MICRO, false)


func _size_prompt() -> void:
	var text_w := _text_width(_prompt_label.text, UITheme.FONT_LABEL, false)
	var width := text_w + PROMPT_PAD_X * 2 + 8
	_prompt_chip.size = Vector2(width, PROMPT_HEIGHT)
	_prompt_label.position = Vector2(PROMPT_PAD_X + 4, 0)
	_prompt_label.size = Vector2(text_w + 4, PROMPT_HEIGHT)


func _update_prompt_position() -> void:
	if not _prompt_active or _prompt_chip == null:
		return
	var screen := to_screen(_prompt_world)
	var pos := Vector2(
		roundf(screen.x - _prompt_chip.size.x * 0.5),
		roundf(screen.y - PROMPT_GAP_Y - _prompt_chip.size.y)
	)
	var view := _root.size
	pos.x = clampf(pos.x, 8.0, maxf(view.x - _prompt_chip.size.x - 8.0, 8.0))
	pos.y = clampf(pos.y, PROMPT_MIN_Y, maxf(view.y - PROMPT_HEIGHT - 8.0, PROMPT_MIN_Y))
	_prompt_chip.position = pos


func _hide_prompt_now() -> void:
	if not _prompt_active:
		_prompt_chip.visible = false


func _text_width(text: String, size: int, bold: bool) -> float:
	var font: Font = UITheme.font_bold() if bold else UITheme.font()
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## World → screen. The tutorial camera is fixed, but the optional 1.06 zoom still has to
## be honoured so the prompt stays glued to its object.
func to_screen(world_pos: Vector2) -> Vector2:
	var view := _root.size if _root.size.x > 0.0 else Vector2(1280, 720)
	if camera == null or not is_instance_valid(camera):
		return world_pos
	var zoom := camera.zoom
	var centre := camera.get_screen_center_position()
	return (world_pos - centre) * zoom + view * 0.5


# --- Feedback ---------------------------------------------------------------


func _completion_line() -> String:
	var accuracy := int(round(GameState.accuracy() * 100.0))
	if GameState.rhythm_actions <= 0:
		return "SIN GOLPES DE RITMO"
	return "PRECISIÓN %d%% · %d GOLPES" % [accuracy, GameState.rhythm_actions]


func _on_skip_yes() -> void:
	skip_confirmed.emit()


func _on_skip_no() -> void:
	_skip.visible = false
	skip_cancelled.emit()


# --- FX canvas --------------------------------------------------------------


## Draws the two world-space fail-forward hints and the success rings, in screen space.
func _draw_fx(canvas: CanvasItem) -> void:
	if _hint_active:
		_draw_dotted_circle(canvas, to_screen(_hint_world), _hint_radius, UITheme.INK_DIM)
	if _beat_active:
		var beat_centre := to_screen(_beat_world)
		var hot := _beat_phase < 0.12
		var beat_radius := 40.0 + 32.0 * (1.0 - _beat_phase)
		if Settings.reduce_motion:
			beat_radius = 56.0
		# A stable outer field marks the timing zone; the inner ring is the moving pulse, so
		# the gate reads even on a frame where the pulse happens to be small.
		canvas.draw_arc(beat_centre, 72.0, 0.0, TAU, 40, Color(UITheme.ACCENT, 0.18), 1.0)
		var beat_alpha := 0.95 if hot else 0.35
		canvas.draw_arc(
			beat_centre, beat_radius, 0.0, TAU, 36, Color(UITheme.ACCENT, beat_alpha), 2.0
		)
		if hot:
			canvas.draw_arc(beat_centre, 40.0, 0.0, TAU, 28, Color(UITheme.ACCENT, 0.5), 1.0)
	if _beacon_active:
		var pulse := _beacon_t / TutorialSteps.BEACON_PERIOD_S
		var radius := BEACON_RADIUS + 10.0 * pulse
		var alpha := 1.0 - pulse * 0.7
		var beacon_centre := to_screen(_beacon_world)
		canvas.draw_arc(beacon_centre, radius, 0.0, TAU, 40, Color(UITheme.SUCCESS, alpha), 2.0)
		_draw_corner_brackets(canvas, beacon_centre, radius + 16.0, UITheme.SUCCESS)
	for pulse_entry in _pulses:
		var t := clampf(float(pulse_entry["t"]) / PULSE_S, 0.0, 1.0)
		var color: Color = pulse_entry["color"]
		canvas.draw_arc(
			to_screen(pulse_entry["pos"]), 16.0 + 30.0 * t, 0.0, TAU, 28, Color(color, 1.0 - t), 2.0
		)


## Four L-brackets around the chute: reads as "put it here", not just "something pulses".
func _draw_corner_brackets(
	canvas: CanvasItem, centre: Vector2, radius: float, color: Color
) -> void:
	var arm := 10.0
	var quadrants: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for quadrant in quadrants:
		var corner: Vector2 = centre + quadrant * radius
		# Both arms grow toward the centre of the reticle, forming an L per corner.
		canvas.draw_rect(Rect2(corner.x, corner.y - 1.0, arm, 2.0), color)
		canvas.draw_rect(Rect2(corner.x - 1.0, corner.y, 2.0, arm), color)


func _draw_dotted_circle(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	var dots := 24
	for index in range(dots):
		var angle := TAU * float(index) / float(dots)
		var point := centre + Vector2(cos(angle), sin(angle)) * radius
		canvas.draw_rect(
			Rect2(roundf(point.x) - 1.0, roundf(point.y) - 1.0, 3.0, 3.0), Color(color, 0.75)
		)


func _draw_ticks(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	for index in range(4):
		var angle := TAU * float(index) / 4.0 + PI * 0.25
		var point := centre + Vector2(cos(angle), sin(angle)) * radius
		canvas.draw_rect(Rect2(roundf(point.x) - 1.0, roundf(point.y) - 1.0, 3.0, 3.0), color)


## Inner drawable: a Control cannot override `_draw` from outside a script, so the FX
## surface is a tiny class that forwards to the overlay's painter.
class FxCanvas:
	extends Control
	var overlay: Node

	func _draw() -> void:
		if overlay != null:
			overlay.call("_draw_fx", self)

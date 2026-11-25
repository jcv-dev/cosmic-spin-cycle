extends Control
## In-game HUD: two corner plaques plus one mission ribbon (docs/UX_BIBLE.md §5, docs/HUD.md).
##
## The full-width top bar and the bottom instruction strip are gone. Time and phase live in the
## left plaque, stability / combo / score in the right one, and the only always-on sentence is
## the mission ribbon. Everything else the player needs is world-space: the beat ring, the aim
## reticle and the contextual prompt (`scripts/ui/DiegeticLayer.gd`), so the play field between
## y = 108 and y = 612 stays clear.
##
## Public API, called by MainLevel (never the reverse): `set_shift_time`, `set_phase`,
## `set_bpm`, `show_grade`, `clock_text`. Grades are forwarded to the diegetic layer; the
## `GradeLabel` node stays as an invisible, test-only surface.

## Draw roles for the interior `PaintSlot` children.
enum Slot {
	PLAQUE_A,
	PLAQUE_B,
	RIBBON,
	TOAST,
}

# --- Geometry (1280×720, docs/UX_BIBLE.md §5) -------------------------------
const PLAQUE_A_RECT := Rect2(0, 0, 312, 104)
const PLAQUE_B_RECT := Rect2(968, 0, 312, 104)
const BAR_RECT := Rect2(24, 26, 200, 16)
const SEGMENTS := 12
const BEAT_DOT_ORIGIN := Vector2(232, 34)
const BEAT_DOT_STEP := 16.0
const DOT_RADIUS := 3.0
const DOT_RADIUS_ACTIVE := 4.0
const DOT_DOWNBEAT_SCALE := 1.3
const STABILITY_DIAMOND_CENTER := Vector2(280, 16)
const STABILITY_DIAMOND_RADIUS := 6.0
const RIBBON_RECT := Rect2(400, 6, 480, 28)
const TOAST_RECT := Rect2(400, 34, 480, 18)

# --- Timing -----------------------------------------------------------------
const PANEL_ALPHA := 0.88
const CLOCK_WARN_S := 10.0
const PHASE_NAME_HOLD_S := 4.0
const DANGER_STABILITY := 35.0
const RIBBON_ALPHA := 0.55
const RIBBON_BORDER_ALPHA := 0.45
const OBJECTIVE_FADE_S := 8.0
const OBJECTIVE_IDLE_ALPHA := 0.55
const OBJECTIVE_MAX_CHARS := 46
const TOAST_MAX_CHARS := 46
const TOAST_S := 1.4
const TOAST_ALPHA := 0.82
const DEFAULT_OBJECTIVE := &"OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00"

const PHASE_NAMES: Array[StringName] = [&"APERTURA", &"CINTA SUR", &"MAREJADA", &"CARGA FINAL"]

var shift_time := 0.0
var phase_index := 0
var bpm := 105
var danger := false

var _phase_name_left := 0.0
var _pulse := 0.0
var _last_beat := -1
var _last_stability := -1.0
var _last_combo := -1
var _last_score := -1
var _last_phase := -1
var _clock_warn := false
var _clock_color := Palette.METAL_4
var _plaque_a: Control
var _plaque_b: Control
var _ribbon: Control
var _slot_a: Control
var _slot_b: Control
var _slot_ribbon: Control
var _slot_toast: Control
var _clock_label: Label
var _caption_label: Label
var _bpm_label: Label
var _stability_caption: Label
var _stability_value: Label
var _combo_label: Label
var _score_label: Label
var _objective_label: Label
var _toast_label: Label
var _grade_label: Label
var _objective_age := 0.0
var _objective_alpha := 1.0
var _toast_left := 0.0


## Interior draw slot: a Control that asks the HUD to paint it, so the plaque can be scaled
## and moved as one unit (`Control.scale` applies to the slot's own drawing and children).
class PaintSlot:
	extends Control
	var host: Node = null
	var role: int = 0

	func _draw() -> void:
		if host != null and is_instance_valid(host):
			host.call("draw_slot", self, role)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_plaque_a()
	_build_plaque_b()
	_build_ribbon()
	_build_grade_label()
	_connect_state()
	_refresh_clock()
	_refresh_caption()
	_refresh_bpm()
	_on_stability(GameState.stability)
	_on_combo(GameState.combo)
	_on_score(GameState.score)
	_on_phase(GameState.phase_index)
	set_objective(tr(String(DEFAULT_OBJECTIVE)))
	queue_redraw()


func _process(delta: float) -> void:
	tick(delta)


## Split from `_process` so tests can advance HUD timers without a frame loop.
func tick(delta: float) -> void:
	_pulse += delta
	if _phase_name_left > 0.0:
		_phase_name_left = maxf(_phase_name_left - delta, 0.0)
		_refresh_caption()
	if _objective_age >= 0.0:
		_objective_age += delta
		var alpha := _objective_alpha_at(_objective_age)
		if not is_equal_approx(alpha, _objective_alpha):
			_objective_alpha = alpha
			_objective_label.modulate.a = alpha
	if _toast_left > 0.0:
		_toast_left = maxf(_toast_left - delta, 0.0)
		if _toast_left <= 0.0:
			_toast_label.visible = false
			_slot_toast.queue_redraw()
	var beat := BeatConductor.get_beat_index() if BeatConductor.is_playing else -1
	if beat != _last_beat:
		_last_beat = beat
		_slot_a.queue_redraw()
	if danger or GameState.stability < DANGER_STABILITY:
		_slot_b.queue_redraw()


# --- Construction -----------------------------------------------------------


func _build_plaque_a() -> void:
	_plaque_a = _make_plaque("PlaqueA", PLAQUE_A_RECT, Vector2.ZERO)
	_slot_a = _make_slot("Paint", Slot.PLAQUE_A, PLAQUE_A_RECT.size)
	_plaque_a.add_child(_slot_a)
	_clock_label = _place(
		UITheme.label("00:00", UITheme.FONT_TITLE, Palette.METAL_4, true),
		_plaque_a,
		"ClockLabel",
		Rect2(24, 4, 272, 52)
	)
	_bpm_label = _place(
		UITheme.label("105 BPM", UITheme.FONT_SMALL, Palette.METAL_2),
		_plaque_a,
		"BpmLabel",
		Rect2(196, 10, 92, 16)
	)
	_bpm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_caption_label = _place(
		UITheme.label("", UITheme.FONT_SMALL, Palette.METAL_2),
		_plaque_a,
		"CaptionLabel",
		Rect2(24, 64, 272, 16)
	)


func _build_plaque_b() -> void:
	_plaque_b = _make_plaque("PlaqueB", PLAQUE_B_RECT, Vector2(PLAQUE_B_RECT.size.x, 0.0))
	_slot_b = _make_slot("Paint", Slot.PLAQUE_B, PLAQUE_B_RECT.size)
	_plaque_b.add_child(_slot_b)
	_stability_caption = _place(
		UITheme.label(tr("ESTABILIDAD"), UITheme.FONT_SMALL, Palette.METAL_2),
		_plaque_b,
		"StabilityCaption",
		Rect2(24, 8, 120, 16)
	)
	_stability_value = _place(
		UITheme.label("100", UITheme.FONT_H2, Palette.CLEAN_GREEN, true),
		_plaque_b,
		"StabilityValue",
		Rect2(238, 20, 50, 26)
	)
	_stability_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label = _place(
		UITheme.label("×1", UITheme.FONT_H1, Palette.METAL_3, true),
		_plaque_b,
		"ComboLabel",
		Rect2(24, 54, 120, 38)
	)
	_score_label = _place(
		UITheme.label("000 000", UITheme.FONT_H2, Palette.METAL_4),
		_plaque_b,
		"ScoreLabel",
		Rect2(150, 54, 138, 30)
	)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _build_ribbon() -> void:
	_ribbon = Control.new()
	_ribbon.name = "Ribbon"
	_ribbon.position = RIBBON_RECT.position
	_ribbon.size = RIBBON_RECT.size
	_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ribbon)
	_slot_ribbon = _make_slot("Paint", Slot.RIBBON, RIBBON_RECT.size)
	_ribbon.add_child(_slot_ribbon)
	_objective_label = _place(
		UITheme.label("", UITheme.FONT_LABEL, Palette.METAL_3),
		_ribbon,
		"ObjectiveLabel",
		Rect2(8, 4, RIBBON_RECT.size.x - 16.0, 20)
	)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_toast = _make_slot("Paint", Slot.TOAST, TOAST_RECT.size)
	_slot_toast.position = TOAST_RECT.position
	add_child(_slot_toast)
	_toast_label = _place(
		UITheme.label("", UITheme.FONT_SMALL, Palette.METAL_3), self, "ToastLabel", TOAST_RECT
	)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.visible = false


## Grade text is never shown on screen any more (the diegetic layer places it at the action);
## the node survives as an invisible, assertable surface for tests.
func _build_grade_label() -> void:
	_grade_label = _place(
		UITheme.label("", UITheme.FONT_TITLE, Palette.FUNK_MAGENTA, true),
		self,
		"GradeLabel",
		Rect2(0, 0, 1280, 52)
	)
	_grade_label.visible = false
	_grade_label.modulate.a = 0.0


func _make_plaque(plaque_name: String, rect: Rect2, pivot: Vector2) -> Control:
	var node := Control.new()
	node.name = plaque_name
	node.position = rect.position
	node.size = rect.size
	node.pivot_offset = pivot
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	var panel := UITheme.panel(Rect2(Vector2.ZERO, rect.size))
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_panel_alpha(panel)
	node.add_child(panel)
	return node


## UITheme.panel owns the 2 px border and the cyan corner ticks; the HUD only tightens the
## fill from 94 % to the 88 % the spec asks for.
func _set_panel_alpha(panel: Panel) -> void:
	var box := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if box == null:
		return
	box.bg_color = Color(box.bg_color, PANEL_ALPHA)
	panel.add_theme_stylebox_override("panel", box)


func _make_slot(slot_name: String, role: int, slot_size: Vector2) -> Control:
	var node := PaintSlot.new()
	node.name = slot_name
	node.host = self
	node.role = role
	node.size = slot_size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _place(node: Control, parent: Control, node_name: String, rect: Rect2) -> Control:
	node.name = node_name
	node.position = rect.position
	node.size = rect.size
	parent.add_child(node)
	return node


func _connect_state() -> void:
	GameState.stability_changed.connect(_on_stability)
	GameState.combo_changed.connect(_on_combo)
	GameState.score_changed.connect(_on_score)
	GameState.phase_changed.connect(_on_phase)
	GameState.feedback.connect(_on_feedback)


# --- Painting ---------------------------------------------------------------


func draw_slot(slot: Control, role: int) -> void:
	match role:
		Slot.PLAQUE_A:
			_draw_beat_dots(slot)
		Slot.PLAQUE_B:
			_draw_stability(slot)
		Slot.RIBBON:
			_draw_ribbon(slot)
		Slot.TOAST:
			_draw_toast(slot)


func _draw_beat_dots(target: CanvasItem) -> void:
	var active := -1
	if BeatConductor.is_playing:
		active = BeatConductor.get_beat_index() % Config.BEATS_PER_MEASURE
	var pulse := _beat_pulse()
	for index in range(Config.BEATS_PER_MEASURE):
		var center := BEAT_DOT_ORIGIN + Vector2(float(index) * BEAT_DOT_STEP, 0.0)
		var is_active := index == active
		var color := Palette.FUNK_CYAN if is_active else Palette.METAL_1
		var radius := DOT_RADIUS_ACTIVE if is_active else DOT_RADIUS
		if index == 0:
			radius *= DOT_DOWNBEAT_SCALE
		if is_active and not Settings.reduce_motion:
			radius += pulse * 1.5
		target.draw_circle(center, radius, color)


## 0 → 1 decay after each beat; 0 when the conductor is idle (and always 0 under
## reduce-motion, which is handled by the caller).
func _beat_pulse() -> float:
	if not BeatConductor.is_playing:
		return 0.0
	return clampf(1.0 - BeatConductor.get_beat_phase(), 0.0, 1.0)


func _draw_stability(target: CanvasItem) -> void:
	var color := stability_color()
	if (danger or GameState.stability < DANGER_STABILITY) and not Settings.reduce_motion:
		color.a = 0.55 + 0.45 * absf(sin(_pulse * 6.0))
	UITheme.draw_segments(
		target,
		BAR_RECT,
		clampf(GameState.stability / 100.0, 0.0, 1.0),
		SEGMENTS,
		color,
		Palette.SPACE_MID
	)
	HudGlyphs.draw_diamond(target, STABILITY_DIAMOND_CENTER, STABILITY_DIAMOND_RADIUS, color)


func _draw_ribbon(target: CanvasItem) -> void:
	target.draw_rect(Rect2(Vector2.ZERO, RIBBON_RECT.size), Color(Palette.SPACE_VOID, RIBBON_ALPHA))
	target.draw_rect(
		Rect2(Vector2.ZERO, RIBBON_RECT.size),
		Color(Palette.METAL_0, RIBBON_BORDER_ALPHA),
		false,
		1.0
	)


## The toast chip is as wide as its text so it never reads as a second bar.
func _draw_toast(target: CanvasItem) -> void:
	if _toast_left <= 0.0 or _toast_label.text == "":
		return
	var font := UITheme.font()
	var text_width := (
		font.get_string_size(_toast_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
	)
	var width := minf(text_width + 20.0, TOAST_RECT.size.x)
	var chip := Rect2((TOAST_RECT.size.x - width) * 0.5, 0.0, width, TOAST_RECT.size.y)
	HudGlyphs.draw_chip(target, chip, TOAST_ALPHA, Color(Palette.METAL_0, RIBBON_BORDER_ALPHA))


# --- State ------------------------------------------------------------------


## Stability colour bands: > 60 clean, 35–60 caution, < 35 hazard (docs/UX_BIBLE.md §5.2).
func stability_color() -> Color:
	var value := GameState.stability
	if value > 60.0:
		return Palette.CLEAN_GREEN
	if value >= DANGER_STABILITY:
		return Palette.YEL_2
	return Palette.HAZARD_ORANGE


func _on_stability(value: float) -> void:
	if is_equal_approx(value, _last_stability):
		return
	_last_stability = value
	_refresh_stability()
	_slot_b.queue_redraw()


func _refresh_stability() -> void:
	if _stability_value == null:
		return
	var color := stability_color()
	_stability_value.text = "%d" % roundi(clampf(GameState.stability, 0.0, 100.0))
	_stability_value.add_theme_color_override("font_color", color)


func _on_combo(value: int) -> void:
	if value == _last_combo:
		return
	_last_combo = value
	if _combo_label == null:
		return
	_combo_label.text = "×%d" % value
	var color := Palette.FUNK_MAGENTA if value >= 4 else Palette.METAL_3
	_combo_label.add_theme_color_override("font_color", color)


func _on_score(value: int) -> void:
	if value == _last_score:
		return
	_last_score = value
	if _score_label == null:
		return
	_score_label.text = _format_score(value)


## `1240` → `001 240`: groups of three, zero-padded (docs/UX_BIBLE.md §9).
static func _format_score(value: int) -> String:
	var digits := "%06d" % maxi(value, 0)
	return "%s %s" % [digits.substr(0, 3), digits.substr(3, 3)]


func _on_phase(index: int) -> void:
	if index == _last_phase:
		return
	_last_phase = index
	set_phase(index, Config.phase_bpm(index))


# --- Public API -------------------------------------------------------------


func set_shift_time(t: float) -> void:
	if is_equal_approx(t, shift_time):
		return
	shift_time = t
	var warn := shift_time >= Config.SHIFT_DURATION_S - CLOCK_WARN_S
	if warn != _clock_warn or _clock_label.text != clock_text():
		_clock_warn = warn
		_refresh_clock()


func set_phase(index: int, p_bpm: int = -1) -> void:
	phase_index = index
	if p_bpm > 0:
		bpm = p_bpm
	_phase_name_left = PHASE_NAME_HOLD_S
	_refresh_caption()
	_refresh_bpm()
	_slot_a.queue_redraw()


func set_bpm(p_bpm: int) -> void:
	bpm = p_bpm
	_refresh_bpm()


## One line, max 46 chars; it shouts for 8 s and then settles to 55 % — it never disappears
## (docs/UX_BIBLE.md §5.3).
func set_objective(text: String) -> void:
	var line := text.strip_edges()
	if line.length() > OBJECTIVE_MAX_CHARS:
		line = line.left(OBJECTIVE_MAX_CHARS)
	if _objective_label == null:
		return
	_objective_label.text = line
	_objective_age = 0.0
	_objective_alpha = 1.0
	_objective_label.modulate.a = 1.0


## 100 % for 8 s, then a 0.4 s settle to 55 %.
static func _objective_alpha_at(age: float) -> float:
	if age <= OBJECTIVE_FADE_S:
		return 1.0
	return lerpf(1.0, OBJECTIVE_IDLE_ALPHA, clampf((age - OBJECTIVE_FADE_S) / 0.4, 0.0, 1.0))


## At most one toast, 1.4 s, never a log (docs/UX_BIBLE.md §8).
func _on_feedback(text: String, kind: StringName) -> void:
	var line := text.strip_edges()
	if line == "" or _toast_label == null:
		return
	_toast_label.text = line.left(TOAST_MAX_CHARS)
	_toast_label.add_theme_color_override("font_color", _kind_color(kind))
	_toast_label.visible = true
	_toast_left = TOAST_S
	_slot_toast.queue_redraw()


static func _kind_color(kind: StringName) -> Color:
	match kind:
		&"success":
			return Palette.CLEAN_GREEN
		&"danger":
			return Palette.HAZARD_ORANGE
		&"warn":
			return Palette.YEL_3
		_:
			return Palette.METAL_3


func show_grade(grade: int) -> void:
	if _grade_label == null:
		return
	var text := tr("PERFECTO")
	if grade == RhythmEvaluator.Grade.GOOD:
		text = tr("BIEN")
	elif grade == RhythmEvaluator.Grade.MISS:
		text = tr("FUERA DE RITMO")
	_grade_label.text = text
	_grade_label.add_theme_color_override("font_color", Palette.grade_color(grade))


func clock_text() -> String:
	return Config.clock_string(shift_time)


func _refresh_clock() -> void:
	if _clock_label == null:
		return
	var text := clock_text()
	if _clock_label.text != text:
		_clock_label.text = text
	var color := Palette.YEL_3 if _clock_warn else Palette.METAL_4
	if _clock_color != color:
		_clock_color = color
		_clock_label.add_theme_color_override("font_color", color)


func _refresh_caption() -> void:
	if _caption_label == null:
		return
	var text := "%s · %s %d" % [tr("TURNO"), tr("FASE"), phase_index + 1]
	if _phase_name_left > 0.0 and phase_index < PHASE_NAMES.size():
		text = (
			"%s · %s %d · %s"
			% [
				tr("TURNO"),
				tr("FASE"),
				phase_index + 1,
				tr(String(PHASE_NAMES[phase_index])),
			]
		)
	_caption_label.text = text


func _refresh_bpm() -> void:
	if _bpm_label != null:
		_bpm_label.text = "%d BPM" % bpm


# --- Test surfaces ----------------------------------------------------------


func plaque_rect(plaque_name: String) -> Rect2:
	var node := get_node_or_null(plaque_name) as Control
	if node == null:
		return Rect2()
	return Rect2(node.position, node.size)


func caption_text() -> String:
	return _caption_label.text if _caption_label != null else ""


func stability_text() -> String:
	return _stability_value.text if _stability_value != null else ""


func score_text() -> String:
	return _score_label.text if _score_label != null else ""


func combo_text() -> String:
	return _combo_label.text if _combo_label != null else ""


func objective_text() -> String:
	return _objective_label.text if _objective_label != null else ""


func objective_alpha() -> float:
	return _objective_alpha


func toast_text() -> String:
	if _toast_label == null or not _toast_label.visible:
		return ""
	return _toast_label.text

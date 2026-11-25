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
const PLAQUE_A_RECT := Rect2(0, 0, 300, 86)
const PLAQUE_B_RECT := Rect2(980, 0, 300, 86)
const BAR_RECT := Rect2(24, 26, 200, 16)
const SEGMENTS := 12
const BEAT_DOT_ORIGIN := Vector2(232, 34)
const BEAT_DOT_STEP := 16.0
const DOT_RADIUS := 4.0
const DOT_RADIUS_ACTIVE := 6.0
const DOT_DOWNBEAT_SCALE := 1.4
const STABILITY_DIAMOND_CENTER := Vector2(280, 16)
const STABILITY_DIAMOND_RADIUS := 6.0
const RIBBON_RECT := Rect2(400, 6, 480, 28)
## The toast hangs just under the ribbon, clear of the north belt lane (y 35…100) that the
## level draws inside the wall band.
const TOAST_RECT := Rect2(400, 104, 480, 18)
const REWARD_RECT := Rect2(1156, 104, 100, 18)
const DIEGETIC_SCENE := "res://scenes/ui/DiegeticLayer.tscn"
const GROUP_DIEGETIC := &"diegetic"

# --- Timing -----------------------------------------------------------------
const PANEL_ALPHA := 0.9
const CLOCK_WARN_S := 10.0
const PHASE_NAME_HOLD_S := 4.0
const DANGER_STABILITY := 35.0
## The objective is floating type with a 2 px shadow, not a plate: a filled bar over the
## wall band read as another HUD panel (owner: "the HUD is way too invasive").
const RIBBON_ALPHA := 0.0
const RIBBON_BORDER_ALPHA := 0.0
const OBJECTIVE_FADE_S := 8.0
const OBJECTIVE_IDLE_ALPHA := 0.55
const OBJECTIVE_MAX_CHARS := 46
const TOAST_MAX_CHARS := 46
const TOAST_S := 1.4
const TOAST_ALPHA := 0.82
const DEFAULT_OBJECTIVE := &"OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00"
const REWARD_S := 0.6
const STEP_CLOCK_FONT := 28
const REWARD_RISE := 16.0
const DANGER_PULSE_HZ := 3.0

const PHASE_NAMES: Array[StringName] = [&"APERTURA", &"CINTA SUR", &"MAREJADA", &"CARGA FINAL"]

var shift_time := 0.0
var phase_index := 0
var bpm := 105
var danger := false
var tutorial_mode := false

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
var _combo_caption: Label
var _score_label: Label
var _objective_label: Label
var _objective_text := ""
var _reward_label: Label
var _toast_label: Label
var _grade_label: Label
var _objective_age := 0.0
var _objective_alpha := 1.0
var _toast_left := 0.0
var _reward_left := 0.0
var _step_index := 0
var _step_total := 0
var _diegetic_node: Node = null


## Interior draw slot: a Control that asks the HUD to paint it, so the plaque can be scaled
## and moved as one unit (`Control.scale` applies to the slot's own drawing and children).
class PaintSlot:
	extends Control
	var host: Node = null
	var role: int = 0

	func _draw() -> void:
		if host != null and is_instance_valid(host):
			host.call("_draw_slot", self, role)


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
	_apply_ui_scale()
	set_objective(tr(String(DEFAULT_OBJECTIVE)))
	call_deferred("_mount_diegetic")
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
			_slot_toast.visible = false
	if _reward_left > 0.0:
		_reward_left = maxf(_reward_left - delta, 0.0)
		_update_reward()
		if _reward_left <= 0.0:
			_reward_label.visible = false
	var beat := BeatConductor.get_beat_index() if BeatConductor.is_playing else -1
	if beat != _last_beat:
		_last_beat = beat
		_slot_a.queue_redraw()
	if _danger_active():
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
		Rect2(24, 8, 272, 52)
	)
	_bpm_label = _place(
		UITheme.label("105 BPM", UITheme.FONT_SMALL, Palette.METAL_2),
		_plaque_a,
		"BpmLabel",
		Rect2(196, 64, 92, 16)
	)
	_bpm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_caption_label = _place(
		UITheme.label("", UITheme.FONT_SMALL, Palette.METAL_2),
		_plaque_a,
		"CaptionLabel",
		Rect2(24, 64, 168, 16)
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
	_combo_caption = _place(
		UITheme.label(tr("COMBO · PUNTOS"), UITheme.FONT_SMALL, Palette.METAL_2),
		_plaque_b,
		"ComboCaption",
		Rect2(24, 38, 170, 14)
	)
	_combo_label = _place(
		UITheme.label("×1", UITheme.FONT_H1, Palette.METAL_3, true),
		_plaque_b,
		"ComboLabel",
		Rect2(24, 52, 120, 34)
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
	_slot_toast.visible = false
	add_child(_slot_toast)
	_reward_label = _place(
		UITheme.label("", UITheme.FONT_LABEL, Palette.CLEAN_GREEN, true),
		self,
		"RewardFloat",
		REWARD_RECT
	)
	_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reward_label.visible = false
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
	Settings.settings_changed.connect(_apply_ui_scale)


# --- Painting ---------------------------------------------------------------


func _draw_slot(slot: Control, role: int) -> void:
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
		if is_active:
			# A bright core + a thin halo make the current beat readable at a glance, not
			# only by comparing dot sizes.
			target.draw_circle(center, maxf(radius - 2.0, 1.0), Palette.METAL_4)
			target.draw_arc(center, radius + 3.0, 0.0, TAU, 20, Color(color, 0.55), 1.5, true)


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
	if _danger_active():
		var border := Palette.HAZARD_ORANGE
		if not Settings.reduce_motion:
			border.a = 0.45 + 0.55 * absf(sin(_pulse * DANGER_PULSE_HZ))
		target.draw_rect(Rect2(Vector2.ZERO, PLAQUE_B_RECT.size), border, false, 2.0)


## True while the fail state is close: the explicit level signal, or the raw stability value
## once it drops below the hazard band (so the HUD is honest even if nobody called us).
func _danger_active() -> bool:
	return danger or GameState.stability < DANGER_STABILITY


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


# --- Diegetic wiring --------------------------------------------------------


## Grades are world-space; the HUD only forwards. The layer is either owned by MainLevel or
## mounted here when the level has not been wired yet, so the HUD is never mute.
func _diegetic_layer() -> Node:
	if _diegetic_node != null and is_instance_valid(_diegetic_node):
		return _diegetic_node
	_diegetic_node = null
	var tree := get_tree()
	if tree == null:
		return null
	_diegetic_node = tree.get_first_node_in_group(GROUP_DIEGETIC)
	return _diegetic_node


func _mount_diegetic() -> void:
	if _diegetic_layer() != null:
		return
	var host := _world_host()
	if host == null or not ResourceLoader.exists(DIEGETIC_SCENE):
		return
	var packed := load(DIEGETIC_SCENE) as PackedScene
	if packed == null:
		return
	var layer := packed.instantiate()
	if layer == null:
		return
	layer.name = "DiegeticLayer"
	host.add_child(layer)
	_diegetic_node = layer


## The nearest Node2D ancestor that is a shift level (it exposes `get_shift_time`). Tests and
## the title screen have no such ancestor, and then nothing is mounted.
func _world_host() -> Node:
	var node := get_parent()
	while node != null:
		if node is Node2D and node.has_method("get_shift_time"):
			return node
		node = node.get_parent()
	return null


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
	if _combo_caption != null:
		var sustain := value >= 4
		_combo_caption.text = tr("COMBO · +ESTAB") if sustain else tr("COMBO · PUNTOS")
		_combo_caption.add_theme_color_override(
			"font_color", Palette.FUNK_CYAN if sustain else Palette.METAL_2
		)


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
## Raw objective string (tests, tutorial overlay handoff).
func objective_text() -> String:
	return _objective_text


func set_objective(text: String) -> void:
	_objective_text = text
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
	_slot_toast.visible = true
	_toast_left = TOAST_S


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


## `+points` near plaque B: 600 ms, floats up 16 px, no stack. Reduce-motion keeps the number
## legible but drops the movement (docs/UX_BIBLE.md §11).
func flash_reward(points: int) -> void:
	if _reward_label == null:
		return
	_reward_label.text = "+%d" % points
	_reward_label.visible = true
	_reward_left = REWARD_S
	_update_reward()


func _update_reward() -> void:
	if _reward_label == null:
		return
	var progress := clampf(1.0 - _reward_left / REWARD_S, 0.0, 1.0)
	if Settings.reduce_motion:
		_reward_label.position = REWARD_RECT.position
		_reward_label.modulate.a = 1.0 - progress * progress
		return
	_reward_label.position = REWARD_RECT.position - Vector2(0.0, REWARD_RISE * progress)
	_reward_label.modulate.a = 1.0 - progress


## Called by MainLevel at the hazard band; pulses the plaque B border and the bar.
func set_danger(on: bool) -> void:
	danger = on
	if _slot_b != null:
		_slot_b.queue_redraw()


## HUD scale (100 % / 125 %) scales only the two plaques, from the screen-edge corner, and
## never the world or the ribbon (docs/UX_BIBLE.md §11.5).
func set_hud_scale(factor: float) -> void:
	var options := Config.HUD_SCALE_OPTIONS
	var clamped := clampf(factor, options[0], options[options.size() - 1])
	if _plaque_a != null:
		_plaque_a.scale = Vector2(clamped, clamped)
	if _plaque_b != null:
		_plaque_b.scale = Vector2(clamped, clamped)


func _apply_ui_scale() -> void:
	set_hud_scale(Settings.ui_scale)


## Tutorial mode hides the tempo and the score — they are noise while learning — and lets the
## clock become the step counter. Stability stays: it is the fail state the step teaches
## (docs/UX_BIBLE.md §7). Safe to call before any step exists.
func set_tutorial_mode(on: bool) -> void:
	tutorial_mode = on
	if _bpm_label != null:
		_bpm_label.visible = not on
	if _score_label != null:
		_score_label.visible = not on
	if _ribbon != null:
		# The tutorial's step chip owns the top line instead of a second mission line.
		_ribbon.visible = not on
	_refresh_clock()


## 1-based step presentation: `PASO 2/7`.
func set_step(index: int, total: int) -> void:
	_step_index = maxi(index, 1)
	_step_total = maxi(total, 0)
	_refresh_clock()


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
	var layer := _diegetic_layer()
	if layer != null and layer.has_method("show_grade"):
		layer.call("show_grade", grade)


func clock_text() -> String:
	return Config.clock_string(shift_time)


func _refresh_clock() -> void:
	if _clock_label == null:
		return
	if tutorial_mode and _step_total > 0:
		_clock_label.add_theme_font_size_override("font_size", STEP_CLOCK_FONT)
		_clock_label.text = "PASO %d/%d" % [mini(_step_index, _step_total), _step_total]
		_set_clock_color(Palette.METAL_4)
		return
	_clock_label.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	var text := clock_text()
	if _clock_label.text != text:
		_clock_label.text = text
	_set_clock_color(Palette.YEL_3 if _clock_warn else Palette.METAL_4)


func _set_clock_color(color: Color) -> void:
	if _clock_color == color:
		return
	_clock_color = color
	_clock_label.add_theme_color_override("font_color", color)


func _refresh_caption() -> void:
	if _caption_label == null:
		return
	var text := "%s · %s %d" % [tr("TURNO"), tr("FASE"), phase_index + 1]
	if _phase_name_left > 0.0 and phase_index < PHASE_NAMES.size():
		# The announcement drops TURNO so the caption never collides with the tempo readout.
		text = ("%s %d · %s" % [tr("FASE"), phase_index + 1, tr(String(PHASE_NAMES[phase_index]))])
	_caption_label.text = text


func _refresh_bpm() -> void:
	if _bpm_label != null:
		_bpm_label.text = "%d BPM" % bpm


# --- Test surface -----------------------------------------------------------


func plaque_rect(plaque_name: String) -> Rect2:
	var node := get_node_or_null(plaque_name) as Control
	if node == null:
		return Rect2()
	return Rect2(node.position, node.size)


## One snapshot of everything the layout tests assert, so they never walk node paths.
func scale_factor() -> float:
	return _plaque_a.scale.x if _plaque_a != null else 1.0


func diegetic_layer() -> Node:
	return _diegetic_layer()


func readout() -> Dictionary:
	return {
		"clock": _clock_label.text,
		"caption": _caption_label.text,
		"bpm": _bpm_label.text,
		"stability": _stability_value.text,
		"combo": _combo_label.text,
		"score": _score_label.text,
		"objective": _objective_label.text,
		"objective_alpha": _objective_alpha,
		"toast": _toast_label.text if _toast_label.visible else "",
		"reward": _reward_label.text if _reward_label.visible else "",
		"bpm_visible": _bpm_label.visible,
		"score_visible": _score_label.visible,
		"stability_visible": _stability_value.visible,
		"tutorial": tutorial_mode,
		"danger": danger,
	}

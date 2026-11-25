extends Control
## Minimal in-game HUD (M6 will extend it): clock, stability, combo, score, phase and
## rhythmic measure dots. Player-facing strings go through tr(); Spanish source strings are
## the keys until the translation resources land (see docs/DECISIONS.md D017).

const PANEL_RECT := Rect2(0, 0, 1280, 48)
const STABILITY_RECT := Rect2(392, 22, 300, 12)
const SEGMENTS := 12
const HINT_TEXT := "WASD mover · ratón apuntar · ESPACIO agarrar/lanzar · SHIFT golpe rítmico"

var shift_time := 0.0
var phase_index := 0
var bpm := 105
var _grade_alpha := 0.0
var _phase_banner_alpha := 0.0
var _pulse := 0.0
var _last_beat := -1
var _last_stability := -1.0
var _last_combo := -1
var _last_score := -1
var _last_phase := -1

var _clock_label: Label
var _turno_label: Label
var _phase_label: Label
var _stability_label: Label
var _combo_label: Label
var _score_label: Label
var _grade_label: Label
var _banner_label: Label
var _hint_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_labels()
	GameState.stability_changed.connect(_on_stability)
	GameState.combo_changed.connect(_on_combo)
	GameState.score_changed.connect(_on_score)
	GameState.phase_changed.connect(_on_phase)
	_on_stability(GameState.stability)
	_on_combo(GameState.combo)
	_on_score(GameState.score)
	_on_phase(GameState.phase_index)
	_refresh_clock()
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	if _grade_alpha > 0.0:
		_grade_alpha = maxf(_grade_alpha - delta * 1.6, 0.0)
		_grade_label.modulate.a = _grade_alpha
	if _phase_banner_alpha > 0.0:
		_phase_banner_alpha = maxf(_phase_banner_alpha - delta * 0.8, 0.0)
		_banner_label.modulate.a = _phase_banner_alpha
	_refresh_clock()
	var beat := BeatConductor.get_beat_index() if BeatConductor.is_playing else -1
	if beat != _last_beat:
		_last_beat = beat
		queue_redraw()
	if GameState.stability < 25.0:
		queue_redraw()


func _build_labels() -> void:
	var font := Fonts.pixel_font()
	_clock_label = _label("ClockLabel", Rect2(24, 0, 220, 34), 26, Palette.METAL_4, font)
	_turno_label = _label("TurnoLabel", Rect2(26, 32, 100, 12), 9, Palette.METAL_2, font)
	_turno_label.text = tr("TURNO")
	_phase_label = _label("PhaseLabel", Rect2(128, 32, 300, 12), 9, Palette.FUNK_CYAN, font)
	_stability_label = _label(
		"StabilityLabel", Rect2(STABILITY_RECT.position.x, 4, 320, 14), 9, Palette.METAL_2, font
	)
	_stability_label.text = tr("ESTABILIDAD DEL TEJIDO CÓSMICO")
	_stability_label.name = "StabilityLabel"
	_combo_label = _label("ComboLabel", Rect2(880, 12, 130, 30), 24, Palette.FUNK_MAGENTA, font)
	var combo_caption := _label("ComboCaption", Rect2(882, 2, 150, 12), 9, Palette.METAL_2, font)
	combo_caption.text = tr("COMBO")
	_score_label = _label("ScoreLabel", Rect2(1046, 12, 194, 30), 22, Palette.METAL_4, font)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var score_caption := _label("ScoreCaption", Rect2(1046, 2, 190, 12), 9, Palette.METAL_2, font)
	score_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_caption.text = tr("PUNTOS")

	_grade_label = _label("GradeLabel", Rect2(0, 286, 1280, 60), 44, Palette.FUNK_MAGENTA, font)
	_grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade_label.modulate.a = 0.0
	_banner_label = _label("PhaseBanner", Rect2(0, 200, 1280, 48), 24, Palette.FUNK_CYAN, font)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.modulate.a = 0.0
	_hint_label = _label("HintLabel", Rect2(0, 688, 1280, 18), 11, Palette.METAL_1, font)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.text = tr(HINT_TEXT)


func _label(node_name: String, rect: Rect2, font_size: int, color: Color, font: Font) -> Label:
	var lbl := Label.new()
	lbl.name = node_name
	lbl.position = rect.position
	lbl.size = rect.size
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Palette.SPACE_VOID)
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	return lbl


func _draw() -> void:
	draw_rect(PANEL_RECT, Color(Palette.SPACE_DEEP, 0.94))
	draw_rect(PANEL_RECT, Palette.METAL_0, false, 2.0)
	# corner accents
	draw_rect(Rect2(PANEL_RECT.position, Vector2(10, 2)), Palette.FUNK_CYAN)
	draw_rect(Rect2(0, 46, 1280, 2), Palette.METAL_0)
	draw_rect(Rect2(PANEL_RECT.position + Vector2(0, 46), Vector2(10, 2)), Palette.FUNK_CYAN)
	draw_rect(Rect2(PANEL_RECT.end - Vector2(10, 2), Vector2(10, 2)), Palette.FUNK_CYAN)
	_draw_stability_bar()
	_draw_measure_dots()


func _draw_stability_bar() -> void:
	draw_rect(STABILITY_RECT.grow(2.0), Palette.SPACE_VOID)
	draw_rect(STABILITY_RECT.grow(2.0), Palette.METAL_0, false, 1.0)
	var segment_w := (STABILITY_RECT.size.x - float(SEGMENTS - 1) * 2.0) / float(SEGMENTS)
	var filled := clampf(GameState.stability / 100.0, 0.0, 1.0) * float(SEGMENTS)
	var color := _stability_color()
	if GameState.stability < 25.0:
		color.a = 0.55 + 0.45 * absf(sin(_pulse * 6.0))
	for i in range(SEGMENTS):
		var seg := Rect2(
			STABILITY_RECT.position + Vector2(float(i) * (segment_w + 2.0), 0),
			Vector2(segment_w, STABILITY_RECT.size.y)
		)
		if float(i) < ceilf(filled) and filled > float(i):
			draw_rect(seg, color)
		else:
			draw_rect(seg, Palette.SPACE_MID)


func _stability_color() -> Color:
	var value := GameState.stability
	if value > 60.0:
		return Palette.CLEAN_GREEN
	if value > 35.0:
		return Palette.YEL_2
	return Palette.HAZARD_ORANGE


func _draw_measure_dots() -> void:
	var active := -1
	if BeatConductor.is_playing:
		active = BeatConductor.get_beat_index() % Config.BEATS_PER_MEASURE
	var origin := Vector2(744, 37)
	for i in range(Config.BEATS_PER_MEASURE):
		var color := Palette.FUNK_CYAN if i == active else Palette.METAL_1
		var radius := 4.0 if i == active else 3.0
		draw_circle(origin + Vector2(float(i) * 13.0, 0), radius, color)


func set_shift_time(t: float) -> void:
	if not is_equal_approx(t, shift_time):
		shift_time = t
		_refresh_clock()


func set_phase(index: int, p_bpm: int = -1) -> void:
	phase_index = index
	if p_bpm > 0:
		bpm = p_bpm
	if _phase_label != null:
		_phase_label.text = "%s %d · %d BPM" % [tr("FASE"), phase_index + 1, bpm]
	_flash_banner("%s %d" % [tr("FASE"), phase_index + 1])


func set_bpm(p_bpm: int) -> void:
	bpm = p_bpm
	if _phase_label != null:
		_phase_label.text = "%s %d · %d BPM" % [tr("FASE"), phase_index + 1, bpm]


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
	_grade_alpha = 1.0
	_grade_label.modulate.a = 1.0


func clock_text() -> String:
	return Config.clock_string(shift_time)


func _refresh_clock() -> void:
	if _clock_label != null:
		_clock_label.text = clock_text()


func _flash_banner(text: String) -> void:
	if _banner_label == null:
		return
	_banner_label.text = text
	_phase_banner_alpha = 1.0
	_banner_label.modulate.a = 1.0


func _on_stability(value: float) -> void:
	if is_equal_approx(value, _last_stability):
		return
	_last_stability = value
	queue_redraw()


func _on_combo(value: int) -> void:
	if value == _last_combo:
		return
	_last_combo = value
	_combo_label.text = "×%d" % value
	var color := Palette.FUNK_MAGENTA if value >= 4 else Palette.METAL_3
	_combo_label.add_theme_color_override("font_color", color)


func _on_score(value: int) -> void:
	if value == _last_score:
		return
	_last_score = value
	_score_label.text = "%06d" % value


func _on_phase(index: int) -> void:
	if index == _last_phase:
		return
	_last_phase = index
	set_phase(index, Config.phase_bpm(index))

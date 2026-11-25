class_name DebugOverlay
extends Control
## Developer rhythm overlay: tempo, beat/measure, signed Δt, grade, ±65/±130 ms window
## bar, song time, output latency and calibration offset (M1).
##
## It reads the autoloaded BeatConductor, so any dev scene can drop the scene in without
## touching the autoload list. Toggle with `toggle_debug()` (F3 by default) or hide it by
## setting `visible = false`.

const PERFECT_COLOR := Color("#E040FB")
const GOOD_COLOR := Color("#19E3D1")
const MISS_COLOR := Color("#FF7A1A")
const TEXT_COLOR := Color("#CDD3E8")
const DIM_TEXT_COLOR := Color("#9AA4C4")
const PANEL_COLOR := Color("#0B0C10D9")
const BAR_BACK_COLOR := Color("#1F2340")
const PERFECT_ZONE_COLOR := Color("#E040FB40")
const GOOD_ZONE_COLOR := Color("#19E3D140")
const ZERO_LINE_COLOR := Color("#F4F6FC")
const EARLY_TEXT := "EARLY"
const LATE_TEXT := "LATE"

const PANEL_POSITION := Vector2(16.0, 16.0)
const PANEL_SIZE := Vector2(620.0, 232.0)
const PADDING := 14.0
const BAR_HEIGHT := 14.0
const BAR_WIDTH := 592.0
const TEXT_SIZE := 16
const TITLE_SIZE := 18
const LINE_GAP := 22.0
const FLASH_DURATION_S := 0.22
const FLASH_RADIUS := 7.0
const LAST_GRADE_HOLD_S := 1.5

## Re-evaluated live when no grade has been reported recently (standalone dev use).
var conductor: Node

var _song_time := 0.0
var _bpm := 0
var _stem_offset_ms := 0.0
var _beat_index := 0
var _measure_index := 0
var _beat_in_bar := 0
var _delta_ms := 0.0
var _signed_ms := 0.0
var _live_grade := RhythmEvaluator.Grade.MISS
var _reported_grade := RhythmEvaluator.Grade.MISS
var _reported_at := -1000.0
var _flash_age := FLASH_DURATION_S


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if conductor == null:
		conductor = get_node_or_null("/root/BeatConductor")
	_connect_conductor()
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not visible:
		return
	refresh()
	_flash_age = minf(_flash_age + delta, FLASH_DURATION_S)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		toggle_debug()
		get_viewport().set_input_as_handled()


func toggle_debug() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		refresh()
	queue_redraw()


## Recomputes every displayed value. Callable from tests without a rendered frame.
func refresh() -> Dictionary:
	if conductor == null or not is_instance_valid(conductor):
		return {}
	_song_time = float(conductor.call("get_song_time"))
	_bpm = int(conductor.get("bpm"))
	_stem_offset_ms = float(conductor.get("stem_first_beat_offset")) * 1000.0
	_beat_index = int(conductor.call("get_beat_index"))
	_measure_index = int(conductor.call("get_measure_index"))
	_beat_in_bar = _beat_index % Config.BEATS_PER_MEASURE
	_delta_ms = float(conductor.call("delta_to_nearest_beat", _song_time)) * 1000.0
	_signed_ms = float(conductor.call("signed_delta_to_nearest_beat", _song_time)) * 1000.0
	_live_grade = RhythmEvaluator.evaluate(_delta_ms / 1000.0)
	if _song_time - _reported_at > LAST_GRADE_HOLD_S:
		_reported_grade = _live_grade
	return {
		"song_time": _song_time,
		"bpm": _bpm,
		"stem_offset_ms": _stem_offset_ms,
		"beat": _beat_index,
		"measure": _measure_index,
		"delta_ms": _delta_ms,
		"signed_ms": _signed_ms,
		"grade": get_display_grade(),
	}


## Stores a grade reported by gameplay so the overlay can keep showing the last action.
func report_grade(grade: int) -> void:
	_reported_grade = grade
	_reported_at = _song_time
	_flash_age = 0.0
	queue_redraw()


func get_display_grade() -> int:
	return _reported_grade


func get_signed_delta_ms() -> float:
	return _signed_ms


func set_conductor(node: Node) -> void:
	_disconnect_conductor()
	conductor = node
	_connect_conductor()


static func color_for_grade(grade: int) -> Color:
	match grade:
		RhythmEvaluator.Grade.PERFECT:
			return PERFECT_COLOR
		RhythmEvaluator.Grade.GOOD:
			return GOOD_COLOR
		_:
			return MISS_COLOR


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(PANEL_POSITION, PANEL_SIZE), PANEL_COLOR)
	draw_rect(Rect2(PANEL_POSITION, PANEL_SIZE), DIM_TEXT_COLOR, false, 1.0)

	var x := PANEL_POSITION.x + PADDING
	var y := PANEL_POSITION.y + PADDING + TITLE_SIZE
	draw_string(
		font, Vector2(x, y), "BEAT DEBUG", HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, TEXT_COLOR
	)
	draw_string(
		font,
		Vector2(PANEL_POSITION.x + PANEL_SIZE.x - 120.0, y),
		"F10 toggles",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TEXT_SIZE,
		DIM_TEXT_COLOR
	)
	_draw_flash(Vector2(PANEL_POSITION.x + PANEL_SIZE.x - 150.0, y - 6.0))

	if conductor == null or not is_instance_valid(conductor):
		draw_string(
			font,
			Vector2(x, y + LINE_GAP * 2.0),
			"BeatConductor not found",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			TEXT_SIZE,
			MISS_COLOR
		)
		return

	y += LINE_GAP * 1.6
	draw_string(
		font,
		Vector2(x, y),
		(
			"BPM %d    beat %d    measure %d    beat %d/%d"
			% [
				_bpm,
				_beat_index,
				_measure_index,
				_beat_in_bar,
				Config.BEATS_PER_MEASURE,
			]
		),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TEXT_SIZE,
		TEXT_COLOR
	)

	y += LINE_GAP
	var grade := get_display_grade()
	draw_string(
		font,
		Vector2(x, y),
		"Δt %+.1f ms    last %s" % [_signed_ms, RhythmEvaluator.grade_name(grade)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TEXT_SIZE,
		color_for_grade(grade)
	)

	y += LINE_GAP * 1.4
	_draw_window_bar(Vector2(x, y), grade)

	y += BAR_HEIGHT + LINE_GAP + 16.0
	draw_string(
		font,
		Vector2(x, y),
		(
			"song %8.3f s    output latency %5.1f ms"
			% [_song_time, AudioServer.get_output_latency() * 1000.0]
		),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TEXT_SIZE,
		TEXT_COLOR
	)

	y += LINE_GAP
	draw_string(
		font,
		Vector2(x, y),
		(
			"calibration %+.1f ms    stem offset %+.0f ms    beat %.3f s"
			% [
				Settings.calibration_offset_ms(),
				_stem_offset_ms,
				float(conductor.call("beat_seconds")),
			]
		),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TEXT_SIZE,
		DIM_TEXT_COLOR
	)


func _draw_window_bar(origin: Vector2, grade: int) -> void:
	var half := BAR_WIDTH * 0.5
	var center := origin.x + half
	draw_rect(Rect2(origin, Vector2(BAR_WIDTH, BAR_HEIGHT)), BAR_BACK_COLOR)
	var good_s := Config.WINDOW_GOOD_S
	var perfect_s := Config.WINDOW_PERFECT_S
	var scale := half / maxf(good_s, 0.000001)
	var good_half := good_s * scale
	var perfect_half := perfect_s * scale
	draw_rect(
		Rect2(Vector2(center - good_half, origin.y), Vector2(good_half * 2.0, BAR_HEIGHT)),
		GOOD_ZONE_COLOR
	)
	draw_rect(
		Rect2(Vector2(center - perfect_half, origin.y), Vector2(perfect_half * 2.0, BAR_HEIGHT)),
		PERFECT_ZONE_COLOR
	)
	draw_line(
		Vector2(center, origin.y), Vector2(center, origin.y + BAR_HEIGHT), ZERO_LINE_COLOR, 2.0
	)
	var marker_ratio := clampf(_signed_ms / (good_s * 1000.0), -1.0, 1.0)
	var marker_x := center + marker_ratio * half
	draw_line(
		Vector2(marker_x, origin.y - 4.0),
		Vector2(marker_x, origin.y + BAR_HEIGHT + 4.0),
		color_for_grade(grade),
		3.0
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(origin.x, origin.y + BAR_HEIGHT + 16.0),
		"%s %d ms" % [EARLY_TEXT, int(-good_s * 1000.0)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		DIM_TEXT_COLOR
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(origin.x + BAR_WIDTH - 70.0, origin.y + BAR_HEIGHT + 16.0),
		"%s %d ms" % [LATE_TEXT, int(good_s * 1000.0)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		DIM_TEXT_COLOR
	)


func _draw_flash(center: Vector2) -> void:
	if _flash_age >= FLASH_DURATION_S:
		return
	var t := _flash_age / FLASH_DURATION_S
	var radius := FLASH_RADIUS * (1.0 + t * 1.5)
	var color := color_for_grade(get_display_grade())
	color.a = 1.0 - t
	draw_circle(center, radius, color)


func _connect_conductor() -> void:
	if conductor == null or not is_instance_valid(conductor):
		return
	if conductor.has_signal("beat_hit") and not conductor.beat_hit.is_connected(_on_beat):
		conductor.beat_hit.connect(_on_beat)


func _disconnect_conductor() -> void:
	if conductor == null or not is_instance_valid(conductor):
		return
	if conductor.has_signal("beat_hit") and conductor.beat_hit.is_connected(_on_beat):
		conductor.beat_hit.disconnect(_on_beat)


func _on_beat(_beat: int) -> void:
	_flash_age = 0.0
	if visible:
		queue_redraw()

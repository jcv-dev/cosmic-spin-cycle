extends Control
## Records screen (addendum §12, D059): the top ten of each difficulty.
##
## Same design system as the options and end screens: one plaque, flat borders in `metal_1`,
## Silkscreen at the shared type scale, ink levels instead of extra colours. Left/right
## switches difficulty; ESC closes. The table is read from disk on every tab change so the
## screen never shows stale data.

signal close_requested

const PLAQUE := Rect2(230, 70, 820, 580)
const CONTENT_X := 262.0
const CONTENT_RIGHT := 1018.0
const TITLE_Y := 96.0
const CAPTION_Y := 146.0
const TABS_Y := 186.0
const TAB_X: Array[float] = [262.0, 430.0, 612.0]
const HEADER_Y := 232.0
const ROW_Y := 262.0
const ROW_STEP := 28.0
const COL_POINTS := 330.0
const COL_RANK := 620.0
const COL_ACCURACY := 740.0
const HINT_Y := 574.0
const BUTTON_X := 818.0
const BUTTON_Y := 556.0
const BUTTON_W := 200
const BUTTON_H := 48

const TITLE_TEXT := "RÉCORDS"
const CAPTION_TEXT := "TOP 10 POR DIFICULTAD · SE GUARDA EN ESTE EQUIPO"
const HINT_TEXT := "← → CAMBIA DIFICULTAD · ESC VOLVER"
const EMPTY_TEXT := "SIN TURNOS REGISTRADOS TODAVÍA"
const BACK_TEXT := "VOLVER"
const HEADERS: Array[String] = ["#", "PUNTOS", "RANGO", "PRECISIÓN"]

const RANK_COLORS := {
	"S": Palette.FUNK_MAGENTA,
	"A": Palette.FUNK_CYAN,
	"B": Palette.METAL_3,
	"C": Palette.METAL_1,
}

var records_path := Config.RECORDS_PATH

var _tab := 0
var _tabs: Array[Button] = []
var _underlines: Array[ColorRect] = []
var _positions: Array[Label] = []
var _points: Array[Label] = []
var _ranks: Array[Label] = []
var _accuracies: Array[Label] = []
var _empty: Label
var _back: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	_build()
	UITheme.wire_audio(self)
	refresh()
	focus_first()


func focus_first() -> void:
	if _back != null:
		_back.call_deferred("grab_focus")


## Tests point the screen at a temporary file; gameplay always uses the shipped path.
func set_path(path: String) -> void:
	records_path = path
	refresh()


func current_tab() -> int:
	return _tab


func set_tab(index: int) -> void:
	_tab = posmod(index, Config.DIFFICULTY_KEYS.size())
	refresh()


func _build() -> void:
	var dimmer := UITheme.dimmer(0.72)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dimmer)
	var plaque := _panel(PLAQUE)
	plaque.name = "Plaque"
	add_child(plaque)
	# Centred against the live viewport instead of pinned to 1280x720: at 16:9 this is the
	# same 230,70, and at any other aspect the plaque stays on screen with its hitboxes
	# aligned (reported hover/offset mismatch).
	_centre(plaque)
	get_viewport().size_changed.connect(_centre.bind(plaque))

	var title := UITheme.label(TITLE_TEXT, UITheme.FONT_TITLE, UITheme.INK, true)
	title.name = "Title"
	title.position = Vector2(CONTENT_X, TITLE_Y) - PLAQUE.position
	plaque.add_child(title)

	var caption := UITheme.label(CAPTION_TEXT, UITheme.FONT_SMALL, Palette.METAL_2)
	caption.name = "Caption"
	caption.position = Vector2(CONTENT_X, CAPTION_Y) - PLAQUE.position
	plaque.add_child(caption)

	for index in range(Config.DIFFICULTY_KEYS.size()):
		_build_tab(plaque, index)
	for index in range(HEADERS.size()):
		_build_header(plaque, index)
	for row in range(Config.LEADERBOARD_SIZE):
		_build_row(plaque, row)

	_empty = UITheme.label(EMPTY_TEXT, UITheme.FONT_LABEL, Palette.METAL_2)
	_empty.name = "Empty"
	_empty.position = Vector2(CONTENT_X, ROW_Y + 60.0) - PLAQUE.position
	plaque.add_child(_empty)

	var hint := UITheme.label(HINT_TEXT, UITheme.FONT_SMALL, Palette.METAL_1)
	hint.name = "Hint"
	hint.position = Vector2(CONTENT_X, HINT_Y) - PLAQUE.position
	plaque.add_child(hint)

	_back = UITheme.action(BACK_TEXT, BUTTON_W, false)
	_back.name = "BackButton"
	_back.text = BACK_TEXT
	_back.custom_minimum_size = Vector2(float(BUTTON_W), float(BUTTON_H))
	_back.size = Vector2(float(BUTTON_W), float(BUTTON_H))
	_back.position = Vector2(BUTTON_X, BUTTON_Y) - PLAQUE.position
	_back.pressed.connect(_on_back_pressed)
	_back.mouse_entered.connect(_back.grab_focus)
	plaque.add_child(_back)
	_style_back()


func _build_tab(parent: Control, index: int) -> void:
	var tab := Button.new()
	tab.name = "Tab%d" % index
	tab.text = tr(Config.DIFFICULTY_LABEL_KEYS[index])
	tab.flat = true
	tab.focus_mode = Control.FOCUS_NONE
	tab.add_theme_font_override("font", UITheme.font_bold())
	tab.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
	tab.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	tab.add_theme_stylebox_override("hover", _tab_box(0.18))
	tab.add_theme_stylebox_override("pressed", _tab_box(0.32))
	tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tab.position = Vector2(TAB_X[index], TABS_Y) - PLAQUE.position
	tab.pressed.connect(set_tab.bind(index))
	parent.add_child(tab)
	_tabs.append(tab)

	var underline := ColorRect.new()
	underline.name = "Underline%d" % index
	underline.color = UITheme.ACCENT
	underline.position = Vector2(TAB_X[index], TABS_Y + 28.0) - PLAQUE.position
	underline.size = Vector2(maxf(float(tab.text.length()) * 10.0, 40.0), 2.0)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(underline)
	_underlines.append(underline)


func _build_header(parent: Control, index: int) -> void:
	var x: float = [CONTENT_X, COL_POINTS, COL_RANK, COL_ACCURACY][index]
	var label := UITheme.label(HEADERS[index], UITheme.FONT_SMALL, Palette.METAL_1)
	label.name = "Header%d" % index
	label.position = Vector2(x, HEADER_Y) - PLAQUE.position
	parent.add_child(label)


func _build_row(parent: Control, row: int) -> void:
	var y := ROW_Y + float(row) * ROW_STEP
	_positions.append(_row_label(parent, "Pos%d" % row, CONTENT_X, y, UITheme.FONT_SMALL))
	_points.append(_row_label(parent, "Points%d" % row, COL_POINTS, y, UITheme.FONT_LABEL))
	_ranks.append(_row_label(parent, "Rank%d" % row, COL_RANK, y, UITheme.FONT_LABEL))
	_accuracies.append(_row_label(parent, "Accuracy%d" % row, COL_ACCURACY, y, UITheme.FONT_SMALL))
	for label: Label in [_positions[row], _points[row], _ranks[row], _accuracies[row]]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _row_label(parent: Control, node_name: String, x: float, y: float, size: int) -> Label:
	var label := UITheme.label("", size, Palette.METAL_3)
	label.name = node_name
	label.position = Vector2(x, y) - PLAQUE.position
	label.size = Vector2(180, ROW_STEP)
	parent.add_child(label)
	return label


## Re-reads the stored table for the active tab. Missing file simply yields an empty list.
func refresh() -> void:
	for index in range(_tabs.size()):
		var active := index == _tab
		var ink := UITheme.ACCENT if active else Palette.METAL_2
		var hover := UITheme.ACCENT if active else Palette.METAL_4
		_tabs[index].add_theme_color_override("font_color", ink)
		_tabs[index].add_theme_color_override("font_hover_color", hover)
		_tabs[index].add_theme_color_override("font_pressed_color", UITheme.ACCENT)
		_tabs[index].add_theme_color_override("font_focus_color", hover)
		_underlines[index].visible = active
	var table := Leaderboard.load_table(_tab, records_path)
	_empty.visible = table.is_empty()
	for row in range(Config.LEADERBOARD_SIZE):
		var visible := row < table.size()
		_positions[row].visible = visible
		_points[row].visible = visible
		_ranks[row].visible = visible
		_accuracies[row].visible = visible
		if not visible:
			continue
		var entry: Dictionary = table[row]
		_positions[row].text = "%02d" % (row + 1)
		_points[row].text = _format_points(int(entry.get("points", 0)))
		var rank := String(entry.get("rank", "C"))
		_ranks[row].text = rank
		var rank_value: Variant = RANK_COLORS.get(rank)
		_ranks[row].add_theme_color_override(
			"font_color", rank_value if rank_value is Color else Palette.METAL_1
		)
		_accuracies[row].text = "%d %%" % int(round(float(entry.get("accuracy", 0.0)) * 100.0))


func _centre(plaque: Control) -> void:
	if plaque == null or not is_instance_valid(plaque):
		return
	var view := get_viewport_rect().size
	plaque.position = ((view - PLAQUE.size) * 0.5).floor().max(Vector2.ZERO)


func _on_back_pressed() -> void:
	close_requested.emit()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		close_requested.emit()
	elif event.is_action_pressed("ui_left"):
		accept_event()
		set_tab(_tab - 1)
	elif event.is_action_pressed("ui_right"):
		accept_event()
		set_tab(_tab + 1)


## "18 450": thin spaces keep the column readable without a second font.
static func _format_points(points: int) -> String:
	var text := str(maxi(points, 0))
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out


## Panel border in `metal_1`, same as the options and end screens (3:1 floor).
func _panel(rect: Rect2) -> Panel:
	var panel := UITheme.panel(rect)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UITheme.PANEL_FILL, UITheme.PANEL_ALPHA)
	box.border_color = Palette.METAL_1
	box.set_border_width_all(UITheme.BORDER)
	box.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", box)
	return panel


func _style_back() -> void:
	_back.add_theme_font_override("font", UITheme.font_bold())
	_back.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	_back.add_theme_color_override("font_color", UITheme.ACCENT)
	_back.add_theme_color_override("font_hover_color", Palette.METAL_4)
	_back.add_theme_color_override("font_pressed_color", UITheme.ACCENT)
	_back.add_theme_stylebox_override("normal", _action_box(0.55, false))
	_back.add_theme_stylebox_override("hover", _action_box(0.85, false))
	_back.add_theme_stylebox_override("pressed", _action_box(1.0, true))
	_back.add_theme_stylebox_override("focus", _empty_box())
	_back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _tab_box(alpha: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.SPACE_MID, alpha)
	box.border_color = UITheme.ACCENT
	box.set_border_width_all(0)
	box.border_width_bottom = 2
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	return box


func _action_box(alpha: float, accent_border: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.SPACE_MID, alpha)
	box.border_color = UITheme.ACCENT if accent_border else Palette.METAL_1
	box.set_border_width_all(2)
	box.set_corner_radius_all(0)
	return box


## A StyleBoxFlat with no colour is opaque grey, not empty: the focus box must draw nothing.
func _empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

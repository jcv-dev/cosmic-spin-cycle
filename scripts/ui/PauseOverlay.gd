extends Control
## Pause overlay (docs/UX_BIBLE.md §12.3).
##
## ESC is owned by `App` (it pauses and resumes); this screen only presents state and emits
## intent. It runs with `PROCESS_MODE_ALWAYS` so it stays alive while the tree is paused,
## and it is the one place in the game that lists the controls (never the HUD).

signal resume_requested
signal restart_requested
signal options_requested
signal menu_requested

const TITLE_TEXT := "PAUSA"
const CAPTION_TEXT := "TURNO EN PAUSA · EL RELOJ NO CORRE"
const CONTROLS_CAPTION := "CONTROLES"
const HINT_TEXT := "ESC · REANUDAR"
## key, action — two columns, read left to right (mover/apuntar, agarrar/golpe, pausa/calibrar).
const CONTROLS: Array[Array] = [
	["WASD · STICK", "MOVER", "RATÓN · STICK", "APUNTAR", "ESPACIO · A", "AGARRAR · LANZAR"],
	["SHIFT · X", "GOLPE RÍTMICO", "ESC · START", "PAUSA", "OPCIONES", "CALIBRAR AUDIO"],
]
const ROW_LABELS: Array[String] = ["REANUDAR", "REINICIAR", "OPCIONES", "MENÚ"]
const ROW_NAMES: Array[StringName] = [
	"ResumeButton", "RestartButton", "OptionsButton", "MenuButton"
]
const ROW_HEIGHT := 44
const ROW_GAP := 8

const PLAQUE := Rect2(360, 125, 560, 470)
const CONTENT_X := 392.0
const CONTENT_W := 496.0
const TITLE_Y := 152.0
const CAPTION_Y := 202.0
const RULE_Y := 224.0
const CONTROLS_Y := 238.0
const CONTROLS_ROW_Y := 258.0
const CONTROLS_ROW_H := 40.0
const CONTROLS_COLUMNS: Array[float] = [392.0, 556.0, 720.0]
const NOTE_Y := 338.0
const ROWS_Y := 356.0
const HINT_Y := 562.0

var _rows: Array[Button] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	UITheme.wire_audio(self)
	focus_first.call_deferred()


## Resume owns the default focus: the safe action is one press away.
func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()


func _build() -> void:
	add_child(UITheme.dimmer(UITheme.DIM_ALPHA))

	var plaque := UITheme.panel(PLAQUE)
	plaque.name = "Plaque"
	add_child(plaque)

	var title := UITheme.label(TITLE_TEXT, UITheme.FONT_TITLE, UITheme.INK, true)
	title.name = "Title"
	title.position = Vector2(CONTENT_X, TITLE_Y) - PLAQUE.position
	plaque.add_child(title)

	var caption := UITheme.label(CAPTION_TEXT, UITheme.FONT_MICRO, Palette.METAL_2)
	caption.name = "Caption"
	caption.position = Vector2(CONTENT_X, CAPTION_Y) - PLAQUE.position
	plaque.add_child(caption)

	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = Color(Palette.METAL_0, 0.9)
	rule.position = Vector2(CONTENT_X, RULE_Y) - PLAQUE.position
	rule.size = Vector2(CONTENT_W, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_child(rule)

	var controls_caption := UITheme.label(CONTROLS_CAPTION, UITheme.FONT_MICRO, Palette.METAL_1)
	controls_caption.name = "ControlsCaption"
	controls_caption.position = (Vector2(CONTENT_X, CONTROLS_Y) - PLAQUE.position)
	plaque.add_child(controls_caption)

	for index in range(CONTROLS.size()):
		var row: Array = CONTROLS[index]
		var y := CONTROLS_ROW_Y + float(index) * CONTROLS_ROW_H
		for column in range(3):
			_control_cell(
				plaque,
				CONTROLS_COLUMNS[column],
				y,
				String(row[column * 2]),
				String(row[column * 2 + 1])
			)

	if Settings.reduce_motion:
		var note := UITheme.label("REDUCE MOTION: ACTIVADO", UITheme.FONT_MICRO, UITheme.ACCENT)
		note.name = "ReduceMotionNote"
		note.position = Vector2(CONTENT_X, NOTE_Y) - PLAQUE.position
		plaque.add_child(note)

	for index in range(ROW_LABELS.size()):
		var row := _menu_row(ROW_LABELS[index])
		row.name = String(ROW_NAMES[index])
		row.position = (
			Vector2(CONTENT_X, ROWS_Y + float(index) * float(ROW_HEIGHT + ROW_GAP))
			- PLAQUE.position
		)
		plaque.add_child(row)
		_rows.append(row)
		row.pressed.connect(_on_row_pressed.bind(index))

	var hint := UITheme.label(HINT_TEXT, UITheme.FONT_MICRO, Palette.METAL_1)
	hint.name = "Hint"
	hint.position = Vector2(CONTENT_X, HINT_Y) - PLAQUE.position
	plaque.add_child(hint)


## One control cell: the key (bright) sits over the verb (quiet), never on the same line —
## a single line cannot hold "ESPACIO" and "AGARRAR · LANZAR" at 12 px.
func _control_cell(parent: Control, x: float, y: float, key_text: String, action: String) -> void:
	var key := UITheme.label(key_text, UITheme.FONT_SMALL, Palette.METAL_4, true)
	key.position = Vector2(x, y) - PLAQUE.position
	parent.add_child(key)
	var verb := UITheme.label(action, UITheme.FONT_SMALL, Palette.METAL_2)
	verb.position = Vector2(x, y + 17) - PLAQUE.position
	parent.add_child(verb)


func _menu_row(caption: String) -> Button:
	var row := UITheme.button(caption, UITheme.FONT_H2)
	row.custom_minimum_size = Vector2(CONTENT_W, ROW_HEIGHT)
	row.add_theme_stylebox_override("normal", _row_box(Palette.SPACE_MID, 0.0, 0))
	row.add_theme_stylebox_override("hover", _row_box(Palette.SPACE_MID, 0.45, 0))
	row.add_theme_stylebox_override("pressed", _row_box(Palette.SPACE_MID, 0.6, 2))
	row.add_theme_stylebox_override("focus", _row_box(Palette.SPACE_MID, 0.0, 2))
	row.add_theme_color_override("font_color", Palette.METAL_2)

	var caret := row.get_node_or_null("Caret") as Control
	if caret != null:
		caret.position = Vector2(16, -UITheme.FONT_H2 * 0.5)
		(caret as Label).add_theme_font_size_override("font_size", UITheme.FONT_SMALL)

	var label_width := (
		row
		. get_theme_font("font")
		. get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_H2)
		. x
	)
	var underline := ColorRect.new()
	underline.name = "FocusUnderline"
	underline.color = UITheme.ACCENT
	underline.position = Vector2(46, ROW_HEIGHT - 9)
	underline.size = Vector2(label_width + 8, 2)
	underline.visible = false
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(underline)

	var hairline := ColorRect.new()
	hairline.name = "Hairline"
	hairline.color = Color(Palette.METAL_0, 0.45)
	hairline.position = Vector2(0, ROW_HEIGHT - 1)
	hairline.size = Vector2(CONTENT_W, 1)
	hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hairline)

	row.focus_entered.connect(underline.set_visible.bind(true))
	row.focus_exited.connect(underline.set_visible.bind(false))
	row.mouse_entered.connect(row.grab_focus)
	return row


func _row_box(fill: Color, alpha: float, left_border: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill.r, fill.g, fill.b, alpha)
	box.border_color = UITheme.ACCENT
	box.set_border_width_all(0)
	box.border_width_left = left_border
	box.content_margin_left = 46.0
	box.content_margin_right = 16.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	return box


func _on_row_pressed(index: int) -> void:
	match index:
		0:
			resume_requested.emit()
		1:
			restart_requested.emit()
		2:
			options_requested.emit()
		_:
			menu_requested.emit()

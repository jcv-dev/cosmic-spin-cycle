extends Control
## First-run prompt (docs/UX_BIBLE.md §12.2).
##
## Shown once, after the player presses INICIAR TURNO, so the first interaction in the game
## is always the big one. It recommends the tutorial (default focus) and never nags again:
## `App` persists the choice through `Settings`. ESC backs out to the title.

signal tutorial_selected
signal skip_selected
signal closed

const TITLE_TEXT := "¿PRIMERA VEZ?"
const BODY_LINES: Array[String] = [
	"El tutorial dura 3 minutos y te enseña",
	"a lavar y entregar.",
]
const TUTORIAL_TEXT := "HACER EL TUTORIAL"
const SKIP_TEXT := "EMPEZAR EL TURNO"
const HINT_TEXT := "ESC · VOLVER AL TÍTULO"

const PLAQUE := Rect2(320, 220, 640, 280)
const CONTENT_X := 352.0
const TITLE_Y := 246.0
const BODY_Y := 314.0
const BODY_LINE_H := 24.0
const BUTTON_Y := 386.0
const BUTTON_H := 48.0
const BUTTON_W := 272
const BUTTON_GAP := 32.0
const HINT_Y := 452.0

var _tutorial_button: Button
var _skip_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	UITheme.wire_audio(self)
	focus_first.call_deferred()


## The recommended action owns the default focus, never the skip.
func focus_first() -> void:
	if _tutorial_button != null:
		_tutorial_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()


func _build() -> void:
	add_child(UITheme.dimmer(0.55))

	var plaque := UITheme.panel(PLAQUE)
	plaque.name = "Plaque"
	add_child(plaque)

	var title := UITheme.label(TITLE_TEXT, UITheme.FONT_TITLE, UITheme.INK, true)
	title.name = "Title"
	title.position = Vector2(CONTENT_X, TITLE_Y) - PLAQUE.position
	plaque.add_child(title)

	for index in range(BODY_LINES.size()):
		var line := UITheme.label(BODY_LINES[index], UITheme.FONT_BODY, Palette.METAL_2)
		line.name = "Body%d" % index
		line.position = (Vector2(CONTENT_X, BODY_Y + float(index) * BODY_LINE_H) - PLAQUE.position)
		plaque.add_child(line)

	_tutorial_button = UITheme.action(TUTORIAL_TEXT, BUTTON_W, true)
	_tutorial_button.name = "TutorialButton"
	_tutorial_button.position = Vector2(CONTENT_X, BUTTON_Y) - PLAQUE.position
	_tutorial_button.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
	_tutorial_button.add_theme_stylebox_override("normal", _primary_box(0.12))
	_tutorial_button.add_theme_stylebox_override("hover", _primary_box(0.2))
	_tutorial_button.pressed.connect(_on_tutorial_pressed)
	_tutorial_button.mouse_entered.connect(_tutorial_button.grab_focus)
	plaque.add_child(_tutorial_button)

	_skip_button = UITheme.action(SKIP_TEXT, BUTTON_W, false)
	_skip_button.name = "SkipButton"
	_skip_button.position = (
		Vector2(CONTENT_X + float(BUTTON_W) + BUTTON_GAP, BUTTON_Y) - PLAQUE.position
	)
	_skip_button.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
	_skip_button.pressed.connect(_on_skip_pressed)
	_skip_button.mouse_entered.connect(_skip_button.grab_focus)
	plaque.add_child(_skip_button)

	_tutorial_button.focus_neighbor_left = _tutorial_button.get_path_to(_skip_button)
	_tutorial_button.focus_neighbor_right = _tutorial_button.get_path_to(_skip_button)
	_skip_button.focus_neighbor_left = _skip_button.get_path_to(_tutorial_button)
	_skip_button.focus_neighbor_right = _skip_button.get_path_to(_tutorial_button)
	_tutorial_button.focus_neighbor_top = _tutorial_button.get_path_to(_tutorial_button)
	_tutorial_button.focus_neighbor_bottom = _tutorial_button.get_path_to(_tutorial_button)
	_skip_button.focus_neighbor_top = _skip_button.get_path_to(_skip_button)
	_skip_button.focus_neighbor_bottom = _skip_button.get_path_to(_skip_button)

	var hint := UITheme.label(HINT_TEXT, UITheme.FONT_MICRO, Palette.METAL_1)
	hint.name = "Hint"
	hint.position = Vector2(CONTENT_X, HINT_Y) - PLAQUE.position
	plaque.add_child(hint)


## Primary action: accent border + a 12 % accent wash, flat (no gradient).
func _primary_box(alpha: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UITheme.ACCENT, alpha)
	box.border_color = UITheme.ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(0)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


func _on_tutorial_pressed() -> void:
	tutorial_selected.emit()


func _on_skip_pressed() -> void:
	# The bible is explicit: taking the shift instead of the tutorial persists the choice.
	Settings.mark_first_run_done()
	skip_selected.emit()

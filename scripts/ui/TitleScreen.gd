extends Control
## Title screen (docs/UX_BIBLE.md §12.1).
##
## The first frame a stranger ever sees, so it has to answer "what is this game" before it
## asks for anything: the living room is the backdrop, the wordmark is the loudest thing on
## screen, and one mission line states the goal in plain Spanish. Pure presentation — every
## row emits an intent signal and `App` decides what happens.
##
## Focus order (keyboard and gamepad share it): INICIAR TURNO → TUTORIAL → CALIBRACIÓN DE
## AUDIO → OPCIONES → SALIR. Mouse hover moves focus onto the hovered row.

signal start_requested
signal tutorial_requested
signal options_requested
signal calibration_requested
signal quit_requested

const TAGLINE := "LAVANDERÍA AL BORDE DEL VACÍO"
const MISSION := "OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00"
const VERSION_LINE := "v0.6 · semilla aleatoria · ESC SALIR"
const LEGEND_LINES: Array[String] = [
	"WASD mover · ratón apuntar",
	"ESPACIO agarrar / lanzar · SHIFT golpe",
	"ESC pausa · ENTER confirmar · flechas mover el foco",
]
const MENU_ROWS: Array[String] = [
	"INICIAR TURNO", "TUTORIAL", "CALIBRACIÓN DE AUDIO", "OPCIONES", "SALIR"
]
const MENU_ACTIONS: Array[StringName] = [
	&"start_requested",
	&"tutorial_requested",
	&"calibration_requested",
	&"options_requested",
	&"quit_requested",
]
const BUTTON_NAMES: Array[StringName] = [
	"StartButton", "TutorialButton", "CalibrationButton", "OptionsButton", "QuitButton"
]

# --- Layout (1280x720 fixed canvas, §12.1) ---------------------------------
const LOGO_POS := Vector2(96, 64)
const LOGO_SIZE := Vector2(640, 192)
const TAGLINE_POS := Vector2(96, 266)
const MISSION_CHIP := Rect2(96, 292, 480, 26)
const PLATE_RECT := Rect2(96, 336, 560, 300)
const MENU_X := 120.0
const MENU_Y := 356.0
const MENU_WIDTH := 512.0
const MENU_ROW_HEIGHT := 52
const RECORD_RECT := Rect2(952, 32, 264, 92)
const LEGEND_X := 96.0
const LEGEND_Y := 650.0
const LEGEND_LINE_H := 16.0
const FOOTER_RECT := Rect2(640, 682, 544, 14)
const FOOTER_BAND := Rect2(0, 636, 1280, 84)

const PROP_MIN_ART_X := 80.0
const SPRITE_DIR := "res://assets/sprites/"
const LAYOUT_PATH := "res://data/layout.json"
const RANK_COLORS := {
	"S": Palette.FUNK_MAGENTA,
	"A": Palette.FUNK_CYAN,
	"B": Palette.METAL_3,
	"C": Palette.METAL_1,
}

var _buttons: Array[Button] = []
var _sheets: Dictionary = {}
var _star_layer: Control
var _record_plaque: Panel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	_build_backdrop()
	_build_brand()
	_build_menu()
	_build_footer()
	UITheme.wire_audio(self)
	Settings.settings_changed.connect(_refresh_record)
	_refresh_record.call_deferred()
	focus_first.call_deferred()


## Default focus: the primary action, never a destructive one.
func focus_first() -> void:
	if _buttons.is_empty():
		return
	_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		focus_quit()
		get_viewport().set_input_as_handled()


## ESC lands on SALIR instead of quitting: the exit is always one deliberate press away.
func focus_quit() -> void:
	if _buttons.is_empty():
		return
	_buttons[_buttons.size() - 1].grab_focus()


# --- Backdrop ---------------------------------------------------------------


## The room itself, populated from `data/layout.json`, dimmed so type stays legible.
## Never a black screen: if the props are missing the room plate is still drawn.
func _build_backdrop() -> void:
	var room := TextureRect.new()
	room.name = "Room"
	room.texture = _sheet("env_room", Vector2i(320, 180))
	room.position = Vector2.ZERO
	room.size = Vector2(1280, 720)
	room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	room.stretch_mode = TextureRect.STRETCH_SCALE
	room.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if room.texture == null:
		room.texture = _fallback_room_texture()
	if room.texture != null:
		add_child(room)

	_build_props()

	_star_layer = Control.new()
	_star_layer.name = "Dust"
	_star_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_star_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_star_layer)
	_star_layer.draw.connect(_on_dust_draw)

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(Palette.SPACE_VOID, 0.52)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# The footer band keeps the control legend and version line legible over the south belt.
	var footer_band := ColorRect.new()
	footer_band.name = "FooterBand"
	footer_band.color = Color(Palette.SPACE_VOID, 0.72)
	footer_band.position = FOOTER_BAND.position
	footer_band.size = FOOTER_BAND.size
	footer_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer_band)


## Static diorama props: four washers, the chute, belts and shredders in their real places.
func _build_props() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if not (parsed is Dictionary):
		return
	var layout := parsed as Dictionary
	var props := Control.new()
	props.name = "Props"
	props.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(props)
	# The brand and the menu own the left half, so only machinery that lives on the right
	# side of the room is instanced: nothing may be cut in half by the menu plate.
	for washer in layout.get("washers", []):
		if _on_right(washer, 0.0):
			_prop(props, "mach_washer", Vector2i(48, 48), _art_rect(washer, Vector2(48, 48)))
	for shredder in layout.get("shredders", []):
		# The north-east corner belongs to the MEJOR TURNO plaque, so its shredder is skipped.
		if _on_right(shredder, 0.0) and float(shredder.get("y", 0)) > 20.0:
			_prop(props, "env_shredder", Vector2i(32, 32), _art_rect(shredder, Vector2(32, 32)))
	# Belts are deliberately left out of the title: the scroll chevrons fight the wordmark and
	# a belt cut by the menu plate or the footer reads as a mistake.
	# Pip stands where the nest of cables ends, out of the way of the type.
	_prop(props, "char_pip", Vector2i(24, 24), Rect2(Vector2(812, 452), Vector2(96, 96)))


## Prop filter: right-hand machinery only (`PROP_MIN_ART_X` is the middle of the room).
func _on_right(entry: Dictionary, _unused: float) -> bool:
	return float(entry.get("x", 0)) >= PROP_MIN_ART_X


func _art_rect(entry: Dictionary, default_size: Vector2) -> Rect2:
	var size := Vector2(
		float(entry.get("w", default_size.x)), float(entry.get("h", default_size.y))
	)
	return Rect2(Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))), size)


func _tile_belt(parent: Control, belt: Dictionary) -> void:
	var rect := _art_rect(belt, Vector2(16, 16))
	var horizontal := rect.size.x >= rect.size.y
	var length := rect.size.x if horizontal else rect.size.y
	var offset := 0.0
	while offset + 16.0 <= length + 0.5:
		var cell := Rect2(rect.position, Vector2(16, 16))
		if horizontal:
			cell.position.x += offset
		else:
			cell.position.y += offset
		_prop(parent, "env_belt", Vector2i(16, 16), cell)
		offset += 16.0


func _prop(parent: Control, sheet_name: String, frame_size: Vector2i, art_rect: Rect2) -> void:
	var texture := _sheet(sheet_name, frame_size)
	if texture == null:
		return
	var node := TextureRect.new()
	node.texture = texture
	node.position = art_rect.position * Config.ART_SCALE
	node.size = art_rect.size * Config.ART_SCALE
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)


## First frame of a sheet as an AtlasTexture, cached per sheet.
func _sheet(sheet_name: String, frame_size: Vector2i) -> Texture2D:
	var key := "%s:%dx%d" % [sheet_name, frame_size.x, frame_size.y]
	if _sheets.has(key):
		return _sheets[key] as Texture2D
	var path := SPRITE_DIR + sheet_name + ".png"
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var sheet := load(path) as Texture2D
		if sheet != null:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(Vector2.ZERO, Vector2(frame_size))
			texture = atlas
	_sheets[key] = texture
	return texture


## Last-resort background: a flat deep-space plate with two haze bands, still not black.
func _fallback_room_texture() -> Texture2D:
	var image := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	image.fill(Palette.SPACE_VOID)
	for y in range(60, 180):
		for x in range(320):
			if (x + y) % 2 == 0:
				image.set_pixel(x, y, Palette.SPACE_DEEP)
	var texture := ImageTexture.create_from_image(image)
	return texture


func _on_dust_draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240117
	for index in range(90):
		var x := float(rng.randi_range(0, 1279))
		var y := float(rng.randi_range(0, 719))
		var size := 1.0 if index % 5 != 0 else 2.0
		var alpha := rng.randf_range(0.12, 0.42)
		_star_layer.draw_rect(
			Rect2(Vector2(x, y), Vector2(size, size)), Color(Palette.METAL_3, alpha)
		)
	_star_layer.draw_rect(Rect2(0, 0, 1280, 2), Color(Palette.FUNK_TEAL, 0.55))


# --- Brand ------------------------------------------------------------------


func _build_brand() -> void:
	var logo := TextureRect.new()
	logo.name = "Logo"
	logo.texture = _sheet("ui_logo", Vector2i(160, 48))
	logo.position = LOGO_POS
	logo.size = LOGO_SIZE
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_SCALE
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if logo.texture != null:
		add_child(logo)
	else:
		var wordmark := UITheme.label("COSMIC SPIN CYCLE", UITheme.FONT_TITLE, UITheme.INK, true)
		wordmark.position = LOGO_POS
		add_child(wordmark)

	var tagline := UITheme.label(TAGLINE, UITheme.FONT_BODY, Palette.METAL_2)
	tagline.name = "Tagline"
	tagline.position = TAGLINE_POS
	add_child(tagline)

	var mission := UITheme.label(MISSION, UITheme.FONT_SMALL, Palette.METAL_3)
	mission.name = "Mission"
	mission.position = MISSION_CHIP.position + Vector2(12, 6)
	var chip_width := (
		(
			mission
			. get_theme_font("font")
			. get_string_size(MISSION, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL)
			. x
		)
		+ 28.0
	)
	var chip := ColorRect.new()
	chip.name = "MissionChip"
	chip.color = Color(Palette.SPACE_VOID, 0.82)
	chip.position = MISSION_CHIP.position
	chip.size = Vector2(chip_width, MISSION_CHIP.size.y)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chip)

	var chip_tick := ColorRect.new()
	chip_tick.name = "MissionTick"
	chip_tick.color = UITheme.ACCENT
	chip_tick.position = MISSION_CHIP.position
	chip_tick.size = Vector2(2, MISSION_CHIP.size.y)
	chip_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chip_tick)
	add_child(mission)


# --- Menu -------------------------------------------------------------------


func _build_menu() -> void:
	var plate := UITheme.panel(PLATE_RECT)
	plate.name = "MenuPlate"
	add_child(plate)
	var column := VBoxContainer.new()
	column.name = "Menu"
	column.position = Vector2(MENU_X - PLATE_RECT.position.x, MENU_Y - PLATE_RECT.position.y)
	column.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	column.add_theme_constant_override("separation", 0)
	plate.add_child(column)
	for index in range(MENU_ROWS.size()):
		var row := _menu_row(MENU_ROWS[index])
		row.name = String(BUTTON_NAMES[index])
		column.add_child(row)
		_buttons.append(row)
		row.pressed.connect(_on_row_pressed.bind(MENU_ACTIONS[index]))


func _menu_row(caption: String) -> Button:
	var row := UITheme.button(caption, UITheme.FONT_H1)
	row.custom_minimum_size = Vector2(MENU_WIDTH, MENU_ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("normal", _row_box(Palette.SPACE_MID, 0.0, 0))
	row.add_theme_stylebox_override("hover", _row_box(Palette.SPACE_MID, 0.42, 0))
	row.add_theme_stylebox_override("pressed", _row_box(Palette.SPACE_MID, 0.55, 2))
	row.add_theme_stylebox_override("focus", _row_box(Palette.SPACE_MID, 0.0, 2))
	row.add_theme_color_override("font_color", Palette.METAL_2)

	var caret := row.get_node_or_null("Caret") as Control
	if caret != null:
		caret.position = Vector2(16, -UITheme.FONT_H1 * 0.5 - 2)
		(caret as Label).add_theme_font_size_override("font_size", UITheme.FONT_H2)

	var label_width := (
		row
		. get_theme_font("font")
		. get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_H1)
		. x
	)
	var underline := ColorRect.new()
	underline.name = "FocusUnderline"
	underline.color = UITheme.ACCENT
	underline.position = Vector2(46, MENU_ROW_HEIGHT - 10)
	underline.size = Vector2(label_width + 10, 2)
	underline.visible = false
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(underline)

	var hairline := ColorRect.new()
	hairline.name = "Hairline"
	hairline.color = Color(Palette.METAL_0, 0.55)
	hairline.position = Vector2(0, MENU_ROW_HEIGHT - 1)
	hairline.size = Vector2(MENU_WIDTH, 1)
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
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


func _on_row_pressed(action: StringName) -> void:
	emit_signal(action)


# --- Record plaque ----------------------------------------------------------


## Only shown when a run actually exists in `Settings` — never invented data.
## Rebuilt whenever settings change (a finished shift records a new best).
func _refresh_record() -> void:
	if _record_plaque != null and is_instance_valid(_record_plaque):
		_record_plaque.queue_free()
		_record_plaque = null
	if Settings.best_score <= 0:
		return
	var plaque := UITheme.panel(RECORD_RECT)
	_record_plaque = plaque
	plaque.name = "RecordPlaque"
	add_child(plaque)

	var caption := UITheme.label("MEJOR TURNO", UITheme.FONT_MICRO, Palette.METAL_1)
	caption.position = Vector2(22, 12)
	plaque.add_child(caption)

	var rank_value: Variant = RANK_COLORS.get(Settings.best_rank)
	var rank_color: Color = rank_value if rank_value is Color else Palette.METAL_2
	var rank := UITheme.label(Settings.best_rank, UITheme.FONT_TITLE, rank_color, true)
	rank.name = "BestRank"
	rank.position = Vector2(22, 28)
	plaque.add_child(rank)

	var score := UITheme.label(_format_score(Settings.best_score), UITheme.FONT_H2, Palette.METAL_3)
	score.name = "BestScore"
	score.position = Vector2(0, 48)
	score.size = Vector2(RECORD_RECT.size.x - 24, 24)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	plaque.add_child(score)


## 12500 → "012 500"; the end screen uses the same grouping.
static func _format_score(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	while digits.length() > 3:
		grouped = " " + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	grouped = digits + grouped
	return ("-" if value < 0 else "") + grouped


# --- Footer -----------------------------------------------------------------


func _build_footer() -> void:
	for index in range(LEGEND_LINES.size()):
		var line := UITheme.label(LEGEND_LINES[index], UITheme.FONT_MICRO, Palette.METAL_1)
		line.name = "Legend%d" % index
		line.position = Vector2(LEGEND_X, LEGEND_Y + float(index) * LEGEND_LINE_H)
		add_child(line)

	var footer := UITheme.label(VERSION_LINE, UITheme.FONT_MICRO, Palette.METAL_1)
	footer.name = "Footer"
	footer.position = FOOTER_RECT.position
	footer.size = FOOTER_RECT.size
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(footer)

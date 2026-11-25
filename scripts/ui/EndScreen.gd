extends Control
## End screen (docs/UX_BIBLE.md §12.5).
##
## The one screen that answers "how did the shift go": verdict, rank, and a ledger of the
## numbers that produced it. `App` fills it with `setup(result)` before adding it to the
## tree; when the scene is previewed on its own (screenshot harness) a demo result is used
## so the layout is reproducible without playing a shift.
##
## Focus order: REPETIR → MENÚ → NUEVA SEMILLA. ESC goes back to the menu (no dead ends).

signal retry_requested
signal new_seed_requested
signal menu_requested

const VERDICT_WIN := "TURNO COMPLETADO"
const VERDICT_LOSS := "DESGARRO UNIVERSAL"
const RETRY_TEXT := "REPETIR"
const MENU_TEXT := "MENÚ"
const NEW_SEED_TEXT := "NUEVA SEMILLA"
const HINT_TEXT := "ESC · MENÚ"
const RANK_SCALE_TIME := 0.24
const RANK_COLORS := {
	"S": Palette.FUNK_MAGENTA,
	"A": Palette.FUNK_CYAN,
	"B": Palette.METAL_3,
	"C": Palette.METAL_1,
}
const REASONS := {
	"stability": "ESTABILIDAD AGOTADA · 0 %",
	"shift_complete": "06:00 · TURNO CERRADO",
}
const LEDGER: Array[String] = [
	"LAVADAS", "ENTREGADAS", "PRECISIÓN", "COMBO MÁX", "PUNTOS", "SEMILLA"
]
## stat index, column, row — the four numbers that explain the run come first (UX_RESEARCH
## §13: "4 stats (washed, accuracy %, max combo, score)"), the other two sit a step below.
const LEDGER_SLOTS: Array[Array] = [
	[0, 0, 0], [2, 1, 0], [3, 0, 1], [4, 1, 1], [1, 0, 2], [5, 1, 2]
]

const PLAQUE := Rect2(280, 80, 720, 560)
const CONTENT_X := 312.0
const CONTENT_RIGHT := 968.0
const VERDICT_Y := 116.0
const REASON_Y := 164.0
const RULE_Y := 188.0
const RANK_CAPTION_Y := 210.0
const RANK_Y := 228.0
const RANK_SIZE := 96
const LEDGER_X := 536.0
const LEDGER_COL_W := 208.0
const LEDGER_ROWS: Array[float] = [212.0, 292.0, 362.0]
## Focus ring geometry: 2 px cyan + 1 px void gap (UX_RESEARCH §5, §8).
const RING_WIDTH := 2.0
const RING_GAP := 1.0
const LADDER_CAPTION_Y := 340.0
const LADDER_Y := 354.0
const LADDER_STEP := 26.0
const RHYTHM_Y := 404.0
const RULE_2_Y := 428.0
const BUTTON_Y := 492.0
const BUTTON_H := 48
const HINT_Y := 566.0

## Demo data for standalone previews; never used when `App` calls `setup()`.
@export var preview_result: Dictionary = {
	"victory": true,
	"reason": "shift_complete",
	"score": 18450,
	"accuracy": 0.93,
	"perfect": 64,
	"good": 12,
	"miss": 5,
	"max_combo": 7,
	"delivered": 41,
	"washed": 58,
	"exploded": 1,
	"seed": 7001,
	"rank": "S",
}

var _result: Dictionary = {}
var _built := false
var _buttons: Array[Button] = []
var _rank_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	_build()
	UITheme.wire_audio(self)
	# Focus is taken on the first frame, not the second: the screen is interactive at once.
	focus_first()


## Called by `App` before the screen enters the tree; also safe to call while shown.
func setup(result: Dictionary) -> void:
	_result = result.duplicate(true)
	if _built:
		_rebuild()


func focus_first() -> void:
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()


## ESC is the way back to the menu; REPETIR stays the default focus.
func cancel() -> void:
	menu_requested.emit()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_buttons.clear()
	_build()


func _data() -> Dictionary:
	if not _result.is_empty():
		return _result
	return preview_result


func _build() -> void:
	_built = true
	var data := _data()
	var victory := bool(data.get("victory", false))
	var rank := String(data.get("rank", "C"))
	if not victory:
		rank = "C"

	add_child(UITheme.dimmer(0.82))

	var plaque := _panel(PLAQUE)
	plaque.name = "Plaque"
	add_child(plaque)

	var verdict := (
		UITheme
		. label(
			VERDICT_WIN if victory else VERDICT_LOSS,
			UITheme.FONT_TITLE,
			UITheme.SUCCESS if victory else UITheme.DANGER,
			true,
		)
	)
	verdict.name = "Verdict"
	verdict.position = Vector2(CONTENT_X, VERDICT_Y) - PLAQUE.position
	plaque.add_child(verdict)

	var reason := UITheme.label(_reason_text(data), UITheme.FONT_LABEL, Palette.METAL_2)
	reason.name = "Reason"
	reason.position = Vector2(CONTENT_X, REASON_Y) - PLAQUE.position
	plaque.add_child(reason)

	_rule(plaque, RULE_Y)

	var rank_caption := UITheme.label("RANGO", UITheme.FONT_SMALL, Palette.METAL_1)
	rank_caption.name = "RankCaption"
	rank_caption.position = Vector2(CONTENT_X, RANK_CAPTION_Y) - PLAQUE.position
	plaque.add_child(rank_caption)

	var rank_value: Variant = RANK_COLORS.get(rank)
	var rank_color: Color = rank_value if rank_value is Color else Palette.METAL_1
	var rank_label := UITheme.label(rank, RANK_SIZE, rank_color, true)
	rank_label.name = "Rank"
	rank_label.position = Vector2(CONTENT_X, RANK_Y) - PLAQUE.position
	plaque.add_child(rank_label)
	_animate_rank(rank_label)

	_build_ledger(plaque, data)
	_build_rank_ladder(plaque, rank)

	var rhythm := UITheme.label(_rhythm_text(data), UITheme.FONT_SMALL, Palette.METAL_2)
	rhythm.name = "Rhythm"
	rhythm.position = Vector2(CONTENT_X, RHYTHM_Y) - PLAQUE.position
	plaque.add_child(rhythm)

	_rule(plaque, RULE_2_Y)

	var retry := UITheme.action(RETRY_TEXT, 200, true)
	retry.name = "RetryButton"
	retry.position = Vector2(CONTENT_X, BUTTON_Y) - PLAQUE.position
	retry.custom_minimum_size = Vector2(200, float(BUTTON_H))
	retry.pressed.connect(_on_retry_pressed)
	retry.mouse_entered.connect(retry.grab_focus)
	_style_action(retry)
	plaque.add_child(retry)
	_focus_ring(retry, Vector2(200, float(BUTTON_H)))
	_buttons.append(retry)

	var menu := UITheme.action(MENU_TEXT, 160, false)
	menu.name = "MenuButton"
	menu.position = Vector2(CONTENT_X + 216.0, BUTTON_Y) - PLAQUE.position
	menu.custom_minimum_size = Vector2(160, float(BUTTON_H))
	menu.pressed.connect(_on_menu_pressed)
	menu.mouse_entered.connect(menu.grab_focus)
	_style_action(menu)
	plaque.add_child(menu)
	_focus_ring(menu, Vector2(160, float(BUTTON_H)))
	_buttons.append(menu)

	var new_seed := UITheme.action(NEW_SEED_TEXT, 240, false)
	new_seed.name = "NewSeedButton"
	new_seed.position = Vector2(CONTENT_RIGHT - 240.0, BUTTON_Y) - PLAQUE.position
	new_seed.custom_minimum_size = Vector2(240, float(BUTTON_H))
	new_seed.pressed.connect(_on_new_seed_pressed)
	new_seed.mouse_entered.connect(new_seed.grab_focus)
	_style_action(new_seed)
	plaque.add_child(new_seed)
	_focus_ring(new_seed, Vector2(240, float(BUTTON_H)))
	_buttons.append(new_seed)

	for index in range(_buttons.size()):
		var button := _buttons[index]
		button.focus_neighbor_left = button.get_path_to(_buttons[posmod(index - 1, 3)])
		button.focus_neighbor_right = button.get_path_to(_buttons[posmod(index + 1, 3)])

	var hint := UITheme.label(HINT_TEXT, UITheme.FONT_SMALL, Palette.METAL_1)
	hint.name = "Hint"
	hint.position = Vector2(CONTENT_X, HINT_Y) - PLAQUE.position
	plaque.add_child(hint)


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


## 2 px `funk_cyan` ring with a 1 px `space_void` gap (10.9:1 on `space_deep`).
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


## Width of a bold 12 px caption, so the inline secondary value clears it.
func _text_width(text: String) -> float:
	return (
		UITheme
		. font_bold()
		. get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL)
		. x
	)


func _rule(parent: Control, y: float) -> void:
	var rule := ColorRect.new()
	rule.color = Color(Palette.METAL_1, 0.9)
	rule.position = Vector2(CONTENT_X, y) - PLAQUE.position
	rule.size = Vector2(CONTENT_RIGHT - CONTENT_X, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)


## S · A · B · C under the big letter: the end screen also teaches what the ranks mean.
func _build_rank_ladder(parent: Control, rank: String) -> void:
	var caption := UITheme.label("ESCALA", UITheme.FONT_SMALL, Palette.METAL_1)
	caption.name = "LadderCaption"
	caption.position = Vector2(CONTENT_X, LADDER_CAPTION_Y) - PLAQUE.position
	parent.add_child(caption)
	var letters: Array[String] = ["S", "A", "B", "C"]
	for index in range(letters.size()):
		var letter := letters[index]
		var achieved := letter == rank
		var color_value: Variant = RANK_COLORS.get(letter)
		var color: Color = color_value if color_value is Color else Palette.METAL_1
		var label := (
			UITheme
			. label(
				letter,
				UITheme.FONT_LABEL if achieved else UITheme.FONT_SMALL,
				color if achieved else Color(Palette.METAL_2, 0.82),
				achieved,
			)
		)
		label.name = "Ladder%s" % letter
		label.position = (
			Vector2(CONTENT_X + float(index) * LADDER_STEP, LADDER_Y) - PLAQUE.position
		)
		parent.add_child(label)


## Ledger: four primary numbers (LAVADAS, PRECISIÓN, COMBO MÁX, PUNTOS) read first, then
## ENTREGADAS and SEMILLA one step smaller — same six values, explicit hierarchy.
func _build_ledger(parent: Control, data: Dictionary) -> void:
	var values := [
		str(int(data.get("washed", 0))),
		str(int(data.get("delivered", 0))),
		"%d %%" % int(round(float(data.get("accuracy", 0.0)) * 100.0)),
		"×%d" % int(data.get("max_combo", 1)),
		_format_score(int(data.get("score", 0))),
		"#%05d" % (int(data.get("seed", 0)) & 0x7FFFFFFF),
	]
	for slot in LEDGER_SLOTS:
		var index := int(slot[0])
		var x := LEDGER_X + float(int(slot[1])) * LEDGER_COL_W
		var y: float = LEDGER_ROWS[int(slot[2])]
		var primary := int(slot[2]) < 2

		var caption := UITheme.label(
			LEDGER[index], UITheme.FONT_SMALL, Palette.METAL_1, not primary
		)
		caption.name = "Stat%dCaption" % index
		caption.position = Vector2(x, y) - PLAQUE.position
		parent.add_child(caption)

		var value := (
			UITheme
			. label(
				String(values[index]),
				UITheme.FONT_H1 if primary else UITheme.FONT_LABEL,
				Palette.METAL_4 if primary else Palette.METAL_2,
				primary,
			)
		)
		value.name = "Stat%dValue" % index
		# Primary numbers sit under their caption; the two secondary ones stay inline on their
		# caption's baseline so the block reads as a footnote, not as a third row of stats.
		var offset := (
			Vector2(0.0, 18.0) if primary else Vector2(_text_width(LEDGER[index]) + 18.0, 0.0)
		)
		value.position = Vector2(x, y) + offset - PLAQUE.position
		parent.add_child(value)


## 240 ms scale-in for the rank letter, skipped entirely when reduce motion is on.
func _animate_rank(label: Label) -> void:
	if Settings.reduce_motion:
		return
	label.pivot_offset = Vector2(0, 0)
	label.scale = Vector2(0.72, 0.72)
	_rank_tween = create_tween()
	_rank_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_rank_tween.tween_property(label, "scale", Vector2.ONE, RANK_SCALE_TIME)


## Any input cuts the 240 ms rank animation short: nothing on this screen may delay REPETIR.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton):
		return
	if _rank_tween != null and _rank_tween.is_valid():
		_rank_tween.kill()
		var rank := get_node_or_null("Plaque/Rank") as Control
		if rank != null:
			rank.scale = Vector2.ONE


func _reason_text(data: Dictionary) -> String:
	var reason := String(data.get("reason", ""))
	if REASONS.has(reason):
		return String(REASONS[reason])
	if bool(data.get("victory", false)):
		return "TURNO CERRADO"
	return "TURNO PERDIDO"


func _rhythm_text(data: Dictionary) -> String:
	return (
		"PERFECTOS %d · BIEN %d · FALLOS %d"
		% [
			int(data.get("perfect", 0)),
			int(data.get("good", 0)),
			int(data.get("miss", 0)),
		]
	)


## 12500 → "12 500"; the title screen uses the same grouping.
static func _format_score(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	while digits.length() > 3:
		grouped = " " + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	grouped = digits + grouped
	return ("-" if value < 0 else "") + grouped


func _on_retry_pressed() -> void:
	retry_requested.emit()


func _on_menu_pressed() -> void:
	menu_requested.emit()


func _on_new_seed_pressed() -> void:
	new_seed_requested.emit()

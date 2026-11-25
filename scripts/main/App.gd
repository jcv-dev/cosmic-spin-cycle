extends Node
## Application shell: owns the screen flow and the lifetime of a shift.
##
## Title → (first-run prompt) → shift or tutorial → pause / options → end → title.
## The game world lives in a child `MainLevel`; every other screen is a Control instanced
## in `UI` (a CanvasLayer above the world). Screens are pure presentation: they emit
## intent signals, this node decides.
##
## Screens are optional at runtime (`ResourceLoader.exists` guards) so the project always
## boots even while a screen is being authored by another workstream.

signal screen_changed(screen: StringName)

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const FIRST_RUN_SCENE := "res://scenes/ui/FirstRunPrompt.tscn"
const PAUSE_SCENE := "res://scenes/ui/PauseOverlay.tscn"
const END_SCENE := "res://scenes/ui/EndScreen.tscn"
const OPTIONS_SCENE := "res://scenes/ui/OptionsScreen.tscn"
const CALIBRATION_SCENE := "res://scenes/ui/CalibrationModal.tscn"
const TUTORIAL_SCENE := "res://scenes/main/Tutorial.tscn"
const MUSIC_MANIFEST := "res://assets/audio/music.json"
const MUSIC_DIR := "res://assets/audio/music/"

var level: Node = null
var is_paused := false
var current_screen: StringName = &""
var run_seed := 0
var last_result: Dictionary = {}

var _ui: CanvasLayer
var _fade: ColorRect
var _screen: Control = null
var _options: Control = null
var _ambient: AudioStreamPlayer
var _fade_tween: Tween
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_ui.layer = 20
	add_child(_ui)
	_build_fade()
	_setup_ambient()
	var boot := _boot_screen()
	if boot == &"shift" or boot == &"tutorial":
		start_shift(boot == &"tutorial")
	else:
		show_title(true)
	Settings.settings_changed.connect(_on_settings_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or event.is_echo():
		return
	if _options != null:
		_close_options()
		get_viewport().set_input_as_handled()
		return
	if current_screen != &"shift" and current_screen != &"tutorial":
		return
	if level == null or bool(level.call("is_ended")):
		return
	_toggle_pause()
	get_viewport().set_input_as_handled()


# --- Public flow ------------------------------------------------------------


func show_title(instant: bool = false) -> void:
	if _busy:
		return
	_busy = true
	await _unload_level()
	_clear_screens()
	_play_ambient()
	var title := _instance(TITLE_SCENE)
	if title == null:
		title = _fallback_title()
	_screen = title
	_ui.add_child(title)
	_connect_screen(
		title,
		{
			"start_requested": _on_title_start,
			"tutorial_requested": _on_title_tutorial,
			"options_requested": _on_title_options,
			"calibration_requested": _on_title_calibration,
			"quit_requested": _on_title_quit,
		}
	)
	_screen_name(&"title")
	_focus_first(title)
	_busy = false
	if instant:
		_set_fade(0.0)
	else:
		_fade_in(0.22)


## Starts a shift. `with_tutorial` starts the tutorial instead of the shift.
func start_shift(with_tutorial: bool = false) -> void:
	if _busy:
		return
	_busy = true
	_stop_ambient()
	_clear_screens()
	await _unload_level()
	run_seed = Settings.db_seed
	GameState.reset(run_seed)
	run_seed = GameState.seed_value
	var node := _spawn_level(with_tutorial)
	if node == null:
		_busy = false
		show_title()
		return
	level = node
	_screen_name(&"tutorial" if with_tutorial else &"shift")
	_busy = false
	_fade_in(0.18)


func restart_shift() -> void:
	var was_tutorial := current_screen == &"tutorial"
	start_shift(was_tutorial)


func quit_to_menu() -> void:
	show_title()


# --- Screen wiring ----------------------------------------------------------


func _on_title_start() -> void:
	if Settings.needs_first_run_prompt():
		_show_first_run_prompt()
	else:
		start_shift(false)


func _on_title_tutorial() -> void:
	start_shift(true)


func _on_title_options() -> void:
	_open_options(false)


func _on_title_calibration() -> void:
	_open_calibration()


func _on_title_quit() -> void:
	get_tree().quit()


func _show_first_run_prompt() -> void:
	var prompt := _instance(FIRST_RUN_SCENE)
	if prompt == null:
		# No prompt authored yet: go straight to the shift but remember the choice.
		Settings.mark_first_run_done()
		start_shift(false)
		return
	_ui.add_child(prompt)
	_connect_screen(
		prompt,
		{
			"tutorial_selected":
			func() -> void:
## Application shell: owns the screen flow and the lifetime of a shift.
##
## Title → (first-run prompt) → shift or tutorial → pause / options → end → title.
## The game world lives in a child `MainLevel`; every other screen is a Control instanced
## in `UI` (a CanvasLayer above the world). Screens are pure presentation: they emit
## intent signals, this node decides.
##
## Screens are optional at runtime (`ResourceLoader.exists` guards) so the project always
## boots even while a screen is being authored by another workstream.

# --- Public flow ------------------------------------------------------------

## Starts a shift. `with_tutorial` starts the tutorial instead of the shift.

# --- Screen wiring ----------------------------------------------------------

				# No prompt authored yet: go straight to the shift but remember the choice.

				prompt.queue_free()
				start_shift(true),
			"skip_selected":
			func() -> void:
## Application shell: owns the screen flow and the lifetime of a shift.
##
## Title → (first-run prompt) → shift or tutorial → pause / options → end → title.
## The game world lives in a child `MainLevel`; every other screen is a Control instanced
## in `UI` (a CanvasLayer above the world). Screens are pure presentation: they emit
## intent signals, this node decides.
##
## Screens are optional at runtime (`ResourceLoader.exists` guards) so the project always
## boots even while a screen is being authored by another workstream.

# --- Public flow ------------------------------------------------------------

## Starts a shift. `with_tutorial` starts the tutorial instead of the shift.

# --- Screen wiring ----------------------------------------------------------

				# No prompt authored yet: go straight to the shift but remember the choice.

				prompt.queue_free()
				start_shift(false),
			"closed": prompt.queue_free,
		}
	)


func _spawn_level(with_tutorial: bool) -> Node:
	var path := TUTORIAL_SCENE if with_tutorial else Config.SCENE_MAIN_LEVEL
	var packed := _load_scene(path)
	if packed == null and with_tutorial:
		packed = _load_scene(Config.SCENE_MAIN_LEVEL)
	if packed == null:
		push_error("APP: cannot load level scene")
		return null
	var node := packed.instantiate()
	if with_tutorial and node.has_method("is_tutorial_level"):
		pass
	elif node.get("mode") != null:
		node.set("mode", &"tutorial" if with_tutorial else &"shift")
	add_child(node)
	if node.has_signal("shift_finished"):
		node.connect("shift_finished", _on_shift_finished)
	if node.has_signal("tutorial_completed"):
		node.connect("tutorial_completed", _on_tutorial_completed)
	if node.has_signal("shift_started"):
		node.emit_signal("shift_started")
	return node


func _on_shift_finished(result: Dictionary) -> void:
	last_result = result.duplicate(true)
	last_result["rank"] = _rank_for(result)
	var rank_letter := String(last_result.get("rank", "C"))
	Settings.record_result(int(result.get("score", 0)), rank_letter)
	_show_end(last_result)


func _on_tutorial_completed() -> void:
	Settings.mark_tutorial_completed()
	show_title()


func _show_end(result: Dictionary) -> void:
	var screen := _instance(END_SCENE)
	if screen == null:
		return
	if screen.has_method("setup"):
		screen.call("setup", result)
	_ui.add_child(screen)
	_screen = screen
	_focus_first(screen)
	_screen_name(&"end")
	_connect_screen(
		screen,
		{
			"retry_requested": restart_shift,
			"new_seed_requested":
			func() -> void:
## Application shell: owns the screen flow and the lifetime of a shift.
##
## Title → (first-run prompt) → shift or tutorial → pause / options → end → title.
## The game world lives in a child `MainLevel`; every other screen is a Control instanced
## in `UI` (a CanvasLayer above the world). Screens are pure presentation: they emit
## intent signals, this node decides.
##
## Screens are optional at runtime (`ResourceLoader.exists` guards) so the project always
## boots even while a screen is being authored by another workstream.

# --- Public flow ------------------------------------------------------------

## Starts a shift. `with_tutorial` starts the tutorial instead of the shift.

# --- Screen wiring ----------------------------------------------------------

				# No prompt authored yet: go straight to the shift but remember the choice.

				Settings.db_seed = 0
				restart_shift(),
			"menu_requested": quit_to_menu,
		}
	)


func _rank_for(result: Dictionary) -> String:
	var score := int(result.get("score", 0))
	var accuracy := float(result.get("accuracy", 0.0))
	var victory := bool(result.get("victory", false))
	if ResourceLoader.exists("res://scripts/logic/ScoreRules.gd"):
		var rules := load("res://scripts/logic/ScoreRules.gd") as Script
		if rules.has_method("rank"):
			return String(
				rules.call("rank", float(result.get("score_ratio", 0.0)), accuracy, victory)
			)
	if not victory:
		return "C"
	if accuracy >= Config.RANK_S_ACCURACY and score >= 12000:
		return "S"
	if score >= 8000:
		return "A"
	if score >= 4000:
		return "B"
	return "C"


# --- Pause and options ------------------------------------------------------


func _toggle_pause() -> void:
	if is_paused:
		resume_game()
	else:
		pause_game()


func pause_game() -> void:
	if is_paused or level == null:
		return
	is_paused = true
	get_tree().paused = true
	var overlay := _instance(PAUSE_SCENE)
	if overlay == null:
		overlay = _fallback_pause()
	_ui.add_child(overlay)
	_screen = overlay
	_focus_first(overlay)
	_connect_screen(
		overlay,
		{
			"resume_requested": resume_game,
			"restart_requested":
			func() -> void:
## Application shell: owns the screen flow and the lifetime of a shift.
##
## Title → (first-run prompt) → shift or tutorial → pause / options → end → title.
## The game world lives in a child `MainLevel`; every other screen is a Control instanced
## in `UI` (a CanvasLayer above the world). Screens are pure presentation: they emit
## intent signals, this node decides.
##
## Screens are optional at runtime (`ResourceLoader.exists` guards) so the project always
## boots even while a screen is being authored by another workstream.

# --- Public flow ------------------------------------------------------------

## Starts a shift. `with_tutorial` starts the tutorial instead of the shift.

# --- Screen wiring ----------------------------------------------------------

				# No prompt authored yet: go straight to the shift but remember the choice.

# --- Pause and options ------------------------------------------------------

				resume_game()
				restart_shift(),
			"options_requested": func() -> void: _open_options(true),
			"menu_requested":
			func() -> void:
## Application shell: owns the screen flow and the lifetime of a shift.
##
## Title → (first-run prompt) → shift or tutorial → pause / options → end → title.
## The game world lives in a child `MainLevel`; every other screen is a Control instanced
## in `UI` (a CanvasLayer above the world). Screens are pure presentation: they emit
## intent signals, this node decides.
##
## Screens are optional at runtime (`ResourceLoader.exists` guards) so the project always
## boots even while a screen is being authored by another workstream.

# --- Public flow ------------------------------------------------------------

## Starts a shift. `with_tutorial` starts the tutorial instead of the shift.

# --- Screen wiring ----------------------------------------------------------

				# No prompt authored yet: go straight to the shift but remember the choice.

# --- Pause and options ------------------------------------------------------

				resume_game()
				quit_to_menu(),
		}
	)
	_screen_name(&"pause")


func resume_game() -> void:
	if not is_paused:
		return
	get_tree().paused = false
	is_paused = false
	if _options != null:
		_options.queue_free()
		_options = null
	if _screen != null and current_screen == &"pause":
		_screen.queue_free()
		_screen = null
	current_screen = &"shift" if not _is_tutorial() else &"tutorial"
	screen_changed.emit(current_screen)


func _open_options(from_pause: bool) -> void:
	if _options != null:
		return
	var options := _instance(OPTIONS_SCENE)
	if options == null:
		return
	_options = options
	options.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.add_child(options)
	if options.has_method("open"):
		options.call("open", from_pause)
	_connect_screen(options, {"closed": _close_options})


func _close_options() -> void:
	if _options == null:
		return
	_options.queue_free()
	_options = null


func _open_calibration() -> void:
	var modal := _instance(CALIBRATION_SCENE)
	if modal == null:
		return
	modal.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.add_child(modal)
	if modal.has_method("open"):
		modal.call("open", -1, false)
	_connect_screen(modal, {"closed": modal.queue_free})


# --- Level lifetime ---------------------------------------------------------


func _unload_level() -> void:
	if level == null:
		return
	var dying := level
	level = null
	dying.process_mode = Node.PROCESS_MODE_DISABLED
	dying.queue_free()
	await get_tree().process_frame


func _is_tutorial() -> bool:
	return current_screen == &"tutorial"


# --- Infrastructure ---------------------------------------------------------


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Fade"
	layer.layer = 40
	add_child(layer)
	_fade = ColorRect.new()
	_fade.name = "FadeRect"
	_fade.color = Palette.SPACE_VOID
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	layer.add_child(_fade)


func _set_fade(value: float) -> void:
	if _fade != null:
		_fade.modulate.a = clampf(value, 0.0, 1.0)


func _fade_in(duration: float) -> void:
	if _fade == null:
		return
	if Settings.reduce_motion:
		_set_fade(0.0)
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "modulate:a", 0.0, duration).from(1.0)


func _clear_screens() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null
	if _options != null and is_instance_valid(_options):
		_options.queue_free()
	_options = null
	for child in _ui.get_children():
		if child is Control and child != _fade:
			child.queue_free()
	current_screen = &""
	# A screen may have paused the tree; never leave it paused across screens.
	get_tree().paused = false
	is_paused = false


## Gives keyboard/gamepad focus to the screen's declared default, or the first button.
func _focus_first(screen: Control) -> void:
	if screen.has_method("focus_first"):
		screen.call_deferred("focus_first")
		return
	var first := _find_first_button(screen)
	if first != null:
		first.call_deferred("grab_focus")


func _find_first_button(node: Node) -> BaseButton:
	for child in node.get_children():
		var button := child as BaseButton
		if button != null and button.focus_mode != Control.FOCUS_NONE:
			return button
		var nested := _find_first_button(child)
		if nested != null:
			return nested
	return null


func _screen_name(value: StringName) -> void:
	current_screen = value
	screen_changed.emit(value)


func _instance(path: String) -> Control:
	var packed := _load_scene(path)
	if packed == null:
		return null
	return packed.instantiate() as Control


func _load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


## Connects only the signals a screen actually declares, so partially authored screens
## never crash the flow.
func _connect_screen(screen: Node, handlers: Dictionary) -> void:
	for signal_name in handlers:
		if screen.has_signal(StringName(signal_name)):
			screen.connect(StringName(signal_name), handlers[signal_name])


func _setup_ambient() -> void:
	if not FileAccess.file_exists(MUSIC_MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_MANIFEST))
	if not (parsed is Dictionary):
		return
	var stems: Array = (parsed as Dictionary).get("stems", [])
	if stems.is_empty():
		return
	var path := MUSIC_DIR + String(stems[0].get("file", ""))
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "MenuAmbience"
	_ambient.stream = stream
	_ambient.volume_db = -16.0
	if AudioServer.get_bus_index("Music") >= 0:
		_ambient.bus = "Music"
	add_child(_ambient)


func _play_ambient() -> void:
	if _ambient != null and not _ambient.playing:
		_ambient.play()


func _stop_ambient() -> void:
	if _ambient != null and _ambient.playing:
		_ambient.stop()


func _on_settings_changed() -> void:
	if _ambient != null:
		_ambient.volume_db = -16.0


func _boot_screen() -> StringName:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--autostart="):
			var value := argument.trim_prefix("--autostart=")
			if value == "shift" or value == "tutorial":
				return StringName(value)
	return &"title"


# --- Fallbacks (only used when a screen scene is missing) -------------------


func _fallback_title() -> Control:
	var root := Control.new()
	root.name = "TitleFallback"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.theme()
	var dim := UITheme.dimmer(0.55)
	root.add_child(dim)
	var logo := UITheme.label("COSMIC SPIN CYCLE", UITheme.FONT_TITLE, UITheme.INK, true)
	logo.position = Vector2(120, 120)
	root.add_child(logo)
	var column := VBoxContainer.new()
	column.position = Vector2(120, 300)
	column.custom_minimum_size = Vector2(360, 0)
	root.add_child(column)
	var start := UITheme.button("INICIAR TURNO")
	start.pressed.connect(_on_title_start)
	column.add_child(start)
	var tutorial := UITheme.button("TUTORIAL")
	tutorial.pressed.connect(_on_title_tutorial)
	column.add_child(tutorial)
	var options := UITheme.button("OPCIONES")
	options.pressed.connect(_on_title_options)
	column.add_child(options)
	var quit := UITheme.button("SALIR")
	quit.pressed.connect(_on_title_quit)
	column.add_child(quit)
	return root


func _fallback_pause() -> Control:
	var root := Control.new()
	root.name = "PauseFallback"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.theme = UITheme.theme()
	root.add_child(UITheme.dimmer(0.6))
	var plaque := UITheme.panel(Rect2(380, 200, 520, 320))
	root.add_child(plaque)
	var column := VBoxContainer.new()
	column.position = Vector2(404, 224)
	column.custom_minimum_size = Vector2(472, 0)
	column.add_theme_constant_override("separation", 8)
	plaque.add_child(column)
	column.add_child(UITheme.label("PAUSA", UITheme.FONT_TITLE, UITheme.INK, true))
	var resume := UITheme.button("REANUDAR")
	resume.pressed.connect(resume_game)
	column.add_child(resume)
	var restart := UITheme.button("REINICIAR")
	restart.pressed.connect(
		func() -> void:
			resume_game()
			restart_shift()
	)
	column.add_child(restart)
	var menu := UITheme.button("MENÚ")
	menu.pressed.connect(
		func() -> void:
			resume_game()
			quit_to_menu()
	)
	column.add_child(menu)
	return root

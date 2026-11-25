extends SceneTree
## One-shot project bootstrapper. Run once after checkout, commit the resulting
## project.godot:
##
##   godot --headless --path . -s tools/setup_project.gd
##
## It owns: display/renderer/physics settings, autoload registration and the Input Map.
## It is idempotent.

const AUTOLOADS := [
	["Config", "res://scripts/autoload/Config.gd"],
	["Settings", "res://scripts/autoload/Settings.gd"],
	["GameState", "res://scripts/autoload/GameState.gd"],
	["BeatConductor", "res://scenes/main/BeatConductor.tscn"],
]


func _initialize() -> void:
	_set_project_settings()
	_setup_autoloads()
	_setup_input_map()
	var err := ProjectSettings.save()
	if err == OK:
		print("PROJECT_SETTINGS_SAVED")
	else:
		push_error("ProjectSettings.save failed: %d" % err)
	quit()


func _set_project_settings() -> void:
	ProjectSettings.set_setting("application/config/name", "Cosmic Spin Cycle")
	ProjectSettings.set_setting("application/config/description", "Lavandería al Borde del Vacío")
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/main/Main.tscn")
	ProjectSettings.set_setting(
		"application/config/features", PackedStringArray(["4.7", "GL Compatibility"])
	)
	ProjectSettings.set_setting("application/boot_splash/bg_color", Color("#0B0C10"))
	ProjectSettings.set_setting("application/boot_splash/show_image", false)

	ProjectSettings.set_setting("display/window/size/viewport_width", 1280)
	ProjectSettings.set_setting("display/window/size/viewport_height", 720)
	ProjectSettings.set_setting("display/window/stretch/mode", "canvas_items")
	ProjectSettings.set_setting("display/window/stretch/aspect", "keep")

	ProjectSettings.set_setting("rendering/renderer/rendering_method", "gl_compatibility")
	ProjectSettings.set_setting("rendering/renderer/rendering_method.mobile", "gl_compatibility")
	ProjectSettings.set_setting("rendering/textures/canvas_textures/default_texture_filter", 0)
	ProjectSettings.set_setting(
		"rendering/environment/defaults/default_clear_color", Color("#0B0C10")
	)

	ProjectSettings.set_setting("physics/common/physics_ticks_per_second", 60)
	ProjectSettings.set_setting("physics/2d/default_gravity", 0.0)
	ProjectSettings.set_setting("physics/2d/default_gravity_vector", Vector2.ZERO)

	ProjectSettings.set_setting("layer_names/2d_physics/layer_1", "world")
	ProjectSettings.set_setting("layer_names/2d_physics/layer_2", "player")
	ProjectSettings.set_setting("layer_names/2d_physics/layer_3", "items")
	ProjectSettings.set_setting("layer_names/2d_physics/layer_4", "belt")
	ProjectSettings.set_setting("layer_names/2d_physics/layer_5", "shredder")
	ProjectSettings.set_setting("layer_names/2d_physics/layer_6", "chute")
	ProjectSettings.set_setting("layer_names/2d_physics/layer_7", "washer")


func _setup_autoloads() -> void:
	for entry in AUTOLOADS:
		ProjectSettings.set_setting("autoload/%s" % entry[0], "*%s" % entry[1])


func _setup_input_map() -> void:
	ProjectSettings.clear("input/test_action")

	# Movement: WASD, arrows, left stick.
	_add_action("move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_add_action("move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_add_action("move_up", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add_action("move_down", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])

	# Aim: right stick. The mouse is read as an absolute position by the Player.
	_add_action("aim_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_add_action("aim_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_add_action("aim_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_add_action("aim_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])

	_add_action("grab_throw", [_key(KEY_SPACE), _mouse(MOUSE_BUTTON_LEFT), _button(JOY_BUTTON_A)])
	_add_action(
		"rhythm_strike", [_key(KEY_SHIFT), _mouse(MOUSE_BUTTON_RIGHT), _button(JOY_BUTTON_B)]
	)
	_add_action("pause", [_key(KEY_ESCAPE), _button(JOY_BUTTON_START)])
	_add_action("toggle_debug", [_key(KEY_F10), _button(JOY_BUTTON_BACK)])
	_add_action("debug_f1", [_key(KEY_F1)])
	_add_action("debug_f2", [_key(KEY_F2)])
	_add_action("debug_f3", [_key(KEY_F3)])
	_add_action("debug_f4", [_key(KEY_F4)])


func _add_action(action: String, events: Array[InputEvent]) -> void:
	var dict := {"deadzone": 0.2, "events": events}
	ProjectSettings.set_setting("input/%s" % action, dict)


func _key(keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.device = -1
	ev.physical_keycode = keycode
	return ev


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.device = -1
	ev.button_index = button
	return ev


func _button(button: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = -1
	ev.button_index = button
	return ev


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.device = -1
	ev.axis = axis
	ev.axis_value = value
	return ev

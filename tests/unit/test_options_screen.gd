extends GutTest
## Options screen contract (§12.4): every row is a real control, values persist through
## `Settings`, the readouts mirror the current state and ESC/VOLVER close the screen.

const OPTIONS_SCENE := preload("res://scenes/ui/OptionsScreen.tscn")

var _screen: Control


func before_each() -> void:
	Settings.reset_to_defaults()
	Settings.db_seed = 0
	_screen = OPTIONS_SCENE.instantiate() as Control
	add_child_autofree(_screen)
	await wait_process_frames(2)


func after_each() -> void:
	Settings.reset_to_defaults()
	Settings.db_seed = 0


func test_declares_every_contract_signal() -> void:
	assert_true(_screen.has_signal("closed"))
	assert_true(_screen.has_signal("calibration_requested"))


func test_plaque_is_780x540_and_centred() -> void:
	var plaque := _screen.get_node("Plaque") as Panel
	assert_eq(plaque.size, Vector2(780, 540))
	assert_eq(plaque.position, Vector2(250, 90))


func test_exposes_open_and_focus_first() -> void:
	assert_true(_screen.has_method("open"))
	assert_true(_screen.has_method("focus_first"))
	_screen.open(true)
	await wait_process_frames(1)
	assert_string_contains(_screen.get_node("Plaque/Caption").text, "PAUSA")


func test_focus_first_lands_on_the_master_volume() -> void:
	_screen.focus_first()
	await wait_process_frames(1)
	assert_true((_screen.get_node("Plaque/Slider0") as HSlider).has_focus())


func test_sliders_are_bound_to_settings_and_write_on_change() -> void:
	var slider := _screen.get_node("Plaque/Slider1") as HSlider
	assert_eq(slider.min_value, -30.0)
	assert_eq(slider.max_value, 6.0)
	assert_eq(slider.step, 1.0)
	slider.value = -12.0
	await wait_process_frames(1)
	assert_eq(Settings.music_volume_db, -12.0, "music slider must write Settings")
	assert_eq((_screen.get_node("Plaque/Readout1") as Label).text, "-12 dB")


func test_readouts_reflect_settings_on_open() -> void:
	Settings.master_volume_db = 3.0
	Settings.sfx_volume_db = -18.0
	Settings.fullscreen = true
	Settings.ui_scale = 1.25
	_screen.open(false)
	await wait_process_frames(1)
	assert_eq((_screen.get_node("Plaque/Readout0") as Label).text, "+3 dB")
	assert_eq((_screen.get_node("Plaque/Readout2") as Label).text, "-18 dB")
	assert_eq(
		(_screen.get_node("Plaque/Toggle%d/Value" % 0) as Label).text, "SÍ", "fullscreen readout"
	)
	assert_eq((_screen.get_node("Plaque/Toggle%d/Value" % 2) as Label).text, "125 %")


func test_fullscreen_toggle_flips_the_setting() -> void:
	var before := Settings.fullscreen
	(_screen.get_node("Plaque/Toggle0") as Button).emit_signal("pressed")
	await wait_process_frames(1)
	assert_eq(Settings.fullscreen, not before)
	var expected := "NO" if before else "SÍ"
	assert_eq((_screen.get_node("Plaque/Toggle0/Value") as Label).text, expected)
	Settings.fullscreen = before


func test_reduce_motion_toggle_flips_the_setting() -> void:
	(_screen.get_node("Plaque/Toggle1") as Button).emit_signal("pressed")
	await wait_process_frames(1)
	assert_true(Settings.reduce_motion)


func test_hud_scale_toggle_cycles_between_the_two_options() -> void:
	(_screen.get_node("Plaque/Toggle2") as Button).emit_signal("pressed")
	await wait_process_frames(1)
	assert_eq(Settings.ui_scale, 1.25)
	(_screen.get_node("Plaque/Toggle2") as Button).emit_signal("pressed")
	await wait_process_frames(1)
	assert_eq(Settings.ui_scale, 1.0)


func test_haptics_toggle_flips_the_setting() -> void:
	var before := Settings.haptics
	(_screen.get_node("Plaque/Toggle3") as Button).emit_signal("pressed")
	await wait_process_frames(1)
	assert_eq(Settings.haptics, not before)
	Settings.haptics = before


func test_calibrate_emits_the_request() -> void:
	watch_signals(_screen)
	(_screen.get_node("Plaque/CalibrateButton") as Button).emit_signal("pressed")
	assert_signal_emitted(_screen, "calibration_requested")


func test_back_button_closes() -> void:
	watch_signals(_screen)
	(_screen.get_node("Plaque/BackButton") as Button).emit_signal("pressed")
	assert_signal_emitted(_screen, "closed")


func test_escape_closes() -> void:
	watch_signals(_screen)
	_screen.close()
	assert_signal_emitted(_screen, "closed")


func test_reset_restores_defaults_and_refreshes() -> void:
	Settings.master_volume_db = -20.0
	Settings.fullscreen = true
	(_screen.get_node("Plaque/ResetButton") as Button).emit_signal("pressed")
	await wait_process_frames(1)
	assert_eq(Settings.master_volume_db, 0.0)
	assert_false(Settings.fullscreen)
	assert_eq((_screen.get_node("Plaque/Readout0") as Label).text, "0 dB")
	assert_eq((_screen.get_node("Plaque/Toggle0/Value") as Label).text, "NO")


func test_every_row_is_focusable() -> void:
	var rows: Array[Control] = []
	for path in [
		"Plaque/Slider0",
		"Plaque/Slider1",
		"Plaque/Slider2",
		"Plaque/CalibrateButton",
		"Plaque/Toggle0",
		"Plaque/Toggle1",
		"Plaque/Toggle2",
		"Plaque/Toggle3",
		"Plaque/ResetButton",
		"Plaque/BackButton",
	]:
		var node := _screen.get_node(path) as Control
		assert_not_null(node, "missing row %s" % path)
		rows.append(node)
	for row in rows:
		assert_ne(row.focus_mode, Control.FOCUS_NONE, "%s must be focusable" % row.name)

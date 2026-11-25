extends GutTest
## App-level screen flow: title → shift → end → restart/menu, with no dead ends.

const MAIN_SCENE := preload("res://scenes/main/Main.tscn")


func before_each() -> void:
	Settings.tutorial_completed = true
	Settings.tutorial_skipped = false
	Settings.first_run_done = true


func after_each() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)


func test_boot_lands_on_the_title() -> void:
	var app := MAIN_SCENE.instantiate()
	add_child_autofree(app)
	await wait_frames(2)
	assert_eq(String(app.get("current_screen")), "title")
	assert_not_null(app.get_node_or_null("UI"))
	assert_null(app.get("level"), "no level is running on the title")


func test_start_shift_builds_a_level_and_pauses() -> void:
	var app := MAIN_SCENE.instantiate()
	add_child_autofree(app)
	await app.call("start_shift", false)
	assert_eq(String(app.get("current_screen")), "shift")
	assert_not_null(app.get("level"), "a level exists after starting a shift")
	app.call("pause_game")
	await wait_frames(1)
	assert_true(bool(app.get("is_paused")))
	assert_true(get_tree().paused, "pause freezes the tree")
	app.call("resume_game")
	await wait_frames(1)
	assert_false(get_tree().paused)
	assert_eq(String(app.get("current_screen")), "shift")


func test_end_screen_has_no_dead_end() -> void:
	var app := MAIN_SCENE.instantiate()
	add_child_autofree(app)
	await app.call("start_shift", false)
	var level := app.get("level") as Node
	assert_not_null(level)
	GameState.add_stability(-500.0, "test")
	await wait_frames(2)
	assert_eq(String(app.get("current_screen")), "end")
	var end_screen := app.get_node_or_null("UI/EndFallback")
	if end_screen == null:
		end_screen = app.get_node_or_null("UI/EndScreen")
	assert_not_null(end_screen, "the end screen is shown")
	app.call("quit_to_menu")
	await wait_frames(12)
	assert_eq(String(app.get("current_screen")), "title")
	assert_null(app.get("level"), "the level is released when returning to the title")

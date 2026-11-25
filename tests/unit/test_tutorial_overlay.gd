# gdlint: disable=max-public-methods
extends GutTest
## The tutorial overlay is the only surface the player reads during the seven gates.

const OVERLAY_SCENE := preload("res://scenes/ui/TutorialOverlay.tscn")


func _spawn() -> TutorialOverlay:
	var overlay := OVERLAY_SCENE.instantiate() as TutorialOverlay
	add_child_autofree(overlay)
	return overlay


func test_overlay_builds_chip_prompt_and_plaques() -> void:
	var overlay := _spawn()
	assert_not_null(overlay.get_node_or_null("Root/StepChip"))
	assert_not_null(overlay.get_node_or_null("Root/StepChip/UnderlineFill"))
	assert_not_null(overlay.get_node_or_null("Root/WorldPrompts/PromptChip"))
	assert_not_null(overlay.get_node_or_null("Root/SkipPlaque"))
	assert_not_null(overlay.get_node_or_null("Root/CompletePlaque"))
	assert_false(overlay.is_skip_open())
	assert_false(overlay.is_completion_open())


func test_chip_starts_on_gate_one() -> void:
	var overlay := _spawn()
	assert_eq(overlay.chip_step_text(), "PASO 1/7")
	assert_eq(overlay.chip_title_text(), "MUÉVETE")
	assert_eq(overlay.step_index(), 0)


func test_chip_tracks_the_step_and_the_underline_progress() -> void:
	var overlay := _spawn()
	overlay.set_step(1, 0.0)
	assert_eq(overlay.chip_step_text(), "PASO 2/7")
	assert_eq(overlay.chip_title_text(), "AGARRA")
	assert_almost_eq(overlay.underline_ratio(), 0.0, 0.01)
	overlay.set_progress(0.5)
	assert_almost_eq(overlay.underline_ratio(), 0.5, 0.02)
	overlay.set_progress(1.0)
	assert_almost_eq(overlay.underline_ratio(), 1.0, 0.02)


func test_chip_stays_inside_the_top_safe_rect() -> void:
	var overlay := _spawn()
	overlay.set_step(6, 1.0)
	var rect := overlay.chip_rect()
	assert_gte(rect.position.y, 0.0)
	assert_lte(rect.end.y, 104.0, "the chip must never leave the top band")
	assert_gte(rect.position.x, 0.0)
	assert_lte(rect.end.x, 1280.0)


func test_prompt_is_world_anchored_and_fades_without_covering_the_mouth() -> void:
	var overlay := _spawn()
	overlay.show_prompt("WASD / STICK", Vector2(640, 400))
	assert_true(overlay.prompt_visible())
	assert_eq(overlay.prompt_text(), "WASD / STICK")
	var chip := overlay.get_node("Root/WorldPrompts/PromptChip") as Control
	assert_lte(
		chip.position.y + chip.size.y,
		400.0,
		"the prompt sits above its anchor, never on top of a mouth"
	)
	assert_gte(chip.position.y + chip.size.y, 400.0 - 40.0)
	overlay.hide_prompt()
	assert_false(overlay._prompt_active)


func test_prompt_copy_never_exceeds_the_24_char_budget() -> void:
	var overlay := _spawn()
	for index in range(TutorialSteps.STEP_COUNT):
		var prompt := TutorialSteps.prompt_for(index)
		overlay.show_prompt(prompt, Vector2(640, 360))
		assert_lte(prompt.length(), 24)
		var chip := overlay.get_node("Root/WorldPrompts/PromptChip") as Control
		assert_lte(chip.size.x, 320.0, "the prompt must stay compact: %s" % prompt)


func test_reduce_motion_keeps_the_prompt_instant() -> void:
	var previous := Settings.reduce_motion
	Settings.reduce_motion = true
	var overlay := _spawn()
	overlay.show_prompt("ESPERA EL PULSO", Vector2(320, 320))
	var chip := overlay.get_node("Root/WorldPrompts/PromptChip") as Control
	assert_almost_eq(chip.modulate.a, 1.0, 0.001)
	Settings.reduce_motion = previous


func test_skip_plaque_defaults_to_no_and_reports_both_answers() -> void:
	var overlay := _spawn()
	overlay.open_skip()
	assert_true(overlay.is_skip_open())
	assert_not_null(overlay.skip_default_button())
	assert_eq(overlay.skip_default_button().text, "NO, SEGUIR")
	watch_signals(overlay)
	overlay.get_node("Root/SkipPlaque/Plaque/Content/Row/YesButton").emit_signal("pressed")
	assert_signal_emitted(overlay, "skip_confirmed")
	overlay.close_skip()
	assert_false(overlay.is_skip_open())


func test_skip_cancel_closes_the_plaque() -> void:
	var overlay := _spawn()
	overlay.open_skip()
	watch_signals(overlay)
	overlay.get_node("Root/SkipPlaque/Plaque/Content/Row/NoButton").emit_signal("pressed")
	assert_signal_emitted(overlay, "skip_cancelled")
	assert_false(overlay.is_skip_open())


func test_completion_plaque_emits_once() -> void:
	var overlay := _spawn()
	GameState.reset(7001)
	overlay.show_completion()
	assert_true(overlay.is_completion_open())
	assert_string_contains(
		(overlay.get_node("Root/CompletePlaque/Plaque/Content/CompleteTitle") as Label).text,
		"TURNO DE PRUEBA COMPLETADO"
	)
	watch_signals(overlay)
	overlay.accept_completion()
	overlay.accept_completion()
	assert_signal_emit_count(overlay, "completion_continued", 1)


func test_completion_ignores_input_before_it_is_shown() -> void:
	var overlay := _spawn()
	watch_signals(overlay)
	overlay.accept_completion()
	assert_signal_emit_count(overlay, "completion_continued", 0)


func test_world_to_screen_matches_the_fixed_camera() -> void:
	var overlay := _spawn()
	var camera := Camera2D.new()
	camera.position = Vector2(640, 360)
	add_child_autofree(camera)
	overlay.camera = camera
	assert_almost_eq(overlay.to_screen(Vector2(640, 360)).x, 640.0, 0.5)
	assert_almost_eq(overlay.to_screen(Vector2(0, 0)).x, 0.0, 0.5)


func test_soft_skip_hint_only_shows_when_tab_is_legal() -> void:
	var overlay := _spawn()
	assert_false(overlay.soft_skip_hint_visible())
	overlay.set_soft_skip_available(true)
	assert_true(overlay.soft_skip_hint_visible())
	var hint := overlay.get_node("Root/SoftSkipHint") as Label
	assert_eq(hint.text, "TAB · SALTAR PASO")
	assert_lte(
		hint.position.x + hint.size.x, 1280.0, "the footer hint must stay inside the viewport"
	)
	assert_gte(hint.position.y, 600.0, "and out of the top safe band")


func test_hint_circle_and_beacon_are_transient_state_only() -> void:
	var overlay := _spawn()
	overlay.show_hint_circle(Vector2(640, 500), 120.0)
	assert_true(overlay._hint_active)
	overlay.hide_hint_circle()
	assert_false(overlay._hint_active)
	overlay.show_beacon(Vector2(640, 360))
	assert_true(overlay._beacon_active)
	overlay.hide_beacon()
	assert_false(overlay._beacon_active)
	overlay.pulse_at(Vector2(200, 200))
	assert_eq(overlay._pulses.size(), 1)

class_name FallbackScreens
extends RefCounted
## Minimal, styled fallbacks used only when a screen scene is missing at runtime.
## They keep the game playable (never a black screen) while a screen is being authored,
## and they follow the same UITheme language so nothing ever looks like an engine default.


## Title fallback: logo + four intent buttons, wired to the App callbacks.
static func title(app: Node) -> Control:
	var root := Control.new()
	root.name = "TitleFallback"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.theme()
	root.add_child(UITheme.dimmer(0.55))
	var logo := UITheme.label("COSMIC SPIN CYCLE", UITheme.FONT_TITLE, UITheme.INK, true)
	logo.position = Vector2(120, 120)
	root.add_child(logo)
	var column := VBoxContainer.new()
	column.position = Vector2(120, 300)
	column.custom_minimum_size = Vector2(360, 0)
	root.add_child(column)
	var start := UITheme.button("INICIAR TURNO")
	start.pressed.connect(Callable(app, "_on_title_start"))
	column.add_child(start)
	var tutorial := UITheme.button("TUTORIAL")
	tutorial.pressed.connect(Callable(app, "_on_title_tutorial"))
	column.add_child(tutorial)
	var options := UITheme.button("OPCIONES")
	options.pressed.connect(Callable(app, "_on_title_options"))
	column.add_child(options)
	var quit := UITheme.button("SALIR")
	quit.pressed.connect(Callable(app, "_on_title_quit"))
	column.add_child(quit)
	return root


## Pause fallback: resume / restart / menu.
static func pause(app: Node) -> Control:
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
	resume.pressed.connect(Callable(app, "resume_game"))
	column.add_child(resume)
	var restart := UITheme.button("REINICIAR")
	restart.pressed.connect(
		func() -> void:
			app.call("resume_game")
			app.call("restart_shift")
	)
	column.add_child(restart)
	var menu := UITheme.button("MENÚ")
	menu.pressed.connect(
		func() -> void:
			app.call("resume_game")
			app.call("quit_to_menu")
	)
	column.add_child(menu)
	return root


## End-of-shift fallback: verdict, rank and the four headline stats with retry/menu.
static func end(app: Node, result: Dictionary) -> Control:
	var victory := bool(result.get("victory", false))
	var root := Control.new()
	root.name = "EndFallback"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.theme = UITheme.theme()
	root.add_child(UITheme.dimmer(0.72))
	var plaque := UITheme.panel(Rect2(300, 90, 680, 540))
	root.add_child(plaque)
	var column := VBoxContainer.new()
	column.position = Vector2(332, 118)
	column.custom_minimum_size = Vector2(616, 0)
	column.add_theme_constant_override("separation", 10)
	plaque.add_child(column)
	var verdict := "TURNO COMPLETADO" if victory else "DESGARRO UNIVERSAL"
	var verdict_color := UITheme.SUCCESS if victory else UITheme.DANGER
	column.add_child(UITheme.label(verdict, UITheme.FONT_TITLE, verdict_color, true))
	var rank := String(result.get("rank", "C"))
	var rank_row := HBoxContainer.new()
	rank_row.add_theme_constant_override("separation", 24)
	column.add_child(rank_row)
	rank_row.add_child(UITheme.label(rank, UITheme.FONT_DISPLAY, UITheme.REWARD, true))
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	rank_row.add_child(stats)
	stats.add_child(
		UITheme.label(
			(
				"LAVADAS %d · ENTREGADAS %d"
				% [int(result.get("washed", 0)), int(result.get("delivered", 0))]
			),
			UITheme.FONT_BODY,
			UITheme.INK
		)
	)
	(
		stats
		. add_child(
			(
				UITheme
				. label(
					(
						"PRECISIÓN %d%% · COMBO ×%d"
						% [
							int(round(float(result.get("accuracy", 0.0)) * 100.0)),
							int(result.get("max_combo", 1)),
						]
					),
					UITheme.FONT_BODY,
					UITheme.INK_MUTED
				)
			)
		)
	)
	stats.add_child(
		UITheme.label(
			"PUNTOS %06d · SEMILLA %d" % [int(result.get("score", 0)), int(result.get("seed", 0))],
			UITheme.FONT_SMALL,
			UITheme.INK_DIM
		)
	)
	var retry := UITheme.button("REPETIR")
	retry.pressed.connect(Callable(app, "_on_end_retry"))
	column.add_child(retry)
	var menu := UITheme.button("MENÚ")
	menu.pressed.connect(Callable(app, "quit_to_menu"))
	column.add_child(menu)
	return root

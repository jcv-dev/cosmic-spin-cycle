extends Node
## Persistent user settings (audio calibration, volumes, accessibility, locale).

signal settings_changed

const PATH := "user://settings.cfg"

var user_calibration_offset := 0.0
var calibration_samples: Array[float] = []
var master_volume_db := 0.0
var music_volume_db := -6.0
var sfx_volume_db := -4.0
var fullscreen := false
var reduce_motion := false
var show_debug_overlay := false
var locale := "es"
var db_seed := 0
var haptics := true
var ui_scale := 1.0
var difficulty := Config.DIFFICULTY_DEFAULT
var tutorial_completed := false
var tutorial_skipped := false
var first_run_done := false
var best_score := 0
var best_rank := ""

var _loaded := false
## Music ducking: a short dip on big hits so the impact reads (D060).
var _duck_left := 0.0
var _duck_db := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	load_settings()
	apply()


## Master → Music / SFX / UI. Volumes are applied by `apply()` and can be tuned on the bus
## layout; M8 may add Loops as a distinct bus for washer/belt loops.
func _ensure_buses() -> void:
	_ensure_bus("Music", "Master", music_volume_db)
	_ensure_bus("SFX", "Master", sfx_volume_db)
	_ensure_bus("UI", "Master", -6.0)
	# Continuous machine loops live on their own bus so they can sit under the mix (D060).
	_ensure_bus("Loops", "Master", -10.0)
	_ensure_master_limiter()


## A limiter on Master is the safety net the docs asked for: four washers, an explosion and
## the alarm can overlap, and the mix must never clip. Idempotent.
func _ensure_master_limiter() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master < 0:
		return
	for index in range(AudioServer.get_bus_effect_count(master)):
		if AudioServer.get_bus_effect(master, index) is AudioEffectLimiter:
			return
	var limiter := AudioEffectLimiter.new()
	limiter.threshold_db = -3.0
	limiter.ceiling_db = -1.0
	limiter.soft_clip_db = 0.0
	AudioServer.add_bus_effect(master, limiter)


func _ensure_bus(bus_name: String, send: String, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)
	AudioServer.set_bus_volume_db(index, volume_db)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err != OK:
		_loaded = true
		return
	user_calibration_offset = float(cfg.get_value("audio", "calibration_offset_s", 0.0))
	master_volume_db = float(cfg.get_value("audio", "master_db", 0.0))
	music_volume_db = float(cfg.get_value("audio", "music_db", -6.0))
	sfx_volume_db = float(cfg.get_value("audio", "sfx_db", -4.0))
	fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	reduce_motion = bool(cfg.get_value("video", "reduce_motion", false))
	show_debug_overlay = bool(cfg.get_value("debug", "show_overlay", false))
	locale = String(cfg.get_value("game", "locale", "es"))
	db_seed = int(cfg.get_value("debug", "seed", 0))
	haptics = bool(cfg.get_value("input", "haptics", true))
	ui_scale = float(cfg.get_value("video", "ui_scale", Config.HUD_SCALE_DEFAULT))
	difficulty = Config.difficulty_from_key(
		StringName(cfg.get_value("game", "difficulty", "standard"))
	)
	tutorial_completed = bool(cfg.get_value("game", "tutorial_completed", false))
	tutorial_skipped = bool(cfg.get_value("game", "tutorial_skipped", false))
	first_run_done = bool(cfg.get_value("game", "first_run_done", false))
	best_score = int(cfg.get_value("game", "best_score", 0))
	best_rank = String(cfg.get_value("game", "best_rank", ""))
	_loaded = true
	settings_changed.emit()


func save_settings() -> Error:
	if not _loaded:
		return ERR_UNCONFIGURED
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "calibration_offset_s", user_calibration_offset)
	cfg.set_value("audio", "master_db", master_volume_db)
	cfg.set_value("audio", "music_db", music_volume_db)
	cfg.set_value("audio", "sfx_db", sfx_volume_db)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "reduce_motion", reduce_motion)
	cfg.set_value("debug", "show_overlay", show_debug_overlay)
	cfg.set_value("game", "locale", locale)
	cfg.set_value("debug", "seed", db_seed)
	cfg.set_value("input", "haptics", haptics)
	cfg.set_value("video", "ui_scale", ui_scale)
	cfg.set_value("game", "difficulty", Config.difficulty_key(difficulty))
	cfg.set_value("game", "tutorial_completed", tutorial_completed)
	cfg.set_value("game", "tutorial_skipped", tutorial_skipped)
	cfg.set_value("game", "first_run_done", first_run_done)
	cfg.set_value("game", "best_score", best_score)
	cfg.set_value("game", "best_rank", best_rank)
	return cfg.save(PATH)


## Dips the Music bus for `seconds` (negative `db`). Used by PERFECT throws and hazard
## impacts; restoring is automatic and never fights the user's volume setting.
func duck_music(db: float = -3.0, seconds: float = 0.12) -> void:
	_duck_db = minf(db, 0.0)
	_duck_left = maxf(seconds, 0.0)
	_apply_music_volume()


func _process(delta: float) -> void:
	if _duck_left <= 0.0:
		return
	_duck_left = maxf(_duck_left - delta, 0.0)
	_apply_music_volume()


func _apply_music_volume() -> void:
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus < 0:
		return
	var offset := _duck_db if _duck_left > 0.0 else 0.0
	AudioServer.set_bus_volume_db(music_bus, music_volume_db + offset)


func calibration_offset_ms() -> float:
	return user_calibration_offset * 1000.0


func set_calibration_offset_ms(ms: float) -> void:
	user_calibration_offset = clampf(ms / 1000.0, -0.5, 0.5)
	save_settings()
	settings_changed.emit()


func set_calibration_samples(samples_ms: Array[float]) -> void:
	calibration_samples.clear()
	for sample in samples_ms:
		calibration_samples.append(sample / 1000.0)


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
			(
				DisplayServer.WINDOW_MODE_FULLSCREEN
				if fullscreen
				else DisplayServer.WINDOW_MODE_WINDOWED
			)
		)
	AudioServer.set_bus_volume_db(0, master_volume_db)
	_apply_music_volume()
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, sfx_volume_db)


## True when the player has never finished OR skipped the tutorial and has never started
## a shift: only then does the first-run prompt appear (it must never nag).
func needs_first_run_prompt() -> bool:
	return not first_run_done and not tutorial_completed and not tutorial_skipped


func mark_tutorial_completed() -> void:
	tutorial_completed = true
	tutorial_skipped = false
	first_run_done = true
	save_settings()
	settings_changed.emit()


func mark_tutorial_skipped() -> void:
	tutorial_skipped = true
	first_run_done = true
	save_settings()
	settings_changed.emit()


func mark_first_run_done() -> void:
	first_run_done = true
	save_settings()
	settings_changed.emit()


## Stores the best rank/score shown on the title screen. Never invents a record.
func record_result(points: int, rank_letter: String) -> void:
	var changed := false
	if points > best_score:
		best_score = points
		changed = true
	if rank_letter != "" and (best_rank == "" or rank_letter < best_rank):
		best_rank = rank_letter
		changed = true
	if changed:
		save_settings()
		settings_changed.emit()


func set_haptics(value: bool) -> void:
	haptics = value
	save_settings()
	settings_changed.emit()


func set_ui_scale(value: float) -> void:
	ui_scale = clampf(
		value,
		Config.HUD_SCALE_OPTIONS[0],
		Config.HUD_SCALE_OPTIONS[Config.HUD_SCALE_OPTIONS.size() - 1]
	)
	save_settings()
	settings_changed.emit()


## Selects a shift preset (D047) and persists it; the next shift starts with it.
func set_difficulty(value: int) -> void:
	var clamped := Config.difficulty_index(value)
	if clamped == difficulty:
		return
	difficulty = clamped
	save_settings()
	settings_changed.emit()


## Multiplier applied to the rhythm windows: CALM is wider, CHAOS is tighter.
func window_scale() -> float:
	return Config.DIFFICULTY_WINDOW_SCALE[Config.difficulty_index(difficulty)]


func reset_to_defaults() -> void:
	user_calibration_offset = 0.0
	calibration_samples.clear()
	master_volume_db = 0.0
	music_volume_db = -6.0
	sfx_volume_db = -4.0
	fullscreen = false
	reduce_motion = false
	show_debug_overlay = false
	locale = "es"
	haptics = true
	ui_scale = Config.HUD_SCALE_DEFAULT
	difficulty = Config.DIFFICULTY_DEFAULT
	tutorial_completed = false
	tutorial_skipped = false
	first_run_done = false
	best_score = 0
	best_rank = ""
	save_settings()
	apply()
	settings_changed.emit()

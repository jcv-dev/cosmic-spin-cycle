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

var _loaded := false


func _ready() -> void:
	load_settings()
	apply()


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
	return cfg.save(PATH)


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
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, music_volume_db)
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, sfx_volume_db)


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
	save_settings()
	apply()
	settings_changed.emit()

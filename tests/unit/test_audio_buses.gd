extends GutTest
## Mix architecture (D060): the Loops bus, the Master limiter and the ducking helper.


func test_the_loops_bus_exists() -> void:
	assert_gte(AudioServer.get_bus_index("Loops"), 0, "machine loops have their own bus")


func test_master_has_a_limiter() -> void:
	var master := AudioServer.get_bus_index("Master")
	var limiter_found := false
	for index in range(AudioServer.get_bus_effect_count(master)):
		if AudioServer.get_bus_effect(master, index) is AudioEffectLimiter:
			limiter_found = true
	assert_true(limiter_found, "four washers plus an explosion must never clip")


func test_ducking_dips_and_restores_the_music_bus() -> void:
	var music := AudioServer.get_bus_index("Music")
	assert_gte(music, 0)
	var base := AudioServer.get_bus_volume_db(music)
	Settings.duck_music(-3.0, 0.1)
	assert_almost_eq(AudioServer.get_bus_volume_db(music), base - 3.0, 0.01)
	Settings.call("_process", 0.25)
	assert_almost_eq(AudioServer.get_bus_volume_db(music), base, 0.01, "the dip is temporary")


func test_ducking_never_raises_the_music() -> void:
	var music := AudioServer.get_bus_index("Music")
	var base := AudioServer.get_bus_volume_db(music)
	Settings.duck_music(4.0, 0.1)
	assert_lte(AudioServer.get_bus_volume_db(music), base)
	Settings.call("_process", 0.25)

extends GutTest
## Level assembly smoke: MainLevel must boot with the static room and UI even before the
## optional M2/M3 scenes land, and expose the shift spine.


func _spawn_level() -> Node2D:
	var packed := load("res://scenes/main/MainLevel.tscn") as PackedScene
	var level := packed.instantiate() as Node2D
	add_child_autofree(level)
	return level


func test_level_assembles_core_layers() -> void:
	var level := _spawn_level()
	assert_not_null(level.get_node_or_null("Camera2D"))
	assert_not_null(level.get_node_or_null("RoomBackground"))
	assert_not_null(level.get_node_or_null("Floor"))
	assert_not_null(level.get_node_or_null("Walls"))
	assert_not_null(level.get_node_or_null("Environment"))
	assert_not_null(level.get_node_or_null("Items"))
	assert_not_null(level.get_node_or_null("Entities"))
	assert_not_null(level.get_node_or_null("UI"))
	assert_not_null(level.get_node_or_null("UI/HUD"))
	BeatConductor.stop()


func test_seed_is_recorded_and_phase_starts() -> void:
	var level := _spawn_level()
	assert_true(level.get_seed() > 0)
	assert_eq(level.get_phase_index(), 0)
	assert_true(BeatConductor.is_playing)
	BeatConductor.stop()


func test_clock_reaches_phase_two() -> void:
	var level := _spawn_level()
	level.shift_time = 120.1
	await wait_frames(4)
	assert_eq(level.get_phase_index(), 1)
	BeatConductor.stop()

extends GutTest
## SpawnDirector phase boundaries, belt activation and the headless simulate() report.

const SEED := 4242

var director: SpawnDirector


func before_each() -> void:
	director = SpawnDirector.new()
	director.name = "SpawnDirector"
	add_child_autofree(director)
	director.stub_factory = func(_event: Dictionary) -> Node: return RigidBody2D.new()


func test_phase_changes_are_emitted_at_the_boundaries() -> void:
	director.start(SEED)
	watch_signals(director)
	director.advance_to(Config.PHASE_START_S[1] + 0.1)
	assert_signal_emitted_with_parameters(director, "phase_changed", [1])
	director.advance_to(Config.PHASE_START_S[2] + 0.1)
	assert_eq(director.current_phase, 2)


func test_force_phase_jumps_without_moving_the_clock() -> void:
	director.start(SEED)
	director.force_phase(3)
	assert_eq(director.current_phase, 3)
	assert_almost_eq(director.time, 0.0, 0.001)


func test_belts_follow_the_active_phase() -> void:
	var north := _add_belt(&"belt_north")
	var south := _add_belt(&"belt_south")
	var west := _add_belt(&"belt_west")

	director.start(SEED)
	assert_true(north.is_active(), "phase 1 runs the north belt")
	assert_false(south.is_active(), "the south belt wakes in phase 2")
	assert_false(west.is_active(), "the west belt wakes in phase 3")

	director.advance_to(Config.PHASE_START_S[1] + 0.1)
	assert_true(south.is_active(), "phase 2 activates the south belt")
	assert_false(west.is_active())

	director.advance_to(Config.PHASE_START_S[2] + 0.1)
	assert_true(west.is_active(), "phase 3 activates the west belt")


func test_simulate_reports_the_run() -> void:
	var report := director.simulate(Config.SHIFT_DURATION_S, SEED)
	assert_eq(int(report.total), director.schedule.size())
	assert_eq(report.per_phase.size(), 4)
	assert_almost_eq(float(report.last_time), float(report.convoy[12].time), 0.001, "convoy tail")
	assert_true(float(report.last_time) < Config.SHIFT_DURATION_S)
	assert_eq(report.spawned, director.spawned_count_by_phase)


func test_simulate_works_without_any_scene() -> void:
	var headless := SpawnDirector.new()
	headless.stub_factory = Callable()
	var report := headless.simulate(Config.SHIFT_DURATION_S, SEED)
	headless.free()
	assert_eq(int(report.total), 83, "accounting mode counts the whole schedule")
	assert_eq(report.spawned, [17, 24, 29, 13])


# --- helpers ----------------------------------------------------------------


func _add_belt(belt_id: StringName) -> ConveyorBelt:
	var belt := ConveyorBelt.new()
	belt.name = String(belt_id)
	belt.belt_id = belt_id
	add_child_autofree(belt)
	return belt


func _sum(values: Array[int]) -> int:
	var total := 0
	for value in values:
		total += value
	return total

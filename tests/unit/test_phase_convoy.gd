extends GutTest
## Phase 4 is a scripted convoy, not a spawn interval (GDD §2.5, §A6 #15).
##
## The convoy is the win condition's clock, so its composition, ordering and times are
## asserted here independently of the spawner.

const EPS := 0.001

var table: PhaseTable


func before_each() -> void:
	table = PhaseTable.load_default()


func _convoy() -> PhaseData:
	if table == null:
		return null
	return table.phase(3)


func test_convoy_phase_shape() -> void:
	var convoy := _convoy()
	assert_not_null(convoy, "phase 4 must exist")
	if convoy == null:
		return
	assert_true(convoy.convoy, "phase 4 is a convoy")
	assert_eq(convoy.convoy_count, Config.FINAL_LOAD_HEAVY_COUNT + Config.FINAL_LOAD_CORE_COUNT)
	assert_eq(convoy.convoy_core_item, &"galaxy_core")
	assert_eq(convoy.convoy_core_slot, convoy.convoy_count - 1, "the core closes the load")


func test_convoy_composition_is_twelve_heavies_plus_core() -> void:
	var convoy := _convoy()
	if convoy == null:
		fail_test("convoy phase missing")
		return
	var heavies := convoy.convoy_heavy_items()
	assert_eq(heavies.size(), Config.FINAL_LOAD_HEAVY_COUNT, "12 heavy objects")
	assert_eq(heavies.count(&"gas_giant"), 4, "4 gas giants")
	assert_eq(heavies.count(&"moon"), 4, "4 moons")
	assert_eq(heavies.count(&"rocky"), 4, "4 rocky planets")
	for item_id in heavies:
		assert_ne(StringName(item_id), convoy.convoy_core_item, "the core is not a heavy")


func test_convoy_slots_are_monotonic_and_inside_phase_four() -> void:
	var convoy := _convoy()
	if convoy == null:
		fail_test("convoy phase missing")
		return
	assert_almost_eq(convoy.convoy_slot_time(0), convoy.start_s, EPS, "first slot at phase start")
	var previous := -1.0
	for slot in range(convoy.convoy_count):
		var t := convoy.convoy_slot_time(slot)
		assert_true(t > previous, "slot %d moves forward" % slot)
		assert_true(t < convoy.end_s, "slot %d spawns before the shift ends" % slot)
		assert_true(t < Config.SHIFT_DURATION_S, "slot %d must respect the 480 s ceiling" % slot)
		previous = t


func test_convoy_delivers_the_final_load_inside_the_final_minute() -> void:
	var convoy := _convoy()
	if convoy == null:
		fail_test("convoy phase missing")
		return
	assert_almost_eq(convoy.start_s, Config.FINAL_LOAD_START_S, EPS, "final minute starts at 420 s")
	var last := convoy.convoy_slot_time(convoy.convoy_count - 1)
	assert_true(last <= convoy.start_s + Config.SECONDS_PER_GAME_HOUR, "the load fits its minute")


func test_validator_rejects_bad_convoy_composition() -> void:
	var broken := _convoy().duplicate(true) as PhaseData
	broken.convoy_composition = {&"gas_giant": 11}
	var single := PhaseTable.new()
	single.phases = [broken]
	var problems := single.validate()
	assert_true(problems.size() > 0, "a 11+1 convoy must not validate")


func test_validator_rejects_a_slot_past_the_shift() -> void:
	var broken := _convoy().duplicate(true) as PhaseData
	broken.convoy_interval_s = 6.0
	var single := PhaseTable.new()
	single.phases = [broken]
	var problems := single.validate()
	var mentions_slot := false
	for problem in problems:
		if problem.contains("last slot"):
			mentions_slot = true
	assert_true(mentions_slot, "problems: %s" % str(problems))


func test_validator_rejects_gaps_between_phases() -> void:
	var broken := PhaseTable.new()
	var first := PhaseData.new()
	first.index = 0
	first.end_s = 100.0
	first.bpm = 105
	first.spawn_interval_s = 3.5
	first.active_belts = [&"belt_north"]
	first.allowed_colors = [&"red"]
	first.allowed_patterns = [&"solid"]
	first.item_weights = {&"rocky": 1.0}
	var second := first.duplicate(true) as PhaseData
	second.index = 1
	second.start_s = 110.0
	second.end_s = 200.0
	broken.phases = [first, second]
	var problems := broken.validate()
	var mentions_gap := false
	for problem in problems:
		if problem.contains("expected 100.000"):
			mentions_gap = true
	assert_true(mentions_gap, "problems: %s" % str(problems))


func test_convoy_phase_has_no_weighted_spawns() -> void:
	var convoy := _convoy()
	if convoy == null:
		fail_test("convoy phase missing")
		return
	assert_eq(convoy.total_weight(), 0.0, "convoy phases do not draw from item weights")
	assert_eq(convoy.weight_for(&"rocky"), 0.0)

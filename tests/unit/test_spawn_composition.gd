extends GutTest
## Per-phase spawn composition (GDD §2.5, §A6 #10/#15).
##
## Phase 1 is the tutorial window (red/blue, solid, no gas giants), phase 2 adds ringed
## items, phase 3 adds yellow and spotted, and phase 4 is the fixed 12 + 1 convoy.

const SEED := 99

var table: PhaseTable
var events: Array[Dictionary]


func before_each() -> void:
	table = PhaseTable.load_default()
	events = SpawnSchedule.build(table, SEED)


func _events_in(phase_index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in events:
		if int(event.phase) == phase_index:
			out.append(event)
	return out


func _item_ids(phase_index: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for event in _events_in(phase_index):
		out.append(StringName(event.item_id))
	return out


# --- phase 1 ----------------------------------------------------------------


func test_phase_one_only_spawns_red_blue_solid() -> void:
	var phase_one := _events_in(0)
	assert_gt(phase_one.size(), 0)
	for event in phase_one:
		assert_true(event.color == &"red" or event.color == &"blue", "colour %s" % event.color)
		assert_eq(event.pattern, &"solid", "phase 1 is solid-only")


func test_phase_one_has_no_heavy_items() -> void:
	assert_eq(table.phase(0).weight_for(&"gas_giant"), 0.0)
	assert_false(_item_ids(0).has(&"gas_giant"), "no gas giant before phase 2")


func test_phase_two_adds_ringed_items() -> void:
	var patterns := {}
	for event in _events_in(1):
		patterns[event.pattern] = true
	assert_true(patterns.has(&"solid"))
	assert_true(patterns.has(&"ringed"), "phase 2 introduces the ringed pattern")


func test_phase_three_introduces_yellow_and_spotted() -> void:
	var colors := {}
	var patterns := {}
	for event in _events_in(2):
		colors[event.color] = true
		patterns[event.pattern] = true
	assert_true(colors.has(&"yellow"), "phase 3 introduces yellow")
	assert_true(patterns.has(&"spotted"), "phase 3 introduces the spotted pattern")


func test_every_variant_is_legal_for_its_phase() -> void:
	for event in events:
		var phase := table.phase(int(event.phase))
		if event.item_id == SpawnSchedule.CORE_ITEM_ID:
			assert_eq(event.color, &"", "the core has no colour variant")
			assert_eq(event.pattern, &"", "the core has no pattern variant")
			continue
		assert_true(phase.allowed_colors.has(event.color), "colour %s" % event.color)
		assert_true(phase.allowed_patterns.has(event.pattern), "pattern %s" % event.pattern)


# --- phase 4 convoy ---------------------------------------------------------


func test_convoy_is_exactly_thirteen_events() -> void:
	var convoy := _events_in(3)
	assert_eq(convoy.size(), Config.FINAL_LOAD_HEAVY_COUNT + Config.FINAL_LOAD_CORE_COUNT)


func test_convoy_composition_is_four_four_four_plus_core() -> void:
	var ids := _item_ids(3)
	assert_eq(ids.count(&"gas_giant"), 4)
	assert_eq(ids.count(&"moon"), 4)
	assert_eq(ids.count(&"rocky"), 4)
	assert_eq(ids.count(&"galaxy_core"), 1)


func test_convoy_core_closes_the_load() -> void:
	var convoy := _events_in(3)
	assert_eq(convoy[convoy.size() - 1].item_id, &"galaxy_core", "the core is the last slot")
	for index in range(convoy.size() - 1):
		assert_ne(convoy[index].item_id, &"galaxy_core", "only one core")


func test_convoy_times_match_the_authored_slots() -> void:
	var phase := table.phase(3)
	var convoy := _events_in(3)
	assert_eq(convoy.size(), phase.convoy_count)
	for slot in range(convoy.size()):
		assert_almost_eq(
			float(convoy[slot].time), phase.convoy_slot_time(slot), 0.001, "slot %d" % slot
		)
	assert_true(float(convoy[convoy.size() - 1].time) < Config.SHIFT_DURATION_S)


# --- weighted draw ----------------------------------------------------------


func test_weighted_draw_returns_the_only_allowed_item() -> void:
	var phase := table.phase(0).duplicate(true) as PhaseData
	phase.item_weights = {&"sock": 1.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for _draw in range(20):
		assert_eq(SpawnSchedule.pick_item(phase, rng), &"sock")


func test_weighted_draw_follows_the_weights() -> void:
	var phase := table.phase(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var counts := {}
	for _draw in range(600):
		var item_id := SpawnSchedule.pick_item(phase, rng)
		counts[item_id] = int(counts.get(item_id, 0)) + 1
	assert_gt(
		int(counts.get(&"rocky", 0)), int(counts.get(&"sock", 0)), "rocky is weighted above sock"
	)
	assert_gt(
		int(counts.get(&"sock", 0)), int(counts.get(&"moon", 0)), "sock is weighted above moon"
	)


func test_no_weight_yields_no_item() -> void:
	var phase := table.phase(3)
	var rng := RandomNumberGenerator.new()
	assert_eq(SpawnSchedule.pick_item(phase, rng), &"", "convoy phases have no weighted draw")
	assert_eq(SpawnSchedule.pick_item(null, rng), &"")


func test_sorted_item_ids_are_alphabetical() -> void:
	var ids := SpawnSchedule.sorted_item_ids(table.phase(0))
	var sorted := ids.duplicate()
	sorted.sort()
	assert_eq(ids, sorted)

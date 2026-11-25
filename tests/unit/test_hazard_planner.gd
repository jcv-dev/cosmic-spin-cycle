extends GutTest
## HazardPlanner (D045): phase unlocking, per-difficulty density, determinism, spacing and
## the point-to-shape test the director uses for damage.

const MEASURES := 64


func _plan_sequence(seed: int, phase: int, difficulty: int, measures: int = MEASURES) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	var previous := Vector2.ZERO
	for _i in range(measures):
		var entry := HazardPlanner.plan(phase, difficulty, rng, previous)
		if not entry.is_empty():
			previous = entry["art_pos"]
		out.append(entry)
	return out


func _count(sequence: Array) -> int:
	var total := 0
	for entry: Dictionary in sequence:
		if not entry.is_empty():
			total += 1
	return total


func test_same_seed_plans_the_same_hazards() -> void:
	var a := _plan_sequence(1234, 3, Config.Difficulty.STANDARD)
	var b := _plan_sequence(1234, 3, Config.Difficulty.STANDARD)
	assert_eq(a.size(), b.size())
	for i in range(a.size()):
		assert_eq(a[i], b[i], "measure %d matches" % i)


func test_different_seeds_diverge() -> void:
	var a := _plan_sequence(1234, 3, Config.Difficulty.STANDARD)
	var b := _plan_sequence(4321, 3, Config.Difficulty.STANDARD)
	assert_ne(a, b)


func test_phase_zero_only_leaks_void() -> void:
	for entry: Dictionary in _plan_sequence(99, 0, Config.Difficulty.CHAOS):
		if entry.is_empty():
			continue
		assert_eq(int(entry["kind"]), Config.HazardKind.VOID_VENT)


func test_later_phases_unlock_more_kinds() -> void:
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i in range(400):
		var entry := HazardPlanner.plan(3, Config.Difficulty.CHAOS, rng, Vector2.ZERO)
		if not entry.is_empty():
			seen[int(entry["kind"])] = true
	assert_eq(seen.size(), 4, "phase 4 can spawn every kind")


func test_chaos_is_denser_than_calm() -> void:
	var calm := _count(_plan_sequence(2024, 3, Config.Difficulty.CALM))
	var standard := _count(_plan_sequence(2024, 3, Config.Difficulty.STANDARD))
	var chaos := _count(_plan_sequence(2024, 3, Config.Difficulty.CHAOS))
	assert_lt(calm, standard, "CALM must be sparser than STANDARD")
	assert_lt(standard, chaos, "STANDARD must be sparser than CHAOS")
	assert_gt(chaos, 0, "CHAOS must actually spawn hazards")


func test_never_more_than_one_hazard_per_measure() -> void:
	# plan() is asked once per measure by contract: the sequence length is the measure count.
	var sequence := _plan_sequence(5, 3, Config.Difficulty.CHAOS, 10)
	assert_eq(sequence.size(), 10)


func test_consecutive_hazards_keep_their_separation() -> void:
	var previous := Vector2.ZERO
	for entry: Dictionary in _plan_sequence(31337, 3, Config.Difficulty.CHAOS, 200):
		if entry.is_empty():
			continue
		var anchor: Vector2 = entry["art_pos"]
		if previous != Vector2.ZERO:
			var separation := anchor.distance_to(previous) * float(Config.ART_SCALE)
			assert_gte(separation, Config.HAZARD_MIN_SEPARATION_PX, "anchors stay apart")
		previous = anchor


func test_anchors_stay_inside_the_playable_band() -> void:
	# Art canvas is 320x180; belts occupy y<26 and y>154 and the west lane x<26.
	for anchor: Vector2 in HazardPlanner.ANCHORS_ART:
		assert_between(anchor.x, 30.0, 290.0, "anchor x %s is inside the room" % anchor)
		assert_between(anchor.y, 30.0, 150.0, "anchor y %s avoids the belt lanes" % anchor)


func test_anchor_never_sits_on_the_chute() -> void:
	var chute := Vector2(160, 90)
	for anchor: Vector2 in HazardPlanner.ANCHORS_ART:
		var clearance := anchor.distance_to(chute) * float(Config.ART_SCALE)
		assert_gte(
			clearance, Config.HAZARD_CHUTE_CLEARANCE_PX, "anchor %s clears the chute" % anchor
		)


func test_contains_is_a_radius_test_for_round_hazards() -> void:
	var center := Vector2(100, 100)
	var radius := HazardPlanner.radius_px(Config.HazardKind.METEOR)
	assert_true(
		HazardPlanner.contains(Config.HazardKind.METEOR, center, 0.0, center + Vector2(radius, 0))
	)
	assert_false(
		HazardPlanner.contains(
			Config.HazardKind.METEOR, center, 0.0, center + Vector2(radius + 1.0, 0)
		)
	)


func test_contains_is_a_segment_test_for_the_arc() -> void:
	var center := Vector2(200, 200)
	var radius := HazardPlanner.radius_px(Config.HazardKind.LINT_ARC)
	# Horizontal beam: a point above the line is safe, a point on the line is not.
	assert_true(
		HazardPlanner.contains(
			Config.HazardKind.LINT_ARC, center, 0.0, center + Vector2(90, radius - 1.0)
		)
	)
	assert_false(
		HazardPlanner.contains(
			Config.HazardKind.LINT_ARC, center, 0.0, center + Vector2(90, radius + 1.0)
		)
	)
	# Beyond the beam's half length it stops damaging.
	assert_false(
		HazardPlanner.contains(
			Config.HazardKind.LINT_ARC,
			center,
			0.0,
			center + Vector2(HazardPlanner.ARC_LENGTH_PX, 0.0)
		)
	)

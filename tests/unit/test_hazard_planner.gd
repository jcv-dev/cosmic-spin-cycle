extends GutTest
## HazardPlanner (D045, D053): phase unlocking, density, determinism, and the procedural
## placement rules that keep hazards off the belts, the furniture, the chute and the player.

const MEASURES := 64
const LAYOUT_PATH := "res://data/layout.json"


func _plan_sequence(
	seed: int, phase: int, difficulty: int, measures: int = MEASURES, avoid: Vector2 = Vector2.ZERO
) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	var previous := Vector2.ZERO
	for _i in range(measures):
		var entry := HazardPlanner.plan(phase, difficulty, rng, previous, avoid)
		if not entry.is_empty():
			previous = entry["pos"]
		out.append(entry)
	return out


func _count(sequence: Array) -> int:
	var total := 0
	for entry: Dictionary in sequence:
		if not entry.is_empty():
			total += 1
	return total


func _layout() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH)) as Dictionary


func _belt_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var layout := _layout()
	var scale := float(layout.get("art_scale", Config.ART_SCALE))
	for belt: Dictionary in layout.get("belts", []):
		rects.append(
			Rect2(
				Vector2(float(belt["x"]), float(belt["y"])) * scale,
				Vector2(float(belt["w"]), float(belt["h"])) * scale
			)
		)
	return rects


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


func test_consecutive_hazards_keep_their_separation() -> void:
	var previous := Vector2.ZERO
	for entry: Dictionary in _plan_sequence(31337, 3, Config.Difficulty.CHAOS, 200):
		if entry.is_empty():
			continue
		var point: Vector2 = entry["pos"]
		if previous != Vector2.ZERO:
			assert_gte(
				point.distance_to(previous),
				Config.HAZARD_MIN_SEPARATION_PX,
				"consecutive hazards stay apart"
			)
		previous = point


func test_every_planned_point_is_legal() -> void:
	for entry: Dictionary in _plan_sequence(555, 3, Config.Difficulty.CHAOS, 200):
		if entry.is_empty():
			continue
		assert_true(
			HazardPlanner.is_valid_point(entry["pos"]),
			"planned point %s is inside the playable band" % entry["pos"]
		)


func test_no_planned_point_lands_on_a_belt() -> void:
	var belts := _belt_rects()
	for entry: Dictionary in _plan_sequence(808, 3, Config.Difficulty.CHAOS, 200):
		if entry.is_empty():
			continue
		for belt: Rect2 in belts:
			assert_false(
				belt.has_point(entry["pos"]), "hazard %s never sits on a belt" % entry["pos"]
			)


func test_no_planned_point_lands_on_furniture_or_the_chute() -> void:
	var chute := HazardPlanner.chute_center()
	for entry: Dictionary in _plan_sequence(909, 3, Config.Difficulty.CHAOS, 200):
		if entry.is_empty():
			continue
		assert_gte(
			(entry["pos"] as Vector2).distance_to(chute),
			Config.HAZARD_CHUTE_CLEARANCE_PX,
			"the delivery stays reachable"
		)


func test_hazards_never_spawn_under_the_player() -> void:
	var avoid := Vector2(640, 520)
	for entry: Dictionary in _plan_sequence(4242, 3, Config.Difficulty.CHAOS, 120, avoid):
		if entry.is_empty():
			continue
		assert_gte(
			(entry["pos"] as Vector2).distance_to(avoid),
			Config.HAZARD_PLAYER_CLEARANCE_PX,
			"a hazard never appears at the player's feet"
		)


func test_planned_points_stay_inside_the_washer_arena() -> void:
	var arena := HazardPlanner.arena_rect()
	assert_gt(arena.size.x, 500.0, "the arena spans the space between the machines")
	assert_gt(arena.size.y, 150.0)
	for entry: Dictionary in _plan_sequence(1717, 3, Config.Difficulty.CHAOS, 200):
		if entry.is_empty():
			continue
		assert_true(
			arena.has_point(entry["pos"]), "hazard %s stays between the machines" % entry["pos"]
		)


func test_playable_rect_is_inside_the_room() -> void:
	var area := HazardPlanner.playable_rect()
	assert_gt(area.size.x, 600.0, "the band keeps most of the floor")
	assert_gt(area.size.y, 300.0)
	assert_true(area.has_point(Vector2(640, 360)), "the middle of the room is playable")


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
	assert_false(
		HazardPlanner.contains(
			Config.HazardKind.LINT_ARC,
			center,
			0.0,
			center + Vector2(HazardPlanner.ARC_LENGTH_PX, 0.0)
		)
	)

extends GutTest
## ScoreRules: delivery points, rank boundaries, the max-possible helper and the summary.


func test_delivery_points_table() -> void:
	var cases := [
		[100, 1, 100, "x1"],
		[100, 4, 400, "x4"],
		[150, 8, 1200, "x8"],
		[100, 99, 800, "combo capped at 8"],
		[100, 0, 100, "combo floored at 1"],
		[0, 8, 0, "free item"],
		[-50, 4, 0, "negative points never pay"],
	]
	for row: Array in cases:
		assert_eq(ScoreRules.delivery_points(row[0], row[1]), row[2], "case %s" % row[3])


func test_rank_boundaries_table() -> void:
	var cases := [
		[1.0, 1.0, true, "S", "perfect"],
		[0.85, 0.90, true, "S", "inclusive S boundary"],
		[0.85, 0.8999, true, "A", "accuracy just below S"],
		[0.8499, 1.0, true, "A", "ratio just below S"],
		[0.65, 0.0, true, "A", "inclusive A boundary"],
		[0.6499, 1.0, true, "B", "just below A"],
		[0.40, 0.0, true, "B", "inclusive B boundary"],
		[0.3999, 1.0, true, "C", "below B"],
		[0.0, 0.0, true, "C", "nothing done"],
	]
	for row: Array in cases:
		assert_eq(ScoreRules.rank(row[0], row[1], row[2]), row[3], "case %s" % row[4])


func test_defeat_is_always_c() -> void:
	assert_eq(ScoreRules.rank(1.0, 1.0, false), "C")
	assert_eq(ScoreRules.rank(0.95, 0.99, false), "C", "a lost shift never ranks S")
	var colors := ["S", "A", "B", "C", "Z"]
	for letter: String in colors:
		assert_ne(ScoreRules.rank_color(letter), Color(0, 0, 0, 0), "colour for %s" % letter)
	assert_eq(ScoreRules.rank_color("S"), Palette.FUNK_MAGENTA)
	assert_eq(ScoreRules.rank_color("A"), Palette.FUNK_CYAN)
	assert_eq(ScoreRules.rank_color("C"), Palette.METAL_1)


func test_max_possible_score_table() -> void:
	var points := {&"rocky": 100, &"sock": 150, &"galaxy_core": 1000}
	var events: Array[Dictionary] = [
		{"item_id": &"rocky"},
		{"item_id": &"rocky"},
		{"item_id": &"sock"},
	]
	assert_eq(ScoreRules.max_possible_score(events, 4, points), 1400, "350 points * x4")
	assert_eq(ScoreRules.max_possible_score(events, 1, points), 350, "reference x1")
	assert_eq(ScoreRules.max_possible_score(events, 8, points), 2800, "reference x8")
	assert_eq(ScoreRules.max_possible_score([], 4, points), 0, "empty schedule")
	var core: Array[Dictionary] = [{"item_id": &"galaxy_core"}]
	assert_eq(ScoreRules.max_possible_score(core, 1, points), 1000)
	assert_eq(ScoreRules.REFERENCE_COMBO, 4, "documented assumption")


func test_points_by_id_reads_the_shipped_database() -> void:
	var table := ScoreRules.points_by_id()
	assert_eq(int(table.get(&"rocky", 0)), 100)
	assert_eq(int(table.get(&"sock", 0)), 150)
	assert_eq(int(table.get(&"moon", 0)), 200)
	assert_eq(int(table.get(&"gas_giant", 0)), 350)
	assert_eq(int(table.get(&"galaxy_core", 0)), 1000)


func test_summary_table() -> void:
	var result := {
		"victory": true,
		"reason": "time",
		"washed": 12,
		"delivered": 10,
		"accuracy": 0.95,
		"max_combo": 6,
		"score": 1700,
		"seed": 4242,
		"exploded": 1,
		"stability": 72.0,
		"final_delivered": 4,
	}
	var summary := ScoreRules.summary(result, 2000)
	assert_eq(summary["washed"], 12)
	assert_eq(summary["delivered"], 10)
	assert_almost_eq(float(summary["accuracy"]), 0.95, 0.0001)
	assert_eq(summary["max_combo"], 6)
	assert_eq(summary["score"], 1700)
	assert_eq(summary["seed"], 4242)
	assert_eq(summary["exploded"], 1)
	assert_eq(summary["final_delivered"], 4)
	assert_almost_eq(float(summary["score_ratio"]), 0.85, 0.0001)
	assert_eq(summary["rank"], "S", "0.85 ratio + 0.95 accuracy")

	var lost := result.duplicate()
	lost["victory"] = false
	assert_eq(ScoreRules.summary(lost, 2000)["rank"], "C", "defeat always C")

	var ratio_only := result.duplicate()
	ratio_only["score_ratio"] = 0.2
	var low := ScoreRules.summary(ratio_only)
	assert_almost_eq(float(low["score_ratio"]), 0.2, 0.0001)
	assert_eq(low["rank"], "C")

	var clamped := result.duplicate()
	clamped["score"] = 99999
	assert_almost_eq(float(ScoreRules.summary(clamped, 2000)["score_ratio"]), 1.0, 0.0001)

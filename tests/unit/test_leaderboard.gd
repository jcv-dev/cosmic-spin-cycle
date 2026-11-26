extends GutTest
## Leaderboard (D059): ordering, the ten-row cut, duplicate runs, and the JSON round-trip.

const PATH := "user://test_records.json"


func _entry(points: int, accuracy: float = 0.9, date: int = 100, seed_value: int = 1) -> Dictionary:
	return {
		"points": points,
		"rank": "A",
		"accuracy": accuracy,
		"max_combo": 3,
		"delivered": 10,
		"seed": seed_value,
		"date": date,
		"difficulty": Config.Difficulty.STANDARD,
	}


func before_each() -> void:
	DirAccess.remove_absolute(PATH)


func after_each() -> void:
	DirAccess.remove_absolute(PATH)


func test_points_order_the_table() -> void:
	var table := Leaderboard.insert([], _entry(100))
	table = Leaderboard.insert(table, _entry(300, 0.5, 200, 2))
	table = Leaderboard.insert(table, _entry(200, 0.7, 300, 3))
	assert_eq(int(table[0]["points"]), 300)
	assert_eq(int(table[1]["points"]), 200)
	assert_eq(int(table[2]["points"]), 100)


func test_accuracy_breaks_a_points_tie() -> void:
	var table := Leaderboard.insert([], _entry(500, 0.60))
	table = Leaderboard.insert(table, _entry(500, 0.95, 100, 2))
	assert_almost_eq(float(table[0]["accuracy"]), 0.95, 0.0001, "the cleaner run wins the tie")


func test_older_run_wins_a_full_tie() -> void:
	var table := Leaderboard.insert([], _entry(500, 0.8, 900, 7))
	table = Leaderboard.insert(table, _entry(500, 0.8, 100, 8))
	assert_eq(int(table[0]["date"]), 100, "the older run stays on top")


func test_the_table_is_capped_at_ten() -> void:
	var table: Array = []
	for i in range(14):
		table = Leaderboard.insert(table, _entry(100 + i, 0.8, 100 + i, i))
	assert_eq(table.size(), Config.LEADERBOARD_SIZE)
	assert_eq(int(table[0]["points"]), 113, "the best run is still first")


func test_the_same_run_is_never_stored_twice() -> void:
	var table := Leaderboard.insert([], _entry(420, 0.8, 100, 55))
	var again := Leaderboard.insert(table, _entry(420, 0.9, 999, 55))
	assert_eq(again.size(), 1, "seed + points identify a run")


func test_position_is_one_based_and_minus_one_when_absent() -> void:
	var table := Leaderboard.insert([], _entry(900))
	table = Leaderboard.insert(table, _entry(100, 0.8, 100, 2))
	assert_eq(Leaderboard.position_of(table, _entry(900)), 1)
	assert_eq(Leaderboard.position_of(table, _entry(100, 0.8, 100, 2)), 2)
	assert_eq(Leaderboard.position_of(table, _entry(42, 0.8, 100, 99)), -1)


func test_round_trip_through_disk() -> void:
	var result := {
		"score": 1234,
		"rank": "B",
		"accuracy": 0.75,
		"max_combo": 4,
		"delivered": 9,
		"seed": 77,
	}
	var submitted := Leaderboard.submit(result, Config.Difficulty.CHAOS, PATH, 1700000000)
	assert_eq(int(submitted["position"]), 1)
	var loaded := Leaderboard.load_table(Config.Difficulty.CHAOS, PATH)
	assert_eq(loaded.size(), 1)
	assert_eq(int(loaded[0]["points"]), 1234)
	assert_eq(String(loaded[0]["rank"]), "B")
	assert_eq(int(loaded[0]["date"]), 1700000000)
	assert_eq(Leaderboard.load_table(Config.Difficulty.CALM, PATH).size(), 0, "tables are separate")


func test_a_corrupt_or_old_file_reads_as_empty() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	assert_eq(Leaderboard.load_table(Config.Difficulty.STANDARD, PATH).size(), 0)

	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 99, "tables": {}}))
	file.close()
	assert_eq(Leaderboard.load_table(Config.Difficulty.STANDARD, PATH).size(), 0)


func test_bad_rows_are_dropped_not_fatal() -> void:
	var tables := {
		"version": Leaderboard.VERSION,
		"tables": {"standard": [42, {"points": "x"}, {"points": 10, "accuracy": 2.0}]},
	}
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(tables))
	file.close()
	var loaded := Leaderboard.load_table(Config.Difficulty.STANDARD, PATH)
	assert_eq(loaded.size(), 1, "only the usable row survives")
	assert_almost_eq(float(loaded[0]["accuracy"]), 1.0, 0.0001, "accuracy is clamped")


func test_entry_from_result_clamps_and_defaults() -> void:
	var entry := Leaderboard.entry_from_result({"score": -5}, Config.Difficulty.CALM, 10)
	assert_eq(int(entry["points"]), 0)
	assert_eq(String(entry["rank"]), "C")
	assert_eq(int(entry["max_combo"]), 1)
	assert_eq(int(entry["date"]), 10)
	assert_eq(int(entry["difficulty"]), Config.Difficulty.CALM)

class_name Leaderboard
extends RefCounted
## Top-10 records per difficulty (docs/DECISIONS.md D059, addendum §12).
##
## Pure sorting/selection plus a small JSON store. Records live in their own file, not in
## `settings.cfg`, because the options screen can reset the settings and must never wipe a
## player's history.
##
## Entry: `{points:int, rank:String, accuracy:float, max_combo:int, delivered:int,
##          seed:int, date:int (unix seconds), difficulty:int}`.
## Order: points desc, accuracy desc, oldest date first, then seed — total, so the table is
## stable across saves and machines.

const VERSION := 1


## Builds an entry from a shift result. `now` is injectable so tests never depend on the
## clock. Missing fields default to zero, never to a crash.
static func entry_from_result(result: Dictionary, difficulty: int, now: int = -1) -> Dictionary:
	var stamp := now
	if stamp < 0:
		stamp = int(Time.get_unix_time_from_system())
	return {
		"points": maxi(int(result.get("score", 0)), 0),
		"rank": String(result.get("rank", "C")),
		"accuracy": clampf(float(result.get("accuracy", 0.0)), 0.0, 1.0),
		"max_combo": maxi(int(result.get("max_combo", 1)), 1),
		"delivered": maxi(int(result.get("delivered", 0)), 0),
		"seed": int(result.get("seed", 0)),
		"date": stamp,
		"difficulty": Config.difficulty_index(difficulty),
	}


## Inserts `entry` keeping the table sorted and cut to `size`. Identical runs (same seed and
## points) are not duplicated: reopening the end screen must not add the same run twice.
static func insert(entries: Array, entry: Dictionary, size: int = Config.LEADERBOARD_SIZE) -> Array:
	var out: Array = []
	var duplicate := false
	for candidate: Variant in entries:
		if candidate is Dictionary:
			if _same_run(candidate, entry):
				duplicate = true
			out.append((candidate as Dictionary).duplicate(true))
	if not duplicate:
		out.append(entry.duplicate(true))
	out.sort_custom(_before)
	while out.size() > maxi(size, 1):
		out.pop_back()
	return out


## 1-based position of `entry` inside `entries`, or -1 when it is not in the table.
static func position_of(entries: Array, entry: Dictionary) -> int:
	for index in range(entries.size()):
		var candidate: Variant = entries[index]
		if candidate is Dictionary and _same_run(candidate, entry):
			return index + 1
	return -1


## Reads the stored table for `difficulty` (empty when the file is missing or unreadable).
static func load_table(difficulty: int, path: String = Config.RECORDS_PATH) -> Array:
	var tables := _read(path)
	return _sanitize(tables.get(String(Config.difficulty_key(difficulty)), []))


## Stores `entries` for `difficulty` and returns the file error (OK on success).
static func save_table(
	difficulty: int, entries: Array, path: String = Config.RECORDS_PATH
) -> Error:
	var tables := _read(path)
	tables[String(Config.difficulty_key(difficulty))] = _sanitize(entries)
	return _write(path, tables)


## Convenience for the end screen: inserts the run and reports where it landed.
## Returns `{ "position": int, "table": Array }`; position is -1 when it misses the top 10.
static func submit(
	result: Dictionary, difficulty: int, path: String = Config.RECORDS_PATH, now: int = -1
) -> Dictionary:
	var entry := entry_from_result(result, difficulty, now)
	var tables := _read(path)
	var key := String(Config.difficulty_key(difficulty))
	var table := insert(_sanitize(tables.get(key, [])), entry)
	tables[key] = table
	_write(path, tables)
	return {"position": position_of(table, entry), "table": table}


## Wipes every table. Used by tests and by a future "clear records" option.
static func clear(path: String = Config.RECORDS_PATH) -> Error:
	return _write(path, {})


static func _same_run(a: Dictionary, b: Dictionary) -> bool:
	return (
		int(a.get("seed", 0)) == int(b.get("seed", 0))
		and int(a.get("points", 0)) == int(b.get("points", 0))
	)


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var points_a := int(a.get("points", 0))
	var points_b := int(b.get("points", 0))
	if points_a != points_b:
		return points_a > points_b
	var accuracy_a := float(a.get("accuracy", 0.0))
	var accuracy_b := float(b.get("accuracy", 0.0))
	if not is_equal_approx(accuracy_a, accuracy_b):
		return accuracy_a > accuracy_b
	var date_a := int(a.get("date", 0))
	var date_b := int(b.get("date", 0))
	if date_a != date_b:
		return date_a < date_b
	return int(a.get("seed", 0)) < int(b.get("seed", 0))


## Drops anything that is not a well-formed entry, so a hand-edited file cannot crash the UI.
static func _sanitize(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for item: Variant in raw:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var raw_points: Variant = entry.get("points")
		if not (raw_points is int or raw_points is float):
			continue
		(
			out
			. append(
				{
					"points": maxi(int(entry.get("points", 0)), 0),
					"rank": String(entry.get("rank", "C")),
					"accuracy": clampf(float(entry.get("accuracy", 0.0)), 0.0, 1.0),
					"max_combo": maxi(int(entry.get("max_combo", 1)), 1),
					"delivered": maxi(int(entry.get("delivered", 0)), 0),
					"seed": int(entry.get("seed", 0)),
					"date": int(entry.get("date", 0)),
					"difficulty": int(entry.get("difficulty", 0)),
				}
			)
		)
	out.sort_custom(_before)
	return out


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	if not (json.data is Dictionary):
		return {}
	var document: Dictionary = json.data
	if int(document.get("version", 0)) != VERSION:
		return {}
	var tables: Variant = document.get("tables", {})
	if not (tables is Dictionary):
		return {}
	return (tables as Dictionary).duplicate(true)


static func _write(path: String, tables: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": VERSION, "tables": tables}, "\t"))
	file.close()
	return OK

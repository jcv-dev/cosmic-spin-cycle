extends SceneTree
## Headless M3 spawn report (AGENTS §A8 M3, `docs/M3_WORLD.md`).
##
## Usage:
##   godot --headless --path . -s tools/sim_run.gd -- --seed=1234
##
## Builds `data/phases.tres` into a spawn schedule for the seed, then prints the per-phase
## counts, the total, the first/last spawn times and the final-load convoy as JSON. The
## schedule is pure, so this runs in milliseconds and never needs a frame.
##
## Exit code: 0 on a produced report, 1 when the phase table cannot be loaded.

## Seed used when `--seed=` is absent; a fixed default keeps CI runs reproducible.
const DEFAULT_SEED := 1


func _initialize() -> void:
	var started_usec := Time.get_ticks_usec()
	var run_seed := _seed_from_args()
	var table := PhaseTable.load_default()
	if table == null:
		push_error("sim_run: cannot load %s" % PhaseTable.RESOURCE_PATH)
		quit(1)
		return

	var events: Array[Dictionary] = SpawnSchedule.build(table, run_seed)
	var report := _report(table, events, run_seed, started_usec)
	print(_summary_line(report))
	print(_phase_table_line(report))
	print(JSON.stringify(report, "  "))
	quit(0)


# --- report -----------------------------------------------------------------


func _report(
	table: PhaseTable, events: Array[Dictionary], run_seed: int, started_usec: int
) -> Dictionary:
	var summary := SpawnSchedule.summarize(events, table.size())
	var phases: Array[Dictionary] = []
	var counts := summary.per_phase as Array
	for index in range(table.size()):
		var entry := table.phase(index)
		(
			phases
			. append(
				{
					"index": index,
					"name": String(entry.name_key),
					"start_s": entry.start_s,
					"end_s": entry.end_s,
					"bpm": entry.bpm,
					"interval_s": entry.spawn_interval_s,
					"convoy": entry.convoy,
					"belts": _string_list(entry.active_belts),
					"spawned": int(counts[index]) if index < counts.size() else 0,
				}
			)
		)

	var convoy: Array[Dictionary] = []
	for event in summary.convoy as Array:
		convoy.append({"time": event.time, "item_id": String(event.item_id)})

	var by_item := {}
	var raw_items: Dictionary = summary.by_item
	var item_keys := raw_items.keys()
	item_keys.sort()
	for item_id: Variant in item_keys:
		by_item[String(item_id)] = int(raw_items[item_id])

	return {
		"seed": run_seed,
		"shift_duration_s": table.total_duration_s(),
		"phases": phases,
		"per_phase": summary.per_phase,
		"total": summary.total,
		"first_time": summary.first_time,
		"last_time": summary.last_time,
		"by_item": by_item,
		"convoy": convoy,
		"max_alive_items": Config.MAX_ALIVE_ITEMS,
		"elapsed_ms": snappedf(float(Time.get_ticks_usec() - started_usec) / 1000.0, 0.01),
	}


func _summary_line(report: Dictionary) -> String:
	return (
		"sim_run seed=%d total=%d per_phase=%s first=%.2fs last=%.2fs elapsed=%.2fms"
		% [
			int(report.seed),
			int(report.total),
			str(report.per_phase),
			float(report.first_time),
			float(report.last_time),
			float(report.elapsed_ms),
		]
	)


func _phase_table_line(report: Dictionary) -> String:
	var parts: Array[String] = []
	for phase: Dictionary in report.phases as Array:
		var mode := "convoy" if bool(phase.convoy) else "%.2fs" % float(phase.interval_s)
		(
			parts
			. append(
				(
					"P%d %.0f-%.0fs %dBPM %s spawned=%d"
					% [
						int(phase.index) + 1,
						float(phase.start_s),
						float(phase.end_s),
						int(phase.bpm),
						mode,
						int(phase.spawned),
					]
				)
			)
		)
	return "  " + " | ".join(parts)


# --- arguments --------------------------------------------------------------


func _seed_from_args() -> int:
	for raw: Variant in OS.get_cmdline_user_args():
		var arg := str(raw)
		if arg.begins_with("--seed="):
			return int(arg.trim_prefix("--seed="))
	return DEFAULT_SEED


func _string_list(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in values:
		out.append(String(value))
	return out

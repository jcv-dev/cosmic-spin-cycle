class_name SpawnSchedule
extends RefCounted
## Pure spawn schedule for a whole shift (GDD §2.5, §6, §A6 #15).
##
## `build()` turns `data/phases.tres` plus a seed into a sorted list of spawn events, with
## no scene, no autoload and no game clock. The [SpawnDirector] node only replays this list
## against game time, so the 480 s run is testable and reproducible headlessly.
##
## Every event is a dictionary:
## `{ "time": float, "item_id": StringName, "color": StringName, "pattern": StringName,
##    "phase": int }`.
## The galaxy core has no colour or pattern variant: both are the empty `StringName`.
##
## Determinism: `build()` owns a private seeded [RandomNumberGenerator] and iterates item
## weights in sorted id order, so the same seed always yields the same list, independent of
## how a dictionary happens to be serialised.

## Unique final object of the convoy; it is not recoloured or re-patterned (GDD §6).
const CORE_ITEM_ID := &"galaxy_core"

## Safety valve: a broken phase table cannot build an unbounded list.
const MAX_EVENTS := 4096


## Sorted spawn events for the whole shift described by `phase_table`.
##
## Returns an empty list when the table is null or empty. Events are ordered by time and
## none reaches the shift's end (`total_duration_s()`), because a spawn at 480 s would be
## outside the run.
static func build(phase_table: PhaseTable, seed: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if phase_table == null or phase_table.size() == 0:
		return events
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var shift_end := phase_table.total_duration_s()

	for index in range(phase_table.size()):
		if events.size() >= MAX_EVENTS:
			break
		var phase := phase_table.phase(index)
		if phase == null:
			continue
		if phase.convoy:
			_append_convoy(events, phase, rng, shift_end)
		else:
			_append_interval(events, phase, rng, shift_end)

	events.sort_custom(_before)
	return events


## Spawn count per phase index, e.g. `[34, 62, 88, 13]` for the shipped table.
static func counts_by_phase(events: Array[Dictionary], phase_count: int = 4) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(maxi(phase_count, 0))
	for event in events:
		var phase := int(event.get("phase", -1))
		if phase >= 0 and phase < counts.size():
			counts[phase] += 1
	return counts


## One line summary for the sim report and the director's `simulate()`.
##
## `{ "total": int, "per_phase": Array[int], "first_time": float, "last_time": float,
##    "convoy": Array[Dictionary], "by_item": Dictionary }` — `first_time` is -1 for an empty
## schedule.
static func summarize(events: Array[Dictionary], phase_count: int = 4) -> Dictionary:
	var total := events.size()
	var first_time := -1.0
	var last_time := -1.0
	if total > 0:
		first_time = float(events[0].get("time", 0.0))
		last_time = float(events[total - 1].get("time", 0.0))
	var convoy: Array[Dictionary] = []
	var by_item := {}
	for event in events:
		if int(event.get("phase", -1)) == phase_count - 1:
			convoy.append(event.duplicate())
		var item_id := StringName(str(event.get("item_id", "")))
		by_item[item_id] = int(by_item.get(item_id, 0)) + 1
	return {
		"total": total,
		"per_phase": counts_by_phase(events, phase_count),
		"first_time": first_time,
		"last_time": last_time,
		"convoy": convoy,
		"by_item": by_item,
	}


## Weighted item draw for one phase, using `rng` (which the caller owns so the stream stays
## reproducible). Returns `&""` when the phase has no positive weight.
static func pick_item(phase: PhaseData, rng: RandomNumberGenerator) -> StringName:
	if phase == null or rng == null:
		return &""
	var total := phase.total_weight()
	if total <= 0.0:
		return &""
	var roll := rng.randf() * total
	var cumulative := 0.0
	var ids := sorted_item_ids(phase)
	for item_id in ids:
		var weight := phase.weight_for(item_id)
		if weight <= 0.0:
			continue
		cumulative += weight
		if roll < cumulative:
			return item_id
	return ids[ids.size() - 1] if ids.size() > 0 else &""


## Item ids of a phase in a stable alphabetical order.
static func sorted_item_ids(phase: PhaseData) -> Array[StringName]:
	var ids: Array[StringName] = []
	if phase == null:
		return ids
	for key in phase.item_weights.keys():
		ids.append(StringName(key))
	ids.sort()
	return ids


## Legal colour/pattern pair for `item_id` in `phase`, drawn from `rng`.
##
## Variant-less items (the galaxy core) return empty names. A phase that allows no variant
## also returns empty names rather than inventing one.
static func pick_variant(
	phase: PhaseData, item_id: StringName, rng: RandomNumberGenerator
) -> Array[StringName]:
	var out: Array[StringName] = [&"", &""]
	if phase == null or rng == null or item_id == CORE_ITEM_ID:
		return out
	if phase.allowed_colors.is_empty() or phase.allowed_patterns.is_empty():
		return out
	out[0] = phase.allowed_colors[rng.randi_range(0, phase.allowed_colors.size() - 1)]
	out[1] = phase.allowed_patterns[rng.randi_range(0, phase.allowed_patterns.size() - 1)]
	return out


# --- internals --------------------------------------------------------------


static func _before(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("time", 0.0)) < float(b.get("time", 0.0))


static func _append_interval(
	events: Array[Dictionary], phase: PhaseData, rng: RandomNumberGenerator, shift_end: float
) -> void:
	var interval := phase.spawn_interval_s
	if interval <= 0.0:
		return
	var limit := minf(phase.end_s, shift_end)
	var slot := 1
	while true:
		var time := phase.start_s + interval * float(slot)
		if time >= limit or time >= shift_end:
			break
		var item_id := pick_item(phase, rng)
		if item_id == &"":
			break
		events.append(_event(phase, time, item_id, rng))
		if events.size() >= MAX_EVENTS:
			break
		slot += 1


static func _append_convoy(
	events: Array[Dictionary], phase: PhaseData, rng: RandomNumberGenerator, shift_end: float
) -> void:
	var heavies := phase.convoy_heavy_items()
	var heavy_index := 0
	for slot in range(phase.convoy_count):
		var time := phase.convoy_slot_time(slot)
		if time >= shift_end or time >= phase.end_s:
			continue
		var item_id := phase.convoy_core_item
		if slot != phase.convoy_core_slot:
			if heavy_index >= heavies.size():
				continue
			item_id = heavies[heavy_index]
			heavy_index += 1
		events.append(_event(phase, time, item_id, rng))
		if events.size() >= MAX_EVENTS:
			break


static func _event(
	phase: PhaseData, time: float, item_id: StringName, rng: RandomNumberGenerator
) -> Dictionary:
	var variant := pick_variant(phase, item_id, rng)
	return {
		"time": time,
		"item_id": item_id,
		"color": variant[0],
		"pattern": variant[1],
		"phase": phase.index,
	}

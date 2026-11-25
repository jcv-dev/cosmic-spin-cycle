class_name PhaseTable
extends Resource
## Ordered, contiguous list of the shift's four phases (GDD §2.5).
##
## Pure data + lookups: no scene, no autoload and no RNG, so both the spawner and the
## headless tools can consume it. `data/phases.tres` is the shipped instance.

const RESOURCE_PATH := "res://data/phases.tres"

@export var phases: Array[PhaseData] = []


## Loads the shipped phase table. Returns null when the resource is missing.
static func load_default() -> PhaseTable:
	if not ResourceLoader.exists(RESOURCE_PATH):
		return null
	return load(RESOURCE_PATH) as PhaseTable


## Number of phases in the table.
func size() -> int:
	return phases.size()


## Phase at `index`, or null when out of range.
func phase(index: int) -> PhaseData:
	if index < 0 or index >= phases.size():
		return null
	return phases[index]


## Phase containing `t` (shift seconds). Out-of-range times clamp to the first/last phase.
func phase_at(t: float) -> PhaseData:
	if phases.is_empty():
		return null
	for entry in phases:
		if entry != null and entry.contains(t):
			return entry
	return phases[0] if t < phases[0].start_s else phases[phases.size() - 1]


## Index of the phase containing `t`.
func phase_index_at(t: float) -> int:
	var entry := phase_at(t)
	if entry == null:
		return 0
	return entry.index


## Phase that starts at `start_s` exactly (used by the phase-change path).
func phase_starting_at(start_s: float) -> PhaseData:
	for entry in phases:
		if entry != null and is_equal_approx(entry.start_s, start_s):
			return entry
	return null


## End of the last phase, i.e. the shift duration the table describes.
func total_duration_s() -> float:
	if phases.is_empty():
		return 0.0
	return phases[phases.size() - 1].end_s


## Every belt id mentioned by any phase, in first-seen order.
func belt_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in phases:
		if entry == null:
			continue
		for belt_id in entry.active_belts:
			if not out.has(belt_id):
				out.append(belt_id)
	return out


## Belts running at `t`.
func active_belts_at(t: float) -> Array[StringName]:
	var entry := phase_at(t)
	if entry == null:
		return []
	return entry.active_belts.duplicate()


## Human-readable data problems. Empty means the table is well formed.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if phases.is_empty():
		problems.append("phase table is empty")
		return problems

	var expected_start := 0.0
	for i in range(phases.size()):
		var entry := phases[i]
		if entry == null:
			problems.append("phase %d is null" % i)
			continue
		if entry.index != i:
			problems.append("phase %d declares index %d" % [i, entry.index])
		if not is_equal_approx(entry.start_s, expected_start):
			problems.append(
				"phase %d starts at %.3f, expected %.3f" % [i, entry.start_s, expected_start]
			)
		if entry.end_s <= entry.start_s:
			problems.append("phase %d has a non-positive duration" % i)
		if entry.bpm <= 0:
			problems.append("phase %d has bpm %d" % [i, entry.bpm])
		if not entry.convoy and entry.spawn_interval_s <= 0.0:
			problems.append("phase %d has no spawn interval" % i)
		if entry.active_belts.is_empty():
			problems.append("phase %d activates no belt" % i)
		if entry.allowed_colors.is_empty():
			problems.append("phase %d allows no colour" % i)
		if entry.allowed_patterns.is_empty():
			problems.append("phase %d allows no pattern" % i)
		if entry.convoy:
			problems.append_array(_validate_convoy(entry, i))
		elif entry.item_weights.is_empty() or entry.total_weight() <= 0.0:
			problems.append("phase %d has no positive item weight" % i)
		expected_start = entry.end_s

	return problems


func _validate_convoy(entry: PhaseData, index: int) -> Array[String]:
	var problems: Array[String] = []
	if entry.convoy_count <= 0:
		problems.append("convoy phase %d has no convoy_count" % index)
	if entry.convoy_interval_s <= 0.0:
		problems.append("convoy phase %d has no convoy_interval_s" % index)
	if entry.convoy_core_item == &"":
		problems.append("convoy phase %d has no core item" % index)
	var heavies := entry.convoy_heavy_items()
	if heavies.size() + 1 != entry.convoy_count:
		problems.append(
			(
				"convoy phase %d composition yields %d heavies + 1 core, convoy_count is %d"
				% [index, heavies.size(), entry.convoy_count]
			)
		)
	if entry.convoy_core_slot < 0 or entry.convoy_core_slot >= entry.convoy_count:
		problems.append("convoy phase %d core slot is out of range" % index)
	var last_slot := entry.convoy_slot_time(entry.convoy_count - 1)
	if last_slot >= entry.end_s:
		problems.append(
			(
				"convoy phase %d ends at %.3f but its last slot is at %.3f"
				% [index, entry.end_s, last_slot]
			)
		)
	return problems

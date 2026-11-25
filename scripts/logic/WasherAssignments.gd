class_name WasherAssignments
extends RefCounted
## Phase -> four washer requirements (AGENTS §A6 #10, docs/M4_WASHERS.md).
##
## This is the deliberate onboarding ramp: two colour washers first, then a pattern washer,
## then a second pattern washer, and a full re-shuffle in the Final Load. Rows are plain
## data so [CosmicWasher] never hard-codes a requirement and the shift can re-shuffle the
## machines at a phase boundary.
##
## ## Known coverage gap (reported to the lead, not silently patched)
## A washer requirement is a colour *or* a pattern (see [Compatibility]). With four washers
## split 2 colours + 2 patterns the best possible coverage of the nine `(colour, pattern)`
## variants is **eight**: the two colour washers cover six, and the two pattern washers can
## only cover the third colour in two of its three patterns. The mandated table therefore
## leaves one orphan per phase from phase 3 on:
##
## * phase 3 (index 2): `yellow_ringed`
## * phase 4 (index 3): `blue_spotted`
##
## [method coverage_ok] reports this honestly instead of pretending. Fix options for the
## lead (both outside this file's ownership): restrict a phase's `allowed_patterns` per
## colour in `data/phases.tres`, or give one washer per phase the `wild` requirement.

## Four corner ids, matching `data/layout.json`.
const WASHER_IDS: Array[StringName] = [&"washer_nw", &"washer_ne", &"washer_sw", &"washer_se"]

const PHASE_COUNT := 4

## `TABLE[phase] = [{washer_id, requirement, locked}, ...]` in NW, NE, SW, SE order.
##
## P1: red + blue, south half offline (onboarding).
## P2: + the south-west pattern washer (`solid`).
## P3: + the south-east pattern washer (`spotted`).
## P4: yellow + red, `solid` + `ringed` (final re-shuffle).
const TABLE := [
	[
		{"washer_id": &"washer_nw", "requirement": &"red", "locked": false},
		{"washer_id": &"washer_ne", "requirement": &"blue", "locked": false},
		{"washer_id": &"washer_sw", "requirement": &"solid", "locked": true},
		{"washer_id": &"washer_se", "requirement": &"spotted", "locked": true},
	],
	[
		{"washer_id": &"washer_nw", "requirement": &"red", "locked": false},
		{"washer_id": &"washer_ne", "requirement": &"blue", "locked": false},
		{"washer_id": &"washer_sw", "requirement": &"solid", "locked": false},
		{"washer_id": &"washer_se", "requirement": &"spotted", "locked": true},
	],
	[
		{"washer_id": &"washer_nw", "requirement": &"red", "locked": false},
		{"washer_id": &"washer_ne", "requirement": &"blue", "locked": false},
		{"washer_id": &"washer_sw", "requirement": &"solid", "locked": false},
		{"washer_id": &"washer_se", "requirement": &"spotted", "locked": false},
	],
	[
		{"washer_id": &"washer_nw", "requirement": &"yellow", "locked": false},
		{"washer_id": &"washer_ne", "requirement": &"red", "locked": false},
		{"washer_id": &"washer_sw", "requirement": &"solid", "locked": false},
		{"washer_id": &"washer_se", "requirement": &"ringed", "locked": false},
	],
]

## Fallback spawn variants when `data/phases.tres` is unavailable (AGENTS §A6 #10).
const FALLBACK_COLORS := [
	[&"red", &"blue"],
	[&"red", &"blue"],
	[&"red", &"blue", &"yellow"],
	[&"red", &"blue", &"yellow"],
]
const FALLBACK_PATTERNS := [
	[&"solid"],
	[&"solid", &"ringed"],
	[&"solid", &"ringed", &"spotted"],
	[&"solid", &"ringed", &"spotted"],
]

## Item id used to probe `Compatibility.item_fits` without triggering the wildcard rule.
const PROBE_ITEM := &"rocky"


## Rows for `phase`, in NW, NE, SW, SE order. Copies, so callers may mutate freely.
static func table(phase: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var source: Array = TABLE[clampi(phase, 0, TABLE.size() - 1)]
	for row: Dictionary in source:
		rows.append(row.duplicate())
	return rows


## Phase -> `{ "washer_nw": {"requirement": &"red", "locked": false}, ... }`.
##
## Always four entries, so `MainLevel` can configure a phase in one loop. Locked rows carry
## the requirement they will have when they unlock (pre-wiring), which keeps `set_locked`
## the only change a boundary needs.
static func for_phase(phase: int) -> Dictionary:
	var out := {}
	for row in table(phase):
		out[str(row["washer_id"])] = {
			"requirement": StringName(str(row["requirement"])),
			"locked": bool(row["locked"]),
		}
	return out


## Requirement of one washer in one phase; `&"wild"` when the id is unknown.
static func requirement_for(phase: int, washer_id: StringName) -> StringName:
	for row in table(phase):
		if StringName(str(row["washer_id"])) == washer_id:
			return StringName(str(row["requirement"]))
	return &"wild"


## True when `washer_id` is offline in `phase`.
static func is_locked(phase: int, washer_id: StringName) -> bool:
	for row in table(phase):
		if StringName(str(row["washer_id"])) == washer_id:
			return bool(row["locked"])
	return true


## True when at least one unlocked washer in `phase` accepts the variant.
static func has_home(phase: int, color: StringName, pattern: StringName) -> bool:
	for row in table(phase):
		if bool(row["locked"]):
			continue
		var requirement := StringName(str(row["requirement"]))
		if Compatibility.item_fits(PROBE_ITEM, color, pattern, requirement):
			return true
	return false


## Every `(colour, pattern)` pair the phase's spawn table can produce, as
## `[{color, pattern}, ...]`. Reads `data/phases.tres`; falls back to the AGENTS §A6 #10
## ramp when the resource is missing.
static func allowed_variants(phase: int) -> Array[Dictionary]:
	var index := clampi(phase, 0, PHASE_COUNT - 1)
	var colors: Array = FALLBACK_COLORS[index]
	var patterns: Array = FALLBACK_PATTERNS[index]
	var phase_data := _phase_data(index)
	if phase_data != null:
		colors = phase_data.allowed_colors
		patterns = phase_data.allowed_patterns
	var out: Array[Dictionary] = []
	for color: StringName in colors:
		for pattern: StringName in patterns:
			out.append({"color": color, "pattern": pattern})
	return out


## Variants that no unlocked washer in `phase` accepts, named `"colour_pattern"`.
static func uncovered_variants(phase: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for variant in allowed_variants(phase):
		var color := StringName(str(variant["color"]))
		var pattern := StringName(str(variant["pattern"]))
		if not has_home(phase, color, pattern):
			out.append(Config.variant_name(color, pattern))
	return out


## True when every variant the phase can spawn has a home. See the class note: phases 3
## and 4 report false until the frozen phase table or this ramp is amended.
static func coverage_ok(phase: int) -> bool:
	return uncovered_variants(phase).is_empty()


static func _phase_data(phase: int) -> PhaseData:
	var phase_table := PhaseTable.load_default()
	if phase_table == null:
		return null
	return phase_table.phase(phase)

class_name PhaseData
extends Resource
## One entry of the GDD §2.5 phase table.
##
## Everything the spawner, the belts and the HUD need to know about a phase lives here so
## `data/phases.tres` remains the single source of truth. Balance numbers never appear in
## code: they are exported fields, filled by the `.tres`.

## Phase index in the shift (0-3). Must equal the entry order in `PhaseTable`.
@export var index: int = 0
## Translation key for the phase name, e.g. `&"PHASE_OPENING"`.
@export var name_key: StringName = &""
## Inclusive start of the phase, in seconds since the shift began.
@export var start_s: float = 0.0
## Exclusive end of the phase, in seconds since the shift began.
@export var end_s: float = 0.0
## Musical tempo of the phase's stem (GDD §2.5).
@export var bpm: int = 105
## Seconds between regular spawns. `0.0` means the phase is a scripted convoy.
@export var spawn_interval_s: float = 3.5
## Belts that are running during this phase, by `belt_id` from `data/layout.json`.
@export var active_belts: Array[StringName] = []
## Variants this phase may spawn (`red`, `blue`, …).
@export var allowed_colors: Array[StringName] = []
## Patterns this phase may spawn (`solid`, `ringed`, `spotted`).
@export var allowed_patterns: Array[StringName] = []
## Relative weight per item id. Zero or missing means "never spawns here".
@export var item_weights: Dictionary = {}
## When true the phase ignores `spawn_interval_s` and runs `convoy_*` instead.
@export var convoy: bool = false
## Total objects delivered during a convoy, core included.
@export var convoy_count: int = 0
## Item id -> count for the convoy's heavy objects (core excluded).
@export var convoy_composition: Dictionary = {}
## Seconds between two convoy slots.
@export var convoy_interval_s: float = 0.0
## Item id of the unique final object (wildcard, no colour/pattern variant).
@export var convoy_core_item: StringName = &""
## Zero-based convoy slot reserved for `convoy_core_item`.
@export var convoy_core_slot: int = 0


## Length of the phase in seconds.
func duration_s() -> float:
	return end_s - start_s


## True when `t` (shift seconds) falls inside this phase: start inclusive, end exclusive.
func contains(t: float) -> bool:
	return t >= start_s and t < end_s


## Weight of an item id in this phase's weighted draw; 0.0 when the id cannot spawn.
func weight_for(item_id: StringName) -> float:
	if convoy:
		return 0.0
	var raw: Variant = item_weights.get(item_id, 0.0)
	return maxf(float(raw), 0.0)


## Sum of every item weight. Zero for convoy phases.
func total_weight() -> float:
	var total := 0.0
	for item_id in item_weights.keys():
		total += weight_for(StringName(item_id))
	return total


## Ordered convoy item ids (heavies only, core excluded), honouring
## `convoy_composition`'s insertion order.
func convoy_heavy_items() -> Array[StringName]:
	var out: Array[StringName] = []
	for item_id in convoy_composition.keys():
		var count := int(convoy_composition[item_id])
		for _i in range(maxi(count, 0)):
			out.append(StringName(item_id))
	return out


## Time of convoy slot `slot`, in shift seconds.
func convoy_slot_time(slot: int) -> float:
	return start_s + float(slot) * convoy_interval_s

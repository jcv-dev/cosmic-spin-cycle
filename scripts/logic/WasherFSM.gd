class_name WasherFSM
extends RefCounted
## Pure washing-machine state machine (GDD §5.2, AGENTS §A6 #2..#8).
##
## The FSM owns every washer rule and has no scene, node, autoload-clock or rendering
## dependency: time only enters through [method tick], and every other input (requirement,
## lock, phase, beat length, rhythm grade) arrives through an explicit call. That is what
## makes the whole loop table-testable. [CosmicWasher] is a renderer plus event forwarder.
##
## ## States
## `IDLE -> WASHING -> (TURBULENT) -> DONE`, and any state `-> BROKEN`, which returns to
## `IDLE` after [constant REPAIR_COOLDOWN_S].
##
## ## Events
## Mutators return a bool and queue events; [method tick] advances time and returns the
## queued events (it drains the queue). [method take_events] drains without advancing.
## Every event is a Dictionary whose `type` key is one of:
##
## | type | payload | meaning |
## |---|---|---|
## | `washing_started` | cycle_time | a cycle began |
## | `progress` | progress, remaining, cycle | one tick of wash progress |
## | `turbulent` | limit, reason | the drum went turbulent |
## | `turbulence_resolved` | grade | a good enough strike calmed it |
## | `cycle_done` | items | the load is clean and collectable |
## | `exploded` | items, reason | the drum collapsed and ejected the load |
## | `repaired` | — | a broken washer is usable again |
##
## `reason` (StringName) is `&"cycle"` (the phase-3 every-third-cycle rule), `&"accumulated"`
## (turbulence reached 1.0) or `&"forced"` (tutorial/debug hook). Explosion reasons are
## `&"turbulence"` (timeout) or `&"forced"` (explicit call).

enum State { IDLE, WASHING, TURBULENT, DONE, BROKEN }

## Rejection reasons stored in [member last_reject].
const REJECT_NONE := &""
const REJECT_FULL := &"full"
const REJECT_INCOMPATIBLE := &"incompatible"
const REJECT_BUSY := &"busy"
const REJECT_LOCKED := &"locked"
const REJECT_WILDCARD_NEEDS_EMPTY := &"wildcard_needs_empty"
const REJECT_INVALID := &"invalid"

## Grade value for "the caller did not grade this throw" (no reduction, no turbulence).
const GRADE_UNKNOWN := -1

## Provisional (see docs/M4_WASHERS.md): the GDD numbers live in Config, these two encode
## §A6 #6's "phases >= 3" (the GDD counts phases from 1) and the cycle cadence.
const AUTO_TURBULENCE_PHASE := 2
const AUTO_TURBULENCE_EVERY := 3

## Seconds a finished load stays in the drum before it can be collected, so the node can
## play the `done` animation. Provisional; promote to Config if it needs tuning.
const DONE_SETTLE_S := 0.35
## Seconds a broken washer stays out of order. Provisional (brief: "say 6 s").
const REPAIR_COOLDOWN_S := 6.0

## Slots of a galaxy core: it is a wildcard that fills the whole drum.
const CAPACITY := Config.WASHER_CAPACITY
const MIN_WASH_TIME_S := Config.MIN_WASH_TIME_S

var state: int = State.IDLE
var requirement: StringName = &"wild"
var locked := false
var phase := 0
var beat_seconds: float = Config.beat_seconds(float(Config.PHASE_BPM[0]))
## 0..1; reaching 1.0 while WASHING enters TURBULENT.
var turbulence := 0.0
## Seconds left in the current cycle.
var remaining := 0.0
## Total length of the current cycle in seconds (0 outside WASHING/TURBULENT/DONE).
var cycle_time := 0.0
## Completed cycles since the washer was created (drives the phase-3 rule).
var cycle_count := 0
## Slots occupied by the current load (galaxy core uses the whole drum).
var slots_used := 0
## Why the last [method insert] failed; `&""` after a successful load.
var last_reject: StringName = REJECT_NONE

var _events: Array[Dictionary] = []
var _load: Array[Dictionary] = []
## Wash reduction from throws that arrived before the cycle started (AGENTS §A6 #8).
var _pending_reduction := 0.0
var _auto_start_left := -1.0
var _settle_elapsed := 0.0
var _turbulence_elapsed := 0.0
var _auto_turbulent_at := -1.0
var _auto_turbulence_fired := false
var _repair_left := 0.0

# --- configuration ----------------------------------------------------------


## Normalises an empty requirement to `wild`, so an unconfigured washer is forgiving.
func set_requirement(value: StringName) -> void:
	requirement = &"wild" if value == &"" else value


func get_requirement() -> StringName:
	return requirement


func set_locked(value: bool) -> void:
	locked = value


func is_locked() -> bool:
	return locked


## Phase index 0-3 (the shift table's zero-based index).
func set_phase(value: int) -> void:
	phase = maxi(value, 0)


## Length of one beat for the turbulence timeout (`min(5 s, 8 beats)`, AGENTS §A6 #5).
func set_beat_seconds(value: float) -> void:
	if value > 0.0:
		beat_seconds = value


# --- queries ----------------------------------------------------------------


func get_state() -> int:
	return state


## 0..1 through the current cycle (1.0 while DONE). While BROKEN it reports the repair
## progress instead, so a single ring can render either meaning.
func get_progress() -> float:
	match state:
		State.DONE:
			return 1.0
		State.BROKEN:
			if REPAIR_COOLDOWN_S <= 0.0:
				return 1.0
			return clampf(1.0 - _repair_left / REPAIR_COOLDOWN_S, 0.0, 1.0)
		State.WASHING, State.TURBULENT:
			if cycle_time <= 0.0:
				return 0.0
			return clampf(1.0 - remaining / cycle_time, 0.0, 1.0)
		_:
			return 0.0


## True once the DONE animation had its settle window (see [constant DONE_SETTLE_S]).
func can_collect() -> bool:
	return state == State.DONE and _settle_elapsed >= DONE_SETTLE_S


func get_loaded_items() -> Array:
	var out: Array = []
	for entry in _load:
		out.append(entry.get("item"))
	return out


func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_events)
	_events.clear()
	return out


## Effective turbulence limit in seconds: `min(5 s, 8 beats)` (AGENTS §A6 #5).
func _turbulence_limit() -> float:
	if beat_seconds <= 0.0:
		return Config.TURBULENCE_TIMEOUT_S
	return minf(Config.TURBULENCE_TIMEOUT_S, float(Config.TURBULENCE_TIMEOUT_BEATS) * beat_seconds)


# --- loading ----------------------------------------------------------------


## Loads `item` when the rules allow it.
##
## `item` may be a [LaundryItem] or a Dictionary describing one (`id`, `color`, `pattern`,
## `wash_s`, `slots`). `info` overrides those fields; `grade` is the rhythm grade of the
## throw that delivered the item and only drives the once-per-throw reduction and the MISS
## turbulence gain (AGENTS §A6 #6/#8). Returns false and sets [member last_reject] when the
## item cannot enter (full, incompatible, busy, locked, wildcard in a dirty drum).
func insert(item: Variant, info: Dictionary = {}, grade: int = GRADE_UNKNOWN) -> bool:
	last_reject = REJECT_NONE
	var entry := _merge_info(item, info)
	var reason := _can_accept(entry)
	if reason != REJECT_NONE:
		last_reject = reason
		return false
	_load.append(entry)
	_recount()
	if state == State.WASHING:
		_apply_reduction(grade)
	else:
		_pending_reduction += _reduction_for(grade)
	_apply_miss_turbulence(grade)
	if state == State.IDLE and slots_used >= CAPACITY:
		_start_cycle()
	elif state == State.IDLE and _load.size() > 0:
		_auto_start_left = Config.WASHER_AUTO_START_S
	return true


## Starts a cycle from IDLE. Empty washers use `Config.WASH_BASE_S` (AGENTS §A6 #3).
func start_cycle() -> bool:
	if state != State.IDLE:
		return false
	return _start_cycle()


## Rhythm strike (GDD §5.2, AGENTS §A6 #4/#7).
##
## Resolves TURBULENT with a grade >= GOOD, starts a cycle when IDLE with at least one
## item, and does nothing otherwise. Returns true when the strike mattered.
func strike(grade: int) -> bool:
	if locked:
		return false
	if state == State.TURBULENT:
		if not RhythmEvaluator.resolves_turbulence(grade):
			return false
		return _resolve_turbulence(grade)
	if state == State.IDLE and not _load.is_empty():
		return _start_cycle()
	return false


## Adds `amount` (0..1) of turbulence; returns true when it tipped into TURBULENT.
func add_turbulence(amount: float) -> bool:
	if amount <= 0.0:
		return false
	if state == State.TURBULENT:
		turbulence = 1.0
		return false
	turbulence = clampf(turbulence + amount, 0.0, 1.0)
	if turbulence >= 1.0 and state == State.WASHING:
		_enter_turbulent(&"accumulated")
		return true
	return false


## Tutorial hook: jump the current (or a freshly started) cycle to 50 % and go turbulent.
func force_turbulent() -> bool:
	if state == State.TURBULENT:
		return false
	if state == State.IDLE:
		if _load.is_empty():
			return false
		_start_cycle()
	if state != State.WASHING:
		return false
	remaining = maxf(cycle_time * (1.0 - Config.TURBULENCE_AT_PROGRESS), Config.MIN_WASH_TIME_S)
	_enter_turbulent(&"forced")
	return state == State.TURBULENT


## Tutorial/test hook: finish the current cycle immediately.
func force_finish() -> bool:
	if state != State.WASHING and state != State.TURBULENT:
		return false
	remaining = 0.0
	_complete()
	return true


## Any state -> BROKEN, ejecting the load. Returns the queued events.
func explode(reason: StringName = &"forced") -> Array[Dictionary]:
	_explode(reason)
	return take_events()


## Takes the clean load out of a DONE washer. Returns [] before the settle window.
func collect() -> Array:
	if not can_collect():
		return []
	var items: Array = []
	for entry in _load:
		items.append(entry.get("item"))
	_load.clear()
	_auto_start_left = -1.0
	_recount()
	state = State.IDLE
	cycle_time = 0.0
	remaining = 0.0
	_settle_elapsed = 0.0
	return items


# --- time -------------------------------------------------------------------


## Advances the machine by `dt` seconds and returns every queued event.
func tick(dt: float) -> Array[Dictionary]:
	if dt > 0.0:
		_advance(dt)
	return take_events()


# --- internals --------------------------------------------------------------


static func _reduction_for(grade: int) -> float:
	if grade < 0:
		return 0.0
	return RhythmEvaluator.wash_reduction_s(grade)


## Pure description of one item for the rules.
static func _read_info(item: Variant) -> Dictionary:
	var out := {
		"id": &"",
		"color": &"",
		"pattern": &"",
		"wash_s": Config.WASH_BASE_S,
		"slots": 1,
	}
	if item == null:
		return out
	if item is Dictionary:
		_read_dict(out, item as Dictionary)
	elif item is Object:
		_read_object(out, item as Object)
	out["item"] = item
	return out


static func _read_dict(out: Dictionary, source: Dictionary) -> void:
	if source.has("id"):
		out["id"] = StringName(str(source["id"]))
	elif source.has("item_id"):
		out["id"] = StringName(str(source["item_id"]))
	if source.has("color"):
		out["color"] = StringName(str(source["color"]))
	if source.has("pattern"):
		out["pattern"] = StringName(str(source["pattern"]))
	if source.has("wash_s"):
		out["wash_s"] = float(source["wash_s"])
	if source.has("slots"):
		out["slots"] = int(source["slots"])


static func _read_object(out: Dictionary, item: Object) -> void:
	var data: Variant = item.get(&"data")
	var source: Object = data as Object if data is Object else item
	var id_value: Variant = item.get(&"item_id")
	if id_value == null:
		id_value = source.get(&"id")
	if id_value != null:
		out["id"] = StringName(str(id_value))
	var color_value: Variant = item.get(&"color")
	if color_value != null:
		out["color"] = StringName(str(color_value))
	var pattern_value: Variant = item.get(&"pattern")
	if pattern_value != null:
		out["pattern"] = StringName(str(pattern_value))
	var wash_value: Variant = source.get(&"wash_s")
	if wash_value != null:
		out["wash_s"] = float(wash_value)
	var slots_value: Variant = source.get(&"slots")
	if slots_value != null:
		out["slots"] = maxi(int(slots_value), 1)


## `_read_info(item)` with caller overrides applied.
static func _merge_info(item: Variant, info: Dictionary = {}) -> Dictionary:
	var entry := _read_info(item)
	for key: Variant in info.keys():
		entry[key] = info[key]
	entry["item"] = item
	if Compatibility.is_wildcard(StringName(str(entry.get("id", &"")))):
		entry["slots"] = CAPACITY
	return entry


## One return, assigned per branch (the linter caps return statements at six).
func _can_accept(entry: Dictionary) -> StringName:
	var reason := REJECT_NONE
	var item_id := StringName(str(entry.get("id", &"")))
	var slots := maxi(int(entry.get("slots", 1)), 1)
	if locked:
		reason = REJECT_LOCKED
	elif state != State.IDLE and state != State.WASHING:
		reason = REJECT_BUSY
	elif item_id == &"" or slots <= 0:
		reason = REJECT_INVALID
	elif Compatibility.is_wildcard(item_id):
		if slots_used > 0:
			reason = REJECT_WILDCARD_NEEDS_EMPTY
		elif slots > CAPACITY:
			reason = REJECT_FULL
	elif slots_used + slots > CAPACITY:
		reason = REJECT_FULL
	elif not _fits_requirement(entry, item_id):
		reason = REJECT_INCOMPATIBLE
	return reason


func _fits_requirement(entry: Dictionary, item_id: StringName) -> bool:
	return Compatibility.item_fits(
		item_id,
		StringName(str(entry.get("color", &""))),
		StringName(str(entry.get("pattern", &""))),
		requirement
	)


func _advance(dt: float) -> void:
	if state == State.IDLE and _auto_start_left > 0.0:
		_auto_start_left = maxf(_auto_start_left - dt, 0.0)
		if _auto_start_left <= 0.0 and _load.size() > 0:
			_start_cycle()
	match state:
		State.WASHING:
			_advance_washing(dt)
		State.TURBULENT:
			_advance_turbulent(dt)
		State.DONE:
			_settle_elapsed += dt
		State.BROKEN:
			_repair_left = maxf(_repair_left - dt, 0.0)
			if _repair_left <= 0.0:
				_repair()
		_:
			pass


func _advance_washing(dt: float) -> void:
	remaining = maxf(remaining - dt, 0.0)
	_push_progress()
	if _auto_turbulent_at >= 0.0 and not _auto_turbulence_fired:
		if get_progress() >= _auto_turbulent_at:
			_auto_turbulence_fired = true
			_enter_turbulent(&"cycle")
			return
	if turbulence >= 1.0:
		_enter_turbulent(&"accumulated")
	elif remaining <= 0.0:
		_complete()


func _advance_turbulent(dt: float) -> void:
	_turbulence_elapsed += dt
	remaining = maxf(remaining - dt, 0.0)
	_push_progress()
	if _turbulence_elapsed >= _turbulence_limit():
		_explode(&"turbulence")


func _start_cycle() -> bool:
	_auto_start_left = -1.0
	var length := _cycle_time()
	cycle_time = length
	remaining = maxf(length - _pending_reduction, minf(length, MIN_WASH_TIME_S))
	_pending_reduction = 0.0
	cycle_count += 1
	_settle_elapsed = 0.0
	_turbulence_elapsed = 0.0
	_auto_turbulence_fired = false
	_auto_turbulent_at = -1.0
	if phase >= AUTO_TURBULENCE_PHASE and cycle_count % AUTO_TURBULENCE_EVERY == 0:
		_auto_turbulent_at = Config.TURBULENCE_AT_PROGRESS
	state = State.WASHING
	_push(&"washing_started", {"cycle_time": cycle_time})
	if turbulence >= 1.0:
		_enter_turbulent(&"accumulated")
	return true


func _explode(reason: StringName) -> void:
	if state == State.BROKEN:
		return
	var items := get_loaded_items()
	_load.clear()
	_auto_start_left = -1.0
	_recount()
	state = State.BROKEN
	_repair_left = REPAIR_COOLDOWN_S
	remaining = 0.0
	cycle_time = 0.0
	_pending_reduction = 0.0
	_auto_turbulent_at = -1.0
	turbulence = 0.0
	_push(&"exploded", {"items": items, "reason": reason})


func _complete() -> void:
	state = State.DONE
	_settle_elapsed = 0.0
	_auto_turbulent_at = -1.0
	_turbulence_elapsed = 0.0
	_push(&"cycle_done", {"items": get_loaded_items()})


func _enter_turbulent(reason: StringName) -> void:
	if state != State.WASHING:
		return
	state = State.TURBULENT
	_turbulence_elapsed = 0.0
	turbulence = 1.0
	_push(&"turbulent", {"limit": _turbulence_limit(), "reason": reason})


func _resolve_turbulence(grade: int) -> bool:
	if state != State.TURBULENT:
		return false
	turbulence = 0.0
	state = State.WASHING
	_turbulence_elapsed = 0.0
	_auto_turbulent_at = -1.0
	_auto_turbulence_fired = true
	_push(&"turbulence_resolved", {"grade": grade})
	return true


func _repair() -> void:
	state = State.IDLE
	_repair_left = 0.0
	turbulence = 0.0
	cycle_time = 0.0
	remaining = 0.0
	_settle_elapsed = 0.0
	_push(&"repaired")


func _apply_reduction(grade: int) -> void:
	var reduction := _reduction_for(grade)
	if reduction <= 0.0:
		return
	# Never below 2 s, and never *raise* a cycle that is already under the floor.
	remaining = maxf(remaining - reduction, minf(remaining, MIN_WASH_TIME_S))


func _apply_miss_turbulence(grade: int) -> void:
	if grade == RhythmEvaluator.Grade.MISS:
		add_turbulence(Config.MISS_TURBULENCE_GAIN)


func _cycle_time() -> float:
	if _load.is_empty():
		return maxf(Config.WASH_BASE_S, MIN_WASH_TIME_S)
	var longest := 0.0
	for entry in _load:
		longest = maxf(longest, float(entry.get("wash_s", 0.0)))
	return maxf(longest, MIN_WASH_TIME_S)


func _recount() -> void:
	slots_used = 0
	for entry in _load:
		slots_used += maxi(int(entry.get("slots", 1)), 1)


func _push_progress() -> void:
	_push(&"progress", {"progress": get_progress(), "remaining": remaining, "cycle": cycle_count})


func _push(type: StringName, payload: Dictionary = {}) -> void:
	var event := payload.duplicate()
	event["type"] = type
	_events.append(event)

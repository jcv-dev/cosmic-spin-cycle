class_name TutorialSteps
extends RefCounted
## Pure seven-gate tutorial table and gating logic (docs/UX_BIBLE.md §16.1).
##
## No scene, node or audio dependency: the director feeds one event in and gets the new
## state out, so every threshold, window widening and fail-forward path is unit-tested
## without a level. `steps()` is the data table; `advance()` is the only mutator.
##
## State dictionary (all keys always present, so tests can compare whole dicts):
##   index        int   current gate, 0-based
##   elapsed      float seconds spent on the current gate
##   travel       float px travelled on gate 1 (never accumulates elsewhere)
##   count        int   successes accumulated for a multi-hit gate (gate 4)
##   misses       int   failed rhythm attempts on the current gate
##   granted      bool  the gate's success condition fired
##   hint         bool  the fail-forward hint is visible
##   soft_skip_ready bool TAB may grant this gate (docs/UX_BIBLE.md §7)
##   window_scale float grading tolerance multiplier for rhythm gates
##   rejected     int   wrong-mouth bounces since the last advance (feedback only)
##   feedback     StringName short tag the director turns into audio/visual feedback

const STEP_COUNT := 7

## Gate 1 — 200 px travelled; a dotted circle at 120 px appears after 4 s.
const TRAVEL_TARGET_PX := 200.0
const TRAVEL_HINT_AFTER_S := 4.0
const TRAVEL_HINT_RADIUS_PX := 120.0
## Gate 2 — after this long the item is steered inside the grab radius.
const GRAB_HINT_AFTER_S := 6.0
## Gate 4 — two throws at GOOD or better, then fail-forward.
const BEAT_THROWS_REQUIRED := 2
const BEAT_MISSES_TO_WIDEN := 2
const BEAT_MISSES_TO_GRANT := 3
## §16.1 fail-forward floor: the GOOD window is never tighter than ±195 ms here. The
## ×2 tutorial scale already exceeds it, so the widening that actually fires multiplies
## the base window; the 195 ms constant keeps the doc's promise if balance tunes it down.
const BEAT_WIDE_WINDOW_S := 0.195
const BEAT_WIDEN_FACTOR := 1.5
## Gate 6 — the scripted washer can never explode: re-force turbulence, then assist.
const STRIKE_HINT_AFTER_S := 10.0
const STRIKE_ASSIST_AFTER_S := 20.0
## Gate 7 — beacon pulse period.
const BEACON_PERIOD_S := 2.0
## Rhythm gates grade with the tutorial tolerance, not the shift tolerance.
const STRIKE_WINDOW_SCALE := 2.0


## The seven gates in play order. Copy is frozen by docs/UX_BIBLE.md §16.1; prompts stay
## inside 24 characters so the world-space chip never wraps (docs/UX_BIBLE.md §12.10).
static func steps() -> Array[Dictionary]:
	return [
		{
			"id": &"move",
			"title": "MUÉVETE",
			"prompt": "WASD / STICK",
			"kind": &"travel",
			"max_words": 3,
			"hint_after_s": TRAVEL_HINT_AFTER_S,
		},
		{
			"id": &"grab",
			"title": "AGARRA",
			"prompt": "ESPACIO O BOTÓN A",
			"kind": &"grab",
			"max_words": 4,
			"hint_after_s": GRAB_HINT_AFTER_S,
		},
		{
			"id": &"throw",
			"title": "LANZA",
			"prompt": "APUNTA Y LANZA",
			"kind": &"throw",
			"max_words": 3,
			"hint_after_s": GRAB_HINT_AFTER_S,
		},
		{
			"id": &"beat",
			"title": "LANZA AL RITMO",
			"prompt": "ESPERA EL PULSO",
			"kind": &"grade",
			"max_words": 3,
			"hint_after_s": STRIKE_HINT_AFTER_S,
		},
		{
			"id": &"match",
			"title": "SUELTA AQUÍ",
			"prompt": "SUELTA EN LA ROJA",
			"kind": &"insert",
			"max_words": 4,
			"hint_after_s": GRAB_HINT_AFTER_S,
		},
		{
			"id": &"strike",
			"title": "GOLPE AL RITMO",
			"prompt": "SHIFT AL PULSO",
			"kind": &"strike",
			"max_words": 3,
			"hint_after_s": STRIKE_HINT_AFTER_S,
		},
		{
			"id": &"deliver",
			"title": "LLEVA EL LIMPIO AL DUCTO",
			"prompt": "AL DUCTO DEL CENTRO",
			"kind": &"deliver",
			"max_words": 4,
			"hint_after_s": GRAB_HINT_AFTER_S,
		},
	]


static func clamp_index(index: int) -> int:
	return clampi(index, 0, STEP_COUNT - 1)


static func step(index: int) -> Dictionary:
	return steps()[clamp_index(index)]


static func step_index_of(id: StringName) -> int:
	for index in range(STEP_COUNT):
		if StringName(steps()[index]["id"]) == id:
			return index
	return -1


static func title_for(index: int) -> String:
	return String(step(index)["title"])


static func prompt_for(index: int) -> String:
	return String(step(index)["prompt"])


static func kind_for(index: int) -> StringName:
	return StringName(step(index)["kind"])


## "PASO 2/7 · AGARRA" — the top chip (docs/UX_BIBLE.md §7).
static func chip_text(index: int) -> String:
	var safe := clamp_index(index)
	return "PASO %d/%d · %s" % [safe + 1, STEP_COUNT, title_for(safe)]


## Fresh state for a gate. `window_scale` starts at the tutorial tolerance; the gradient
## gate widens it after two misses.
static func new_state(index: int = 0) -> Dictionary:
	return {
		"index": clamp_index(index),
		"elapsed": 0.0,
		"travel": 0.0,
		"count": 0,
		"misses": 0,
		"granted": false,
		"hint": false,
		"soft_skip_ready": false,
		"window_scale": window_scale(0),
		"rejected": 0,
		"feedback": &"",
	}


## Effective GOOD tolerance for gate 4/6, in seconds.
static func good_window_s(misses: int) -> float:
	var base := maxf(BEAT_WIDE_WINDOW_S, Config.WINDOW_GOOD_S * Config.TUTORIAL_WINDOW_SCALE)
	if misses >= BEAT_MISSES_TO_WIDEN:
		return base * BEAT_WIDEN_FACTOR
	return base


static func window_scale(misses: int) -> float:
	return good_window_s(misses) / Config.WINDOW_GOOD_S


## Tutorial grading for a rhythm attempt, in seconds to the nearest beat.
static func grade_throw(delta_t: float, misses: int) -> int:
	return RhythmEvaluator.evaluate(delta_t, window_scale(misses))


## Gate 6 grades with the flat tutorial tolerance (no fail-forward widening needed: the
## washer cannot explode and the director rescues a stalled player).
static func grade_strike(delta_t: float) -> int:
	return RhythmEvaluator.evaluate(delta_t, STRIKE_WINDOW_SCALE)


## 0..1 fill for the 2 px cyan underline under the chip.
static func progress(state: Dictionary) -> float:
	if bool(state.get("granted", false)):
		return 1.0
	match kind_for(int(state.get("index", 0))):
		&"travel":
			return clampf(float(state.get("travel", 0.0)) / TRAVEL_TARGET_PX, 0.0, 1.0)
		&"grade":
			return clampf(float(state.get("count", 0)) / float(BEAT_THROWS_REQUIRED), 0.0, 1.0)
		&"strike":
			return 0.0
		_:
			return 0.0


static func is_rhythm_gate(index: int) -> bool:
	var kind := kind_for(index)
	return kind == &"grade" or kind == &"strike"


## Call once per frame: advances the dwell timer, the fail-forward hint and — after the
## soft-skip grace — makes TAB legal. Returns the same dictionary it was given, mutated.
static func tick(state: Dictionary, delta: float) -> Dictionary:
	if bool(state.get("granted", false)):
		return state
	state["elapsed"] = float(state.get("elapsed", 0.0)) + maxf(delta, 0.0)
	var hint_after := float(step(int(state.get("index", 0))).get("hint_after_s", 4.0))
	state["hint"] = float(state["elapsed"]) >= hint_after
	# Only the stuck grace makes TAB legal (§7): a visible hint is an invitation, not a
	# licence to skip the gate the player is still learning.
	state["soft_skip_ready"] = float(state["elapsed"]) >= Config.TUTORIAL_SOFT_SKIP_S
	return state


## Applies one event and returns the *same* state dictionary, mutated in place, so the
## director never reallocates per frame. Unknown events for the active gate are ignored.
static func advance(state: Dictionary, event: Dictionary) -> Dictionary:
	state["rejected"] = 0
	state["feedback"] = &""
	if bool(state.get("granted", false)):
		return state
	var ev := StringName(event.get("kind", ""))
	if ev == &"tick":
		return tick(state, float(event.get("delta", 0.0)))
	if ev == &"skip":
		_grant(state, &"skipped")
		return state
	var kind := kind_for(int(state.get("index", 0)))
	match kind:
		&"travel":
			_apply_travel(state, ev, event)
		&"grab":
			if ev == &"grab":
				_grant(state, &"granted")
		&"throw":
			if ev == &"throw" and bool(event.get("left_hold", false)):
				_grant(state, &"granted")
		&"grade":
			if ev == &"throw":
				_apply_grade(state, event)
		&"insert":
			_apply_insert(state, ev, event)
		&"strike":
			_apply_strike(state, ev, event)
		&"deliver":
			_apply_deliver(state, ev, event)
		_:
			pass
	return state


static func _grant(state: Dictionary, feedback: StringName = &"granted") -> void:
	state["granted"] = true
	state["feedback"] = feedback


## Gate 1 only: a travel event during another gate must never accumulate.
static func _apply_travel(state: Dictionary, ev: StringName, event: Dictionary) -> void:
	if ev != &"travel":
		return
	state["travel"] = float(state.get("travel", 0.0)) + absf(float(event.get("delta", 0.0)))
	if float(state["travel"]) >= TRAVEL_TARGET_PX:
		_grant(state)


## Gate 4: one throw at GOOD or better each, two good throws grant; three misses do too.
static func _apply_grade(state: Dictionary, event: Dictionary) -> void:
	var misses := int(state.get("misses", 0))
	var delta_t := float(event.get("delta_t", 999.0))
	var grade := int(event.get("grade", grade_throw(delta_t, misses)))
	if grade <= RhythmEvaluator.Grade.GOOD:
		state["count"] = int(state.get("count", 0)) + 1
		if int(state["count"]) >= BEAT_THROWS_REQUIRED:
			_grant(state)
			return
		state["feedback"] = &"good"
		return
	state["misses"] = misses + 1
	state["window_scale"] = window_scale(int(state["misses"]))
	state["feedback"] = &"miss"
	if int(state["misses"]) >= BEAT_MISSES_TO_GRANT:
		_grant(state, &"granted_after_misses")


## Gate 5: only the compatible washer grants; a wrong mouth bounces with no penalty.
static func _apply_insert(state: Dictionary, ev: StringName, event: Dictionary) -> void:
	if ev != &"insert":
		return
	if not bool(event.get("correct", false)):
		state["rejected"] = int(state.get("rejected", 0)) + 1
		state["feedback"] = &"wrong_mouth"
		return
	_grant(state)


## Gate 6: one strike at GOOD or better resolves the scripted turbulence.
static func _apply_strike(state: Dictionary, ev: StringName, event: Dictionary) -> void:
	if ev != &"strike":
		return
	var grade := int(event.get("grade", RhythmEvaluator.Grade.MISS))
	if grade <= RhythmEvaluator.Grade.GOOD:
		_grant(state, &"stabilized")
		return
	state["misses"] = int(state.get("misses", 0)) + 1
	state["feedback"] = &"miss"


## Gate 7: only a clean item counts; a dirty one bounces off the hatch.
static func _apply_deliver(state: Dictionary, ev: StringName, event: Dictionary) -> void:
	if ev != &"deliver":
		return
	if not bool(event.get("clean", false)):
		state["rejected"] = int(state.get("rejected", 0)) + 1
		state["feedback"] = &"dirty"
		return
	_grant(state, &"delivered")

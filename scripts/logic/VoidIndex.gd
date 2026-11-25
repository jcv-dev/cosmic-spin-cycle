class_name VoidIndex
extends RefCounted
## The void index (docs/DECISIONS.md D046): continuous pressure, never a second fail state.
##
## Pure static maths. The director owns the value; this class only says how fast it rises
## per second, how a discrete event moves it, and when it collapses.

const CLEAN := 0.0


## Points per second at `phase` for `difficulty`. Grows with the shift, scaled by preset.
static func rate_per_second(phase: int, difficulty: int) -> float:
	var rate := Config.VOID_RATE_BY_PHASE[clampi(phase, 0, Config.VOID_RATE_BY_PHASE.size() - 1)]
	return rate * Config.DIFFICULTY_VOID_SCALE[Config.difficulty_index(difficulty)]


## Continuous advance for `delta` seconds.
static func advance(value: float, delta: float, phase: int, difficulty: int) -> float:
	return clampf(
		value + rate_per_second(phase, difficulty) * maxf(delta, 0.0),
		Config.VOID_START,
		Config.VOID_MAX
	)


## Applies a discrete gain or relief (deliveries and perfect dodges are negative).
static func bump(value: float, amount: float) -> float:
	return clampf(value + amount, Config.VOID_START, Config.VOID_MAX)


static func is_danger(value: float) -> bool:
	return value >= Config.VOID_DANGER_AT


## True the frame the meter fills: the caller must collapse once and then reset.
static func is_collapse(value: float) -> bool:
	return value >= Config.VOID_COLLAPSE_AT


## Value after a collapse. Above zero on purpose: the player starts the next stretch in
## danger instead of at zero, so the debt stays legible.
static func after_collapse() -> float:
	return Config.VOID_COLLAPSE_RESET


## Fraction 0..1 for the HUD bar.
static func fraction(value: float) -> float:
	return clampf(value / Config.VOID_MAX, 0.0, 1.0)

class_name RhythmEvaluator
extends RefCounted
## Pure rhythm grading (GDD §5.1). No scene or audio dependencies.
##
## Δt is the distance in seconds to the nearest beat, already latency-compensated by
## BeatConductor.get_song_time(). Windows are inclusive.

enum Grade { PERFECT, GOOD, MISS }


static func evaluate(delta_t: float, window_scale: float = 1.0) -> int:
	var scale := maxf(window_scale, 0.001)
	var d := absf(delta_t) / scale
	if d <= Config.WINDOW_PERFECT_S:
		return Grade.PERFECT
	if d <= Config.WINDOW_GOOD_S:
		return Grade.GOOD
	return Grade.MISS


static func grade_name(grade: int) -> String:
	match grade:
		Grade.PERFECT:
			return "PERFECT"
		Grade.GOOD:
			return "GOOD"
		_:
			return "MISS"


## Throw impulse multiplier. PERFECT is +40% (GDD §5.1).
static func force_multiplier(grade: int) -> float:
	if grade == Grade.PERFECT:
		return 1.0 + Config.PERFECT_FORCE_BONUS
	return 1.0


static func combo_gain(grade: int) -> int:
	match grade:
		Grade.PERFECT:
			return int(Config.COMBO_GAIN["PERFECT"])
		Grade.GOOD:
			return int(Config.COMBO_GAIN["GOOD"])
		_:
			return 0


static func wash_reduction_s(grade: int) -> float:
	match grade:
		Grade.PERFECT:
			return float(Config.WASH_REDUCTION_S["PERFECT"])
		Grade.GOOD:
			return float(Config.WASH_REDUCTION_S["GOOD"])
		_:
			return 0.0


## A GOOD or better strike resolves TURBULENT (GDD §A6 #7). MISS does not.
static func resolves_turbulence(grade: int) -> bool:
	return grade == Grade.PERFECT or grade == Grade.GOOD

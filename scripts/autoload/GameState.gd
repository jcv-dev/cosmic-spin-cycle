extends Node
## Single source of truth for shift state: stability, combo, score, phase, RNG and stats.
##
## Nodes react to signals; they never write these fields directly except through the API.

signal stability_changed(v: float)
signal combo_changed(mult: int)
signal score_changed(v: int)
signal phase_changed(idx: int)
signal shift_ended(result: Dictionary)
## Short contextual message for the HUD/overlay layer (never a wall of text).
signal feedback(text: String, kind: StringName)

var stability := Config.STABILITY_START
var combo := Config.COMBO_MIN
var score := 0
var phase_index := 0
var seed_value := 0
var rng := RandomNumberGenerator.new()
var is_ended := false

var perfect_count := 0
var good_count := 0
var miss_count := 0
var rhythm_actions := 0
var max_combo := Config.COMBO_MIN
var delivered_count := 0
var washed_count := 0
var exploded_count := 0
var dropped_count := 0
var wrong_washer_count := 0
var final_load_delivered := 0
var feedback_count := 0

var _end_result: Dictionary = {}


func _ready() -> void:
	rng.randomize()


func reset(p_seed: int = 0) -> void:
	var use_seed := p_seed
	if use_seed == 0:
		use_seed = int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF
	seed_value = use_seed
	rng.seed = use_seed

	stability = Config.STABILITY_START
	combo = Config.COMBO_MIN
	score = 0
	phase_index = 0
	is_ended = false
	perfect_count = 0
	good_count = 0
	miss_count = 0
	rhythm_actions = 0
	max_combo = Config.COMBO_MIN
	delivered_count = 0
	washed_count = 0
	exploded_count = 0
	dropped_count = 0
	wrong_washer_count = 0
	final_load_delivered = 0
	feedback_count = 0
	_end_result = {}

	stability_changed.emit(stability)
	combo_changed.emit(combo)
	score_changed.emit(score)
	phase_changed.emit(phase_index)


func reset_rng(p_seed: int) -> void:
	seed_value = p_seed
	rng.seed = p_seed


func add_stability(delta: float, reason: String = "") -> void:
	if is_ended:
		return
	stability = clampf(stability + delta, 0.0, 100.0)
	stability_changed.emit(stability)
	if stability <= 0.0:
		end_shift(false, reason if reason != "" else "stability")


func register_grade(grade: int) -> void:
	if is_ended:
		return
	rhythm_actions += 1
	if grade == RhythmEvaluator.Grade.PERFECT:
		perfect_count += 1
		combo = mini(combo + int(Config.COMBO_GAIN["PERFECT"]), Config.COMBO_MAX)
	elif grade == RhythmEvaluator.Grade.GOOD:
		good_count += 1
		combo = mini(combo + int(Config.COMBO_GAIN["GOOD"]), Config.COMBO_MAX)
	else:
		miss_count += 1
		combo = Config.COMBO_MIN
	max_combo = maxi(max_combo, combo)
	combo_changed.emit(combo)


## Emits one short contextual line. `kind` is one of info | success | danger | rhythm.
func emit_feedback(text: String, kind: StringName = &"info") -> void:
	if is_ended:
		return
	feedback_count += 1
	feedback.emit(text, kind)


func add_score(points: int) -> void:
	if is_ended:
		return
	score = maxi(score + points, 0)
	score_changed.emit(score)


func set_phase(idx: int) -> void:
	var clamped := clampi(idx, 0, Config.PHASE_BPM.size() - 1)
	if clamped == phase_index:
		return
	phase_index = clamped
	phase_changed.emit(phase_index)


func accuracy() -> float:
	if rhythm_actions <= 0:
		return 0.0
	return float(perfect_count + good_count) / float(rhythm_actions)


func end_shift(victory: bool, reason: String) -> void:
	if is_ended:
		return
	is_ended = true
	_end_result = {
		"victory": victory,
		"reason": reason,
		"score": score,
		"stability": stability,
		"accuracy": accuracy(),
		"perfect": perfect_count,
		"good": good_count,
		"miss": miss_count,
		"max_combo": max_combo,
		"delivered": delivered_count,
		"washed": washed_count,
		"exploded": exploded_count,
		"wrong_washer": wrong_washer_count,
		"final_load_delivered": final_load_delivered,
		"seed": seed_value,
	}
	shift_ended.emit(_end_result)


func get_end_result() -> Dictionary:
	return _end_result.duplicate(true)

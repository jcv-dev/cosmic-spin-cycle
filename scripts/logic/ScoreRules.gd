class_name ScoreRules
extends RefCounted
## Delivery scoring, rank and end-screen summary (GDD §4.3, AGENTS §A6 #13).
##
## Pure static rules: no nodes, no clock, no autoload state. The caller passes the numbers.
## Rank thresholds are inclusive at the boundary and a defeat is always `C`.

## Reference combo used by [method max_possible_score].
##
## The ladder runs x1..x8 and the combo only ever grows on PERFECT/GOOD throws, so x4
## (the middle of the ladder) is the documented "competent player" assumption. Changing it
## rescales the ratio, never the delivered points.
const REFERENCE_COMBO := 4

const RANK_S := "S"
const RANK_A := "A"
const RANK_B := "B"
const RANK_C := "C"


## Points paid by the chute for an item worth `item_points` at `combo`
## (`score += item.points * combo_multiplier`, AGENTS §A6 #13).
static func delivery_points(item_points: int, combo: int) -> int:
	return maxi(item_points, 0) * clampi(combo, Config.COMBO_MIN, Config.COMBO_MAX)


## Stability paid by the chute, scaled by combo. The base is the GDD's +3; a sustained combo
## is worth more because it is the only reward that keeps the shift alive, not just the score.
static func combo_stability_bonus(combo: int) -> float:
	var level := clampi(combo, Config.COMBO_MIN, Config.COMBO_MAX)
	if level >= Config.COMBO_MAX:
		return 2.0
	if level >= 4:
		return 1.0
	return 0.0


static func delivery_stability(combo: int) -> float:
	return Config.STABILITY_CHUTE_DELIVERY + combo_stability_bonus(combo)


## Letter rank from the score ratio and rhythm accuracy (AGENTS §A6 #13).
##
## `S` needs ratio >= 0.85 **and** accuracy >= 0.90; `A` >= 0.65; `B` >= 0.40; else `C`.
## A defeat is always `C`, whatever the numbers say.
static func rank(score_ratio: float, accuracy: float, victory: bool) -> String:
	if not victory:
		return RANK_C
	if score_ratio >= Config.RANK_S_THRESHOLD and accuracy >= Config.RANK_S_ACCURACY:
		return RANK_S
	if score_ratio >= Config.RANK_A_THRESHOLD:
		return RANK_A
	if score_ratio >= Config.RANK_B_THRESHOLD:
		return RANK_B
	return RANK_C


## Rank colour from the UX bible §12.5 (S magenta, A cyan, B steel, C dim steel).
static func rank_color(rank_letter: String) -> Color:
	match rank_letter:
		RANK_S:
			return Palette.FUNK_MAGENTA
		RANK_A:
			return Palette.FUNK_CYAN
		RANK_B:
			return Palette.METAL_3
		_:
			return Palette.METAL_1


## `{item_id: points}` from the shipped item database; empty when it is unavailable.
static func points_by_id() -> Dictionary:
	var out := {}
	var database := ItemDatabase.load_default()
	if database == null:
		return out
	for item in database.items:
		if item != null:
			out[item.id] = item.points
	return out


## Upper bound on deliverable points for a spawn schedule.
##
## Assumes **every** scheduled item is delivered clean at [constant REFERENCE_COMBO]; the
## resulting ratio is therefore conservative (a perfect player still cannot exceed 1.0).
## `points` lets tests inject the table instead of loading `data/items.tres`.
static func max_possible_score(
	events: Array[Dictionary], reference_combo: int = REFERENCE_COMBO, points: Dictionary = {}
) -> int:
	var table := points if not points.is_empty() else points_by_id()
	var total := 0
	for event in events:
		var item_id := StringName(str(event.get("item_id", &"")))
		total += int(table.get(item_id, 0))
	return total * clampi(reference_combo, Config.COMBO_MIN, Config.COMBO_MAX)


## End-screen payload derived from a [GameState] result dictionary.
##
## `max_possible` is the value from [method max_possible_score]; pass 0 when the caller
## already stored `score_ratio` in `result`. The returned keys are the ones the end screen
## renders (washed, delivered, accuracy, max combo, score, rank, seed, explosions).
static func summary(result: Dictionary, max_possible: int = 0) -> Dictionary:
	var victory := bool(result.get("victory", false))
	var score := int(result.get("score", 0))
	var accuracy := float(result.get("accuracy", 0.0))
	var ratio := 0.0
	if max_possible > 0:
		ratio = clampf(float(score) / float(max_possible), 0.0, 1.0)
	else:
		ratio = clampf(float(result.get("score_ratio", 0.0)), 0.0, 1.0)
	return {
		"victory": victory,
		"reason": str(result.get("reason", "")),
		"washed": int(result.get("washed", 0)),
		"delivered": int(result.get("delivered", 0)),
		"accuracy": accuracy,
		"max_combo": int(result.get("max_combo", Config.COMBO_MIN)),
		"score": score,
		"score_ratio": ratio,
		"rank": rank(ratio, accuracy, victory),
		"seed": int(result.get("seed", 0)),
		"exploded": int(result.get("exploded", 0)),
		"stability": float(result.get("stability", 0.0)),
		"final_delivered": int(result.get("final_delivered", 0)),
	}

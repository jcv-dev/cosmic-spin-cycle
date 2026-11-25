class_name ShiftRules
extends RefCounted
## Win/lose evaluation for an 8-minute shift (GDD §2.3/§2.4, AGENTS §A6 #11).
##
## Pure static rules: the node passes the clock, stability and delivery counters; nothing
## reads an autoload or a scene.
##
## **Documented override (AGENTS §A6 #11):** the brief for M4/M5 drops the Final Load count
## as a victory gate. A shift ends in victory at `t >= SHIFT_DURATION_S` when stability is
## above zero, whatever `final_delivered` is. The Final Load numbers stay in the result so
## the end screen can still show them.

const REASON_ONGOING := ""
const REASON_STABILITY := "stability"
const REASON_TIME := "time"

const ENDED := "ended"
const VICTORY := "victory"
const REASON := "reason"


## `{ended, victory, reason, time, stability, delivered, final_delivered}`.
##
## Defeat wins over victory when both conditions hold on the same tick: reaching zero
## stability at 480.0 s is a loss.
static func evaluate(
	t: float, stability: float, delivered: int, final_delivered: int
) -> Dictionary:
	var ended := false
	var victory := false
	var reason := REASON_ONGOING
	if stability <= 0.0:
		ended = true
		reason = REASON_STABILITY
	elif t >= Config.SHIFT_DURATION_S:
		ended = true
		victory = true
		reason = REASON_TIME
	return {
		ENDED: ended,
		VICTORY: victory,
		REASON: reason,
		"time": t,
		"stability": stability,
		"delivered": delivered,
		"final_delivered": final_delivered,
	}


## Fraction of the shift elapsed, clamped to 0..1 (HUD/end-screen helper).
static func shift_progress(t: float) -> float:
	if Config.SHIFT_DURATION_S <= 0.0:
		return 1.0
	return clampf(t / Config.SHIFT_DURATION_S, 0.0, 1.0)


## Spanish end-screen verdict word for a result (UX bible §12.5).
static func verdict_text(victory: bool) -> String:
	return "TURNO COMPLETADO" if victory else "DESGARRO UNIVERSAL"

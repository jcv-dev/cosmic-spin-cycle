class_name BeltReversal
extends RefCounted
## Phase-3 reversal schedule for the conveyor belts (GDD §5.3, §A6 #12).
##
## Pure logic: no scene, no clock and no signals. `ConveyorBelt` calls [method on_beat] from
## the beat clock and flips its flow when the verdict says `flip`; a `warn` verdict four
## beats earlier gives the player the visual/audio heads-up.
##
## Only phase index [constant ACTIVE_PHASE] (the GDD's "phase 3") reverses. Every
## [constant Config.BELT_REVERSE_EVERY_MEASURES] measures the belts flip direction, and
## [constant Config.BELT_REVERSE_WARNING_BEATS] beats before that flip the schedule warns,
## so the first warning lands on beat
## `16 * 4 - 4 = 60` and the first flip on beat `64` (130 BPM, phase 3).

## Zero-based phase index of the GDD's phase 3 ("Centrifugado Turbulento").
const ACTIVE_PHASE := 2

## True once the belts have flipped an odd number of times.
var is_reversed := false

var _last_beat := -1
var _last_result: Dictionary = {}


## Empty verdict, used when the schedule is inactive or the input is out of range.
static func idle_result() -> Dictionary:
	return {"warn": false, "flip": false, "beats_left": 0}


## Beats between two flips: `BELT_REVERSE_EVERY_MEASURES` measures of 4/4.
static func beats_per_flip() -> int:
	return Config.BELT_REVERSE_EVERY_MEASURES * Config.BEATS_PER_MEASURE


## Beats of warning before a flip.
static func warning_beats() -> int:
	return Config.BELT_REVERSE_WARNING_BEATS


## True when `phase` (zero-based) is the only phase that reverses belts.
static func is_active_phase(phase: int) -> bool:
	return phase == ACTIVE_PHASE


## Goes back to the default direction and forgets the last beat.
func reset() -> void:
	is_reversed = false
	_last_beat = -1
	_last_result = {}


## Reversal verdict for one beat.
##
## `beat` is the global beat index, `measure` the 4/4 measure index and `phase` the
## zero-based phase index; all three come from `BeatConductor`. Returns
## `{ "warn": bool, "flip": bool, "beats_left": int }`. `beats_left` counts the beats until
## the next flip and is 0 when the schedule is inactive, so a caller can drive a chevron
## animation without extra maths.
func on_beat(beat: int, measure: int, phase: int) -> Dictionary:
	if not is_active_phase(phase) or beat < 0 or measure < 0:
		return idle_result()
	if beat == _last_beat:
		return idle_result()

	var beat_in_measure := beat % Config.BEATS_PER_MEASURE
	var measures_left := (
		Config.BELT_REVERSE_EVERY_MEASURES - measure % Config.BELT_REVERSE_EVERY_MEASURES
	)
	var result := {
		"warn": false,
		"flip": false,
		"beats_left": measures_left * Config.BEATS_PER_MEASURE - beat_in_measure,
	}
	if measure > 0 and beat_in_measure == 0 and measure % Config.BELT_REVERSE_EVERY_MEASURES == 0:
		is_reversed = not is_reversed
		result.flip = true
		result.beats_left = beats_per_flip()
	elif result.beats_left == warning_beats():
		result.warn = true
	_last_beat = beat
	_last_result = result.duplicate()
	return result


## Measure-based convenience wrapper (CONTRACTS §4); equivalent to
## `on_beat(measure * 4, measure, phase)`.
func on_measure(measure: int, phase: int) -> Dictionary:
	return on_beat(measure * Config.BEATS_PER_MEASURE, measure, phase)


## Beats until the next flip for a given measure, clamped to one flip interval.
static func beats_until_flip(measure: int) -> int:
	var mod := measure % Config.BELT_REVERSE_EVERY_MEASURES
	return (Config.BELT_REVERSE_EVERY_MEASURES - mod) * Config.BEATS_PER_MEASURE


## Human-readable direction after `flips` flips: +1 forward, -1 reversed.
static func direction_sign_after(flips: int) -> int:
	return -1 if flips % 2 == 1 else 1

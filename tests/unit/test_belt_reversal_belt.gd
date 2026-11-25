extends GutTest
## Belt-level reversal wiring (GDD §5.3): the belt forwards beats to the pure schedule,
## announces the warning and only then flips its own flow.

const SCENE_PATH := "res://scenes/environment/ConveyorBelt.tscn"

var belt: ConveyorBelt


func before_each() -> void:
	belt = load(SCENE_PATH).instantiate() as ConveyorBelt
	assert_not_null(belt, "ConveyorBelt.tscn must exist")
	add_child_autofree(belt)


# --- reversal ---------------------------------------------------------------


func test_flip_reverses_flow_and_emits() -> void:
	watch_signals(belt)
	var verdict := belt.on_beat(64, 16, BeltReversal.ACTIVE_PHASE)
	assert_true(verdict.flip)
	assert_eq(belt.flow_direction, Vector2.LEFT, "flow flipped")
	assert_signal_emitted(belt, "reversed")
	assert_signal_emitted_with_parameters(belt, "reversed", [Vector2.LEFT])


func test_warning_precedes_the_flip() -> void:
	watch_signals(belt)
	var verdict := belt.on_beat(60, 15, BeltReversal.ACTIVE_PHASE)
	assert_true(verdict.warn)
	assert_true(belt.is_warning_active())
	assert_eq(belt.warning_beats_left(), Config.BELT_REVERSE_WARNING_BEATS)
	assert_signal_emitted_with_parameters(belt, "reverse_warning", [4])
	assert_eq(belt.flow_direction, Vector2.RIGHT, "a warning does not move the belt yet")


func test_flip_clears_the_warning() -> void:
	belt.on_beat(60, 15, BeltReversal.ACTIVE_PHASE)
	assert_true(belt.is_warning_active())
	belt.on_beat(64, 16, BeltReversal.ACTIVE_PHASE)
	assert_false(belt.is_warning_active(), "the flip consumes the warning")


func test_no_reversal_outside_phase_three() -> void:
	watch_signals(belt)
	for phase: int in [0, 1, 3]:
		belt.on_beat(64, 16, phase)
	assert_eq(belt.flow_direction, Vector2.RIGHT, "only phase 3 reverses")
	assert_signal_not_emitted(belt, "reversed")
	assert_signal_not_emitted(belt, "reverse_warning")

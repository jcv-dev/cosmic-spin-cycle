# gdlint: disable=max-public-methods
extends GutTest
## Pure gating logic for the seven-gate tutorial (docs/UX_BIBLE.md §16.1).

const STEPS := preload("res://scripts/tutorial/TutorialSteps.gd")
const GOOD := RhythmEvaluator.Grade.GOOD
const PERFECT := RhythmEvaluator.Grade.PERFECT
const MISS := RhythmEvaluator.Grade.MISS


func _advance(state: Dictionary, event: Dictionary) -> Dictionary:
	return STEPS.advance(state, event)


func _tick(state: Dictionary, seconds: float) -> Dictionary:
	return STEPS.advance(state, {"kind": &"tick", "delta": seconds})


func _travel(state: Dictionary, delta: float) -> Dictionary:
	return STEPS.advance(state, {"kind": &"travel", "delta": delta})


func _state_at(id: StringName) -> Dictionary:
	return STEPS.new_state(STEPS.step_index_of(id))


# --- Table ------------------------------------------------------------------


func test_table_has_seven_gates_in_the_binding_order() -> void:
	var steps := STEPS.steps()
	assert_eq(steps.size(), STEPS.STEP_COUNT)
	assert_eq(steps.size(), 7)
	var ids: Array[StringName] = []
	for entry in steps:
		ids.append(StringName(entry["id"]))
	assert_eq(ids[0], &"move")
	assert_eq(ids[1], &"grab")
	assert_eq(ids[2], &"throw")
	assert_eq(ids[3], &"beat")
	assert_eq(ids[4], &"match")
	assert_eq(ids[5], &"strike")
	assert_eq(ids[6], &"deliver")


func test_titles_match_the_frozen_copy() -> void:
	assert_eq(STEPS.title_for(0), "MUÉVETE AL PLANETA")
	assert_eq(STEPS.title_for(1), "AGARRA EL PLANETA")
	assert_eq(STEPS.title_for(2), "LANZA A LA LAVADORA")
	assert_eq(STEPS.title_for(3), "LANZA A TIEMPO")
	assert_eq(STEPS.title_for(4), "LAVADORA ROJA")
	assert_eq(STEPS.title_for(5), "LAVADORA AGITADA")
	assert_eq(STEPS.title_for(6), "ENTREGA EN LA TAPA")


func test_every_prompt_fits_the_world_chip() -> void:
	for index in range(STEPS.STEP_COUNT):
		var prompt := STEPS.prompt_for(index)
		assert_lte(prompt.length(), 34, "prompt %d is wider than 34 chars" % index)
		assert_lte(
			prompt.split(" ", false).size(),
			int(STEPS.step(index)["max_words"]),
			"prompt %d is wordier than its budget" % index
		)
		assert_false(prompt.ends_with("!"), "no shouting in tutorial copy")


func test_chip_text_reads_step_n_of_seven() -> void:
	assert_eq(STEPS.chip_text(0), "PASO 1/7 · MUÉVETE AL PLANETA")
	assert_eq(STEPS.chip_text(1), "PASO 2/7 · AGARRA EL PLANETA")
	assert_eq(STEPS.chip_text(6), "PASO 7/7 · ENTREGA EN LA TAPA")


func test_out_of_range_index_is_clamped() -> void:
	assert_eq(STEPS.clamp_index(-4), 0)
	assert_eq(STEPS.clamp_index(99), STEPS.STEP_COUNT - 1)
	assert_eq(StringName(STEPS.step(99)["id"]), &"deliver")


# --- Gate 1: travel ---------------------------------------------------------


func test_travel_gate_needs_two_hundred_pixels() -> void:
	var state := _state_at(&"move")
	_travel(state, 199.0)
	assert_false(state["granted"])
	assert_almost_eq(STEPS.progress(state), 199.0 / 200.0, 0.001)
	_travel(state, 1.0)
	assert_true(state["granted"])
	assert_eq(STEPS.progress(state), 1.0)


func test_travel_accumulates_only_while_its_gate_is_active() -> void:
	var beat := _state_at(&"beat")
	_travel(beat, 500.0)
	assert_eq(beat["travel"], 0.0)
	assert_false(beat["granted"])


func test_travel_hint_appears_after_four_seconds() -> void:
	var state := _state_at(&"move")
	_tick(state, 3.9)
	assert_false(state["hint"])
	_tick(state, 0.2)
	assert_true(state["hint"])
	assert_eq(STEPS.TRAVEL_HINT_RADIUS_PX, 120.0)


# --- Gate 2/3: grab and throw ----------------------------------------------


func test_one_grab_grants_the_grab_gate() -> void:
	var state := _state_at(&"grab")
	_advance(state, {"kind": &"grab"})
	assert_true(state["granted"])


func test_throw_gate_needs_the_item_to_leave_the_hold() -> void:
	var state := _state_at(&"throw")
	_advance(state, {"kind": &"throw", "left_hold": false})
	assert_false(state["granted"])
	_advance(state, {"kind": &"throw", "left_hold": true})
	assert_true(state["granted"])


# --- Gate 4: two throws at GOOD --------------------------------------------


func test_beat_gate_counts_two_throws_at_good_or_better() -> void:
	var state := _state_at(&"beat")
	var scale := float(state["window_scale"])
	assert_almost_eq(scale, 2.0, 0.001)
	_advance(state, {"kind": &"throw", "delta_t": 0.0})
	assert_eq(state["count"], 1)
	assert_false(state["granted"])
	_advance(state, {"kind": &"throw", "delta_t": 0.0})
	assert_eq(state["count"], 2)
	assert_true(state["granted"])


func test_beat_gate_accepts_good_inside_the_tutorial_window() -> void:
	var state := _state_at(&"beat")
	assert_eq(STEPS.grade_throw(0.2, 0), GOOD)
	assert_eq(STEPS.grade_throw(0.35, 0), MISS)
	_advance(state, {"kind": &"throw", "delta_t": 0.2})
	assert_eq(state["count"], 1)


func test_two_misses_widen_the_window_then_three_grant() -> void:
	var state := _state_at(&"beat")
	_advance(state, {"kind": &"throw", "delta_t": 0.9})
	assert_eq(state["misses"], 1)
	assert_almost_eq(float(state["window_scale"]), 2.0, 0.001)
	_advance(state, {"kind": &"throw", "delta_t": 0.9})
	assert_eq(state["misses"], 2)
	assert_almost_eq(float(state["window_scale"]), 3.0, 0.01)
	assert_false(state["granted"])
	_advance(state, {"kind": &"throw", "delta_t": 0.9})
	assert_true(state["granted"])
	assert_eq(state["feedback"], &"granted_after_misses")


func test_widened_window_still_honours_the_195ms_floor() -> void:
	assert_gte(STEPS.good_window_s(0), STEPS.BEAT_WIDE_WINDOW_S)
	assert_gte(STEPS.good_window_s(2), STEPS.good_window_s(0))


# --- Gate 5: only the compatible washer ------------------------------------


func test_wrong_washer_never_grants_and_never_penalises() -> void:
	var state := _state_at(&"match")
	_advance(state, {"kind": &"insert", "correct": false})
	assert_false(state["granted"])
	assert_eq(state["rejected"], 1)
	assert_eq(state["feedback"], &"wrong_mouth")
	assert_eq(GameState.stability, Config.STABILITY_START)


func test_correct_insert_grants_the_match_gate() -> void:
	var state := _state_at(&"match")
	_advance(state, {"kind": &"insert", "correct": true})
	assert_true(state["granted"])


# --- Gate 6: 3 s interact hold ---------------------------------------------


func test_interact_gate_grants_when_the_hold_resolves() -> void:
	var state := _state_at(&"strike")
	_advance(state, {"kind": &"interact"})
	assert_true(state["granted"])


func test_interact_gate_ignores_throwing() -> void:
	var state := _state_at(&"strike")
	_advance(state, {"kind": &"throw", "delta_t": 0.0})
	assert_false(state["granted"], "throwing never calms a washer")


# --- Gate 7: clean delivery -------------------------------------------------


func test_dirty_delivery_does_not_count() -> void:
	var state := _state_at(&"deliver")
	_advance(state, {"kind": &"deliver", "clean": false})
	assert_false(state["granted"])
	assert_eq(state["feedback"], &"dirty")


func test_clean_delivery_grants_the_final_gate() -> void:
	var state := _state_at(&"deliver")
	_advance(state, {"kind": &"deliver", "clean": true})
	assert_true(state["granted"])
	assert_eq(state["feedback"], &"delivered")


# --- Soft skip, ticks and immutability -------------------------------------


func test_tab_soft_skip_grants_the_current_gate() -> void:
	var state := _state_at(&"strike")
	_tick(state, 1.0)
	assert_false(state["soft_skip_ready"])
	_advance(state, {"kind": &"skip"})
	assert_true(state["granted"])
	assert_eq(state["feedback"], &"skipped")


func test_soft_skip_becomes_ready_after_the_stuck_grace() -> void:
	var state := _state_at(&"grab")
	_tick(state, Config.TUTORIAL_SOFT_SKIP_S - 0.1)
	assert_false(state["soft_skip_ready"])
	_tick(state, 0.2)
	assert_true(state["soft_skip_ready"])


func test_a_granted_gate_ignores_later_events() -> void:
	var state := _state_at(&"grab")
	_advance(state, {"kind": &"grab"})
	_advance(state, {"kind": &"travel", "delta": 10.0})
	assert_eq(state["travel"], 0.0)
	assert_true(state["granted"])


func test_the_worst_case_run_fits_the_four_minute_cap() -> void:
	# Every gate can be escaped after the stuck grace, so the run can never exceed this.
	var worst := float(STEPS.STEP_COUNT) * Config.TUTORIAL_SOFT_SKIP_S
	assert_lte(worst, Config.TUTORIAL_MAX_S, "7 soft-skips must fit inside the 240 s cap")


func test_new_state_starts_clean_at_every_gate() -> void:
	for index in range(STEPS.STEP_COUNT):
		var state := STEPS.new_state(index)
		assert_eq(int(state["index"]), index)
		assert_false(state["granted"])
		assert_false(state["hint"])
		assert_eq(float(state["elapsed"]), 0.0)
		assert_eq(int(state["count"]), 0)
		assert_eq(int(state["misses"]), 0)

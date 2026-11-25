extends GutTest
## WasherFSM: table-driven coverage of every transition and every AGENTS §A6 default.
##
## gdlint caps a class at 20 public methods, so the coverage is grouped into a handful of
## tables instead of one function per assertion. Each row carries its own failure label.

const T_105 := 60.0 / 105.0
const T_142 := 60.0 / 142.0
const T_60 := 1.0

var fsm: WasherFSM


func before_each() -> void:
	fsm = _new_fsm(&"red", 0)


func _new_fsm(requirement: StringName, phase: int) -> WasherFSM:
	var created := WasherFSM.new()
	created.set_requirement(requirement)
	created.set_phase(phase)
	created.set_beat_seconds(T_105)
	return created


func _item(
	id: StringName = &"rocky",
	wash: float = 6.0,
	slots: int = 1,
	color: StringName = &"red",
	pattern: StringName = &"solid"
) -> Dictionary:
	return {
		"id": id,
		"wash_s": wash,
		"slots": slots,
		"color": color,
		"pattern": pattern,
	}


func _types(events: Array[Dictionary]) -> Array:
	var out := []
	for event in events:
		out.append(StringName(str(event.get("type", &""))))
	return out


func _has_type(events: Array[Dictionary], type: StringName) -> bool:
	return _types(events).has(type)


func _fill(machine: WasherFSM, requirement: StringName = &"red", count: int = 3) -> void:
	for _i in range(count):
		machine.insert(_item(&"rocky", 6.0, 1, requirement, &"solid"))


## Runs one cycle to completion and clears the drum (used by the phase-3 rule tests).
func _complete_cycle(machine: WasherFSM) -> void:
	machine.insert(_item(&"rocky", 6.0))
	machine.start_cycle()
	machine.force_finish()
	machine.tick(WasherFSM.DONE_SETTLE_S + 0.01)
	machine.collect()


# --- loading, capacity, compatibility ---------------------------------------


func test_identity_and_loading_table() -> void:
	assert_eq(fsm.get_state(), WasherFSM.State.IDLE)
	assert_eq(fsm.slots_used, 0)
	assert_eq(fsm.get_progress(), 0.0)
	assert_eq(fsm.last_reject, WasherFSM.REJECT_NONE)

	var cases := [
		[_item(&"rocky", 6.0, 1, &"red", &"solid"), true, WasherFSM.REJECT_NONE, "match"],
		[_item(&"sock", 4.0, 1, &"blue", &"solid"), false, WasherFSM.REJECT_INCOMPATIBLE, "colour"],
		[
			_item(&"moon", 7.0, 1, &"blue", &"spotted"),
			false,
			WasherFSM.REJECT_INCOMPATIBLE,
			"pattern"
		],
	]
	for row: Array in cases:
		var machine := _new_fsm(&"red", 0)
		var accepted := machine.insert(row[0])
		assert_eq(accepted, row[1], "insert case %s" % row[3])
		assert_eq(machine.last_reject, row[2], "reject case %s" % row[3])


func test_capacity_and_slots_table() -> void:
	_fill(fsm)
	assert_eq(fsm.get_state(), WasherFSM.State.WASHING, "a full drum starts the cycle")
	assert_eq(fsm.slots_used, 3)
	assert_false(fsm.insert(_item()), "a fourth item cannot enter")
	assert_eq(fsm.last_reject, WasherFSM.REJECT_FULL)
	assert_eq(fsm.get_loaded_items().size(), 3, "the rejected item is not kept")

	var heavy := _new_fsm(&"red", 0)
	assert_true(heavy.insert(_item(&"gas_giant", 10.0, 2)))
	assert_eq(heavy.slots_used, 2)
	assert_true(heavy.insert(_item(&"rocky", 6.0, 1)))
	assert_eq(heavy.get_state(), WasherFSM.State.WASHING)

	var wild := _new_fsm(&"spotted", 0)
	assert_true(wild.insert(_item(&"galaxy_core", 12.0, 3, &"", &"")), "core fits any washer")
	assert_eq(wild.slots_used, WasherFSM.CAPACITY, "a wildcard takes the whole drum")
	assert_eq(wild.get_state(), WasherFSM.State.WASHING)

	var guarded := _new_fsm(&"red", 0)
	guarded.insert(_item())
	assert_false(guarded.insert(_item(&"galaxy_core", 12.0, 3, &"", &"")), "core needs empty")
	assert_eq(guarded.last_reject, WasherFSM.REJECT_WILDCARD_NEEDS_EMPTY)


func test_locking_mid_cycle_keeps_the_load_but_rejects_new_work() -> void:
	var machine := _new_fsm(&"red", 0)
	machine.insert(_item(&"rocky", 8.0))
	machine.start_cycle()
	machine.set_locked(true)
	assert_eq(machine.get_state(), WasherFSM.State.WASHING, "the current load finishes")
	assert_false(machine.insert(_item(&"sock", 4.0)), "no new work is accepted")
	assert_eq(machine.last_reject, WasherFSM.REJECT_LOCKED)
	machine.tick(8.1)
	assert_eq(machine.get_state(), WasherFSM.State.DONE, "the wash still completes")


func test_requirement_lock_and_busy_table() -> void:
	var spot := _new_fsm(&"spotted", 0)
	assert_true(spot.insert(_item(&"rocky", 6.0, 1, &"blue", &"spotted")))
	assert_false(spot.insert(_item(&"sock", 4.0, 1, &"red", &"solid")))

	var wildcard := _new_fsm(&"", 0)
	assert_eq(wildcard.get_requirement(), &"wild", "an empty requirement means wild")
	assert_true(wildcard.insert(_item(&"sock", 4.0, 1, &"blue", &"spotted")))

	var locked := _new_fsm(&"red", 0)
	locked.set_locked(true)
	assert_false(locked.insert(_item()))
	assert_eq(locked.last_reject, WasherFSM.REJECT_LOCKED)

	var done := _new_fsm(&"red", 0)
	_fill(done)
	done.force_finish()
	assert_false(done.insert(_item()))
	assert_eq(done.last_reject, WasherFSM.REJECT_BUSY, "DONE is busy")
	done.explode()
	assert_false(done.insert(_item()))
	assert_eq(done.last_reject, WasherFSM.REJECT_BUSY, "BROKEN is busy")

	var changing := _new_fsm(&"red", 0)
	assert_true(changing.insert(_item(&"rocky", 6.0, 1, &"red", &"solid")))
	changing.set_requirement(&"blue")
	assert_false(changing.insert(_item(&"sock", 4.0, 1, &"red", &"solid")))
	assert_eq(changing.last_reject, WasherFSM.REJECT_INCOMPATIBLE)


# --- cycle timing -----------------------------------------------------------


func test_cycle_time_table() -> void:
	fsm.insert(_item(&"rocky", 6.0))
	fsm.insert(_item(&"sock", 4.0))
	fsm.insert(_item(&"moon", 7.0))
	assert_eq(fsm.cycle_time, 7.0, "the longest wash wins")
	assert_almost_eq(fsm.remaining, 7.0, 0.001)

	var floored := _new_fsm(&"red", 0)
	assert_true(floored.insert(_item(&"rocky", 0.4)))
	floored.start_cycle()
	assert_eq(floored.cycle_time, Config.MIN_WASH_TIME_S, "two-second floor")

	var empty := _new_fsm(&"red", 0)
	assert_true(empty.start_cycle())
	assert_eq(empty.cycle_time, Config.WASH_BASE_S, "base time only for an empty start")
	assert_eq(empty.get_state(), WasherFSM.State.WASHING)


func test_reduction_table() -> void:
	var stored := _new_fsm(&"red", 0)
	stored.insert(_item(&"rocky", 8.0), {}, RhythmEvaluator.Grade.PERFECT)
	assert_eq(stored.get_state(), WasherFSM.State.IDLE, "one item does not start yet")
	stored.start_cycle()
	assert_almost_eq(stored.remaining, 5.0, 0.001, "8 s - 3 s, applied once at start")

	var starts := _new_fsm(&"red", 0)
	starts.insert(_item(&"rocky", 6.0))
	starts.insert(_item(&"sock", 4.0))
	starts.insert(_item(&"moon", 6.5), {}, RhythmEvaluator.Grade.GOOD)
	assert_eq(starts.get_state(), WasherFSM.State.WASHING)
	assert_almost_eq(starts.remaining, 5.5, 0.001, "the starting insert's GOOD applies")

	var per_throw := _new_fsm(&"red", 0)
	per_throw.insert(_item(&"rocky", 8.0))
	per_throw.start_cycle()
	per_throw.insert(_item(&"moon", 7.0), {}, RhythmEvaluator.Grade.PERFECT)
	assert_almost_eq(per_throw.remaining, 5.0, 0.001)
	per_throw.insert(_item(&"sock", 4.0), {}, RhythmEvaluator.Grade.PERFECT)
	assert_almost_eq(per_throw.remaining, 2.0, 0.001, "clamped at the 2 s floor")
	per_throw.tick(0.1)
	assert_almost_eq(per_throw.remaining, 1.9, 0.001, "time keeps running after the clamp")

	var sub_floor := _new_fsm(&"red", 0)
	sub_floor.insert(_item(&"rocky", 1.0))
	sub_floor.start_cycle()
	assert_almost_eq(sub_floor.remaining, 2.0, 0.001)
	sub_floor.tick(1.0)
	sub_floor.insert(_item(&"sock", 4.0), {}, RhythmEvaluator.Grade.PERFECT)
	assert_almost_eq(sub_floor.remaining, 1.0, 0.001, "a reduction never gives time back")

	var missed := _new_fsm(&"red", 0)
	missed.insert(_item(&"rocky", 8.0), {}, RhythmEvaluator.Grade.MISS)
	missed.start_cycle()
	assert_almost_eq(missed.remaining, 8.0, 0.001, "MISS does not reduce")
	assert_almost_eq(missed.turbulence, Config.MISS_TURBULENCE_GAIN, 0.001)


# --- progress, done and collection -----------------------------------------


func test_progress_completion_and_settle_table() -> void:
	var machine := _new_fsm(&"red", 0)
	machine.insert(_item(&"rocky", 2.0))
	machine.start_cycle()
	var early := machine.tick(1.0)
	assert_true(_has_type(early, &"progress"), "progress is reported every tick")
	assert_almost_eq(machine.get_progress(), 0.5, 0.001)
	assert_eq(machine.get_state(), WasherFSM.State.WASHING)

	var late := machine.tick(1.2)
	assert_true(_has_type(late, &"cycle_done"))
	assert_eq(machine.get_state(), WasherFSM.State.DONE)
	assert_almost_eq(machine.get_progress(), 1.0, 0.001)
	assert_false(machine.can_collect(), "the DONE animation has to settle")
	assert_eq(machine.collect().size(), 0)
	machine.tick(WasherFSM.DONE_SETTLE_S + 0.01)
	assert_true(machine.can_collect())
	assert_eq(machine.collect().size(), 1)
	assert_eq(machine.get_state(), WasherFSM.State.IDLE)
	assert_eq(machine.slots_used, 0)

	var two := _new_fsm(&"red", 0)
	two.insert(_item(&"rocky", 2.0))
	two.insert(_item(&"sock", 2.0))
	two.start_cycle()
	var payload: Array = []
	for event in two.tick(2.1):
		if StringName(str(event.get("type"))) == &"cycle_done":
			payload = event["items"]
	assert_eq(payload.size(), 2, "cycle_done carries the load")

	var forced := _new_fsm(&"red", 0)
	assert_false(forced.force_finish(), "idle cannot finish")
	forced.insert(_item(&"rocky", 8.0))
	forced.start_cycle()
	assert_true(forced.force_finish())
	assert_eq(forced.get_state(), WasherFSM.State.DONE)


# --- turbulence -------------------------------------------------------------


func test_auto_turbulence_phase_rule_table() -> void:
	var phase_three := _new_fsm(&"red", 2)
	_complete_cycle(phase_three)
	_complete_cycle(phase_three)
	phase_three.insert(_item(&"rocky", 6.0))
	phase_three.start_cycle()
	assert_eq(phase_three.cycle_count, 3)
	var events := phase_three.tick(3.05)
	assert_true(_has_type(events, &"turbulent"), "cycle 3 goes turbulent at 50 %")
	assert_eq(phase_three.get_state(), WasherFSM.State.TURBULENT)

	for phase in range(2):
		var calm := _new_fsm(&"red", phase)
		_complete_cycle(calm)
		_complete_cycle(calm)
		calm.insert(_item(&"rocky", 6.0))
		calm.start_cycle()
		var calm_events := calm.tick(3.05)
		assert_false(_has_type(calm_events, &"turbulent"), "phase %d stays calm" % phase)


func test_turbulence_accumulation_table() -> void:
	fsm.insert(_item(&"rocky", 6.0))
	fsm.start_cycle()
	assert_false(fsm.add_turbulence(0.5))
	assert_almost_eq(fsm.turbulence, 0.5, 0.001)
	assert_false(_has_type(fsm.tick(0.0), &"turbulent"))
	assert_true(fsm.add_turbulence(0.5))
	assert_eq(fsm.get_state(), WasherFSM.State.TURBULENT)

	var missed := _new_fsm(&"red", 0)
	missed.insert(_item(&"rocky", 6.0))
	missed.start_cycle()
	missed.add_turbulence(0.9)
	missed.insert(_item(&"sock", 4.0), {}, RhythmEvaluator.Grade.MISS)
	assert_eq(missed.get_state(), WasherFSM.State.TURBULENT, "a MISS can tip it")


func test_turbulence_limits_table() -> void:
	fsm.set_beat_seconds(T_105)
	_fill(fsm)
	assert_almost_eq(fsm._turbulence_limit(), 8.0 * T_105, 0.001, "8 beats at 105 BPM")
	assert_true(fsm._turbulence_limit() < Config.TURBULENCE_TIMEOUT_S)

	fsm.set_beat_seconds(T_142)
	assert_almost_eq(fsm._turbulence_limit(), 8.0 * T_142, 0.001, "8 beats at 142 BPM")

	fsm.set_beat_seconds(T_60)
	assert_almost_eq(fsm._turbulence_limit(), Config.TURBULENCE_TIMEOUT_S, 0.001, "5 s cap")


func test_turbulence_timeout_and_forced_table() -> void:
	var timed := _new_fsm(&"red", 0)
	timed.insert(_item(&"rocky", 6.0))
	assert_true(timed.force_turbulent())
	assert_eq(timed.get_state(), WasherFSM.State.TURBULENT)
	assert_almost_eq(timed.get_progress(), Config.TURBULENCE_AT_PROGRESS, 0.01)
	assert_eq(timed.turbulence, 1.0)
	var limit := timed._turbulence_limit()
	timed.tick(limit - 0.01)
	assert_eq(timed.get_state(), WasherFSM.State.TURBULENT, "not yet")
	var events := timed.tick(0.02)
	assert_true(_has_type(events, &"exploded"))
	assert_eq(timed.get_state(), WasherFSM.State.BROKEN)
	assert_eq(timed.get_loaded_items().size(), 0, "the load is ejected")

	var empty := _new_fsm(&"red", 0)
	assert_false(empty.force_turbulent(), "nothing to make turbulent")


func test_strike_resolution_table() -> void:
	for grade: int in [RhythmEvaluator.Grade.GOOD, RhythmEvaluator.Grade.PERFECT]:
		var machine := _new_fsm(&"red", 0)
		_fill(machine)
		machine.force_turbulent()
		assert_true(machine.strike(grade), "grade %d resolves" % grade)
		assert_eq(machine.get_state(), WasherFSM.State.WASHING)
		assert_eq(machine.turbulence, 0.0)
		assert_true(_has_type(machine.take_events(), &"turbulence_resolved"))

	var missed := _new_fsm(&"red", 0)
	_fill(missed)
	missed.force_turbulent()
	assert_false(missed.strike(RhythmEvaluator.Grade.MISS))
	assert_eq(missed.get_state(), WasherFSM.State.TURBULENT)

	var starts := _new_fsm(&"red", 0)
	starts.insert(_item(&"rocky", 6.0))
	assert_true(starts.strike(RhythmEvaluator.Grade.PERFECT), "a strike starts the cycle")

	var empty := _new_fsm(&"red", 0)
	assert_false(empty.strike(RhythmEvaluator.Grade.PERFECT))

	var locked := _new_fsm(&"red", 0)
	locked.insert(_item(&"rocky", 6.0))
	locked.set_locked(true)
	assert_false(locked.strike(RhythmEvaluator.Grade.PERFECT))


# --- explosion, repair, determinism ----------------------------------------


func test_explosion_and_repair_table() -> void:
	fsm.insert(_item(&"rocky", 6.0))
	fsm.insert(_item(&"sock", 4.0))
	var events := fsm.explode()
	assert_eq(fsm.get_state(), WasherFSM.State.BROKEN)
	assert_eq(fsm.slots_used, 0)
	var payload: Array = []
	var reason := &""
	for event in events:
		if StringName(str(event.get("type"))) == &"exploded":
			payload = event["items"]
			reason = StringName(str(event.get("reason")))
	assert_eq(payload.size(), 2, "the exploded event carries the ejected load")
	assert_eq(reason, &"forced")

	assert_almost_eq(fsm.get_progress(), 0.0, 0.001, "repair starts at 0")
	fsm.tick(WasherFSM.REPAIR_COOLDOWN_S * 0.5)
	assert_almost_eq(fsm.get_progress(), 0.5, 0.02)
	fsm.tick(WasherFSM.REPAIR_COOLDOWN_S * 0.46)
	assert_eq(fsm.get_state(), WasherFSM.State.BROKEN, "still repairing")
	var repaired := fsm.tick(0.3)
	assert_true(_has_type(repaired, &"repaired"))
	assert_eq(fsm.get_state(), WasherFSM.State.IDLE)


func test_determinism_table() -> void:
	var first := _new_fsm(&"red", 2)
	var second := _new_fsm(&"red", 2)
	for machine: WasherFSM in [first, second]:
		machine.insert(_item(&"rocky", 6.0))
		machine.insert(_item(&"sock", 4.0))
		machine.insert(_item(&"moon", 7.0))
		machine.tick(1.5)
		machine.force_turbulent()
		machine.tick(0.75)
		machine.strike(RhythmEvaluator.Grade.GOOD)
		machine.tick(1.0)
	assert_eq(first.get_state(), second.get_state())
	assert_almost_eq(first.get_progress(), second.get_progress(), 0.0001)
	assert_almost_eq(first.remaining, second.remaining, 0.0001)
	assert_eq(first.get_loaded_items().size(), second.get_loaded_items().size())

	var info := WasherFSM._read_info(_item(&"moon", 7.0, 2, &"blue", &"ringed"))
	assert_eq(StringName(str(info["id"])), &"moon")
	assert_eq(StringName(str(info["color"])), &"blue")
	assert_eq(StringName(str(info["pattern"])), &"ringed")
	assert_eq(float(info["wash_s"]), 7.0)
	assert_eq(int(info["slots"]), 2)

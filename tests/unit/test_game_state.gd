extends GutTest
## GameState rules: stability ledger, combo multiplier, accuracy, seeded RNG.


func before_each() -> void:
	GameState.reset(777)


func test_reset_state() -> void:
	assert_almost_eq(GameState.stability, 100.0, 0.0001)
	assert_eq(GameState.combo, 1)
	assert_eq(GameState.score, 0)
	assert_eq(GameState.seed_value, 777)
	assert_false(GameState.is_ended)


func test_stability_is_clamped_and_ends_shift() -> void:
	GameState.add_stability(Config.STABILITY_FELL_OFF_BELT)
	assert_almost_eq(GameState.stability, 100.0 + Config.STABILITY_FELL_OFF_BELT, 0.0001)
	assert_false(GameState.is_ended)
	GameState.add_stability(-500.0, "shredder")
	assert_almost_eq(GameState.stability, 0.0, 0.0001)
	assert_true(GameState.is_ended)
	assert_eq(GameState.get_end_result().get("reason"), "shredder")
	assert_false(GameState.get_end_result().get("victory"))


func test_stability_never_exceeds_100() -> void:
	GameState.add_stability(50.0)
	assert_almost_eq(GameState.stability, 100.0, 0.0001)


func test_combo_gains_and_cap() -> void:
	GameState.register_grade(RhythmEvaluator.Grade.PERFECT)
	assert_eq(GameState.combo, 3)
	GameState.register_grade(RhythmEvaluator.Grade.GOOD)
	assert_eq(GameState.combo, 4)
	for i in range(10):
		GameState.register_grade(RhythmEvaluator.Grade.PERFECT)
	assert_eq(GameState.combo, 8, "combo caps at x8")
	assert_eq(GameState.max_combo, 8)
	GameState.register_grade(RhythmEvaluator.Grade.MISS)
	assert_eq(GameState.combo, 1, "MISS resets to x1")
	assert_eq(GameState.max_combo, 8)


func test_accuracy_math() -> void:
	GameState.register_grade(RhythmEvaluator.Grade.PERFECT)
	GameState.register_grade(RhythmEvaluator.Grade.PERFECT)
	GameState.register_grade(RhythmEvaluator.Grade.GOOD)
	GameState.register_grade(RhythmEvaluator.Grade.MISS)
	assert_almost_eq(GameState.accuracy(), 0.75, 0.0001)
	assert_eq(GameState.rhythm_actions, 4)


func test_accuracy_with_no_actions_is_zero() -> void:
	assert_almost_eq(GameState.accuracy(), 0.0, 0.0001)


func test_score_and_delivery_counters() -> void:
	GameState.add_score(100)
	GameState.add_score(350)
	assert_eq(GameState.score, 450)
	GameState.add_score(-1000)
	assert_eq(GameState.score, 0)


func test_seeded_rng_is_reproducible() -> void:
	GameState.reset(4242)
	var first := [GameState.rng.randi(), GameState.rng.randi(), GameState.rng.randi()]
	GameState.reset(4242)
	var second := [GameState.rng.randi(), GameState.rng.randi(), GameState.rng.randi()]
	assert_eq(first, second)


func test_set_phase_emits_once_per_change() -> void:
	watch_signals(GameState)
	GameState.set_phase(2)
	assert_eq(GameState.phase_index, 2)
	assert_signal_emit_count(GameState, "phase_changed", 1)
	GameState.set_phase(2)
	assert_signal_emit_count(GameState, "phase_changed", 1)

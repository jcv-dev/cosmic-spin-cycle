extends GutTest
## CosmicWasher node contract, consequences and the stability ledger.
##
## The node's `_process` is disabled in every test: the FSM is deterministic and `tick(dt)`
## is the only clock. The beat clock is parked for the whole file (AGENTS §A9 lesson).

const SCENE_PATH := "res://scenes/entities/CosmicWasher.tscn"
const SANDBOX_PATH := "res://scenes/dev/WasherSandbox.tscn"

var washer: CosmicWasher
var _beat_processing := false


class StubItem:
	extends Node2D

	var item_id := &"rocky"
	var color := &"red"
	var pattern := &"solid"
	var is_clean := false
	var wash_s := 2.0
	var slots := 1
	var points := 100
	var data = null


func before_each() -> void:
	GameState.reset(1234)
	_beat_processing = BeatConductor.is_processing()
	BeatConductor.set_stream(null, 0.0)
	BeatConductor.set_process(false)
	washer = load(SCENE_PATH).instantiate() as CosmicWasher
	assert_not_null(washer, "CosmicWasher.tscn must exist")
	add_child_autofree(washer)
	washer.set_process(false)
	washer.configure(&"washer_nw", Rect2(36, 32, 48, 48), Vector2(60, 80), &"red")


func after_each() -> void:
	BeatConductor.stop()
	BeatConductor.set_process(_beat_processing)


func _make_item(
	id: StringName = &"rocky",
	color: StringName = &"red",
	pattern: StringName = &"solid",
	clean: bool = false,
	wash: float = 2.0
) -> StubItem:
	var item := StubItem.new()
	item.item_id = id
	item.color = color
	item.pattern = pattern
	item.wash_s = wash
	item.is_clean = clean
	add_child_autofree(item)
	return item


# --- scene contract ---------------------------------------------------------


func test_scene_contract() -> void:
	assert_true(washer is StaticBody2D, "root is a StaticBody2D")
	assert_eq(
		washer.collision_layer & Config.CollisionLayer.WASHER,
		Config.CollisionLayer.WASHER,
		"layer carries WASHER"
	)
	assert_eq(washer.collision_mask, 0, "the body does not scan anything")
	assert_true(washer.is_in_group(Config.GROUP_WASHERS))
	var mouth := washer.get_node_or_null(^"Mouth") as Area2D
	assert_not_null(mouth, "Mouth Area2D exists")
	assert_eq(mouth.collision_layer, 0, "mouth layer 0")
	assert_eq(mouth.collision_mask, Config.CollisionLayer.ITEMS, "mouth sees items")
	assert_not_null(washer.get_node_or_null(^"Visual"), "Visual exists")
	assert_not_null(washer.get_node_or_null(^"Audio"), "Audio exists")
	assert_not_null(washer.get_node_or_null(^"SteamAnchor"), "SteamAnchor exists")
	assert_not_null(washer.get_node_or_null(^"Holo"), "Holo is built in _ready")
	assert_not_null(washer.get_node_or_null(^"ProgressRing"), "ProgressRing is built")
	var body := washer.get_node(^"CollisionShape2D") as CollisionShape2D
	assert_almost_eq((body.shape as RectangleShape2D).size.x, 176.0, 0.001)
	var mouth_shape := mouth.get_node(^"CollisionShape2D") as CollisionShape2D
	assert_almost_eq((mouth_shape.shape as CircleShape2D).radius, CosmicWasher.MOUTH_RADIUS, 0.001)
	assert_eq(CosmicWasher.State.IDLE, 0)
	assert_eq(CosmicWasher.State.WASHING, 1)
	assert_eq(CosmicWasher.State.TURBULENT, 2)
	assert_eq(CosmicWasher.State.DONE, 3)
	assert_eq(CosmicWasher.State.BROKEN, 4)
	for ordinal in range(5):
		assert_eq(
			int(CosmicWasher.State.values()[ordinal]),
			int(WasherFSM.State.values()[ordinal]),
			"the node mirrors the FSM ordinal %d" % ordinal
		)
	assert_eq(washer.get_state(), CosmicWasher.State.IDLE)


func test_configure_positions_the_mouth_and_requirement() -> void:
	assert_almost_eq(washer.position.x, 240.0, 0.001)
	assert_almost_eq(washer.position.y, 320.0, 0.001)
	assert_eq(washer.get_requirement(), &"red")
	assert_false(washer.is_locked())
	assert_eq(washer.get_mouth_world(), washer.global_position)
	var holo := washer.get_node(^"Holo") as Node2D
	assert_almost_eq(holo.global_position.x, 240.0, 0.001, "centred on the machine")
	assert_almost_eq(
		holo.global_position.y,
		192.0,
		0.001,
		"bottom edge inside the control panel, clear of the HUD"
	)


func test_configure_before_ready_is_applied() -> void:
	var early := load(SCENE_PATH).instantiate() as CosmicWasher
	assert_not_null(early)
	early.configure(&"washer_se", Rect2(236, 96, 48, 48), Vector2(260, 144), &"spotted")
	add_child_autofree(early)
	assert_almost_eq(early.position.x, 1040.0, 0.001)
	assert_almost_eq(early.position.y, 576.0, 0.001)
	assert_eq(early.get_requirement(), &"spotted")


func test_requirement_and_lock_can_be_changed_at_a_phase_boundary() -> void:
	washer.set_requirement(&"blue")
	assert_eq(washer.get_requirement(), &"blue")
	washer.set_locked(true)
	assert_true(washer.is_locked())
	washer.set_locked(false)
	assert_false(washer.is_locked())


# --- loading and the stability ledger --------------------------------------


func test_accepting_a_matching_item() -> void:
	var item := _make_item()
	watch_signals(washer)
	assert_true(washer.try_accept(item))
	assert_signal_emitted_with_parameters(washer, "item_loaded", [item])
	assert_eq(washer.get_loaded_items().size(), 1)
	assert_false(item.visible, "the machine keeps the item inside")
	assert_eq(washer.get_state(), WasherFSM.State.IDLE)


func test_wrong_washer_jams_the_machine_and_costs_twelve() -> void:
	var item := _make_item(&"sock", &"blue", &"solid")
	watch_signals(washer)
	assert_true(washer.try_accept(item), "a wrong colour is accepted, then jams")
	assert_eq(washer.get_state(), WasherFSM.State.BROKEN, "the machine is broken")
	assert_almost_eq(GameState.stability, 88.0, 0.001, "-12")
	assert_eq(GameState.wrong_washer_count, 1)
	assert_signal_emitted_with_parameters(washer, "item_rejected", [item, "jammed"])
	assert_eq(washer.get_loaded_items().size(), 0)
	var chip := washer.get_node_or_null(^"FeedbackChip")
	assert_not_null(chip, "the wrong-washer chip is local to the machine")
	assert_eq(str(chip.get(&"text")), "-12")
	assert_false(bool(chip.get(&"gain")), "a loss uses the down glyph")
	chip.set_process(false)
	# A broken machine refuses further loads until it repairs itself.
	washer.force_finish()
	assert_eq(washer.get_state(), WasherFSM.State.BROKEN)


func test_locked_washer_never_penalises() -> void:
	washer.set_locked(true)
	var item := _make_item()
	watch_signals(washer)
	assert_false(washer.try_accept(item))
	assert_almost_eq(GameState.stability, 100.0, 0.001, "no penalty")
	assert_eq(GameState.wrong_washer_count, 0)
	assert_signal_emitted_with_parameters(washer, "item_rejected", [item, "locked"])


func test_wildcard_is_never_penalised() -> void:
	var core := _make_item(&"galaxy_core", &"", &"", false, 12.0)
	assert_true(washer.try_accept(core), "the core fits an empty red washer")
	var second := _make_item(&"galaxy_core", &"", &"", false, 12.0)
	assert_false(washer.try_accept(second), "a second core cannot enter")
	assert_almost_eq(GameState.stability, 100.0, 0.001, "the wildcard never costs stability")
	assert_eq(GameState.wrong_washer_count, 0)


func test_a_full_washer_rejects_without_a_penalty() -> void:
	for _i in range(3):
		assert_true(washer.try_accept(_make_item()))
	var fourth := _make_item()
	assert_false(washer.try_accept(fourth))
	assert_almost_eq(GameState.stability, 100.0, 0.001, "full is not wrong")
	assert_eq(GameState.wrong_washer_count, 0)


# --- cycle consequences -----------------------------------------------------


func test_cycle_marks_items_clean_and_counts_them_once() -> void:
	var items: Array[StubItem] = []
	for _i in range(3):
		var item := _make_item(&"rocky", &"red", &"solid", false, 2.0)
		items.append(item)
		assert_true(washer.try_accept(item))
	watch_signals(washer)
	washer.tick(2.1)
	assert_eq(washer.get_state(), WasherFSM.State.DONE)
	assert_signal_emitted(washer, "cycle_done")
	assert_true(washer.get_node(^"Bubbles").visible, "the clean loop is on while DONE")
	assert_eq(GameState.washed_count, 3, "one count per item")
	for item in items:
		assert_true(item.is_clean, "cycle_done marks the load clean")
	washer.tick(1.0)
	assert_eq(GameState.washed_count, 3, "no double counting")
	assert_almost_eq(GameState.stability, 100.0, 0.001, "washing is free")


func test_done_items_are_ejected_after_the_settle() -> void:
	var item := _make_item(&"rocky", &"red", &"solid", false, 2.0)
	assert_true(washer.try_accept(item))
	assert_true(washer.strike(RhythmEvaluator.Grade.PERFECT), "a strike starts the cycle")
	assert_true(washer.force_finish())
	assert_eq(washer.get_state(), WasherFSM.State.DONE)
	washer.tick(WasherFSM.DONE_SETTLE_S + 0.1)
	assert_eq(washer.get_state(), WasherFSM.State.IDLE)
	assert_true(item.visible, "the clean item is back in the room")
	assert_eq(washer.get_loaded_items().size(), 0)


func test_state_changed_reports_old_and_new() -> void:
	watch_signals(washer)
	for _i in range(3):
		washer.try_accept(_make_item())
	assert_signal_emitted_with_parameters(
		washer, "state_changed", [WasherFSM.State.IDLE, WasherFSM.State.WASHING]
	)


func test_explosion_applies_the_penalty_once_and_ejects() -> void:
	var items: Array[StubItem] = []
	for _i in range(2):
		var item := _make_item(&"rocky", &"red", &"solid", false, 2.0)
		items.append(item)
		washer.try_accept(item)
	watch_signals(washer)
	assert_true(washer.force_turbulent())
	assert_eq(washer.get_state(), WasherFSM.State.TURBULENT)
	var limit := minf(Config.TURBULENCE_TIMEOUT_S, 8.0 * Config.beat_seconds(Config.PHASE_BPM[0]))
	washer.tick(limit + 0.1)
	assert_signal_emitted(washer, "exploded")
	assert_not_null(washer.get_node_or_null(^"ExplosionFX"), "the 6-frame burst plays")
	assert_not_null(washer.get_node_or_null(^"ExplosionText"), "¡EXPLOSIÓN! at the machine")
	assert_eq(washer.get_state(), WasherFSM.State.BROKEN)
	assert_almost_eq(GameState.stability, 75.0, 0.001, "-25 from 100")
	assert_eq(GameState.exploded_count, 1)
	for item in items:
		assert_true(item.visible, "the load is thrown back into the room")
	assert_eq(washer.get_loaded_items().size(), 0)


func test_strike_resolves_turbulence() -> void:
	var item := _make_item(&"rocky", &"red", &"solid", false, 2.0)
	washer.try_accept(item)
	assert_true(washer.strike(RhythmEvaluator.Grade.GOOD))
	assert_true(washer.force_turbulent())
	assert_eq(washer.holo_label, "TURBULENTO", "persistent 14 px label, not a popup")
	watch_signals(washer)
	assert_true(washer.strike(RhythmEvaluator.Grade.GOOD))
	assert_signal_emitted_with_parameters(
		washer, "turbulence_resolved", [RhythmEvaluator.Grade.GOOD]
	)
	assert_eq(washer.get_state(), WasherFSM.State.WASHING)
	assert_false(washer.strike(RhythmEvaluator.Grade.MISS), "MISS does nothing when calm")


# --- hologram ---------------------------------------------------------------


func test_carry_hint_matches_and_mismatches() -> void:
	var red := _make_item(&"rocky", &"red", &"solid")
	washer.set_carry_hint(red)
	assert_eq(washer.holo_state, CosmicWasher.HoloState.MATCH)
	assert_almost_eq(washer.holo_alpha, 1.0, 0.001)
	var blue := _make_item(&"sock", &"blue", &"solid")
	washer.set_carry_hint(blue)
	assert_eq(washer.holo_state, CosmicWasher.HoloState.MISMATCH)
	assert_almost_eq(washer.holo_alpha, 0.25, 0.001, "mismatch dims to 25 %")
	assert_eq(washer.holo_label, "NO COMPATIBLE")
	washer.set_carry_hint(null)
	assert_eq(washer.holo_state, CosmicWasher.HoloState.IDLE)
	assert_almost_eq(washer.holo_alpha, 0.6, 0.001, "idle sits at 60 %")


func test_locked_holo_says_out_of_service() -> void:
	washer.set_locked(true)
	assert_eq(washer.holo_state, CosmicWasher.HoloState.LOCKED)
	assert_eq(washer.holo_label, "BLOQUEADA")


func test_done_and_broken_holo_states() -> void:
	var item := _make_item()
	washer.try_accept(item)
	washer.strike(RhythmEvaluator.Grade.PERFECT)
	washer.force_finish()
	assert_eq(washer.holo_state, CosmicWasher.HoloState.DONE)
	assert_eq(washer.holo_label, "LISTO")
	washer.explode_now()
	assert_eq(washer.holo_state, CosmicWasher.HoloState.BROKEN)
	assert_eq(washer.holo_label, "AVERIADA")


# --- dev sandbox ------------------------------------------------------------


func test_sandbox_scene_builds_the_four_washers_and_the_chute() -> void:
	var sandbox := load(SANDBOX_PATH) as PackedScene
	assert_not_null(sandbox, "WasherSandbox.tscn must exist")
	var instance := sandbox.instantiate()
	add_child_autofree(instance)
	var washers := get_tree().get_nodes_in_group(Config.GROUP_WASHERS)
	var chutes := get_tree().get_nodes_in_group(Config.GROUP_CHUTE)
	assert_true(washers.size() >= 4, "four washers in the sandbox")
	assert_true(chutes.size() >= 1, "the chute is the goal")

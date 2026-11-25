# gdlint: disable=max-public-methods
extends GutTest
## The director is the only adapter between the pure gates and the live level.
##
## Fake level/player/washer/chute: every M4 system is behind a `has_method` guard, so this
## exercises the adapter without the washer scene and stays valid after that merge.

const DIRECTOR_SCRIPT := preload("res://scripts/tutorial/TutorialDirector.gd")
const OVERLAY_SCENE := preload("res://scenes/ui/TutorialOverlay.tscn")
const FLOW_TOLERANCE := 0.02


class FakeItem:
	extends Node2D
	var item_id: StringName = &"rocky"
	var color: StringName = &"red"
	var pattern: StringName = &"solid"
	var is_clean := false

	func set_clean(value: bool) -> void:
		is_clean = value


class FakePlayer:
	extends Node2D
	signal grabbed(item: Node)
	signal thrown(item: Node, grade: int)
	signal struck(washer: Node, grade: int)
	var held_item: Node = null


class FakeWasher:
	extends Node2D
	signal item_loaded(item: Node)
	signal state_changed(old_state: int, new_state: int)
	signal cycle_done(items: Array)
	var washer_id: StringName = &"washer_nw"
	var requirement: StringName = &"red"
	var locked := false
	var state := 0
	var loaded: Array = []
	var turbulent_calls := 0
	var finish_calls := 0

	func get_requirement() -> StringName:
		return requirement

	func set_requirement(value: StringName) -> void:
		requirement = value

	func set_locked(value: bool) -> void:
		locked = value

	func get_state() -> int:
		return state

	func get_progress() -> float:
		return 0.5

	func get_loaded_items() -> Array:
		return loaded

	func get_mouth_world() -> Vector2:
		return global_position

	func force_turbulent() -> bool:
		turbulent_calls += 1
		state = 2
		return true

	func force_finish() -> void:
		finish_calls += 1
		state = 3

	func strike(grade: int) -> bool:
		if grade <= RhythmEvaluator.Grade.GOOD:
			state = 3
		return true

	func set_carry_hint(_item: Variant) -> void:
		pass


class FakeChute:
	extends Node2D
	signal delivered(item: Node, points: int)
	signal dirty_rejected(item: Node)


class FakeLevel:
	extends Node2D
	var player: FakePlayer
	var washers: Array = []
	var chute: FakeChute
	var items: Node2D
	var clock_running := false
	var completed := false
	var spawn_count := 0

	func _init() -> void:
		player = FakePlayer.new()
		player.name = "Player"
		add_child(player)
		chute = FakeChute.new()
		chute.name = "DeliveryChute"
		items = Node2D.new()
		items.name = "Items"
		add_child(items)

	func spawn_item(
		item_id: StringName,
		color: StringName,
		pattern: StringName,
		position: Vector2,
		clean: bool = false
	) -> Node:
		var item := FakeItem.new()
		item.item_id = item_id
		item.color = color
		item.pattern = pattern
		item.is_clean = clean
		item.position = position
		items.add_child(item)
		spawn_count += 1
		return item

	func clear_items() -> void:
		for child in items.get_children():
			child.queue_free()

	func get_player() -> Node:
		return player

	func get_washers() -> Array:
		return washers

	func get_washer(id: StringName) -> Node:
		for washer in washers:
			if washer.washer_id == id:
				return washer
		return null

	func get_chute() -> Node:
		return chute

	func get_items_layer() -> Node2D:
		return items

	func get_camera() -> Camera2D:
		return null

	func complete_tutorial() -> void:
		completed = true

	func _is_locked(_id: StringName) -> bool:
		return false


func _make_washer(id: StringName, requirement: StringName, at: Vector2) -> FakeWasher:
	var washer := FakeWasher.new()
	washer.washer_id = id
	washer.requirement = requirement
	washer.position = at
	return washer


func _make_level() -> FakeLevel:
	var level := FakeLevel.new()
	add_child_autofree(level)
	level.washers.append(_make_washer(&"washer_nw", &"red", Vector2(240, 320)))
	level.washers.append(_make_washer(&"washer_ne", &"blue", Vector2(1040, 320)))
	for washer in level.washers:
		level.add_child(washer)
	return level


func _start(level: FakeLevel) -> Array:
	var overlay := OVERLAY_SCENE.instantiate() as TutorialOverlay
	add_child_autofree(overlay)
	var director := DIRECTOR_SCRIPT.new() as TutorialDirector
	add_child_autofree(director)
	director.level = level
	director.overlay = overlay
	director.start()
	return [director, overlay]


func _frames(director: TutorialDirector, count: int, delta: float = 0.016) -> void:
	for _i in range(count):
		director._process(delta)


func _until_step(director: TutorialDirector, index: int, max_frames: int = 240) -> bool:
	for _i in range(max_frames):
		director._process(0.016)
		if director.current_step() == index:
			return true
	return false


func after_each() -> void:
	GameState.stability_protected = false
	BeatConductor.stop()


# --- Lifecycle --------------------------------------------------------------


func test_director_starts_on_the_first_gate_and_protects_stability() -> void:
	GameState.reset(7001)
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	assert_true(director.is_active())
	assert_eq(director.current_step(), 0)
	assert_true(GameState.stability_protected)
	assert_eq(TutorialSteps.chip_text(director.current_step()), "PASO 1/7 · MUÉVETE")


func test_director_stages_a_throwable_item_on_the_grab_gate() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	director.debug_goto(1)
	assert_eq(director.current_step(), 1)
	assert_not_null(director.gate_item())
	assert_eq(level.items.get_child_count(), 1)


func test_no_gate_advances_without_its_success_event() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	_frames(director, 180, 0.05)
	assert_eq(director.current_step(), 0, "nothing moved, so gate 1 cannot be granted")
	assert_false(bool(director.current_state()["granted"]))


func test_exit_always_clears_the_stability_guard() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	assert_true(GameState.stability_protected)
	director.exit()
	assert_false(GameState.stability_protected)
	assert_false(director.is_active())


# --- Gate flow --------------------------------------------------------------


func test_travel_gate_completes_after_two_hundred_pixels() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	for _i in range(3):
		level.player.position += Vector2(60, 0)
		director._process(0.016)
	assert_true(
		_until_step(director, 1),
		"180 px is not enough; the extra frames plus the 60 px below must finish it"
	)
	director.debug_goto(0)
	level.player.position = Vector2.ZERO
	for _i in range(4):
		level.player.position += Vector2(60, 0)
		director._process(0.016)
	assert_true(_until_step(director, 1))


func test_grab_gate_advances_on_the_player_signal() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	director.debug_goto(1)
	level.player.emit_signal("grabbed", director.gate_item())
	assert_true(_until_step(director, 2))


func test_throw_gate_requires_the_item_to_leave_the_hold() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	director.debug_goto(2)
	var item := director.gate_item()
	item.position = level.player.position
	level.player.emit_signal("thrown", item, RhythmEvaluator.Grade.GOOD)
	assert_false(bool(director.current_state()["granted"]))
	item.position = level.player.position + Vector2(200, 0)
	level.player.emit_signal("thrown", item, RhythmEvaluator.Grade.GOOD)
	assert_true(_until_step(director, 3))


func test_beat_gate_needs_two_good_throws() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	director.debug_goto(3)
	var first := director.gate_item()
	first.position = level.player.position + Vector2(300, 0)
	level.player.emit_signal("thrown", first, RhythmEvaluator.Grade.PERFECT)
	assert_eq(int(director.current_state()["count"]), 1)
	director._process(0.016)
	var second: Node = director.gate_item()
	if second == null:
		second = level.items.get_child(0)
	second.position = level.player.position + Vector2(300, 0)
	level.player.emit_signal("thrown", second, RhythmEvaluator.Grade.PERFECT)
	assert_true(_until_step(director, 4))


func test_match_gate_locks_the_incompatible_washers() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	director.debug_goto(4)
	var red: FakeWasher = level.get_washer(&"washer_nw")
	var blue: FakeWasher = level.get_washer(&"washer_ne")
	assert_eq(director.target_washer(), red)
	assert_false(red.locked)
	assert_true(blue.locked)


func test_match_gate_ignores_a_wrong_mouth_and_accepts_the_right_one() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	director.debug_goto(4)
	var blue: FakeWasher = level.get_washer(&"washer_ne")
	blue.emit_signal("item_loaded", level.items.get_child(0))
	assert_false(bool(director.current_state()["granted"]))
	assert_eq(int(director.current_state()["rejected"]), 1)
	var red: FakeWasher = level.get_washer(&"washer_nw")
	red.loaded.append(level.items.get_child(0))
	red.emit_signal("item_loaded", level.items.get_child(0))
	assert_true(_until_step(director, 5))


func test_strike_gate_arms_turbulence_and_accepts_a_good_hit() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	director.debug_goto(5)
	var red: FakeWasher = level.get_washer(&"washer_nw")
	assert_eq(red.turbulent_calls, 1)
	assert_eq(red.state, 2)
	director.debug_delta_t = 0.5
	level.player.emit_signal("struck", red, RhythmEvaluator.Grade.MISS)
	assert_false(bool(director.current_state()["granted"]))
	director.debug_delta_t = 0.0
	level.player.emit_signal("struck", red, RhythmEvaluator.Grade.GOOD)
	assert_true(_until_step(director, 6))


func test_deliver_gate_ends_the_protection_and_needs_a_clean_item() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	director.debug_goto(6)
	assert_false(GameState.stability_protected, "gate 7 restores real stability stakes")
	var item := FakeItem.new()
	level.items.add_child(item)
	item.is_clean = false
	level.chute.emit_signal("delivered", item, 0)
	assert_false(bool(director.current_state()["granted"]))
	item.is_clean = true
	level.chute.emit_signal("delivered", item, 100)
	assert_true(bool(director.current_state()["granted"]))
	for _i in range(40):
		director._process(0.016)
	assert_false(director.is_active(), "the last gate ends the run, not a gate 8")


# --- Fail-forward and soft skip --------------------------------------------


func test_soft_skip_only_after_the_stuck_grace() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	assert_false(director.can_soft_skip())
	director.debug_set_elapsed(TutorialSteps.STRIKE_ASSIST_AFTER_S + 0.1)
	assert_true(director.can_soft_skip())
	director.soft_skip()
	assert_true(_until_step(director, 1))


func test_travel_hint_circle_appears_after_four_seconds() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	var overlay: TutorialOverlay = started[1]
	director.debug_set_elapsed(4.2)
	director._process(0.016)
	assert_true(overlay._hint_active)
	assert_almost_eq(overlay._hint_radius, 120.0, 0.001)


func test_travel_hint_ring_follows_the_player() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	var overlay: TutorialOverlay = started[1]
	director.debug_set_elapsed(5.0)
	level.player.position = Vector2(40, 0)
	director._process(0.016)
	assert_true(overlay._hint_active)
	assert_almost_eq(overlay._hint_world.x, 40.0, 1.0)
	level.player.position = Vector2(80, 0)
	director._process(0.016)
	assert_almost_eq(overlay._hint_world.x, 80.0, 1.0, "the ring tracks, it does not lag")
	assert_eq(director.current_step(), 0, "80 px of walking must not grant the 200 px gate")


func test_strike_gate_cannot_explode_and_assists_a_stuck_player() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	director.debug_goto(5)
	var red: FakeWasher = level.get_washer(&"washer_nw")
	director.debug_set_elapsed(TutorialSteps.STRIKE_ASSIST_AFTER_S + 0.1)
	director._process(0.016)
	assert_eq(red.state, 3, "the assisted strike resolves the turbulence")
	assert_true(bool(director.current_state()["granted"]))


func test_locked_washers_are_restored_when_the_gate_ends() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	director.debug_goto(6)
	var blue: FakeWasher = level.get_washer(&"washer_ne")
	assert_false(blue.locked, "gate 7 must not leave the room half locked")


func test_autoplay_walks_every_gate() -> void:
	var level := _make_level()
	var started := _start(level)
	var director: TutorialDirector = started[0]
	director.autoplay = true
	watch_signals(director)
	for _i in range(400):
		director._process(0.05)
		if not director.is_active():
			break
	assert_false(director.is_active(), "autoplay must walk all seven gates")
	assert_signal_emitted(director, "finished")

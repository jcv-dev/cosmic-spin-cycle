extends GutTest
## DiegeticLayer contract: it boots with no world, finds the world by group, and the beat ring
## stays inside its radius band (docs/UX_BIBLE.md §6.4, docs/HUD.md).

const LAYER_SCENE := preload("res://scenes/ui/DiegeticLayer.tscn")


class FakePlayer:
	extends Node2D
	var held_item: Node = null
	var aim_direction := Vector2.RIGHT

	func _ready() -> void:
		add_to_group(Config.GROUP_PLAYER)

	func get_aim_direction() -> Vector2:
		return aim_direction

	func get_hold_position() -> Vector2:
		return global_position + aim_direction * Config.HOLD_DISTANCE


class FakeWasher:
	extends Node2D
	var requirement: StringName = &"red"
	var state := 0
	var locked := false

	func _ready() -> void:
		add_to_group(Config.GROUP_WASHERS)

	func get_requirement() -> StringName:
		return requirement

	func get_state() -> int:
		return state

	func is_locked() -> bool:
		return locked

	func get_progress() -> float:
		return 0.0

	func get_mouth_world() -> Vector2:
		return global_position

	func strike(_grade: int) -> void:
		pass


class FakeChute:
	extends Node2D

	func _ready() -> void:
		add_to_group(Config.GROUP_CHUTE)

	func try_deliver(_item: Node) -> bool:
		return true


class FakeItem:
	extends Node2D
	var item_id: StringName = &"rocky"
	var color: StringName = &"red"
	var pattern: StringName = &"solid"
	var is_held := false
	var is_clean := false
	var data: ItemData = null

	func _ready() -> void:
		add_to_group(Config.GROUP_ITEMS)


var _world: Node2D
var _layer: Node2D
var _player: FakePlayer
var _washers: Array[FakeWasher] = []
var _chute: FakeChute


func before_each() -> void:
	GameState.reset(22)
	BeatConductor.stop()
	# A stream left on the conductor by another test would make get_song_time() follow the
	# (stopped) audio position instead of the stepped clock.
	BeatConductor.set_stream(null, 0.0)
	BeatConductor.set_process(false)
	Settings.reduce_motion = false
	_world = Node2D.new()
	_world.name = "TestWorld"
	add_child_autofree(_world)
	_washers.clear()
	_player = null
	_chute = null


func after_each() -> void:
	Settings.reduce_motion = false
	BeatConductor.stop()
	BeatConductor.set_process(true)


## Adds the layer after the world actors, so its `_ready` sees the groups.
func _add_layer() -> Node2D:
	_layer = LAYER_SCENE.instantiate() as Node2D
	_world.add_child(_layer)
	return _layer


func _add_player(at: Vector2 = Vector2(640, 360)) -> FakePlayer:
	_player = FakePlayer.new()
	_player.position = at
	_world.add_child(_player)
	return _player


func _add_washer(at: Vector2, requirement: StringName = &"red") -> FakeWasher:
	var washer := FakeWasher.new()
	washer.position = at
	washer.requirement = requirement
	_world.add_child(washer)
	_washers.append(washer)
	return washer


func _add_chute(at: Vector2) -> FakeChute:
	_chute = FakeChute.new()
	_chute.position = at
	_world.add_child(_chute)
	return _chute


func _add_item(at: Vector2, color: StringName = &"red") -> FakeItem:
	var item := FakeItem.new()
	item.position = at
	item.color = color
	_world.add_child(item)
	return item


func _hold(item: Node) -> void:
	_player.held_item = item


# --- Boot -------------------------------------------------------------------


func test_layer_boots_with_no_player_and_no_washers() -> void:
	_add_layer()
	assert_false(_layer.has_player())
	var state: Dictionary = _layer.state_readout()
	assert_eq(state["washers"], 0)
	assert_eq(state["items"], 0)
	assert_false(state["has_chute"])
	assert_between(_layer.ring_radius(), 42.0, 70.0, "ring radius stays in its band")
	_layer.advance(0.5)
	assert_false(_layer.has_player(), "still no player, still no crash")


func test_layer_finds_the_world_by_group() -> void:
	_add_player()
	_add_washer(Vector2(900, 360))
	_add_chute(Vector2(640, 200))
	_add_item(Vector2(600, 360))
	_add_layer()
	var state: Dictionary = _layer.state_readout()
	assert_true(state["has_player"])
	assert_eq(state["washers"], 1)
	assert_eq(state["items"], 1)
	assert_true(state["has_chute"])


func test_refresh_now_picks_up_a_late_player() -> void:
	_add_layer()
	assert_false(_layer.has_player())
	_add_player()
	_layer.refresh_now()
	assert_true(_layer.has_player(), "the 0.5 s rescan is also available on demand")


# --- Pulse ring -------------------------------------------------------------


func test_ring_contracts_between_beats() -> void:
	_add_player()
	_add_layer()
	BeatConductor.start(105)
	var beat := BeatConductor.beat_seconds()
	BeatConductor.advance_clock(beat * 0.1)
	_layer.refresh_now()
	var early: float = _layer.ring_radius()
	BeatConductor.advance_clock(beat * 0.6)
	_layer.refresh_now()
	var late: float = _layer.ring_radius()
	assert_between(early, 42.0, 70.0)
	assert_between(late, 42.0, 70.0)
	assert_lt(late, early, "the ring contracts toward the next beat")


func test_ring_snaps_wide_and_thick_on_the_beat() -> void:
	_add_player()
	_add_layer()
	BeatConductor.start(105)
	BeatConductor.advance_clock(BeatConductor.beat_seconds())
	_layer.refresh_now()
	assert_almost_eq(_layer.ring_radius(), 70.0, 0.5, "wide at the beat")
	assert_almost_eq(_layer.ring_width(), 4.0, 0.01, "thick inside the PERFECT window")
	assert_gte(_layer.ring_alpha(), 0.7)


func test_reduce_motion_keeps_the_ring_static_but_readable() -> void:
	Settings.reduce_motion = true
	_add_player()
	_add_layer()
	BeatConductor.start(105)
	BeatConductor.advance_clock(BeatConductor.beat_seconds() * 0.2)
	_layer.refresh_now()
	var first_radius: float = _layer.ring_radius()
	var first_alpha: float = _layer.ring_alpha()
	BeatConductor.advance_clock(BeatConductor.beat_seconds() * 0.5)
	_layer.refresh_now()
	assert_almost_eq(_layer.ring_radius(), first_radius, 0.01, "no scale snap")
	assert_ne(_layer.ring_alpha(), first_alpha, "information moves to alpha instead")
	assert_almost_eq(_layer.ring_width(), 2.0, 0.01)

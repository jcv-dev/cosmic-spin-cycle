extends GutTest
## DiegeticLayer world contract: it boots with no world, finds the world by group, keeps the
## beat ring inside its band and classifies the reticle destination
## (docs/UX_BIBLE.md §6.3–§6.4, docs/HUD.md).

const Fakes := preload("res://tests/unit/support/diegetic_fakes.gd")
const LAYER_SCENE := preload("res://scenes/ui/DiegeticLayer.tscn")

var world: Fakes.World
var layer: Node2D


func before_each() -> void:
	GameState.reset(22)
	BeatConductor.stop()
	# A stream left on the conductor by another test would make get_song_time() follow the
	# (stopped) audio position instead of the stepped clock.
	BeatConductor.set_stream(null, 0.0)
	BeatConductor.set_process(false)
	Settings.reduce_motion = false
	world = Fakes.World.new()
	world.name = "DiegeticTestWorld"
	add_child_autofree(world)
	layer = null


func after_each() -> void:
	Settings.reduce_motion = false
	BeatConductor.stop()
	BeatConductor.set_process(true)


## Adds the layer after the world actors, so its `_ready` sees the groups.
func _add_layer() -> Node2D:
	layer = LAYER_SCENE.instantiate() as Node2D
	world.add_child(layer)
	return layer


# --- Boot -------------------------------------------------------------------


func test_layer_boots_with_no_player_and_no_washers() -> void:
	_add_layer()
	assert_false(layer.has_player())
	var state: Dictionary = layer.state_readout()
	assert_eq(state["washers"], 0)
	assert_eq(state["items"], 0)
	assert_false(state["has_chute"])
	assert_between(layer.ring_radius(), 42.0, 70.0, "ring radius stays in its band")
	layer.advance(0.5)
	assert_false(layer.has_player(), "still no player, still no crash")


func test_layer_finds_the_world_by_group() -> void:
	world.add_player()
	world.add_washer(Vector2(900, 360))
	world.add_chute(Vector2(640, 200))
	world.add_item(Vector2(600, 360))
	_add_layer()
	var state: Dictionary = layer.state_readout()
	assert_true(state["has_player"])
	assert_eq(state["washers"], 1)
	assert_eq(state["items"], 1)
	assert_true(state["has_chute"])


func test_refresh_now_picks_up_a_late_player() -> void:
	_add_layer()
	assert_false(layer.has_player())
	world.add_player()
	layer.refresh_now()
	assert_true(layer.has_player(), "the 0.5 s rescan is also available on demand")


# --- Pulse ring -------------------------------------------------------------


func test_ring_contracts_between_beats() -> void:
	world.add_player()
	_add_layer()
	BeatConductor.start(105)
	var beat := BeatConductor.beat_seconds()
	BeatConductor.advance_clock(beat * 0.1)
	layer.refresh_now()
	var early: float = layer.ring_radius()
	BeatConductor.advance_clock(beat * 0.6)
	layer.refresh_now()
	var late: float = layer.ring_radius()
	assert_between(early, 42.0, 70.0)
	assert_between(late, 42.0, 70.0)
	assert_lt(late, early, "the ring contracts toward the next beat")


func test_ring_snaps_wide_and_thick_on_the_beat() -> void:
	world.add_player()
	_add_layer()
	BeatConductor.start(105)
	BeatConductor.advance_clock(BeatConductor.beat_seconds())
	layer.refresh_now()
	assert_almost_eq(layer.ring_radius(), 70.0, 0.5, "wide at the beat")
	assert_almost_eq(layer.ring_width(), 4.0, 0.01, "thick inside the PERFECT window")
	assert_gte(layer.ring_alpha(), 0.7)


func test_reduce_motion_keeps_the_ring_static_but_readable() -> void:
	Settings.reduce_motion = true
	world.add_player()
	_add_layer()
	BeatConductor.start(105)
	BeatConductor.advance_clock(BeatConductor.beat_seconds() * 0.2)
	layer.refresh_now()
	var first_radius: float = layer.ring_radius()
	var first_alpha: float = layer.ring_alpha()
	BeatConductor.advance_clock(BeatConductor.beat_seconds() * 0.2)
	layer.refresh_now()
	assert_almost_eq(layer.ring_radius(), first_radius, 0.01, "no scale snap")
	assert_ne(layer.ring_alpha(), first_alpha, "information moves to alpha instead")
	assert_almost_eq(layer.ring_width(), 2.0, 0.01)


# --- Aim reticle ------------------------------------------------------------


func test_no_target_without_a_held_item() -> void:
	world.add_player()
	world.add_washer(Vector2(840, 360), &"red")
	_add_layer()
	assert_eq(
		layer.reticle_state(), "none", "the reticle points at a destination for what you carry"
	)
	assert_null(layer.target())


func test_reticle_accepts_a_compatible_washer() -> void:
	world.add_player()
	world.add_washer(Vector2(840, 360), &"red")
	_add_layer()
	world.hold(world.add_item(Vector2(640, 360), &"red"))
	layer.refresh_now()
	assert_eq(layer.reticle_state(), "washer_ok")
	assert_not_null(layer.target())


func test_reticle_rejects_an_incompatible_washer() -> void:
	world.add_player()
	world.add_washer(Vector2(840, 360), &"red")
	_add_layer()
	world.hold(world.add_item(Vector2(640, 360), &"blue"))
	layer.refresh_now()
	assert_eq(layer.reticle_state(), "washer_no")


func test_reticle_rejects_a_locked_washer() -> void:
	world.add_player()
	var washer: Fakes.FakeWasher = world.add_washer(Vector2(840, 360), &"red")
	washer.locked = true
	_add_layer()
	world.hold(world.add_item(Vector2(640, 360), &"red"))
	layer.refresh_now()
	assert_eq(layer.reticle_state(), "washer_no")


func test_reticle_chute_states() -> void:
	world.add_player()
	world.add_chute(Vector2(840, 360))
	_add_layer()
	var item: Fakes.FakeItem = world.add_item(Vector2(640, 360), &"red")
	world.hold(item)
	layer.refresh_now()
	assert_eq(layer.reticle_state(), "chute")
	assert_false(bool(layer.state_readout()["chute_ok"]), "a dirty piece cannot be delivered")
	item.is_clean = true
	layer.refresh_now()
	assert_eq(layer.reticle_state(), "chute")
	assert_true(bool(layer.state_readout()["chute_ok"]), "a clean piece can")


func test_the_destination_closest_to_the_aim_ray_wins() -> void:
	world.add_player()
	world.add_washer(Vector2(880, 360), &"red")
	world.add_chute(Vector2(760, 360))
	_add_layer()
	var item: Fakes.FakeItem = world.add_item(Vector2(640, 360), &"red")
	item.is_clean = true
	world.hold(item)
	layer.refresh_now()
	assert_eq(layer.reticle_state(), "chute")

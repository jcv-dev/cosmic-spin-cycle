extends GutTest
## End-to-end M4 loop: a real LaundryItem goes into a washer, comes out clean, and pays at
## the chute. This is the acceptance path the brief asks for, with the real nodes and the
## real item database — no stubs.

const WASHER_SCENE := "res://scenes/entities/CosmicWasher.tscn"
const CHUTE_SCENE := "res://scenes/environment/DeliveryChute.tscn"

var washer: CosmicWasher
var chute: DeliveryChute
var item: LaundryItem
var _beat_processing := false


func before_each() -> void:
	GameState.reset(4321)
	GameState.stability = 50.0
	_beat_processing = BeatConductor.is_processing()
	BeatConductor.set_stream(null, 0.0)
	BeatConductor.set_process(false)

	washer = (load(WASHER_SCENE) as PackedScene).instantiate() as CosmicWasher
	add_child_autofree(washer)
	washer.set_process(false)
	washer.configure(&"washer_nw", Rect2(36, 32, 48, 48), Vector2(60, 80), &"red")

	chute = (load(CHUTE_SCENE) as PackedScene).instantiate() as DeliveryChute
	add_child_autofree(chute)
	chute.set_process(false)
	chute.configure(Rect2(144, 74, 32, 32), Vector2(160, 90))

	item = (load(Config.SCENE_LAUNDRY_ITEM) as PackedScene).instantiate() as LaundryItem
	item.setup(&"rocky", &"red", &"solid", false)
	add_child_autofree(item)
	item.global_position = Vector2(400.0, 500.0)


func after_each() -> void:
	BeatConductor.stop()
	BeatConductor.set_process(_beat_processing)


func test_wash_then_deliver_pays_once() -> void:
	assert_true(washer.try_accept(item, RhythmEvaluator.Grade.PERFECT))
	assert_eq(washer.get_loaded_items().size(), 1)
	assert_false(item.visible, "the drum holds the item")
	assert_true(washer.strike(RhythmEvaluator.Grade.PERFECT), "the strike starts the wash")

	# The rocky wash is 6 s and the PERFECT throw already took 3 s off at insertion.
	washer.tick(3.2)
	assert_eq(washer.get_state(), WasherFSM.State.DONE, "the cycle completed")
	assert_true(item.is_clean, "the item came out clean")
	assert_eq(GameState.washed_count, 1, "one wash counted")

	washer.tick(WasherFSM.DONE_SETTLE_S + 0.1)
	assert_true(item.visible, "the clean item is back in the room")
	assert_eq(washer.get_loaded_items().size(), 0)

	assert_true(chute.try_deliver(item), "a clean item delivers")
	assert_eq(GameState.delivered_count, 1)
	assert_eq(GameState.score, 100, "rocky is worth 100 at x1")
	assert_almost_eq(GameState.stability, 53.0, 0.001, "+3 for the delivery")
	assert_eq(GameState.washed_count, 1, "delivery never double-counts the wash")
	assert_true(item.is_queued_for_deletion(), "the item leaves the room")

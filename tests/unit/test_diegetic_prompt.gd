extends GutTest
## DiegeticLayer teaching contract: the contextual prompt and the held-item chip are what
## replace the deleted instruction strip (docs/UX_BIBLE.md §6.5–§6.6, docs/HUD.md).

const Fakes := preload("res://tests/unit/support/diegetic_fakes.gd")
const LAYER_SCENE := preload("res://scenes/ui/DiegeticLayer.tscn")

var world: Fakes.World
var layer: Node2D


func before_each() -> void:
	GameState.reset(22)
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)
	BeatConductor.set_process(false)
	Settings.reduce_motion = false
	world = Fakes.World.new()
	world.name = "DiegeticPromptWorld"
	add_child_autofree(world)
	layer = null


func after_each() -> void:
	Settings.reduce_motion = false
	BeatConductor.stop()
	BeatConductor.set_process(true)


func _add_layer() -> Node2D:
	layer = LAYER_SCENE.instantiate() as Node2D
	world.add_child(layer)
	return layer


# --- Contextual prompt ------------------------------------------------------


func test_prompt_is_silent_with_a_bare_floor() -> void:
	world.add_player()
	world.add_washer(Vector2(900, 360), &"solid")
	_add_layer()
	assert_eq(layer.prompt_text(), "", "no item, no washer to hit: nothing to say")


func test_prompt_offers_grab_within_the_grab_radius() -> void:
	world.add_player()
	world.add_item(Vector2(700, 360))
	_add_layer()
	assert_eq(layer.prompt_text(), "ESPACIO · AGARRAR")
	var already_held: Fakes.FakeItem = world.add_item(Vector2(640 + Config.GRAB_RADIUS + 8.0, 400))
	already_held.is_held = true
	layer.refresh_now()
	assert_eq(
		layer.prompt_text(), "ESPACIO · AGARRAR", "an item someone else holds is not a target"
	)


func test_prompt_switches_to_throw_when_carrying() -> void:
	world.add_player()
	_add_layer()
	world.hold(world.add_item(Vector2(700, 360)))
	layer.refresh_now()
	assert_eq(layer.prompt_text(), "ESPACIO · LANZAR")


func test_prompt_offers_strike_near_a_turbulent_washer() -> void:
	world.add_player()
	var washer: Fakes.FakeWasher = world.add_washer(Vector2(700, 360), &"solid")
	washer.state = 2
	_add_layer()
	layer.refresh_now()
	assert_eq(layer.prompt_text(), "MANTÉN E")


func test_prompt_uses_gamepad_glyphs_when_a_pad_is_active() -> void:
	world.add_player()
	_add_layer()
	world.hold(world.add_item(Vector2(700, 360)))
	layer.refresh_now()
	assert_eq(layer.prompt_text(), "ESPACIO · LANZAR")
	layer.set_gamepad_hint(true)
	assert_eq(layer.prompt_text(), "Ⓐ · LANZAR", "the verb stays, the key becomes a button")
	layer.set_gamepad_hint(false)
	assert_eq(layer.prompt_text(), "ESPACIO · LANZAR")


func test_carried_item_chip_reads_colour_pattern_points() -> void:
	world.add_player()
	_add_layer()
	var item: Fakes.FakeItem = world.add_item(Vector2(688, 360))
	item.color = &"red"
	item.pattern = &"ringed"
	var data := ItemData.new()
	data.points = 100
	item.data = data
	world.hold(item)
	layer.refresh_now()
	assert_eq(layer.item_chip_text(), "ROJO · ANILLADO · 100")
	item.is_clean = true
	layer.refresh_now()
	assert_eq(
		layer.item_chip_text(), "ROJO · ANILLADO · 100", "LIMPIA is a separate tag, not a suffix"
	)


# --- Grade popup + turbulence -----------------------------------------------


func test_grade_popup_appears_at_the_action_for_380_ms() -> void:
	world.add_player(Vector2(500, 400))
	_add_layer()
	layer.show_grade(RhythmEvaluator.Grade.PERFECT)
	assert_eq(layer.grade_text(), "PERFECTO  +2 combo")
	assert_true(layer.is_grade_active())
	layer.advance(0.2)
	assert_true(layer.is_grade_active(), "still visible at 200 ms")
	layer.advance(0.2)
	assert_false(layer.is_grade_active(), "gone after 380 ms")


func test_grade_copy_matches_the_grade() -> void:
	world.add_player()
	_add_layer()
	layer.show_grade(RhythmEvaluator.Grade.GOOD)
	assert_eq(layer.grade_text(), "BIEN  +1 combo")
	layer.show_grade(RhythmEvaluator.Grade.MISS)
	assert_eq(layer.grade_text(), "FUERA DE RITMO")


func test_turbulence_path_targets_one_washer() -> void:
	world.add_player()
	var first: Fakes.FakeWasher = world.add_washer(Vector2(500, 360), &"solid")
	first.state = 2
	var second: Fakes.FakeWasher = world.add_washer(Vector2(900, 360), &"red")
	second.state = 2
	_add_layer()
	layer.refresh_now()
	assert_eq(layer.turbulence_target(), first, "only the nearest turbulent washer is signalled")
	first.state = 1
	layer.refresh_now()
	assert_eq(layer.turbulence_target(), second, "the next one takes over")


func test_no_turbulence_path_when_everything_is_calm() -> void:
	world.add_player()
	world.add_washer(Vector2(500, 360), &"solid")
	_add_layer()
	layer.refresh_now()
	assert_null(layer.turbulence_target())

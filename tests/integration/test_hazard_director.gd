extends GutTest
## HazardDirector (D045/D046): the damage test, the on-beat dodge reward, i-frames and the
## void meter. The director is driven directly instead of waiting for a real measure, so
## these are fast and deterministic.

var _director: HazardDirector
var _player: Node2D
var _root: Node2D


## Minimal stand-in for Pip: the director only reads `global_position` and, for the gravity
## pocket, calls `set_input_inverted`.
class FakePlayer:
	extends CharacterBody2D
	var input_inverted := false
	var field_velocity := Vector2.ZERO
	var field_speed_scale := 1.0

	func set_input_inverted(on: bool) -> void:
		input_inverted = on


func before_each() -> void:
	GameState.reset(1234)
	GameState.stability_protected = false
	BeatConductor.stop()
	_player = FakePlayer.new()
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	_player.add_child(shape)
	add_child_autofree(_player)
	_root = Node2D.new()
	add_child_autofree(_root)
	_director = HazardDirector.new()
	add_child_autofree(_director)
	_director.setup(_player, _root, 99, Config.Difficulty.STANDARD)
	_director.advance_shift_time(60.0)
	_director.set_enabled(true)


func after_each() -> void:
	GameState.reset(1234)
	BeatConductor.stop()


## The live typed array the director uses; appending is the only way to inject without
## fighting the `Array[Dictionary]` type.
func _pending() -> Array:
	return _director.get("_pending") as Array


func _inject(kind: int, center: Vector2, exit_time: float = -1.0) -> void:
	(
		_pending()
		. append(
			{
				"strike_beat": 0,
				"kind": kind,
				"center": center,
				"angle": 0.0,
				"node": null,
				"exit_time": exit_time,
				"was_inside": true,
			}
		)
	)


func test_hazard_inside_the_zone_damages_stability() -> void:
	var center := Vector2(400, 300)
	_player.global_position = center
	_inject(Config.HazardKind.METEOR, center)
	_director.call("_on_beat", 0)
	assert_almost_eq(GameState.stability, 100.0 + Config.DIFFICULTY_HIT_DAMAGE[1], 0.001)


func test_a_hit_fires_the_feedback_channels() -> void:
	var center := Vector2(400, 300)
	_player.global_position = center
	Juice.release_motion()
	_inject(Config.HazardKind.METEOR, center)
	_director.call("_on_beat", 0)
	assert_true(Juice.is_hitstopping(), "the hit freezes the frame for a beat")
	assert_gt(Juice.trauma, 0.0, "the camera shakes")
	var chip := _player.get_node_or_null("FeedbackChip")
	assert_not_null(chip, "a -N chip floats over Pip")


func test_gravity_pocket_never_damages() -> void:
	var center := Vector2(400, 300)
	_player.global_position = center
	_inject(Config.HazardKind.GRAVITY_POCKET, center)
	_director.call("_on_beat", 0)
	assert_eq(GameState.stability, 100.0, "disorientation is not damage")
	assert_true(_player.get("input_inverted") == true, "the pocket flips the axes")


func test_leaving_on_the_beat_pays_a_perfect_dodge() -> void:
	var center := Vector2(400, 300)
	_player.global_position = center + Vector2(500, 0)
	_inject(Config.HazardKind.METEOR, center, BeatConductor.get_song_time())
	_director.call("_on_beat", 0)
	assert_eq(GameState.stability, 100.0)
	assert_eq(GameState.score, Config.HAZARD_DODGE_POINTS)
	var chip := _player.get_node_or_null("FeedbackChip")
	assert_not_null(chip, "the +25 chip confirms the dodge")


func test_leaving_early_is_safe_but_pays_nothing() -> void:
	var center := Vector2(400, 300)
	_player.global_position = center + Vector2(500, 0)
	_inject(Config.HazardKind.METEOR, center, BeatConductor.get_song_time() - 1.0)
	_director.call("_on_beat", 0)
	assert_eq(GameState.stability, 100.0)
	assert_eq(GameState.score, 0, "only a dodge on the beat scores")


func test_iframes_swallow_the_second_hit() -> void:
	var center := Vector2(400, 300)
	_player.global_position = center
	_inject(Config.HazardKind.METEOR, center)
	_director.call("_on_beat", 0)
	var after_first := GameState.stability
	_inject(Config.HazardKind.METEOR, center)
	_director.call("_on_beat", 0)
	assert_eq(GameState.stability, after_first, "one hit, one penalty")


func test_well_force_points_inward_and_stops_at_the_edge() -> void:
	var center := Vector2(500, 500)
	var radius := 100.0
	var inside := HazardDirector.well_force(center, center + Vector2(50, 0), 400.0, radius)
	assert_lt(inside.x, 0.0, "the pull points back at the centre")
	assert_almost_eq(inside.length(), 200.0, 0.5, "linear falloff: half the radius, half the force")
	assert_eq(
		HazardDirector.well_force(center, center + Vector2(radius + 1.0, 0), 400.0, radius),
		Vector2.ZERO,
		"nothing outside the gravity radius"
	)


func test_vent_pulls_the_player_and_slows_it() -> void:
	var center := Vector2(400, 300)
	_player.global_position = center + Vector2(50, 0)
	_inject(Config.HazardKind.VOID_VENT, center)
	_director.call("_on_beat", 0)
	assert_eq((_director.get("_fields") as Array).size(), 1, "a gravity well is live")
	_player.velocity = Vector2.ZERO
	_director.call("_physics_process", 0.1)
	assert_lt(
		(_player.get("field_velocity") as Vector2).x, 0.0, "the well drags Pip toward the centre"
	)
	assert_almost_eq(
		float(_player.get("field_speed_scale")),
		Config.HAZARD_VENT_SLOW_SCALE,
		0.001,
		"inside the damage radius Pip moves slower"
	)


func test_vent_pulls_items_toward_its_centre() -> void:
	var center := Vector2(400, 300)
	_player.global_position = center + Vector2(400, 0)
	var body := RigidBody2D.new()
	body.mass = 1.0
	body.gravity_scale = 0.0
	body.add_to_group(Config.GROUP_ITEMS)
	add_child_autofree(body)
	body.global_position = center + Vector2(60, 0)
	_inject(Config.HazardKind.VOID_VENT, center)
	_director.call("_on_beat", 0)
	await wait_physics_frames(4)
	assert_lt(body.linear_velocity.x, 0.0, "the well bends the throw toward its centre")


func test_staying_in_the_void_keeps_hurting() -> void:
	var center := Vector2(400, 300)
	_player.global_position = center
	_inject(Config.HazardKind.VOID_VENT, center)
	_director.call("_on_beat", 0)
	var after_strike := GameState.stability
	for _i in range(12):
		_director.call("_process", 0.2)
	_director.call("_physics_process", 0.6)
	assert_lt(GameState.stability, after_strike, "standing in the well costs more than one hit")


func test_void_rises_delivery_lowers_and_collapse_resets() -> void:
	var before: float = _director.void_value
	_director.call("_advance_void", 10.0)
	assert_gt(_director.void_value, before, "the meter climbs on its own")
	_director.call("_on_delivery")
	assert_lt(_director.void_value, before + 10.0, "a delivery buys relief")
	_director.void_value = 99.0
	_director.call("_advance_void", 10.0)
	assert_almost_eq(_director.void_value, Config.VOID_COLLAPSE_RESET, 0.001)
	assert_true(_director.is_collapsing())


func test_no_hazards_before_the_onboarding_window() -> void:
	_director.advance_shift_time(5.0)
	_pending().clear()
	_director.call("_on_measure", 0)
	assert_eq(_pending().size(), 0)
	_director.set_enabled(false)
	_director.advance_shift_time(60.0)
	_director.call("_on_measure", 0)
	assert_eq(_pending().size(), 0, "disabled means no hazards")


func test_planned_hazard_telegraphs_before_it_strikes() -> void:
	_director.advance_shift_time(60.0)
	_pending().clear()
	# STANDARD plans on half the measures, so twelve tries is effectively deterministic.
	for measure: int in range(12):
		_director.call("_on_measure", measure)
		if _pending().size() > 0:
			break
	assert_gt(_pending().size(), 0, "a hazard is planned within twelve measures")
	var entry: Dictionary = _pending()[0]
	var warning := Config.DIFFICULTY_WARNING_BEATS[Config.Difficulty.STANDARD]
	assert_gte(int(entry["strike_beat"]), warning, "the strike is at least two beats ahead")
	assert_true(is_instance_valid(entry["node"]), "a visual telegraph was instantiated")

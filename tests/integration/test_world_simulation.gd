extends GutTest
## Virtual 480 s integration run (AGENTS §A8 M3, CONTRACTS §7).
##
## Proves the whole M3 chain without rendering or real time: the phase table drives the
## schedule, the director replays it, the sandbox places items on the belts and the grinder
## sits where the belt ends.

const SEED := 1234
const SCENE_PATH := "res://scenes/dev/WorldSandbox.tscn"
## Virtual step of the shift clock, in seconds.
const STEP := 0.25
const TICK := 1.0 / 60.0

var sandbox: WorldSandbox


func before_each() -> void:
	GameState.reset(SEED)
	sandbox = load(SCENE_PATH).instantiate() as WorldSandbox
	assert_not_null(sandbox, "the sandbox scene must build the environment")
	add_child_autofree(sandbox)


# --- counting ---------------------------------------------------------------


func test_accounting_run_matches_the_acceptance_counts() -> void:
	var director := SpawnDirector.new()
	var report := director.simulate(Config.SHIFT_DURATION_S, SEED)
	director.free()

	assert_eq(report.per_phase, [17, 24, 29, 13], "per-phase spawn counts")
	assert_almost_eq(float(report.total), 83.0, 2.0, "total spawns in the shift")
	assert_almost_eq(float(report.first_time), Config.PHASE_SPAWN_INTERVAL_S[0], 0.001)
	assert_true(float(report.last_time) < Config.SHIFT_DURATION_S, "the last spawn is inside")
	assert_eq((report.convoy as Array).size(), Config.FINAL_LOAD_HEAVY_COUNT + 1)


func test_live_run_spawns_the_whole_schedule() -> void:
	var started := Time.get_ticks_msec()
	while sandbox.shift_time + STEP < Config.SHIFT_DURATION_S:
		sandbox.step(STEP)
		_release_items()
	sandbox.director.advance_to(Config.SHIFT_DURATION_S)
	var elapsed_ms := Time.get_ticks_msec() - started

	assert_eq(sandbox.director.spawned_count_by_phase, [17, 24, 29, 13])
	assert_lt(elapsed_ms, 60000, "the virtual shift must finish in well under a minute")


func test_no_spawns_after_the_shift_ends() -> void:
	while sandbox.shift_time + STEP < Config.SHIFT_DURATION_S:
		sandbox.step(STEP)
		_release_items()
	sandbox.director.advance_to(Config.SHIFT_DURATION_S)
	var final_counts := sandbox.director.spawned_count_by_phase.duplicate()

	sandbox.director.advance_to(Config.SHIFT_DURATION_S * 4.0)
	assert_eq(sandbox.director.spawned_count_by_phase, final_counts, "480 s is the hard stop")


func test_items_are_placed_on_the_running_belt() -> void:
	while sandbox.director.spawned_count_by_phase[0] == 0:
		sandbox.step(STEP)
	var items := sandbox.director.get_node_or_null(^"Items")
	assert_not_null(items, "spawned items live under Items")
	assert_gt(items.get_child_count(), 0)
	var item := items.get_child(0) as Node2D
	var north: ConveyorBelt = sandbox.belts["belt_north"]
	assert_true(
		absf(item.position.y - north.position.y) <= north.world_size().y,
		"the first item starts on the north belt"
	)


func test_every_belt_runs_in_the_final_phase() -> void:
	sandbox.force_phase(3)
	for belt: ConveyorBelt in sandbox.belts.values():
		assert_true(belt.is_active(), "%s runs the final load" % belt.belt_id)


# --- belt -> shredder handoff -----------------------------------------------


func test_north_belt_delivers_its_items_to_the_grinder() -> void:
	var belt: ConveyorBelt = sandbox.belts["belt_north"]
	var shredder: Shredder = sandbox.shredders["shredder_north"]
	var item := (
		sandbox.director.stub_factory.call(
			{"item_id": &"rocky", "color": &"red", "pattern": &"solid"}
		)
		as RigidBody2D
	)
	assert_not_null(item, "the sandbox stub factory produces items")
	add_child_autofree(item)
	item.position = belt.position - Vector2(belt.world_size().x * 0.5, 0.0) + Vector2(8.0, 0.0)

	var start := item.position
	var exit_x := belt.position.x + belt.world_size().x * 0.5
	var ticks := 0
	while item.position.x < exit_x and ticks < 900:
		belt.apply_to_body(item, TICK)
		item.position += item.linear_velocity * TICK
		ticks += 1

	assert_gt(item.position.x, start.x, "the belt moved the item downstream")
	assert_true(item.position.x >= exit_x, "the item crossed the whole belt")
	var exit_rect := Rect2(
		Vector2(exit_x - 8.0, belt.position.y - belt.world_size().y * 0.5),
		Vector2(16.0, belt.world_size().y)
	)
	assert_true(
		_circle_meets_rect(shredder.position, shredder.radius(), exit_rect),
		"the grinder overlaps the belt exit, so nothing escapes"
	)
	assert_true(shredder.is_item_body(item))
	var before := GameState.stability
	assert_true(shredder.consume(item))
	assert_almost_eq(
		GameState.stability, before + Config.STABILITY_FELL_OFF_BELT, 0.001, "the fall costs 8"
	)
	assert_eq(GameState.dropped_count, 1)


# --- helpers ----------------------------------------------------------------


func _circle_meets_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(
		clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y)
	)
	return closest.distance_to(center) <= radius


func _release_items() -> void:
	# The loop runs without frames, so deferred frees would never resolve: delete now.
	var items := sandbox.director.get_node_or_null(^"Items")
	if items == null:
		return
	for item: Node in items.get_children():
		items.remove_child(item)
		item.free()

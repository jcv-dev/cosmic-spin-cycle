class_name SpawnDirector
extends Node
## Replays a [SpawnSchedule] against game time and instantiates the items (GDD §2.5).
##
## The pure schedule decides *what* spawns and *when*; this node only owns the cursor, the
## live-item cap, the `Items` parent and belt activation. Because the schedule is pure, the
## director can also run in "accounting" mode (no item scene, no tree): every accepted event
## is counted but nothing is instantiated. That is what `simulate()` uses headlessly.
##
## `item_scene` defaults to [constant Config.SCENE_LAUNDRY_ITEM] when that scene exists, so
## M3 works before M2 lands: tests and the sandbox inject `stub_factory` instead.

## Emitted for every item actually instantiated.
signal item_spawned(item: Node)
## Emitted when game time crosses into a new phase (or [method force_phase] is used).
signal phase_changed(index: int)
## Emitted once when the schedule's last event has been consumed.
signal schedule_finished

## Item scene to instantiate. Falls back to `Config.SCENE_LAUNDRY_ITEM` when loadable.
@export var item_scene: PackedScene
## Spawn `Items` parent; resolved to a child named `Items` when left empty.
@export var items_parent_path: NodePath
## Fallback world position for a spawned item (north belt dispenser, world px).
@export var spawn_position := Vector2(336.0, 72.0)
## Phase data. Loaded from `data/phases.tres` when left empty.
@export var phase_table: PhaseTable
## Optional `Callable(event: Dictionary, phase: PhaseData) -> Vector2`, so the sandbox can
## place each item on the belt that is actually running.
var position_resolver: Callable = Callable()
## Optional `Callable(event: Dictionary) -> Node`; when valid it overrides `item_scene`
## (tests, stub sandbox, headless runs).
var stub_factory: Callable = Callable()

## Spawn count per phase; the M3 acceptance metric.
var spawned_count_by_phase: Array[int] = [0, 0, 0, 0]
## Items skipped because [constant Config.MAX_ALIVE_ITEMS] was reached.
var skipped_count := 0
## Sorted events of the current run.
var schedule: Array[Dictionary] = []

var items_parent: Node
var is_running := false
var current_phase := 0
var time := 0.0

var _cursor := 0
var _alive: Array[Node] = []
var _finished_emitted := false


func _ready() -> void:
	if phase_table == null:
		phase_table = PhaseTable.load_default()
	if item_scene == null and ResourceLoader.exists(Config.SCENE_LAUNDRY_ITEM):
		item_scene = load(Config.SCENE_LAUNDRY_ITEM) as PackedScene


# --- public API (CONTRACTS §4) ----------------------------------------------


## Builds the schedule for `seed` and rewinds to t = 0.
func start(seed: int) -> void:
	if phase_table == null:
		phase_table = PhaseTable.load_default()
	schedule = SpawnSchedule.build(phase_table, seed)
	_cursor = 0
	time = 0.0
	is_running = true
	skipped_count = 0
	_alive.clear()
	_finished_emitted = false
	var phase_count := _phase_count()
	spawned_count_by_phase = []
	spawned_count_by_phase.resize(phase_count)
	current_phase = -1
	_set_phase(0)


## Stops consuming the schedule. Advancing afterwards is a no-op until the next `start()`.
func stop() -> void:
	is_running = false


## Consumes every event up to `t` seconds of game time.
##
## Idempotent: calling it again with the same (or an earlier) time spawns nothing new.
func advance_to(t: float) -> void:
	if not is_running:
		return
	var target := maxf(t, time)
	_prune_alive()
	while _cursor < schedule.size():
		var event := schedule[_cursor]
		if float(event.time) > target:
			break
		_cursor += 1
		_spawn_event(event)
	time = target
	if phase_table != null:
		_set_phase(phase_table.phase_index_at(target))
	if _cursor >= schedule.size() and not _finished_emitted:
		_finished_emitted = true
		schedule_finished.emit()


## Moves the cursor to the first event after `t` without spawning anything.
##
## Used by the sandbox when a forced phase jump must not replay the phases it skips.
func seek(t: float) -> void:
	if not is_running:
		return
	var target := maxf(t, 0.0)
	var index := 0
	while index < schedule.size() and float(schedule[index].time) <= target:
		index += 1
	_cursor = index
	time = target
	_finished_emitted = false
	if phase_table != null:
		_set_phase(phase_table.phase_index_at(target))


## Jumps the active phase without moving the clock (sandbox keys 1-4).
func force_phase(index: int) -> void:
	if phase_table == null:
		return
	var entry := phase_table.phase(index)
	if entry == null:
		return
	_set_phase(entry.index)


## Number of live (valid, not freed) items, capped by `Config.MAX_ALIVE_ITEMS`.
func alive_count() -> int:
	_prune_alive()
	return _alive.size()


## Runs the whole schedule headlessly and returns the report dictionary.
##
## Works without a scene tree: when no item scene or stub factory is available the events
## are only counted, which is how `tools/sim_run.gd` and the integration test stay fast.
func simulate(duration: float, seed: int = 1) -> Dictionary:
	start(seed)
	advance_to(duration)
	var summary := SpawnSchedule.summarize(schedule, _phase_count())
	summary["spawned"] = spawned_count_by_phase.duplicate()
	summary["alive"] = alive_count()
	summary["skipped"] = skipped_count
	summary["duration"] = duration
	return summary


# --- spawning ---------------------------------------------------------------


func _spawn_event(event: Dictionary) -> void:
	var phase_index := int(event.get("phase", 0))
	if alive_count() >= Config.MAX_ALIVE_ITEMS:
		skipped_count += 1
		return
	var item := _instantiate(event)
	if item == null:
		# Accounting mode: count the event without a node.
		_count_spawn(phase_index)
		return
	_count_spawn(phase_index)
	if item is Node2D:
		(item as Node2D).position = _position_for(event)
	_tag(item, event)
	var parent := _resolve_items_parent()
	if parent != null:
		parent.add_child(item)
	if item.is_inside_tree():
		item.add_to_group(Config.GROUP_ITEMS)
	_alive.append(item)
	item_spawned.emit(item)


func _instantiate(event: Dictionary) -> Node:
	# An explicitly injected stub/factory always wins, so tests and the sandbox stay
	# independent of the shipped item scene.
	if stub_factory.is_valid():
		var made: Variant = stub_factory.call(event)
		return made as Node
	if item_scene != null:
		return item_scene.instantiate()
	return null


func _tag(item: Node, event: Dictionary) -> void:
	var item_id := StringName(str(event.get("item_id", "")))
	var color := StringName(str(event.get("color", "")))
	var pattern := StringName(str(event.get("pattern", "")))
	if item.has_method(&"setup"):
		item.call(&"setup", item_id, color, pattern)
	item.set_meta(&"item_id", item_id)
	item.set_meta(&"color", color)
	item.set_meta(&"pattern", pattern)
	item.set_meta(&"phase", int(event.get("phase", 0)))


func _position_for(event: Dictionary) -> Vector2:
	if position_resolver.is_valid():
		var entry: PhaseData = null
		if phase_table != null:
			entry = phase_table.phase(int(event.get("phase", 0)))
		var resolved: Variant = position_resolver.call(event, entry)
		if resolved is Vector2:
			return resolved
	return spawn_position


func _count_spawn(phase_index: int) -> void:
	while spawned_count_by_phase.size() <= phase_index:
		spawned_count_by_phase.append(0)
	spawned_count_by_phase[phase_index] += 1


func _resolve_items_parent() -> Node:
	if items_parent != null and is_instance_valid(items_parent):
		return items_parent
	if not is_inside_tree():
		return null
	if items_parent_path != NodePath() and not items_parent_path.is_empty():
		items_parent = get_node_or_null(items_parent_path)
		if items_parent != null:
			return items_parent
	var existing := get_node_or_null(^"Items")
	if existing == null:
		var created := Node2D.new()
		created.name = "Items"
		add_child(created)
		existing = created
	items_parent = existing
	return items_parent


func _prune_alive() -> void:
	if _alive.is_empty():
		return
	var kept: Array[Node] = []
	for item in _alive:
		if is_instance_valid(item) and not item.is_queued_for_deletion():
			kept.append(item)
	_alive = kept


func _set_phase(index: int) -> void:
	if index == current_phase:
		return
	current_phase = index
	if phase_table != null:
		_activate_belts(phase_table.phase(index))
	phase_changed.emit(index)


func _activate_belts(phase: PhaseData) -> void:
	if not is_inside_tree() or phase == null:
		return
	var belts := get_tree().get_nodes_in_group(Config.GROUP_BELTS)
	for belt in belts:
		if belt == null or not belt.has_method(&"set_active"):
			continue
		var belt_id := StringName(str(belt.get(&"belt_id")))
		belt.call(&"set_active", phase.active_belts.has(belt_id))


func _phase_count() -> int:
	if phase_table == null:
		return Config.PHASE_BPM.size()
	return maxi(phase_table.size(), 1)

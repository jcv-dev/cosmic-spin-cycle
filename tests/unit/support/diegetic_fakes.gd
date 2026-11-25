extends RefCounted
## Test doubles for the world-space layer: they implement only the documented duck-typed API
## (`get_requirement`, `get_state`, `is_locked`, `get_mouth_world`, `get_aim_direction`,
## `get_hold_position`, `try_deliver`) and register in the real groups, so the DiegeticLayer
## is exercised exactly as it will be against CosmicWasher / DeliveryChute.
##
## `World` is a one-call scene graph builder: add it to the tree, then spawn actors in the
## order that matters (the layer rescans groups on `_ready`).


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


class World:
	extends Node2D
	var player: FakePlayer = null
	var washers: Array[FakeWasher] = []
	var chute: FakeChute = null
	var items: Array[FakeItem] = []

	func add_player(at: Vector2 = Vector2(640, 360)) -> FakePlayer:
		player = FakePlayer.new()
		player.position = at
		add_child(player)
		return player

	func add_washer(at: Vector2, requirement: StringName = &"red") -> FakeWasher:
		var washer := FakeWasher.new()
		washer.position = at
		washer.requirement = requirement
		add_child(washer)
		washers.append(washer)
		return washer

	func add_chute(at: Vector2) -> FakeChute:
		chute = FakeChute.new()
		chute.position = at
		add_child(chute)
		return chute

	func add_item(at: Vector2, color: StringName = &"red") -> FakeItem:
		var item := FakeItem.new()
		item.position = at
		item.color = color
		add_child(item)
		items.append(item)
		return item

	func hold(item: Node) -> void:
		if player != null:
			player.held_item = item


## Stand-in for the real layer when a test only needs the HUD's forwarding side.
class FakeDiegetic:
	extends Node2D
	var last_grade := -1
	var calls := 0

	func _ready() -> void:
		add_to_group(&"diegetic")

	func show_grade(grade: int) -> void:
		last_grade = grade
		calls += 1


## Minimal shift level: a Node2D that exposes `get_shift_time`, which is what the HUD uses to
## decide that a world exists to host a diegetic layer.
class FakeLevel:
	extends Node2D
	var mounted_children := 0

	func _ready() -> void:
		child_entered_tree.connect(_on_child_entered)

	func get_shift_time() -> float:
		return 0.0

	func _on_child_entered(_child: Node) -> void:
		mounted_children += 1

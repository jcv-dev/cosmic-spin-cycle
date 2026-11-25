class_name MagneticGrabber
extends Node2D
## Magnetic glove: finds and holds exactly one laundry item at a time.
##
## The grabber owns the ownership handshake; the item owns the motion. While held, a
## `LaundryItem` steers itself in `_integrate_forces` toward the player's hold point and
## only collides with the world, so two held items can never push each other around.

signal target_changed(item: Node)

var held_item: Node = null
var player: Node2D = null


func _ready() -> void:
	player = get_parent() as Node2D


## Nearest item in the `items` group within `radius` of `origin`, or null.
##
## Boundary rule: distance <= radius. The contract tests 63.9 (inside) and 64.1 (outside).
func find_target(origin: Vector2, radius: float) -> Node:
	var best: Node = null
	var best_distance := radius + 0.0001
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group(Config.GROUP_ITEMS):
		var item := node as Node2D
		if item == null or not is_instance_valid(item):
			continue
		if item == held_item:
			continue
		if _is_item_held(item):
			continue
		var distance := origin.distance_to(item.global_position)
		if distance < best_distance:
			best_distance = distance
			best = item
	return best


func grab(item: Node) -> bool:
	if held_item != null or item == null or not is_instance_valid(item):
		return false
	if not item.has_method("begin_hold"):
		return false
	held_item = item
	item.begin_hold(player)
	target_changed.emit(item)
	return true


## Releases the held item (no throw impulse). Returns the item for convenience.
func drop() -> Node:
	var item := held_item
	if item == null:
		return null
	held_item = null
	if is_instance_valid(item) and item.has_method("end_hold"):
		item.end_hold()
	target_changed.emit(null)
	return item


## World-space point the held item should settle at; mirrors the player's hold anchor.
func hold_position() -> Vector2:
	if player == null:
		return global_position
	if player.has_method("get_hold_position"):
		var value: Variant = player.call("get_hold_position")
		if value is Vector2:
			return value
	return player.global_position + Vector2.DOWN * Config.HOLD_DISTANCE


func is_holding() -> bool:
	return held_item != null


func _is_item_held(item: Node2D) -> bool:
	var value: Variant = item.get("is_held")
	return value is bool and value

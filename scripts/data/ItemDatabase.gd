class_name ItemDatabase
extends Resource
## The five item definitions of GDD §6, loaded from `res://data/items.tres`.
##
## The database is a resource so balance can be tuned without code changes. Consumers use
## `load_default()` (cached) and never construct ItemData by hand in gameplay code.

const DEFAULT_PATH := "res://data/items.tres"

static var _default: ItemDatabase = null

@export var items: Array[ItemData] = []


## Item for `p_id`, or `null` when the id is unknown.
func get_item(p_id: StringName) -> ItemData:
	for item in items:
		if item != null and item.id == p_id:
			return item
	return null


func has_item(p_id: StringName) -> bool:
	return get_item(p_id) != null


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for item in items:
		if item != null:
			out.append(item.id)
	return out


## Loads and caches `res://data/items.tres`. Returns `null` only if the resource is broken,
## in which case callers must fall back to a safe default instead of crashing.
static func load_default() -> ItemDatabase:
	if _default == null:
		_default = load(DEFAULT_PATH) as ItemDatabase
	return _default

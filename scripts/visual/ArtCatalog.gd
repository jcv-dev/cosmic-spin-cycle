class_name ArtCatalog
extends RefCounted
## Loose sprite loader used by greybox scenes before the art pipeline lands.
##
## Returns null when the sprite does not exist; every visual node must then draw a flat
## placeholder in palette colours. When `assets/sprites/<id>.png` is imported, the same
## script picks it up with no code change.

const SPRITE_DIR := "res://assets/sprites/"

static var _cache: Dictionary = {}


static func sprite_path(id: String) -> String:
	return SPRITE_DIR + id + ".png"


static func has_sprite(id: String) -> bool:
	return ResourceLoader.exists(sprite_path(id))


static func texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id] as Texture2D
	if not has_sprite(id):
		return null
	var tex := load(sprite_path(id)) as Texture2D
	_cache[id] = tex
	return tex

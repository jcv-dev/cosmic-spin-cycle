class_name SpriteSheet
extends RefCounted
## Runtime loader for the frozen Track-B contract: `<id>.png` + `<id>.json`.
##
## Builds SpriteFrames/AtlasTextures on demand so placeholder art can be swapped by
## dropping files into assets/sprites/ — no code changes. Returns null when the pair is
## missing or malformed; callers must fall back to flat palette art.

const DIR := "res://assets/sprites/"

static var _frames_cache: Dictionary = {}
static var _json_cache: Dictionary = {}


static func json_path(id: String) -> String:
	return DIR + id + ".json"


static func has_sheet(id: String) -> bool:
	return (
		ResourceLoader.exists(ArtCatalog.sprite_path(id)) and FileAccess.file_exists(json_path(id))
	)


static func load_data(id: String) -> Dictionary:
	if _json_cache.has(id):
		return _json_cache[id] as Dictionary
	if not FileAccess.file_exists(json_path(id)):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path(id)))
	if not (parsed is Dictionary):
		push_warning("SpriteSheet: invalid JSON for '%s'" % id)
		return {}
	_json_cache[id] = parsed
	return parsed as Dictionary


static func frame_size(id: String) -> Vector2i:
	var data := load_data(id)
	var size: Array = data.get("frame_size", [])
	if size.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(size[0]), int(size[1]))


static func pivot(id: String) -> Vector2:
	var data := load_data(id)
	var p: Array = data.get("pivot", [])
	if p.size() != 2:
		return Vector2.ZERO
	return Vector2(float(p[0]), float(p[1]))


static func art_scale(id: String) -> int:
	var data := load_data(id)
	return int(data.get("scale", Config.ART_SCALE))


static func animation_names(id: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var data := load_data(id)
	var anims: Dictionary = data.get("animations", {})
	for key in anims.keys():
		out.append(StringName(key))
	return out


static func sprite_frames(id: String) -> SpriteFrames:
	if _frames_cache.has(id):
		return _frames_cache[id] as SpriteFrames
	if not has_sheet(id):
		return null
	var data := load_data(id)
	var texture := ArtCatalog.texture(id)
	if texture == null:
		return null
	var cell := frame_size(id)
	if cell.x <= 0 or cell.y <= 0:
		return null

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var anims: Dictionary = data.get("animations", {})
	for key in anims.keys():
		var anim: Dictionary = anims[key]
		var anim_name := StringName(key)
		var row := int(anim.get("row", 0))
		var count := maxi(int(anim.get("frames", 1)), 1)
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, float(anim.get("fps", 8.0)))
		frames.set_animation_loop(anim_name, bool(anim.get("loop", true)))
		for i in range(count):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * cell.x, row * cell.y, cell.x, cell.y)
			frames.add_frame(anim_name, atlas)
	_frames_cache[id] = frames
	return frames


## AtlasTexture for a single frame; used by static Sprite2D visuals.
static func frame_texture(id: String, animation: StringName, frame: int = 0) -> AtlasTexture:
	var frames := sprite_frames(id)
	if frames == null:
		return null
	if not frames.has_animation(animation):
		if frames.get_animation_names().is_empty():
			return null
		animation = StringName(frames.get_animation_names()[0])
	var count := frames.get_frame_count(animation)
	if count <= 0:
		return null
	var tex := frames.get_frame_texture(animation, clampi(frame, 0, count - 1))
	return tex as AtlasTexture


## Configures an AnimatedSprite2D for the contract (nearest, no rotation, feet pivot).
static func configure(sprite: AnimatedSprite2D, id: String, initial: StringName = &"") -> bool:
	var frames := sprite_frames(id)
	if frames == null:
		return false
	sprite.sprite_frames = frames
	var names := frames.get_animation_names()
	if names.is_empty():
		return false
	sprite.centered = false
	sprite.offset = -pivot(id)
	sprite.scale = Vector2.ONE * float(art_scale(id))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var anim := initial
	if anim == &"" or not frames.has_animation(anim):
		anim = StringName(names[0])
	sprite.animation = anim
	sprite.play()
	return true


static func clear_cache() -> void:
	_frames_cache.clear()
	_json_cache.clear()

class_name ItemVisual
extends Node2D
## Upright visual for a laundry item, drawn from the 30-colour palette.
##
## Track B ships `assets/sprites/<id>.png` + `.json`; when that pair exists this node shows
## the requested variant cell as a sprite. When it does not (greybox, CI, screenshots on a
## fresh clone) it falls back to a distinct flat silhouette per item id. The owner keeps
## this node unrotated: pixel art must never spin with the RigidBody2D.

const VISUAL_SCALE := 1.6
const OUTLINE_WIDTH := 2.0
const OUTLINE_MIX := 0.55
const PATTERN_SHIFT := 0.3
const SPARKLE_COLOR := Color("#5CFF8A")
const SPARKLE_COUNT := 3
const SPRITE_DIR := "res://assets/sprites/"

static var _sheet_cache: Dictionary = {}

var _data: ItemData = null
var _color_id: StringName = &"red"
var _pattern_id: StringName = &"solid"
var _clean := false
var _has_sprite := false
var _sprite: Sprite2D = null


## Rebinds the visual to a data row and a world variant. Safe before the node enters the tree.
func configure(
	p_data: ItemData, p_color: StringName, p_pattern: StringName, p_clean: bool = false
) -> void:
	_data = p_data
	_color_id = p_color
	_pattern_id = p_pattern
	_clean = p_clean
	_setup_sprite()
	queue_redraw()


func set_clean(value: bool) -> void:
	_clean = value
	queue_redraw()


func is_clean() -> bool:
	return _clean


## Builds an AtlasTexture for one animation/frame of an imported sheet, or null when the
## art (or its JSON sidecar) is absent. Row and frame size come from the frozen §B6 schema.
static func frame_texture(sprite_id: String, animation: StringName) -> Texture2D:
	var tex := ArtCatalog.texture(sprite_id)
	if tex == null:
		return null
	var sheet := _read_sheet(sprite_id)
	if sheet.is_empty():
		return tex
	var animations: Variant = sheet.get("animations")
	if not animations is Dictionary:
		return tex
	var anims: Dictionary = animations
	if not anims.has(String(animation)):
		return tex
	var frame_size: Variant = sheet.get("frame_size", [tex.get_width(), tex.get_height()])
	var size := Vector2i(int(frame_size[0]), int(frame_size[1]))
	var anim: Variant = anims[String(animation)]
	if not anim is Dictionary:
		return tex
	var row := int((anim as Dictionary).get("row", 0))
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(Vector2i(0, row * size.y), size)
	return atlas


static func _read_sheet(sprite_id: String) -> Dictionary:
	if _sheet_cache.has(sprite_id):
		return _sheet_cache[sprite_id]
	var path := SPRITE_DIR + sprite_id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	_sheet_cache[sprite_id] = parsed
	return parsed as Dictionary


func _setup_sprite() -> void:
	if _data == null:
		return
	var animation: StringName = &"idle"
	if _data.special != ItemData.Special.GRAVITY_FIELD:
		animation = StringName("%s_%s" % [_color_id, _pattern_id])
	var texture := frame_texture(_data.sprite_id, animation)
	if texture == null:
		return
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sheet"
		add_child(_sprite)
	_sprite.texture = texture
	var frame_size := texture.get_size()
	var diameter := _data.radius * 2.0 * VISUAL_SCALE
	if frame_size.y > 0.0:
		var factor := diameter / frame_size.y
		_sprite.scale = Vector2.ONE * factor
	_has_sprite = true


func _draw() -> void:
	if _data == null:
		return
	if not _has_sprite:
		match _data.id:
			&"sock":
				_draw_sock()
			&"moon":
				_draw_moon()
			&"gas_giant":
				_draw_gas_giant()
			&"galaxy_core":
				_draw_core()
			_:
				_draw_rocky()
		_draw_pattern()
	if _clean:
		_draw_sparkles()


func _body_color() -> Color:
	if _data == null:
		return Color("#CDD3E8")
	return _data.tint_color


func _outline_color() -> Color:
	return _body_color().lerp(Color("#0B0C10"), OUTLINE_MIX)


func _radius() -> float:
	if _data == null:
		return 8.0
	return maxf(_data.radius, 6.0) * VISUAL_SCALE


func _draw_rocky() -> void:
	var r := _radius()
	var body := _body_color()
	draw_circle(Vector2.ZERO, r + OUTLINE_WIDTH, _outline_color())
	draw_circle(Vector2.ZERO, r, body)
	draw_circle(Vector2(-r * 0.34, -r * 0.3), r * 0.2, body.darkened(0.35))
	draw_circle(Vector2(r * 0.38, r * 0.12), r * 0.14, body.darkened(0.35))
	draw_circle(Vector2(-r * 0.05, r * 0.42), r * 0.1, body.darkened(0.25))


func _draw_sock() -> void:
	var r := _radius()
	var body := _body_color()
	var points := PackedVector2Array(
		[
			Vector2(-0.22, -1.0),
			Vector2(0.42, -1.0),
			Vector2(0.42, -0.15),
			Vector2(0.82, 0.18),
			Vector2(0.98, 0.58),
			Vector2(0.72, 0.9),
			Vector2(0.28, 0.94),
			Vector2(-0.02, 0.62),
			Vector2(-0.22, 0.2),
		]
	)
	var scaled := PackedVector2Array()
	for point in points:
		scaled.append(point * r)
	draw_colored_polygon(_scaled(scaled, 1.16), _outline_color())
	draw_colored_polygon(scaled, body)
	draw_rect(
		Rect2(Vector2(-0.22, -1.0) * r, Vector2(0.64, 0.28) * r), body.lightened(PATTERN_SHIFT)
	)


func _draw_moon() -> void:
	var r := _radius()
	var body := _body_color()
	draw_arc(
		Vector2.ZERO, r * 0.9, PI * 0.3, PI * 1.7, 24, _outline_color(), r * 0.58 + OUTLINE_WIDTH
	)
	draw_arc(Vector2.ZERO, r * 0.9, PI * 0.3, PI * 1.7, 24, body, r * 0.58)
	draw_circle(Vector2(r * 0.62, -r * 0.55), r * 0.1, body.lightened(PATTERN_SHIFT))
	draw_circle(Vector2(r * 0.36, r * 0.62), r * 0.07, body.lightened(PATTERN_SHIFT))


func _draw_gas_giant() -> void:
	var r := _radius()
	var body := _body_color()
	draw_circle(Vector2.ZERO, r + OUTLINE_WIDTH, _outline_color())
	draw_circle(Vector2.ZERO, r, body)
	var bands := [-0.5, 0.0, 0.5]
	for index in range(bands.size()):
		var y: float = bands[index] * r
		var half := sqrt(maxf(r * r - y * y, 0.0))
		var band_color := body.darkened(0.28) if index % 2 == 0 else body.lightened(0.18)
		draw_line(Vector2(-half, y), Vector2(half, y), band_color, r * 0.24)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, _outline_color(), OUTLINE_WIDTH)


func _draw_core() -> void:
	var r := _radius()
	var body := _body_color()
	draw_circle(Vector2.ZERO, r + OUTLINE_WIDTH, _outline_color())
	draw_circle(Vector2.ZERO, r, body.darkened(0.55))
	draw_circle(Vector2.ZERO, r * 0.78, body.darkened(0.75))
	draw_arc(Vector2.ZERO, r * 0.66, -2.6, 1.4, 22, body, r * 0.14)
	draw_arc(Vector2.ZERO, r * 0.4, 0.4, 4.2, 18, body.lightened(0.25), r * 0.12)
	draw_circle(Vector2.ZERO, r * 0.2, Color("#F4F6FC"))
	for index in range(4):
		var angle := TAU * float(index) / 4.0 + 0.4
		draw_circle(Vector2.from_angle(angle) * r * 0.9, r * 0.09, Color("#E040FB"))


func _draw_pattern() -> void:
	var r := _radius()
	var body := _body_color()
	var shade := body.lightened(PATTERN_SHIFT)
	match _pattern_id:
		&"ringed":
			draw_arc(Vector2.ZERO, r * 0.58, 0.0, TAU, 28, shade, OUTLINE_WIDTH)
		&"spotted":
			draw_circle(Vector2(-r * 0.42, -r * 0.36), r * 0.13, shade)
			draw_circle(Vector2(r * 0.34, -r * 0.1), r * 0.11, shade)
			draw_circle(Vector2(-r * 0.05, r * 0.48), r * 0.1, shade)


func _draw_sparkles() -> void:
	var r := _radius()
	for index in range(SPARKLE_COUNT):
		var angle := TAU * float(index) / float(SPARKLE_COUNT) + 0.6
		var center := Vector2.from_angle(angle) * (r + 5.0)
		var arm := 2.5
		draw_line(center - Vector2(arm, 0.0), center + Vector2(arm, 0.0), SPARKLE_COLOR, 1.5)
		draw_line(center - Vector2(0.0, arm), center + Vector2(0.0, arm), SPARKLE_COLOR, 1.5)


func _scaled(points: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point * factor)
	return out

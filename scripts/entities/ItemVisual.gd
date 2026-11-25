class_name ItemVisual
extends Node2D
## Upright visual for a laundry item, drawn from the 30-colour palette.
##
## Track B ships `assets/sprites/<id>.png` + `.json`; when that pair exists this node shows
## the requested variant cell as a sprite. When it does not (greybox, CI, screenshots on a
## fresh clone) it falls back to a distinct flat silhouette per item id. The owner keeps
## this node unrotated: pixel art must never spin with the RigidBody2D.
##
## Feel layer: a fake-height shadow (rotates and grows with altitude while the sprite stays
## upright), a 60 ms magnet pull on grab, a landing squash/ring, a 2-frame throw smear and
## the on-beat dotted guide toward the assisted washer mouth.

const OUTLINE_WIDTH := 2.0
const OUTLINE_MIX := 0.55
const PATTERN_SHIFT := 0.3
const SPARKLE_COLOR := Color("#5CFF8A")
const SPARKLE_COUNT := 3
const SPRITE_DIR := "res://assets/sprites/"
const SHADOW_COLOR := Color(0.043, 0.047, 0.063, 0.5)
## Light comes from the top-left, so the ground shadow sits down-right of the body.
const SHADOW_OFFSET := Vector2(3.0, 5.0)
const SHADOW_RADIUS_SCALE := 0.85
const SHADOW_FLATTEN := 0.38
const PULL_DURATION_S := 0.06
const PULL_MAX_PX := 14.0
const SQUASH_DURATION_S := 0.04
const GUIDE_DURATION_S := 0.18
const GUIDE_DOT_STEP := 14.0
const GUIDE_DOT_SIZE := 2.0
const GUIDE_COLOR := Color(0.098, 0.890, 0.819, 0.7)
const LANDING_RING_RADIUS := 26.0
const SMEAR_LIFETIME := 0.04
const SMEAR_OFFSET_PX := 3.0
const SMEAR_ALPHA := 0.35
const TICK_STREAM := "res://assets/audio/sfx/ui_click.ogg"

static var _sheet_cache: Dictionary = {}

var _data: ItemData = null
var _color_id: StringName = &"red"
var _pattern_id: StringName = &"solid"
var _clean := false
var _has_sprite := false
var _sprite: AnimatedSprite2D = null
var _shadow: Polygon2D = null
var _tick_player: AudioStreamPlayer = null
var _height := 0.0
var _pull_start := Vector2.ZERO
var _pull_left := 0.0
var _squash_left := 0.0
var _landing_frames := 0
var _guide_target := Vector2.ZERO
var _guide_left := 0.0
var _smears: Array[Dictionary] = []
var _last_draw_offset := Vector2.INF
var _caption: Label


func _ready() -> void:
	_build_shadow()
	_build_tick_player()


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


## Catalogue name under the object: 10 px, centred, never covered by the sprite.
func set_caption(text: String) -> void:
	if text == "":
		return
	if _caption == null:
		_caption = Label.new()
		_caption.name = "CelestialName"
		_caption.add_theme_font_override("font", Fonts.pixel_font())
		_caption.add_theme_font_size_override("font_size", UITheme.FONT_MICRO)
		_caption.add_theme_color_override("font_color", Palette.METAL_2)
		_caption.add_theme_color_override("font_shadow_color", Palette.SPACE_VOID)
		_caption.add_theme_constant_override("shadow_offset_x", 1)
		_caption.add_theme_constant_override("shadow_offset_y", 1)
		_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_caption.size = Vector2(120, 14)
		_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_caption)
	_caption.text = text
	_caption.position = Vector2(-60, _caption_y())


func _caption_y() -> float:
	var radius := 16.0
	if _data != null:
		radius = float(_data.radius) * float(Config.ART_SCALE) * 0.5
	return radius + 10.0


func is_clean() -> bool:
	return _clean


## Altitude above the floor in world px, owned by `LaundryItem`.
func set_height(value: float) -> void:
	_height = maxf(value, 0.0)
	if _sprite != null:
		_sprite.position = _sprite_position()
	if not _has_sprite:
		queue_redraw()


func get_height() -> float:
	return _height


## 60 ms magnet yank: the sprite leads toward the hold point, then eases back.
func play_grab_pull(hold_position: Vector2) -> void:
	var towards := hold_position - global_position
	_pull_start = towards.limit_length(PULL_MAX_PX)
	_pull_left = PULL_DURATION_S


## 2-frame additive smear behind a throw, never scaling the real sprite.
func play_smear(direction: Vector2) -> void:
	if direction.length() < 0.0001 or _sprite == null or _sprite.sprite_frames == null:
		return
	var texture := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	if texture == null:
		return
	var back := -direction.normalized()
	for index in range(2):
		var ghost := Sprite2D.new()
		ghost.texture = texture
		ghost.centered = _sprite.centered
		ghost.offset = _sprite.offset
		ghost.scale = _sprite.scale
		ghost.flip_h = _sprite.flip_h
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		ghost.material = material
		ghost.modulate = Color(1.0, 1.0, 1.0, SMEAR_ALPHA)
		add_child(ghost)
		var smear := _visual_offset() + back * (SMEAR_OFFSET_PX * float(index + 1))
		ghost.position = Vector2(roundf(smear.x), roundf(smear.y))
		_smears.append({"node": ghost, "left": SMEAR_LIFETIME})


## Dotted guide for 180 ms after a non-MISS throw. `target` may be null (no washer).
func show_throw_guide(target: Variant, grade: int) -> void:
	if grade == RhythmEvaluator.Grade.MISS:
		return
	if not (target is Vector2):
		return
	_guide_target = target as Vector2
	_guide_left = GUIDE_DURATION_S


func play_landing(on_beat: bool, heavy: bool) -> void:
	_squash_left = SQUASH_DURATION_S
	_landing_frames = 1 if on_beat else 0
	queue_redraw()
	var dust := Color("#9AA4C4")
	if heavy:
		dust = Color("#FF7A1A")
	FootFX.burst(self, global_position, dust, 5)
	_play_tick(heavy)


func is_guide_visible() -> bool:
	return _guide_left > 0.0


func _process(delta: float) -> void:
	_tick_pull(delta)
	if _squash_left > 0.0:
		_squash_left = maxf(_squash_left - delta, 0.0)
	if _landing_frames > 0:
		_landing_frames -= 1
		queue_redraw()
	if _guide_left > 0.0:
		_guide_left = maxf(_guide_left - delta, 0.0)
		queue_redraw()
	_tick_smears(delta)
	if _sprite != null:
		_sprite.position = _sprite_position()
	_update_shadow()
	var offset := _visual_offset()
	if not _has_sprite and offset != _last_draw_offset:
		_last_draw_offset = offset
		queue_redraw()


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
	if _data == null or _data.sprite_id == "":
		return
	if not SpriteSheet.has_sheet(_data.sprite_id):
		_has_sprite = false
		if _sprite != null:
			_sprite.visible = false
		return
	if _sprite == null:
		_sprite = AnimatedSprite2D.new()
		_sprite.name = "Sheet"
		add_child(_sprite)
	var animation: StringName = &"idle"
	if _data.special != ItemData.Special.GRAVITY_FIELD:
		animation = StringName("%s_%s" % [_color_id, _pattern_id])
	_has_sprite = SpriteSheet.configure(_sprite, _data.sprite_id, animation)
	_sprite.visible = _has_sprite
	if _has_sprite:
		_sprite.position = _visual_offset()


func _build_shadow() -> void:
	_shadow = Polygon2D.new()
	_shadow.name = "Shadow"
	_shadow.show_behind_parent = true
	_shadow.color = SHADOW_COLOR
	var points := PackedVector2Array()
	for index in range(20):
		var angle := TAU * float(index) / 20.0
		points.append(Vector2(cos(angle), sin(angle)))
	_shadow.polygon = points
	add_child(_shadow)


func _build_tick_player() -> void:
	_tick_player = AudioStreamPlayer.new()
	_tick_player.name = "LandTick"
	_tick_player.volume_db = -15.0
	if AudioServer.get_bus_index("SFX") >= 0:
		_tick_player.bus = "SFX"
	if ResourceLoader.exists(TICK_STREAM):
		_tick_player.stream = load(TICK_STREAM) as AudioStream
	add_child(_tick_player)


func _play_tick(heavy: bool) -> void:
	if _tick_player == null or _tick_player.stream == null:
		return
	_tick_player.pitch_scale = 0.8 if heavy else 1.25
	_tick_player.play()


func _tick_pull(delta: float) -> void:
	if _pull_left <= 0.0:
		return
	_pull_left = maxf(_pull_left - delta, 0.0)


func _tick_smears(delta: float) -> void:
	if _smears.is_empty():
		return
	for index in range(_smears.size() - 1, -1, -1):
		var entry := _smears[index]
		var node: Variant = entry["node"]
		if not (node is Node) or not is_instance_valid(node):
			_smears.remove_at(index)
			continue
		entry["left"] = float(entry["left"]) - delta
		if float(entry["left"]) <= 0.0:
			(node as Node).queue_free()
			_smears.remove_at(index)
			continue
		(node as CanvasItem).modulate.a = SMEAR_ALPHA * (float(entry["left"]) / SMEAR_LIFETIME)


## The art is x4; snapping the sprite's *global* position to that grid keeps texels crisp
## while `ItemVisual.global_position` still tracks the rigid body exactly (contract test).
func _sprite_position() -> Vector2:
	var art := float(Config.ART_SCALE)
	var snapped := (global_position / art).round() * art
	return snapped - global_position + _visual_offset()


func _visual_offset() -> Vector2:
	var offset := Vector2.ZERO
	var art := float(Config.ART_SCALE)
	offset.y -= roundf(_height / art) * art
	if _squash_left > 0.0:
		offset.y += art
	if _pull_left > 0.0:
		var ratio := 1.0 - clampf(_pull_left / PULL_DURATION_S, 0.0, 1.0)
		offset += _pull_start * (1.0 - ratio) * (1.0 - ratio)
	return Vector2(roundf(offset.x), roundf(offset.y))


func _update_shadow() -> void:
	if _shadow == null:
		return
	var parent := get_parent() as Node2D
	var angle := parent.rotation if parent != null else 0.0
	var radius := _radius()
	var lift := 1.0 + _height / 48.0
	var squash := 1.25 if _squash_left > 0.0 else 1.0
	_shadow.position = SHADOW_OFFSET
	_shadow.rotation = angle
	_shadow.scale = Vector2(
		radius * SHADOW_RADIUS_SCALE * lift * squash, radius * SHADOW_FLATTEN * lift
	)
	var alpha := clampf(SHADOW_COLOR.a - _height / 96.0, 0.16, SHADOW_COLOR.a)
	_shadow.color = Color(SHADOW_COLOR.r, SHADOW_COLOR.g, SHADOW_COLOR.b, alpha)


func _draw() -> void:
	if _data == null:
		return
	draw_set_transform(_visual_offset(), 0.0, Vector2.ONE)
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _landing_frames > 0:
		_draw_landing_ring()
	if _guide_left > 0.0:
		_draw_guide()


func _body_color() -> Color:
	if _data == null:
		return Color("#CDD3E8")
	return _data.tint_color


func _outline_color() -> Color:
	return _body_color().lerp(Color("#0B0C10"), OUTLINE_MIX)


func _radius() -> float:
	if _data == null:
		return 8.0 * float(Config.ART_SCALE)
	return maxf(_data.radius, 6.0) * float(Config.ART_SCALE)


func _draw_landing_ring() -> void:
	draw_arc(Vector2.ZERO, LANDING_RING_RADIUS, 0.0, TAU, 24, GUIDE_COLOR, 2.0)


## Dotted 2 px path from the item to the assisted mouth, in local space.
func _draw_guide() -> void:
	var local := _guide_target - global_position
	var length := local.length()
	if length < 1.0:
		return
	var direction := local / length
	var travelled := 10.0
	while travelled < length:
		var center := direction * travelled
		draw_rect(
			Rect2(
				center - Vector2(GUIDE_DOT_SIZE, GUIDE_DOT_SIZE) * 0.5,
				Vector2(GUIDE_DOT_SIZE, GUIDE_DOT_SIZE)
			),
			GUIDE_COLOR
		)
		travelled += GUIDE_DOT_STEP


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
	var points := _crescent(r, Vector2(r * 0.52, -r * 0.12), r * 0.92, 28)
	if points.is_empty():
		return
	draw_colored_polygon(_scaled(points, 1.14), _outline_color())
	draw_colored_polygon(points, body)
	draw_circle(Vector2(r * 0.52, -r * 0.52), r * 0.09, body.lightened(PATTERN_SHIFT))
	draw_circle(Vector2(r * 0.28, r * 0.46), r * 0.07, body.lightened(PATTERN_SHIFT))


## Closed outer-minus-cut crescent polygon. `cut_offset` points at the bite.
func _crescent(
	outer_radius: float, cut_offset: Vector2, cut_radius: float, steps: int
) -> PackedVector2Array:
	var distance := cut_offset.length()
	if distance < 0.001 or distance >= outer_radius + cut_radius:
		return PackedVector2Array()
	var a := (
		(distance * distance + outer_radius * outer_radius - cut_radius * cut_radius)
		/ (2.0 * distance)
	)
	var h := sqrt(maxf(outer_radius * outer_radius - a * a, 0.0))
	var unit := cut_offset / distance
	var perpendicular := Vector2(-unit.y, unit.x)
	var first := unit * a + perpendicular * h
	var second := unit * a - perpendicular * h
	var outer := _arc_away_from(Vector2.ZERO, outer_radius, first, second, -unit, steps)
	var inner := _arc_away_from(cut_offset, cut_radius, second, first, -unit, steps)
	var out := PackedVector2Array()
	out.append_array(outer)
	out.append_array(inner.slice(1, inner.size() - 1))
	return out


func _arc_away_from(
	center: Vector2,
	radius: float,
	start_point: Vector2,
	end_point: Vector2,
	away_dir: Vector2,
	steps: int
) -> PackedVector2Array:
	var from_angle := (start_point - center).angle()
	var to_angle := (end_point - center).angle()
	var sweep := wrapf(to_angle - from_angle, -PI, PI)
	var midpoint := from_angle + sweep * 0.5
	if Vector2.from_angle(midpoint).dot(away_dir) < 0.0:
		sweep = sweep + TAU if sweep < 0.0 else sweep - TAU
	var out := PackedVector2Array()
	for index in range(steps + 1):
		var angle := from_angle + sweep * float(index) / float(steps)
		out.append(center + Vector2.from_angle(angle) * radius)
	return out


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

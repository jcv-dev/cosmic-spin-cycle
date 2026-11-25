class_name DeliveryChute
extends Area2D
## The goal: the pneumatic hatch in the middle of the laundromat (GDD §2.3, UX bible §6.2).
##
## Only a **clean** item is delivered. A clean delivery pays `item.points * combo` through
## [GameState.add_score], adds [constant Config.STABILITY_CHUTE_DELIVERY], bumps
## `delivered_count`, plays the accept animation and frees the item. A dirty item is bounced
## out with `LAVA PRIMERO` for 1.2 s and costs **nothing** — the chute teaches, it does not
## punish.
##
## The beacon ring and the floating `+points` label are procedural (no image assets). The
## hatch art is the shipped `env_chute` sheet; if it is missing a palette pair of rings is
## drawn instead so the goal never disappears from the room.

signal delivered(item: Node, points: int)
signal dirty_rejected(item: Node)

const ART_ID := "env_chute"

## Idle dashed ring radius (UX bible §6.2), world px.
const BEACON_RADIUS := 44.0
## Outer "come here" ring shown while carrying a clean item.
const HINT_RADIUS := 84.0
const HATCH_RADIUS := 64.0
const REJECT_LABEL_S := 1.2
const REJECT_COOLDOWN_S := 0.6
const ACCEPT_ANIM_S := 0.5
const BOUNCE_IMPULSE := 340.0
const CHIME_DB := -7.0
const CLICK_DB := -10.0
const LABEL_IDLE := "DUCTO"
const LABEL_DELIVER := "ENTREGAR"
const LABEL_DIRTY := "LAVA PRIMERO"

var label_text := LABEL_IDLE
var beacon_color: Color = Palette.METAL_2
var has_clean_hint := false
var has_dirty_hint := false

var _visual: AnimatedSprite2D
var _beacon: Node2D
var _audio: AudioStreamPlayer
var _oneshots: Array[AudioStreamPlayer] = []
var _oneshot_index := 0
var _chime: AudioStream
var _click: AudioStream
var _delivered_ids: Dictionary = {}
var _reject_cooldown: Dictionary = {}
var _reject_left := 0.0
var _accept_left := 0.0
var _animate_time := 0.0
var _hint_item: Node = null
var _has_hatch_art := false


func _ready() -> void:
	add_to_group(Config.GROUP_CHUTE)
	collision_layer = Config.CollisionLayer.CHUTE
	collision_mask = Config.CollisionLayer.ITEMS
	monitorable = false
	monitoring = true
	_ensure_shape()
	_ensure_visual()
	_ensure_beacon()
	_ensure_audio()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_refresh_hint()


func _process(delta: float) -> void:
	tick(delta)


# --- public API -------------------------------------------------------------


## Places the hatch from `data/layout.json` art pixels (`art_rect` is the 32x32 footprint,
## `center` its centre). Both are multiplied by [constant Config.ART_SCALE].
func configure(art_rect: Rect2, center: Vector2) -> void:
	var at := center
	if at == Vector2.ZERO:
		at = art_rect.position + art_rect.size * 0.5
	position = at * float(Config.ART_SCALE)
	if is_node_ready():
		_ensure_shape()


## Green beacon + `ENTREGAR` while carrying a clean item; orange `LAVA PRIMERO` when dirty.
func set_carry_hint(clean_item: Node) -> void:
	_hint_item = clean_item if clean_item != null and is_instance_valid(clean_item) else null
	has_clean_hint = _hint_item != null and _is_clean(_hint_item)
	has_dirty_hint = _hint_item != null and not has_clean_hint
	_refresh_hint()
	if is_node_ready():
		_beacon.queue_redraw()


## Delivers `item` when it is clean. Returns true on a completed delivery.
func try_deliver(item: Node) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if item.is_queued_for_deletion():
		return false
	if not _looks_like_item(item):
		return false
	var key := item.get_instance_id()
	if _delivered_ids.has(key):
		return false
	if not _is_clean(item):
		_reject_dirty(item)
		return false
	_delivered_ids[key] = true
	var points := ScoreRules.delivery_points(_item_points(item), GameState.combo)
	GameState.add_stability(Config.STABILITY_CHUTE_DELIVERY, "chute")
	GameState.delivered_count += 1
	GameState.add_score(points)
	_accept_left = ACCEPT_ANIM_S
	_play_animation(&"accept")
	_play_oneshot(_chime, CHIME_DB)
	_float_points(points)
	if item.has_method(&"report_delivered"):
		item.call(&"report_delivered")
	delivered.emit(item, points)
	item.queue_free()
	return true


## Deterministic step for tests; `_process` calls it with the frame delta.
func tick(delta: float) -> void:
	_animate_time += delta
	_reject_left = maxf(_reject_left - delta, 0.0)
	_accept_left = maxf(_accept_left - delta, 0.0)
	_decay(_reject_cooldown, delta)
	if _reject_left <= 0.0:
		_refresh_hint()
	_apply_animation()
	if _beacon != null:
		_beacon.set(&"hint", has_clean_hint)
		_beacon.set(&"dirty", has_dirty_hint)
		_beacon.set(&"tint", beacon_color)
		_beacon.set(&"label_text", label_text)
		_beacon.set(&"fallback", not _has_hatch_art)
		_beacon.set(&"time", _animate_time)
		_beacon.queue_redraw()


func get_label_text() -> String:
	return label_text


func get_beacon_color() -> Color:
	return beacon_color


func is_rejecting() -> bool:
	return _reject_left > 0.0


func get_center_world() -> Vector2:
	return global_position


# --- internals --------------------------------------------------------------


func _refresh_hint() -> void:
	if _reject_left > 0.0:
		label_text = LABEL_DIRTY
		beacon_color = Palette.HAZARD_ORANGE
		return
	if has_clean_hint:
		label_text = LABEL_DELIVER
		beacon_color = Palette.CLEAN_GREEN
	elif has_dirty_hint:
		label_text = LABEL_DIRTY
		beacon_color = Palette.HAZARD_ORANGE
	else:
		label_text = LABEL_IDLE
		beacon_color = Palette.METAL_2


func _reject_dirty(item: Node) -> void:
	var key := item.get_instance_id()
	if float(_reject_cooldown.get(key, 0.0)) > 0.0:
		return
	_reject_cooldown[key] = REJECT_COOLDOWN_S
	_reject_left = REJECT_LABEL_S
	label_text = LABEL_DIRTY
	beacon_color = Palette.HAZARD_ORANGE
	_play_animation(&"opening")
	_play_oneshot(_click, CLICK_DB)
	_bounce(item)
	dirty_rejected.emit(item)


func _bounce(item: Node) -> void:
	var body := item as RigidBody2D
	if body == null:
		return
	var away := body.global_position - global_position
	if away.length() < 0.001:
		away = Vector2.DOWN
	body.apply_central_impulse(away.normalized() * BOUNCE_IMPULSE * maxf(body.mass, 0.1))


func _float_points(points: int) -> void:
	if points <= 0:
		return
	var label := Label.new()
	label.name = "FloatingPoints"
	label.text = "+%d" % points
	label.add_theme_font_override("font", Fonts.pixel_font())
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Palette.CLEAN_GREEN)
	label.position = Vector2(-24.0, -72.0)
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 48.0, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)


func _is_clean(item: Node) -> bool:
	var value: Variant = item.get(&"is_clean")
	return bool(value) if value != null else false


func _item_points(item: Node) -> int:
	var data: Variant = item.get(&"data")
	if data is Object:
		var points: Variant = (data as Object).get(&"points")
		if points != null:
			return int(points)
	var own: Variant = item.get(&"points")
	return int(own) if own != null else 0


func _looks_like_item(item: Node) -> bool:
	if item.is_in_group(Config.GROUP_ITEMS):
		return true
	if item.get(&"item_id") != null:
		return true
	if item.get(&"is_clean") != null:
		return true
	var layer: Variant = item.get(&"collision_layer")
	return layer != null and (int(layer) & Config.CollisionLayer.ITEMS) != 0


func _on_body_entered(body: Node) -> void:
	try_deliver(body)


func _apply_animation() -> void:
	if _visual == null or _visual.sprite_frames == null:
		return
	var animation := &"closed"
	if _accept_left > 0.0:
		animation = &"accept"
	elif has_clean_hint or has_dirty_hint:
		animation = &"open"
	if not _visual.sprite_frames.has_animation(animation):
		return
	if _visual.animation != animation or not _visual.is_playing():
		_visual.play(animation)


func _play_animation(animation: StringName) -> void:
	if _visual == null or _visual.sprite_frames == null:
		return
	if _visual.sprite_frames.has_animation(animation):
		_visual.play(animation)


func _decay(timers: Dictionary, delta: float) -> void:
	if timers.is_empty():
		return
	var expired: Array = []
	for key: Variant in timers.keys():
		var left := float(timers[key]) - delta
		if left <= 0.0:
			expired.append(key)
		else:
			timers[key] = left
	for key: Variant in expired:
		timers.erase(key)


# --- construction -----------------------------------------------------------


func _ensure_shape() -> void:
	var shape_node := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		add_child(shape_node)
	var circle := CircleShape2D.new()
	circle.radius = HATCH_RADIUS
	shape_node.shape = circle


func _ensure_visual() -> void:
	_visual = get_node_or_null(^"Visual") as AnimatedSprite2D
	if _visual == null:
		_visual = AnimatedSprite2D.new()
		_visual.name = "Visual"
		add_child(_visual)
	_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_visual.z_index = 0
	_has_hatch_art = SpriteSheet.configure(_visual, ART_ID, &"closed")


func _ensure_beacon() -> void:
	_beacon = get_node_or_null(^"Beacon") as Node2D
	if _beacon == null:
		_beacon = BeaconRing.new()
		_beacon.name = "Beacon"
		add_child(_beacon)
	_beacon.z_index = 1


func _ensure_audio() -> void:
	_audio = get_node_or_null(^"Audio") as AudioStreamPlayer
	if _audio == null:
		_audio = AudioStreamPlayer.new()
		_audio.name = "Audio"
		add_child(_audio)
	if AudioServer.get_bus_index("SFX") >= 0:
		_audio.bus = "SFX"
	_chime = _load_stream("delivery_chime")
	_click = _load_stream("ui_click")
	for index in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "AudioOneShot%d" % index
		if AudioServer.get_bus_index("SFX") >= 0:
			player.bus = "SFX"
		add_child(player)
		_oneshots.append(player)


func _load_stream(id: String) -> AudioStream:
	var path := "res://assets/audio/sfx/%s.ogg" % id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func _play_oneshot(stream: AudioStream, volume_db: float) -> void:
	if stream == null or _oneshots.is_empty():
		return
	var player := _oneshots[_oneshot_index % _oneshots.size()]
	_oneshot_index += 1
	player.stream = stream
	player.volume_db = volume_db
	player.play()


## Rotating dashed beacon + "come here" ring + label. Procedural, no image assets.
class BeaconRing:
	extends Node2D

	var hint := false
	var dirty := false
	var tint: Color = Palette.METAL_2
	var label_text := "DUCTO"
	var time := 0.0
	var fallback := false

	func _draw() -> void:
		if fallback:
			draw_circle(Vector2.ZERO, 56.0, Palette.SPACE_VOID)
			draw_circle(Vector2.ZERO, 50.0, Palette.SPACE_DEEP)
			draw_arc(Vector2.ZERO, 56.0, 0.0, TAU, 48, Palette.METAL_1, 6.0, true)
			draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 40, Palette.METAL_2, 2.0, true)
		var radius := 44.0
		var segments := 12
		for index in range(segments):
			if index % 2 == 1:
				continue
			var start := time * 0.6 + TAU * float(index) / float(segments)
			draw_arc(Vector2.ZERO, radius, start, start + TAU / float(segments), 8, tint, 3.0)
		if hint:
			var pulse := 84.0 + sin(time * 3.2) * 6.0
			draw_arc(Vector2.ZERO, pulse, 0.0, TAU, 64, Color(tint, 0.45), 3.0, true)
			for index in range(3):
				var y := -118.0 - float(index) * 16.0
				draw_polyline(
					PackedVector2Array(
						[Vector2(-14.0, y), Vector2(0.0, y + 12.0), Vector2(14.0, y)]
					),
					Color(tint, 0.8),
					3.0,
					true
				)
		elif dirty:
			draw_arc(Vector2.ZERO, 60.0, 0.0, TAU, 48, Color(tint, 0.35), 2.0, true)
		var font := Fonts.pixel_font()
		var size := 14
		var width := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(
			font,
			Vector2(-width * 0.5, 96.0),
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			size,
			tint
		)

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
## The hatch is a mouth, not a coin slot: a 110 px catch plus a 240 px suction funnel, so a
## clean item that lands near the centre is pulled in (the owner's "if it should be sucking
## the planet then it's not working").
const HATCH_RADIUS := 110.0
const FUNNEL_RADIUS := 240.0
const SUCTION_ACCEL := 1500.0
const SUCTION_MIN := 60.0
const REJECT_LABEL_S := 1.2
const REJECT_COOLDOWN_S := 0.6
## 3 frames at 12 fps (`env_chute` accept animation).
const ACCEPT_ANIM_S := 0.25
## The item shrinks into the iris over 200 ms, capped by 0.45 x T_beat.
const SWALLOW_S := 0.2
## The +points label flies at most 200 px towards the HUD counter (top-right plaque).
const COUNTER_HINT := Vector2(1124.0, 52.0)
const POINTS_FLIGHT_PX := 200.0
## Every action feedback stays under 0.45 x T_beat (190 ms at 142 BPM).
const FEEDBACK_S := 0.18
const BOUNCE_IMPULSE := 340.0
const CHIME_DB := -7.0
const CLICK_DB := -10.0
const LABEL_IDLE := "TAPA VERDE"
const LABEL_DELIVER := "TIRA AQUÍ"
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
var _swallow_item: Node = null
var _swallow_visual: Node2D = null
var _swallow_scale := Vector2.ONE
var _swallow_left := 0.0
var _swallow_total := SWALLOW_S
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


## The chute is a funnel: clean items near the hatch are pulled toward the iris so the
## player can throw roughly at it and still score. Dirty items are not pulled (they bounce).
func _suction() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group(Config.GROUP_ITEMS):
		var item := node as Node2D
		if item == null or not is_instance_valid(item):
			continue
		if item.get("is_held") == true:
			continue
		if not _is_clean(item):
			continue
		var offset := global_position - item.global_position
		var distance := offset.length()
		if distance <= 1.0 or distance > FUNNEL_RADIUS:
			continue
		var falloff := 1.0 - distance / FUNNEL_RADIUS
		var body := item as RigidBody2D
		if body == null:
			continue
		var pull := maxf(SUCTION_ACCEL * falloff * falloff, SUCTION_MIN)
		body.apply_central_force(offset.normalized() * pull * body.mass)


func _physics_process(_delta: float) -> void:
	_suction()


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
	var stability := ScoreRules.delivery_stability(GameState.combo)
	GameState.add_stability(stability, "chute")
	GameState.delivered_count += 1
	GameState.add_score(points)
	_accept_left = ACCEPT_ANIM_S
	_play_animation(&"accept")
	_play_oneshot(_chime, CHIME_DB)
	_spawn_points(points)
	WasherFX.make_chip(self, "+%d" % int(round(stability)), true, Palette.CLEAN_GREEN)
	_begin_swallow(item)
	if item.has_method(&"report_delivered"):
		item.call(&"report_delivered")
	delivered.emit(item, points)
	return true


## Deterministic step for tests; `_process` calls it with the frame delta.
func tick(delta: float) -> void:
	_animate_time += delta
	_reject_left = maxf(_reject_left - delta, 0.0)
	_accept_left = maxf(_accept_left - delta, 0.0)
	_decay(_reject_cooldown, delta)
	_advance_swallow(delta)
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
	# No bounce: items used to rebound off the hatch and read as a solid wall. A dirty item
	# simply crosses the funnel while the label explains why it was not taken.
	dirty_rejected.emit(item)


func _bounce(item: Node) -> void:
	var body := item as RigidBody2D
	if body == null:
		return
	var away := body.global_position - global_position
	if away.length() < 0.001:
		away = Vector2.DOWN
	body.apply_central_impulse(away.normalized() * BOUNCE_IMPULSE * maxf(body.mass, 0.1))


func _spawn_points(points: int) -> void:
	if points <= 0:
		return
	var pop := WasherFX.TextPop.new()
	pop.name = "PointsPop"
	pop.text = "+%d" % points
	pop.color = Palette.CLEAN_GREEN
	pop.font_size = 16
	pop.lifetime = FEEDBACK_S
	var travel := (COUNTER_HINT - global_position).normalized() * POINTS_FLIGHT_PX
	pop.travel = Vector2.ZERO if Settings.reduce_motion else travel
	pop.position = Vector2(0.0, -30.0)
	pop.z_index = 4
	add_child(pop)


## Starts the 200 ms shrink into the iris. `tick` finishes and frees the item.
func _begin_swallow(item: Node) -> void:
	_swallow_item = item
	_swallow_total = SWALLOW_S
	if BeatConductor.is_playing:
		_swallow_total = minf(SWALLOW_S, 0.45 * BeatConductor.beat_seconds())
	_swallow_left = _swallow_total
	var visual: Variant = item.get(&"visual")
	_swallow_visual = visual as Node2D if visual is Node2D else item as Node2D
	_swallow_scale = _swallow_visual.scale if _swallow_visual != null else Vector2.ONE
	var body := item as RigidBody2D
	if body != null:
		body.set_deferred(&"freeze", true)
		body.set_deferred(&"collision_layer", 0)
		body.set_deferred(&"collision_mask", 0)


func _advance_swallow(delta: float) -> void:
	if _swallow_left <= 0.0:
		return
	_swallow_left = maxf(_swallow_left - delta, 0.0)
	var t := 1.0 - _swallow_left / maxf(_swallow_total, 0.001)
	if _swallow_visual != null and is_instance_valid(_swallow_visual):
		_swallow_visual.scale = _swallow_scale * lerpf(1.0, 0.15, t)
		_swallow_visual.modulate.a = 1.0 - t
	if _swallow_left <= 0.0 and _swallow_item != null and is_instance_valid(_swallow_item):
		_swallow_item.queue_free()
		_swallow_item = null
		_swallow_visual = null


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
		# The chute is the room's focal point, so the beat lives here: a ring that swells on
		# every beat plus four quadrant arcs showing which beat of the bar we are on.
		_draw_beat_ring()
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
			Vector2(-width * 0.5, -104.0),
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			size,
			tint
		)

	## Beat cue on the chute: a ring that swells on every beat plus four quadrant arcs
	## showing which beat of the bar we are on. Reads the conductor; no allocation.
	func _draw_beat_ring() -> void:
		if not BeatConductor.is_playing:
			return
		if BeatConductor.beat_seconds() <= 0.0:
			return
		var phase := clampf(BeatConductor.get_beat_phase(), 0.0, 1.0)
		var swell := 1.0 - phase
		var beat_index := BeatConductor.get_beat_index()
		var downbeat := beat_index % Config.BEATS_PER_MEASURE == 0
		var ink := Palette.METAL_4 if downbeat else Palette.FUNK_CYAN
		draw_arc(
			Vector2.ZERO,
			92.0 + swell * 14.0,
			0.0,
			TAU,
			48,
			Color(ink, 0.10 + swell * 0.55),
			2.0 + swell * 2.0,
			true
		)
		for index in range(Config.BEATS_PER_MEASURE):
			var start := -PI * 0.5 + TAU * float(index) / float(Config.BEATS_PER_MEASURE)
			var active := index == beat_index % Config.BEATS_PER_MEASURE
			draw_arc(
				Vector2.ZERO,
				112.0,
				start + 0.08,
				start + TAU / float(Config.BEATS_PER_MEASURE) - 0.08,
				10,
				Color(Palette.FUNK_CYAN, 0.95 if active else 0.28),
				4.0 if active else 2.0,
				true
			)

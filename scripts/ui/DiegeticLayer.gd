extends Node2D
## World-space affordances: the pulse ring, the aim reticle, the contextual prompt, the
## held-item chip, the grade popup and the turbulence path (docs/UX_BIBLE.md §6, docs/HUD.md).
##
## This layer is what replaced the deleted instruction strip. It answers "when do I press",
## "where does this go" and "what is this piece" *at the object*, instead of in a corner, and
## it draws everything procedurally: no textures, no child nodes, no shader.
##
## Defensive by contract: the washers and the chute are owned by other workstreams and may not
## exist yet, so every foreign read goes through `has_method` / `get` and the layer must look
## and behave correctly with zero washers.

## Pulse ring geometry (world px). It starts wide at the beat and contracts toward the next.
const RING_MIN := 42.0
const RING_MAX := 70.0
const RING_WIDTH := 2.0
const RING_WIDTH_PERFECT := 4.0
const RING_ALPHA := 0.22
const RING_ALPHA_PERFECT := 0.70
const RING_IDLE_ALPHA := 0.28

## Aim reticle (docs/UX_BIBLE.md §6.3). The reticle is a destination indicator, not a cursor.
const AIM_DISTANCE := 96.0
const RETICLE_RADIUS := 12.0
const BRACKET_RADIUS := 20.0
const TARGET_MIN_PROJ := 16.0
const TARGET_MAX_PROJ := 260.0
const TARGET_MAX_PERP := 64.0
const TRACER_ALPHA := 0.30
const TRACER_WIDTH := 2.0
const WORLD_TEXT_SIZE := 12

const STATE_NONE := &"none"
const STATE_WASHER_OK := &"washer_ok"
const STATE_WASHER_NO := &"washer_no"
const STATE_CHUTE := &"chute"

const WASHER_TURBULENT := 2
const COMPAT_SCRIPT := "res://scripts/logic/Compatibility.gd"

const RESCAN_INTERVAL := 0.5
const GROUP_DIEGETIC := &"diegetic"

var _player: Node2D = null
var _chute: Node = null
var _washers: Array[Node] = []
var _items: Array[Node] = []
var _font: Font = null
var _font_bold: Font = null
var _rescan_left := 0.0
var _now := 0.0
var _ring_radius := RING_MAX
var _ring_width := RING_WIDTH
var _ring_alpha := RING_ALPHA
var _last_beat := -1
var _dirty := true
var _aim := Vector2.DOWN
var _held: Node = null
var _target: Node = null
var _reticle_state := STATE_NONE
var _chute_ok := true
var _compat: Script = null


func _ready() -> void:
	add_to_group(GROUP_DIEGETIC)
	_font = Fonts.pixel_font()
	_font_bold = Fonts.pixel_font_bold()
	_rescan()
	_update(0.0)
	queue_redraw()


func _process(delta: float) -> void:
	advance(delta)


## Split from `_process` so tests can step the layer without a frame loop.
func advance(delta: float) -> void:
	_now += delta
	_rescan_left -= delta
	if _rescan_left <= 0.0:
		_rescan_left = RESCAN_INTERVAL
		_rescan()
	_update(delta)
	if _dirty or _ring_is_animating():
		_dirty = false
		queue_redraw()


## Force a cache refresh and a repaint (tests, and callers that cannot wait 0.5 s).
func refresh_now() -> void:
	_rescan()
	_update(0.0)
	_dirty = false
	queue_redraw()


func _update(_delta: float) -> void:
	_aim = _player_aim()
	_update_held()
	_update_target()
	_update_ring()


# --- Cached world lookup ----------------------------------------------------


## Groups are the only contract available while the core loop lands; re-read them every
## `RESCAN_INTERVAL` instead of every frame (docs/UX_BIBLE.md §14).
func _rescan() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_player = tree.get_first_node_in_group(Config.GROUP_PLAYER) as Node2D
	_chute = tree.get_first_node_in_group(Config.GROUP_CHUTE)
	_washers.clear()
	for node in tree.get_nodes_in_group(Config.GROUP_WASHERS):
		_washers.append(node)
	_items.clear()
	for node in tree.get_nodes_in_group(Config.GROUP_ITEMS):
		_items.append(node)
	_dirty = true


func _player_position() -> Vector2:
	return _player.global_position if _player != null else Vector2.ZERO


func _player_aim() -> Vector2:
	if _player == null:
		return Vector2.DOWN
	if _player.has_method("get_aim_direction"):
		var reported: Variant = _player.call("get_aim_direction")
		if reported is Vector2 and (reported as Vector2).length() > 0.01:
			return (reported as Vector2).normalized()
	var stored: Variant = _player.get("aim_direction")
	if stored is Vector2 and (stored as Vector2).length() > 0.01:
		return (stored as Vector2).normalized()
	return Vector2.DOWN


# --- Target state -----------------------------------------------------------


func _update_held() -> void:
	var next: Node = null
	if _player != null:
		var value: Variant = _player.get("held_item")
		if value is Node and is_instance_valid(value as Node):
			next = value as Node
	if next != _held:
		_held = next
		_dirty = true


## Picks the single best destination under the aim ray: a washer, or the chute when the player
## carries something. Sets both the state and the label the reticle draws.
func _update_target() -> void:
	var previous := _reticle_state
	var previous_target := _target
	var origin := _player_position()
	_target = null
	_chute_ok = false
	_reticle_state = STATE_NONE
	if _player == null or _held == null:
		_dirty = _dirty or previous != _reticle_state or previous_target != _target
		return
	var best_score := -1.0
	for washer in _washers:
		if not is_instance_valid(washer):
			continue
		var score := _target_score(washer, _aim, origin)
		if score < 0.0:
			continue
		if best_score < 0.0 or score < best_score:
			best_score = score
			_target = washer
	if _chute != null and is_instance_valid(_chute):
		var chute_score := _target_score(_chute, _aim, origin)
		if chute_score >= 0.0 and (best_score < 0.0 or chute_score < best_score):
			best_score = chute_score
			_target = _chute
	if _target == null:
		_reticle_state = STATE_NONE
	elif _target == _chute:
		_chute_ok = bool(_held.get("is_clean"))
		_reticle_state = STATE_CHUTE
	elif _washer_accepts(_target):
		_reticle_state = STATE_WASHER_OK
	else:
		_reticle_state = STATE_WASHER_NO
	if previous != _reticle_state or previous_target != _target:
		_dirty = true


func _target_score(candidate: Node, aim: Vector2, origin: Vector2) -> float:
	var rel := _mouth_of(candidate) - origin
	var projection := rel.dot(aim)
	if projection < TARGET_MIN_PROJ or projection > TARGET_MAX_PROJ:
		return -1.0
	var perpendicular := absf(rel.cross(aim))
	if perpendicular > TARGET_MAX_PERP:
		return -1.0
	return perpendicular + absf(projection - AIM_DISTANCE) * 0.25


func _mouth_of(node: Node) -> Vector2:
	if node == null or not is_instance_valid(node):
		return Vector2.ZERO
	if node.has_method("get_mouth_world"):
		var value: Variant = node.call("get_mouth_world")
		if value is Vector2:
			return value as Vector2
	var body := node as Node2D
	return body.global_position if body != null else Vector2.ZERO


func _washer_accepts(washer: Node) -> bool:
	if washer.has_method("is_locked") and bool(washer.call("is_locked")):
		return false
	var requirement: StringName = &""
	if washer.has_method("get_requirement"):
		requirement = StringName(str(washer.call("get_requirement")))
	return _item_fits(_held, requirement)


## Uses the shared rule when it is available and mirrors it locally when it is not, so the
## reticle never lies about compatibility while the core loop lands.
func _item_fits(item: Node, requirement: StringName) -> bool:
	if item == null:
		return false
	var item_id := _property_name(item, "item_id")
	var color := _property_name(item, "color")
	var pattern := _property_name(item, "pattern")
	var script := _compat_script()
	if script != null:
		return bool(script.call("item_fits", item_id, color, pattern, requirement))
	if item_id == &"galaxy_core" or requirement == &"wild":
		return true
	return color == requirement or pattern == requirement


func _compat_script() -> Script:
	if _compat != null:
		return _compat
	if not ResourceLoader.exists(COMPAT_SCRIPT):
		return null
	_compat = load(COMPAT_SCRIPT) as Script
	return _compat


static func _property_name(node: Node, property: String, fallback: StringName = &"") -> StringName:
	var value: Variant = node.get(property)
	if value == null:
		return fallback
	return StringName(str(value))


# --- Beat ring --------------------------------------------------------------


## Radius 42→70: wide at the beat, contracting toward the next one, so the ring *arrives* at
## the beat you should press on. Reduce-motion keeps a fixed radius and moves alpha instead.
func _update_ring() -> void:
	if not BeatConductor.is_playing:
		_ring_radius = (RING_MIN + RING_MAX) * 0.5
		_ring_alpha = RING_IDLE_ALPHA
		_ring_width = RING_WIDTH
		return
	var progress := clampf(BeatConductor.get_beat_phase(), 0.0, 1.0)
	var perfect := (
		BeatConductor.delta_to_nearest_beat(BeatConductor.get_song_time())
		<= Config.WINDOW_PERFECT_S
	)
	if Settings.reduce_motion:
		_ring_radius = (RING_MIN + RING_MAX) * 0.5
		_ring_alpha = lerpf(RING_IDLE_ALPHA, RING_ALPHA_PERFECT, 1.0 - progress)
	else:
		_ring_radius = clampf(lerpf(RING_MAX, RING_MIN, progress), RING_MIN, RING_MAX)
		_ring_alpha = RING_ALPHA
	_ring_width = RING_WIDTH_PERFECT if perfect else RING_WIDTH
	if perfect:
		_ring_alpha = maxf(_ring_alpha, RING_ALPHA_PERFECT)


func _ring_is_animating() -> bool:
	if _player == null or not BeatConductor.is_playing:
		return false
	if Settings.reduce_motion:
		var beat := BeatConductor.get_beat_index()
		if beat == _last_beat:
			return false
		_last_beat = beat
		return true
	return true


# --- Painting ---------------------------------------------------------------


func _draw() -> void:
	if _player == null:
		return
	var origin := (_player.global_position).round()
	var reticle := (origin + _aim * AIM_DISTANCE).round()
	if _target != null and is_instance_valid(_target):
		if _reticle_state == STATE_WASHER_OK or (_reticle_state == STATE_CHUTE and _chute_ok):
			var tracer := Palette.FUNK_CYAN
			tracer.a = TRACER_ALPHA
			draw_line(to_local(origin), to_local(_mouth_of(_target)), tracer, TRACER_WIDTH, false)
	_draw_ring(to_local(origin))
	_draw_reticle(to_local(reticle))


func _draw_reticle(center: Vector2) -> void:
	match _reticle_state:
		STATE_WASHER_OK:
			HudGlyphs.draw_cross(self, center, RETICLE_RADIUS, Palette.FUNK_CYAN, 2.0)
			HudGlyphs.draw_brackets(self, center, BRACKET_RADIUS, Palette.FUNK_CYAN, 2.0)
			_draw_text_chip(tr("LANZAR"), center + Vector2(0.0, 34.0), Palette.FUNK_CYAN)
		STATE_WASHER_NO:
			HudGlyphs.draw_cross(self, center, RETICLE_RADIUS, Palette.RED_3, 2.0)
			HudGlyphs.draw_reject(self, center, RETICLE_RADIUS + 6.0, Palette.RED_3, 2.0)
			_draw_text_chip(tr("NO"), center + Vector2(0.0, 34.0), Palette.RED_3)
		STATE_CHUTE:
			if _chute_ok:
				HudGlyphs.draw_cross(self, center, RETICLE_RADIUS, Palette.CLEAN_GREEN, 2.0)
				HudGlyphs.draw_chevron(
					self, center + Vector2(0.0, 8.0), 6.0, Palette.CLEAN_GREEN, 2.0
				)
				_draw_text_chip(tr("ENTREGAR"), center + Vector2(0.0, 34.0), Palette.CLEAN_GREEN)
			else:
				HudGlyphs.draw_cross(self, center, RETICLE_RADIUS, Palette.HAZARD_ORANGE, 2.0)
				_draw_text_chip(
					tr("LAVA PRIMERO"), center + Vector2(0.0, 34.0), Palette.HAZARD_ORANGE
				)
		_:
			var idle := Palette.METAL_2
			idle.a = 0.6
			HudGlyphs.draw_cross(self, center, RETICLE_RADIUS, idle, 1.0)


## A flat world-space chip: `space_void` fill, 1 px border, Silkscreen Bold 12.
func _draw_text_chip(text: String, center: Vector2, ink: Color) -> void:
	if text == "":
		return
	var width := _font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, WORLD_TEXT_SIZE).x
	var chip := Rect2(
		(center - Vector2(width * 0.5, 9.0)).round(), Vector2(width + 12.0, 18.0).round()
	)
	HudGlyphs.draw_chip(self, chip, 0.86, Color(Palette.METAL_0, 0.6))
	draw_string(
		_font_bold,
		chip.position + Vector2(6.0, 13.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		WORLD_TEXT_SIZE,
		ink
	)


func _draw_ring(origin: Vector2) -> void:
	var ink := Palette.FUNK_CYAN
	ink.a = clampf(_ring_alpha, 0.0, 1.0)
	draw_arc(origin, _ring_radius, 0.0, TAU, HudGlyphs.RING_SEGMENTS, ink, _ring_width, false)


# --- Test surface -----------------------------------------------------------


func has_player() -> bool:
	return _player != null and is_instance_valid(_player)


func ring_radius() -> float:
	return _ring_radius


func ring_width() -> float:
	return _ring_width


func ring_alpha() -> float:
	return _ring_alpha


func reticle_state() -> StringName:
	return _reticle_state


func target() -> Node:
	return _target if _target != null and is_instance_valid(_target) else null


func state_readout() -> Dictionary:
	return {
		"has_player": has_player(),
		"reticle": _reticle_state,
		"chute_ok": _chute_ok,
		"has_target": target() != null,
		"has_held": _held != null,
		"ring_radius": _ring_radius,
		"ring_width": _ring_width,
		"ring_alpha": _ring_alpha,
		"washers": _washers.size(),
		"items": _items.size(),
		"has_chute": _chute != null and is_instance_valid(_chute),
	}

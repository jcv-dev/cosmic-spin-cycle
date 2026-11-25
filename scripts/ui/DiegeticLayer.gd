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
	_draw_ring(to_local(origin))


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


func state_readout() -> Dictionary:
	return {
		"has_player": has_player(),
		"ring_radius": _ring_radius,
		"ring_width": _ring_width,
		"ring_alpha": _ring_alpha,
		"washers": _washers.size(),
		"items": _items.size(),
		"has_chute": _chute != null and is_instance_valid(_chute),
	}

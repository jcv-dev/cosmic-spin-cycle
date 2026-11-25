class_name CosmicWasher
extends StaticBody2D
## One washing machine: the pure [WasherFSM] plus every pixel, sound and stability effect.
##
## The node owns no washer rule. It turns a throw into `WasherFSM.insert`, forwards strikes,
## renders the state and applies the authoritative consequences (wrong washer -12,
## explosion -25, clean items bumped into `GameState.washed_count`, once per item).
##
## Wiring is in the class doc of `docs/M4_WASHERS.md`: `configure`, `set_phase`,
## `set_requirement`, `set_locked`, `set_carry_hint`, `strike`, and the `Mouth` Area2D that
## accepts thrown items by itself. `Visual`/`Holo`/`ProgressRing`/`Mouth`/`Audio` and
## `SteamAnchor` exist after `_ready`; the sprite is `mach_washer` x4, never rotated.
## Provisional constants and the wiring list live in `docs/M4_WASHERS.md`.

signal item_loaded(item: Node)
signal item_rejected(item: Node, reason: String)
signal state_changed(old_state: int, new_state: int)
signal cycle_done(items: Array)
signal exploded
signal turbulence_resolved(grade: int)
signal delivered_ready(washer: Node)

enum HoloState { IDLE, MATCH, MISMATCH, WASHING, TURBULENT, DONE, BROKEN, LOCKED }

const ART_ID := "mach_washer"

const MOUTH_RADIUS := 60.0
const BODY_SIZE := Vector2(176.0, 176.0)
const BODY_CENTER := Vector2(0.0, -96.0)
const EJECT_OFFSET := Vector2(0.0, 76.0)
const EJECT_IMPULSE := 260.0
const EXPLODE_IMPULSE := 420.0
const BOUNCE_IMPULSE := 320.0
const REJECT_COOLDOWN_S := 0.6
const RELEASE_COOLDOWN_S := 0.4

## Holo panel anchor: 40 world px above the 48 art px machine (UX bible §6.1).
const HOLO_GAP := 40.0
## Machine art height (48 art px) plus the pivot overhang, scaled to world px.
const MACHINE_TOP := -184.0
const HOLO_ORIGIN := Vector2(0.0, MACHINE_TOP - HOLO_GAP)
## Share of the south row: the frozen layout leaves no room above those machines.
const HOLO_ORIGIN_BELOW := Vector2(0.0, 8.0 + HOLO_GAP + 84.0)
const SHAKE_PX := 6.0
const SHAKE_TIME_S := 0.26
const LOAD_FLASH_S := 0.18
const ALARM_MAX := 3

const DRUM_DB := -16.0
const DONE_DB := -8.0
const EXPLODE_DB := -6.0
const ALARM_DB := -9.0
const CLICK_DB := -12.0

const SFX_DIR := "res://assets/audio/sfx/"

## Stable identity from `data/layout.json` (`washer_nw`, …).
var washer_id: StringName = &""

## Holo presentation state for the current frame (read by `_HoloPanel`).
var holo_state: int = HoloState.IDLE
var holo_alpha := 0.6
var holo_label := ""
var holo_tint: Color = Palette.METAL_3
var ring_color: Color = Palette.FUNK_CYAN

var _fsm: WasherFSM = WasherFSM.new()
var _configured := false
var _requirement: StringName = &"wild"
var _locked := false

var _visual: AnimatedSprite2D
var _holo: Node2D
var _ring: Node2D
var _glow: Node2D
var _fallback: Node2D
var _mouth: Area2D
var _body_shape: CollisionShape2D
var _mouth_shape: CollisionShape2D
var _holo_origin := HOLO_ORIGIN

var _audio: AudioStreamPlayer
var _oneshots: Array[AudioStreamPlayer] = []
var _oneshot_index := 0
var _sfx: Dictionary = {}

var _carry_hint: Node = null
var _last_state := WasherFSM.State.IDLE
var _load_flash_left := 0.0
var _shake_left := 0.0
var _holo_flash := 0.0
var _beat_pulse := 0.0
var _last_beat := -1
var _alarm_count := 0
var _animate_time := 0.0
var _reject_cooldown: Dictionary = {}
var _release_cooldown: Dictionary = {}
var _clean_counted: Dictionary = {}
var _absorbed: Dictionary = {}


func _ready() -> void:
	add_to_group(Config.GROUP_WASHERS)
	# WASHER identifies the machine; WORLD is what actually blocks the player (mask 1) and
	# the items (mask 1|4) with the frozen collision masks.
	collision_layer = Config.CollisionLayer.WASHER | Config.CollisionLayer.WORLD
	collision_mask = 0
	_ensure_collisions()
	_ensure_visual()
	_ensure_procedural()
	_ensure_audio()
	_ensure_steam()
	_fsm.set_requirement(_requirement)
	_fsm.set_locked(_locked)
	if _configured:
		_apply_config()
	_sync_state()
	_update_visuals(0.0)


func _process(delta: float) -> void:
	tick(delta)


## Places the machine. `art_rect` and `mouth_art` are `data/layout.json` art-pixel values;
## the root sits on the mouth so the sprite's bottom-centre pivot lands on the machine base.
func configure(
	p_id: StringName, art_rect: Rect2, mouth_art: Vector2, requirement: StringName
) -> void:
	washer_id = p_id
	var mouth := mouth_art
	if mouth == Vector2.ZERO:
		mouth = art_rect.position + Vector2(art_rect.size.x * 0.5, art_rect.size.y)
	position = mouth * float(Config.ART_SCALE)
	var below := art_rect.get_center().y > float(Config.ART_CANVAS.y) * 0.5
	_holo_origin = HOLO_ORIGIN_BELOW if below else HOLO_ORIGIN
	if _holo != null:
		_holo.position = _holo_origin
	_configured = true
	_requirement = &"wild" if requirement == &"" else requirement
	_fsm.set_requirement(_requirement)
	if is_node_ready():
		_apply_config()
		_holo_flash = 0.5
		_update_visuals(0.0)


## Phase change hook: swaps the hologram requirement and flashes it.
func set_requirement(value: StringName) -> void:
	_requirement = &"wild" if value == &"" else value
	_fsm.set_requirement(_requirement)
	_holo_flash = 0.5
	if is_node_ready():
		_update_visuals(0.0)


func get_requirement() -> StringName:
	return _fsm.get_requirement()


## P1/P2 keep the south washers offline; a locked washer bounces items without a penalty.
func set_locked(value: bool) -> void:
	_locked = value
	_fsm.set_locked(value)
	if is_node_ready():
		_update_visuals(0.0)


func is_locked() -> bool:
	return _fsm.is_locked()


func set_phase(value: int) -> void:
	_fsm.set_phase(value)


## Rhythm strike forwarded by `Player.struck`. Returns true when it mattered.
func strike(grade: int) -> bool:
	if not _fsm.strike(grade):
		return false
	_handle_events(_fsm.take_events())
	_sync_state()
	_update_visuals(0.0)
	return true


## The mouth's entry point. `grade` is the throw's rhythm grade when the caller knows it.
func try_accept(item: Node, grade: int = WasherFSM.GRADE_UNKNOWN) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	var key := item.get_instance_id()
	if float(_reject_cooldown.get(key, 0.0)) > 0.0:
		return false
	if float(_release_cooldown.get(key, 0.0)) > 0.0:
		return false
	if _absorbed.has(key):
		return false
	if not _fsm.insert(item, {}, grade):
		_reject(item, _fsm.last_reject)
		return false
	_absorb(item)
	_load_flash_left = LOAD_FLASH_S
	_apply_animation()
	_play_oneshot("click", CLICK_DB)
	_handle_events(_fsm.take_events())
	_sync_state()
	_update_visuals(0.0)
	item_loaded.emit(item)
	return true


## Tutorial hook: force TURBULENT at 50 % progress.
func force_turbulent() -> bool:
	if not _fsm.force_turbulent():
		return false
	_handle_events(_fsm.take_events())
	_sync_state()
	_update_visuals(0.0)
	return true


## Tutorial/test hook: complete the cycle now.
func force_finish() -> bool:
	if not _fsm.force_finish():
		return false
	_handle_events(_fsm.take_events())
	_sync_state()
	_update_visuals(0.0)
	return true


## Tutorial hook (UX bible §7 step 6): show a controlled explosion on the beat.
func explode_now() -> bool:
	if _fsm.get_state() == WasherFSM.State.BROKEN:
		return false
	_handle_events(_fsm.explode())
	_sync_state()
	_update_visuals(0.0)
	return true


func get_state() -> int:
	return _fsm.get_state()


func get_progress() -> float:
	return _fsm.get_progress()


func get_loaded_items() -> Array:
	return _fsm.get_loaded_items()


## Tint for the environment's light pools (UX bible §3.5).
func get_glow_color() -> Color:
	match _fsm.get_requirement():
		&"red":
			return Palette.RED_3
		&"blue":
			return Palette.BLUE_3
		&"yellow":
			return Palette.YEL_3
		&"wild":
			return Palette.FUNK_CYAN
		_:
			return Palette.METAL_3


func get_mouth_world() -> Vector2:
	return global_position


## Tells the hologram what the player is carrying so it can dim incompatible machines.
func set_carry_hint(item: Node) -> void:
	_carry_hint = item if item != null and is_instance_valid(item) else null
	if is_node_ready():
		_update_visuals(0.0)


## Deterministic step used by tests and tools; `_process` calls it with the frame delta.
func tick(delta: float) -> Array[Dictionary]:
	var events := _fsm.tick(delta)
	_handle_events(events)
	_sync_state()
	_update_visuals(delta)
	return events


func _handle_events(events: Array[Dictionary]) -> void:
	for event in events:
		match StringName(str(event.get("type", &""))):
			&"washing_started":
				_alarm_count = 0
				_play_loop("drum", DRUM_DB)
			&"turbulent":
				_on_turbulent()
			&"turbulence_resolved":
				_on_turbulence_resolved(int(event.get("grade", -1)))
			&"cycle_done":
				_on_cycle_done(event.get("items", []))
			&"exploded":
				_on_exploded(event.get("items", []))
			&"repaired":
				_alarm_count = 0
				_play_oneshot("click", CLICK_DB)
			_:
				pass


func _on_turbulent() -> void:
	_alarm_count = 1
	_play_oneshot("alarm", ALARM_DB)
	_spawn_burst(Palette.HAZARD_ORANGE, 10, 180.0, 3.0)
	_shake_left = SHAKE_TIME_S


func _on_turbulence_resolved(grade: int) -> void:
	_alarm_count = ALARM_MAX
	turbulence_resolved.emit(grade)
	_spawn_burst(Palette.FUNK_CYAN, 12, 240.0, 3.0)
	_play_oneshot("click", CLICK_DB)


func _on_cycle_done(items: Array) -> void:
	_stop_loop()
	for item: Variant in items:
		_mark_clean(item)
	_play_oneshot("done", DONE_DB)
	_spawn_burst(Palette.CLEAN_GREEN, 14, 200.0, 3.0)
	cycle_done.emit(items)
	delivered_ready.emit(self)


func _on_exploded(items: Array) -> void:
	_stop_loop()
	_alarm_count = ALARM_MAX
	_play_oneshot("explode", EXPLODE_DB)
	_spawn_burst(Palette.HAZARD_ORANGE, 18, 320.0, 4.0)
	_spawn_burst(Palette.YEL_2, 10, 220.0, 3.0)
	_shake_left = SHAKE_TIME_S * 1.6
	GameState.add_stability(Config.STABILITY_EXPLOSION, "washer_explosion")
	GameState.exploded_count += 1
	for index in range(items.size()):
		_eject(items[index], true, index)
	exploded.emit()


func _sync_state() -> void:
	var new_state := _fsm.get_state()
	if new_state == _last_state:
		return
	var old_state := _last_state
	_last_state = new_state
	_apply_animation()
	state_changed.emit(old_state, new_state)


func _apply_animation() -> void:
	if _visual == null or _visual.sprite_frames == null:
		return
	if _load_flash_left > 0.0 and _visual.sprite_frames.has_animation(&"load_flash"):
		if _visual.animation != &"load_flash" or not _visual.is_playing():
			_visual.play(&"load_flash")
		return
	var animation := &"idle"
	match _fsm.get_state():
		WasherFSM.State.WASHING:
			animation = &"washing"
		WasherFSM.State.TURBULENT:
			animation = &"turbulent"
		WasherFSM.State.DONE:
			animation = &"done"
		WasherFSM.State.BROKEN:
			animation = &"broken"
		_:
			animation = &"idle"
	if not _visual.sprite_frames.has_animation(animation):
		return
	if _visual.animation != animation or not _visual.is_playing():
		_visual.play(animation)


func _mark_clean(item: Variant) -> void:
	if item == null or not is_instance_valid(item):
		return
	var key := int((item as Object).get_instance_id())
	if _clean_counted.has(key):
		return
	_clean_counted[key] = true
	if (item as Object).has_method(&"mark_clean"):
		(item as Object).call(&"mark_clean")
	elif "is_clean" in (item as Object):
		(item as Object).set(&"is_clean", true)
	GameState.washed_count += 1


func _reject(item: Node, reason: StringName) -> void:
	var reason_name := StringName(reason)
	if reason_name == WasherFSM.REJECT_INCOMPATIBLE and not _fsm.is_locked():
		if not _is_wildcard_item(item):
			GameState.add_stability(Config.STABILITY_WRONG_WASHER, "wrong_washer")
			GameState.wrong_washer_count += 1
			_spawn_burst(Palette.HAZARD_ORANGE, 6, 120.0, 3.0)
			_shake_left = SHAKE_TIME_S
			_play_oneshot("alarm", ALARM_DB - 1.0)
	_reject_cooldown[item.get_instance_id()] = REJECT_COOLDOWN_S
	_bounce(item)
	item_rejected.emit(item, String(reason_name))


func _bounce(item: Node) -> void:
	var body := item as RigidBody2D
	if body == null:
		return
	var away := body.global_position - global_position
	if away.length() < 0.001:
		away = Vector2.DOWN
	body.apply_central_impulse(away.normalized() * BOUNCE_IMPULSE * maxf(body.mass, 0.1))


func _absorb(item: Node) -> void:
	_absorbed[item.get_instance_id()] = true
	var node := item as Node2D
	if node != null:
		node.visible = false
	var body := item as RigidBody2D
	if body == null:
		return
	# The mouth signal fires inside the physics flush; defer every state change.
	body.set_deferred(&"freeze", true)
	body.set_deferred(&"collision_layer", 0)
	body.set_deferred(&"collision_mask", 0)
	body.set_deferred(&"global_position", global_position)
	body.linear_velocity = Vector2.ZERO
	body.angular_velocity = 0.0


func _eject(item: Variant, explosive: bool, index: int = 0) -> void:
	if item == null or not is_instance_valid(item):
		return
	_absorbed.erase((item as Object).get_instance_id())
	var node := item as Node2D
	if node != null:
		node.visible = true
	_release_cooldown[(item as Object).get_instance_id()] = RELEASE_COOLDOWN_S
	var spread := 0.0
	if explosive:
		spread = (float(index % 3) - 1.0) * 0.45
	var direction := Vector2(sin(spread), cos(spread))
	var offset := EJECT_OFFSET + Vector2(direction.x * 28.0, 0.0)
	var body := item as RigidBody2D
	if body != null:
		body.freeze = false
		body.global_position = global_position + offset
		body.collision_layer = Config.CollisionLayer.ITEMS
		body.collision_mask = Config.CollisionLayer.WORLD | Config.CollisionLayer.ITEMS
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
		var impulse := EXPLODE_IMPULSE if explosive else EJECT_IMPULSE
		body.apply_central_impulse(direction * impulse * maxf(body.mass, 0.1))
	elif node != null:
		node.global_position = global_position + offset
	if "is_held" in (item as Object):
		(item as Object).set(&"is_held", false)


func _is_wildcard_item(item: Node) -> bool:
	var item_id: Variant = item.get(&"item_id")
	if item_id == null:
		var data: Variant = item.get(&"data")
		if data is Object:
			item_id = (data as Object).get(&"id")
	if item_id == null:
		return false
	return Compatibility.is_wildcard(StringName(str(item_id)))


func _update_visuals(delta: float) -> void:
	_animate_time += delta
	_load_flash_left = maxf(_load_flash_left - delta, 0.0)
	_shake_left = maxf(_shake_left - delta, 0.0)
	_holo_flash = maxf(_holo_flash - delta, 0.0)
	_decay(_reject_cooldown, delta)
	_decay(_release_cooldown, delta)
	_collect_done_items()
	_refresh_holo()
	_refresh_ring()
	_refresh_glow()
	_refresh_audio_beat(delta)
	_refresh_animation()
	if _load_flash_left <= 0.0:
		_apply_animation()


func _refresh_animation() -> void:
	if _visual == null:
		return
	var shake := Vector2.ZERO
	if _shake_left > 0.0 and not Settings.reduce_motion:
		var strength := _shake_left / SHAKE_TIME_S
		shake = Vector2(sin(_animate_time * 91.0), cos(_animate_time * 77.0)) * SHAKE_PX
		shake *= strength
	_visual.position = shake.round()
	_visual.rotation = 0.0
	var dim := 0.55 if _fsm.is_locked() else 1.0
	_visual.modulate = Color(dim, dim, dim, 1.0)


func _refresh_holo() -> void:
	if _holo == null:
		return
	var state := _fsm.get_state()
	var alpha := 0.6
	var text := _requirement_text(_fsm.get_requirement())
	var tint := get_glow_color()
	holo_state = HoloState.IDLE
	if _fsm.is_locked():
		holo_state = HoloState.LOCKED
		alpha = 0.85
		tint = Palette.METAL_1
		text = tr("FUERA DE SERVICIO")
	else:
		match state:
			WasherFSM.State.BROKEN:
				holo_state = HoloState.BROKEN
				alpha = 1.0
				tint = Palette.HAZARD_ORANGE
				text = tr("AVERIADA")
			WasherFSM.State.DONE:
				holo_state = HoloState.DONE
				alpha = 1.0
				tint = Palette.CLEAN_GREEN
				text = tr("LISTO")
			WasherFSM.State.TURBULENT:
				holo_state = HoloState.TURBULENT
				alpha = 1.0
				tint = Palette.HAZARD_ORANGE
				text = tr("¡GOLPE!")
			WasherFSM.State.WASHING:
				holo_state = HoloState.WASHING
				alpha = 1.0
				text = tr("LAVANDO %d%%") % int(round(_fsm.get_progress() * 100.0))
			_:
				var hint := _carry_hint_state()
				holo_state = hint
				if hint == HoloState.MISMATCH:
					alpha = 0.25
					tint = Palette.METAL_1
					text = tr("NO COMPATIBLE")
				elif hint == HoloState.MATCH:
					alpha = 1.0
	holo_alpha = alpha
	holo_label = text
	holo_tint = tint
	_holo.modulate = Color(1.0, 1.0, 1.0, alpha)
	_holo.set(&"requirement", _fsm.get_requirement())
	_holo.set(&"label_text", text)
	_holo.set(&"tint", tint)
	_holo.set(&"flash", _holo_flash)
	_holo.set(&"matched", holo_state == HoloState.MATCH)
	var bob := 0.0 if Settings.reduce_motion else roundf(sin(_animate_time * 1.7) * 2.0)
	_holo.position.y = _holo_origin.y + bob
	_holo.queue_redraw()


func _refresh_ring() -> void:
	if _ring == null:
		return
	var state := _fsm.get_state()
	var mode := 0
	var color := Palette.FUNK_CYAN
	match state:
		WasherFSM.State.WASHING, WasherFSM.State.TURBULENT:
			mode = 1
			color = (
				Palette.HAZARD_ORANGE if state == WasherFSM.State.TURBULENT else Palette.FUNK_CYAN
			)
		WasherFSM.State.DONE:
			mode = 2
			color = Palette.CLEAN_GREEN
		WasherFSM.State.BROKEN:
			mode = 3
			color = Palette.HAZARD_ORANGE
		_:
			mode = 0
	ring_color = color
	_ring.visible = mode != 0
	_ring.set(&"mode", mode)
	_ring.set(&"progress", _fsm.get_progress())
	_ring.set(&"ring_color", color)
	_ring.queue_redraw()


func _refresh_glow() -> void:
	if _glow == null:
		return
	_glow.visible = not _fsm.is_locked()
	var energy := 0.35
	if BeatConductor.is_playing:
		energy += 0.55 * _beat_pulse
	else:
		energy += 0.12 * sin(_animate_time * 1.6)
	_glow.set(&"energy", clampf(energy, 0.0, 1.0))
	_glow.set(&"tint", get_glow_color())
	_glow.queue_redraw()


func _refresh_audio_beat(delta: float) -> void:
	_beat_pulse = maxf(_beat_pulse - delta * 3.2, 0.0)
	if not BeatConductor.is_playing:
		return
	var beat: int = BeatConductor.get_beat_index()
	if beat == _last_beat:
		return
	_last_beat = beat
	_beat_pulse = 1.0
	if _fsm.get_state() == WasherFSM.State.TURBULENT and _alarm_count < ALARM_MAX:
		_alarm_count += 1
		_play_oneshot("alarm", ALARM_DB)


func _collect_done_items() -> void:
	if _fsm.get_state() != WasherFSM.State.DONE or not _fsm.can_collect():
		return
	var items := _fsm.collect()
	for index in range(items.size()):
		_eject(items[index], false, index)
	_sync_state()


func _carry_hint_state() -> int:
	if _carry_hint == null or not is_instance_valid(_carry_hint):
		return HoloState.IDLE
	var item_id := StringName(str(_carry_hint.get(&"item_id")))
	var color := StringName(str(_carry_hint.get(&"color")))
	var pattern := StringName(str(_carry_hint.get(&"pattern")))
	if item_id == &"":
		var data: Variant = _carry_hint.get(&"data")
		if data is Object:
			item_id = StringName(str((data as Object).get(&"id")))
	if Compatibility.is_wildcard(item_id):
		return HoloState.MATCH if _fsm.slots_used == 0 else HoloState.MISMATCH
	if Compatibility.item_fits(item_id, color, pattern, _fsm.get_requirement()):
		return HoloState.MATCH
	return HoloState.MISMATCH


func _requirement_text(requirement: StringName) -> String:
	var text := "CUALQUIERA"
	match requirement:
		&"red":
			text = "ROJO"
		&"blue":
			text = "AZUL"
		&"yellow":
			text = "AMARILLO"
		&"solid":
			text = "LISO"
		&"ringed":
			text = "ANILLOS"
		&"spotted":
			text = "MOTAS"
	return tr(text)


func _apply_config() -> void:
	if _body_shape != null:
		var rectangle := RectangleShape2D.new()
		rectangle.size = BODY_SIZE
		_body_shape.shape = rectangle
		_body_shape.position = BODY_CENTER
	if _mouth_shape != null:
		var circle := CircleShape2D.new()
		circle.radius = MOUTH_RADIUS
		_mouth_shape.shape = circle
	if _fallback != null:
		_fallback.visible = not SpriteSheet.has_sheet(ART_ID)


func _ensure_collisions() -> void:
	_body_shape = get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if _body_shape == null:
		_body_shape = CollisionShape2D.new()
		_body_shape.name = "CollisionShape2D"
		_body_shape.position = BODY_CENTER
		add_child(_body_shape)
	_mouth = get_node_or_null(^"Mouth") as Area2D
	if _mouth == null:
		_mouth = Area2D.new()
		_mouth.name = "Mouth"
		add_child(_mouth)
	_mouth.collision_layer = 0
	_mouth.collision_mask = Config.CollisionLayer.ITEMS
	_mouth.monitorable = false
	_mouth.monitoring = true
	_mouth_shape = _mouth.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if _mouth_shape == null:
		_mouth_shape = CollisionShape2D.new()
		_mouth_shape.name = "CollisionShape2D"
		_mouth.add_child(_mouth_shape)
	if not _mouth.body_entered.is_connected(_on_mouth_body_entered):
		_mouth.body_entered.connect(_on_mouth_body_entered)


func _ensure_visual() -> void:
	_visual = get_node_or_null(^"Visual") as AnimatedSprite2D
	if _visual == null:
		_visual = AnimatedSprite2D.new()
		_visual.name = "Visual"
		add_child(_visual)
	_visual.z_index = 0
	_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if SpriteSheet.configure(_visual, ART_ID, &"idle"):
		return
	_fallback = FallbackBody.new()
	_fallback.name = "FallbackBody"
	_fallback.position = Vector2(-96.0, MACHINE_TOP)
	_fallback.z_index = 0
	add_child(_fallback)


func _ensure_procedural() -> void:
	_holo = get_node_or_null(^"Holo") as Node2D
	if _holo == null:
		_holo = HoloPanel.new()
		_holo.name = "Holo"
		add_child(_holo)
	_holo.z_index = 2
	_holo.position = HOLO_ORIGIN
	_ring = get_node_or_null(^"ProgressRing") as Node2D
	if _ring == null:
		_ring = ProgressRing.new()
		_ring.name = "ProgressRing"
		add_child(_ring)
	_ring.z_index = 1
	_ring.visible = false
	_glow = get_node_or_null(^"Glow") as Node2D
	if _glow == null:
		_glow = DrumGlow.new()
		_glow.name = "Glow"
		add_child(_glow)
	_glow.z_index = -1


func _ensure_audio() -> void:
	_audio = get_node_or_null(^"Audio") as AudioStreamPlayer
	if _audio == null:
		_audio = AudioStreamPlayer.new()
		_audio.name = "Audio"
		add_child(_audio)
	if AudioServer.get_bus_index("SFX") >= 0:
		_audio.bus = "SFX"
	_sfx = {
		"drum": _load_stream("washer_drum", true),
		"done": _load_stream("washer_done", false),
		"explode": _load_stream("washer_explode", false),
		"alarm": _load_stream("turbulent_alarm", false),
		"click": _load_stream("ui_click", false),
	}
	for index in range(3):
		var player := AudioStreamPlayer.new()
		player.name = "AudioOneShot%d" % index
		if AudioServer.get_bus_index("SFX") >= 0:
			player.bus = "SFX"
		add_child(player)
		_oneshots.append(player)


func _ensure_steam() -> void:
	if get_node_or_null(^"SteamAnchor") != null:
		return
	var anchor := Marker2D.new()
	anchor.name = "SteamAnchor"
	anchor.position = Vector2(0.0, MACHINE_TOP)
	add_child(anchor)


func _on_mouth_body_entered(body: Node) -> void:
	if GameState.is_ended:
		return
	try_accept(body)


func _load_stream(id: String, loop: bool) -> AudioStream:
	var path := SFX_DIR + id + ".ogg"
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = (
			AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		)
	return stream


func _play_loop(id: String, volume_db: float) -> void:
	var stream: AudioStream = _sfx.get(id) as AudioStream
	if stream == null or _audio == null:
		return
	if _audio.playing and _audio.stream == stream:
		_audio.volume_db = volume_db
		return
	_audio.stream = stream
	_audio.volume_db = volume_db
	_audio.play()


func _stop_loop() -> void:
	if _audio != null and _audio.playing:
		_audio.stop()


func _play_oneshot(id: String, volume_db: float) -> void:
	var stream: AudioStream = _sfx.get(id) as AudioStream
	if stream == null or _oneshots.is_empty():
		return
	var player := _oneshots[_oneshot_index % _oneshots.size()]
	_oneshot_index += 1
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func _spawn_burst(color: Color, count: int, speed: float, size: float) -> void:
	var burst := SparkBurst.new()
	burst.color = color
	burst.count = int(float(count) * (0.35 if Settings.reduce_motion else 1.0))
	burst.speed = speed
	burst.size = size
	burst.position = Vector2(0.0, -60.0)
	burst.z_index = 3
	add_child(burst)


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


## Hologram: panel + two requirement glyphs + one text line, all procedural.
class HoloPanel:
	extends Node2D

	var requirement: StringName = &"wild"
	var label_text := ""
	var tint: Color = Palette.METAL_3
	var flash := 0.0
	var matched := false

	func _draw() -> void:
		var rect := Rect2(-64.0, -84.0, 128.0, 84.0)
		var background := Color(Palette.SPACE_DEEP, 0.84)
		draw_rect(rect, background, true)
		draw_rect(Rect2(-62.0, -82.0, 124.0, 80.0), Color(Palette.SPACE_HAZE, 0.35), true)
		draw_rect(rect, Color(tint, 0.95), false, 2.0)
		var tick := Color(Palette.METAL_4, 0.9)
		draw_rect(Rect2(-64.0, -84.0, 10.0, 2.0), tick, true)
		draw_rect(Rect2(-64.0, -84.0, 2.0, 10.0), tick, true)
		draw_rect(Rect2(54.0, -2.0, 10.0, 2.0), tick, true)
		draw_rect(Rect2(62.0, -10.0, 2.0, 10.0), tick, true)
		_draw_icon(_icon_a(), Vector2(-52.0, -76.0))
		_draw_icon(_icon_b(), Vector2(4.0, -76.0))
		var font := Fonts.pixel_font()
		var size := 9 if label_text.length() > 13 else 12
		var width := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var color := Palette.FUNK_CYAN if matched else Palette.METAL_4
		draw_string(
			font,
			Vector2(-width * 0.5, -10.0),
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			size,
			color
		)
		if matched:
			draw_rect(Rect2(-34.0, -5.0, 68.0, 3.0), Palette.FUNK_CYAN, true)

	func _draw_icon(icon_name: StringName, at: Vector2) -> void:
		var texture := SpriteSheet.frame_texture("ui_holo_icons", icon_name, 0)
		if texture == null:
			draw_rect(Rect2(at, Vector2(48.0, 48.0)), Color(tint, 0.5), false, 2.0)
			return
		draw_texture_rect(texture, Rect2(at, Vector2(48.0, 48.0)), false)

	func _icon_a() -> StringName:
		return requirement if _is_colour(requirement) else &"wild"

	func _icon_b() -> StringName:
		return &"wild" if _is_colour(requirement) else requirement

	func _is_colour(value: StringName) -> bool:
		return value == &"red" or value == &"blue" or value == &"yellow"


## Progress arc around the drum (UX bible §6.1): wash %, done ring, or repair countdown.
class ProgressRing:
	extends Node2D

	## 0 hidden, 1 wash, 2 done, 3 repair.
	var mode := 0
	var progress := 0.0
	var ring_color: Color = Palette.FUNK_CYAN

	func _draw() -> void:
		if mode == 0:
			return
		var center := Vector2(0.0, -96.0)
		var radius := 66.0
		draw_arc(center, radius, 0.0, TAU, 64, Color(Palette.SPACE_VOID, 0.65), 6.0, true)
		var start := -PI * 0.5
		var sweep := TAU * clampf(progress, 0.0, 1.0)
		if sweep > 0.001:
			draw_arc(center, radius, start, start + sweep, 64, ring_color, 4.0, true)
			var tip := center + Vector2(cos(start + sweep), sin(start + sweep)) * radius
			draw_circle(tip, 4.0, ring_color)
		if mode == 1:
			draw_arc(center, radius + 6.0, 0.0, TAU, 64, Color(ring_color, 0.25), 2.0, true)


## Additive light pool on the floor; energy pulses on the beat (UX bible §3.5).
class DrumGlow:
	extends Node2D

	var energy := 0.35
	var tint: Color = Palette.METAL_3

	func _draw() -> void:
		draw_set_transform(Vector2(0.0, 12.0), 0.0, Vector2(1.0, 0.34))
		for index in range(4):
			var radius := 120.0 - float(index) * 24.0
			var alpha := (0.05 + 0.05 * energy) * (1.0 + float(index) * 0.35)
			draw_circle(Vector2.ZERO, radius, Color(tint, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Deterministic spark burst used for loads, turbulence, done and explosions.
class SparkBurst:
	extends Node2D

	var color: Color = Palette.HAZARD_ORANGE
	var count := 10
	var speed := 200.0
	var size := 3.0
	var lifetime := 0.5
	var age := 0.0

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := clampf(age / lifetime, 0.0, 1.0)
		var alpha := 1.0 - t
		var travel := speed * sqrt(t)
		for index in range(maxi(count, 1)):
			var angle := TAU * float(index) / float(maxi(count, 1)) + 0.4
			var direction := Vector2(cos(angle), sin(angle))
			var tip := direction * travel
			draw_line(tip, tip - direction * 8.0, Color(color, alpha), size)
		if t < 0.35:
			draw_circle(Vector2.ZERO, 10.0 * (1.0 - t), Color(color, alpha * 0.5))


## Procedural stand-in machine, drawn only when `mach_washer` is missing.
class FallbackBody:
	extends Node2D

	func _draw() -> void:
		draw_rect(Rect2(0.0, 0.0, 192.0, 184.0), Palette.METAL_0, true)
		draw_rect(Rect2(4.0, 4.0, 184.0, 176.0), Palette.METAL_2, true)
		draw_rect(Rect2(4.0, 4.0, 184.0, 12.0), Palette.METAL_3, true)
		draw_rect(Rect2(16.0, 22.0, 160.0, 26.0), Palette.SPACE_DEEP, true)
		draw_rect(Rect2(20.0, 26.0, 52.0, 8.0), Palette.FUNK_CYAN, true)
		for index in range(8):
			var color := Palette.YEL_2 if index % 2 == 0 else Palette.HAZARD_ORANGE
			draw_rect(Rect2(8.0 + float(index) * 22.0, 56.0, 12.0, 8.0), color, true)
		var drum := Vector2(96.0, 116.0)
		draw_circle(drum, 60.0, Palette.SPACE_VOID)
		draw_arc(drum, 60.0, 0.0, TAU, 40, Palette.METAL_1, 6.0, true)
		draw_circle(drum, 48.0, Palette.SPACE_DEEP)
		draw_arc(drum, 34.0, 0.5, 2.6, 24, Palette.FUNK_CYAN, 4.0, true)
		draw_circle(drum + Vector2(-14.0, -18.0), 5.0, Palette.BLUE_4)
		draw_rect(Rect2(150.0, 150.0, 30.0, 10.0), Palette.METAL_1, true)

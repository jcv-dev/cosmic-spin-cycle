class_name CosmicWasher
extends StaticBody2D
## One washing machine: the pure [WasherFSM] plus every pixel, sound and stability effect.
##
## The node owns no washer rule. It turns a throw into `WasherFSM.insert`, forwards strikes,
## renders the state and applies the authoritative consequences (wrong washer -12,
## explosion -25, clean items bumped into `GameState.washed_count`, once per item).
##
## Feedback follows the measured UX notes: local chips instead of camera shake, turbulence
## gets a persistent 3-segment gauge + deadline timer, the drum starts on the beat and every
## action feedback is shorter than `0.45 x T_beat` (190 ms at 142 BPM).
##
## Wiring and the frozen state ordinals live in `docs/M4_WASHERS.md`.

signal item_loaded(item: Node)
signal item_rejected(item: Node, reason: String)
signal state_changed(old_state: int, new_state: int)
signal cycle_done(items: Array)
signal exploded
signal turbulence_resolved(grade: int)

## Frozen ordinals for `MainLevel`'s camera punctuation; identical to `WasherFSM.State`.
enum State { IDLE = 0, WASHING = 1, TURBULENT = 2, DONE = 3, BROKEN = 4 }

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

## The hologram sits on the machine's control panel: a 128x56 plaque whose bottom edge is
## 48 px below the `art_rect` top, so it never collides with the HUD corner plaques (which
## end at y = 104) and all four stay fully on screen at 1280x720.
const MACHINE_TOP := -184.0
const HOLO_DROP_PX := 48.0
const HOLO_ORIGIN := Vector2(0.0, -144.0)
## Steel cabinets are the brightest thing on screen; pull them back 12-15 % so the holo,
## items and chute win the eye.
const BODY_TINT := Color(0.97, 0.98, 1.0)

## Every action feedback must stay under `0.45 x T_beat`; 190 ms is the tightest phase.
const FEEDBACK_S := 0.18
## One rendered frame at 60 FPS (`red_1` porthole flash, mouth rim).
const RIM_FRAME_S := 0.02
## Wrong-washer buzz length.
const BUZZ_S := 0.12
## Delay between the two bell notes of a finished load.
const BELL_GAP_S := 0.15
const LOAD_FLASH_S := 0.18
## Explosion shake: 8 px maximum, quantised to whole art pixels (4 px steps).
const EXPLOSION_SHAKE_PX := 8.0
const SHAKE_STEP_PX := 4.0
## Turbulent drum vibration: 1 art px at 2 Hz.
const TURBULENCE_VIBRATION_PX := 4.0
const TURBULENCE_VIBRATION_HZ := 2.0
## Two alarm beeps on the beat, then silence (not a looping siren).
const ALARM_BEEPS := 2

const DRUM_DB := -16.0
const DONE_DB := -8.0
const EXPLODE_DB := -6.0
const ALARM_DB := -9.0
const BUZZ_DB := -12.0
const CLICK_DB := -12.0

const SFX_DIR := "res://assets/audio/sfx/"

## Stable identity from `data/layout.json` (`washer_nw`, …).
var washer_id: StringName = &""

## Holo presentation state for the current frame (read by `WasherFX.HoloPanel`).
var holo_state: int = HoloState.IDLE
var holo_alpha := 0.6
var holo_label := ""
var holo_tint: Color = Palette.METAL_3
var ring_color: Color = Palette.FUNK_CYAN

var _fsm: WasherFSM = WasherFSM.new()
var _configured := false
var _requirement: StringName = &"wild"
var _locked := false
var _holo_origin := HOLO_ORIGIN

var _visual: AnimatedSprite2D
var _holo: Node2D
var _ring: Node2D
var _glow: Node2D
var _fallback: Node2D
var _bubbles: AnimatedSprite2D
var _mouth: Area2D
var _body_shape: CollisionShape2D
var _mouth_shape: CollisionShape2D

var _audio: AudioStreamPlayer
var _oneshots: Array[AudioStreamPlayer] = []
var _oneshot_index := 0
var _buzz_player: AudioStreamPlayer
var _sfx: Dictionary = {}

var _carry_hint: Node = null
var _last_state := WasherFSM.State.IDLE
var _load_flash_left := 0.0
var _shake_left := 0.0
var _holo_flash := 0.0
var _beat_pulse := 0.0
var _last_beat := -1
var _alarm_pending := 0
var _animate_time := 0.0
var _reject_cooldown: Dictionary = {}
var _release_cooldown: Dictionary = {}
var _clean_counted: Dictionary = {}
var _absorbed: Dictionary = {}
var _rim_color: Color = Palette.CLEAN_GREEN
var _rim_left := 0.0
var _porthole_flash_color: Color = Palette.RED_1
var _porthole_flash_left := 0.0
var _turbulence_limit_s := 0.0
var _turbulence_elapsed := 0.0
var _start_pending := false
var _bell_repeat := 0.0
var _buzz_left := 0.0


func _ready() -> void:
	add_to_group(Config.GROUP_WASHERS)
	# WASHER identifies the machine; WORLD is what actually blocks the player (mask 1) and
	# the items (mask 1|4) with the frozen collision masks.
	collision_layer = Config.CollisionLayer.WASHER | Config.CollisionLayer.WORLD
	collision_mask = 0
	_ensure_collisions()
	_ensure_visual()
	_ensure_procedural()
	_ensure_bubbles()
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


## Mouth rim: a 1-frame clean-green flash on a correct load, orange on a wrong one.
func _draw() -> void:
	if _rim_left <= 0.0:
		return
	draw_arc(Vector2.ZERO, MOUTH_RADIUS, 0.0, TAU, 48, Color(_rim_color, 0.9), 3.0, true)


# --- public API -------------------------------------------------------------


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
	var center_x := (art_rect.position.x + art_rect.size.x * 0.5) * float(Config.ART_SCALE)
	var top_y := art_rect.position.y * float(Config.ART_SCALE)
	_holo_origin = Vector2(center_x - position.x, top_y - position.y + HOLO_DROP_PX)
	if _holo != null:
		_holo.position = _holo_origin
	_configured = true
	_requirement = &"wild" if requirement == &"" else requirement
	_fsm.set_requirement(_requirement)
	if is_node_ready():
		_apply_config()
		_holo_flash = FEEDBACK_S
		_update_visuals(0.0)


## Phase change hook: swaps the hologram requirement and flashes it.
func set_requirement(value: StringName) -> void:
	_requirement = &"wild" if value == &"" else value
	_fsm.set_requirement(_requirement)
	_holo_flash = FEEDBACK_S
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
	_flash_rim(Palette.CLEAN_GREEN)
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


# --- state + events ---------------------------------------------------------


func _handle_events(events: Array[Dictionary]) -> void:
	for event in events:
		match StringName(str(event.get("type", &""))):
			&"washing_started":
				_on_washing_started()
			&"turbulent":
				_on_turbulent(float(event.get("limit", Config.TURBULENCE_TIMEOUT_S)))
			&"turbulence_resolved":
				_on_turbulence_resolved(int(event.get("grade", -1)))
			&"cycle_done":
				_on_cycle_done(event.get("items", []))
			&"exploded":
				_on_exploded(event.get("items", []))
			&"repaired":
				_alarm_pending = 0
				_play_oneshot("click", CLICK_DB)
			_:
				pass


func _on_washing_started() -> void:
	_alarm_pending = 0
	# Correct insert: the drum starts (and chimes) on the next beat when music is running.
	if BeatConductor.is_playing:
		_start_pending = true
	else:
		_start_drum()


func _start_drum() -> void:
	_start_pending = false
	_play_loop("drum", DRUM_DB)
	_play_oneshot("click", CLICK_DB)


func _on_turbulent(limit: float) -> void:
	_turbulence_limit_s = maxf(limit, 0.0)
	_turbulence_elapsed = 0.0
	_alarm_pending = ALARM_BEEPS


func _on_turbulence_resolved(grade: int) -> void:
	_alarm_pending = 0
	_turbulence_elapsed = 0.0
	turbulence_resolved.emit(grade)
	_play_oneshot("click", CLICK_DB)


func _on_cycle_done(items: Array) -> void:
	_stop_loop()
	for item: Variant in items:
		_mark_clean(item)
	_play_oneshot("done", DONE_DB)
	_bell_repeat = BELL_GAP_S
	cycle_done.emit(items)


func _on_exploded(items: Array) -> void:
	_stop_loop()
	_alarm_pending = 0
	_play_oneshot("explode", EXPLODE_DB)
	_spawn_explosion_fx()
	_spawn_text("¡EXPLOSIÓN!", 24, Palette.HAZARD_ORANGE)
	_shake_left = FEEDBACK_S
	_flash_porthole(Palette.HAZARD_ORANGE)
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


# --- consequences -----------------------------------------------------------


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
			# Local and small: a -12 chip with a glyph, a 1-frame porthole flash and a buzz.
			_spawn_chip("-12", false, Palette.HAZARD_ORANGE)
			_flash_porthole(Palette.RED_1)
			_play_buzz()
			_flash_rim(Palette.HAZARD_ORANGE)
	elif reason_name == WasherFSM.REJECT_LOCKED:
		_play_oneshot("click", CLICK_DB)
		_flash_rim(Palette.METAL_2)
	_reject_cooldown[item.get_instance_id()] = REJECT_COOLDOWN_S
	_bounce(item)
	_update_visuals(0.0)
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


# --- rendering --------------------------------------------------------------


func _update_visuals(delta: float) -> void:
	_animate_time += delta
	_load_flash_left = maxf(_load_flash_left - delta, 0.0)
	_shake_left = maxf(_shake_left - delta, 0.0)
	_holo_flash = maxf(_holo_flash - delta, 0.0)
	var rim_was := _rim_left
	_rim_left = maxf(_rim_left - delta, 0.0)
	if rim_was > 0.0 and _rim_left <= 0.0:
		queue_redraw()
	_porthole_flash_left = maxf(_porthole_flash_left - delta, 0.0)
	var bell_due := _bell_repeat > 0.0 and _bell_repeat - delta <= 0.0
	_bell_repeat = maxf(_bell_repeat - delta, 0.0)
	_buzz_left = maxf(_buzz_left - delta, 0.0)
	if _buzz_left <= 0.0 and _buzz_player != null and _buzz_player.playing:
		_buzz_player.stop()
	if _fsm.get_state() == WasherFSM.State.TURBULENT:
		_turbulence_elapsed += delta
	if bell_due:
		_play_oneshot("done", DONE_DB)
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
	if _rim_left > 0.0:
		queue_redraw()
	if _bubbles != null:
		_bubbles.visible = _fsm.get_state() == WasherFSM.State.DONE


func _refresh_animation() -> void:
	if _visual == null:
		return
	var offset := Vector2.ZERO
	if _fsm.get_state() == WasherFSM.State.TURBULENT and not Settings.reduce_motion:
		var phase := _animate_time * TAU * TURBULENCE_VIBRATION_HZ
		offset.x = sin(phase) * TURBULENCE_VIBRATION_PX
	if _shake_left > 0.0 and not Settings.reduce_motion:
		var raw := sin(_animate_time * 140.0) * EXPLOSION_SHAKE_PX
		offset += Vector2(roundf(raw / SHAKE_STEP_PX) * SHAKE_STEP_PX, 0.0)
	_visual.position = offset
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
				text = tr("TURBULENTO")
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
	_holo.position = _holo_origin + Vector2(0.0, bob)
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
			var hot := state == WasherFSM.State.TURBULENT
			color = Palette.HAZARD_ORANGE if hot else Palette.FUNK_CYAN
		WasherFSM.State.DONE:
			mode = 2
			color = Palette.CLEAN_GREEN
		WasherFSM.State.BROKEN:
			mode = 3
			color = Palette.HAZARD_ORANGE
		_:
			mode = 0
	ring_color = color
	_ring.visible = mode != 0 or _porthole_flash_left > 0.0
	_ring.set(&"mode", mode)
	_ring.set(&"progress", _fsm.get_progress())
	_ring.set(&"ring_color", color)
	_ring.set(&"turbulent", state == WasherFSM.State.TURBULENT)
	_ring.set(&"time_left", maxf(_turbulence_limit_s - _turbulence_elapsed, 0.0))
	_ring.set(&"time_total", maxf(_turbulence_limit_s, 0.001))
	_ring.set(&"flash_color", _porthole_flash_color)
	_ring.set(&"flash_left", _porthole_flash_left)
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
	if _start_pending:
		_start_drum()
	if _fsm.get_state() == WasherFSM.State.TURBULENT and _alarm_pending > 0:
		_alarm_pending -= 1
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


# --- node construction ------------------------------------------------------


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
	_visual.self_modulate = BODY_TINT
	if SpriteSheet.configure(_visual, ART_ID, &"idle"):
		return
	_fallback = WasherFX.FallbackBody.new()
	_fallback.name = "FallbackBody"
	_fallback.position = Vector2(-96.0, MACHINE_TOP)
	_fallback.z_index = 0
	_fallback.self_modulate = BODY_TINT
	add_child(_fallback)


func _ensure_procedural() -> void:
	_holo = WasherFX.make_holo(self, _holo_origin)
	_ring = WasherFX.make_ring(self)
	_glow = WasherFX.make_glow(self)


func _ensure_bubbles() -> void:
	_bubbles = WasherFX.make_bubbles(self)


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
	_buzz_player = AudioStreamPlayer.new()
	_buzz_player.name = "AudioBuzz"
	if AudioServer.get_bus_index("SFX") >= 0:
		_buzz_player.bus = "SFX"
	_buzz_player.stream = _sfx["alarm"] as AudioStream
	add_child(_buzz_player)


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


# --- feedback helpers -------------------------------------------------------


func _flash_rim(color: Color) -> void:
	_rim_color = color
	_rim_left = RIM_FRAME_S
	queue_redraw()


func _flash_porthole(color: Color) -> void:
	_porthole_flash_color = color
	_porthole_flash_left = RIM_FRAME_S
	if _ring != null:
		_ring.queue_redraw()


func _play_buzz() -> void:
	if _buzz_player == null or _buzz_player.stream == null:
		return
	_buzz_player.volume_db = BUZZ_DB
	_buzz_player.play()
	_buzz_left = BUZZ_S


func _spawn_chip(text: String, gain: bool, color: Color) -> void:
	WasherFX.make_chip(self, text, gain, color)


func _spawn_text(text: String, size: int, color: Color) -> void:
	WasherFX.make_text(self, text, size, color)


func _spawn_explosion_fx() -> void:
	WasherFX.make_explosion(self, Vector2(0.0, -96.0))


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


# --- audio ------------------------------------------------------------------


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

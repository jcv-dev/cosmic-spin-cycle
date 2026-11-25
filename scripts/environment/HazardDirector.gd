class_name HazardDirector
extends Node
## Runs the hazard loop and owns the void meter (docs/DECISIONS.md D045/D046).
##
## One hazard per measure, announced on the measure (telegraph) and resolved on a beat, so
## dodging is a rhythm action: leaving the zone within the PERFECT window of the strike
## scores. The damage test reuses [HazardPlanner] so what you see is what hits you.

signal void_changed(value: float, collapsing: bool)
signal hazard_hit(kind: int, damage: float)
signal hazard_dodged(kind: int, perfect: bool)
signal collapse_started

const HAZARD_SCENE := "res://scenes/environment/Hazard.tscn"
const IMPACT_SFX := "res://assets/audio/sfx/washer_explode.ogg"
const DODGE_SFX := "res://assets/audio/sfx/throw_whoosh.ogg"
## How long the gravity-pocket axis flip lasts, in beats. One measure of disorientation.
const POCKET_BEATS := 4

var enabled := false
var difficulty := Config.DIFFICULTY_DEFAULT
var phase := 0
var shift_time := 0.0
var void_value := Config.VOID_START

var _player: Node2D
var _root: Node2D
var _rng := RandomNumberGenerator.new()
var _pending: Array[Dictionary] = []
var _last_anchor := Vector2.ZERO
var _invulnerable_left := 0.0
var _collapsing_left := 0.0
var _pocket_left := 0.0
## Live gravity wells (one per active void vent): centre, seconds left and damage tick.
var _fields: Array[Dictionary] = []
var _impact: AudioStreamPlayer
var _dodge: AudioStreamPlayer


func setup(player: Node2D, hazard_root: Node2D, seed_value: int, preset: int) -> void:
	_player = player
	_root = hazard_root
	difficulty = Config.difficulty_index(preset)
	_rng.seed = seed_value
	if not BeatConductor.measure_hit.is_connected(_on_measure):
		BeatConductor.measure_hit.connect(_on_measure)
	if not BeatConductor.beat_hit.is_connected(_on_beat):
		BeatConductor.beat_hit.connect(_on_beat)
	if not GameState.delivery_made.is_connected(_on_delivery):
		GameState.delivery_made.connect(_on_delivery)
	if not GameState.wrong_washer_made.is_connected(_on_wrong_washer):
		GameState.wrong_washer_made.connect(_on_wrong_washer)
	if not GameState.rhythm_missed.is_connected(_on_rhythm_missed):
		GameState.rhythm_missed.connect(_on_rhythm_missed)
	_ensure_audio()
	void_changed.emit(void_value, false)


func _exit_tree() -> void:
	if BeatConductor.measure_hit.is_connected(_on_measure):
		BeatConductor.measure_hit.disconnect(_on_measure)
	if BeatConductor.beat_hit.is_connected(_on_beat):
		BeatConductor.beat_hit.disconnect(_on_beat)
	if GameState.delivery_made.is_connected(_on_delivery):
		GameState.delivery_made.disconnect(_on_delivery)
	if GameState.wrong_washer_made.is_connected(_on_wrong_washer):
		GameState.wrong_washer_made.disconnect(_on_wrong_washer)
	if GameState.rhythm_missed.is_connected(_on_rhythm_missed):
		GameState.rhythm_missed.disconnect(_on_rhythm_missed)


func set_phase(index: int) -> void:
	phase = clampi(index, 0, Config.PHASE_BPM.size() - 1)


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		_fields.clear()


## Shift clock (seconds since 00:00). The director gates on it, never on audio time.
func advance_shift_time(t: float) -> void:
	shift_time = t


func void_fraction() -> float:
	return VoidIndex.fraction(void_value)


func is_collapsing() -> bool:
	return _collapsing_left > 0.0


## Gravity wells act on physics bodies, so they tick in `_physics_process`, never in `_input`.
func _physics_process(delta: float) -> void:
	if GameState.is_ended or _fields.is_empty():
		return
	for field: Dictionary in _fields.duplicate():
		field["left"] = float(field["left"]) - delta
		_pull_player(field)
		_pull_items(field)
		_tick_well_damage(field, delta)
		if float(field["left"]) <= 0.0:
			_fields.erase(field)


## Force (px/s²) that `strength` applies at `point` for a well centred on `center`.
## Zero outside `radius`; falls off linearly to the edge so the pull reads as physical.
static func well_force(center: Vector2, point: Vector2, strength: float, radius: float) -> Vector2:
	var offset := center - point
	var distance := offset.length()
	if distance <= 0.001 or distance > radius:
		return Vector2.ZERO
	return offset.normalized() * strength * (1.0 - distance / radius)


func _pull_player(field: Dictionary) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var center: Vector2 = field["center"]
	var body := _player as CharacterBody2D
	if body == null:
		return
	var pull := well_force(
		center,
		body.global_position,
		Config.HAZARD_VENT_PULL_SPEED,
		Config.HAZARD_VENT_GRAVITY_RADIUS_PX
	)
	# px/s handed to the player, which applies it as displacement so friction cannot eat it.
	body.set("field_velocity", pull)
	if body.global_position.distance_to(center) <= Config.HAZARD_VENT_RADIUS_PX:
		body.set("field_speed_scale", Config.HAZARD_VENT_SLOW_SCALE)


func _pull_items(field: Dictionary) -> void:
	var center: Vector2 = field["center"]
	for node: Node in get_tree().get_nodes_in_group(Config.GROUP_ITEMS):
		var body := node as RigidBody2D
		if body == null or body.freeze or body.get("is_held") == true:
			continue
		var distance := body.global_position.distance_to(center)
		if _swallows(body, distance):
			_swallow(body, center)
			continue
		var force := well_force(
			center,
			body.global_position,
			Config.HAZARD_VENT_ITEM_PULL,
			Config.HAZARD_VENT_GRAVITY_RADIUS_PX
		)
		if force != Vector2.ZERO:
			body.apply_central_force(force * body.mass)


## The core eats fast planets only: a resting item is dragged but never consumed, and the
## galaxy core is too dense (it is the shift's unique trophy).
func _swallows(body: RigidBody2D, distance: float) -> bool:
	if distance > Config.HAZARD_VENT_CORE_RADIUS_PX:
		return false
	if body.linear_velocity.length() < Config.HAZARD_VENT_SWALLOW_MIN_SPEED:
		return false
	return StringName(str(body.get(&"item_id"))) != &"galaxy_core"


func _swallow(body: RigidBody2D, center: Vector2) -> void:
	GameState.add_stability(Config.STABILITY_VOID_SWALLOW, "void")
	GameState.emit_feedback(tr("¡EL VACÍO SE LO TRAGÓ!"), &"danger")
	_spawn_well_chip(center, "-%d" % int(absf(Config.STABILITY_VOID_SWALLOW)))
	_play(_impact, 0.55, -12.0)
	body.queue_free()


## A chip needs a parent in the tree; the hazard that owns the well may already be gone, so a
## short-lived marker carries it and frees itself.
func _spawn_well_chip(center: Vector2, text: String) -> void:
	if _root == null:
		return
	var marker := Node2D.new()
	marker.position = center
	_root.add_child(marker)
	WasherFX.make_chip(marker, text, false, Palette.HAZARD_ORANGE)
	get_tree().create_timer(1.2).timeout.connect(marker.queue_free)


func _tick_well_damage(field: Dictionary, delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	field["tick"] = float(field["tick"]) - delta
	if float(field["tick"]) > 0.0:
		return
	field["tick"] = Config.HAZARD_VENT_TICK_S
	var center: Vector2 = field["center"]
	if _player.global_position.distance_to(center) <= Config.HAZARD_VENT_RADIUS_PX:
		_hit(Config.HazardKind.VOID_VENT)


func _process(delta: float) -> void:
	_tick_pocket(delta)
	if GameState.is_ended or not enabled:
		return
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_advance_void(delta)
	_watch_pending()


func _tick_pocket(delta: float) -> void:
	if _pocket_left <= 0.0:
		return
	_pocket_left = maxf(_pocket_left - delta, 0.0)
	if _pocket_left <= 0.0 and _player != null and _player.has_method("set_input_inverted"):
		_player.call("set_input_inverted", false)


func _advance_void(delta: float) -> void:
	if _collapsing_left > 0.0:
		_collapsing_left = maxf(_collapsing_left - delta, 0.0)
	var next := VoidIndex.advance(void_value, delta, phase, difficulty)
	if VoidIndex.is_collapse(next):
		_collapse()
		return
	if next != void_value:
		void_value = next
		void_changed.emit(void_value, is_collapsing())


func _collapse() -> void:
	void_value = VoidIndex.after_collapse()
	_collapsing_left = Config.DIFFICULTY_COLLAPSE_S[Config.difficulty_index(difficulty)]
	void_changed.emit(void_value, true)
	collapse_started.emit()
	GameState.emit_feedback(tr("¡COLAPSO DE VACÍO!"), &"danger")


func _on_measure(measure: int) -> void:
	if not _can_spawn():
		return
	_plan(measure, 0)
	if is_collapsing():
		_plan(measure, Config.BEATS_PER_MEASURE / 2)


func _plan(measure: int, beat_offset: int) -> void:
	var avoid := Vector2.ZERO
	if _player != null and is_instance_valid(_player):
		avoid = _player.global_position
	var entry := HazardPlanner.plan(phase, difficulty, _rng, _last_anchor, avoid)
	if entry.is_empty():
		return
	var warning := Config.DIFFICULTY_WARNING_BEATS[Config.difficulty_index(difficulty)]
	var center: Vector2 = entry["pos"]
	var packed: PackedScene = load(HAZARD_SCENE)
	var node := packed.instantiate() as Hazard
	if node == null:
		return
	_root.add_child(node)
	node.setup(
		int(entry["kind"]),
		center,
		float(entry.get("angle", 0.0)),
		float(warning) * Config.beat_seconds(float(Config.PHASE_BPM[phase]))
	)
	_last_anchor = center
	var strike_beat := measure * Config.BEATS_PER_MEASURE + warning + beat_offset
	(
		_pending
		. append(
			{
				"strike_beat": strike_beat,
				"kind": int(entry["kind"]),
				"center": center,
				"angle": float(entry.get("angle", 0.0)),
				"node": node,
				"exit_time": -1.0,
				"was_inside": false,
			}
		)
	)


func _on_beat(beat: int) -> void:
	if _pending.is_empty():
		return
	var due: Array[Dictionary] = []
	for entry: Dictionary in _pending.duplicate():
		if beat >= int(entry["strike_beat"]):
			due.append(entry)
	for entry: Dictionary in due:
		_resolve(entry)


## Tracks the exact frame the player leaves the zone, so the dodge can be graded on the beat.
func _watch_pending() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var now := BeatConductor.get_song_time()
	var point := _player.global_position
	for entry: Dictionary in _pending:
		var inside := HazardPlanner.contains(
			int(entry["kind"]), entry["center"], float(entry["angle"]), point
		)
		if inside:
			entry["was_inside"] = true
			entry["exit_time"] = -1.0
		elif bool(entry["was_inside"]) and float(entry["exit_time"]) < 0.0:
			entry["exit_time"] = now


func _resolve(entry: Dictionary) -> void:
	_pending.erase(entry)
	var node: Hazard = entry["node"]
	var beat_s := Config.beat_seconds(float(Config.PHASE_BPM[phase]))
	var kind := int(entry["kind"])
	var active_s := beat_s * float(Config.HAZARD_ACTIVE_BEATS)
	if kind == Config.HazardKind.VOID_VENT:
		active_s = beat_s * float(Config.HAZARD_VENT_ACTIVE_BEATS)
		_fields.append({"center": entry["center"], "left": active_s, "tick": 0.0})
	if node != null and is_instance_valid(node):
		node.strike(active_s)
	var center: Vector2 = entry["center"]
	var angle := float(entry["angle"])
	var inside := (
		_player != null
		and is_instance_valid(_player)
		and HazardPlanner.contains(kind, center, angle, _player.global_position)
	)
	var strike_time := BeatConductor.get_song_time()
	var exit_time := float(entry["exit_time"])
	var perfect := (
		not inside
		and exit_time >= 0.0
		and absf(strike_time - exit_time) <= Config.WINDOW_PERFECT_S * Settings.window_scale()
	)
	if kind == Config.HazardKind.GRAVITY_POCKET:
		if inside and _player != null and _player.has_method("set_input_inverted"):
			_player.call("set_input_inverted", true)
			_pocket_left = float(POCKET_BEATS) * Config.beat_seconds(float(Config.PHASE_BPM[phase]))
		hazard_dodged.emit(kind, perfect)
		if perfect:
			_reward_dodge()
		return
	if inside:
		_hit(kind)
		return
	hazard_dodged.emit(kind, perfect)
	if perfect:
		_reward_dodge()
	else:
		# A safe dodge still gets an audible "you passed" so silence never means "nothing
		# happened" (owner report).
		_play(_dodge, 0.85, -16.0)


func _hit(kind: int) -> void:
	if _invulnerable_left > 0.0:
		return
	var preset := Config.difficulty_index(difficulty)
	_invulnerable_left = Config.DIFFICULTY_IFRAME_S[preset]
	var damage := Config.DIFFICULTY_HIT_DAMAGE[preset]
	GameState.add_stability(damage, "hazard")
	GameState.emit_feedback(tr("¡GOLPE DEL VACÍO!"), &"danger")
	hazard_hit.emit(kind, damage)
	# Four channels of feedback, because one was not enough (owner: "no veo nada").
	Juice.flash(Palette.HAZARD_ORANGE, 0.10)
	if _player != null and is_instance_valid(_player) and _player is Node2D:
		WasherFX.make_chip(
			_player as Node2D, "-%d" % int(absf(damage)), false, Palette.HAZARD_ORANGE
		)
	if kind == Config.HazardKind.METEOR:
		Juice.hitstop(Config.HAZARD_METEOR_HITSTOP_S)
	else:
		Juice.hitstop(0.05)
	Juice.shake(0.45, 0.3)
	_play(_impact, 0.95, -8.0)


func _reward_dodge() -> void:
	GameState.add_score(Config.HAZARD_DODGE_POINTS)
	void_value = VoidIndex.bump(void_value, Config.VOID_PERFECT_DODGE_RELIEF)
	void_changed.emit(void_value, is_collapsing())
	GameState.emit_feedback(tr("¡ESQUIVA PERFECTA!"), &"rhythm")
	if _player != null and is_instance_valid(_player) and _player is Node2D:
		WasherFX.make_chip(
			_player as Node2D, "+%d" % Config.HAZARD_DODGE_POINTS, true, Palette.FUNK_CYAN
		)


func _ensure_audio() -> void:
	if _impact != null:
		return
	_impact = _make_player(IMPACT_SFX, -8.0)
	_dodge = _make_player(DODGE_SFX, -12.0)


func _make_player(path: String, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		player.stream = load(path) as AudioStream
	player.volume_db = volume_db
	if AudioServer.get_bus_index("SFX") >= 0:
		player.bus = "SFX"
	add_child(player)
	return player


func _play(player: AudioStreamPlayer, pitch: float, volume_db: float) -> void:
	if player == null or player.stream == null:
		return
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


func _can_spawn() -> bool:
	return (
		enabled and not GameState.is_ended and shift_time >= Config.HAZARD_FIRST_S and _root != null
	)


func _on_delivery() -> void:
	void_value = VoidIndex.bump(void_value, Config.VOID_DELIVERY_RELIEF)
	void_changed.emit(void_value, is_collapsing())


func _on_wrong_washer() -> void:
	void_value = VoidIndex.bump(void_value, Config.VOID_WRONG_WASHER_GAIN)
	void_changed.emit(void_value, is_collapsing())


func _on_rhythm_missed() -> void:
	void_value = VoidIndex.bump(void_value, Config.VOID_MISS_GAIN)
	void_changed.emit(void_value, is_collapsing())

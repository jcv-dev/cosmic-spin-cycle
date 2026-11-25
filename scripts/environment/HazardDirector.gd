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


## Shift clock (seconds since 00:00). The director gates on it, never on audio time.
func advance_shift_time(t: float) -> void:
	shift_time = t


func void_fraction() -> float:
	return VoidIndex.fraction(void_value)


func is_collapsing() -> bool:
	return _collapsing_left > 0.0


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
	var entry := HazardPlanner.plan(phase, difficulty, _rng, _last_anchor)
	if entry.is_empty():
		return
	var warning := Config.DIFFICULTY_WARNING_BEATS[Config.difficulty_index(difficulty)]
	var center := HazardPlanner.world_position(entry)
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
	_last_anchor = entry["art_pos"]
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
	if node != null and is_instance_valid(node):
		node.strike(Config.beat_seconds(float(Config.PHASE_BPM[phase])))
	var kind := int(entry["kind"])
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


func _hit(kind: int) -> void:
	if _invulnerable_left > 0.0:
		return
	var preset := Config.difficulty_index(difficulty)
	_invulnerable_left = Config.DIFFICULTY_IFRAME_S[preset]
	var damage := Config.DIFFICULTY_HIT_DAMAGE[preset]
	GameState.add_stability(damage, "hazard")
	GameState.emit_feedback(tr("¡GOLPE DEL VACÍO!"), &"danger")
	hazard_hit.emit(kind, damage)
	if kind == Config.HazardKind.METEOR:
		Juice.hitstop(Config.HAZARD_METEOR_HITSTOP_S)
	Juice.shake(0.4, 0.3)


func _reward_dodge() -> void:
	GameState.add_score(Config.HAZARD_DODGE_POINTS)
	void_value = VoidIndex.bump(void_value, Config.VOID_PERFECT_DODGE_RELIEF)
	void_changed.emit(void_value, is_collapsing())
	GameState.emit_feedback(tr("¡ESQUIVA PERFECTA!"), &"rhythm")


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

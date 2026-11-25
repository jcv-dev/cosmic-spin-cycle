extends SceneTree
## Headless game-feel benchmark for the player/item feel pass.
##
##   godot --headless --path . --fixed-fps 60 -s tools/feel_probe.gd
##
## Drives the real Player scene through five seconds of movement, a dash and ten
## throws, then prints machine-readable `FEEL_PROBE key=value` lines so the before/after
## table in `docs/FEEL.md` is reproducible rather than remembered. Not shipped in exports.
##
## The probe keeps every gameplay node dynamically typed on purpose: a static reference
## to `Player` would compile `Player.gd` while the main-loop script itself is compiled,
## which is before autoload singletons exist, and the run would abort.

enum State { ACCEL, CRUISE, BRAKE, TURN, DASH, THROWS, DONE }

const CONFIG = preload("res://scripts/autoload/Config.gd")
const PLAYER_SCENE := "res://scenes/entities/Player.tscn"
const ITEM_SCENE := "res://scenes/entities/LaundryItem.tscn"
const CRUISE_FRAMES := 180
const THROW_COUNT := 10
const ITEM_SPAWN_AHEAD := 40.0
const THROW_SETTLE_FRAMES := 4
## Ignore the first two seconds: GDScript compiles lazily and the first frame is not a cost.
const COST_WARMUP_FRAMES := 120

var _player: Node = null
var _game_state: Node = null
var _beat: Node = null
var _items_root: Node2D = null
var _state := State.ACCEL
var _state_frames := 0
var _clock := 0.0
var _turn_started := false
var _throw_index := 0
var _thrown_item: Node = null

var _accel_time := -1.0
var _stop_time := -1.0
var _turnaround_time := -1.0
var _dash_distance := -1.0
var _throw_speed_sum := 0.0
var _throw_speed_min := INF
var _process_cost_sum := 0.0
var _physics_cost_sum := 0.0
var _cost_samples := 0
var _cost_steady := 0
var _last_physics_frame := -1
var _saw_nan := false
var _booted := false
var _preset := -1


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			_preset = int(arg.trim_prefix("--preset="))
	_last_physics_frame = Engine.get_physics_frames()


func _boot() -> void:
	_game_state = root.get_node_or_null("GameState")
	_beat = root.get_node_or_null("BeatConductor")
	_game_state.call("reset", 4242)
	_beat.call("stop")
	_beat.call("set_stream", null, 0.0)
	_beat.call("start", 120)
	_beat.set_process(false)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(_player)
	(_player as Node2D).global_position = Vector2(200.0, 360.0)
	_player.call("set_aim_direction", Vector2.RIGHT)
	if _preset >= 0:
		_player.call("set_feel_preset", _preset)
	_items_root = Node2D.new()
	_items_root.name = "ProbeItems"
	root.add_child(_items_root)


func _process(_delta: float) -> bool:
	if not _booted:
		_booted = true
		_boot()
		return false
	var physics_frame := Engine.get_physics_frames()
	if physics_frame == _last_physics_frame:
		return false
	_last_physics_frame = physics_frame
	_sample_cost()
	_tick_physics()
	if _saw_nan:
		print("FEEL_PROBE nan=true")
		return true
	if _state == State.DONE:
		_print_results()
		return true
	return false


func _sample_cost() -> void:
	if _cost_samples >= COST_WARMUP_FRAMES:
		_process_cost_sum += Performance.get_monitor(Performance.TIME_PROCESS)
		_physics_cost_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		_cost_steady += 1
	_cost_samples += 1


func _tick_physics() -> void:
	_state_frames += 1
	match _state:
		State.ACCEL:
			_tick_accel()
		State.CRUISE:
			_tick_cruise()
		State.BRAKE:
			_tick_brake()
		State.TURN:
			_tick_turn()
		State.DASH:
			_tick_dash()
		State.THROWS:
			_tick_throws()


func _tick_accel() -> void:
	if _state_frames == 1:
		Input.action_press(&"move_right")
	_clock += _physics_delta()
	_check_nan()
	if _speed() >= CONFIG.PLAYER_MAX_SPEED * 0.9:
		_accel_time = _clock
		_next_state(State.CRUISE)


func _tick_cruise() -> void:
	_check_nan()
	if _state_frames >= CRUISE_FRAMES:
		Input.action_release(&"move_right")
		_clock = 0.0
		_next_state(State.BRAKE)


func _tick_brake() -> void:
	_clock += _physics_delta()
	_check_nan()
	if _speed() <= CONFIG.PLAYER_MAX_SPEED * 0.02:
		_stop_time = _clock
		_next_state(State.TURN)


func _tick_turn() -> void:
	if not _turn_started:
		if _state_frames == 1:
			Input.action_press(&"move_right")
		if _velocity().x >= CONFIG.PLAYER_MAX_SPEED * 0.9:
			Input.action_release(&"move_right")
			Input.action_press(&"move_left")
			_turn_started = true
			_clock = 0.0
		return
	_clock += _physics_delta()
	_check_nan()
	if _velocity().x <= -CONFIG.PLAYER_MAX_SPEED * 0.9:
		_turnaround_time = _clock
		Input.action_release(&"move_left")
		_next_state(State.DASH)


func _tick_dash() -> void:
	if _state_frames == 1:
		_player.set("velocity", Vector2.ZERO)
		_player.call("dash", Vector2.RIGHT)
		return
	if not bool(_player.get("is_dashing")):
		_dash_distance = float(_player.get("last_dash_distance"))
		_next_state(State.THROWS)


func _tick_throws() -> void:
	if _state_frames == 1:
		_throw_index = 0
		_begin_throw()
		return
	if _state_frames % THROW_SETTLE_FRAMES != 1:
		return
	_finish_throw()
	if _throw_index >= THROW_COUNT:
		_next_state(State.DONE)
		return
	_begin_throw()


func _begin_throw() -> void:
	var item := (load(ITEM_SCENE) as PackedScene).instantiate()
	item.call("setup", &"rocky", &"red", &"solid", false)
	_items_root.add_child(item)
	(item as Node2D).global_position = (
		(_player as Node2D).global_position + Vector2(ITEM_SPAWN_AHEAD, 0.0)
	)
	_thrown_item = item
	_player.call("grab_or_throw")
	_player.call("grab_or_throw")


func _finish_throw() -> void:
	if _thrown_item == null or not is_instance_valid(_thrown_item):
		return
	var velocity: Variant = _thrown_item.get("linear_velocity")
	var speed := (velocity as Vector2).length()
	if is_nan(speed):
		_saw_nan = true
	else:
		_throw_speed_sum += speed
		_throw_speed_min = minf(_throw_speed_min, speed)
	_throw_index += 1
	_thrown_item.queue_free()
	_thrown_item = null


func _next_state(next: State) -> void:
	_state = next
	_state_frames = 0


func _speed() -> float:
	return _velocity().length()


func _velocity() -> Vector2:
	var value: Variant = _player.get("velocity")
	return value as Vector2


func _check_nan() -> void:
	var velocity := _velocity()
	if is_nan(velocity.x) or is_nan(velocity.y):
		_saw_nan = true


func _physics_delta() -> float:
	return 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)


func _print_results() -> void:
	var frame_cost := (_process_cost_sum / maxf(float(_cost_steady), 1.0)) * 1000.0
	var physics_cost := (_physics_cost_sum / maxf(float(_cost_steady), 1.0)) * 1000.0
	var throw_avg := _throw_speed_sum / maxf(float(_throw_index), 1.0)
	print("FEEL_PROBE accel_90_ms=%.1f" % (_accel_time * 1000.0))
	print("FEEL_PROBE stop_ms=%.1f" % (_stop_time * 1000.0))
	print("FEEL_PROBE turnaround_ms=%.1f" % (_turnaround_time * 1000.0))
	print("FEEL_PROBE dash_distance_px=%.1f" % _dash_distance)
	print("FEEL_PROBE throw_avg_speed=%.1f" % throw_avg)
	print("FEEL_PROBE throw_min_speed=%.1f" % _throw_speed_min)
	print("FEEL_PROBE process_ms=%.3f" % frame_cost)
	print("FEEL_PROBE physics_ms=%.3f" % physics_cost)
	print("FEEL_PROBE samples=%d" % _cost_samples)
	print("FEEL_PROBE steady_samples=%d" % _cost_steady)
	print("FEEL_PROBE nan=false")

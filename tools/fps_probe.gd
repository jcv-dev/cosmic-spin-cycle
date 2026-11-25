extends SceneTree
## 60-second frame probe for the environment pass (UX_BIBLE §14).
##
##   godot --path . -s tools/fps_probe.gd --resolution 1280x720 --audio-driver Dummy \
##         --display-driver wayland --rendering-method gl_compatibility \
##         -- --scene=res://scenes/dev/EnvironmentSandbox.tscn --seconds=60
##
## V-sync is disabled so the numbers measure what the frame costs, not the 60 Hz cap. The
## first `WARMUP_FRAMES` frames are dropped (shader and texture warm-up). The summary is one
## line per metric so it can be pasted into `docs/ENVIRONMENT.md`.
##
## Not shipped in exports (`tools/` is excluded from the presets).

const DEFAULT_SCENE := "res://scenes/dev/EnvironmentSandbox.tscn"
const DEFAULT_SECONDS := 60.0
const WARMUP_FRAMES := 45

var _scene_path := DEFAULT_SCENE
var _seconds := DEFAULT_SECONDS
var _size := Vector2i(1280, 720)
var _probe_viewport: SubViewport

var _elapsed := 0.0
var _frames := 0
var _frame_ms: Array[float] = []
var _draw_calls := 0.0
var _objects := 0.0
var _samples := 0
var _done := false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			if parts.size() == 2:
				_size = Vector2i(int(parts[0]), int(parts[1]))
	var scene := load(_scene_path) as PackedScene
	if scene == null:
		push_error("fps_probe: cannot load " + _scene_path)
		quit(1)
		return
	# Render into a fixed 1280×720 SubViewport instead of the window: the desktop compositor
	# owns the window size here (it reported 945×1142 mid-run), which would silently change
	# the resolution the numbers describe.
	_probe_viewport = SubViewport.new()
	_probe_viewport.name = "ProbeViewport"
	_probe_viewport.size = _size
	_probe_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_probe_viewport.gui_disable_input = true
	root.add_child(_probe_viewport)
	_probe_viewport.add_child(scene.instantiate())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("FPS_PROBE_BOOT scene=%s seconds=%.1f size=%s" % [_scene_path, _seconds, str(_size)])


func _process(delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames <= WARMUP_FRAMES:
		return false
	_elapsed += delta
	_frame_ms.append(delta * 1000.0)
	_draw_calls += float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_objects += float(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_samples += 1
	if _elapsed >= _seconds:
		_summary()
		_done = true
		return true
	return false


func _summary() -> void:
	if _frame_ms.is_empty():
		print("FPS_PROBE_EMPTY")
		return
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for value: float in _frame_ms:
		total += value
	var average := total / float(_frame_ms.size())
	var worst: float = sorted[sorted.size() - 1]
	var p95: float = sorted[int(float(sorted.size() - 1) * 0.95)]
	var p99: float = sorted[int(float(sorted.size() - 1) * 0.99)]
	print(
		(
			"FPS_PROBE frames=%d seconds=%.1f fps_min=%.1f fps_avg=%.1f"
			% [_samples, _elapsed, 1000.0 / worst, 1000.0 / average]
		)
	)
	print("FRAME_MS avg=%.3f p95=%.3f p99=%.3f max=%.3f" % [average, p95, p99, worst])
	print(
		(
			"DRAW_CALLS avg=%.1f OBJECTS avg=%.1f"
			% [_draw_calls / float(_samples), _objects / float(_samples)]
		)
	)
	print("CANVAS size=%s" % str(_probe_viewport.size))
	print("PROCESS_MS avg=%.3f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0))
	print("FPS_PROBE_OK")

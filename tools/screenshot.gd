extends SceneTree
## Dev-only screenshot harness. Renders a scene offscreen at an exact pixel size and saves
## a PNG.
##
##   godot --path . -s tools/screenshot.gd --audio-driver Dummy --display-driver wayland \
##         --rendering-method gl_compatibility -- \
##         --scene=res://scenes/main/Main.tscn --out=res://docs/media/title.png --frames=12
##
## The scene is rendered into a 1280x720 SubViewport, so the PNG is exactly one art frame
## regardless of the compositor's HiDPI scale (Wayland otherwise opens at 1900x1068).
## Not shipped in exports (tools/ is excluded from export presets).

const DEFAULT_OUT := "res://.work/screens/main.png"
const DEFAULT_FRAMES := 12
const DEFAULT_SCENE := "res://scenes/main/Main.tscn"

var _frames := 0
var _target := DEFAULT_FRAMES
var _out := DEFAULT_OUT
var _scene_path := DEFAULT_SCENE
var _time := -1.0
var _size := Vector2i(1280, 720)

var _viewport: SubViewport
var _instance: Node


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			_target = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--scene="):
			_scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--time="):
			_time = float(arg.trim_prefix("--time="))
		elif arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			if parts.size() == 2:
				_size = Vector2i(int(parts[0]), int(parts[1]))
	var scene := load(_scene_path) as PackedScene
	if scene == null:
		push_error("cannot load scene " + _scene_path)
		quit(1)
		return
	_viewport = SubViewport.new()
	_viewport.name = "ScreenshotViewport"
	_viewport.size = _size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	root.add_child(_viewport)
	_instance = scene.instantiate()
	_viewport.add_child(_instance)
	if _time >= 0.0:
		var level := _find_shift_level(_instance)
		if level != null:
			if level.has_method("warp_to"):
				level.call("warp_to", _time)
			else:
				level.call("set_shift_time", _time)
	print(
		(
			"SCREENSHOT_BOOT ok scene=%s time=%.1f frames=%d size=%s out=%s"
			% [_scene_path, _time, _target, str(_size), _out]
		)
	)


func _find_shift_level(node: Node) -> Node:
	if node.has_method("set_shift_time") and node.has_method("warp_to"):
		return node
	for child in node.get_children():
		var found := _find_shift_level(child)
		if found != null:
			return found
	return null


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < _target:
		return false
	var items := _viewport.find_child("Items", true, false)
	var level := _find_shift_level(_viewport)
	var state := root.get_node_or_null("GameState")
	print(
		(
			"SCREENSHOT_STATE items=%d stability=%.1f t=%.1f"
			% [
				items.get_child_count() if items != null else -1,
				float(state.get("stability")) if state != null else -1.0,
				float(level.call("get_shift_time")) if level != null else -1.0,
			]
		)
	)
	var texture := _viewport.get_texture()
	if texture == null:
		push_error("no viewport texture")
		return true
	var img := texture.get_image()
	if img == null:
		push_error("no viewport image (headless?)")
		return true
	var dir := _out.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(_out)
	print("SCREENSHOT_SAVED %s size=%s err=%d" % [_out, str(img.get_size()), err])
	return true

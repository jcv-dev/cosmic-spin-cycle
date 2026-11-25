extends SceneTree
## Dev-only screenshot harness. Renders the real main scene for N frames and writes a PNG.
##
##   godot --path . -s tools/screenshot.gd --resolution 1280x720 --audio-driver Dummy \
##         --display-driver x11 --rendering-method gl_compatibility
##
## Not shipped in exports (tools/ is excluded from export presets).

const DEFAULT_OUT := "res://.work/screens/main.png"
const DEFAULT_FRAMES := 12
const DEFAULT_SCENE := "res://scenes/main/Main.tscn"

var _frames := 0
var _target := DEFAULT_FRAMES
var _out := DEFAULT_OUT
var _scene_path := DEFAULT_SCENE
var _time := -1.0


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
	var scene := load(_scene_path) as PackedScene
	if scene == null:
		push_error("cannot load scene " + _scene_path)
		quit(1)
		return
	var instance := scene.instantiate()
	root.add_child(instance)
	if _time >= 0.0:
		var level := _find_shift_level(instance)
		if level != null:
			if level.has_method("warp_to"):
				level.call("warp_to", _time)
			else:
				level.call("set_shift_time", _time)
	print(
		(
			"SCREENSHOT_BOOT ok scene=%s time=%.1f frames=%d out=%s"
			% [_scene_path, _time, _target, _out]
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
	var items := root.find_child("Items", true, false)
	var level := _find_shift_level(root)
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
	var img := root.get_texture().get_image()
	if img == null:
		push_error("no viewport image (headless?)")
		return true
	var dir := _out.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(_out)
	print("SCREENSHOT_SAVED %s size=%s err=%d" % [_out, str(img.get_size()), err])
	return true

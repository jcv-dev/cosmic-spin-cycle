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


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			_target = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--scene="):
			_scene_path = arg.trim_prefix("--scene=")
	var scene := load(_scene_path) as PackedScene
	if scene == null:
		push_error("cannot load scene " + _scene_path)
		quit(1)
		return
	root.add_child(scene.instantiate())
	print("SCREENSHOT_BOOT ok scene=%s frames=%d out=%s" % [_scene_path, _target, _out])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < _target:
		return false
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

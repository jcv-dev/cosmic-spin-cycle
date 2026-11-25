extends GutTest
## CameraRig: lead clamp, deadzone, whole-pixel output, kick decay, zoom-out flag and the
## reduce-motion contract.

const RIG_SCRIPT := preload("res://scripts/main/CameraRig.gd")

var _rig: CameraRig = null
var _target: CharacterBody2D = null


func before_each() -> void:
	_target = CharacterBody2D.new()
	add_child_autofree(_target)
	_target.global_position = Vector2(640.0, 360.0)
	_rig = RIG_SCRIPT.new()
	add_child_autofree(_rig)
	_rig.setup(_target)


func after_each() -> void:
	_rig.set_reduce_motion(false)


func _step(frames: int, duration: float = 1.0 / 60.0) -> void:
	for frame in range(frames):
		_rig.call("_process", duration)


func test_setup_snaps_to_the_target_and_stays_enabled() -> void:
	assert_eq(_rig.target, _target)
	assert_true(_rig.enabled)
	assert_eq(_rig.global_position, Vector2(640.0, 360.0), "rig starts centred on the target")


func test_lead_is_clamped_to_fifty_four_pixels() -> void:
	_target.velocity = Vector2(5000.0, -4000.0)
	var lead := _rig.get_lead_offset()
	assert_lt(lead.length(), CameraRig.MAX_LEAD_PX + 0.01, "lead never exceeds the clamp")
	assert_gt(lead.length(), CameraRig.MAX_LEAD_PX - 0.01, "lead saturates at the clamp")


func test_deadzone_ignores_small_target_motion() -> void:
	_target.global_position = Vector2(650.0, 360.0)
	_step(30)
	assert_eq(_rig.global_position.x, 640.0, "10 px inside the 24 px deadzone does not move")


func test_follow_smooths_toward_a_distant_target() -> void:
	_target.global_position = Vector2(1000.0, 360.0)
	_step(1)
	assert_gt(_rig.global_position.x, 640.0, "camera starts moving on the first frame")
	assert_lt(_rig.global_position.x, 1000.0, "but does not snap across the room")
	_step(120)
	assert_almost_eq(_rig.global_position.x, 1000.0 - CameraRig.DEADZONE_PX, 4.0)


func test_camera_position_and_shake_are_whole_pixels() -> void:
	_target.global_position = Vector2(700.0, 380.0)
	_rig.shake(1.0, 0.5)
	var maximum := 0.0
	for frame in range(20):
		_rig.call("_process", 1.0 / 60.0)
		var offset := _rig.get_shake_offset()
		assert_almost_eq(offset.x, roundf(offset.x), 0.0001, "shake x is a whole pixel")
		assert_almost_eq(offset.y, roundf(offset.y), 0.0001, "shake y is a whole pixel")
		assert_almost_eq(_rig.global_position.x, roundf(_rig.global_position.x), 0.0001)
		assert_almost_eq(_rig.global_position.y, roundf(_rig.global_position.y), 0.0001)
		maximum = maxf(maximum, offset.length())
	assert_lte(maximum, 6.0, "shared shake is capped at 6 px")


func test_kick_is_capped_and_decays_to_zero() -> void:
	var before := _rig.global_position
	_rig.kick(Vector2.RIGHT, 100.0)
	_rig.call("_process", 1.0 / 60.0)
	assert_gt(_rig.global_position.x, before.x, "kick moves the camera right")
	_step(120)
	assert_almost_eq(_rig.global_position.x, before.x, 1.0, "kick decays back to the follow point")
	assert_lt(_rig.get("_kick_offset").length(), 0.06)


func test_reduce_motion_disables_shake_and_kick_and_halves_lead() -> void:
	_target.velocity = Vector2(340.0, 0.0)
	var full_lead := _rig.get_lead_offset().length()
	_rig.set_reduce_motion(true)
	var reduced_lead := _rig.get_lead_offset().length()
	assert_almost_eq(reduced_lead, full_lead * 0.5, 0.5, "reduce motion halves the lead")
	_rig.shake(1.0, 0.5)
	assert_eq(_rig.get_shake_offset(), Vector2.ZERO, "shake is disabled")
	_target.velocity = Vector2.ZERO
	_step(30)
	var before := _rig.global_position
	_rig.kick(Vector2.RIGHT, 8.0)
	_step(2)
	assert_eq(_rig.global_position, before, "kick is disabled")


func test_zoom_out_reaches_but_never_crosses_the_cap() -> void:
	_rig.zoom_out_enabled = true
	_rig.flight_count = CameraRig.FLIGHT_ZOOM_THRESHOLD + 2
	for frame in range(240):
		_rig.call("_update_zoom", 1.0 / 60.0)
	assert_lt(_rig.zoom.x, 0.995, "many items in flight pull the camera back")
	assert_gte(_rig.zoom.x, CameraRig.ZOOM_MIN - 0.0001, "zoom-out is capped at 0.97")


func test_zoom_out_is_disabled_by_its_flag() -> void:
	_rig.zoom_out_enabled = false
	_rig.flight_count = 10
	for frame in range(120):
		_rig.call("_update_zoom", 1.0 / 60.0)
	assert_almost_eq(_rig.zoom.x, 1.0, 0.0005, "flag off keeps the zoom at 1.0")


func test_scan_ignores_held_items() -> void:
	var item := (load(Config.SCENE_LAUNDRY_ITEM) as PackedScene).instantiate() as LaundryItem
	item.setup(&"rocky", &"red", &"solid", false)
	add_child_autofree(item)
	item.global_position = Vector2(300.0, 300.0)
	item.linear_velocity = Vector2(400.0, 0.0)
	await wait_physics_frames(1)
	assert_eq(_rig.refresh_flight_count(), 1, "a fast free item counts as in flight")
	item.begin_hold(_target)
	await wait_physics_frames(1)
	assert_eq(_rig.refresh_flight_count(), 0, "held items never count")

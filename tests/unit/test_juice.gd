extends GutTest
## Juice: trauma clamp/decay, whole-pixel shake, non-stacking hitstop, one-frame flash,
## zoom punch and the reduce-motion kill switch.

const JUICE_SCRIPT := preload("res://scripts/autoload/Juice.gd")

var _juice: Node = null


func before_each() -> void:
	_juice = JUICE_SCRIPT.new()
	_juice.name = "JuiceUnderTest"
	add_child_autofree(_juice)


func after_each() -> void:
	_juice.release_motion()
	_juice.set_process(false)
	Engine.time_scale = 1.0


func _simulate(seconds: float, step: float = 1.0 / 60.0) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		_juice.call("_process", step)
		elapsed += step


func test_shake_accumulates_and_clamps_at_one() -> void:
	_juice.shake(5.0, 0.2)
	assert_almost_eq(float(_juice.get("trauma")), 1.0, 0.0001, "trauma is clamped to 1")
	_juice.shake(5.0, 0.2)
	assert_almost_eq(float(_juice.get("trauma")), 1.0, 0.0001, "shaking again cannot exceed 1")


func test_shake_decays_to_zero_over_its_duration() -> void:
	_juice.shake(1.0, 0.2)
	_simulate(0.1)
	assert_lt(float(_juice.get("trauma")), 0.75, "trauma decays over time")
	assert_gt(float(_juice.get("trauma")), 0.25, "half the duration leaves roughly half")
	_simulate(0.2)
	assert_almost_eq(float(_juice.get("trauma")), 0.0, 0.0001, "trauma reaches zero")
	assert_eq(_juice.get_shake_offset(), Vector2.ZERO, "no residual shake")


func test_shake_offset_is_whole_pixels_and_capped() -> void:
	_juice.shake(1.0, 0.5)
	var maximum := 0.0
	for frame in range(20):
		_juice.call("_process", 1.0 / 60.0)
		var offset: Vector2 = _juice.get_shake_offset()
		assert_almost_eq(offset.x, roundf(offset.x), 0.0001, "x offset is a whole pixel")
		assert_almost_eq(offset.y, roundf(offset.y), 0.0001, "y offset is a whole pixel")
		maximum = maxf(maximum, offset.length())
	assert_lte(maximum, 6.0, "shake never exceeds the 6 px cap")


func test_hitstop_is_capped_and_never_stacks() -> void:
	watch_signals(_juice)
	_juice.hitstop(0.5)
	assert_lte(float(_juice.get("last_hitstop_duration")), 0.09, "hitstop is capped at 90 ms")
	assert_true(_juice.is_hitstopping())
	assert_almost_eq(Engine.time_scale, 0.05, 0.0001, "engine slows to the requested scale")
	assert_signal_emitted(_juice, "hit_stopped")
	_juice.hitstop(0.05)
	assert_eq(int(_juice.get("hitstop_count")), 1, "a second hitstop while active is ignored")
	_juice.release_motion()
	assert_false(_juice.is_hitstopping())
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001, "release restores real time")


func test_hitstop_restores_after_wall_clock_deadline() -> void:
	_juice.hitstop(0.02)
	assert_true(_juice.is_hitstopping())
	OS.delay_msec(40)
	_juice.call("_process", 0.0)
	assert_false(_juice.is_hitstopping(), "unscaled deadline releases the freeze")
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001)


func test_flash_is_one_frame() -> void:
	_juice.flash(Color("#19E3D1"))
	assert_true(_juice.is_flash_visible(), "flash is armed immediately")
	await wait_frames(2)
	assert_false(_juice.is_flash_visible(), "flash is retired before the second draw")


func test_reduce_motion_disables_every_motion_effect() -> void:
	_juice.set_reduce_motion(true)
	_juice.shake(1.0, 0.5)
	assert_almost_eq(float(_juice.get("trauma")), 0.0, 0.0001, "shake is skipped")
	_juice.hitstop(0.08)
	assert_false(_juice.is_hitstopping(), "hitstop is skipped")
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001)
	_juice.flash(Color.WHITE)
	assert_false(_juice.is_flash_visible(), "flash is skipped")
	_juice.punch_zoom(0.04, 0.1)
	assert_almost_eq(float(_juice.get_zoom_punch()), 0.0, 0.0001, "zoom punch is skipped")
	_juice.set_reduce_motion(false)
	_juice.shake(1.0, 0.5)
	assert_gt(float(_juice.get("trauma")), 0.0, "shaking works again once motion is allowed")


func test_reduce_motion_cancels_an_active_hitstop() -> void:
	_juice.hitstop(0.08)
	assert_true(_juice.is_hitstopping())
	_juice.set_reduce_motion(true)
	assert_false(_juice.is_hitstopping(), "turning reduce motion on releases the freeze")
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001)


func test_punch_zoom_clamps_and_decays() -> void:
	_juice.punch_zoom(1.0, 0.1)
	assert_lte(float(_juice.get_zoom_punch()), 0.05, "zoom punch is capped at 5 %")
	_simulate(0.05)
	var mid := float(_juice.get_zoom_punch())
	assert_gt(mid, 0.0)
	assert_lt(mid, 0.05)
	_simulate(0.1)
	assert_almost_eq(float(_juice.get_zoom_punch()), 0.0, 0.0001, "zoom punch returns to zero")


func test_rumble_records_request_even_without_a_pad() -> void:
	_juice.rumble(0.35, 0.0, 70)
	var recorded: Vector3 = _juice.get("last_rumble")
	assert_almost_eq(recorded.x, 0.35, 0.0001)
	assert_eq(int(recorded.z), 70)


func test_hitstop_signal_reports_the_clamped_duration() -> void:
	watch_signals(_juice)
	_juice.hitstop(0.2)
	assert_signal_emitted_with_parameters(_juice, "hit_stopped", [0.09])

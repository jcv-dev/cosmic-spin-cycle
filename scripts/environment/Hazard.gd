class_name Hazard
extends Node2D
## Visual telegraph for one hazard (docs/DECISIONS.md D045).
##
## This node never decides damage: the [HazardDirector] resolves the hit on the strike beat
## so grading and penalties live in one place. Two phases, both audible and readable:
## WARNING (telegraph, always at least two beats) and ACTIVE (one beat of danger).

## The first pass at 0.55 alpha was invisible on the dark floor (owner report). The
## telegraph now draws a dark underlay plus a bright 2.5 px line, in the top half of the
## palette, so the shape reads from across the room.
const WARNING_ALPHA := 0.92
const ACTIVE_ALPHA := 1.0
const LINE_W := 2.5
const UNDERLAY_W := 5.0
const UNDERLAY_ALPHA := 0.8
## Telegraph rings start this much wider than the danger radius and close on the beat.
const WARNING_START_SCALE := 1.4
## Impact ring grows to this scale while it fades.
const SHOCKWAVE_SCALE := 1.6
const FADE_S := 0.18
## Beat signals can land a frame or two after the wall-clock telegraph ends.
const RESOLVE_GRACE_S := 0.75
const DASHES := 12
const ARC_DASHES := 9

var kind := Config.HazardKind.METEOR
var angle := 0.0
var warning_s := 1.0
var active_s := 0.5

var _elapsed := 0.0
var _active := false
var _finished := false


## Colour per kind, always paired with a shape so colour is never the only signal (B2).
static func kind_color(kind_id: int) -> Color:
	match kind_id:
		Config.HazardKind.VOID_VENT:
			return Palette.FUNK_MAGENTA
		Config.HazardKind.METEOR:
			return Palette.HAZARD_ORANGE
		Config.HazardKind.LINT_ARC:
			return Palette.YEL_3
		_:
			return Palette.FUNK_CYAN


func setup(kind_id: int, world_center: Vector2, strike_angle: float, telegraph_s: float) -> void:
	kind = kind_id
	angle = strike_angle
	warning_s = maxf(telegraph_s, 0.05)
	active_s = Config.beat_seconds(Config.PHASE_BPM[0])
	position = world_center
	z_index = 1
	queue_redraw()


## One beat of danger. Called by the director exactly on the strike beat.
func strike(active_seconds: float) -> void:
	_active = true
	active_s = maxf(active_seconds, 0.05)
	_elapsed = 0.0
	queue_redraw()


func is_active() -> bool:
	return _active


func is_finished() -> bool:
	return _finished


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	if _active and _elapsed >= active_s:
		_finished = true
		queue_free()
		return
	if not _active and _elapsed >= warning_s + RESOLVE_GRACE_S:
		# The telegraph was never resolved (shift ended or level freed): drop it. The grace
		# keeps the visual alive while the audio beat that resolves it arrives.
		_finished = true
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var color := kind_color(kind)
	var alpha := WARNING_ALPHA
	if _active:
		alpha = ACTIVE_ALPHA
	elif _elapsed > warning_s:
		alpha = lerpf(WARNING_ALPHA, 0.0, (_elapsed - warning_s) / FADE_S)
	match kind:
		Config.HazardKind.VOID_VENT:
			_draw_vent(color, alpha)
		Config.HazardKind.METEOR:
			_draw_meteor(color, alpha)
		Config.HazardKind.LINT_ARC:
			_draw_arc(color, alpha)
		_:
			_draw_pocket(color, alpha)


## Void vent: dashed ring that contracts as the beat approaches.
func _draw_vent(color: Color, alpha: float) -> void:
	var radius := Config.HAZARD_VENT_RADIUS_PX
	# Contract only during the warning. On the strike the radius stays put and a shockwave
	# expands instead; the old code reset the progress to 0 and snapped back to 1.35x.
	var draw_radius := lerpf(radius * WARNING_START_SCALE, radius, _warning_progress())
	_dashed_circle(draw_radius, DASHES, color, alpha)
	draw_circle(Vector2.ZERO, radius * 0.35, Color(color, alpha * 0.35))
	if _active:
		_draw_shockwave(radius, color)


## Meteor: floor shadow plus a closing reticle.
func _draw_meteor(color: Color, alpha: float) -> void:
	var radius := Config.HAZARD_METEOR_RADIUS_PX
	draw_circle(Vector2.ZERO, radius, Color(Palette.SPACE_VOID, alpha * 0.45))
	var shrink := lerpf(WARNING_START_SCALE, 1.0, _warning_progress())
	_dashed_circle(radius * shrink, 8, color, alpha)
	var cross := radius * 0.55
	draw_line(
		Vector2(-cross, 0), Vector2(cross, 0), Color(Palette.SPACE_VOID, UNDERLAY_ALPHA), UNDERLAY_W
	)
	draw_line(
		Vector2(0, -cross), Vector2(0, cross), Color(Palette.SPACE_VOID, UNDERLAY_ALPHA), UNDERLAY_W
	)
	draw_line(Vector2(-cross, 0), Vector2(cross, 0), Color(color, alpha), LINE_W)
	draw_line(Vector2(0, -cross), Vector2(0, cross), Color(color, alpha), LINE_W)
	if _active:
		draw_circle(Vector2.ZERO, radius * 0.6, Color(color, alpha * 0.5))
		_draw_shockwave(radius, color)


## Lint arc: a beam with a pulsing core and sparks at both ends.
func _draw_arc(color: Color, alpha: float) -> void:
	var axis := Vector2.RIGHT.rotated(angle)
	var half := HazardPlanner.ARC_LENGTH_PX * 0.5
	var normal := axis.orthogonal() * Config.HAZARD_ARC_HALF_WIDTH_PX
	var edge := normal.normalized() * Config.HAZARD_ARC_HALF_WIDTH_PX
	for side: float in [-1.0, 1.0]:
		var a := axis * -half + edge * side
		var b := axis * half + edge * side
		draw_line(a, b, Color(Palette.SPACE_VOID, UNDERLAY_ALPHA), UNDERLAY_W)
		draw_line(a, b, Color(color, alpha * 0.8), LINE_W)
	var step := (half * 2.0) / float(ARC_DASHES)
	for i in range(ARC_DASHES):
		var from := axis * (-half + step * i)
		var to := from + axis * step * 0.55
		draw_line(from, to, Color(Palette.SPACE_VOID, UNDERLAY_ALPHA), UNDERLAY_W)
		draw_line(from, to, Color(color, alpha), LINE_W)
	if _active:
		draw_line(axis * -half, axis * half, Color(color, alpha * 0.45), 2.0)
	draw_circle(axis * -half, 2.0, Color(color, alpha))
	draw_circle(axis * half, 2.0, Color(color, alpha))


## Gravity pocket: two rings with rotating ticks, no fill (it is a feeling, not a hole).
func _draw_pocket(color: Color, alpha: float) -> void:
	var radius := Config.HAZARD_POCKET_RADIUS_PX
	draw_arc(
		Vector2.ZERO, radius, 0.0, TAU, 28, Color(Palette.SPACE_VOID, UNDERLAY_ALPHA), UNDERLAY_W
	)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, Color(color, alpha), LINE_W)
	draw_arc(Vector2.ZERO, radius * 0.72, 0.0, TAU, 24, Color(color, alpha * 0.75), LINE_W)
	var spin := _elapsed * 2.0
	for i in range(4):
		var dir := Vector2.RIGHT.rotated(spin + TAU * float(i) / 4.0)
		draw_line(dir * radius * 0.8, dir * radius * 1.05, Color(color, alpha), LINE_W)


## Impact ring: expands from the danger radius outward and fades. This is the "it landed"
## read, distinct from the warning contraction.
func _draw_shockwave(radius: float, color: Color) -> void:
	var t := _active_progress()
	var ring := lerpf(radius, radius * SHOCKWAVE_SCALE, t)
	var fade := 1.0 - t
	draw_arc(Vector2.ZERO, ring, 0.0, TAU, 28, Color(color, fade * 0.9), LINE_W)
	draw_arc(
		Vector2.ZERO, ring * 0.96, 0.0, TAU, 28, Color(Palette.SPACE_VOID, fade * 0.6), UNDERLAY_W
	)


func _dashed_circle(radius: float, count: int, color: Color, alpha: float) -> void:
	var step := TAU / float(count)
	for i in range(count):
		var from := step * float(i)
		var to := from + step * 0.55
		draw_arc(
			Vector2.ZERO, radius, from, to, 8, Color(Palette.SPACE_VOID, UNDERLAY_ALPHA), UNDERLAY_W
		)
		draw_arc(Vector2.ZERO, radius, from, to, 8, Color(color, alpha), LINE_W)


## 0 at the start of the telegraph, 1 the instant it strikes. Frozen at 1 while active so a
## finished warning never restarts its animation.
func _warning_progress() -> float:
	if _active or warning_s <= 0.0:
		return 1.0
	return clampf(_elapsed / warning_s, 0.0, 1.0)


func _active_progress() -> float:
	if not _active or active_s <= 0.0:
		return 0.0
	return clampf(_elapsed / active_s, 0.0, 1.0)

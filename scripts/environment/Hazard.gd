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


## Void vent: an accretion disc. The dashed ring contracts as the beat approaches, three
## arms spiral inward and matter dots fall toward the core, so the pull reads before it hits.
func _draw_vent(color: Color, alpha: float) -> void:
	var radius := Config.HAZARD_VENT_RADIUS_PX
	var draw_radius := lerpf(radius * WARNING_START_SCALE, radius, _warning_progress())
	draw_circle(Vector2.ZERO, radius, Color(Palette.SPACE_VOID, alpha * 0.45))
	var spin := _elapsed * 2.4
	for arm in range(3):
		var base := spin + TAU * float(arm) / 3.0
		for segment in range(4):
			var t0 := 0.15 + 0.2 * float(segment)
			var from_r := radius * (1.0 - t0 * 0.75)
			var to_r := radius * (1.0 - (t0 + 0.18) * 0.75)
			var from_a := base + t0 * 2.2
			var to_a := base + (t0 + 0.18) * 2.2
			draw_line(
				Vector2.RIGHT.rotated(from_a) * from_r,
				Vector2.RIGHT.rotated(to_a) * to_r,
				Color(color, alpha * (0.85 - 0.15 * float(segment))),
				LINE_W
			)
	for i in range(6):
		var t := fposmod(_elapsed * 0.7 + float(i) / 6.0, 1.0)
		var orbit := radius * (1.0 - t)
		var dot_angle := spin * 0.6 + TAU * float(i) / 6.0 - t * 3.0
		draw_circle(
			Vector2.RIGHT.rotated(dot_angle) * orbit, 2.0, Color(color, alpha * (1.0 - t) * 0.9)
		)
	_dashed_circle(draw_radius, DASHES, color, alpha)
	draw_arc(Vector2.ZERO, radius * 0.30, 0.0, TAU, 20, Color(color, alpha), LINE_W)
	draw_circle(Vector2.ZERO, radius * 0.22, Palette.SPACE_VOID)
	if _active:
		_draw_shockwave(radius, color)


## Meteor: the rock falls in from above while the reticle closes, then the floor bursts.
func _draw_meteor(color: Color, alpha: float) -> void:
	var radius := Config.HAZARD_METEOR_RADIUS_PX
	if _active:
		_draw_explosion(radius, color)
		return
	var shadow := lerpf(0.6, 1.0, _warning_progress())
	draw_circle(Vector2.ZERO, radius * shadow, Color(Palette.SPACE_VOID, alpha * 0.45))
	var shrink := lerpf(WARNING_START_SCALE, 1.0, _warning_progress())
	_dashed_circle(radius * shrink, 8, color, alpha)
	var cross := radius * 0.5
	draw_line(Vector2(-cross, 0), Vector2(cross, 0), Color(color, alpha * 0.9), LINE_W)
	draw_line(Vector2(0, -cross), Vector2(0, cross), Color(color, alpha * 0.9), LINE_W)
	var progress := _warning_progress()
	var fall := lerpf(-320.0, 0.0, progress)
	var rock_radius := radius * 0.75
	# Fiery trail: three tapered streaks behind the falling rock.
	for i in range(3):
		var t := float(i) / 3.0
		var trail_y := fall - rock_radius - 12.0 - 28.0 * t
		var width := 7.0 * (1.0 - t)
		draw_line(
			Vector2(-width, trail_y),
			Vector2(width, trail_y + 18.0),
			Color(Palette.YEL_3, alpha * (0.55 - 0.15 * t)),
			3.0 - t * 1.5
		)
	# The rock itself: two tones, dark outline, slow rotation.
	var spin := progress * 2.4
	var rock := _rock_points(rock_radius)
	var rotated := PackedVector2Array()
	for point in rock:
		rotated.append(point.rotated(spin))
	var offset := Vector2(0.0, fall)
	draw_colored_polygon(_offset_points(rotated, offset), Palette.METAL_1)
	var lit := PackedVector2Array()
	for point in rotated:
		lit.append(point * 0.55 + Vector2(-rock_radius * 0.18, -rock_radius * 0.22))
	draw_colored_polygon(_offset_points(lit, offset), Palette.METAL_2)
	draw_polyline(_closed(rotated, offset), Color(Palette.SPACE_VOID, alpha), LINE_W)
	draw_circle(
		offset + Vector2(rock_radius * 0.28, rock_radius * 0.12),
		maxf(rock_radius * 0.16, 2.0),
		Color(Palette.METAL_0, alpha)
	)


## Impact: scorch, blast streaks, shards, smoke, ring and flash, inside the active window.
func _draw_explosion(radius: float, color: Color) -> void:
	var t := _active_progress()
	var fade := 1.0 - t
	# Burnt floor under the impact.
	draw_circle(Vector2.ZERO, radius * 0.9, Color(Palette.SPACE_VOID, 0.5 * fade))
	# Smoke behind everything.
	for i in range(5):
		var angle := TAU * float(i) / 5.0 + 0.4
		var distance := radius * (0.45 + 1.0 * t)
		var puff := Vector2.RIGHT.rotated(angle) * distance + Vector2(0.0, -10.0 * t)
		draw_circle(puff, radius * (0.3 + 0.3 * t), Color(Palette.SPACE_HAZE, fade * 0.45))
	# Blast streaks: the punch that reads at a glance.
	for i in range(8):
		var angle := TAU * float(i) / 8.0 + 0.15
		var from := Vector2.RIGHT.rotated(angle) * radius * 0.35
		var to := Vector2.RIGHT.rotated(angle) * radius * (0.6 + 1.3 * t)
		draw_line(from, to, Color(Palette.HAZARD_ORANGE, fade * 0.95), 4.0 * fade + 1.0)
	# Shards: bright, outlined, flying outward.
	for i in range(8):
		var angle := TAU * float(i) / 8.0 + 0.2
		var point := Vector2.RIGHT.rotated(angle) * radius * (0.4 + 1.5 * t)
		var size := 14.0 * fade
		if size <= 1.0:
			continue
		var shard := PackedVector2Array(
			[
				point + Vector2(-size, -size * 0.6),
				point + Vector2(size, -size),
				point + Vector2(size * 0.35, size),
			]
		)
		draw_colored_polygon(shard, Palette.YEL_3)
		draw_polyline(
			PackedVector2Array([shard[0], shard[1], shard[2], shard[0]]),
			Color(Palette.SPACE_VOID, fade),
			1.5
		)
	draw_arc(Vector2.ZERO, radius * (0.8 + 1.5 * t), 0.0, TAU, 32, Color(color, fade), 3.0)
	if t < 0.6:
		var flash := 1.0 - t / 0.6
		draw_circle(Vector2.ZERO, radius * (0.55 + 1.0 * t), Color(Palette.YEL_4, flash))
		draw_arc(
			Vector2.ZERO,
			radius * (0.55 + 1.0 * t),
			0.0,
			TAU,
			28,
			Color(Palette.HAZARD_ORANGE, flash),
			5.0 * flash + 1.0
		)
		draw_circle(Vector2.ZERO, radius * 0.32, Color(Palette.METAL_4, flash))


## Lint arc: two rails plus a crackling current that jumps between them.
func _draw_arc(color: Color, alpha: float) -> void:
	var axis := Vector2.RIGHT.rotated(angle)
	var half := HazardPlanner.ARC_LENGTH_PX * 0.5
	var edge := axis.orthogonal().normalized() * Config.HAZARD_ARC_HALF_WIDTH_PX
	for side: float in [-1.0, 1.0]:
		var a := axis * -half + edge * side
		var b := axis * half + edge * side
		draw_line(a, b, Color(Palette.SPACE_VOID, UNDERLAY_ALPHA), UNDERLAY_W)
		draw_line(a, b, Color(color, alpha * 0.8), LINE_W)
	var bolts := 10
	var points := PackedVector2Array()
	for i in range(bolts + 1):
		var t := float(i) / float(bolts)
		var along := axis * lerpf(-half, half, t)
		var jitter := sin(_elapsed * 14.0 + float(i) * 2.3) * Config.HAZARD_ARC_HALF_WIDTH_PX * 0.7
		points.append(along + edge.normalized() * jitter)
	draw_polyline(points, Color(Palette.SPACE_VOID, UNDERLAY_ALPHA), UNDERLAY_W)
	draw_polyline(points, Color(color, alpha), LINE_W)
	draw_circle(axis * -half, 2.5, Color(color, alpha))
	draw_circle(axis * half, 2.5, Color(color, alpha))


## Gravity pocket: counter-rotating rings and drifting dust. Non-damaging, so no dark fill.
func _draw_pocket(color: Color, alpha: float) -> void:
	var radius := Config.HAZARD_POCKET_RADIUS_PX
	draw_circle(Vector2.ZERO, radius, Color(color, alpha * 0.12))
	draw_arc(
		Vector2.ZERO, radius, 0.0, TAU, 28, Color(Palette.SPACE_VOID, UNDERLAY_ALPHA), UNDERLAY_W
	)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, Color(color, alpha), LINE_W)
	draw_arc(Vector2.ZERO, radius * 0.72, 0.0, TAU, 24, Color(color, alpha * 0.75), LINE_W)
	for ring in range(2):
		var spin := _elapsed * (2.0 if ring == 0 else -2.6)
		var ring_radius := radius * (0.9 if ring == 0 else 0.62)
		for i in range(6):
			var a := spin + TAU * float(i) / 6.0
			var from := Vector2.RIGHT.rotated(a) * ring_radius
			draw_line(
				from, from + Vector2.RIGHT.rotated(a) * 8.0, Color(color, alpha * 0.8), LINE_W
			)


func _rock_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var r := radius * (0.78 + 0.22 * sin(float(i) * 2.7 + 1.3))
		points.append(Vector2.RIGHT.rotated(angle) * r)
	return points


func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	for point in points:
		moved.append(point + offset)
	return moved


func _closed(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var out := _offset_points(points, offset)
	if out.size() > 0:
		out.append(out[0])
	return out


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

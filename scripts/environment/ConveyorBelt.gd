class_name ConveyorBelt
extends Area2D
## A running belt surface that steers the items standing on it (GDD §5.3, §A6 #12).
##
## Model: every physics tick each non-held [RigidBody2D] overlap has its velocity moved
## toward `flow_direction * belt_speed * item.belt_speed_scale` by at most
## [constant Config.BELT_ACCEL] * delta. Velocity is never assigned outright, because that
## would cancel item-item and item-wall collisions (`docs/DECISIONS.md` D006).
##
## The belt owns no clock: `WorldSandbox`/`MainLevel` forward `BeatConductor` beats into
## [method on_beat], which delegates to the pure [BeltReversal] schedule.
##
## Visuals are procedural and palette-locked (`art/palette.json`): a metal deck with
## scrolling chevrons that point along the flow, orange while a reversal is warned.

## Emitted when the flow direction actually changes.
signal reversed(new_direction: Vector2)
## Emitted `beats_left` beats before a phase-3 reversal.
signal reverse_warning(beats_left: int)

## Chevron pitch, in world pixels.
@export var chevron_spacing := 4.0 * float(Config.ART_SCALE)
## Half-length of one chevron, in world pixels.
@export var chevron_half := float(Config.ART_SCALE)
## Rail thickness in world pixels.
@export var rail_width := 2.0

@export var belt_id: StringName = &""
@export var flow_direction := Vector2.RIGHT
@export var belt_speed := Config.BELT_SPEED
@export var active := true
## Belt footprint in world pixels (the scene default matches `belt_north`).
@export var belt_size := Vector2(608.0, 64.0)

## Reversal schedule shared by every belt of the run; each belt keeps its own direction.
var reversal := BeltReversal.new()

var _scroll := 0.0
var _warning_beats_left := 0
var _shape_node: CollisionShape2D


func _ready() -> void:
	collision_layer = Config.CollisionLayer.BELT
	collision_mask = Config.CollisionLayer.ITEMS
	monitorable = false
	add_to_group(Config.GROUP_BELTS)
	_ensure_shape()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not active:
		return
	for body in get_overlapping_bodies():
		apply_to_body(body, delta)


func _process(delta: float) -> void:
	if not active:
		return
	_scroll = fposmod(_scroll + belt_speed * delta, chevron_spacing)
	queue_redraw()


# --- public API (CONTRACTS §4) ----------------------------------------------


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if not active:
		_scroll = 0.0
		_warning_beats_left = 0
	queue_redraw()


func is_active() -> bool:
	return active


## Sets the flow. Only axis-aligned unit vectors are meaningful; anything else is
## normalised and snapped to the dominant axis so the visual stays on the pixel grid.
func set_flow_direction(dir: Vector2) -> void:
	if dir.is_zero_approx():
		return
	var snapped := _snap_axis(dir)
	if snapped.is_equal_approx(flow_direction):
		return
	flow_direction = snapped
	queue_redraw()


func get_flow_direction() -> Vector2:
	return flow_direction


## Footprint in world pixels.
func world_size() -> Vector2:
	return belt_size


## Positions and sizes the belt from an `art_px` rect of `data/layout.json`.
func configure(p_belt_id: StringName, art_rect: Rect2, flow: Vector2) -> void:
	belt_id = p_belt_id
	belt_size = art_rect.size * float(Config.ART_SCALE)
	position = (art_rect.position + art_rect.size * 0.5) * float(Config.ART_SCALE)
	flow_direction = _snap_axis(flow)
	_ensure_shape()
	queue_redraw()


## Velocity a body on this belt should converge to.
func target_velocity_for(body: Node) -> Vector2:
	return flow_direction * belt_speed * speed_scale_for(body)


## Speed multiplier of one item: `ItemData.belt_speed_scale` when present, layout metadata
## for greybox stubs, and the sock rule from GDD §6 as a fallback.
func speed_scale_for(body: Node) -> float:
	if body == null:
		return 1.0
	var data: Variant = body.get(&"data")
	if data != null and data.get(&"belt_speed_scale") != null:
		return float(data.get(&"belt_speed_scale"))
	if body.has_meta(&"belt_speed_scale"):
		return float(body.get_meta(&"belt_speed_scale"))
	if StringName(str(body.get(&"item_id"))) == &"sock":
		return Config.BELT_SOCK_SPEED_SCALE
	return 1.0


## Steers one body for `delta` seconds. Returns false when the body is ignored (not a
## rigid body, held by the player, or the belt is off).
func apply_to_body(body: Node, delta: float) -> bool:
	if not active or body == null or not (body is RigidBody2D):
		return false
	if body.get(&"is_held") == true:
		return false
	var rigid := body as RigidBody2D
	var target := target_velocity_for(body)
	rigid.linear_velocity = steer_velocity(rigid.linear_velocity, target, Config.BELT_ACCEL * delta)
	return true


## One steering step, exposed so the rule is testable without a physics world.
static func steer_velocity(current: Vector2, target: Vector2, max_delta: float) -> Vector2:
	var diff := target - current
	if diff.length() <= max_delta:
		return target
	if max_delta <= 0.0:
		return current
	return current + diff.normalized() * max_delta


## Forwards one beat to the reversal schedule. Returns the verdict, and emits
## [signal reverse_warning] / [signal reversed] when it says so.
func on_beat(beat: int, measure: int, phase: int) -> Dictionary:
	var verdict := reversal.on_beat(beat, measure, phase)
	if verdict.warn:
		_warning_beats_left = int(verdict.beats_left)
		reverse_warning.emit(_warning_beats_left)
		queue_redraw()
	if verdict.flip:
		_warning_beats_left = 0
		set_flow_direction(-flow_direction)
		reversed.emit(flow_direction)
	return verdict


## Number of warning beats still queued (0 when no reversal is announced).
func warning_beats_left() -> int:
	return _warning_beats_left


## True while a reversal is being announced.
func is_warning_active() -> bool:
	return _warning_beats_left > 0


# --- internals --------------------------------------------------------------


func _snap_axis(dir: Vector2) -> Vector2:
	if absf(dir.x) >= absf(dir.y):
		return Vector2.RIGHT if dir.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if dir.y >= 0.0 else Vector2.UP


func _ensure_shape() -> void:
	_shape_node = get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		_shape_node.name = "CollisionShape2D"
		add_child(_shape_node)
	var rect := RectangleShape2D.new()
	rect.size = belt_size
	_shape_node.shape = rect


func _draw() -> void:
	var half := belt_size * 0.5
	var deck := Rect2(-half, belt_size)
	var base := EnvironmentPalette.color("space_mid")
	var surface := EnvironmentPalette.color("metal_1")
	var rail := EnvironmentPalette.color("metal_3")
	var muted := EnvironmentPalette.color("space_haze")
	var live := EnvironmentPalette.color("funk_cyan")
	var warning := EnvironmentPalette.color("hazard_orange")

	draw_rect(deck, base, true)
	var inner := deck.grow(-rail_width)
	draw_rect(inner, surface, true)
	var axis := _snap_axis(flow_direction)
	var rails := _rail_rects(inner, axis)
	for rect: Rect2 in rails:
		draw_rect(rect, rail, true)

	var chevron_color := live if active else muted
	if is_warning_active():
		chevron_color = warning
	_draw_chevrons(axis, chevron_color, inner)


func _rail_rects(inner: Rect2, axis: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if absf(axis.x) > 0.0:
		out.append(Rect2(inner.position, Vector2(inner.size.x, rail_width)))
		out.append(
			Rect2(
				Vector2(inner.position.x, inner.end.y - rail_width),
				Vector2(inner.size.x, rail_width)
			)
		)
	else:
		out.append(Rect2(inner.position, Vector2(rail_width, inner.size.y)))
		out.append(
			Rect2(
				Vector2(inner.end.x - rail_width, inner.position.y),
				Vector2(rail_width, inner.size.y)
			)
		)
	return out


func _draw_chevrons(axis: Vector2, color: Color, inner: Rect2) -> void:
	if chevron_spacing <= 0.0:
		return
	var extent := absf(inner.size.x * axis.x) + absf(inner.size.y * axis.y)
	if extent <= chevron_spacing:
		return
	var perp := axis.orthogonal()
	var count := int(extent / chevron_spacing)
	for index in range(count):
		var along := -extent * 0.5 + fposmod(float(index) * chevron_spacing + _scroll, extent)
		var center := axis * along
		var tip := center + axis * chevron_half
		var back := center - axis * chevron_half
		var points := PackedVector2Array(
			[tip, back + perp * chevron_half, back - perp * chevron_half]
		)
		draw_colored_polygon(points, color)

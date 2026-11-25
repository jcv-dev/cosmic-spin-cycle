class_name Shredder
extends Area2D
## Belt-end grinder (GDD §5.3). An item that falls off a belt lands here.
##
## Contract: emit `fell_off_belt` on the item, apply
## [constant Config.STABILITY_FELL_OFF_BELT] to `GameState` with reason `"shredder"`, bump
## the drop counter and free the item. Entry is guarded, because a body that is already
## queued for deletion can report a second overlap on the same frame.
##
## The node also owns its own `consumed_count` so a sandbox can show the loss rate without
## reading autoload state.

## Emitted once per body that feeds the grinder.
signal item_consumed(body: Node)

## Footprint in world pixels (32 art px square in `data/layout.json`).
@export var shredder_size := Vector2(32.0, 32.0) * float(Config.ART_SCALE)
@export var shredder_id: StringName = &""
## Radians per second for the vortex animation.
@export var spin_speed := 2.0

var consumed_count := 0

var _consumed: Dictionary = {}
var _spin := 0.0
var _shape_node: CollisionShape2D


func _ready() -> void:
	collision_layer = Config.CollisionLayer.SHREDDER
	collision_mask = Config.CollisionLayer.ITEMS
	monitorable = false
	add_to_group(Config.GROUP_SHREDDERS)
	_ensure_shape()
	body_entered.connect(_on_body_entered)
	queue_redraw()


func _process(delta: float) -> void:
	_spin = fposmod(_spin + spin_speed * delta, TAU)
	queue_redraw()


# --- public API -------------------------------------------------------------


## Places the grinder from an `art_px` rect of `data/layout.json`.
func configure(p_shredder_id: StringName, art_rect: Rect2) -> void:
	shredder_id = p_shredder_id
	shredder_size = art_rect.size * float(Config.ART_SCALE)
	position = (art_rect.position + art_rect.size * 0.5) * float(Config.ART_SCALE)
	_ensure_shape()
	queue_redraw()


## Radius of the vortex visual, in world pixels.
func radius() -> float:
	return minf(shredder_size.x, shredder_size.y) * 0.5


## Feeds one body to the grinder.
##
## Returns false when the body is not an item or was already consumed. Returns true after
## the stability hit, the counter bump and `queue_free()`.
func consume(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if body.is_queued_for_deletion():
		return false
	if not is_item_body(body):
		return false
	var body_id := body.get_instance_id()
	if _consumed.has(body_id):
		return false
	_consumed[body_id] = true

	if body.has_signal(&"fell_off_belt"):
		body.emit_signal(&"fell_off_belt")
	GameState.add_stability(Config.STABILITY_FELL_OFF_BELT, "shredder")
	GameState.dropped_count += 1
	consumed_count += 1
	item_consumed.emit(body)
	body.queue_free()
	return true


## True for anything the grinder should accept: a rigid body that declares itself an item.
func is_item_body(body: Node) -> bool:
	if not (body is RigidBody2D):
		return false
	if body.has_signal(&"fell_off_belt"):
		return true
	if body.is_in_group(Config.GROUP_ITEMS):
		return true
	if body.get(&"item_id") != null:
		return true
	var layer := int(body.get(&"collision_layer"))
	return (layer & Config.CollisionLayer.ITEMS) != 0


# --- internals --------------------------------------------------------------


func _on_body_entered(body: Node) -> void:
	consume(body)


func _ensure_shape() -> void:
	_shape_node = get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		_shape_node.name = "CollisionShape2D"
		add_child(_shape_node)
	var circle := CircleShape2D.new()
	circle.radius = radius()
	_shape_node.shape = circle


func _draw() -> void:
	var r := radius()
	var deep := EnvironmentPalette.color("space_deep")
	var void_color := EnvironmentPalette.color("space_void")
	var hazard := EnvironmentPalette.color("hazard_orange")
	var metal := EnvironmentPalette.color("metal_1")

	draw_circle(Vector2.ZERO, r, void_color)
	draw_circle(Vector2.ZERO, r * 0.86, deep)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, hazard, 2.0, true)
	for index in range(3):
		var phase := _spin + TAU * float(index) / 3.0
		var start := phase
		var end := phase + TAU * 0.42
		var arc_radius := r * (0.30 + 0.22 * float(index))
		draw_arc(Vector2.ZERO, arc_radius, start, end, 16, metal, 3.0, true)
	draw_circle(Vector2.ZERO, r * 0.12, hazard)

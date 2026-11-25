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

	# A recessed floor well, not a black hole: the mouth must read as machinery in the
	# floor, never as a portal or a target.
	draw_circle(Vector2.ZERO, r, Color(deep.r, deep.g, deep.b, 0.55))
	draw_circle(Vector2.ZERO, r * 0.60, Color(void_color.r, void_color.g, void_color.b, 0.72))
	_draw_throat_chevrons(r, hazard)
	# One 2 px marking ring at 55 % — a hazard label, not a glow.
	draw_arc(
		Vector2.ZERO, r - 1.0, 0.0, TAU, 48, Color(hazard.r, hazard.g, hazard.b, 0.55), 2.0, false
	)
	# A single tick shows the grinder is running without drawing three spinning rings.
	var tick := Vector2(cos(_spin), sin(_spin))
	draw_line(tick * r * 0.20, tick * r * 0.42, Color(metal.r, metal.g, metal.b, 0.55), 2.0, false)
	_draw_loss_marker(r, hazard, void_color)


## Hazard chevrons across the throat, pointing into the machine.
func _draw_throat_chevrons(r: float, hazard: Color) -> void:
	var ink := Color(hazard.r, hazard.g, hazard.b, 0.34)
	var half := r * 0.16
	for index in range(3):
		var y := -r * 0.26 + float(index) * r * 0.26
		var points := PackedVector2Array(
			[
				Vector2(-half, y),
				Vector2(0.0, y + half * 0.8),
				Vector2(half, y),
				Vector2(half, y + 3.0),
				Vector2(0.0, y + half * 0.8 + 3.0),
				Vector2(-half, y + 3.0),
			]
		)
		draw_colored_polygon(points, ink)


## The honest tell: a small "−8" chip instead of a glowing hub. It sits away from the room
## centre (above on the north wall, below elsewhere) and is dim until the first loss, so it
## never collides with a washer hologram or reads as a permanent objective.
func _draw_loss_marker(r: float, hazard: Color, void_color: Color) -> void:
	var above := global_position.y < 160.0
	var y := -r - 24.0 if above else r + 2.0
	var chip := Rect2(-18.0, y, 36.0, 22.0)
	var idle_alpha := 0.34 if consumed_count == 0 else 0.85
	draw_rect(chip, Color(void_color.r, void_color.g, void_color.b, idle_alpha))
	draw_rect(
		chip, Color(hazard.r, hazard.g, hazard.b, 0.35 if consumed_count == 0 else 0.5), false, 2.0
	)
	var ink := Color(hazard.r, hazard.g, hazard.b, 0.55 if consumed_count == 0 else 0.9)
	var rows := [["000", "000", "111", "000", "000"], ["111", "101", "111", "101", "111"]]
	var pixel := 4.0
	var origin := chip.position + Vector2(4.0, 2.0)
	for glyph in range(rows.size()):
		var bits: Array = rows[glyph]
		for row in range(bits.size()):
			var line: String = bits[row]
			for column in range(line.length()):
				if line[column] != "1":
					continue
				var at := Vector2(float(glyph) * 12.0 + float(column) * pixel, float(row) * pixel)
				draw_rect(Rect2(origin + at, Vector2(pixel, pixel)), ink)

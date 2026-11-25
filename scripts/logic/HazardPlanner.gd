class_name HazardPlanner
extends RefCounted
## Pure hazard selection and placement (docs/DECISIONS.md D045, D053).
##
## The [HazardDirector] calls [method plan] once per measure and replays the answer against
## the beat clock. Nothing here reads a node, the clock or an autoload, so the escalation
## curve is unit-testable and reproducible per seed.
##
## Fairness and sense rules live here, not in the node:
## * one hazard per measure maximum (the caller never asks twice);
## * kinds unlock by phase, so phase 1 cannot throw a meteor;
## * a hazard lands on a sampled point that is inside the playable band, clear of the belts,
##   the washer cabinets, the shredders and the chute, at least `HAZARD_MIN_SEPARATION_PX`
##   from the previous one and `HAZARD_PLAYER_CLEARANCE_PX` from the player.

## Beam length for [constant Config.HazardKind.LINT_ARC], in world pixels.
const ARC_LENGTH_PX := 220.0
const LAYOUT_PATH := "res://data/layout.json"

## Parsed `data/layout.json`, cached for the session. Static vars are supported in 4.x.
static var _layout_cache: Dictionary = {}


## Kinds available per phase index. Phase 0 is the onboarding beat: only the void vent.
## A function, not a const, so the enum values are resolved at runtime (GDScript cannot
## constant-fold `Config.HazardKind.*` in a const initialiser).
static func kinds_for_phase(phase: int) -> Array[int]:
	match clampi(phase, 0, 3):
		0:
			return [Config.HazardKind.VOID_VENT]
		1:
			return [Config.HazardKind.VOID_VENT, Config.HazardKind.METEOR]
		2:
			return [
				Config.HazardKind.VOID_VENT,
				Config.HazardKind.METEOR,
				Config.HazardKind.LINT_ARC,
			]
		_:
			return [
				Config.HazardKind.VOID_VENT,
				Config.HazardKind.METEOR,
				Config.HazardKind.LINT_ARC,
				Config.HazardKind.GRAVITY_POCKET,
			]


## Empty dictionary means "this measure spawns nothing".
##
## `previous` and `avoid` are world points; `Vector2.ZERO` means "none" (the room centre is
## never a candidate because the chute is not walkable). `rng` is the caller's seeded
## generator, advanced only when a hazard is actually placed.
static func plan(
	phase: int,
	difficulty: int,
	rng: RandomNumberGenerator,
	previous: Vector2,
	avoid: Vector2 = Vector2.ZERO
) -> Dictionary:
	var chance := Config.DIFFICULTY_HAZARD_PER_MEASURE[Config.difficulty_index(difficulty)]
	if rng.randf() >= chance:
		return {}
	var kinds := kinds_for_phase(phase)
	var kind: int = int(kinds[rng.randi_range(0, kinds.size() - 1)])
	var position := _pick_point(rng, previous, avoid)
	if position == Vector2.ZERO:
		return {}
	var angle := 0.0
	if kind == Config.HazardKind.LINT_ARC:
		angle = 0.0 if rng.randi_range(0, 1) == 0 else PI * 0.5
	return {"kind": kind, "pos": position, "angle": angle, "phase": phase}


## Radius used by the damage test, in world pixels. The arc uses its half-width because the
## test is point-to-segment, not point-to-centre.
static func radius_px(kind: int) -> float:
	match kind:
		Config.HazardKind.VOID_VENT:
			return Config.HAZARD_VENT_RADIUS_PX
		Config.HazardKind.METEOR:
			return Config.HAZARD_METEOR_RADIUS_PX
		Config.HazardKind.LINT_ARC:
			return Config.HAZARD_ARC_HALF_WIDTH_PX
		Config.HazardKind.GRAVITY_POCKET:
			return Config.HAZARD_POCKET_RADIUS_PX
		_:
			return 0.0


## True when the world point is inside `kind`'s danger shape at `center` with `angle`.
static func contains(
	kind: int, center: Vector2, angle: float, point: Vector2, radius_scale: float = 1.0
) -> bool:
	if kind == Config.HazardKind.LINT_ARC:
		var half := ARC_LENGTH_PX * 0.5 * radius_scale
		var axis := Vector2.RIGHT.rotated(angle)
		var relative := point - center
		var along := clampf(relative.dot(axis), -half, half)
		var nearest := center + axis * along
		return point.distance_to(nearest) <= radius_px(kind) * radius_scale
	return point.distance_to(center) <= radius_px(kind) * radius_scale


## Playable area in world pixels: the room minus the wall band.
static func playable_rect() -> Rect2:
	var layout := _layout()
	var scale := float(layout.get("art_scale", Config.ART_SCALE))
	var room: Dictionary = layout.get("room", {})
	var rect := Rect2(
		Vector2(float(room.get("x", 0)), float(room.get("y", 0))) * scale,
		Vector2(float(room.get("w", 320)), float(room.get("h", 180))) * scale
	)
	return rect.grow(-Config.HAZARD_ROOM_MARGIN_PX)


## True when a hazard centre is allowed there: inside the room, off the furniture and clear
## of the delivery chute.
static func is_valid_point(point: Vector2) -> bool:
	if not playable_rect().has_point(point):
		return false
	for rect: Rect2 in blocked_rects():
		if rect.has_point(point):
			return false
	var chute := chute_center()
	if chute != Vector2.ZERO and point.distance_to(chute) < Config.HAZARD_CHUTE_CLEARANCE_PX:
		return false
	return true


## Belts, washer cabinets and shredders, in world pixels and grown by a safety pad.
static func blocked_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var layout := _layout()
	var scale := float(layout.get("art_scale", Config.ART_SCALE))
	_append_rects(rects, layout.get("belts", []), scale, Config.HAZARD_BELT_PAD_PX)
	_append_rects(rects, layout.get("washers", []), scale, Config.HAZARD_BLOCK_PAD_PX)
	_append_rects(rects, layout.get("shredders", []), scale, Config.HAZARD_BLOCK_PAD_PX)
	return rects


static func chute_center() -> Vector2:
	var layout := _layout()
	var scale := float(layout.get("art_scale", Config.ART_SCALE))
	var chute: Dictionary = layout.get("chute", {})
	var centre: Array = chute.get("center", [])
	if centre.size() != 2:
		return Vector2.ZERO
	return Vector2(float(centre[0]), float(centre[1])) * scale


static func _layout() -> Dictionary:
	if not _layout_cache.is_empty():
		return _layout_cache
	if not FileAccess.file_exists(LAYOUT_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if parsed is Dictionary:
		_layout_cache = parsed
	return _layout_cache


static func _append_rects(into: Array[Rect2], entries: Array, scale: float, pad: float) -> void:
	for entry: Dictionary in entries:
		var rect := Rect2(
			Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))) * scale,
			Vector2(float(entry.get("w", 0)), float(entry.get("h", 0))) * scale
		)
		into.append(rect.grow(pad))


## Samples the grid and picks one legal point. Returns `Vector2.ZERO` when the room is too
## crowded (cannot happen with the shipped layout, but the director handles it).
static func _pick_point(rng: RandomNumberGenerator, previous: Vector2, avoid: Vector2) -> Vector2:
	var candidates: Array[Vector2] = []
	var area := playable_rect()
	var step := Config.HAZARD_GRID_PX
	var y := area.position.y
	while y <= area.end.y:
		var x := area.position.x
		while x <= area.end.x:
			var point := Vector2(x, y)
			if _accepts(point, previous, avoid):
				candidates.append(point)
			x += step
		y += step
	if candidates.is_empty():
		return Vector2.ZERO
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _accepts(point: Vector2, previous: Vector2, avoid: Vector2) -> bool:
	if not is_valid_point(point):
		return false
	if previous != Vector2.ZERO and point.distance_to(previous) < Config.HAZARD_MIN_SEPARATION_PX:
		return false
	if avoid != Vector2.ZERO and point.distance_to(avoid) < Config.HAZARD_PLAYER_CLEARANCE_PX:
		return false
	return true

class_name HazardPlanner
extends RefCounted
## Pure hazard selection (docs/DECISIONS.md D045).
##
## The [HazardDirector] calls [method plan] once per measure and replays the answer against
## the beat clock. Nothing here reads a node, the clock or an autoload, so the escalation
## curve is unit-testable and reproducible per seed.
##
## Fairness rules enforced here, not in the node:
## * one hazard per measure maximum (the caller never asks twice);
## * hazard kinds unlock by phase, so phase 1 cannot throw a meteor;
## * two consecutive hazards are at least [constant Config.HAZARD_MIN_SEPARATION_PX] apart;
## * anchors stay inside the playable band, clear of the chute and the washer mouths.

## Candidate centres in art pixels (×ART_SCALE for world space). Chosen by hand from
## `data/layout.json`: the band between the belts, clear of the four washer mouths and of
## the central chute.
const ANCHORS_ART: Array[Vector2] = [
	Vector2(110, 52),
	Vector2(160, 48),
	Vector2(210, 52),
	Vector2(98, 86),
	Vector2(222, 86),
	Vector2(128, 68),
	Vector2(192, 68),
	Vector2(110, 126),
	Vector2(210, 126),
	Vector2(160, 128),
]

## Beam length for [constant Config.HazardKind.LINT_ARC], in world pixels.
const ARC_LENGTH_PX := 220.0


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
## `previous_art` is the last hazard's anchor in art pixels (or `Vector2.ZERO` for none);
## `rng` is the caller's seeded generator, advanced only when a hazard is actually placed.
static func plan(
	phase: int, difficulty: int, rng: RandomNumberGenerator, previous_art: Vector2
) -> Dictionary:
	var chance := Config.DIFFICULTY_HAZARD_PER_MEASURE[Config.difficulty_index(difficulty)]
	if rng.randf() >= chance:
		return {}
	var kinds := kinds_for_phase(phase)
	var kind: int = int(kinds[rng.randi_range(0, kinds.size() - 1)])
	var anchor := _pick_anchor(rng, previous_art)
	if anchor == Vector2.ZERO:
		return {}
	var angle := 0.0
	if kind == Config.HazardKind.LINT_ARC:
		angle = 0.0 if rng.randi_range(0, 1) == 0 else PI * 0.5
	return {"kind": kind, "art_pos": anchor, "angle": angle, "phase": phase}


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


## World-space centre of a plan entry.
static func world_position(plan_entry: Dictionary) -> Vector2:
	var art: Vector2 = plan_entry.get("art_pos", Vector2.ZERO)
	return art * float(Config.ART_SCALE)


static func _pick_anchor(rng: RandomNumberGenerator, previous_art: Vector2) -> Vector2:
	var candidates: Array[Vector2] = []
	for anchor: Vector2 in ANCHORS_ART:
		if previous_art == Vector2.ZERO:
			candidates.append(anchor)
			continue
		var separation := anchor.distance_to(previous_art) * float(Config.ART_SCALE)
		if separation >= Config.HAZARD_MIN_SEPARATION_PX:
			candidates.append(anchor)
	if candidates.is_empty():
		return Vector2.ZERO
	return candidates[rng.randi_range(0, candidates.size() - 1)]

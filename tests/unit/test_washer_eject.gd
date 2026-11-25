extends GutTest
## Washers eject their clean item toward the room centre (D050 regression).
##
## The report was "the bottom machines drop the item onto the south belt". The cause was a
## fixed `(0, 76)` offset: the south mouths sit 40 px above the belt lane, so every release
## landed inside it. This test reads `data/layout.json` and proves the rule against the real
## layout, so a future layout tweak that breaks it fails here.

const LAYOUT_PATH := "res://data/layout.json"


func _layout() -> Dictionary:
	var text := FileAccess.get_file_as_string(LAYOUT_PATH)
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary


func _mouths_world() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var layout := _layout()
	var scale := float(layout.get("art_scale", Config.ART_SCALE))
	for washer: Dictionary in layout.get("washers", []):
		var mouth: Array = washer.get("mouth", [])
		if mouth.size() == 2:
			points.append(Vector2(float(mouth[0]), float(mouth[1])) * scale)
	return points


func _belt_rects_world() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var layout := _layout()
	var scale := float(layout.get("art_scale", Config.ART_SCALE))
	for belt: Dictionary in layout.get("belts", []):
		rects.append(
			Rect2(
				Vector2(float(belt["x"]), float(belt["y"])) * scale,
				Vector2(float(belt["w"]), float(belt["h"])) * scale
			)
		)
	return rects


func test_every_washer_ejects_away_from_the_centre_side() -> void:
	for mouth: Vector2 in _mouths_world():
		var direction := CosmicWasher.eject_direction(mouth)
		var toward_centre := (Vector2(640, 360) - mouth).normalized()
		assert_gt(direction.dot(toward_centre), 0.9, "eject %s points at the room centre" % mouth)


func test_no_eject_point_lands_on_a_belt() -> void:
	var belts := _belt_rects_world()
	for mouth: Vector2 in _mouths_world():
		var point := CosmicWasher.eject_point(mouth)
		for belt: Rect2 in belts:
			assert_false(
				belt.grow(4.0).has_point(point), "eject from %s lands on belt %s" % [mouth, belt]
			)


func test_eject_point_stays_inside_the_room() -> void:
	var canvas := Vector2(Config.ART_CANVAS) * float(Config.ART_SCALE)
	for mouth: Vector2 in _mouths_world():
		var point := CosmicWasher.eject_point(mouth)
		assert_between(point.x, 24.0, canvas.x - 24.0, "eject x stays on screen")
		assert_between(point.y, 24.0, canvas.y - 24.0, "eject y stays on screen")

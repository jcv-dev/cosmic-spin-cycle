extends GutTest
## data/layout.json is the frozen art-pixel contract (see docs/CONTRACTS.md §5).


func _load_layout() -> Dictionary:
	var f := FileAccess.open("res://data/layout.json", FileAccess.READ)
	assert_not_null(f, "layout.json must exist")
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary, "layout.json must be an object")
	return parsed as Dictionary


func _rect_inside(rect: Dictionary, w: int, h: int) -> bool:
	return (
		int(rect.x) >= 0
		and int(rect.y) >= 0
		and int(rect.x) + int(rect.w) <= w
		and int(rect.y) + int(rect.h) <= h
	)


func test_layout_identity() -> void:
	var layout := _load_layout()
	assert_eq(layout.get("coord_space"), "art_px")
	assert_eq(int(layout.get("art_scale")), Config.ART_SCALE)
	assert_eq(int(layout.canvas.w), Config.ART_CANVAS.x)
	assert_eq(int(layout.canvas.h), Config.ART_CANVAS.y)


func test_belts_are_inside_canvas_and_have_valid_flow() -> void:
	var layout := _load_layout()
	var belts: Array = layout.belts
	assert_eq(belts.size(), 3, "north, south and west belts")
	for belt in belts:
		assert_true(_rect_inside(belt, Config.ART_CANVAS.x, Config.ART_CANVAS.y), belt.id)
		var flow: Array = belt.flow
		assert_eq(flow.size(), 2, belt.id)
		assert_true(abs(int(flow[0]) + abs(int(flow[1]))) == 1, "axis-aligned flow")
		assert_true(belt.active_phases.size() > 0, belt.id)


func _as_ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value in values:
		out.append(int(value))
	return out


func test_phase_activation_matches_gdd() -> void:
	var layout := _load_layout()
	var by_id := {}
	for belt in layout.belts:
		by_id[belt.id] = belt
	assert_eq(_as_ints(by_id.belt_north.active_phases), [0, 1, 2, 3])
	assert_eq(_as_ints(by_id.belt_south.active_phases), [1, 2, 3])
	assert_eq(_as_ints(by_id.belt_west.active_phases), [2, 3])
	assert_true(by_id.belt_west.reversed_in_phase3)


func test_washers_shredders_and_chute() -> void:
	var layout := _load_layout()
	assert_eq(layout.washers.size(), Config.WASHER_COUNT)
	for washer in layout.washers:
		assert_true(_rect_inside(washer, 320, 180), washer.id)
		var mouth: Array = washer.mouth
		var cx := int(washer.x) + int(washer.w) / 2
		assert_eq(int(mouth[0]), cx, "mouth is centred")
		assert_eq(int(mouth[1]), int(washer.y) + int(washer.h), "mouth at the bottom edge")
	assert_eq(layout.shredders.size(), 3)
	for shredder in layout.shredders:
		assert_true(_rect_inside(shredder, 320, 180), shredder.id)
	assert_true(_rect_inside(layout.chute, 320, 180))
	assert_eq(int(layout.player_spawn[0]), 160)
	assert_eq(int(layout.player_spawn[1]), 128)


func test_world_conversion_is_integer() -> void:
	var layout := _load_layout()
	for belt in layout.belts:
		for key in ["x", "y", "w", "h"]:
			var world := int(belt[key]) * Config.ART_SCALE
			assert_eq(world % Config.ART_SCALE, 0)

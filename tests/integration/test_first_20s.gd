extends GutTest
## The 20-second test (docs/UX_BIBLE.md §2): a stranger must meet the goal, the
## destination and the beat before the first item can reach a shredder.


func after_each() -> void:
	BeatConductor.stop()
	BeatConductor.set_stream(null, 0.0)


func _spawn_level() -> Node2D:
	var packed := load("res://scenes/main/MainLevel.tscn") as PackedScene
	var level := packed.instantiate() as Node2D
	add_child_autofree(level)
	return level


func test_starter_item_spawns_near_the_player() -> void:
	var level := _spawn_level()
	level.set_shift_time(1.3)
	var items := level.get_node("Items")
	assert_eq(items.get_child_count(), 1, "exactly one starter item")
	var player := level.call("get_player") as Node2D
	var item := items.get_child(0) as Node2D
	assert_true(
		item.global_position.distance_to(player.global_position) <= 130.0,
		"the first useful action is a grab, not a walk"
	)
	assert_eq(StringName(item.get("item_id")), Config.STARTER_ITEM_ID)
	assert_false(bool(item.get("is_clean")), "the starter item is dirty")


func test_no_item_is_at_a_shredder_early() -> void:
	var level := _spawn_level()
	level.set_shift_time(1.3)
	var shredders := get_tree().get_nodes_in_group(Config.GROUP_SHREDDERS)
	assert_gt(shredders.size(), 0, "the level has its shredders")
	for node in get_tree().get_nodes_in_group(Config.GROUP_ITEMS):
		var item := node as Node2D
		for shredder_node in shredders:
			var shredder := shredder_node as Node2D
			assert_gt(
				item.global_position.distance_to(shredder.global_position),
				120.0,
				"no item within a shredder mouth at 1.3 s"
			)


func test_objective_is_stated_and_hint_strip_is_gone() -> void:
	var level := _spawn_level()
	var hud := level.get_node_or_null("UI/HUD") as Control
	if hud == null:
		pending("HUD missing")
		return
	if not hud.has_method("objective_text"):
		pending("HUD objective API lands with the HUD workstream")
		return
	var text := String(hud.call("objective_text"))
	assert_string_contains(text.to_lower(), "entrega", "the objective names the goal")
	for node in hud.find_children("*", "Label", true, false):
		var label := node as Label
		assert_false(
			label.text.to_lower().contains("wasd"),
			"no control legend in the HUD (it lives on the title and in pause)"
		)

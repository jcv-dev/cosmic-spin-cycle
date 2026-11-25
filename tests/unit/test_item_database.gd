extends GutTest
## data/items.tres must load as an ItemDatabase with the five GDD §6 items.

var db: ItemDatabase


func before_each() -> void:
	db = ItemDatabase.load_default()


func test_database_loads() -> void:
	assert_not_null(db, "items.tres must load as an ItemDatabase")
	if db == null:
		return
	assert_eq(db.items.size(), 5, "exactly five item definitions")


func test_all_five_ids_exist() -> void:
	if db == null:
		return
	assert_eq(db.ids().size(), 5)
	for id in Config.ITEM_IDS:
		assert_true(db.has_item(id), "missing item id %s" % id)
		assert_not_null(db.get_item(id))
	assert_null(db.get_item(&"__missing__"), "unknown id returns null")


func test_masses_match_gdd() -> void:
	if db == null:
		return
	assert_almost_eq(db.get_item(&"rocky").mass_kg, 1.0, 0.0001)
	assert_almost_eq(db.get_item(&"sock").mass_kg, 0.3, 0.0001)
	assert_almost_eq(db.get_item(&"moon").mass_kg, 0.8, 0.0001)
	assert_almost_eq(db.get_item(&"gas_giant").mass_kg, 2.2, 0.0001)
	assert_almost_eq(db.get_item(&"galaxy_core").mass_kg, 3.0, 0.0001)


func test_wash_times_and_points() -> void:
	if db == null:
		return
	var expected := {
		&"rocky": [6.0, 100],
		&"sock": [4.0, 150],
		&"moon": [7.0, 200],
		&"gas_giant": [10.0, 350],
		&"galaxy_core": [12.0, 1000],
	}
	for id: StringName in expected:
		var item := db.get_item(id)
		assert_almost_eq(item.wash_s, float(expected[id][0]), 0.0001, "%s wash" % id)
		assert_eq(item.points, int(expected[id][1]), "%s points" % id)


func test_slots() -> void:
	if db == null:
		return
	assert_eq(db.get_item(&"rocky").slots, 1)
	assert_eq(db.get_item(&"sock").slots, 1)
	assert_eq(db.get_item(&"moon").slots, 1)
	assert_eq(db.get_item(&"gas_giant").slots, 2, "gas giant occupies two slots")
	assert_eq(db.get_item(&"galaxy_core").slots, 3, "core needs an empty washer")


func test_physics_fields() -> void:
	if db == null:
		return
	assert_almost_eq(db.get_item(&"rocky").bounce, 0.4, 0.0001)
	assert_almost_eq(db.get_item(&"sock").bounce, 0.3, 0.0001)
	assert_almost_eq(db.get_item(&"gas_giant").bounce, 0.85, 0.0001)
	for id in Config.ITEM_IDS:
		var item := db.get_item(id)
		assert_gt(item.radius, 0.0, "%s needs a collision radius" % id)
		assert_gt(item.friction, 0.0, "%s needs friction" % id)
		assert_true(item.sprite_id != "", "%s needs an art id" % id)


func test_sock_belt_scale_matches_config() -> void:
	if db == null:
		return
	assert_almost_eq(db.get_item(&"sock").belt_speed_scale, Config.BELT_SOCK_SPEED_SCALE, 0.0001)
	assert_almost_eq(db.get_item(&"rocky").belt_speed_scale, 1.0, 0.0001)


func test_specials() -> void:
	if db == null:
		return
	assert_eq(db.get_item(&"rocky").special, ItemData.Special.NONE)
	assert_eq(db.get_item(&"sock").special, ItemData.Special.SQUELCH)
	assert_eq(db.get_item(&"moon").special, ItemData.Special.BOOMERANG)
	assert_eq(db.get_item(&"gas_giant").special, ItemData.Special.NONE)
	assert_eq(db.get_item(&"galaxy_core").special, ItemData.Special.GRAVITY_FIELD)


func test_only_core_is_unique() -> void:
	if db == null:
		return
	assert_true(db.get_item(&"galaxy_core").unique)
	for id in Config.ITEM_IDS:
		if id != &"galaxy_core":
			assert_false(db.get_item(id).unique, "%s is not unique" % id)


func test_display_keys_and_tints() -> void:
	if db == null:
		return
	for id in Config.ITEM_IDS:
		var item := db.get_item(id)
		assert_true(item.display_key.begins_with("ITEM_"), "%s translation key" % id)
		assert_gt(item.tint_color.a, 0.0)

extends GutTest
## The greybox belt visual must be palette-locked (AGENTS Part B4): no colour is invented
## in a node script, they all come from `art/palette.json`.


func test_palette_file_exists() -> void:
	assert_true(
		FileAccess.file_exists(EnvironmentPalette.PALETTE_PATH),
		"art/palette.json is the frozen 30-colour contract"
	)


func test_palette_loads_known_colours() -> void:
	assert_true(EnvironmentPalette.has_color("metal_1"))
	assert_eq(EnvironmentPalette.color("space_void"), Color("#0B0C10"), "GDD background")
	assert_eq(EnvironmentPalette.color("funk_cyan"), Color("#19E3D1"), "beat / belt accent")


func test_every_colour_the_belts_draw_exists() -> void:
	var used := ["space_mid", "metal_1", "metal_3", "space_haze", "funk_cyan", "hazard_orange"]
	for name: String in used:
		assert_true(EnvironmentPalette.has_color(name), "palette is missing %s" % name)


func test_unknown_colour_is_loud_not_black() -> void:
	assert_eq(
		EnvironmentPalette.color("does_not_exist"),
		EnvironmentPalette.MISSING_COLOR,
		"a typo draws magenta instead of vanishing into the background"
	)


func test_palette_is_cached() -> void:
	var first := EnvironmentPalette.load_colors()
	var second := EnvironmentPalette.load_colors()
	assert_same(first, second, "the JSON is parsed once per process")
	assert_true(first.size() >= 30, "30 colours in the contract")

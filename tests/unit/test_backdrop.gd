extends GutTest
## Procedural backdrop (starfield + nebula/planet sheet).
##
## Everything is generated in code, so the tests cover three things the layer must never
## lose: determinism for a seed, texture caching (no leak per build) and whole-pixel drift.


func before_each() -> void:
	Backdrop.clear_cache()


func after_each() -> void:
	Backdrop.clear_cache()


func test_generate_stars_is_deterministic() -> void:
	var first := Backdrop.generate_stars(320, 180, 90, 4242)
	var second := Backdrop.generate_stars(320, 180, 90, 4242)
	assert_eq(first.get_size(), Vector2i(320, 180))
	assert_eq(first.get_data(), second.get_data(), "same seed must yield identical pixels")


func test_generate_stars_differs_by_seed() -> void:
	var first := Backdrop.generate_stars(320, 180, 90, 4242)
	var other := Backdrop.generate_stars(320, 180, 90, 99)
	assert_ne(first.get_data(), other.get_data())


func test_stars_use_three_brightness_classes() -> void:
	var image := Backdrop.generate_stars(320, 180, 90, 7)
	var colours := {}
	var lit := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			lit += 1
			if not is_equal_approx(pixel.a, 1.0):
				# The dim cross arms of the brightest stars are deliberate 55 % pixels.
				continue
			colours[pixel.to_html(false)] = true
	assert_true(lit >= 90, "at least one pixel per star")
	assert_eq(colours.size(), 3, "three brightness classes (plus the dim cross pixels)")


func test_star_texture_is_cached_and_two_tiles_wide() -> void:
	var first := Backdrop.star_texture()
	var second := Backdrop.star_texture()
	assert_same(first, second, "textures must be cached, not rebuilt")
	assert_eq(first.get_size(), Vector2(Backdrop.SHEET_ART_W, Backdrop.SHEET_ART_H))
	assert_eq(
		int(first.get_size().x),
		Backdrop.TILE_ART_W * 2,
		"two identical tiles so the drift wraps invisibly",
	)
	Backdrop.clear_cache()
	assert_ne(first, Backdrop.star_texture(), "clear_cache must rebuild")


func test_nebula_texture_has_alpha_and_is_cached() -> void:
	var texture := Backdrop.nebula_texture()
	assert_not_null(texture)
	assert_same(texture, Backdrop.nebula_texture())
	var image := texture.get_image()
	var lowest := 1.0
	var highest := 0.0
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			var alpha := image.get_pixel(x, y).a
			lowest = minf(lowest, alpha)
			highest = maxf(highest, alpha)
	assert_gt(highest, 0.05, "the nebula sheet must not be empty")
	assert_lt(highest, 0.5, "it is a wash, never opaque")
	assert_gt(highest - lowest, 0.02, "the bands must vary across the sheet")


func test_planet_limb_bakes_a_body_and_a_rim() -> void:
	var body := Backdrop._planet_limb_alpha(345, 0)
	var rim := 0.0
	for x in range(0, 320):
		rim = maxf(rim, Backdrop._planet_limb_alpha(x, 0))
	assert_true(body > 0.0, "planet body tint")
	assert_gt(rim, body, "rim ring is brighter than the body")
	assert_almost_eq(rim, 0.30, 0.001, "the limb itself is the brightest pixel")
	assert_eq(Backdrop._planet_limb_alpha(20, 170), 0.0, "far from the limb is empty")


func test_build_creates_the_layer_at_z_minus_95() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var backdrop := Backdrop.build(root)
	assert_eq(backdrop.z_index, -95)
	assert_not_null(backdrop.get_node_or_null("Stars"), "stars and nebula share one sheet")


func test_star_drift_lands_on_whole_pixels() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var backdrop := Backdrop.build(root)
	var stars := backdrop.get_node("Stars") as Sprite2D
	for step in range(120):
		backdrop._process(0.37)
		assert_eq(
			stars.position.x,
			float(roundi(stars.position.x)),
			"drift must stay on integer world pixels (step %d)" % step,
		)
		assert_true(stars.position.x <= 0.0 and stars.position.x >= -Backdrop.DRIFT_WRAP)

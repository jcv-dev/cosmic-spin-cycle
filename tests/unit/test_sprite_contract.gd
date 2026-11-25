extends GutTest
## Contract loader: missing art must degrade to null, and the palette mirror must stay in
## sync with art/palette.json.


func test_missing_sheet_degrades() -> void:
	assert_false(SpriteSheet.has_sheet("__missing_sheet__"))
	assert_null(SpriteSheet.sprite_frames("__missing_sheet__"))
	assert_null(SpriteSheet.frame_texture("__missing_sheet__", &"idle"))
	assert_eq(SpriteSheet.frame_size("__missing_sheet__"), Vector2i.ZERO)
	assert_eq(SpriteSheet.load_data("__missing_sheet__"), {})


func test_palette_mirror_matches_json() -> void:
	var text := FileAccess.get_file_as_string("res://art/palette.json")
	var data: Dictionary = JSON.parse_string(text)
	assert_eq(int(data.colors.size()), 30)
	var names: Array = []
	for row in data.colors:
		names.append(row.name)
	assert_true(names.has("space_void"))
	assert_true(names.has("funk_cyan"))
	assert_true(names.has("clean_green"))
	assert_eq(Palette.SPACE_VOID.to_html(false), "0b0c10")
	assert_eq(Palette.RED_2.to_html(false), "c41e3a")
	assert_eq(Palette.FUNK_CYAN.to_html(false), "19e3d1")


func test_font_fallback_is_available() -> void:
	assert_not_null(Fonts.pixel_font(), "a font must always be available")


func test_grade_colors_are_distinct() -> void:
	assert_ne(
		Palette.grade_color(RhythmEvaluator.Grade.PERFECT),
		Palette.grade_color(RhythmEvaluator.Grade.GOOD)
	)

extends GutTest
## Difficulty presets (docs/DECISIONS.md D047): one value per preset, and CHAOS must be
## harder than CALM on every axis or the selector lies to the player.


func test_every_axis_covers_all_three_presets() -> void:
	var axes := [
		Config.DIFFICULTY_KEYS.size(),
		Config.DIFFICULTY_LABEL_KEYS.size(),
		Config.DIFFICULTY_HAZARD_PER_MEASURE.size(),
		Config.DIFFICULTY_WARNING_BEATS.size(),
		Config.DIFFICULTY_HIT_DAMAGE.size(),
		Config.DIFFICULTY_IFRAME_S.size(),
		Config.DIFFICULTY_SPAWN_SCALE.size(),
		Config.DIFFICULTY_VOID_SCALE.size(),
		Config.DIFFICULTY_WINDOW_SCALE.size(),
		Config.DIFFICULTY_COLLAPSE_S.size(),
	]
	for size: int in axes:
		assert_eq(size, 3, "every difficulty axis has one value per preset")


func test_default_is_standard() -> void:
	assert_eq(Config.DIFFICULTY_DEFAULT, Config.Difficulty.STANDARD)
	assert_eq(Config.difficulty_key(Config.DIFFICULTY_DEFAULT), &"standard")


func test_keys_round_trip() -> void:
	for value: int in range(Config.DIFFICULTY_KEYS.size()):
		var key := Config.difficulty_key(value)
		assert_eq(Config.difficulty_from_key(key), value, "key %s round-trips" % key)


func test_unknown_key_falls_back_to_the_default() -> void:
	assert_eq(Config.difficulty_from_key(&"nightmare"), Config.DIFFICULTY_DEFAULT)
	assert_eq(Config.difficulty_from_key(&""), Config.DIFFICULTY_DEFAULT)


func test_out_of_range_values_clamp_to_the_nearest_preset() -> void:
	assert_eq(Config.difficulty_index(-9), 0)
	assert_eq(Config.difficulty_index(99), Config.DIFFICULTY_KEYS.size() - 1)


func test_chaos_is_harder_than_calm_on_every_axis() -> void:
	var calm := Config.Difficulty.CALM
	var chaos := Config.Difficulty.CHAOS
	assert_gt(
		Config.DIFFICULTY_HAZARD_PER_MEASURE[chaos],
		Config.DIFFICULTY_HAZARD_PER_MEASURE[calm],
		"more hazards"
	)
	assert_lt(
		Config.DIFFICULTY_HIT_DAMAGE[chaos], Config.DIFFICULTY_HIT_DAMAGE[calm], "harder hits"
	)
	assert_lt(Config.DIFFICULTY_IFRAME_S[chaos], Config.DIFFICULTY_IFRAME_S[calm], "fewer i-frames")
	assert_lt(
		Config.DIFFICULTY_SPAWN_SCALE[chaos], Config.DIFFICULTY_SPAWN_SCALE[calm], "faster belt"
	)
	assert_gt(
		Config.DIFFICULTY_VOID_SCALE[chaos], Config.DIFFICULTY_VOID_SCALE[calm], "faster void"
	)
	assert_lt(
		Config.DIFFICULTY_WINDOW_SCALE[chaos],
		Config.DIFFICULTY_WINDOW_SCALE[calm],
		"tighter windows"
	)
	assert_gt(
		Config.DIFFICULTY_COLLAPSE_S[chaos], Config.DIFFICULTY_COLLAPSE_S[calm], "longer collapse"
	)


func test_telegraph_is_never_below_two_beats() -> void:
	for beats: int in Config.DIFFICULTY_WARNING_BEATS:
		assert_gte(beats, 2, "one beat at 142 BPM (423 ms) is not readable")


## STANDARD is the baseline every measurement in the repo was taken at (98 spawns, 668
## tests). If this moves, the balance docs and the sim report must be regenerated.
func test_standard_keeps_the_measured_baseline() -> void:
	assert_eq(Config.DIFFICULTY_SPAWN_SCALE[Config.Difficulty.STANDARD], 1.0)
	assert_eq(Config.DIFFICULTY_WINDOW_SCALE[Config.Difficulty.STANDARD], 1.0)
	assert_eq(Config.DIFFICULTY_HIT_DAMAGE[Config.Difficulty.STANDARD], -6.0)

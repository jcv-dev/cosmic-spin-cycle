class_name EnvironmentPalette
extends RefCounted
## Palette lookup for the procedural greybox visuals.
##
## M3 must look like the game's palette before the art pipeline ships, but a colour must
## never be invented in a node script: every environment colour comes from
## `art/palette.json` (the frozen 30-colour contract). Values are cached after the first
## read, so `_draw()` can call [method color] every frame.

const PALETTE_PATH := "res://art/palette.json"

## Drawn for a missing name so a typo is visible instead of silently black.
const MISSING_COLOR := Color(1.0, 0.0, 1.0)

static var _colors: Dictionary = {}
static var _loaded := false


## Colour for a palette name (`"metal_1"`, `"funk_cyan"`, …).
static func color(name: String) -> Color:
	var colors := load_colors()
	return colors.get(name, MISSING_COLOR) as Color


## True when the palette declares `name`.
static func has_color(name: String) -> bool:
	return load_colors().has(name)


## Parsed palette, loaded once. Empty when `art/palette.json` is unreadable.
static func load_colors() -> Dictionary:
	if _loaded:
		return _colors
	_loaded = true
	_colors = {}
	if not FileAccess.file_exists(PALETTE_PATH):
		push_warning("EnvironmentPalette: %s is missing" % PALETTE_PATH)
		return _colors
	var f := FileAccess.open(PALETTE_PATH, FileAccess.READ)
	if f == null:
		push_warning("EnvironmentPalette: cannot read %s" % PALETTE_PATH)
		return _colors
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_warning("EnvironmentPalette: %s is not an object" % PALETTE_PATH)
		return _colors
	var entries: Variant = (parsed as Dictionary).get("colors", [])
	if not (entries is Array):
		return _colors
	var rows: Array = entries as Array
	for entry: Variant in rows:
		if not (entry is Dictionary):
			continue
		var row := entry as Dictionary
		var name := str(row.get("name", ""))
		var hex := str(row.get("hex", ""))
		if name == "" or hex == "":
			continue
		_colors[name] = Color(hex)
	return _colors


## Drops the cache (tests only).
static func clear_cache() -> void:
	_colors = {}
	_loaded = false

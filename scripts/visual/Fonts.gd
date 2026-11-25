class_name Fonts
extends RefCounted
## Loads the first imported font found in assets/fonts/. Falls back to the engine font so
## UI never breaks while the audio/art deliverables are still landing.

const DIR := "res://assets/fonts/"
const PREFERRED := ["Silkscreen-Regular.ttf", "Silkscreen-Bold.ttf"]

static var _cached: Font


static func pixel_font() -> Font:
	if _cached != null:
		return _cached
	for file in PREFERRED:
		if ResourceLoader.exists(DIR + file):
			var preferred := load(DIR + file) as Font
			if preferred != null:
				_cached = preferred
				return _cached
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file in dir.get_files():
			if file.ends_with(".ttf") or file.ends_with(".otf"):
				var font := load(DIR + file) as Font
				if font != null:
					_cached = font
					return _cached
	_cached = ThemeDB.fallback_font
	return _cached


static func has_custom_font() -> bool:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return false
	for file in dir.get_files():
		if file.ends_with(".ttf") or file.ends_with(".otf"):
			return true
	return false

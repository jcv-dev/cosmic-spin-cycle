class_name Palette
extends RefCounted
## Palette constants mirroring art/palette.json (AGENTS §B4). Never add colours here
## without updating the palette file, the linter and docs/DECISIONS.md.

const SPACE_VOID := Color("#0B0C10")
const SPACE_DEEP := Color("#14172A")
const SPACE_MID := Color("#1F2340")
const SPACE_HAZE := Color("#2E3460")

const METAL_0 := Color("#4A5278")
const METAL_1 := Color("#6B7599")
const METAL_2 := Color("#9AA4C4")
const METAL_3 := Color("#CDD3E8")
const METAL_4 := Color("#F4F6FC")

const RED_0 := Color("#3D0A1C")
const RED_1 := Color("#7A1230")
const RED_2 := Color("#C41E3A")
const RED_3 := Color("#F0526B")
const RED_4 := Color("#FF9AA8")

const BLUE_0 := Color("#0E1A4D")
const BLUE_1 := Color("#1E3A9A")
const BLUE_2 := Color("#3B6DF0")
const BLUE_3 := Color("#7FA6FF")
const BLUE_4 := Color("#C3D8FF")

const YEL_0 := Color("#5C3A00")
const YEL_1 := Color("#B07A00")
const YEL_2 := Color("#FFC21A")
const YEL_3 := Color("#FFE066")
const YEL_4 := Color("#FFF5B8")

const FUNK_CYAN := Color("#19E3D1")
const FUNK_TEAL := Color("#0B7F86")
const FUNK_MAGENTA := Color("#E040FB")
const FUNK_PLUM := Color("#7A1F8F")
const CLEAN_GREEN := Color("#5CFF8A")
const HAZARD_ORANGE := Color("#FF7A1A")


## Body fill colour for an item variant.
static func body_for_variant(color: StringName) -> Color:
	match color:
		&"red":
			return RED_2
		&"blue":
			return BLUE_2
		&"yellow":
			return YEL_2
		_:
			return METAL_2


## Accent colour for grade feedback.
static func grade_color(grade: int) -> Color:
	match grade:
		RhythmEvaluator.Grade.PERFECT:
			return FUNK_MAGENTA
		RhythmEvaluator.Grade.GOOD:
			return FUNK_CYAN
		_:
			return METAL_1

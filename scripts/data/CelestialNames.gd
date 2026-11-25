class_name CelestialNames
extends RefCounted
## Real catalogue names shown under each item, so a washable object reads as a world and not
## as "clothes" (owner: "you are washing planets"). Names are assigned round-robin per item
## type, which is deterministic for a spawn order and needs no RNG.

const NAMES := {
	&"rocky":
	[
		"KEPLER-452b",
		"TRAPPIST-1e",
		"PROXIMA b",
		"55 CANCRI e",
		"GJ 1214 b",
		"KEPLER-16b",
		"WASP-12b",
		"HD 189733b",
		"LHS 1140b",
		"KEPLER-186f",
	],
	&"gas_giant":
	[
		"JÚPITER",
		"SATURNO",
		"HD 209458b",
		"WASP-17b",
		"KEPLER-7b",
		"GJ 436b",
		"HAT-P-7b",
		"51 PEGASI b",
	],
	&"moon":
	[
		"ÍO",
		"EUROPA",
		"GANÍMEDES",
		"CALISTO",
		"TITÁN",
		"ENCÉLADO",
		"TRITÓN",
		"CARONTE",
		"FOBOS",
		"DEIMOS",
	],
	&"sock":
	[
		"HALLEY",
		"HALE-BOPP",
		"NEOWISE",
		"ENOKE",
		"ISON",
		"LOVEJOY",
		"BORRELLY",
		"McNAUGHT",
	],
	&"galaxy_core":
	[
		"SAGITARIO A*",
		"ANDRÓMEDA",
		"M87*",
		"CENTAURO A",
		"OJ 287",
		"NGC 1277",
	],
}

static var _cursor := 0


## Next catalogue name for a type. Unknown ids fall back to a rocky world.
static func next_name(item_id: StringName) -> String:
	var list: Array = NAMES.get(item_id, NAMES[&"rocky"])
	if list.is_empty():
		return ""
	var name: String = str(list[_cursor % list.size()])
	_cursor += 1
	return name


## Test/reset hook: makes the sequence repeatable for screenshots and unit tests.
static func reset_cursor() -> void:
	_cursor = 0

class_name Compatibility
extends RefCounted
## Item ↔ washer matching (GDD §5.2, §A6 #10). Galaxy core is a wildcard.

const GALAXY_CORE := &"galaxy_core"


static func is_wildcard(item_id: StringName) -> bool:
	return item_id == GALAXY_CORE


## A washer requirement is a colour ("red"), a pattern ("ringed") or "wild".
static func item_fits(
	item_id: StringName, item_color: StringName, item_pattern: StringName, requirement: StringName
) -> bool:
	if is_wildcard(item_id) or requirement == &"wild":
		return true
	return item_color == requirement or item_pattern == requirement

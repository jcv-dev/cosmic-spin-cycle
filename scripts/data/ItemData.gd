class_name ItemData
extends Resource
## One laundry-item definition (GDD §6, AGENTS §A5). Pure data, no scene dependencies.
##
## Instances live in `res://data/items.tres`; gameplay reads them through `ItemDatabase`.
## `radius` is in **art pixels** (16 px items use ~8); runtime collision/physics multiply it
## by `Config.ART_SCALE`. `mass_kg` maps directly to RigidBody2D.mass.

enum Special {
	NONE,
	BOOMERANG,
	GRAVITY_FIELD,
	SQUELCH,
}

@export var id: StringName = &""
@export var display_key := ""
@export var mass_kg := 1.0
@export var wash_s := 6.0
@export var points := 100
@export var slots := 1
@export var radius := 8.0
@export var bounce := 0.4
@export var friction := 0.6
@export var linear_damp := 0.4
@export var belt_speed_scale := 1.0
@export var special: Special = Special.NONE
@export var sprite_id := ""
@export var tint_color := Color("#C41E3A")
@export var unique := false

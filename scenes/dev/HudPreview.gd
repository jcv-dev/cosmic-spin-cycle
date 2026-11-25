extends Node2D
## Dev preview for the HUD: fake state, no gameplay. Used by tools/screenshot.gd.

const HUD_SCENE := "res://scenes/ui/HUD.tscn"


func _ready() -> void:
	GameState.reset(2026)
	GameState.add_score(1250)
	GameState.add_stability(-33.0)
	GameState.combo = 4
	GameState.combo_changed.emit(4)
	GameState.set_phase(2)
	BeatConductor.start(Config.phase_bpm(2))
	var packed := load(HUD_SCENE) as PackedScene
	var hud := packed.instantiate() as Control
	hud.set_shift_time(270.0)
	add_child(hud)
	hud.set_phase(2, Config.phase_bpm(2))
	hud.show_grade(RhythmEvaluator.Grade.PERFECT)

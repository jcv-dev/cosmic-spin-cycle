# GDD / rubric traceability

Living matrix: every GDD requirement and course-rubric item → where it lives → how it is
verified. Update at each milestone. Status: **M0–M3 implemented; M4+ planned.**

## Course rubric

| Requirement | Where | Status / evidence |
|---|---|---|
| Public GitHub repo | `README.md`, `docs/COMMITS.md`, CI | repo initialised with conventional history; publishing is the owner's step |
| Commits from every team member | git history | one developer + agent workstreams, many small green commits |
| Approved engine (Godot) | `project.godot` | Godot 4.7.2, GL Compatibility, verified `godot --version` |
| One complete level with clear start/end | `ShiftManager`/`MainLevel` (M5–M6) | M3 provides the 480 s phase/spawn spine; win/lose + screen flow land in M5–M6 |
| Audio is 50% of the game | `BeatConductor`, `assets/audio/music`, SFX, calibration | 4 phase stems (105/118/130/142 BPM), click tracks, 9 SFX, 10 s calibration wizard |
| No drugs/sex/politics/religion | content | game is a cosmic laundromat; zero violence; ESRB E / PEGI 3 |
| Demo + oral defence | `docs/PROGRESS.md`, this matrix, `docs/QA_CHECKLIST.md` | evidence trail + reproducible commands |

## GDD sections

| GDD | Requirement | Implementation | Verification |
|---|---|---|---|
| §1.2 | Audio-latency blocker | `BeatConductor.get_song_time()` compensation + `Settings.user_calibration_offset` + `CalibrationMath` | `test_beat_*`, `test_calibration_*`; manual protocol in `docs/CALIBRATION.md` |
| §1.8 | Cosmic retro-futurism, dark bg `#0B0C10` | `art/palette.json`, `art/DESIGN.md`, `env_room` | sprite linter, contact sheet |
| §2.2 | Core loop: intercept → identify → throw on beat → stabilise/collect | Player/grabber (M2), belts/spawns (M3), washers/chute (M4) | M2/M3 tests; M4 pending |
| §2.2 | Outer loop 8 min, 1 h = 80 s | `Config.GAME_HOURS`, `SHIFT_DURATION_S`, `clock_string()` | `test_config_clock` (00:00→06:00) |
| §2.3 | Win conditions | `ShiftManager` (M5) | pending |
| §2.4 | Lose conditions + stability ledger | `GameState.add_stability`, `StabilityRules` (M4–M5) | `test_game_state`; full bot proof in M5 |
| §2.5 | 4 phases 105/118/130/142, 3.5/2.4/1.7 s, final convoy | `data/phases.tres`, `SpawnSchedule` (M3) | phase/spawn tests, 480 s sim |
| §2.5 | Belt activation per phase | `data/layout.json`, `ConveyorBelt.set_active` (M3) | phase activation test |
| §3.1 | 1280×720 room, 3 perimeter belts, 4 inner-corner washers, central chute | `data/layout.json`, `RoomBuilder` | layout tests, room-builder tests |
| §3.2 | Accel 2400, vmax 340, friction μ 0.12 | `Config`, `Player` (M2) | player movement/friction tests |
| §3.2 | Hold one item at 48 px, inherit inertia | `MagneticGrabber`, `LaundryItem._integrate_forces` (M2) | grab/hold tests |
| §3.2 | On-beat selective collision / magnetic assist | grade-scaled throws (M2/M4) | throw tests; assist with washers in M4 |
| §4.1 | Keyboard+mouse and gamepad controls | `tools/setup_project.gd` Input Map | project.godot inspection |
| §4.2 | Diegetic HUD: pulse ring, clock, stability, combo, washer holos | `HUD` (M6 extends), `PulseRing` (M6) | HUD tests, screenshots |
| §4.3 | Title → game → end screen, instant restart | M6 | pending |
| §5.1 | PERFECT ±65 ms, GOOD ±130 ms, MISS | `RhythmEvaluator` | boundary tests (0.065/0.130/0.131) |
| §5.1 | PERFECT +40% force, +2 combo, −3 s wash; GOOD +1, −1 s; MISS reset + turbulence | `Config`, `RhythmEvaluator`, `GameState` | reward tests, state tests; wash application in M4 |
| §5.2 | 3 slots, WASHING cycle, TURBULENT, explosion, DONE | `WasherFSM` (M4) | pending |
| §5.3 | Belt constant velocity; phase 3 reversal every 16 measures with 4-beat warning | `ConveyorBelt`, `BeltReversal` (M3) | belt/reversal tests |
| §6 | Five items with mass/wash/points/physics | `data/items.tres` (M2) | database + behaviour tests |
| §7.1 | BeatConductor signals from playback position | `scenes/main/BeatConductor.tscn` | beat tests |
| §7.2 | Directory structure | `res://` tree | `docs/CONTRACTS.md` |
| §7.3 | F1–F4 debug cheats | M5 | pending |
| §8.2-1 | HARD_CUT vs DRUM_BRIDGE | `Config.PHASE_TRANSITION_MODE` (M8) | pending |
| §8.2-2 | MISS wash penalty toggle | `Config.MISS_WASH_PENALTY_S` | wired in M4 |
| §A6 #2 | Colapso de Singularidad = BROKEN | `WasherFSM` (M4) | pending |
| §A6 #3 | Cycle = max(item.wash_s), floor 2 s | M4 | pending |
| §A6 #4 | Cycle starts full or on a strike | M4 | pending |
| §A6 #5 | Turbulence limit min(5 s, 8 beats) | M4 | pending |
| §A6 #6 | Turbulence 0–1 + phase-3 every 3rd cycle | M4 | pending |
| §A6 #7 | GOOD resolves turbulence, MISS does not | `RhythmEvaluator.resolves_turbulence` | test passes |
| §A6 #8 | Wash reduction on insertion, once per throw | M4 | pending |
| §A6 #9 | Supernova flag | `Config.ENABLE_SUPERNOVA` | M5 |
| §A6 #10 | Phase colour/pattern introduction, core wildcard | `data/phases.tres` (M3), `Compatibility` | phase tests; M4 FSM |
| §A6 #11 | Final Load counts delivered before 480 | M5 | pending |
| §A6 #12 | Layout coordinates | `data/layout.json` | layout tests |
| §A6 #13 | Score = points × combo at chute, S/A/B/C | M5/M9 | pending |
| §A6 #14 | Combo no decay, cap ×8 | `GameState` | combo tests |
| §A6 #15 | Final Load 4+4+4+1 | `data/phases.tres` (M3) | convoy tests |
| §A6 #16 | BeatConductor is a scene autoload | `project.godot`, `scenes/main/BeatConductor.tscn` | beat tests |
| §A6 #17 | Friction interpretation | `Config.PLAYER_FRICTION`, `Player` | friction test |

## Reproducible verification

```bash
./tools/dev.sh check              # import + tests + lint + format
./tools/verify_milestones.sh      # all gates incl. sim/asset/audio when present
./tools/dev.sh sim                # headless 480 s spawn simulation
./tools/dev.sh shot res://scenes/main/Main.tscn res://.work/screens/main.png
```

## Known gaps (honest)

- M4–M9 systems are not implemented yet; rows marked "pending" are the roadmap, not claims.
- Windows audio latency and gamepad feel need the owner's hardware (documented protocol).
- The public GitHub remote is not configured in this checkout; the owner must create/push.

## Status 2026-11-24 — M0–M3 evidence

M0–M3 are implemented and green: **314 tests / 7,175 assertions**, `tools/lint_sprites.py`
29/29, `tools/verify_audio.py` 16/16, `tools/sim_run.gd` 197 spawns.

| Area | Primary evidence |
|---|---|
| Beat windows / clock | `tests/unit/test_rhythm_evaluator.gd`, `test_beat_clock.gd`, `test_beat_compensation.gd`, `tests/integration/test_beat_480s.gd` |
| Calibration | `test_calibration_math.gd`, `test_calibration_modal.gd`, `docs/CALIBRATION.md` |
| Player/item physics | `test_player_*.gd`, `test_item_*.gd`, `test_physics_items.gd`, `docs/M2_PHYSICS.md` |
| Belts / reversal / shredder | `test_belt_*.gd`, `test_shredder.gd`, `docs/M3_WORLD.md` |
| Phases / spawning | `test_phase_*.gd`, `test_spawn_*.gd`, `test_world_simulation.gd`, `tools/sim_run.gd` |
| Level integration | `tests/integration/test_main_level.gd` (belts, activation, first spawn, belt transport, warp) |
| Art / audio / font | `tools/lint_sprites.py`, `tools/verify_audio.py`, `docs/PROVENANCE.md` |

Rows above marked "pending" are M4–M9 work, not regressions. The M3 level intentionally has
no washers/chute yet (D024).

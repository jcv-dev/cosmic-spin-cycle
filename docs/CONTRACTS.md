# Frozen contracts — M0–M3

> Read this before touching code. These interfaces are **frozen for the M0–M3 wave**.
> If something must change, stop and report it; do not silently diverge.
> Language: code, comments, tests and docs in **English**. Player-facing strings are
> translation keys, `es` is the default locale.

## 1. Ownership and boundaries

| Area | Owner | Paths |
|---|---|---|
| Project shell, autoloads, layout, main scenes, CI | lead | `project.godot`, `scripts/autoload/`, `scripts/logic/Compatibility.gd`, `scripts/visual/`, `scenes/main/`, `data/layout.json`, `.github/`, root docs |
| Beat engine + calibration | session `m1-beat` | `scripts/autoload/BeatConductor.gd`, `scenes/main/BeatConductor.tscn`, `scripts/ui/DebugOverlay.*`, `scripts/ui/CalibrationModal.*`, `scripts/logic/CalibrationMath.gd`, `tools/make_click_track.py`, `assets/audio/metronome/`, `tests/**/test_beat_*`, `tests/**/test_calibration_*`, `tests/**/test_rhythm_*`, `docs/CALIBRATION.md` |
| Player + item physics | session `m2-physics` | `scripts/entities/`, `scripts/components/MagneticGrabber.gd`, `scripts/data/ItemData.gd`, `scripts/data/ItemDatabase.gd`, `scenes/entities/`, `data/items.tres`, `tests/**/test_player_*`, `tests/**/test_item_*`, `scenes/dev/PlayerSandbox.tscn` |
| Belts + spawning + phases | session `m3-world` | `scripts/environment/`, `scripts/components/SpawnDirector.gd`, `scripts/logic/SpawnSchedule.gd`, `scripts/data/PhaseData.gd`, `scripts/data/PhaseTable.gd`, `scenes/environment/`, `data/phases.tres`, `tests/**/test_belt_*`, `tests/**/test_spawn_*`, `tests/**/test_phase_*`, `scenes/dev/WorldSandbox.tscn`, `tools/sim_run.gd` |
| Sprites + art pipeline | session `a1-art` | `assets/sprites/`, `art/`, `tools/pxlib.py`, `tools/make_art.py`, `tools/lint_sprites.py`, `tools/preview.py`, `tools/fetch_sources.py`, `art/CONCEPTS/` |
| Music + SFX + fonts | session `a2-audio` | `assets/audio/music/`, `assets/audio/sfx/`, `assets/audio/music.json`, `assets/fonts/`, `tools/fetch_audio.py`, `docs/PROVENANCE.md`, `docs/AUDIO.md` |

**Do not edit files outside your area.** In particular nobody except the lead edits
`project.godot`, `Config.gd`, `GameState.gd`, `Settings.gd`, `data/layout.json`, `AGENTS.md`,
`docs/PROGRESS.md`, `MainLevel.tscn` or `Main.tscn`. Need a change there? Report it.

**Never spawn subagents.** Do the work yourself.

## 2. Toolchain and verification commands

```bash
# Godot 4.7.2 is on PATH. In a worktree, make writable user dirs first:
export XDG_DATA_HOME="$PWD/.work/xdg/data" XDG_CACHE_HOME="$PWD/.work/xdg/cache" \
       XDG_CONFIG_HOME="$PWD/.work/xdg/config"

godot --headless --path . --import                 # rebuild import cache after adding files
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gdir=res://tests/unit -ginclude_subdirs -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd \
      -gdir=res://tests/integration -ginclude_subdirs -gexit
godot --headless --path . --quit                    # smoke: must exit 0
/usr/bin/python3 tools/lint_sprites.py               # assets only (Pillow + numpy available)

# Lint tooling (shared read-only venv):
/home/moravak/proyecto/.work/venv/bin/gdlint scripts tests tools
/home/moravak/proyecto/.work/venv/bin/gdformat --check scripts tests
```

If `gdlint`/`gdformat` do not exist yet, use `godot --headless --check-only` style checks
and note it in your report; the lead runs the final lint gate.

## 3. Autoloads (order matters)

`Config` → `Settings` → `GameState` → `BeatConductor` (scene autoload).

### `Config` — `res://scripts/autoload/Config.gd`
All GDD numbers live here. Read-only. Notable additions beyond AGENTS §A5:

```gdscript
const BELT_SPEED := 110.0            # world px/s
const BELT_ACCEL := 900.0
const BELT_SOCK_SPEED_SCALE := 1.6
const THROW_SPEED := 900.0           # px/s for a 1.0 impulse multiplier
const THROW_GAS_OFFBEAT_SCALE := 0.5
const HOLD_SPRING := 18.0
const HOLD_MAX_SPEED := 1100.0
const DASH_DURATION_S := 0.18
const DASH_DISTANCE_PX := 120.0
const STRIKE_RANGE_PX := 96.0
const BOOMERANG_ACCEL := 1200.0
const BOOMERANG_DURATION_S := 0.6
const CORE_GRAVITY_RADIUS := 170.0
const CORE_GRAVITY_ACCEL := 220.0
const MAX_ALIVE_ITEMS := 40
const MAX_ITEM_SPEED := 1600.0
const PHASE_TRANSITION_MODE := TransitionMode.HARD_CUT
const MISS_WASH_PENALTY_S := 0.0
const ENABLE_SUPERNOVA := true
const FINAL_LOAD_COUNTS_DONE_IN_WASHER := false
const WINDOW_SCALE_BY_PHASE: Array[float] = [1.0, 1.0, 1.0, 1.0]

enum TransitionMode { HARD_CUT, DRUM_BRIDGE }
enum CollisionLayer { WORLD = 1, PLAYER = 2, ITEMS = 4, BELT = 8,
                      SHREDDER = 16, CHUTE = 32, WASHER = 64 }
```

Helpers: `beat_seconds(bpm)`, `phase_index_at(t)`, `phase_start_s(i)`, `phase_bpm(i)`,
`clock_hours(t)`, `clock_string(t)`, `variant_name(color, pattern)`.
Scene/group paths: `SCENE_LAUNDRY_ITEM`, `SCENE_PLAYER`, `GROUP_ITEMS`, `GROUP_BELTS`,
`GROUP_WASHERS`, `GROUP_SHREDDERS`, `GROUP_CHUTE`, `GROUP_PLAYER`.

### `Settings` — `res://scripts/autoload/Settings.gd`
`user_calibration_offset: float` (**seconds**; negative = player hears the beat late),
`calibration_offset_ms()`, `set_calibration_offset_ms(ms)`, `load_settings()`,
`save_settings()`, `calibration_samples: Array[float]`. Signal `settings_changed`.
Persists to `user://settings.cfg`.

### `GameState` — `res://scripts/autoload/GameState.gd`
State: `stability` (0–100), `combo` (1–8), `score`, `phase_index`, `seed_value`,
`rng: RandomNumberGenerator`, `is_ended`, `perfect_count`, `good_count`, `miss_count`,
`rhythm_actions`, `delivered_count`, `washed_count`.

Signals (exact names): `stability_changed(v: float)`, `combo_changed(mult: int)`,
`score_changed(v: int)`, `phase_changed(idx: int)`, `shift_ended(result: Dictionary)`.

API: `reset(seed: int = 0)`, `add_stability(delta: float, reason: String = "")`,
`register_grade(grade: int)`, `add_score(points: int)`, `set_phase(idx: int)`,
`end_shift(victory: bool, reason: String)`, `accuracy() -> float`,
`max_combo -> int`, `reset_rng(seed)`.

Rules: combo starts ×1, `PERFECT +2`, `GOOD +1`, `MISS` resets to ×1, cap ×8. Stability
clamps 0…100; reaching 0 ends the shift as defeat (`reason = "stability"`). `accuracy()`
= `(perfect + good) / max(rhythm_actions, 1)`.

### `BeatConductor` — scene autoload `res://scenes/main/BeatConductor.tscn`
Root script `res://scripts/autoload/BeatConductor.gd`, child `AudioStreamPlayer` named
**`AudioStreamPlayer`**.

```gdscript
signal beat_hit(beat: int)            # global beat index since start(), 0-based
signal measure_hit(measure: int)      # 4/4; every 4th beat, 0-based
signal bpm_changed(bpm: int)

var bpm: int
var is_playing: bool

func start(start_bpm: int = -1) -> void      # emits beat 0 + measure 0 immediately
func stop() -> void
func set_bpm(new_bpm: int) -> void           # new musical clock (new stem) at phase boundary
func get_song_time() -> float                # latency/calibration-compensated seconds
func delta_to_nearest_beat(t: float) -> float # Δt ∈ [0, T/2]
func beat_seconds() -> float
func get_beat_phase() -> float               # 0..1 through current beat
func get_beat_index() -> int
func get_measure_index() -> int
func beats_until_next_measure() -> int
func advance_clock(seconds: float) -> void   # deterministic stepping for tests/sim
```

`get_song_time()` = audio playback position + `AudioServer.get_time_since_last_mix()`
− `AudioServer.get_output_latency()` − `Settings.user_calibration_offset`
− `stem_first_beat_offset`, **when a stream is playing**; otherwise an accumulated clock.
Time is monotonic frame-to-frame (clamp backward jumps to 0). Beats are emitted from
`_process`, never from a Timer. `set_bpm` resets the musical clock to 0 and emits
`bpm_changed`.

### `RhythmEvaluator` — `res://scripts/components/RhythmEvaluator.gd`
Pure static class, `class_name RhythmEvaluator`, `extends RefCounted`.

```gdscript
enum Grade { PERFECT, GOOD, MISS }
static func evaluate(delta_t: float, window_scale: float = 1.0) -> int
static func grade_name(grade: int) -> String
static func force_multiplier(grade: int) -> float      # PERFECT 1.4, else 1.0
static func combo_gain(grade: int) -> int              # 2 / 1 / 0
static func wash_reduction_s(grade: int) -> float      # 3.0 / 1.0 / 0.0
static func resolves_turbulence(grade: int) -> bool    # GOOD or PERFECT
```

Boundaries are inclusive: Δt = 0.065 → PERFECT, 0.130 → GOOD, 0.131 → MISS
(after `window_scale`). **Evaluate rhythm in `_input()`, never `_physics_process()`.**

### `ArtCatalog` — `res://scripts/visual/ArtCatalog.gd`
`static func texture(id: String) -> Texture2D` returns the imported sprite or `null` when
the asset does not exist yet. Every visual must degrade gracefully to a `ColorRect` /
`Polygon2D` placeholder when `null` — art is integrated after M2/M3.

## 4. Scene + node contracts

### Player — `res://scenes/entities/Player.tscn`
Root `CharacterBody2D` (name `Player`), `collision_layer = 2`, `collision_mask = 1`.
Children (names are contract): `Visual` (`Node2D`; sprite must **never rotate**),
`CollisionShape2D` (circle r≈14), `HoldAnchor` (`Marker2D`), `Grabber` (`Node2D`),
`AimIndicator` (`Node2D`). Script `res://scripts/entities/Player.gd`.

```gdscript
signal grabbed(item: Node)
signal thrown(item: Node, grade: int)
signal struck(washer: Node, grade: int)
signal aim_changed(dir: Vector2)

var held_item: Node
var aim_direction: Vector2
var is_dashing: bool
func get_throw_grade() -> int          # evaluates now via BeatConductor + RhythmEvaluator
func grab_or_throw() -> void            # action `grab_throw`
func do_strike() -> void                # action `rhythm_strike`; dash + strike
func get_aim_direction() -> Vector2
```

Movement: accel 2400 px/s², max 340 px/s, friction `v *= pow(1 - 0.12, 60*delta)` when idle.
Aim: mouse position if the mouse moved recently, else right stick (`aim_*` actions).
Throw: `apply_central_impulse(aim * Config.THROW_SPEED * force_multiplier(grade) * mass)`,
gas giant ×0.5 when `MISS`, moon gets a perpendicular `BOOMERANG_ACCEL` when `MISS`.
Held item is steered in `_integrate_forces` to `player.pos + aim * HOLD_DISTANCE`.

### MagneticGrabber — `res://scripts/components/MagneticGrabber.gd`
`func find_target(origin: Vector2, radius: float) -> Node`, `grab(item)`, `drop()`,
`held_item: Node`. One item at a time. Radius `Config.GRAB_RADIUS` (64 px).

### LaundryItem — `res://scenes/entities/LaundryItem.tscn`
Root `RigidBody2D`, `collision_layer = 4`, `collision_mask = 1|4`,
`continuous_cd = CCD_MODE_CAST_SHAPE`, `contact_monitor = true`, `max_contacts_reported = 4`.
Children: `Visual` (`Node2D`), `CollisionShape2D` (circle r≈data.radius), `SquelchPlayer`
(`AudioStreamPlayer2D`, optional). Script `res://scripts/entities/LaundryItem.gd`.

```gdscript
@export var item_id: StringName
@export var color: StringName        # red | blue | yellow
@export var pattern: StringName      # solid | ringed | spotted
var data: ItemData
var is_held: bool
var is_clean: bool

func setup(id: StringName, p_color: StringName, p_pattern: StringName,
           clean: bool = false) -> void
func begin_hold(player: Node) -> void
func end_hold() -> void
func throw_with_impulse(direction: Vector2, grade: int) -> void   # called by Player
func mark_clean() -> void

signal fell_off_belt()
signal delivered()
```

`data/items.tres` is an `ItemDatabase` (`scripts/data/ItemDatabase.gd`) containing five
`ItemData` resources: `rocky`, `sock`, `moon`, `gas_giant`, `galaxy_core`. `ItemData`
fields: `id`, `display_key`, `mass_kg`, `wash_s`, `points`, `slots`, `radius`,
`bounce`, `friction`, `linear_damp`, `belt_speed_scale`, `special` (enum `NONE`,
`BOOMERANG`, `GRAVITY_FIELD`, `SQUELCH`), `sprite_id`, `tint_color`.

### ConveyorBelt — `res://scenes/environment/ConveyorBelt.tscn`
Root `Area2D`, `collision_layer = 8`, `collision_mask = 4`, `monitorable = false`.
Child `CollisionShape2D` (rectangle). Script `scripts/environment/ConveyorBelt.gd`.

```gdscript
@export var belt_id: StringName
@export var flow_direction := Vector2.RIGHT
@export var belt_speed := Config.BELT_SPEED
@export var active := true
signal reversed(new_direction: Vector2)
signal reverse_warning(beats_left: int)
func set_active(v: bool) -> void
func set_flow_direction(dir: Vector2) -> void
func is_active() -> bool
```

Model: for every non-held `RigidBody2D` in `get_overlapping_bodies()`, each physics tick
move `linear_velocity` toward `flow_direction * belt_speed * item.belt_speed_scale` at
`BELT_ACCEL` px/s². Never set velocity instantly (kills collisions). Phase 3 only: after
the 16th, 32nd, … measure give a 4-beat warning then reverse. Logic lives in a pure
`scripts/logic/BeltReversal.gd` (`on_measure(measure, phase) -> {warn, flip, beats_left}`).

### Shredder — `res://scenes/environment/Shredder.tscn`
Root `Area2D`, `collision_layer = 16`, `collision_mask = 4`. On `body_entered` with a
`LaundryItem`: emit `item.fell_off_belt`, `GameState.add_stability(
Config.STABILITY_FELL_OFF_BELT, "shredder")`, then free the item. Scenes placed per
`data/layout.json`. Script `scripts/environment/Shredder.gd`.

### SpawnDirector + pure schedule
`scripts/logic/SpawnSchedule.gd` (pure, static):
`build(phase_table: PhaseTable, seed: int) -> Array[Dictionary]` where each event is
`{ "time": float, "item_id": StringName, "color": StringName, "pattern": StringName,
"phase": int }`, sorted by time, deterministic for a seed.
`scenes`/`scripts/components/SpawnDirector.gd` Node consumes events by game time, spawns
`Config.SCENE_LAUNDRY_ITEM` instances under an `Items` parent, respects
`Config.MAX_ALIVE_ITEMS`, and emits `item_spawned(item)`. It must expose
`spawned_count_by_phase: Array[int]` and `func simulate(duration: float) -> Dictionary`
for headless runs.
`PhaseTable`/`PhaseData` resources in `scripts/data/`; `data/phases.tres` has four entries
matching GDD §2.5 (105/118/130/142 BPM, 3.5/2.4/1.7 s, convoy in phase 4).

## 5. Data resources

`data/layout.json` (art-pixel coordinates, ×4 = world px; canvas 320×180) — **frozen**:

| id | rect (x, y, w, h) | notes |
|---|---|---|
| room | 0, 0, 320, 180 | wall inset 8 |
| belt_north | 84, 10, 152, 16 | flow east |
| belt_south | 84, 154, 152, 16 | flow west |
| belt_west | 10, 60, 16, 80 | dormant; phase 3 active, reverse (south→north) |
| shredder_north | 236, 6, 32, 32 | at north belt east end |
| shredder_south | 44, 146, 32, 32 | at south belt west end |
| shredder_west | 6, 142, 32, 32 | at west belt south end |
| washer_nw | 36, 32, 48, 48 | mouth at (60, 80) |
| washer_ne | 236, 32, 48, 48 | mouth at (260, 80) |
| washer_sw | 36, 96, 48, 48 | mouth at (60, 144) |
| washer_se | 236, 96, 48, 48 | mouth at (260, 144) |
| chute | 144, 74, 32, 32 | centre (160, 90) |
| player_spawn | 160, 128 | world (640, 512) |

Top-left origin, y down, as in Godot. All values are integers in art px. `world = art * 4`.

## 6. Groups and collision

| layer | value | used by |
|---|---|---|
| WORLD | 1 | walls, static geometry |
| PLAYER | 2 | Player body |
| ITEMS | 4 | LaundryItem bodies |
| BELT | 8 | belt Areas |
| SHREDDER | 16 | shredder Areas |
| CHUTE | 32 | delivery chute Area |
| WASHER | 64 | washer bodies / mouths |

Groups: `items`, `belts`, `washers`, `shredders`, `chute`, `player`.

## 7. Test policy

- GUT 9.6.1 (`addons/gut`). Tests `extends GutTest`.
- Unit tests must not require a rendered window. `BeatConductor.advance_clock()` is the
  deterministic stepping hook.
- Every pure rule gets boundary tests (inclusive/exclusive), every seeded system gets a
  fixed-seed test, every new node scene gets a `add_child_autofree(load(...).instantiate())`
  smoke test.
- Integration tests go in `tests/integration/` and must finish in < 60 s.

## 8. Report contract (every session)

End your final message with exactly these headings:

```
## Report
status: done | partial | blocked
branch: <branch>
commits: <n> — <subject list or range>
files: <paths>
verify: <commands + exit codes + 1-line result each>
deviations: <none | list, with reason>
known_issues: <none | list>
next: <what the lead should do/integrate>
```

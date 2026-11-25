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

# Frozen contracts — M4–M6 (screen flow, washers, HUD, tutorial)

These extend the M0–M3 contracts above; nothing in §1–§8 is retracted. Where a name here
differs from an earlier section, **this section wins**.

## 9. Application shell (`scripts/main/App.gd`, root of `Main.tscn`)

`Main.tscn` root is `Node` with `App.gd`. It owns level lifetime, pause, fades and
persistence; screens are signal-only `Control`s that may be missing at runtime (a styled
`FallbackScreens` version is used instead, so `main` always boots).

```gdscript
signal screen_changed(screen: StringName)
var level: Node              # MainLevel or Tutorial instance, or null on the title
var is_paused: bool
var current_screen: StringName   # &"title" | &"shift" | &"tutorial" | &"pause" | &"end"

func show_title(instant: bool = false) -> void
func start_shift(with_tutorial: bool = false) -> void   # async (awaits one frame)
func restart_shift() -> void
func quit_to_menu() -> void
func pause_game() -> void
func resume_game() -> void
```

Rules:
- `start_shift` frees the old level and awaits one frame **before** instancing the new one,
  because `MainLevel._exit_tree()` stops `BeatConductor`; otherwise the new shift's music
  would be killed by the old level.
- Pause sets `get_tree().paused = true`; `App` runs with `PROCESS_MODE_ALWAYS`.
  `pause` action toggles; while paused `ESC` resumes (or closes Options first).
- Boot option: `--autostart=shift|tutorial` in `OS.get_cmdline_user_args()` skips the title
  (screenshots, QA). Default is the title.
- `App` enriches the end result with `rank` and records the best score/rank in `Settings`.

### Screen contracts (signals are connected by name; missing ones are ignored)

| Screen | Scene | Signals | Methods App calls |
|---|---|---|---|
| Title | `scenes/ui/TitleScreen.tscn` | `start_requested`, `tutorial_requested`, `options_requested`, `calibration_requested`, `quit_requested` | `focus_first()` |
| First run | `scenes/ui/FirstRunPrompt.tscn` | `tutorial_selected`, `skip_selected`, `closed` | `focus_first()` |
| Pause | `scenes/ui/PauseOverlay.tscn` | `resume_requested`, `restart_requested`, `options_requested`, `menu_requested` | `focus_first()` |
| Options | `scenes/ui/OptionsScreen.tscn` | `closed`, `calibration_requested` | `open(from_pause)`, `focus_first()` |
| End | `scenes/ui/EndScreen.tscn` | `retry_requested`, `new_seed_requested`, `menu_requested` | `setup(result)` |
| Calibration | `scenes/ui/CalibrationModal.tscn` (existing) | `closed`, `offset_applied` | `open(bpm = -1, skip_countdown = false)` |

`EndScreen.setup(result)` receives the `GameState.shift_ended` dictionary plus `rank`
(`S|A|B|C`) and may read `score_ratio` when `ScoreRules` is present.

## 10. Washers and chute (M4)

### `WasherFSM` — `res://scripts/logic/WasherFSM.gd` (pure)
States `IDLE=0, WASHING=1, TURBULENT=2, DONE=3, BROKEN=4`. Capacity 3 (`galaxy_core`
takes all 3), compatibility via `Compatibility.item_fits`, cycle time `max(item.wash_s)`
floored at `MIN_WASH_TIME_S`, beat reductions applied once at insertion, turbulence at
`turbulence >= 1.0` plus "phase ≥ 3 every 3rd cycle at 50 %", limit
`min(TURBULENCE_TIMEOUT_S, TURBULENCE_TIMEOUT_BEATS × T_beat)`, grade ≥ GOOD resolves.
All time arrives through `tick(dt)`/explicit calls (deterministic tests).

### `WasherAssignments` — `res://scripts/logic/WasherAssignments.gd` (pure)
```gdscript
static func for_phase(phase: int) -> Dictionary
# { "washer_nw": {"requirement": &"red", "locked": false}, ... }
static func requirement_for(phase: int, washer_id: StringName) -> StringName
static func is_locked(phase: int, washer_id: StringName) -> bool
static func coverage_ok(phase: int) -> bool
```
Table per `docs/DECISIONS.md` D026.

### `CosmicWasher` — `scenes/entities/CosmicWasher.tscn`
Root `StaticBody2D` (layer WASHER=64, mask 0) + `Mouth` `Area2D` (mask ITEMS=4).
```gdscript
signal item_loaded(item: Node)
signal item_rejected(item: Node, reason: String)
signal state_changed(old_state: int, new_state: int)
signal cycle_done(items: Array)
signal exploded()
signal turbulence_resolved(grade: int)

func configure(id: StringName, art_rect: Rect2, mouth_art: Vector2, requirement: StringName) -> void
func set_requirement(req: StringName) -> void
func get_requirement() -> StringName
func set_locked(locked: bool) -> void
func is_locked() -> bool
func set_carry_hint(item: Node) -> void       # nullable; drives MATCH/MISMATCH holo
func strike(grade: int) -> bool               # true when it resolved turbulence or started a cycle
func try_accept(item: Node) -> bool
func force_turbulent() -> bool                # tutorial
func force_finish() -> void                   # tutorial / QA
func get_state() -> int
func get_progress() -> float
func get_loaded_items() -> Array
func get_glow_color() -> Color
func get_mouth_world() -> Vector2
```
Side effects owned by the washer: `-12` wrong washer (`wrong_washer_count += 1`), `-25`
explosion (`exploded_count += 1`), `washed_count += 1` per item on completion. Group
`washers` is required (Player's `do_strike` and the HUD reticle use it).

### `DeliveryChute` — `scenes/environment/DeliveryChute.tscn`
```gdscript
signal delivered(item: Node, points: int)
signal dirty_rejected(item: Node)
func configure(art_rect: Rect2, center: Vector2) -> void
func set_carry_hint(clean_item: Node) -> void
func try_deliver(item: Node) -> bool
```
Clean items only: `+3` stability, `delivered_count += 1`,
`score += item.data.points × GameState.combo`, chime, `accept` animation. Dirty items
bounce out with no penalty. Group `chute`.

## 11. HUD and world-space affordances

`scripts/ui/HUD.gd` / `scenes/ui/HUD.tscn` — kept node names `ClockLabel`, `ScoreLabel`,
`ComboLabel`, `GradeLabel`, `PhaseLabel`; public API used by `MainLevel`:
```gdscript
func set_shift_time(t: float) -> void
func set_phase(index: int, bpm: int = -1) -> void
func show_grade(grade: int) -> void
func set_objective(text: String) -> void
func objective_text() -> String
func set_tutorial_mode(enabled: bool) -> void
func set_step(index: int, total: int) -> void
func set_danger(critical: bool) -> void
func flash_reward(points: int) -> void
func clock_text() -> String
```
Layout: two corner plaques `(0,0,312,104)` and `(968,0,312,104)`, mission ribbon
`(400,6,480,28)`. Nothing in the bottom 24 px except world art. The bottom instruction
strip is deleted; controls live on the title screen and in pause.

`scenes/ui/DiegeticLayer.tscn` (`Node2D`, world space, optional, added by `MainLevel`
under `Entities`): pulse ring around Pip, aim reticle with state labels, contextual
prompt, carried-item label, grade pop at the event, turbulence path. It finds nodes by
group and must survive their absence.

## 12. Tutorial

`scenes/main/Tutorial.tscn` root script `scripts/tutorial/TutorialRoot.gd`; children:
`MainLevel` with `mode = "tutorial"`, `UI` (overlay), `Director`.

```gdscript
signal tutorial_completed
signal tutorial_skipped
```
- The root re-emits `MainLevel.tutorial_completed` (which calls
  `Settings.mark_tutorial_completed()`), and emits `tutorial_skipped` after
  `Settings.mark_tutorial_skipped()`.
- Gates: move → grab → throw → beat → match → strike → deliver (docs/UX_BIBLE.md §16.1);
  each gate's success is an event from the real systems (`Player.grabbed`,
  `Player.thrown`, `Player.struck`, chute `delivered`, distance travelled).
- `GameState.stability_protected = true` until gate 7; always restored to false on exit.
- Skip: `pause` action → confirm plaque; per-gate soft skip with `TAB` after
  `Config.TUTORIAL_SOFT_SKIP_S`.
- Persistence: `Settings.tutorial_completed`, `tutorial_skipped`, `first_run_done`.

## 13. Config / Settings / GameState additions (M4–M6)

`Config`: `WASHER_MOUTH_RADIUS_PX`, `WASHER_REPAIR_S`, `CHUTE_ACCEPT_RADIUS_PX`,
`STARTER_ITEM_AT_S`, `STARTER_ITEM_ID/COLOR/PATTERN`, `INPUT_BUFFER_S`, `AIM_SNAP_RAD`,
`AIM_STICKY_RAD`, `AIM_STICKY_RANGE_PX`, `TUTORIAL_SEED`, `TUTORIAL_WINDOW_SCALE`,
`TUTORIAL_SOFT_SKIP_S`, `TUTORIAL_MAX_S`, `HUD_SCALE_DEFAULT`, `HUD_SCALE_OPTIONS`,
`TEXT_SPEED`.

`Settings`: `haptics`, `ui_scale`, `tutorial_completed`, `tutorial_skipped`,
`first_run_done`, `best_score`, `best_rank`; methods `needs_first_run_prompt()`,
`mark_tutorial_completed()`, `mark_tutorial_skipped()`, `mark_first_run_done()`,
`record_result(points, rank)`, `set_haptics(v)`, `set_ui_scale(v)`.

`GameState`: `final_load_delivered`, `feedback_count`, `stability_protected`, signal
`feedback(text, kind)` and `emit_feedback(text, kind)`; `end_shift` results add
`wrong_washer` and `final_load_delivered`.

## 14. UI design system (`scripts/ui/UITheme.gd`)

One font family (Silkscreen Regular/Bold), type scale 56/40/28/20/16/14/12/10, ink
`metal_4`/`metal_2`/`metal_1`, accents `funk_cyan` (act), `funk_magenta` (reward),
`clean_green` (done), `hazard_orange` (danger). Panels are flat 2 px-bordered with one
cyan corner tick; buttons are left-aligned rows with a `▶` caret on focus; every screen
calls `UITheme.wire_audio(root)` once. No gradients, glows, second typeface or default
engine control styles. Screens own no gameplay logic.

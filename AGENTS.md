# AGENTS.md — Cosmic Spin Cycle

*Subtitle: "Lavandería al Borde del Vacío"* · Godot 4.x · 2D pixel-art rhythm-arcade · PC (Windows + Linux)

> **Source of truth:** `docs/GDD.pdf` (Spanish, Juan Camilo Valencia, Univalle). This file turns it into an executable plan.
> If this file and the GDD disagree, **the GDD wins** unless `docs/DECISIONS.md` records an explicit override.
> Companion file: `PROMPTS.md` (kickoff prompts and Open Design prompt library).

---

## 0. How to use this file

There are two parallel tracks that meet at one contract (file names + JSON metadata, see §B6).

| Track | Who | Sections | Touches |
|---|---|---|---|
| **A — Engineering** | Godot/GDScript agent | Part A | `scripts/`, `scenes/`, `data/`, `tests/`, `tools/*.gd` |
| **B — Graphic design** | Pixel-art agent using the **Open Design MCP** | Part B | `art/`, `assets/sprites/`, `tools/*.py` |

Read order for any agent: §0 → §A1–A3 → the section for your track → §A6 (GDD gaps) → your current milestone.
Never edit the other track's folders without a note in `docs/HANDOFF.md`.

---

# PART A — ENGINEERING

## A1. Project snapshot

- **Engine:** Godot 4.x stable (target ≥ 4.4; run `godot --version` and record it in `docs/DECISIONS.md`). GDScript with static typing. No Godot 3 APIs.
- **Genre:** chaotic arcade management + active rhythm mechanics + 2D rigid-body physics. Single player, single 8-minute level (480 s) in 4 continuous phases.
- **Viewport / world:** 1280×720 world pixels, top-down 2.5D. Target 60 FPS, physics tick 60 Hz.
- **Input:** keyboard+mouse and gamepad (XInput/SDL). **Platforms:** Windows + Linux native. Min spec: dual-core 2 GHz, 4 GB RAM, OpenGL 3.3 / Vulkan 1.0, audio output latency < 50 ms.
- **Art:** 2D pixel art, 1 art pixel = 4 world pixels (`ART_SCALE = 4`, i.e. a 320×180 art canvas). See Part B.
- **Monetization:** none in code (premium, no ads, no IAP, no telemetry).
- **Language policy:** code, comments, commit messages and docs in **English**; player-facing strings in **Spanish** through translation keys (`tr("HUD_STABILITY")`) with `es` as the default locale and `en` stubbed for later.

## A2. Working agreements (read before coding)

1. **Small, verifiable steps.** One milestone task → implement → test → run headless smoke → commit. Commit message format: `M3: add ConveyorBelt Area2D force application`.
2. **No magic numbers.** Every number from the GDD lives in `scripts/autoload/Config.gd` or `data/*.tres` (see §A5). Tests reference the same constants.
3. **Don't invent mechanics.** If the GDD is silent or contradicts itself, use the *proposed default* in §A6, expose it as a config flag, and log it in `docs/DECISIONS.md` (date, GDD ref, choice, how to flip it). Escalate the ★ items to the human.
4. **GDD §8.2 open questions are toggles, not decisions** (`PHASE_TRANSITION_MODE`, `MISS_WASH_PENALTY_S`). Implement both options.
5. **Pure logic stays testable.** Rhythm grading, stability math, phase/clock mapping, washer FSM, spawn scheduling and compatibility rules are plain scripts with no scene dependencies and have unit tests.
6. **Determinism.** One seeded RNG (`GameState.rng`) for spawns; the seed is shown on the end screen and settable in debug builds.
7. **Evaluate rhythm in `_input()`**, never in `_physics_process()` (60 Hz quantization is 16.7 ms; the PERFECT window is ±65 ms).
8. **Ask before adding dependencies** (addons, native libs). Allowed without asking: the chosen test framework (gdUnit4 *or* GUT — pick one, record it), `gdtoolkit` (gdlint/gdformat) for CI.
9. **Debug cheats (F1–F4)** exist only when `OS.is_debug_build()`.
10. **Progress log.** After each milestone update `docs/PROGRESS.md` (done / next / blockers / measured latency numbers).

## A3. Glossary (ES → EN identifiers)

| GDD term | Identifier |
|---|---|
| Estabilidad del Tejido Cósmico | `stability` (0–100) |
| Lavadora / Cinta / Ducto de Entrega | `CosmicWasher` / `ConveyorBelt` / `DeliveryChute` |
| Calcetín Estelar, Planeta Rocoso, Luna Creciente, Gigante Gaseoso, Núcleo de Galaxia | `sock`, `rocky`, `moon`, `gas_giant`, `galaxy_core` |
| Color: Rojo Carmesí / Azul Nebulosa / Amarillo Solar | `RED` / `BLUE` / `YELLOW` |
| Patrón: Liso / Anillado / Moteado | `SOLID` / `RINGED` / `SPOTTED` |
| PERFECTO / BIEN / FUERA DE RITMO | `PERFECT` / `GOOD` / `MISS` |
| Golpe Rítmico | `rhythm_strike` |
| Centrifugado Turbulento | `TURBULENT` |
| Carga Final | `final_load` |
| Colapso de Singularidad | `BROKEN` washer state (see §A6 #2) |
| Anillo de Pulso | `PulseRing` |

## A4. Repository layout (GDD §7.2, extended)

```
res://
├─ project.godot
├─ assets/
│  ├─ audio/            # stems 105/118/130/142 BPM + SFX
│  ├─ sprites/          # SHIPPED pixel art: <id>.png + <id>.json  (Track B output)
│  ├─ spriteframes/     # generated SpriteFrames .tres (from the JSON)
│  └─ fonts/
├─ scenes/
│  ├─ main/             # Main.tscn, MainLevel.tscn
│  ├─ entities/         # Player.tscn, LaundryItem.tscn, CosmicWasher.tscn
│  ├─ environment/      # ConveyorBelt.tscn, DeliveryChute.tscn, Shredder.tscn
│  └─ ui/               # HUD.tscn, TitleScreen.tscn, CalibrationModal.tscn, EndScreen.tscn, PauseOverlay.tscn
├─ scripts/
│  ├─ autoload/         # Config.gd, BeatConductor (scene+script), GameState.gd, Settings.gd
│  ├─ components/       # RhythmEvaluator.gd, MagneticGrabber.gd, SpawnDirector.gd, ShiftManager.gd
│  └─ logic/            # pure logic: StabilityRules.gd, WasherFSM.gd, Compatibility.gd, ScoreRules.gd
├─ data/                # phases.tres, items.tres, washer_assignments.tres, layout.json, balance.tres
├─ tests/               # unit + integration tests
├─ tools/               # make_placeholders.py, balance_sim.gd, build_spriteframes.gd, art tools (Track B)
├─ art/                 # Track B source (see §B6)
└─ docs/                # GDD.pdf, DECISIONS.md, PROGRESS.md, HANDOFF.md, CALIBRATION.md
```

## A5. Constants extracted from the GDD

Put these in `Config.gd` (and mirror in `data/balance.tres` where tunable). Section refs are GDD sections.

```gdscript
# --- Shift & clock (§2.2, §2.5)
const SHIFT_DURATION_S := 480.0           # 8 min real time
const GAME_HOURS := 6.0                   # 00:00 → 06:00
const SECONDS_PER_GAME_HOUR := 80.0
const PHASE_START_S := [0.0, 120.0, 270.0, 420.0]   # clock 00:00, 01:30, 03:22.5, 05:15
const PHASE_BPM := [105, 118, 130, 142]
const SPAWN_INTERVAL_S := [3.5, 2.4, 1.7, 0.0]      # phase 4 = scripted convoy
const FINAL_LOAD_HEAVY_COUNT := 12
const FINAL_LOAD_CORE_COUNT := 1

# --- Player (§3.2, §4.1)
const PLAYER_ACCEL := 2400.0              # px/s²
const PLAYER_MAX_SPEED := 340.0           # px/s
const PLAYER_FRICTION := 0.12             # see §A6 #17 for interpretation
const HOLD_DISTANCE := 48.0
const GRAB_RADIUS := 64.0
const DASH_DISTANCE := 120.0

# --- Rhythm (§5.1)
const WINDOW_PERFECT_S := 0.065
const WINDOW_GOOD_S := 0.130
const PERFECT_FORCE_BONUS := 0.40
const COMBO_GAIN := {"PERFECT": 2, "GOOD": 1, "MISS": 0}   # MISS resets to x1
const COMBO_MIN := 1
const COMBO_MAX := 8
const WASH_REDUCTION_S := {"PERFECT": 3.0, "GOOD": 1.0, "MISS": 0.0}
const MISS_TURBULENCE_GAIN := 0.15        # +15 % on receiving washer

# --- Washers (§5.2)
const WASHER_COUNT := 4
const WASHER_CAPACITY := 3                # slots; gas_giant uses 2
const WASH_BASE_S := 8.0                  # see §A6 #3
const TURBULENCE_AT_PROGRESS := 0.50
const TURBULENCE_TIMEOUT_S := 5.0
const TURBULENCE_TIMEOUT_BEATS := 8       # effective limit = min(5.0 s, 8 beats)

# --- Stability (§2.4, §3.1)
const STABILITY_START := 100.0
const STABILITY_FELL_OFF_BELT := -8.0
const STABILITY_WRONG_WASHER := -12.0
const STABILITY_EXPLOSION := -25.0
const STABILITY_CHUTE_DELIVERY := 3.0

# --- Belts (§5.3)
const BELT_REVERSE_EVERY_MEASURES := 16   # Phase 3 only
const BELT_REVERSE_WARNING_BEATS := 4

# --- Misc
const ART_SCALE := 4
const CALIBRATION_DURATION_S := 10.0
const RESTART_MAX_S := 0.5
```

**Items (GDD §6)** → `data/items.tres`

| id | mass kg | wash s | points | slots | special physics |
|---|---|---|---|---|---|
| rocky | 1.0 | 6.0 | 100 | 1 | stable linear trajectory, bounce e = 0.4 |
| sock | 0.3 | 4.0 | 150 | 1 | very light/fast on belts; squelch SFX on grab; if dropped un-thrown it slides randomly |
| moon | 0.8 | 7.0 | 200 | 1 | curved (light boomerang) trajectory when thrown **off-beat** |
| gas_giant | 2.2 | 10.0 | 350 | **2** | e = 0.85; needs an **on-beat** throw to reach full speed |
| galaxy_core | 3.0 | 12.0 | 1000 | see §A6 #10 | unique (Final Load); weak gravity field attracts nearby socks while carried |

**Beat math (derived, use in tests and balance notes)**

`T_beat = 60 / BPM` → 0.571 s, 0.508 s, 0.462 s, 0.423 s. `Δt = min(t mod T, T − (t mod T))`.
Because windows are fixed in seconds, a random press lands on-beat (PERFECT+GOOD) **45.5 % of the time at 105 BPM and 61.5 % at 142 BPM** — rhythm gets *easier* in later phases. Keep windows configurable per phase (`WINDOW_SCALE_BY_PHASE`, default 1.0) so balance can compensate.

## A6. GDD gaps, contradictions and proposed defaults

Implement the **Proposed default** behind a flag, log it in `DECISIONS.md`. ★ = ask the human early.

| # | GDD ref | Problem | Proposed default |
|---|---|---|---|
| 1 ★ | §1.7 vs §2.5 | Key-moment timeline contradicts the phase table (BPM 110→125 at 3:30 vs 105/118/130/142; south belt at 3:30 vs 2:00; ringed planet at 0:30 although Phase 1 is solid-only; alarm at 7:00 vs opening bell at 8:00). | §2.5 table is authoritative; §1.7 is narrative. Keep phases data-driven (`data/phases.tres`). |
| 2 | §2.3 | "Colapso de Singularidad" is not in the washer FSM. | Maps to `BROKEN`. |
| 3 ★ | §5.2 vs §6 | `t_wash = 8.0 s` base vs per-item wash times 4–12 s. | `cycle_time = max(item.wash_s)` over the load; `WASH_BASE_S` is only a fallback. Reductions never take remaining time below 2.0 s. |
| 4 | §5.2 | "Cargada o activada": what starts a cycle? | Starts when slots are full, **or** when the player lands a Rhythm Strike on a washer holding ≥ 1 item. No auto-timeout. |
| 5 | §5.2 | "5.0 s or 8 beats": at 105–142 BPM 8 beats = 3.4–4.6 s, so 5.0 s never fires. | Limit = `min(5.0 s, 8 × T_beat)`. |
| 6 | §5.1/5.2 | How does "+15 % turbulence accumulation" relate to `TURBULENT`? | Washer has `turbulence` 0–1. `≥ 1.0` → `TURBULENT`. Additionally, in phases ≥ 3 every 3rd cycle of a washer turns turbulent at 50 % progress. |
| 7 | §5.2 | Must the stabilizing strike be on-beat? | Grade ≥ `GOOD` resolves it. A `MISS` strike doesn't resolve it (and resets combo). |
| 8 | §5.1 | When do the 3 s / 1 s wash reductions apply? | On insertion of the thrown item, to the receiving washer's remaining time, once per throw. If not started yet, stored as a bonus for the first cycle. |
| 9 | §1.7 | "Supernova Spin" appears only in narrative. | Flag `ENABLE_SUPERNOVA` (default **on**, built in M9): 3 consecutive throws ≥ `GOOD` instantly finish every `WASHING` washer. 20 s cooldown. |
| 10 ★ | §2.2/§2.5/§6 | Spotted/Yellow introduction phase, per-phase washer assignments, Galaxy Core compatibility/slots are undefined. | Phase 1: Red/Blue + Solid. Phase 2: + Ringed. Phase 3: + Yellow + Spotted. Washer assignments are data (`washer_assignments.tres`) changed only at phase boundaries after a 4-beat warning. Core = wildcard (fits any washer), needs an empty washer, uses all 3 slots. |
| 11 ★ | §2.3/§2.4 | Does "processed" mean washed or delivered? | **Delivered clean to the chute** before 480 s. Flag `FINAL_LOAD_COUNTS_DONE_IN_WASHER` (default off) relaxes it. |
| 12 | §3.1 | Belt flow directions, spawn points, shredder and washer coordinates are unspecified. | `data/layout.json` in art-pixel coords. Default: North flows W→E, South E→W, West N→S (reversed in Phase 3). Shredder at each belt end. Authored jointly with Track B (§B8 Stage 2). |
| 13 | §4.3 | Score formula and S/A/B/C thresholds missing. | `score += item.points × combo_multiplier` at chute delivery. Rank by `score / max_possible` and accuracy: S ≥ 0.85 & ≥ 90 % · A ≥ 0.65 · B ≥ 0.40 · else C (defeat is always C). Tune in M9. |
| 14 | §5.1 | Does the combo decay? | No decay; only `MISS` resets to ×1; cap ×8. |
| 15 | §2.5 | Final Load "12 heavy objects" composition. | 4 gas giants + 4 moons + 4 rocky planets + 1 core, spawned over the final 60 s. **Verify winnable with `tools/balance_sim.gd`.** |
| 16 | §7.1 vs §7.2 | BeatConductor is a scene in 7.1 but an autoload script in 7.2. | Autoload the **scene** `BeatConductor.tscn` whose root script is `BeatConductor.gd`. |
| 17 | §3.2 | Friction "μ = 0.12 linear" has no units. | Per-frame-at-60 Hz velocity decay: `v *= pow(1.0 - μ, 60.0 * delta)` when no input (stops from full speed in ≈ 0.5 s). Tunable. |

## A7. Architecture

```
Autoloads: Config · Settings (user://settings.cfg) · GameState · BeatConductor(.tscn)

Main (Node)
├─ MainLevel (Node2D)
│  ├─ ShiftManager        # clock, phase changes, Final Load, win/lose evaluation
│  ├─ SpawnDirector       # phases.tres → spawn queue, seeded RNG, convoy
│  ├─ Camera2D            # rhythm shake (toggle: reduce_motion)
│  ├─ Environment         # floor, ConveyorBelt ×3, Shredder ×3, DeliveryChute
│  ├─ Washers             # CosmicWasher ×4 (StaticBody2D + FSM)
│  ├─ Items               # LaundryItem (RigidBody2D) instances
│  └─ Player              # CharacterBody2D + MagneticGrabber
└─ UI (CanvasLayer)       # HUD, Pause, Calibration, EndScreen
```

**Signal contract** (decouple everything through these):

| Emitter | Signals |
|---|---|
| `BeatConductor` | `beat_hit(beat:int)`, `measure_hit(measure:int)`, `bpm_changed(bpm:int)` |
| `GameState` | `stability_changed(v)`, `combo_changed(mult)`, `score_changed(v)`, `phase_changed(idx)`, `shift_ended(result:Dictionary)` |
| `Player` | `grabbed(item)`, `thrown(item, grade)`, `struck(washer, grade)` |
| `CosmicWasher` | `item_loaded(item)`, `state_changed(old,new)`, `cycle_done(items)`, `exploded()` |
| `LaundryItem` | `fell_off_belt()`, `delivered()` |

**BeatConductor** (GDD §7.1):

```gdscript
func get_song_time() -> float:
    var t := _player.get_playback_position() + AudioServer.get_time_since_last_mix()
    t -= AudioServer.get_output_latency()
    t -= Settings.user_calibration_offset       # seconds, from the 10 s wizard
    t -= _stem_first_beat_offset                # stems may have leading silence
    return t

func delta_to_nearest_beat(t: float) -> float:   # Δt (§5.1)
    var T := 60.0 / _bpm
    var m := fposmod(t, T)
    return minf(m, T - m)
```

Rules: emit beats from `_process`, derived from `get_song_time()` (not from a Timer); handle loop wrap and `playing == false`; keep the time monotonic frame-to-frame (clamp backward jumps < 5 ms); on phase change, switch stem on a **measure boundary** (`PHASE_TRANSITION_MODE = HARD_CUT | DRUM_BRIDGE`, GDD §8.2-1). `RhythmEvaluator.evaluate(delta_t) -> Grade` is a pure static function.

**LaundryItem (RigidBody2D)**: `is_held` flag; while held, `_integrate_forces(state)` steers the body to `player.pos + aim_dir × 48` with a spring/PID and inherits part of the player's velocity; on release apply impulse `J = base_impulse × grade_multiplier` (PERFECT ×1.4) along the aim vector. On-beat throws: temporary collision-mask change (ignore lighter items) + magnetic assist (steer velocity toward the nearest *compatible* washer mouth). Moon off-beat: add perpendicular acceleration for the boomerang curve. Gas giant off-beat: speed × 0.5.
**Sprites never rotate with the body** (see §B3): keep the `Sprite2D`/`AnimatedSprite2D` upright (`top_level = true` or counter-rotate) so pixels stay crisp and the light stays top-left.

**ConveyorBelt (Area2D)**: in `_physics_process`, for each `RigidBody2D` in `get_overlapping_bodies()` where `not is_held`, apply `v_belt` (velocity override or force — pick one, document it). Phase 3: reverse vector every 16 measures after a 4-beat visual+audio warning. Items leaving the belt end enter the Shredder: −8 % stability + item freed.

**CosmicWasher (StaticBody2D)**: pure FSM in `scripts/logic/WasherFSM.gd` (`IDLE → WASHING → (TURBULENT) → DONE`, any → `BROKEN`), node only renders and forwards events. `AnimationPlayer` is synced to the beat for squash-and-stretch. Compatibility rule in `Compatibility.gd`: item matches `COLOR` washer by color, `PATTERN` washer by pattern; core is a wildcard.

## A8. Milestones

Each milestone ends with: tests green, headless smoke run OK, `docs/PROGRESS.md` updated, one commit/PR.

**M0 — Bootstrap**
- Godot project, folders (§A4), `project.godot`: 1280×720, `stretch/mode=canvas_items`, aspect keep, **default texture filter = Nearest**, 60 Hz physics, Input Map (`move_*`, `aim_*`, `grab_throw`, `rhythm_strike`, `pause`, `debug_f1..f4`).
- Autoload stubs, test framework + one trivial test, `gdlint`/`gdformat` config, GitHub Actions (headless tests + lint), `.gitignore` (`.godot/`, builds), `.gitattributes` (binary png/ogg/wav).
- `tools/make_placeholders.py`: generates **placeholder PNG + JSON for every Tier A asset** in §B5 at exact sizes/frames (flat palette shapes), so gameplay never blocks on art.
- **Done when:** project opens, `godot --headless --quit` exits 0, CI green, placeholders exist.

**M1 — Beat engine & calibration**
- `tools/make_click_track.py` (stdlib `wave` + numpy optional) → metronome stems at 105/118/130/142 BPM with accented downbeat; known `first_beat_offset`.
- `BeatConductor`, `RhythmEvaluator`, debug overlay (Δt in ms, grade, current beat, window bar), measure counter.
- Calibration wizard (10 s tap-along, median offset → `Settings`). Document the test protocol in `docs/CALIBRATION.md`.
- **Done when:** unit tests cover boundaries (Δt = 0.065 → PERFECT, 0.130 → GOOD, 0.131 → MISS, wrap at T/2), 4 BPMs, calibration offset; manual check on one Windows and one Linux machine recorded in `PROGRESS.md`.

**M2 — Player & item physics (greybox)**
- `Player` (accel/vmax/friction, 8-dir, gamepad), `MagneticGrabber` (grab ≤ 64 px, hold at 48 px, one item), throw impulse, dash 120 px, aim via cursor/right stick.
- `LaundryItem` with all five item behaviors (§A5) driven by `items.tres`.
- **Done when:** items feel distinct (mass/bounce/boomerang), you can pick/throw 20 items with no tunneling or stuck bodies, 60 FPS with 40 bodies.

**M3 — Belts, spawning, phases**
- `ConveyorBelt`, `Shredder`, `SpawnDirector` reading `phases.tres` (belts active, intervals, allowed colors/patterns), phase table of GDD §2.5, belt reversal in Phase 3.
- **Done when:** a headless 480 s run spawns the expected counts per phase (±1), belt reversal fires every 16 measures with a 4-beat warning, spawns are reproducible per seed.

**M4 — Washers**
- `WasherFSM` + `CosmicWasher` + holograms (requirement icon), capacity/slots, compatibility, cycle start rules, beat-based reductions, turbulence + strike resolution + explosion (ejects items, −25 %), DONE ejection of clean items, `DeliveryChute`.
- **Done when:** FSM tests cover every transition and every §A6 default; wrong-washer penalty −12 %; chute +3 %.

**M5 — Shift flow & rules**
- `ShiftManager` (clock = `t / 80 s` per hour), phase changes, Final Load convoy (12 + core), win/lose conditions (§2.3/2.4), `GameState` (stability, score, combo ×1–×8), Supernova (behind flag), cheats F1–F4.
- **Done when:** scripted bot runs prove each win and each lose path; clock shows 00:00→06:00 exactly across 480 s; F1 jumps +60 s.

**M6 — UI & screen flow**
- Title (Start Shift / Audio Calibration / Options), HUD (top bar: clock, stability bar, combo; diegetic `PulseRing` contracting each quarter note; washer holograms/progress ring/vibration meter), pause overlay (ESC), end screen (washed, accuracy %, max combo, rank S/A/B/C), **instant restart < 0.5 s**.
- Options: volume, calibration, fullscreen, reduce screen shake, key rebinding (stretch).
- **Done when:** a full playthrough is possible title → end → restart using placeholders only.

**M7 — Art integration (needs Track B Gate G3)**
- `tools/build_spriteframes.gd` (headless EditorScript): reads `assets/sprites/*.json` → writes `assets/spriteframes/*.tres`.
- Replace placeholders, pixel-clean rendering checks (no rotation, no sub-pixel), shaders for `PulseRing`, hit bursts, screen shake.
- **Done when:** screenshot comparison at 1280×720 shows crisp integer-scaled pixels, no frame-to-frame shimmer.

**M8 — Audio**
- Final stems per BPM (or placeholder if music isn't ready), phase transitions per `PHASE_TRANSITION_MODE`, SFX: squelch, belt hum, washer drum synced to beat, microwave bell, explosion, UI.
- **Done when:** both transition modes selectable from the debug menu; audio mix has no clipping at 4 simultaneous washers.

**M9 — Balance, polish, release**
- `tools/balance_sim.gd` (bot with configurable skill: % on-beat, reaction delay) proves the Final Load is winnable at "average" skill and not trivial at "perfect"; tune rank thresholds, windows by phase, spawn rates.
- Playtest the two open questions (§8.2), perf pass, export presets Windows + Linux, README/itch page text.
- **Done when:** release candidate builds for both OSes, 60 FPS on min-spec target, known issues listed.

## A9. Testing

- **Unit (headless):** `RhythmEvaluator`, `delta_to_nearest_beat`, clock/phase mapping, `StabilityRules`, `ScoreRules`, `Compatibility`, `WasherFSM`, spawn determinism by seed.
- **Integration (headless):** 480 s simulated run with an `AutoBot` (all throws PERFECT = same as F4 Auto-Beat) must win; a bot that never acts must lose by stability or Final Load; assert the stability ledger.
- **Manual:** audio-latency protocol (Windows + Linux, wired + Bluetooth headphones), gamepad feel, color-blind readability of washers (color **and** glyph), reduce-motion setting.

## A10. Definition of done (any task)

Typed GDScript with no warnings · `gdlint`/`gdformat` clean · constants from `Config` · tests added/updated and green · headless smoke passes · `DECISIONS.md`/`PROGRESS.md` updated · no GDD number hardcoded in a scene or script.

## A11. Risks

| Risk | Mitigation |
|---|---|
| Audio latency differs between Windows/Linux (GDD §1.2 blocker) | Calibration wizard + `get_output_latency()` + per-stem offset + evaluate in `_input()` + documented measurements. |
| Beat windows are fixed in seconds → rhythm gets easier at high BPM (§A5) | `WINDOW_SCALE_BY_PHASE`, tune in M9. |
| Pixel art + RigidBody rotation → mixels/shimmer | Sprites don't rotate with bodies (§A7), art scale ×4 only, Nearest filter. |
| Final Load unwinnable/trivial | `balance_sim.gd`, ranked thresholds, flagged defaults in §A6. |
| Open Design output isn't pixel-exact (Track B) | OD is used for direction/layout/reference/preview; pixels come from the scripted pipeline (§B7). |

---

# PART B — GRAPHIC DESIGN & PIXEL-ART PIPELINE (Open Design MCP)

## B1. Role, scope and the contract with Track A

You are the **art agent**. You produce every 2D asset of the game as **crisp, palette-locked pixel art**, plus the art bible and previews. You deliver files in `assets/sprites/` that Track A loads *without code changes*.

**Contract:** filenames, frame sizes, animation names and the JSON schema in §B6 are frozen after Gate G1. Track A's `make_placeholders.py` creates placeholders with the same names; you overwrite them 1:1.

## B2. Art direction (from GDD §1.8) and style rules

- **Direction:** stylized 2D, high contrast, *Cosmic Retro-Futurism*. Deep-space background `#0B0C10` so bright silhouettes, color codes and rhythm indicators read instantly.
- **Readability first:** each item must be identifiable by **silhouette at 1× (16 px)**, then by color, then by pattern. Color is never the only signal — washers and items carry a **shape glyph** too (proposal: Red = triangle, Blue = circle, Yellow = square; patterns shown by their pattern icon).
- **Tone:** funny, absurd, zero violence (ESRB E / PEGI 3). Washers are chunky industrial "black-hole" machines; Pip is a small interdimensional janitor with **gravity gloves**.

**Pixel rules (non-negotiable):**
1. Palette only (§B4): no color outside the 30 listed; transparent background (alpha 0 or 255 — **no semi-transparent pixels**).
2. No anti-aliasing, no blur, no glow halos, no sub-pixel offsets, no scaling or rotating baked art (all rotation, if any, is multiples of 90° and only for belt tiles).
3. **Light from top-left**, always. Items are upright and never rotate in-game, so lighting stays consistent.
4. Shading: 3 tones + 1 highlight per object using the 5-step ramps; hue-shift shadows toward `space_haze` blue/purple, highlights toward warmer tones.
5. **Selective outline (sel-out)**: 1 px outline using the object's own darkest ramp color (`*_0`), never pure black.
6. Dithering only as a 2×2 checker, only on large surfaces (washer panels, gas-giant bands); never on small sprites.
7. One pixel scale: **1 art px = 4 world px**. No mixed-resolution ("mixel") art.
8. Max 5 ramp colors + 2 accents per sprite.

## B3. Technical spec

| Item | Value |
|---|---|
| Art canvas | 320×180 art px (= 1280×720 world px at ×4) |
| Scale in Godot | `Sprite2D/AnimatedSprite2D.scale = Vector2(4,4)`, `texture_filter = NEAREST` |
| Project default filter | Nearest (set in M0) |
| PNG | RGBA 8-bit, no color profile, no interlace, lossless import, mipmaps off |
| Frame layout | horizontal strips, one row per animation, 0 px padding, uniform frame size per sheet |
| Pivot | declared per sheet in JSON (feet-center for characters, center for items/FX) |
| Determinism | running the build twice yields byte-identical PNGs |

## B4. Palette (30 colors — `art/palette.json`, `.gpl`, `palette.png`)

| Role | Name → Hex |
|---|---|
| Space | `space_void #0B0C10` (GDD bg) · `space_deep #14172A` · `space_mid #1F2340` · `space_haze #2E3460` |
| Metal | `metal_0 #4A5278` · `metal_1 #6B7599` · `metal_2 #9AA4C4` · `metal_3 #CDD3E8` · `metal_4 #F4F6FC` |
| Crimson (Rojo Carmesí) | `red_0 #3D0A1C` · `red_1 #7A1230` · `red_2 #C41E3A` · `red_3 #F0526B` · `red_4 #FF9AA8` |
| Nebula (Azul Nebulosa) | `blue_0 #0E1A4D` · `blue_1 #1E3A9A` · `blue_2 #3B6DF0` · `blue_3 #7FA6FF` · `blue_4 #C3D8FF` |
| Solar (Amarillo Solar) | `yel_0 #5C3A00` · `yel_1 #B07A00` · `yel_2 #FFC21A` · `yel_3 #FFE066` · `yel_4 #FFF5B8` |
| Accents | `funk_cyan #19E3D1` · `funk_teal #0B7F86` · `funk_magenta #E040FB` · `funk_plum #7A1F8F` · `clean_green #5CFF8A` · `hazard_orange #FF7A1A` |

Usage: `*_2` is the **body fill** of an item (must keep ≥ 3:1 contrast against `#0B0C10`; `red_2` is ≈ 3.3:1 — the linter checks this). `funk_cyan` = Pip + beat/rhythm UI. `funk_magenta` = PERFECT feedback. `clean_green` = DONE/clean. `hazard_orange` = TURBULENT/alerts. Items share **one authored shape** and are recolored by swapping ramps (`red_*`, `blue_*`, `yel_*`), so palette-slot discipline matters.

If a color must change, change it in `palette.json` **and** announce it in `docs/HANDOFF.md`.

## B5. Asset manifest

IDs are final. Sizes in **art px**. `Tier A` blocks M7; `Tier B` is polish.

### Tier A

| id | size | animations (frames) | notes |
|---|---|---|---|
| `char_pip` | 24×24 | dirs `down`,`side`,`up` × `idle`(2) `run`(4) `throw`(2) `strike`(2) | `side` is mirrored in-engine for left. Gravity gloves glow `funk_cyan`. Pivot = feet. |
| `item_rocky` | 16×16 | 9 variants `{red,blue,yellow}_{solid,ringed,spotted}` (2 frames each: idle shimmer) | recolor + pattern masks from one shape |
| `item_sock` | 16×16 | same 9 variants (2: wiggle) | silhouette = clearly a sock |
| `item_moon` | 16×16 | same 9 variants (1) | crescent, upright |
| `item_gas` | 24×24 | same 9 variants (2) | banded sphere; 2-slot visual weight |
| `item_core` | 32×32 | `idle`(4 swirl) | multicolor, wildcard; unique |
| `item_grime` | 16×16 / 24×24 / 32×32 | one overlay per size (1) | "dirty" stains; hidden when clean |
| `fx_clean_sparkle` | 8×8 | `play`(4) | shown on clean items |
| `mach_washer` | 48×48 | `idle`(2) `load_flash`(3) `washing`(4) `turbulent`(4) `done`(2) `broken`(2) | black-hole porthole drum, dials, hazard stripe; pivot bottom-center |
| `ui_holo_icons` | 12×12 | 7 single frames: `red`,`blue`,`yellow`,`solid`,`ringed`,`spotted`,`wild` | glyph + color for washer requirement holograms |
| `env_belt` | 16×16 | `scroll`(4) | seamless in 90° rotations; magnetic rails |
| `env_belt_cap` | 16×16 | `start`(1) | portal/dispenser end |
| `env_shredder` | 32×32 | `idle`(3) | vacuum shredder at belt ends |
| `env_chute` | 32×32 | `closed`(1) `opening`(3) `open`(2) `accept`(3) | pneumatic central hatch |
| `env_floor` | 16×16 | 3 variants (1) | subtle, low contrast so items pop |
| `env_room` | 320×180 | `bg`(1) | composed room: walls, panels, portholes; no belts/washers baked in |
| `fx_burst_perfect` | 16×16 | `play`(4) | `funk_magenta` |
| `fx_burst_good` | 12×12 | `play`(3) | `funk_cyan` |
| `fx_miss_puff` | 12×12 | `play`(3) | `metal_*` smoke puff |
| `fx_explosion` | 32×32 | `play`(6) | washer explosion, `hazard_orange` + `yel_*` |
| `fx_bubbles` | 8×8 | `play`(3) | static bubbles on clean items |
| `ui_panel` | 24×24 | 9-slice (corner 8 px) | HUD panel |
| `ui_bar_stability` | 96×10 + 1×6 fill | frame + fill tile | segmented; `clean_green`→`hazard_orange` thresholds |
| `ui_icons` | 8×8 | `clock`,`stability`,`combo` | |
| `ui_reticle` | 16×16 | `aim`(1) | aim crosshair |
| `ui_logo` | 160×48 | `logo`(1) | "COSMIC SPIN CYCLE" |

### Tier B

`char_pip_hold` (`hold_idle` 2, `hold_run` 4) · `char_pip_dash` smear (3) · `char_pip_pose` (`victory` 4, `defeat` 4) · `env_stars` 320×180 twinkle (4) · `env_porthole` (2) · `fx_supernova` 48×48 (8) · `env_belt_warning` chevrons (4) · `mach_washer_oos` ("out of order" overlay, 2) · `fx_magnet_dots` (3).

### Animation timing defaults

idle 3–4 fps · run 10 · throw/strike 18 · belt scroll 8 · washing 8 · turbulent 14 · explosion 12 · sparkle 8. The **pulse ring** (beat indicator), washer **progress ring**, **vibration meter** and **magnet trail** are procedural in Godot — do **not** draw them.

## B6. Files, naming, JSON schema

```
art/
├─ DESIGN.md          # art bible (source of truth; registered in Open Design)
├─ TOOLS.md           # MCP tool names discovered at runtime (see §B7)
├─ PROVENANCE.md      # every AI-assisted artifact: tool, prompt, date, license note
├─ palette.json  palette.gpl  palette.png
├─ src/               # one Python builder per asset family (uses tools/pxlib.py)
├─ concepts/          # Open Design references (NEVER shipped)
├─ od/                # Open Design exports (HTML boards, viewer)
└─ preview/           # generated ×8 previews + contact sheets
assets/sprites/       # SHIPPED: <id>.png + <id>.json
tools/                # pxlib.py  make_art.py  lint_sprites.py  preview.py  pixelize.py
```

`<id>.json`:

```json
{
  "id": "mach_washer",
  "frame_size": [48, 48],
  "scale": 4,
  "pivot": [24, 46],
  "animations": {
    "idle":      {"row": 0, "frames": 2, "fps": 3,  "loop": true},
    "load_flash":{"row": 1, "frames": 3, "fps": 18, "loop": false},
    "washing":   {"row": 2, "frames": 4, "fps": 8,  "loop": true},
    "turbulent": {"row": 3, "frames": 4, "fps": 14, "loop": true},
    "done":      {"row": 4, "frames": 2, "fps": 6,  "loop": true},
    "broken":    {"row": 5, "frames": 2, "fps": 4,  "loop": true}
  },
  "tier": "A",
  "source": "art/src/mach_washer.py"
}
```

Item sheets use variant names as animations (`red_solid`, `blue_ringed`, …). `char_pip` animations are `idle_down`, `idle_side`, `idle_up`, `run_down`, … Naming: `snake_case`, prefixes `char_ item_ mach_ env_ fx_ ui_`.

## B7. Toolchain

### B7.1 Open Design MCP — what it is and what it's for

Open Design (`github.com/nexu-io/open-design`) is an open-source (Apache-2.0), local-first design workspace: a local daemon plus a **stdio MCP server** that coding agents call. As of the README checked on 2026-11-24: it produces HTML prototypes, decks, images (needs a configured image provider), motion; it has 150+ `DESIGN.md` design systems, plugins/skills, design templates such as `sprite-animation` (8-bit pixel animated explainer) and `critique` (five-dimension self-critique); CLI helpers like `od project list --json`, `od files list <project-id>`, `od files read <project-id> <path>`, `od plugin list|search|info|apply`, `od skills list`. **Re-verify; versions move fast.**

**It is a design workspace, not a pixel editor.** Image models do not respect pixel grids or palettes. Therefore:

| Use Open Design for | Do NOT use it for |
|---|---|
| Art bible as a `DESIGN.md` design system (palette tokens, rules) | Final sprite pixels |
| Style board, 1280×720 scene/HUD layout mockup (HTML) | Anything that must be palette-exact |
| Concept references / mood images (if an image provider is configured) | Shipping generated images |
| **Animated sprite viewer** (HTML, `image-rendering: pixelated`, 1×/4×/8×, on `#0B0C10`) for human review | Replacing the lint step |
| Critique passes on boards and previews | |

**Final pixels** come from the scripted pipeline (§B7.3), which is deterministic and lintable.

### B7.2 Setup (Stage 0 — do this first, record results in `art/TOOLS.md`)

1. Make sure Open Design is running: desktop app (macOS/Windows), or **Linux: run from source** (Node ~24, pnpm 10.33.x, `pnpm tools-dev run web`) or Docker (`deploy/`; default `http://127.0.0.1:7456`, Basic Auth with `OD_API_TOKEN`). Ask the human to start it if it isn't.
2. Install the MCP server into your agent: `od mcp install <agent>` (`claude`, `codex`, `cursor`, `copilot`, `opencode`, …; `--print` for a dry run). On macOS the system `/usr/bin/od` can shadow it — use the desktop app's **Settings → MCP server** snippet instead. Claude Code: verify with `/mcp`.
3. **Enumerate the live MCP tool list and write it to `art/TOOLS.md`.** Tool names differ between the official server and community bridges (e.g. `od_generate_design`, `read_open_design_source`, `publish_open_design_artifact`…). **The live list is authoritative; never guess tool names.**
4. Check whether an **image provider** is configured (needed for concept images). If not: skip Stage 3 image generation and use HTML/CSS-drawn concept boards, or ask the human to configure a provider/BYOK key. **Never** paste API keys into repo files.
5. Smoke test: create a throwaway project, generate a tiny HTML prototype, read it back. If any step fails → **Plan B**: continue Stages 1–6 with the local pipeline only and render the style board/viewer as plain HTML in `art/od/`; report the failure in `docs/HANDOFF.md`.

### B7.3 Local deterministic pipeline (authoritative for pixels)

Python 3.11+, `Pillow`, optional `numpy`. Build these tools first (Stage 1):

- `tools/pxlib.py` — tiny pixel library: `Canvas(w,h)`, `px/line/rect/disc/ellipse/ring/polygon/flood`, `Ramp("red")` (5 colors), `shade_sphere(canvas, cx, cy, r, ramp, light=(-1,-1))` (banded, no AA), `outline(canvas)` (sel-out from darkest neighbor ramp), `dither_checker(region, c1, c2)`, `stamp_pattern(mask, "ringed"|"spotted")`, `recolor(canvas, ramp_from, ramp_to)`, `Sheet(rows).save(png, json)`. Strict: any color not in the palette raises.
- `tools/make_art.py` — runs every `art/src/*.py` builder → `assets/sprites/`.
- `tools/lint_sprites.py` — see §B9.
- `tools/preview.py` — ×8 nearest-neighbor previews on `#0B0C10` with a 1 px grid and animation strips, plus `art/preview/contact_sheet.png` (so a vision-capable agent can *look* at its work).
- `tools/pixelize.py` — concept image → target size (box downscale) → quantize to the 30-color palette, **no dithering**. For **reference only**; always hand-clean via `pxlib`.

Authoring style: procedural primitives for big/regular shapes (washer, belts, chute, planets), hand-authored character grids for Pip (24×24), parametric frame generation (drum rotation, shake offsets, leg cycle). Pattern/color variants of items are **generated** (one authored shape → 9 variants).

*Optional alternative if the human prefers a ready-made pixel MCP* (e.g. a Pillow-based pixel-art MCP): it may replace `pxlib.py`, but the lint/preview/palette rules still apply.

## B8. Workflow and gates

Stop at every **GATE** and ask the human for approval (list the exact files to review).

**Stage 0 — Preflight (G0).** §B7.2 complete, `art/TOOLS.md` written, Plan A or Plan B declared.

**Stage 1 — Art bible & tools (G1).**
- Write `art/DESIGN.md` (direction, palette tokens, pixel rules, ramps, glyphs, animation timings), `palette.*`, and the local tools of §B7.3.
- Register the art bible with Open Design as a design system via whatever mechanism the installed version exposes (Settings/CLI/MCP; **don't hand-write into the daemon's data directory**). Then generate a **Style Board** prototype (HTML): swatches, background, ramps, silhouette test at 1×/4×, light-direction diagram, type sample. Export to `art/od/style_board.html`.
- **G1 = human approves board + palette + contract (§B5/§B6).** After G1 these are frozen.

**Stage 2 — Scene & HUD layout.**
- With Open Design, produce a 1280×720 HTML mockup using block-out shapes in palette colors: room, 3 belts, 4 washers (corners), central chute, HUD top bar, pulse ring around Pip. Export `art/od/layout_mockup.html`.
- Derive `data/layout.json` (art-px coordinates, belt flow directions, shredder positions, washer anchors, chute center) and hand it to Track A via `docs/HANDOFF.md`. Washers sit in the four inner corners; the player area stays free.

**Stage 3 — Concept references (optional, recommended).**
- If an image provider exists: per category generate ≥ 4 variants (Pip, washer) / ≥ 2 (each item, chute, belt) with the **Style Lock Block** (§B10). Save to `art/concepts/`, log each prompt in `PROVENANCE.md`.
- Pick winners; run `pixelize.py` for pixel-reference crops. Concepts guide shapes — they are **never** copied in as final art.

**Stage 4 — Golden samples (G2).** Build the smallest set that proves the style: `char_pip` (`idle_down` + `run_side`), `item_rocky` (`red_solid`, `blue_ringed`), `item_sock` (`yellow_spotted`), `mach_washer` (`idle` + `washing`), `env_belt`, `ui_panel`. Run lint + preview, assemble an **Open Design sprite-viewer** page (`art/od/viewer.html`: animated, 1×/4×/8×, on `#0B0C10`, with a composite "in-scene" strip). **G2 = human approves style.**

**Stage 5 — Tier A production (G3).** Order: items → washer → belts/chute/shredder → Pip → room/floor → FX → UI. For **each asset family** run the loop: *build → lint → preview → self-critique (1–5 on silhouette, palette discipline, consistency with golden samples, 1× readability, animation clarity) → fix, max 3 iterations → commit*. Run an Open Design `critique` pass on the viewer after each family. Update manifest status in `art/MANIFEST.md`. **G3 = all Tier A pass lint, human spot-check, Track A confirms import works.**

**Stage 6 — Tier B (G4).** Same loop. Optional.

**Stage 7 — Handoff.** Freeze names, finish `PROVENANCE.md`, write `docs/HANDOFF.md` (what's final, known weak spots, how to rebuild: `python tools/make_art.py && python tools/lint_sprites.py`).

## B9. Validation rules (`tools/lint_sprites.py`, run in CI)

For every `assets/sprites/*.png` + `.json` pair:

1. Dimensions = `frame_size × (max frames, rows)`; JSON animations match actual rows/frames.
2. Every non-transparent pixel ∈ palette; alpha ∈ {0, 255}.
3. ≤ 5 ramp colors + 2 accents per frame (warn above, fail above 8 total colors).
4. No fully empty frames; no frame touching the cell edge unless `allow_edge: true` in JSON (clipping check).
5. Pivot inside the frame; item/char frames have a 1 px outline pass (≥ 90 % of border pixels use a `*_0`/`space_*` color).
6. **Contrast:** for item sheets, the dominant mid-tone (`*_2`) vs `#0B0C10` ≥ 3:1 (WCAG relative luminance).
7. Pattern/color variants of the same item are silhouette-identical (mask equality), differing only inside the mask.
8. Reproducibility: rebuilding yields identical hashes.
9. Names match the manifest; no orphan files.

## B10. Style Lock Block (paste into every Open Design image/design generation)

```
STYLE LOCK — Cosmic Spin Cycle pixel art.
Pixel art game asset, strict limited palette (30 colors: deep space #0B0C10/#14172A/#1F2340/#2E3460,
steel blues/greys, crimson, nebula blue, solar yellow, accents cyan #19E3D1, magenta #E040FB,
green #5CFF8A, orange #FF7A1A). Hard 1-pixel edges, NO anti-aliasing, NO gradients, NO blur,
NO glow halos, NO soft shadows. Flat cel shading with 3 tones + 1 highlight, light from the top-left.
1-pixel selective outline in a darker shade of the object's own hue (not black).
Orthographic 3/4 top-down (2.5D) view, object centered, fully visible, single object,
solid flat background #0B0C10, no text, no watermark, no logos.
Theme: retro-futuristic cosmic laundromat, funny and friendly, no violence.
Silhouette must read at 16×16 pixels. Designed on a pixel grid at 1/4 final scale.
```

Negative guidance: no photorealism, no 3D render, no painterly texture, no dithering noise, no sub-pixel detail, no existing characters/brands (original designs only).

## B11. Godot import (Track A, M7; art agent verifies)

- Import: Filter **Nearest**, mipmaps off, compress **Lossless**, no alpha-border fix.
- `tools/build_spriteframes.gd` converts each JSON into `SpriteFrames` (`AtlasTexture` regions per frame, fps/loop from JSON).
- Nodes: `AnimatedSprite2D`, scale ×4, `centered = false` with `offset = -pivot`. Items/Pip bodies don't rotate the sprite (§A7).
- 9-slice for `ui_panel`, `NinePatchRect` with `patch_margin = 8`.
- Font: an **OFL-licensed pixel font** with full Spanish coverage (`á é í ó ú ñ ü ¿ ¡`); verify glyphs before choosing (candidates: *Silkscreen*, *Pixelify Sans*, *Press Start 2P*). Record license in `PROVENANCE.md`.

## B12. Acceptance checklist per asset

- [ ] Listed in §B5 with the exact id/size/frames, JSON valid
- [ ] `lint_sprites.py` passes; palette-only; no semi-transparent pixels
- [ ] Silhouette readable at 1× on `#0B0C10`; color-blind glyph present where required
- [ ] Light top-left; sel-out outline; consistent with golden samples
- [ ] Animation loops cleanly; timing per §B5
- [ ] Preview ×8 reviewed (by a vision-capable agent or the human)
- [ ] `PROVENANCE.md` updated (tool, prompt, date, license note); no third-party IP copied
- [ ] Imported in Godot and verified in the running game (no shimmer, correct pivot)

## B13. Failure modes and fallbacks

| Symptom | Action |
|---|---|
| OD MCP not reachable / tools missing | Plan B (§B7.2-5); log in `HANDOFF.md`; continue local pipeline. |
| No image provider configured | Skip concept images; ask the human for a provider or use hand-drawn HTML concept boards. |
| Generated concept isn't pixel-clean | Expected. Use as reference only; build via `pxlib`. |
| Palette needs a new color | Propose in `HANDOFF.md`; don't add silently (breaks lint + consistency). |
| Shapes look inconsistent across items | Re-derive from the shared base shape; check ramp slots; compare against golden samples. |
| Asset too complex for budget | Reduce frames (Tier A minimum), keep silhouette and palette discipline. |
| Contradiction with GDD | Log in `docs/DECISIONS.md`, follow GDD §1.8 (visual direction) first. |
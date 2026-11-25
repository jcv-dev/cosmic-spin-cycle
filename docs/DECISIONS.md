# Decisions log

Format: id · date · decision · why · how to change it.
The GDD wins over `AGENTS.md`; this file records explicit overrides and gaps.

## D001 — Engine version: Godot 4.7.2 stable
2026-11-24 · Verified with `godot --version` (`4.7.2.stable.arch_linux.ed1daf0bf`).
Target ≥ 4.4 per AGENTS §A1; CI pins 4.7.2. Change: bump the project features and CI
version together, then re-run the full suite.

## D002 — Test framework: GUT 9.6.1 (vendored)
2026-11-24 · GUT is pure GDScript, vendored in `addons/gut` (MIT), and was smoke-tested
against Godot 4.7.2 before adoption. gdUnit4 was not verified on 4.7. Change requires
rewriting `tests/` and CI.

## D003 — Renderer: `gl_compatibility`
2026-11-24 · Minimum spec is OpenGL 3.3 and the build box has no GPU (llvmpipe). The 2D
game does not need Forward+. Verified a 1280×720 window renders and screenshots.

## D004 — Pixel scale and coordinates
2026-11-24 · 1 art px = 4 world px (`Config.ART_SCALE`), art canvas 320×180.
`data/layout.json` stores **art-pixel** integer coordinates with a top-left origin;
runtime converts with `× 4`. This keeps the design and the art pipeline in one unit.

## D005 — Rhythm clock architecture
2026-11-24 · `BeatConductor` is a **scene** autoload (AGENTS §A6 #16) with an
`AudioStreamPlayer` child. `get_song_time()` derives from audio playback + mix time −
output latency − user calibration − stem offset when a stream plays, and free-runs from
accumulated frame delta otherwise, so headless tests and silent greybox runs use the same
API. Beats are emitted in `_process`, never a Timer. `set_bpm()` starts a new musical
clock at a stem/phase boundary. M1 owns refinement and tests; the public API is frozen in
`docs/CONTRACTS.md`.

## D006 — Conveyor model: velocity steering, not instant override
2026-11-24 · GDD §5.3 allows "velocity override or force". Belts steer each non-held
body's velocity toward `flow × speed × item.belt_speed_scale` at `BELT_ACCEL` (900 px/s²)
per physics tick. Instant assignment was rejected because it would cancel item-item and
item-wall collisions. Socks use a 1.6× belt speed scale (GDD §6: "muy ligero y rápido").

## D007 — Friction interpretation (§A6 #17)
2026-11-24 · With no input: `v *= pow(1.0 - 0.12, 60.0 * delta)`, i.e. ~0.5 s to stop from
340 px/s. Exposed as `Config.PLAYER_FRICTION`; balance may tune it.

## D008 — Item variants
2026-11-24 · An item instance is `(item_id, color, pattern)`. Sheets expose the nine
`<color>_<pattern>` animations. `galaxy_core` is a wildcard and has no variants. Colour
and pattern data live in `data/items.tres`; art ids stay `item_rocky` etc.

## D009 — Commit policy (owner override)
2026-11-24 · The project owner explicitly requires **many small commits**, superseding
AGENTS §A8's "one commit per milestone". See `docs/COMMITS.md`. Every commit must be green
(relevant tests + lint) and carry a conventional message.

## D010 — Internet-sourced, keep-able placeholders (owner override)
2026-11-24 · Instead of AGENTS M0's flat palette-shape placeholder generator, all
placeholder sprites, music, SFX and fonts are **sourced from the internet** under
CC0/public-domain or openly licensed terms, then adapted deterministically to the frozen
frame/palette contract. They are good enough to keep if the owner likes them, and are
recorded in `docs/PROVENANCE.md`. Procedural art remains a fallback only if a source
cannot be found or licensed.

## D011 — Layout
2026-11-24 · Frozen in `data/layout.json` (art px). Washers in the four inner corners,
north/south/west perimeter belts, central chute, player spawn at (160,128). The west belt
is dormant until phase 3 and runs south→north ("in reverse"). Track B may propose a better
layout, but it must land as a data change + `docs/HANDOFF.md` note, not silently.

## D012 — Stability bar asset split
2026-11-24 · AGENTS B5 describes `ui_bar_stability` as "96×10 + 1×6 fill", which cannot be
one uniform-frame sheet under the §B6 contract. Split into `ui_bar_stability` (96×10) and
`ui_bar_stability_fill` (8×6 tile), both with JSON. Everything else follows §B5.

## D013 — Phase timing and BPM
2026-11-24 · GDD §2.5 table is authoritative (AGENTS §A6 #1): phases at 0/120/270/420 s
with 105/118/130/142 BPM. The §1.7 narrative is not used for numbers.

## D014 — Debug seed
2026-11-24 · One `RandomNumberGenerator` (`GameState.rng`) drives all spawns. `reset(seed)`
is deterministic for non-zero seeds; 0 means "pick a random seed", which is stored and
shown on the end screen. Debug builds can force a seed via `Settings.db_seed`.

## D015 — Final Load composition
2026-11-24 · 4 gas giants + 4 moons + 4 rocky planets + 1 core, spawned across the final
60 s (`Config.FINAL_LOAD_*`, §A6 #15). M3 implements the convoy schedule; M9 validates
winnability with `tools/balance_sim.gd`.

## D016 — CI target
2026-11-24 · GitHub Actions uses `chickensoft-games/setup-godot@v2` with 4.7.2, imports
the project, runs GUT, then gdlint/gdformat and `tools/lint_sprites.py` when it exists.

## D017 — Localization keys for M0–M3 UI
2026-11-24 · Player-facing strings go through `tr()` from day one, but until the Godot
`Translation` resources land (M6), the **Spanish source string is the key** (`tr("TURNO")`,
gettext-style). This keeps the UI readable now and lets English be added later without
rewriting call sites. M6 must add `data/i18n/es.*`/`en.*` keyed by these strings and switch
to stable `HUD_*` keys only if the Spanish copy changes.

## D018 — Runtime art scale and physics units
2026-11-24 · Sprites ship at art size; Godot renders them at exactly ×4 (`Config.ART_SCALE`)
with Nearest filtering and the JSON pivot. `ItemData.radius` is stored in **art pixels** and
multiplied by ×4 only when creating the physics circle (rocky 8 art px → 32 world px,
gas 12→48, core 16→64), so collisions match the visible silhouette. The hold point is
`HOLD_DISTANCE + item radius`, so a 96 px gas giant clears the 96 px Pip instead of covering
him. No other scale factors are used; non-integer scaling is forbidden.

## D019 — Audio buses created at runtime
2026-11-24 · `Settings._ready()` creates `Music` (−6 dB), `SFX` (−6 dB) and `UI` (−6 dB)
buses sent to Master, idempotently. `BeatConductor` sends its player to `Music`, item
squelch and the belt warning to `SFX`. AGENTS M8 recommends a persisted
`default_bus_layout.tres` and a `Loops` bus; that is deferred to M8 because the current
three-bus split is sufficient and avoids checking in a generated binary resource before the
mix exists.

## D020 — HUD occupies the top wall band
2026-11-24 · The frozen layout places the north belt at y = 40–104 world px. A 74 px HUD
hid it. The HUD is now a 48 px full-width bar (clock, stability, beat dots, combo, score)
sitting over the 32 px wall band; belts and items are visible. The bottom hint is below the
south belt. M6 may restyle it, but it must not cover the north belt.

## D021 — QA warp uses seek, not replay
2026-11-24 · `MainLevel.warp_to(t)` jumps to a phase without instantiating every historical
spawn: it applies the phase, then `SpawnDirector.seek(t)` skips the past events and play
continues from `t`. It is deferred until `_ready` completes (the first `add_child` in a
`SceneTree` script happens before `_ready`, which caused replay piles). `set_shift_time(t)`
remains the replay path used by tests. M5's F1 cheat will use `warp_to`.

## D022 — Belt-reversal warning sound placeholder
2026-11-24 · Belts turn their chevrons orange and emit `reverse_warning(beats_left)` four
beats before a flip; `MainLevel` plays `turbulent_alarm.ogg` at −7 dB on the warning beat.
M8 should replace it with a dedicated two-note belt alarm; the signal and timing are final.

## D023 — Placeholder provenance policy (owner override of M0 placeholders)
2026-11-24 · Every shipped sprite is either adapted/composed from a pinned CC0 Kenney pack
or explicitly `authored-fallback` with a recorded reason (Pip: the character pack transfer
failed twice and the industrial pack has no characters; sock/core: no 16/32 px CC0
silhouette reads correctly). No AI images, no unlicensed material. Full table and hashes in
`docs/PROVENANCE.md`. The owner may keep any of these assets; replacements must preserve the
same ids, frame sizes and JSON.

## D024 — M3 level scope
2026-11-24 · `MainLevel` runs the complete 480 s spine: clock, phase changes, BPM/stem
switch, belt activation, seeded spawns, item physics, shredders, HUD, music, belt warning
and a temporary end label. Washers, chute and the real win/lose evaluation are M4/M5, so
today ending at 480 s only checks stability > 0. This is deliberate and documented rather
than faking M4 systems.

## D025 — Sprite import settings
2026-11-24 · `assets/sprites/*.import` are committed with Lossless compression, mipmaps
off, no alpha-border fix, no 3D detection; Bronze/source scans under `art/sources/` are
excluded with `.gdignore`. Re-importing must not change pixels or filtering.

## D026 — Washer assignment ramp and the pattern machine
2026-11-24 · M4 needs a per-phase requirement for four washers. The GDD (§A6 #10) is
underspecified. Adopted: **P1** NW=`red`, NE=`blue`, SW/SE **locked** (`FUERA DE
SERVICIO`); **P2** SW unlocks as `solid`; **P3** SE unlocks as `spotted` (yellow world
introduced); **P4** NW=`yellow`, NE=`red`, SW=`solid`, SE=`ringed`. Rationale: two
choices in the first 20 s (the onboarding target), one new machine per phase, and the
pattern machine always rotates so patterns stay meaningful without breaking coverage —
every `(colour, pattern)` the spawner can produce in a phase has at least one home
(`WasherAssignments.coverage_ok` is unit-tested). Locked washers bounce items with no
stability penalty. Change: edit `WasherAssignments` + the coverage test.

## D027 — Victory condition: survive the shift, rank by delivery
2026-11-24 · §A6 #11 proposed "Final Load delivered clean to the chute" as the win
condition. Delivering 13 heavy items in the last 60 s with one pair of hands is not
winnable (the research measured a 2.53 s loop vs a 1.7 s spawn interval in phase 3), so
gating victory on it would make the game feel broken. **Adopted: victory = stability > 0
at 06:00; defeat = stability 0 at any time.** The Final Load is a climactic wave that
threatens stability, and deliveries/rank (S/A/B/C) carry the skill expression.
`FINAL_LOAD_COUNTS_DONE_IN_WASHER` stays as a stat, not a gate. Change: reintroduce the
gate in `ShiftRules.evaluate` and retune the convoy.

## D028 — Screen flow lives in `App.gd`; screens are signal-only
2026-11-24 · `Main.tscn` root is now `App` (`scripts/main/App.gd`), which owns level
lifetime, pause (`get_tree().paused`), fades and persistence. Every screen is a `Control`
that emits intent signals (`start_requested`, `resume_requested`, …) and is optional at
runtime (`ResourceLoader.exists`): a missing screen falls back to a styled
`FallbackScreens` version, so `main` always boots. Screens never load scenes or touch
autoloads beyond `Settings` values. Change: keep the signal names in
`docs/CONTRACTS.md` §9 consistent or update App's `_connect_screen` map.

## D029 — HUD: corner plaques replace the top bar and the bottom strip
2026-11-24 · Supersedes D020. The 48 px full-width bar still clipped the north belt
(y=40) by 8 px and gave four numbers the same visual weight. The HUD is now two corner
plaques (0–312 × 0–104 and 968–1280 × 0–104) plus a 480 px mission ribbon in the wall
band; the middle 608 px of the play field stays clear. The 73-character bottom
instruction strip is deleted (measured 11 px at 3.90:1 — below the 4.5:1 floor). All
world-relevant information moves to the objects it describes (washer holograms, chute
beacon, reticle states, beat ring). Change: `scripts/ui/HUD.gd` + `docs/HUD.md`.

## D030 — Tutorial contract
2026-11-24 · A 7-gate, ~150 s tutorial runs the **real** MainLevel in `mode =
"tutorial"` (`Tutorial.tscn` instances it): scripted items, no spawner, phase locked to
1, fixed seed `Config.TUTORIAL_SEED`, negative stability disabled until gate 7. Gates:
move → grab → throw → beat → match → strike → deliver, ending with a real wash→deliver
cycle. Skippable at any time (ESC → confirm) and soft-skippable per gate after 12 s.
`Settings.tutorial_completed` / `tutorial_skipped` / `first_run_done` persist and drive
the first-run prompt, which appears **after** pressing Play and never again. Replayable
from the title forever; nothing is gated behind completion.

## D031 — Research-derived feel constraints
2026-11-24 · From `docs/UX_RESEARCH.md` (21 sources): beat ring contracts over **2
beats**; action transients ≤ 0.45 × T_beat (257/229/208/190 ms); screen shake quantised
to whole art pixels (4/8 px, never 6); **no hitstop on graded throws/grabs** (it desyncs
the player's clock) — explosions only, 33 ms, reduce-motion gated; no shake on the beat;
no full-screen flashes; every colour-coded state carries a glyph + text. These are
tested where practical (`tests/unit/test_diegetic_layer.gd`, `test_juice.gd`).

## D032 — `Juice` autoload and `CameraRig`
2026-11-24 · Impact effects are centralised in a `Juice` autoload (`shake`, `hitstop`,
`flash`, `punch_zoom`, `rumble`, `set_reduce_motion`) so no entity hard-codes shake
logic, and `Juice.hitstop` measures wall-clock time (Engine.time_scale scales `_process`
delta, which made a naive timer 20× too long). `CameraRig` replaces the plain
`Camera2D` (same node name `Camera2D`, so existing tests keep passing) and owns
lead/deadzone/shake offsets. `Settings.reduce_motion` disables shake, hitstop, flash and
zoom; the beat ring remains (it is information).

## D033 — First-run prompt policy
2026-11-24 · Pressing `INICIAR TURNO` for the first time opens a modal that recommends
the tutorial with two choices: `HACER EL TUTORIAL` (default focus) and `EMPEZAR EL
TURNO` (persists `first_run_done`). Skipping is a legitimate choice and is never
punished or repeated. The prompt is not shown before the first press, so the first
interaction is always the big one.

## D034 — First 20 seconds
2026-11-24 · A dirty starter item (`rocky`, red, solid) is placed 96 px from Pip at
1.2 s so the first useful action is a grab, not a walk. The objective ribbon starts as
`OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00`. Phase banners are suppressed before 20 s
and only `rocky`+`solid` spawn in phase 1. Measured against the 20-second test in
`docs/UX_BIBLE.md` §2; guarded by `tests/integration/test_first_20s.gd`.

## D035 — A single loaded item starts washing (owner playtest)
2026-11-24 · AGENTS §A6 #4 said a cycle starts when the drum is full **or** on a rhythm
strike. Playtested build: a player throws one item into a machine and nothing happens, so
the machines read as broken ("I have no idea what the black holes do"). **Adopted:** a load
of ≥ 1 item auto-starts after `Config.WASHER_AUTO_START_S` (1.2 s) with the holo showing the
countdown; a rhythm strike still starts it instantly, and filling the drum still works.
Change: `WasherFSM._advance` / `Config.WASHER_AUTO_START_S`.

## D036 — Balance retuned to one player's throughput (E2E bot evidence)
2026-11-24 · `tools/playtest_bot.gd` measured the real loop at ~13 s (grab → walk → wash →
walk → deliver). The old cadence (3.5/2.4/1.7 s = 197 spawns) was **1.5× faster than one
pair of hands**, so stability always hit zero: the game was unwinnable by construction.
**Adopted:** phase intervals `10 / 8 / 6 s` (66 spawns per shift), shredder loss `−3` (was
−8), and the chute funnel (D037) so clean items are not lost to a missed throw. The bot now
reports 100 % throw accuracy and 94–100 stability over 90 s. Change: `data/phases.tres`,
`Config.PHASE_SPAWN_INTERVAL_S`, `Config.STABILITY_FELL_OFF_BELT`; the spawn-count tests
assert the new numbers.

## D037 — Chute position bug, generous catch volumes and the delivery funnel
2026-11-24 · Three playtest findings, one root cause each:
1. `MainLevel` passed **world** pixels into `DeliveryChute.configure()`, which multiplies by
   `ART_SCALE`; the chute lived at (2560, 1440), off-screen, so delivery was impossible and
   the "green ring" players aimed at was scenery. Fixed to pass art pixels; an integration
   test now asserts `(640, 360)`.
2. The washer catch volume was a 60 px circle at the door. A throw that grazed the cabinet
   did nothing ("aiming exactly at the door is near impossible"). The catch is now a 122 px
   circle centred on the **cabinet**, and the whole machine draws a cyan bracket + chevrons
   while a compatible item is carried.
3. The chute is now a funnel: a 110 px hatch plus a 240 px suction field pulls clean items
   in, and thrown items home for 0.55 s toward the nearest valid destination (washers or
   chute) so the player aims the machine, not a pixel.

## D038 — Owner playtest #2: causal copy, silent-stem fix, friendly volumes
2026-11-25 · Evidence and reasoning in `docs/UX_RESEARCH_ADDENDUM.md`. Changes:
1. **Tutorial copy is causal** ("Muévete para alcanzar la ropa", "Golpea para lavar y calmar").
   No riddle nouns; every prompt names the object it affects and its purpose. Gates 3 and 6
   now stage the machine they talk about, so the sentence is literally true.
2. **Music was silent from the first frame.** `AudioStreamPlayer.stream` stops playback when
   assigned (engine contract), and phase setup re-assigned the stream after `start()`.
   `BeatConductor.set_stream()` now restarts a live player. A headless check asserts
   `playing=true` after `LEVEL_READY`.
3. **Friendly volumes never push bodies.** The chute no longer bounces dirty items; it shows
   `LAVA PRIMERO`. Washers reject `clean` items (`REJECT_CLEAN`), which stops a washed item
   ejected from an upper machine being re-inserted into the lower one.
4. **Strike feedback:** a 160 ms cyan arc, a pitched whoosh (hit vs whiff), the same graded
   action, and a tutorial gate that explains the verb's two uses.
5. **Cadence:** 7/6/5 s (83 spawns/shift) after the owner asked for more pressure; the E2E
   bot remains the gate that proves it stays survivable.
6. **Conveyor audio:** a −24 dB belt hum loop plus a pitched-down arrival click on each spawn.

## D039 — Playtest #3: wider windows, an audible beat, sticky aim and aim-based homing
2026-11-25 · The owner could not feel the beat and could not tell where a throw was going.
1. **Windows widened**: PERFECT ±90 ms, GOOD ±170 ms (was ±65/±130). Random on-beat rate
   rises to ~60 % at 105 BPM and ~80 % at 142 BPM — the deliberate trade is a lower skill
   ceiling for a beat that a non-rhythm player can actually hit. Change:
   `Config.WINDOW_PERFECT_S` / `WINDOW_GOOD_S` and the boundary tests.
2. **Audible metronome**: `BeatConductor` plays a quiet click on every beat (−19 dB, pitch
   1.9) with a louder, higher accent on the downbeat (−15 dB, pitch 2.4), mixed under the
   stems. The stems alone were not legible. The click is driven by the same audio-derived
   beat emission as gameplay, so it is the reference, not a parallel timer.
3. **HUD beat dots**: radius 4/6 px with a white core and a 1.5 px halo on the active dot,
   so the current beat is readable without comparing sizes.
4. **Aim is sticky**: once the mouse has been used it stays authoritative until the right
   stick is moved (the old 1.2 s timeout silently reverted aim, which is why the arrow
   seemed to stop following the mouse).
5. **Homing follows the aim**: thrown items curve toward the compatible machine best aligned
   with the throw (dot ≥ 0.55), not simply the nearest one. Clean items only home to the
   chute when the throw points at it. This removes "it went to the wrong washer".
6. **Copy**: gate 4 `Lanza al cerrarse el anillo`; gate 6 `Golpéala para que no explote`
   (turbulence named as the threat, not "calmar").

## D040 — Playtest #4: pressure up, beat legible, item identity, broken machines
2026-11-25 · Owner feedback after the audio/copy pass.
1. **Difficulty up**: spawn cadence 6/5/4 s → **98 spawns per shift** (19/29/37/13).
2. **Gradual ramp**: belts accelerate continuously to **+35 %** by 06:00 (`MainLevel._apply_speed_ramp`
   on each beat), while the official phase marks stay frozen at 120/270/420 s and still own
   BPM, assignments and the base spawn interval. A full spawn-interval ramp is left for M9.
3. **Beat legibility**: the metronome click is now −9 dB (downbeat) / −12 dB, and the *chute*
   carries the beat — a swelling ring plus four quadrant arcs, one per beat of the bar. The
   active HUD dot also gained a white core and halo.
4. **Rewards made explicit**: grade popups read `PERFECTO +2 combo` / `BIEN +1 combo` and each
   grade has its own chime pitch. Previously the player could not know what a grade bought.
5. **Item identity**: the carried-item chip moved **above Pip** (never occluded by the item)
   at 16 px with a colour swatch (triangle/circle/square) and a pattern swatch (square/ring/
   dots), because "moteado" was hard to read on a small sprite.
6. **Broken path**: turbulence now starts in phase 2 (`AUTO_TURBULENCE_PHASE = 1`), so
   explosions and `AVERIADA` are reachable before the last phase. Explosion posts an
   `AVERIADA` chip and a HUD line; the auto-repair posts `REPARADA` with a green flash and a
   bell. Locked machines now read `ABRE EN FASE 2/3` instead of the ambiguous "out of service".
7. **Corner rescue**: a free item that has not moved for 3 s gets a 320 px/s nudge toward the
   room centre, so items that pile at the far end of a reversed belt cannot stay stuck.
8. **HUD smaller**: plaques 300×86 at 90 % instead of 312×94 at 97 %; holograms sit 64 px into
   the cabinet so the drum is never covered.

## D041 — Combo has a survival payoff, not only a score payoff
2026-11-25 · The owner asked the right question: "what does the combo do for me? Just score?"
It did only multiply points at the chute (`item.points × combo`), which feeds the rank but
never changes a decision during play. Adopted: **×4 adds +1 stability on delivery, ×8 adds
+2** (`ScoreRules.combo_stability_bonus`), so holding a combo through a bad stretch is a
survival tool, not a vanity number. The HUD caption now reads `COMBO · PUNTOS` and switches
to `COMBO · +ESTAB` (cyan) at ×4, and the first time the player reaches ×4 a single toast
explains it. Nothing else about the combo changed (build +2/+1, MISS resets, cap ×8).
Change: `ScoreRules` + `DeliveryChute` + `HUD._on_combo`.

## D042 — Combo is score only; a wrong load jams the machine; worlds have names
2026-11-25 · Owner corrections:
1. **No stability from combo.** D041 reverted: combo multiplies delivery points and nothing
   else; "I don't want to make the game easier". The HUD caption is a plain `COMBO · PUNTOS`.
2. **A wrong colour/pattern now goes in and breaks the machine.** `Compatibility` still
   decides a fit, but a mismatch is no longer bounced: the washer absorbs the item, jams
   (`WasherFSM.jam()` → `BROKEN` with the 6 s repair timer), ejects the whole load, applies
   `-12` once, plays the alarm + `¡ATASCADA!` chip and reports `LAVADORA ATASCADA`. This makes
   the match rule a real trap instead of a nudge. Locked washers still refuse without a cost.
3. **The fiction is celestial, not laundry.** Player-facing copy says planeta/astro, not ropa
   or pieza (tutorial, tips, objective). Each item carries a **real catalogue name** from
   `CelestialNames` (exoplanets for rocky, gas giants for gas, moons for moon, comets for the
   light one, galaxy cores for the unique one), drawn 10 px under the sprite: KEPLER-452b,
   TRAPPIST-1e, EUROPA, TITÁN, HALLEY, SAGITARIO A*…

## D043 — Dash is movement; stabilising is a 3 s hold; broken lasts 10 s
2026-11-25 · Owner change of technique.
1. `rhythm_strike`/Shift is now **dash only**: no grade, no washer interaction, no `struck`
   signal. `Player.do_dash()` replaces `do_strike()` (alias kept), and the strike arc/sound
   are gone.
2. Stabilising a turbulent washer is a **hold of the new `interact` action (E / gamepad X) for
   `Config.INTERACT_HOLD_S` = 3 s**, anywhere within `INTERACT_RANGE_PX` = 170 px of the
   cabinet. While the hold is active the explosion countdown is frozen, so arriving at the
   machine is the skill, not winning a sprint. The washer shows `MANTÉN E` / a countdown and
   grants `ESTABILIZADA` on success.
3. **Broken lasts 10 s** (`WasherFSM.REPAIR_COOLDOWN_S`), shown as `AVERIADA 9s…` on the holo;
   a jam still costs −12 and ejects the load.
4. **Metronome louder again**: −6 dB downbeat / −9 dB beat (was −9/−12).
5. Tutorial gate 6 is now `Mantén E para calmarla`; the director polls the machine state
   instead of listening for a strike, and its fail-forward completes the hold.

# Progress

Updated after every milestone/workstream. Times are local (America/Bogota).

## Milestone status

| Milestone | State | Evidence |
|---|---|---|
| M0 Bootstrap | **done** | project settings, autoloads, Input Map, GUT, CI, contracts, layout |
| M1 Beat engine & calibration | **done** | `BeatConductor` audio clock, 4 click tracks, overlay, calibration wizard, BeatLab |
| M2 Player & item physics | **done** | `Player`, `MagneticGrabber`, 5 behaviours, `PlayerSandbox`, 20-item stability test |
| M3 Belts, spawning, phases | **done** | belts, shredders, `SpawnSchedule`, `SpawnDirector`, 480 s sim, warp/phase wiring |
| M4 Washers | **done** | `WasherFSM`, `CosmicWasher` ×4, holograms, turbulence/strike, `DeliveryChute`, score rules |
| M5 Shift flow | **done** | real win/lose, `shift_finished`, `ShiftRules`, F1–F4 cheats, final-load data |
| M6 UI & flow | **done** | title, first-run, tutorial, pause, options, end, instant restart, HUD redesign |
| M7 Art integration | **partially done early** | sprite sheets + SpriteSheet loader are live; M7 becomes polish |
| M8 Audio | **partially done early** | four phase stems, SFX, buses live; transition modes remain |
| M9 Balance/polish | planned | balance sim, export presets |

## M0 — done

- Godot 4.7.2, `gl_compatibility`, 1280×720 canvas_items, 60 Hz, zero 2D gravity,
  Nearest canvas filter, full Input Map, four autoloads.
- GUT 9.6.1 vendored; CI workflow; `gdlint`/`gdformat` policy; 30-colour palette;
  `data/layout.json` frozen.

## M1 — done

- **BeatConductor**: audio-derived song time (`playback + since_mix − output latency −
  calibration − stem offset`), ≤5 ms monotonic clamp, free-run fallback for headless,
  beats from `_process`, 4/4 measures, `set_bpm` = fresh stem clock, WAV/OGG loop support.
  Pure `compensated_song_time` and `monotonic_time` helpers are unit-tested.
- **Click tracks**: deterministic 8-bar loops + count-ins at 105/118/130/142 BPM,
  44.1 kHz/16-bit mono, SHA-256 manifest (`assets/audio/metronome/`).
- **Calibration**: wrap/median/MAD/outlier/±500 ms math, 10 s wizard, persisted to
  `user://settings.cfg`. **Debug overlay**: signed Δt, grade, window bar, latency,
  calibration, beat flash (F10). **BeatLab** dev scene for manual listening.
- Tests: 49 added; 480 s virtual beat count ±1 at all four tempos.

## M2 — done

- `ItemData`/`ItemDatabase` + `data/items.tres` for all five GDD items.
- Player: accel 2400 / vmax 340 / friction `pow(0.88, 60·dt)`, 8-dir, mouse+stick aim,
  dash 120 px (measured 46 px into a wall 60 px away), one grade per action.
- Grab ≤64 px, hold spring, one item, art-scaled collision radii, dynamic hold clearance.
- Behaviours: rocky stable; sock 1.6× belt speed + squelch + random slide; moon
  boomerang on MISS; gas giant ×0.5 on MISS + e=0.85; core attracts socks, is a wildcard.
- **40 bodies / 600 physics ticks: 0.544 ms/tick** (physics monitor).
- 20-item/3 s integration: no escapes, no NaN, no stuck bodies.

## M3 — done

- Phase table 105/118/130/142, 3.5/2.4/1.7 s, belt activation per phase, convoy 4+4+4+1.
- Pure `SpawnSchedule` (seeded, deterministic) → **11/18/24/13 = 66** spawns / 480 s
  (retuned from 197 in D036: the old cadence was 1.5× faster than one player).
- `SpawnDirector.start/advance_to/seek/simulate`, alive cap 40, per-phase counts.
- Belts steer velocity at 900 px/s², sock multiplier; phase-3 reversal is pure and warns
  4 beats before flipping every 16 measures: **warnings on beats 60/124/188, flips on
  64/128/192** at 130 BPM.
- Shredders: −8 % stability, `fell_off_belt`, free, double-entry guard.
- 480 s virtual integration run, `tools/sim_run.gd` (66 total, exits 0).
- MainLevel now drives the clock, spawner, belt activation, beat forwarding and warning SFX.

## Integration (M0–M3)

- 29 Tier A sprite sheets (176 frames) from CC0 Kenney packs + authored fallbacks,
  30-colour palette, deterministic build, lint 29/29, contact sheet in
  `docs/media/sprites_contact.png`.
- Four CC0 HoliznaCC0 stems tempo-mapped to 105/118/130/142 (16 bars each), nine CC0 SFX,
  Silkscreen OFL with full Spanish coverage; `verify_audio.py` 16/16.
- `SpriteSheet` runtime loader pulls `<id>.png+.json` into `SpriteFrames` (×4, pivot from
  JSON, Nearest); items and Pip animate from the shipped sheets with flat-art fallback.
- Audio buses Master → Music / SFX / UI; beat stems on Music, sock squelch + warning on SFX.
- HUD compacted into the 48 px top band so it no longer hides the north belt; Silkscreen
  font; beat dots in the bar.
- QA: `MainLevel.warp_to(t)` + `SpawnDirector.seek` for time-jump screenshots; safe deferred
  until `_ready`.

## Measurements

| Metric | Value | Where |
|---|---|---|
| Test suite | **315 tests, 7,179 asserts, ~38 s** | GUT summary |
| Sprite contract | 29/29 sheets, 176 frames, 22 colour-budget warnings | `tools/lint_sprites.py` |
| Audio contract | 16/16 checks (BPM drift ≤0.01 ms, peaks −1.3…−2.2 dBFS, Spanish glyphs) | `tools/verify_audio.py` |
| Spawns / 480 s | 66 (11/18/24/13), seed 1234 | `tools/sim_run.gd` |
| E2E playtest bot | 6 washes, 4 deliveries, 0 losses, 100 % throws, stability 94 (93 s) | `tools/playtest_bot.gd` |
| Belt reversal | warnings 60/124/188, flips 64/128/192 (130 BPM) | `test_belt_reversal*` |
| Physics | 0.544 ms/tick for 40 bodies | `docs/M2_PHYSICS.md` |
| Reported PulseAudio latency | 52.84 ms (headless Dummy = 0) | `docs/CALIBRATION.md` |
| Godot | 4.7.2.stable.arch_linux.ed1daf0bf | `godot --version` |

## Known issues / honest gaps

- **M4 missing**: no washers, chute, holograms, turbulence or washing cycle. Throwing an
  item currently only exercises physics. Win/lose and the chute are M4/M5.
- **M6 missing**: immediate start, no title/pause/end screen or instant-restart button; the
  M3 level shows a temporary end label and R restarts.
- **Audio**: phase stems cut at 120/270/420 s rather than a measured musical bar; the
  DRUM_BRIDGE mode and a dedicated belt-reversal SFX wait for M8 (the warning uses the
  turbulent alarm placeholder). No Windows/Bluetooth latency measurement yet — owner TODO.
- **Art**: `char_pip`, `item_sock`, `item_core` remain `authored-fallback` (documented
  attempts in PROVENANCE); 22 frames exceed the advisory 7-colour budget (still pass B9);
  `ui_*` assets are not yet used by the HUD (M6).
- **Washer slots/core wildcard** compatibility is pure-tested but not wired into a washer FSM.
- **Public GitHub remote** is not configured in this checkout.
- HUD font at 9–11 px is legible but the bottom hint is small at 1280×720; M6 polish.
- The test suite reports engine ObjectDB/RID leak warnings at exit (GUT scene instancing);
  they do not fail the run, but M7 should investigate.

## M4 — done (owner UX phase)

- Pure `WasherFSM` (549 lines, table-driven) + `WasherAssignments` + `ScoreRules` + `ShiftRules`.
- `CosmicWasher` ×4 instantiated from `data/layout.json`; capacity 3, wildcard core, beat
  reductions once per insert, turbulence rule (`min(5 s, 8 beats)`, grade ≥ GOOD resolves),
  explosion (−25) and repair, DONE ejection of clean items.
- Holograms carry the requirement as glyph + label (colour + pattern, never colour alone);
  the shipped `solid`/`spotted` icons were replaced procedurally because they read as a cloud
  and plus signs.
- `DeliveryChute` at the room centre: clean only, +3 stability, points × combo, chirp, accept
  animation; dirty items bounce with `LAVA PRIMERO` and no penalty.
- `WasherAssignments` ramp: P1 red/blue with two locked machines, P2 +solid, P3 +spotted,
  P4 yellow/red/solid/ringed. Coverage is unit-tested for every variant a phase can spawn.
- Wrong washer −12, explosion −25, delivery +3 are all asserted in the stability ledger.

## M5 — done

- `MainLevel` announces `shift_finished(result)` exactly once; `App` shows the end screen.
- Victory = stability > 0 at 06:00 (D027), defeat = stability 0; rank S/A/B/C from
  `ScoreRules`; best score/rank persisted and shown on the title only when a real run exists.
- F1 (+60 s), F2 (+25 stability), F3 (+500 score), F4 (spawn item) exist only in debug builds.
- Full loop test: `tests/integration/test_m4_loop.gd` drives grab → wash → deliver with the real scenes.

## M6 — done (the owner's three asks)

- **Menu**: title with a living diorama (real room rendered in a SubViewport), logo, five
  entries with three type tiers, focus ring + caret, hover, ambient stem, fade-in.
- **First run**: pressing Play opens `¿PRIMERA VEZ?` with the tutorial as the default focus and
  `EMPEZAR EL TURNO` as the persistent skip. Never asks again; tutorial always replayable.
- **Tutorial**: 7 gated steps on the real level (`mode = "tutorial"`), scripted items, phase 1,
  fixed seed 7001, stability protected until gate 7, ESC skip with confirm, TAB soft-skip after
  12 s, completion persists.
- **HUD redesign**: two corner plaques + mission ribbon, no bottom strip, segmented stability
  with numeric value and glyph, beat dots, combo/score, tutorial mode.
- **Diegetic layer**: 2-beat pulse ring, four-state reticle with `LANZAR`/`NO`/`ENTREGAR`,
  contextual prompt, carried-item label, grade at the event, turbulence path.
- **Pause / options / end**: resume/restart/options/menu; volumes, calibration, fullscreen,
  reduce motion, HUD scale, haptics, reset; verdict + rank + stats + retry/new seed/menu.
- **Feel**: `Juice` autoload (trauma² shake in 4 px steps, wall-clock hitstop, flash, zoom,
  rumble, reduce-motion), `CameraRig` fixed at the room centre with shake/kick/zoom, input
  buffering, reversal-boosted movement, afterimages, dust, item shadow height.
- **Environment**: layered room (backdrop/floor/dressing/lighting/atmosphere/foreground), 6
  tinted light pools, 3 particle emitters, hazard shredders, deleted lamp-shaft artifacts.

## Measurements (owner UX phase)

| Metric | Value | Where |
|---|---|---|
| Test suite | **668 tests, 10,214 asserts** | GUT summary |
| Clean clone | `git clone --local` + full gate: **exit 0, all PASS** | `.work/clean.log` |
| Washer/chute tests | FSM transitions, coverage 4 phases, rank bounds, scene smoke | `tests/unit/test_washer*`, `test_delivery_chute.gd` |
| Screen flow tests | title, first-run, pause, options, end, app flow | `tests/unit/test_*_screen.gd`, `test_pause_overlay.gd`, `tests/integration/test_app_flow.gd` |
| Tutorial tests | 7 gates, skip, completion persistence, real level | `tests/unit/test_tutorial_*`, `tests/integration/test_tutorial_full.gd` |
| First 20 s | starter item ≤ 130 px from Pip, no shredder contact | `tests/integration/test_first_20s.gd` |
| Movement feel | stop 483 → **200 ms**, turnaround 267 → **167 ms**, accel 0→90 % in 150 ms | `docs/FEEL.md` |
| In-game frame | median **12.8 ms**, p95 ~14 ms, worst 43.7 FPS single frame | `docs/ENVIRONMENT.md` |
| Light budget | 6 pools + 1 chute + neutral fill (no lamp shafts) | `docs/ENVIRONMENT.md` |
| Tutorial length | ≈150 s at average pace, hard cap 240 s | `docs/TUTORIAL.md` |

## Known issues (honest)

- 60 FPS is met on the median on this llvmpipe box (12.8 ms) but not with headroom; the
  worst single frames drop into the 40s during explosions/particles.
- The tutorial's step 3–4 prompts were authored from the research sheet; the *human* playtest
  protocol in `docs/UX_BIBLE.md` §2 (5 strangers, 20 s) has not been run — the automated
  `test_first_20s` covers the affordances, not a person's comprehension.
- `%` and `×` glyphs in Silkscreen render ambiguously at small sizes; the UI avoids `%`
  (uses `/100`) and keeps `×` only at ≥20 px.
- Windows export/CI and the two §8.2 open questions remain M9 work.
- `docs/media/` before/after stills are from this box; the menu diorama's camera framing is
  authored for 1280×720 only.

## Next

1. Human playtest of the 20-second test + tutorial with 5 strangers.
2. Perf: move the atmosphere to a lower update rate or cut embers on the software renderer.
3. M9: balance sim across four phases, Windows export preset, §8.2 A/B toggles.

# Progress

Updated after every milestone/workstream. Times are local (America/Bogota).

## Milestone status

| Milestone | State | Evidence |
|---|---|---|
| M0 Bootstrap | **done** | project settings, autoloads, Input Map, GUT, CI, contracts, layout |
| M1 Beat engine & calibration | **done** | `BeatConductor` audio clock, 4 click tracks, overlay, calibration wizard, BeatLab |
| M2 Player & item physics | **done** | `Player`, `MagneticGrabber`, 5 behaviours, `PlayerSandbox`, 20-item stability test |
| M3 Belts, spawning, phases | **done** | belts, shredders, `SpawnSchedule`, `SpawnDirector`, 480 s sim, warp/phase wiring |
| M4 Washers | planned | FSM, holograms, turbulence, chute — next |
| M5 Shift flow | planned | real win/lose, cheats, final-load validation |
| M6 UI & flow | planned | title/pause/end/restart, pulse ring |
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
- Pure `SpawnSchedule` (seeded, deterministic) → **34/62/88/13 = 197** spawns / 480 s.
- `SpawnDirector.start/advance_to/seek/simulate`, alive cap 40, per-phase counts.
- Belts steer velocity at 900 px/s², sock multiplier; phase-3 reversal is pure and warns
  4 beats before flipping every 16 measures: **warnings on beats 60/124/188, flips on
  64/128/192** at 130 BPM.
- Shredders: −8 % stability, `fell_off_belt`, free, double-entry guard.
- 480 s virtual integration run, `tools/sim_run.gd` (197 total, exits 0).
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
| Spawns / 480 s | 197 (34/62/88/13), seed 1234 | `tools/sim_run.gd` |
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

## Next

1. **M4** — `WasherFSM`, `CosmicWasher`, holograms, turbulence/strike, chute, −12 % wrong
   washer, +3 % delivery. Use the shipped `mach_washer`, `ui_holo_icons`, `env_chute`,
   `fx_*` sheets.
2. **M5** — ShiftManager win/lose, score/combo at chute, F1–F4 cheats, Supernova flag.
3. **M6** — title, pause, end/restart, pulse ring, calibration from title.

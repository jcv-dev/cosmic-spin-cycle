# Progress

Updated after every milestone/workstream. Times are local (America/Bogota).

## Milestone status

| Milestone | State | Notes |
|---|---|---|
| M0 Bootstrap | **done** | Project settings, autoloads, Input Map, GUT, unit tests, CI, contracts, layout |
| M1 Beat engine & calibration | in progress | BeatConductor M0 base in place; M1 adds audio clock, calibration wizard, overlay |
| M2 Player & item physics | in progress | Item/player contracts frozen; M2 implements |
| M3 Belts, spawning, phases | in progress | Layout/phases contract frozen; M3 implements |
| M4 Washers | planned | |
| M5 Shift flow | planned | |
| M6 UI & flow | planned | |
| M7 Art integration | planned | Internet-sourced placeholder art pipeline started in parallel |
| M8 Audio | planned | Internet-sourced music/SFX pipeline started in parallel |
| M9 Balance/polish | planned | |

## M0 — done (2026-11-24)

- Godot 4.7.2 verified, `gl_compatibility`, 1280×720 canvas_items, 60 Hz physics, zero
  2D gravity, Nearest canvas texture filter.
- Autoloads: `Config`, `Settings`, `GameState`, `BeatConductor` (scene).
- Input Map: WASD/arrows + left stick, right-stick aim, Space/LMB/A grab-throw,
  Shift/RMB/B rhythm strike, Esc/Start pause, F1–F4 cheats, F10/Back debug overlay.
- GUT 9.6.1 vendored; 40 unit tests green in 0.44 s; headless smoke exits 0.
- `data/layout.json` frozen; `art/palette.json` (30 colours) frozen.
- Docs: CONTRACTS, COMMITS, DECISIONS, HANDOFF, PROVENANCE stub.

### Verification

```
godot --headless --path . --import            → 0
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
                                              → 40/40 passing
godot --headless --path . --quit              → 0
gdlint scripts tests tools                    → 0
gdformat --check scripts tests tools          → 0
```

### Next

- M1: click tracks, audio-locked clock, calibration math + wizard, debug overlay.
- M2: player, grabber, items, five behaviours, sandbox.
- M3: belts, shredder, phase table, spawn schedule, 480 s simulation.
- A1/A2: source CC0 art/music/fonts, adapt to contract, lint, provenance.

### Blockers

- None. Audio measurements (M1 done-when) still need a real Windows + Linux listening
  test by the owner; documented in `docs/CALIBRATION.md`.

## Measured numbers

| Metric | Value | Where |
|---|---|---|
| Unit suite wall time | 0.44 s | GUT summary, this box |
| Godot version | 4.7.2.stable.arch_linux.ed1daf0bf | `godot --version` |
| Physics tick | 60 Hz | project.godot |
| Render backend | llvmpipe (software) on this box | runtime log |

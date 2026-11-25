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

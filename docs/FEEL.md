# Game feel — implementation note

> Scope: movement, throw weight, impact/camera feedback and the accessibility rules from
> `docs/UX_BIBLE.md` §3.8, §8, §11 and §14. This note is the A/B manual: the numbers below
> were produced by the same probe before and after the pass, not remembered.

## 1. What changed, in one screen

- **Stopping** is a ~200 ms ease-out instead of a 483 ms glide (`FEEL_BRAKE_GAIN` scales the
  frozen `Config.PLAYER_FRICTION` decay; no Config change needed).
- **Turnarounds** snap: 1.6× acceleration while the input opposes velocity, held for 160 ms
  past the reversal (`FEEL_REVERSAL_BOOST`, `FEEL_TURN_BOOST_S`).
- **Pip is art-aligned**: the `CharacterBody2D` keeps a float position while the `Visual`
  node is snapped to the 4 px art grid; breathing, run lean and the dash never scale a
  sprite, they offset it in whole art pixels.
- **Frame-based secondary motion**: run cadence follows speed (`speed_scale`), a 2-frame
  directional lean, a 4-frame shadow squash, and a dust puff every second step
  (`FootFX`, pool of 6 particles per puff).
- **Dash**: instant (no anticipation), 3 additive afterimages 60 ms apart, a 4 px floor
  streak, a 2 px `Juice` shake, a 1.2 % zoom punch and a 70 ms pad rumble.
- **Grab**: a 60 ms magnet yank on the item's visual, a 1 px cyan tracer, a quiet click.
- **Input buffer**: `grab_throw` / `rhythm_strike` presses are buffered for 120 ms; strikes
  are graded at press time so the buffer never steals rhythm accuracy.
- **Aim**: 8-way snap only for stick aim (12° cone), plus a sticky compatible-washer reticle
  (`get_assisted_target()`) with a 2 px visual offset; the throw vector stays analog.
- **Throws** leave at an exact base speed (the hold-spring speed is cancelled at release),
  then a capped fraction of the player's velocity decays over 50 ms for follow-through.
  The shadow — never the sprite — arcs up to 24 px, grows and spins.
- **Landing**: dust, a 40 ms settle frame (1 art px down, shadow widened), a soft tick and a
  1-frame cyan ground ring on-beat. A non-MISS throw shows a 2 px dotted guide to the nearest
  compatible mouth for 180 ms.
- **Impact layer**: `Juice` autoload with trauma² shake (6 px cap, whole pixels), hitstop
  (90 ms cap, never stacks, unscaled release), 1-frame flash, zoom punch, rumble, and a
  reduce-motion kill switch bound to `Settings.settings_changed`.

## 2. Before / after measurements

Probe (committed): `godot --headless --path . -s tools/feel_probe.gd`.
It drives the real `Player.tscn` through 5 s of movement, a dash and 10 throws, and prints
`FEEL_PROBE key=value` lines.

| Metric | Before | After (SNAPPY) |
|---|---|---|
| Acceleration 0 → 90 % max | 150 ms | 150 ms |
| Stop from max to < 2 % | **483 ms** | **200 ms** |
| Turnaround +90 % → −90 % | **267 ms** | **167 ms** |
| Dash distance | 122 px | 122 px |
| PERFECT throw speed 4 frames after release | 1229 px/s | 1232 px/s |
| Steady process cost (after 2 s warm-up) | 0.34 ms | 0.14 ms |
| Steady physics cost (after 2 s warm-up) | 0.16 ms | 0.26 ms |

The throw speed looks unchanged because the probe throws from a standstill; the real
difference is **consistency**: before, a throw inherited the hold-spring velocity (up to
+720 px/s observed) and was pushed into the 1600 px/s clamp, so the same input produced
different throws. Now the launch is `THROW_SPEED × grade + capped carry`
(`tests/unit/test_item_feel.gd` covers both).

Cost caveat: the headless loop is paced at 60 FPS and `Performance.TIME_PROCESS` keeps a
rolling maximum, so absolute values are meaningless; only the before/after delta is useful,
and the first 120 frames (GDScript compilation) are excluded. Treat sub-0.5 ms deltas as
noise. The particle/afterimage budget stays inside the UX bible caps (≤ 24 dust particles
per puff system, 3 ghosts, 2 smear copies, no new raster assets).

## 3. A/B presets (recommended: SNAPPY)

Three movement profiles are selectable two ways:

```gdscript
# scripts/entities/Player.gd
const FEEL_PRESET := FeelPreset.SNAPPY   # SNAPPY | WEIGHTED | FLOATY
```

or at runtime `player.set_feel_preset(Player.FeelPreset.FLOATY)` from a debug menu. The
probe accepts `-- --preset=N` (0 = SNAPPY, 1 = WEIGHTED, 2 = FLOATY).

| Preset | Accel 90 % | Stop | Turnaround | Feel |
|---|---|---|---|---|
| Original build | 150 ms | 483 ms | 267 ms | icy glide, wide turn |
| **SNAPPY** (recommended) | 150 ms | 200 ms | 167 ms | responsive, still has weight |
| WEIGHTED | 167 ms | 333 ms | 250 ms | heavier load, longer commitment |
| FLOATY | 183 ms | 617 ms | 317 ms | loose/arcade drift |

Why SNAPPY: it is the only profile that lands inside the brief's stop window (180–250 ms)
while keeping a visible ease-out instead of a hard stop, and its 167 ms turnaround is fast
enough to feel intentional without reading as a teleport. WEIGHTED is the natural candidate
for a future `carrying gas giant/core` mode (not implemented here); FLOATY is the old feel
kept as a reference point.

## 4. Tunables

All of these are provisional constants in the owning file; the lead can promote the ones
that survive playtesting to `Config` (suggested names in the last column). None of them is
read from a scene, so a promoted constant can replace the local one mechanically.

### `scripts/entities/Player.gd`

| Constant | Default | Effect |
|---|---|---|
| `FEEL_REVERSAL_BOOST` | 1.6 | accel multiplier when input opposes velocity |
| `FEEL_TURN_BOOST_S` | 0.16 | how long the boost outlives the opposing half |
| `FEEL_BRAKE_GAIN` | 2.5 | multiplier on the frozen `Config.PLAYER_FRICTION` decay |
| `FEEL_BUFFER_S` | 0.12 | input buffer window |
| `FEEL_SNAP_ASSIST_DEG` | 12.0 | 8-way stick snap cone |
| `FEEL_ASSIST_ANGLE_DEG` | 18.0 | sticky-target cone |
| `FEEL_ASSIST_RANGE_PX` | 420.0 | sticky-target range |
| `FEEL_RETICLE_OFFSET` | 2.0 | visual reticle offset when assisted |
| `FEEL_STEP_DISTANCE_PX` | 48.0 | one step of travel; dust every second step |
| `FEEL_STEP_MIN_SPEED` | 40.0 | below this the feet are silent |
| `FEEL_IDLE_BREATH_S` | 0.62 | idle breath cadence |
| `FEEL_RUN_LEAN_S` | 0.09 | 2-frame run lean cadence |
| `FEEL_SHADOW_FRAME_S` | 0.09 | 4-frame shadow squash cadence |
| `FEEL_DASH_RUMBLE_MS` | 70 | pad rumble on dash |
| `dash_cooldown_s` | 0.24 | existing export, unchanged |

Suggested Config names: `PLAYER_TURN_BOOST`, `PLAYER_TURN_BOOST_S`, `PLAYER_BRAKE_GAIN`,
`INPUT_BUFFER_S`, `AIM_SNAP_DEG`, `AIM_ASSIST_CONE_DEG`, `AIM_ASSIST_RANGE_PX`,
`AIM_RETICLE_ASSIST_PX`, `FOOTSTEP_DISTANCE_PX`.

### `scripts/entities/FootFX.gd`

| Constant | Default | Effect |
|---|---|---|
| `DUST_AMOUNT` | 6 | particles per step puff |
| `DUST_LIFETIME` | 0.36 s | puff life |
| `GHOST_ALPHA` / `GHOST_LIFETIME` | 0.35 / 0.18 s | dash afterimages |
| `STREAK_LENGTH` / `STREAK_WIDTH` / `STREAK_LIFETIME` | 40 / 4 / 0.12 | floor streak |
| `TRACER_LIFETIME` | 0.07 s | grab tracer |
| `CLICK_VOLUME_DB` | −11 dB | grab click |

Suggested: `FOOT_DUST_*`, `DASH_GHOST_*`, `GRAB_TRACER_S`.

### `scripts/entities/LaundryItem.gd`

| Constant | Default | Effect |
|---|---|---|
| `FOLLOW_THROUGH_SCALE` / `FOLLOW_THROUGH_MAX` | 0.35 / 120 px/s | carried player velocity |
| `FOLLOW_THROUGH_DECAY_S` | 0.05 s | how fast the carry bleeds off |
| `AIR_ARC_PX` / `AIR_TIME_S` | 24 / 0.34 s | fake 2.5D arc |
| `SOCK_ARC_ACCEL` / `SOCK_ARC_DURATION_S` | 120 / 0.22 s | sock's tiny curve |
| `THROW_PITCH_HEAVY` / `THROW_PITCH_SOCK` | 0.85 / 1.1 | whoosh pitch |
| `GUIDE_RANGE_PX` / `GUIDE_DURATION_S` | 700 / 0.18 s | dotted assist guide |
| `HEAVY_SHAKE` / `HEAVY_SHAKE_S` | 0.58 / 0.09 | heavy-item camera kick (~2 px) |

### `scripts/entities/ItemVisual.gd`

`PULL_DURATION_S` 0.06 / `PULL_MAX_PX` 14 (grab yank), `SQUASH_DURATION_S` 0.04,
`SHADOW_OFFSET` (3, 5) down-right, `SHADOW_RADIUS_SCALE` 0.85, `SHADOW_FLATTEN` 0.38,
`SMEAR_OFFSET_PX` 3, `SMEAR_LIFETIME` 0.04, `GUIDE_DOT_STEP` 14.

### `scripts/autoload/Juice.gd`

`MAX_SHAKE_PX` 6, `MAX_HITSTOP_S` 0.09, `MAX_TRAUMA` 1, `MAX_PUNCH_ZOOM` 0.05.
Trauma decays linearly at `1 / duration`; amplitude is `trauma² × 6 px`, rounded.

### `scripts/main/CameraRig.gd`

`MAX_LEAD_PX` 54, `LEAD_VELOCITY_GAIN` 0.16, `LEAD_AIM_GAIN` 18, `DEADZONE_PX` 24,
`FOLLOW_SHARPNESS` 10/s, `KICK_DECAY` 9/s, `ZOOM_MIN` 0.97, `FLIGHT_ZOOM_THRESHOLD` 4,
`@export zoom_out_enabled` (true) and `zoom_out_amount` (0.03).

## 5. Wiring the lead still has to do

1. **Autoload** (after `Settings`, before or after `BeatConductor` — either works):

```ini
Juice="*res://scripts/autoload/Juice.gd"
```

2. **Replace MainLevel's bare camera** in `_build_camera()`; the rig binds itself to the
   first node in the `player` group, so call order does not matter:

```gdscript
func _build_camera() -> void:
    var rig := CameraRig.new()
    rig.name = "CameraRig"
    rig.position = Vector2(640, 360)
    rig.enabled = true
    add_child(rig)
    rig.setup(player)   # optional; auto-bind covers construction order
```

3. **HUD stream**: `player.get_assisted_target()` returns the sticky washer `Node` (or null)
   for reticle state; `player.get_buffered_action()` / `get_buffer_left()` are available for a
   debug readout only.
4. **Items**: `LaundryItem.height` is public (0…24) if the HUD ever wants it; the `landed`
   signal is new and additive.
5. **Do not** add a second `Camera2D`: the rig is the only camera and owns the zoom punch.

## 6. Evidence

- `docs/media/feel_player.png` — PlayerSandbox at 1280×720, captured with Movie Maker:

```bash
godot --path . --write-movie .work/movie/frame.png --fixed-fps 60 --resolution 1280x720 \
  --quit-after 50 res://scenes/dev/PlayerSandbox.tscn
```

  (The shared `tools/screenshot.gd` reports the compositor-scaled 1900×1068 buffer on this
  Wayland session; Movie Maker writes true viewport-size frames. The HUD's FPS figure is the
  offline render rate, not gameplay.)
  What to look at: Pip and the items are crisp on the 4 px grid, item shadows sit down-right
  of the body (light top-left), the core's shadow is no longer an all-around halo, and the
  aim reticle remains the sandbox's cyan line.
- Tests: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests
  -ginclude_subdirs -gexit` → 360 passing.

## 7. Known gaps / deliberate non-goals

- **Magnetic steering is not in this branch.** `docs/M2_PHYSICS.md` §8 says the on-beat
  assist needs washer mouths (M4). The dotted guide therefore points at the nearest
  compatible mouth and is suppressed on MISS, but it does not itself steer the item.
- `Juice` and `CameraRig` are inert until the lead wires them (above); every caller degrades
  gracefully when `/root/Juice` is absent, which is why the test suite runs without the
  autoload.
- `Juice.flash()` has no gameplay caller yet; it is ready for the M4/M5 explosion and
  wrong-washer feedback.
- Item **body** positions stay float (the frozen test asserts
  `visual.global_position == item.global_position`); only the sprite child is snapped.
- Item landing dust uses the shared CPUParticles2D path; in a dense 40-item scene it should
  be measured on llvmpipe before M9 (budget: ≤ 120 particles, ≤ 3 emitters — the static
  burst frees itself after 0.8 s).
- No screen-space shader was added: all effects are nodes, so the GL Compatibility budget is
  untouched.

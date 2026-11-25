# Environment pass — layers, budget and tuning

> Scope: the "dramatically richer" room pass and the living menu diorama
> (`docs/UX_BIBLE.md` §3.4–3.7, §14). Branch `ws/environment`, worktree
> `.worktrees/environment`. Everything procedural: **no new raster asset**, `assets/`
> untouched.

Media:

| File | Frame |
|---|---|
| `docs/media/env_before.png` | **in-game** (`Main.tscn --autostart=shift --env-bare`): the shipped greybox |
| `docs/media/env_after.png` | **in-game** (`Main.tscn --autostart=shift`): the pass installed |
| `docs/media/env_sandbox.png` | sandbox at 1280×720 with the washer/chute sheets (pre-M4 preview) |
| `docs/media/menu_diorama.png` | the title diorama at 1280×720 |

The two in-game stills share the camera, the HUD and the machine set, so the comparison
isolates the pass. They are captured at the compositor's 1900×1068 window (see §11).

---

## 1. What ships

| File | Role |
|---|---|
| `scripts/main/RoomBuilder.gd` | extended `build()` — installs the layer stack, returns it by name; `--env-bare` skips it |
| `scripts/environment/Backdrop.gd` | generated starfield + nebula + planet limb, 2 px/s drift |
| `scripts/environment/RoomDressing.gd` | floor story, machine dressing, foreground, display machinery |
| `scripts/environment/LightingRig.gd` | `CanvasModulate` + 6 tinted pools that pulse on the beat |
| `scripts/environment/Atmosphere.gd` | steam/dust/embers + additive belt rails and drum shimmer |
| `scripts/environment/Diorama.gd` | the title diorama (camera, machines, Pip, beacon, scrim) |
| `scripts/environment/Shredder.gd` | **visuals only** — hazard mouth, 2 px ring, `−8` chip (see §10) |
| `scenes/main/Diorama.tscn` | self-contained menu scene (app-flow instances it) |
| `scenes/dev/EnvironmentSandbox.tscn` | dev/screenshot scene (`--bare` reproduces the greybox) |
| `tools/fps_probe.gd` | frame probe: FPS min/avg, frame ms, draw calls |
| `tests/unit/test_{backdrop,room_dressing,lighting_rig,diorama}.gd` | 43 new tests |

`RoomBuilder.build(root)` keeps its signature and returns `walls` as before; the new keys
are `backdrop`, `floor`, `dressing`, `belt_glow`, `belt_shadow`, `atmosphere`, `lighting`,
`foreground`.

## 2. Layer stack

| z | Node | Content | Draw cost |
|---|---|---|---|
| −100 | `RoomBackground` | shipped `env_room` sheet (floor, walls, portholes) | 1 opaque quad |
| −95 | `Backdrop/Stars` | one 640×180 sheet: 90 stars + 2 blue-grey nebula bands + planet limb, drifts 2 px/s | 1 blended quad |
| −90 | `Floor` + `FloorDecals` | grime, puddles + gloss, wet streaks, hazard stripes, dashed routes, scuffs, delivery zone, wall shadow, contact/cast shadows | ~110 small quads |
| −80 | `RoomDressing` | cable runs + plugs, vent grilles, mop/bucket, basket stack, `TURNOS` sign, 2 valve wheels, floor drain, wall seams/bolts | ~55 small quads |
| −5 | `Belts` | `ConveyorBelt` scenes (unchanged) | |
| −4 | `Shredders` | `Shredder` scenes: hazard mouth, 2 px ring at 55 %, `−8` chip | |
| −3 | `BeltShade` | 30 % dark wash so the machines and the chute stay the brightest things | 3 quads |
| 0 | `Machines` | display washers + chute (sandbox/diorama only; the shift uses M4 entities) | |
| 2 | `PanelReadouts` | one recessed 3-bar readout per cabinet | ~20 |
| 5 | `Items` / `DioramaItems` | laundry | |
| 6 | light emitters | 4 washer pools + chute pool + neutral spawn fill | 6 quads |
| 8 | `Atmosphere` | 3 `CPUParticles2D` emitters (36 steam + 24 dust + 4 embers) | |
| 9 | `BeltGlow` | additive rails at each belt edge + drum-window shimmer | 10 quads |
| 19 | `MenuScrim` (diorama only) | 3-step screen-anchored scrim under the title menu | 3 |
| 20 | `Foreground` | one generated overlay (vignette + floor falloff + 150 dust motes) + ceiling pipes, lamp cords and glow rings | 1 quad + ~14 |

There are **no hand-drawn light quads**: the lamp shafts that produced the hard-edged
triangles in the first integrated build were deleted (`test_atmosphere_has_no_hard_edged_light_shafts`).
All light is either a radial gradient sprite, the baked backdrop, or a `_draw()` element
that sits on the floor.

Integers only: decal vertices snap to 4 world px (`RoomDressing.SNAP`), node positions are
rounded, the star drift is rounded, emitter positions are rounded. The only non-integer
transforms are the procedural light gradients (512 px radial texture scaled by
`radius / 256`) — no art sprite is ever scaled by anything but ×4 or rotated.

## 3. Generated textures (no raster assets)

Built once, cached in `static var`, so repeated builds share one texture (asserted by
`test_*_five_builds_*`).

| Texture | Size | Generator | Cached in |
|---|---|---|---|
| backdrop sheet (stars + nebula + limb) | 640×180 | `Backdrop.star_texture()` | `_star_texture` |
| nebula tile | 320×180 | `Backdrop.nebula_tile()` | `_nebula_tile` |
| radial light gradient | 512×512 | `LightingRig.radial_texture()` | `_radial` |
| soft particle puff | 16×16 | `Atmosphere.puff_texture()` | `_puff` |
| foreground overlay (vignette + dust) | 320×180 | `RoomDressing.overlay_texture()` | `_overlay_texture` |

Colour discipline: the nebula is **blue-grey only** (`blue_1` 14 %, `space_haze` 10 %) — the
plum band that pushed the floor toward magenta is gone.

## 4. Lighting — steel stays steel

Two integrated-view problems drove this section, and both are now measured, not guessed:

1. **8 `PointLight2D` cost 56 ms/frame** on llvmpipe (lit shader on every canvas item plus
   a screen-sized light buffer). Replaced with additive gradient sprites; the API is
   unchanged and `LightingRig.USE_POINT_LIGHTS = true` restores real lights.
2. **The tint + saturated pools turned the floor violet.** `CanvasModulate` is now
   near-neutral `(0.74, 0.76, 0.80)` (darkens; barely cools), the two cyan overhead lamps
   are gone, and the pools use the deeper `_2` ramp at low energy so the structure keeps
   its own `space_*` blue-grey.

Current light budget:

| Emitter | Radius | Energy | Colour |
|---|---|---|---|
| 4 × washer pool (mouth) | 150 | 0.24 (+0.06 beat) | requirement ramp `_2` (red/blue/red/blue default) |
| chute pool | 170 | 0.42 | `clean_green` |
| spawn fill | 180 | 0.10 | `metal_3` (neutral) |

Every emitter is anchored to a machine, the chute or the player spawn
(`test_coloured_light_stays_near_the_machines`). Measured floor samples in the integrated
frame (1900×1068 capture, floor band): `G − B ≈ −20` everywhere, `R − G` between −6 and +7 —
blue-grey outside a washer pool, warm only inside it.

Pulse: instant attack, 0.28 s decay from `BeatConductor` (`pulse_bpm = 0`), or the rig's own
clock when `pulse_bpm > 0` (diorama: 90 BPM). `Settings.reduce_motion` pins every emitter to
its base value.

## 5. Foreground / play-lane rule

The play lane (`x 120…1160`, `y 120…600`) keeps **≤ 8 % alpha** from the foreground: the
overlay's vignette reaches zero exactly at the lane boundary and only the 3–5 % dust motes
are inside. The ceiling pipes, lamp cords and rings live in the margins.
`test_foreground_specs_never_cover_the_play_lane` and
`test_overlay_texture_is_cached_and_lane_safe` enforce it, and
`test_overlay_never_covers_the_chute_ring_or_the_drums` samples the beacon ring and the four
drum windows (< 0.07 alpha).

## 6. Performance (measured)

Box: llvmpipe (`Mesa 26.3.1`, `llvmpipe LLVM 23.1.5`), GL Compatibility, 1280×720.
`tools/fps_probe.gd` renders into a fixed 1280×720 `SubViewport` (the Wayland compositor
resizes the real window, which silently changed the resolution in an earlier run).

Method: v-sync off, 20 s runs × 3 per configuration, **median** of the three. This box is
shared and single runs vary by up to 2×.

| Scene | Frame ms (median) | FPS (median) | Draw calls |
|---|---|---|---|
| **in-game, `--env-bare`** (shipped room + HUD + player) | **7.70** | 130 | 160 |
| **in-game, full pass** | **12.82** | 78 | 262 |
| `EnvironmentSandbox` (with machines) | 11.69 | 86 | 263 |
| `Diorama` (menu) | 12.19 | 82 | 168 |

The pass costs **≈ +5.1 ms/frame** in the integrated game (7.70 → 12.82 ms), which leaves
~3.9 ms of the 16.7 ms budget for M4/M5 systems on this box. The menu diorama is 12.19 ms
despite the 1.25× zoom, because it drops the third belt.

### 6.1 Confirmation checklist

* **FPS min/avg at 1280×720** — in-game **78 avg**, sandbox 86, diorama 82 (medians above).
  Worst single frame over a 60 s in-game run: **43.7 FPS** (sandbox), 31.6 (diorama) — single
  spikes on a shared box, not a sustained drop.
* **`PointLight2D` count** — **0** on the shipped path, **6** additive emitters. Flipping
  `USE_POINT_LIGHTS` gives exactly 6 real lights, never more than the 8 budget.
  `test_light_budget_is_eight_emitters_and_zero_point_lights` asserts the cap and the zero.
* **Particles** — 3 `CPUParticles2D` emitters, **64 particles**: steam 36 (one emitter, 9 per
  washer, `STEAM_BOOSTED = 60` while TURBULENT), dust 24, embers 4. Under UX §14's 3 emitters
  / 120 particles.
* **`Settings.reduce_motion`** — `LightingRig.beat_envelope()` returns 0 (emitters pinned to
  base energy), `Atmosphere` stops all three emitters and pauses the ember timer
  (`particles_active()` false), `BeltGlow` returns a 0 envelope, the diorama beacon stops
  stepping and Pip's `Z` fades out. Camera pan continues (it is not juice). Proven by
  `test_reduce_motion_pins_the_pulse` and `test_reduce_motion_stops_the_atmosphere`.
* **No hard-edged light geometry** — shafts removed; the only translucent geometry is the
  full-screen overlay, the baked backdrop and floor-level decals.
  `test_atmosphere_has_no_hard_edged_light_shafts` fails if a hand-drawn light quad returns.

Approximate per-feature cost (±0.5 ms on this box, measured by hiding one layer at a time
with `--no-lights`, `--no-backdrop`, `--no-dressing`, `--no-floordecals`, `--no-glow`,
`--no-atmosphere`):

| Feature | Δ ms |
|---|---|
| 6 light emitters + `CanvasModulate` | ~1.4 |
| backdrop (one blended full-screen quad) | ~0.8 |
| foreground overlay (one blended full-screen quad) | ~1.3 |
| floor decals (~110 quads) | ~1.5 |
| dressing + foreground props (~69 quads) | ~1.3 |
| particles, belt rails, readouts, scrim | ~0.6 |

Actions taken because of the budget:

1. `PointLight2D` → additive emitters (56 ms → 1.4 ms).
2. Nebula + planet baked into the star sheet: 4 polygons (~1.7 screens) → 1 quad.
3. Vignette + floor falloff + dust merged into one 320×180 overlay: 4 passes → 1.
4. Washer pools 260 → 150 px, cold lamps deleted, chute 220 → 170 px.
5. Dropped the separate "floor spill" sprites and the lamp shafts.
6. Belt glow redraws only when the beat envelope changes by > 0.02.

**Honest limit:** the in-game frame is 12.8 ms on the *median*, so 60 FPS is reachable now,
but the p95 in a busy frame is ~14 ms: M4 (4 washers with holograms) and M5 (items, effects)
have ~4 ms of headroom. Treat UX §14's 60 FPS as a hardware-GL target and this box as 55–60.

## 7. Rebuild, screenshot, measure

```bash
cd /home/moravak/proyecto/.worktrees/environment
export XDG_DATA_HOME="$PWD/.work/xdg/data" XDG_CACHE_HOME="$PWD/.work/xdg/cache" \
       XDG_CONFIG_HOME="$PWD/.work/xdg/config" HOME="/home/moravak/proyecto/.work/home"

godot --headless --path . --import

SHOT='godot --path . -s tools/screenshot.gd --resolution 1280x720 --audio-driver Dummy
      --display-driver wayland --rendering-method gl_compatibility --'

# in-game after / before (same camera, same HUD)
$SHOT --scene=res://scenes/main/Main.tscn --autostart=shift --out=res://docs/media/env_after.png  --frames=40
$SHOT --scene=res://scenes/main/Main.tscn --autostart=shift --env-bare --out=res://docs/media/env_before.png --frames=40
# machines preview + menu
$SHOT --scene=res://scenes/dev/EnvironmentSandbox.tscn --out=res://docs/media/env_sandbox.png --frames=40
$SHOT --scene=res://scenes/main/Diorama.tscn --out=res://docs/media/menu_diorama.png --frames=70

# frame probe (in-game is the frame that matters)
godot --path . -s tools/fps_probe.gd --audio-driver Dummy --display-driver wayland \
  --rendering-method gl_compatibility \
  -- --scene=res://scenes/main/Main.tscn --autostart=shift --seconds=60 --size=1280x720
```

A/B switches: `--env-bare` (all new layers off, in-game), `--bare` (sandbox), `--no-lights`,
`--no-backdrop`, `--no-dressing`, `--no-floordecals`, `--no-glow`, `--no-beltshade`,
`--no-atmosphere`. Sandbox keys: `1`–`4` retint pools, `H` hides dressing, `L` hides lights.

## 8. Tuning knobs

| Constant | Default | Effect |
|---|---|---|
| `RoomDressing.SEED` | `20261124` | grime shape/placement, grease smear |
| `RoomDressing.SNAP` | `4.0` | decal vertex grid (1 art px) |
| `RoomDressing.GRIME_COUNT` / `PUDDLES` | 6 / 2 | floor story density |
| `RoomDressing.SIGN_RECT` | `(48,12,24,9)` art px | 96×36 px `TURNOS` sign on the top band |
| `RoomDressing.MACHINE_ALBEDO` | `(0.87, 0.88, 0.93)` | cabinets secondary to the chute |
| `Backdrop.STAR_COUNT` / `DRIFT_PX_S` | 90 / 2.0 | starfield density and parallax |
| `LightingRig.WASHER_RADIUS` / `_ENERGY` / `_PULSE` | 150 / 0.24 / 0.06 | pool size, base energy, beat amplitude |
| `LightingRig.CHUTE_ENERGY` | 0.42 | the destination gets the most light |
| `LightingRig.ROOM_TINT` | `(0.74, 0.76, 0.80)` | how dark the room sits (near-neutral) |
| `LightingRig.USE_POINT_LIGHTS` | `false` | switch to 6 real `PointLight2D` |
| `LightingRig.PULSE_DECAY` | 0.28 s | neon decay after each beat |
| `Atmosphere.STEAM_AMOUNT` / `BOOSTED` | 36 / 60 | calm vs TURBULENT steam |
| `Atmosphere.RAIL_ALPHA_MIN/MAX` | 0.05 / 0.16 | belt neon breathing |
| `Diorama.CAMERA_ZOOM` | 1.25 | 1 art px = 5 screen px exactly |
| `Diorama.CAMERA_HOME` | `(640, 316)` | centred; top belt fully in frame |
| `Diorama.PAN_X` / `PAN_Y` / `PAN_PERIOD_S` | 18 / 6 / 24 | camera drift (worst case crops 2 world px) |
| `Diorama.SCRIM_STEPS` / `SCRIM_ALPHAS` | `[160,320,470]` / `[.34,.20,.09]` | quiet left third, stops before the chute ring |
| `Diorama.AMBIENT_BPM` | 90 | menu pulse and beacon step |

## 9. What the lead must wire in `MainLevel`

Nothing is required for the room to look like `env_after.png`. Optional hooks:

```gdscript
var lighting := nodes["lighting"] as LightingRig
var atmosphere := nodes["atmosphere"] as Atmosphere
var glow := nodes["belt_glow"] as Node2D            # has set_phase_palette()

# on phase / washer-assignment change (M4/M5):
lighting.set_phase_palette([&"red", &"blue", &"yellow", &"red"])
glow.call("set_phase_palette", [&"red", &"blue", &"yellow", &"red"])

# on TURBULENT enter/exit:
atmosphere.set_steam_boosted(true)

# title screen:
var diorama := load("res://scenes/main/Diorama.tscn").instantiate()
diorama.set_paused(true)     # while hidden
diorama.play_intro()         # 1.2 s camera settle when returning from a shift
```

`Diorama` never starts `BeatConductor`; its 90 BPM ambient clock is local. It also dims its
own left third (`MenuScrim`, a camera child) and trims the cabinet albedo — do **not** add a
second title scrim.

## 10. Deviations from the brief

| Brief | Shipped | Why |
|---|---|---|
| 8 × `PointLight2D` | 6 additive gradient emitters (+ flag for 6 real lights) | 56 ms → 1.4 ms/frame measured |
| washer pool radius 260, energy 0.5 | 150 px, 0.24 | the owner's integrated-view rule: colour within ~180 px, energy ≤ 0.45 |
| cold overhead lamps (funk_cyan) | removed | cyan over red/blue pools was the source of the violet floor |
| lamp shafts (§ atmosphere) | removed entirely | straight edges read as geometry, not light |
| `Shredder.gd` was read-only for this workstream | **edited, visuals only** (`_draw` + two painters) | the owner asked for the hazard re-skin; the file is not on the forbidden list and behaviour is untouched (`test_shredder.gd` still green) |
| `TURNOS` sign 160 px, yellow on dark | 96 px, `metal_2` paper with dark ink, y 48–84 | owner: ≤ 96 px, dim paper, top band |
| diorama zoom 1.15 | 1.25 | 1.15 gives 4.6 screen px per art px and shimmers |
| diorama ±18 px pan + right offset | centred camera, screen-anchored 3-step scrim | +90 px clipped the left cabinets in half |
| `env_before.png` from `main` | same in-game scene with `--env-bare` | identical camera/HUD isolates the pass |
| diorama dust at 5 % in the lane | unchanged | the lane must stay legible (§3.6.6) |

## 11. Known issues

- The Wayland window comes up at **1900×1142** on this desktop and `canvas_items` stretch
  upscales it **linearly**, so the in-game captures (`env_before/after.png`) are soft and
  every 1280×720 canvas looks soft in a real window here. The sandbox/diorama stills are
  pinned to exactly 1280×720. Fixing it belongs to `project.godot`, which this workstream
  may not touch.
- `MainLevel` has no washers or chute yet (M4), so the four pools currently light empty floor
  and the chute pool marks an empty spot. In the sandbox/diorama they sit under machines.
- M4 should call `set_phase_palette` when washer requirements change; until then the pools
  stay red/blue/red/blue and are not tied to the holograms.
- p95 in-game is ~14 ms: the pass is at the 60 Hz budget on the median, not with headroom to
  spare. The next 4 ms belong to M4/M5.

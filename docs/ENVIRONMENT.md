# Environment pass — layers, budget and tuning

> Scope: the "dramatically richer" room pass and the living menu diorama
> (`docs/UX_BIBLE.md` §3.4–3.7, §14). Branch `ws/environment`, worktree
> `.worktrees/environment`. Everything here is procedural: **no new raster asset** was
> added, and `assets/` is untouched.

Media: `docs/media/env_before.png` (the pass disabled, same camera and machinery),
`docs/media/env_after.png`, `docs/media/menu_diorama.png`.

---

## 1. What ships

| File | Role |
|---|---|
| `scripts/main/RoomBuilder.gd` | extended `build()` — installs the whole layer stack, returns it by name |
| `scripts/environment/Backdrop.gd` | generated starfield + nebula + planet limb, 2 px/s drift |
| `scripts/environment/RoomDressing.gd` | floor story, machine dressing, foreground, display machinery |
| `scripts/environment/LightingRig.gd` | `CanvasModulate` + 8 tinted pools that pulse on the beat |
| `scripts/environment/Atmosphere.gd` | steam/dust/embers, additive belt rails + drum shimmer, lamp shafts |
| `scripts/environment/Diorama.gd` | the title diorama (camera, machines, Pip, beacon) |
| `scenes/main/Diorama.tscn` | self-contained menu scene (app-flow instances it) |
| `scenes/dev/EnvironmentSandbox.tscn` | dev/screenshot scene (`--bare` reproduces the greybox) |
| `tools/fps_probe.gd` | 60 s frame probe (FPS min/avg, frame ms, draw calls) |
| `tests/unit/test_backdrop.gd` · `test_room_dressing.gd` · `test_lighting_rig.gd` · `test_diorama.gd` | 35 new tests |

`RoomBuilder.build(root)` keeps its old signature and returns the wall node as `walls`; the
new keys are `backdrop`, `floor`, `dressing`, `belt_glow`, `belt_shadow`, `atmosphere`,
`lighting`, `foreground`.

## 2. Layer stack

| z | Node | Content | Draw cost |
|---|---|---|---|
| −100 | `RoomBackground` | shipped `env_room` sheet (floor, walls, portholes) | 1 opaque quad |
| −95 | `Backdrop/Stars` | one 640×180 sheet: 90 stars + 2 nebula bands + planet limb, drifts 2 px/s | 1 blended quad |
| −90 | `Floor` + `FloorDecals` | grime, puddles + gloss, wet streaks, hazard stripes, dashed routes, scuffs, delivery zone, wall shadow, contact/cast shadows | ~110 small quads |
| −80 | `RoomDressing` | cable runs + plugs, vent grilles, mop/bucket, basket stack, `TURNOS` sign, 2 valve wheels, floor drain, wall seams/bolts | ~55 small quads |
| −5 | `Belts` | `ConveyorBelt` scenes (unchanged) | |
| −4 | `Shredders` | `Shredder` scenes (unchanged) | |
| −3 | `BeltShade` | 30 % dark wash so the washers/chute stay the brightest things | 3 quads |
| 0 | `Machines` | display washers + chute (sandbox/diorama only; the shift uses M4 entities) | |
| 5 | `Items` / `DioramaItems` | laundry | |
| 6 | light emitters | 4 washer pools, chute pool, 2 cold lamps, warm spawn lamp | 8 quads (+2 shafts) |
| 8 | `Atmosphere` | 3 `CPUParticles2D` emitters (36 steam + 24 dust + 4 embers) | |
| 9 | `BeltGlow` | additive rails at each belt edge + drum-window shimmer | 10 quads |
| 20 | `Foreground` | one generated overlay (vignette + floor falloff + 150 dust motes) + ceiling pipes, lamp cords and glow rings | 1 quad + ~14 |

Integers only: decal vertices snap to 4 world px (`RoomDressing.SNAP`), every node position
is rounded, the star drift is rounded, and the light emitter positions are rounded. The only
non-integer transforms are the procedural light gradients (a 512 px radial texture scaled by
`radius / 256`) — no art sprite is ever scaled by anything but ×4 or rotated.

## 3. Generated textures (no raster assets)

All are built once and cached in `static var`, so five room builds share one texture
(asserted by `test_*_five_builds_*`).

| Texture | Size | Generator | Cached in |
|---|---|---|---|
| backdrop sheet (stars + nebula + limb) | 640×180 | `Backdrop.star_texture()` | `_star_texture` |
| nebula tile | 320×180 | `Backdrop.nebula_tile()` | `_nebula_tile` |
| radial light gradient | 512×512 | `LightingRig.radial_texture()` | `_radial` |
| soft particle puff | 16×16 | `Atmosphere.puff_texture()` | `_puff` |
| foreground overlay (vignette + dust) | 320×180 | `RoomDressing.overlay_texture()` | `_overlay_texture` |

Star layout is seeded (`Backdrop.SEED`), so two runs are byte-identical (unit-tested).

## 4. Lighting — why additive emitters, not `PointLight2D`

`docs/UX_BIBLE.md` §3.5 specifies a `CanvasModulate` plus ≤ 8 `PointLight2D`. That was
implemented first and **measured 56 ms/frame on this box** — with 8 lights every canvas item
goes through the lit shader and GL Compatibility pays for a screen-sized light buffer:

| Config | Frame ms (1280×720, llvmpipe) |
|---|---|
| bare room, no env pass | 8.2 |
| full pass, 8 × `PointLight2D` | **70.1** |
| full pass, `PointLight2D` hidden | 14.4 (nothing but the tint) |
| full pass, additive gradient emitters | **14.4** (current) |

So the rig draws the same pools as **additive gradient sprites** (`BLEND_MODE_ADD`) and
keeps the `CanvasModulate` tint. `LightingRig.USE_POINT_LIGHTS = true` restores the real
lights on hardware GL in one line. The public API is unchanged: `set_phase_palette()`,
`pools()`, `lights()`, `beat_envelope()`, `room_tint()`.

Pulse: instant attack, 0.28 s decay from `BeatConductor` (`pulse_bpm = 0`), or from the
rig's own clock when `pulse_bpm > 0` (the diorama uses 90 BPM). `Settings.reduce_motion`
pins every emitter to its base value.

## 5. Foreground / play-lane rule

The play lane (`x 120…1160`, `y 120…600`) keeps **≤ 8 % alpha** from the foreground: the
overlay's vignette reaches zero exactly at the lane boundary and only the 3–5 % dust motes
are inside. Everything else (vignette, floor falloff, ceiling pipes, lamp cords and rings)
lives in the margins. `test_foreground_specs_never_cover_the_play_lane` and
`test_overlay_texture_is_cached_and_lane_safe` enforce it.

## 6. Performance (measured)

Box: llvmpipe (`Mesa 26.3.1`, `llvmpipe LLVM 23.1.5`), GL Compatibility, 1280×720,
`tools/fps_probe.gd` renders into a fixed 1280×720 `SubViewport` (the Wayland compositor
resizes the real window, which silently changed the resolution in an earlier run).

60 s runs, v-sync off:

| Scene | FPS avg | FPS min | Frame ms avg | p95 | p99 | Draw calls |
|---|---|---|---|---|---|---|
| `--bare` (greybox room only) | 154.5 | 28.8 | 6.47 | 7.41 | 8.73 | 148 |
| `EnvironmentSandbox` (full pass) | 69.4 | 22.6 | 14.40 | 17.52 | 20.83 | 254 |
| `Diorama` (menu) | 76.1 | 29.5 | 13.15 | 16.67 | 18.81 | 199 |

So the pass costs **+7.9 ms/frame** over the shipped room, and the menu diorama costs
**+6.7 ms** — the diorama adds nothing measurable over the sandbox (it drops the third belt
and adds the beacon/Pip/items). Both clear 60 FPS on average; the p95 sits at ~16.7 ms, so
the frame is at the 60 Hz budget with the room alone, and the ~100 GPU-less draw calls of
the shipped belts/washers are the bigger half of the bill.

Approximate per-feature cost (20 s runs, ±0.5 ms on this noisy box):

| Feature | Δ ms |
|---|---|
| 8 light emitters + `CanvasModulate` | ~1.8 |
| backdrop (one blended full-screen quad) | ~0.8 |
| foreground overlay (one blended full-screen quad) | ~1.3 |
| floor decals (~110 quads) | ~1.5 |
| dressing + foreground props (~69 quads) | ~1.5 |
| particles, shafts, belt rails | ~0.6 |

Actions taken because of the budget (each is in the code with the reason):

1. `PointLight2D` → additive emitters (56 ms → 1.8 ms).
2. Nebula + planet baked into the star sheet: 4 polygons (~1.7 screens) → 1 quad.
3. Vignette + floor falloff + dust merged into one 320×180 overlay: 4 passes → 1.
4. Washer pools 260 → 220 px, cold lamps 420 → 260 px, chute 220 → 180 px.
5. Dropped the separate "floor spill" sprites (the emitters already tint the floor).
6. Belt glow redraws only when the beat envelope changes by > 0.02.

**Honest limit:** 60 FPS is reachable *with the room only*. The full game adds physics,
items and the HUD on top of these 14.4 ms, so the lead should expect ~45–55 FPS on this
llvmpipe box and treat §14 of the UX bible as a hardware-GL target. Nothing in this pass is
needed for correctness: `RoomBuilder` still builds without any of it if a layer is hidden.

## 7. Rebuild, screenshot, measure

```bash
cd /home/moravak/proyecto/.worktrees/environment
export XDG_DATA_HOME="$PWD/.work/xdg/data" XDG_CACHE_HOME="$PWD/.work/xdg/cache" \
       XDG_CONFIG_HOME="$PWD/.work/xdg/config" HOME="/home/moravak/proyecto/.work/home"

godot --headless --path . --import

# after / before / menu stills (1280×720 exactly)
godot --path . -s tools/screenshot.gd --resolution 1280x720 --audio-driver Dummy \
  --display-driver wayland --rendering-method gl_compatibility \
  -- --scene=res://scenes/dev/EnvironmentSandbox.tscn --out=res://docs/media/env_after.png --frames=40
godot --path . -s tools/screenshot.gd ... -- --scene=res://scenes/dev/EnvironmentSandbox.tscn \
  --out=res://docs/media/env_before.png --frames=40 --bare
godot --path . -s tools/screenshot.gd ... -- --scene=res://scenes/main/Diorama.tscn \
  --out=res://docs/media/menu_diorama.png --frames=70

# 60 s frame probe
godot --path . -s tools/fps_probe.gd --audio-driver Dummy --display-driver wayland \
  --rendering-method gl_compatibility \
  -- --scene=res://scenes/dev/EnvironmentSandbox.tscn --seconds=60 --size=1280x720
```

Sandbox keys: `1`–`4` retint the pools, `H` hides the dressing, `L` hides the light rig.
Probe/sandbox flags for A/B work: `--bare`, `--no-lights`, `--no-backdrop`,
`--no-dressing`, `--no-floordecals`, `--no-glow`, `--no-beltshade`, `--no-atmosphere`.

## 8. Tuning knobs

| Constant | Default | Effect |
|---|---|---|
| `RoomDressing.SEED` | `20261124` | grime shape/placement, grease smear |
| `RoomDressing.SNAP` | `4.0` | decal vertex grid (1 art px) |
| `RoomDressing.GRIME_COUNT` / `PUDDLES` | 6 / 2 | floor story density |
| `Backdrop.STAR_COUNT` / `DRIFT_PX_S` | 90 / 2.0 | starfield density and parallax |
| `LightingRig.WASHER_RADIUS` / `_ENERGY` / `_PULSE` | 220 / 0.34 / 0.07 | pool size, base energy, beat amplitude |
| `LightingRig.ROOM_TINT` | `(0.70, 0.72, 0.84)` | how dark/cool the room sits |
| `LightingRig.PULSE_DECAY` | 0.28 s | neon decay after each beat |
| `Atmosphere.STEAM_AMOUNT` / `BOOSTED` | 36 / 60 | calm vs TURBULENT steam |
| `Atmosphere.RAIL_ALPHA_MIN/MAX` | 0.05 / 0.16 | belt neon breathing |
| `Diorama.CAMERA_ZOOM` | 1.25 | 1 art px = 5 screen px exactly |
| `Diorama.PAN_X` / `PAN_Y` / `PAN_PERIOD_S` | 18 / 6 / 24 | drift of the menu camera |
| `Diorama.AMBIENT_BPM` | 90 | menu pulse and beacon step |

## 9. What the lead must wire in `MainLevel`

Nothing is required for the room to look like `env_after.png` — `RoomBuilder.build()`
installs the pass. Optional hooks:

```gdscript
# after RoomBuilder.build(self)
var lighting := nodes["lighting"] as LightingRig
var atmosphere := nodes["atmosphere"] as Atmosphere
var glow := nodes["belt_glow"] as Node2D            # has set_phase_palette()

# on phase / washer-assignment change (M4/M5):
lighting.set_phase_palette([&"red", &"blue", &"yellow", &"red"])
glow.call("set_phase_palette", [&"red", &"blue", &"yellow", &"red"])  # inner class

# on TURBULENT enter/exit:
atmosphere.set_steam_boosted(true)

# title screen:
var diorama := load("res://scenes/main/Diorama.tscn").instantiate()
diorama.set_paused(true)     # while hidden
diorama.play_intro()         # 1.2 s camera settle when returning from a shift
```

`Diorama` never starts `BeatConductor`; its 90 BPM ambient clock is local.

## 10. Deviations from the brief

| Brief | Shipped | Why |
|---|---|---|
| 8 × `PointLight2D` | 8 additive gradient emitters (+ `USE_POINT_LIGHTS` flag) | 56 ms → 1.8 ms/frame measured |
| washer pool radius 260 | 220 | fill budget (one 512² quad per pool) |
| diorama zoom 1.15 | 1.25 | 1.15 gives 4.6 screen px per art px and shimmers; 1.25 is exactly 5 |
| diorama < 2.5 ms/frame | 13.15 ms total, +6.7 ms over the bare room | the shipped room alone is 6.47 ms on llvmpipe; see §6 |
| foreground dust layer | dust motes at ≤ 5 % inside the lane, none of the vignette | the lane must stay legible (§3.6.6) |
| "2 px" belt rails | 1 art px (4 world px) | the pixel grid has no 2 px unit in world space |
| `env_before.png` from `main` | same sandbox with `--bare` | identical camera/machinery isolates the pass |

## 11. Known issues

- The Wayland window comes up at 1900×1142 on this desktop and `canvas_items` stretch
  upscales it with linear filtering, so **any** 1280×720 canvas looks soft in a real window
  here. Screenshots are pinned to exactly 1280×720 (the sandbox and the probe force it).
  Fixing the window scale belongs to `project.godot`, which this workstream may not touch.
- `MainLevel` has no washers yet (M4), so the four pools currently light empty floor in the
  real level; the sandbox and the diorama show them as intended.
- M4 should call `set_phase_palette` when washer requirements change; until then the pools
  stay red/blue/red/blue.

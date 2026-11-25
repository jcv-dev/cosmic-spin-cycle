# M2 — Player & item physics (greybox)

Status: **complete** on branch `m2-physics`. This document is the contract between the M2
code and the sessions that integrate it (M3 belts, M4 washers, M5 shift flow).

Scope of this workstream: `Player`, `MagneticGrabber`, `LaundryItem`, `ItemVisual`,
`ItemData`/`ItemDatabase`, `data/items.tres`, `scenes/entities/*`, `scenes/dev/PlayerSandbox.*`
and the `test_player_*` / `test_item_*` / `test_physics_*` suites.

## 1. Player (`scripts/entities/Player.gd`, `scenes/entities/Player.tscn`)

Root `CharacterBody2D`, `collision_layer = PLAYER (2)`, `collision_mask = WORLD (1)`,
`motion_mode = FLOATING`. Children are the frozen contract nodes: `Visual`, `CollisionShape2D`
(circle r 14), `HoldAnchor`, `Grabber`, `AimIndicator`.

| Behaviour | Rule |
|---|---|
| Acceleration | `velocity.move_toward(input * 340, 2400 * delta)` |
| Top speed | 340 px/s; diagonals are normalised by `Input.get_vector` |
| Idle friction | `v *= pow(1 - 0.12, 60 * delta)`, then snap to rest below 2.5 % of max speed |
| Aim | mouse motion **or mouse button** for 1.2 s after the event, else right stick (`aim_*`); `set_aim_direction()` overrides for tests/tools |
| Hold point | `global_position + aim_direction * 48` |
| Dash | `DASH_DISTANCE / DASH_DURATION_S` = 666.7 px/s, travel through `move_and_slide` for 0.18 s, then velocity is clamped to walk speed |
| Dash cooldown | exported `dash_cooldown_s` (0.24 s); see the deviation table |
| Strike | grades once, registers one grade, dashes toward the aim, emits `struck(washer, grade)` for group `washers` inside `STRIKE_RANGE_PX` (96) within a 60° cone |
| Grab / throw | `grab_or_throw()` grabs the nearest item ≤ 64 px, or throws the held one |

Rhythm is evaluated only through
`RhythmEvaluator.evaluate(BeatConductor.delta_to_nearest_beat(BeatConductor.get_song_time()))`
from `_input()` callbacks. `grab_or_throw()` and `do_strike()` are public so the sandbox and
tests can drive them, but gameplay must call them from input events only.

Signals: `grabbed(item)`, `thrown(item, grade)`, `struck(washer, grade)`, `aim_changed(dir)`.
`GameState.register_grade()` runs **once per throw** and **once per strike**; a grab is not a
graded action.

## 2. MagneticGrabber (`scripts/components/MagneticGrabber.gd`)

`find_target(origin, radius)` returns the nearest node in group `items` with
`distance <= radius` and `is_held == false`, or `null`. `grab(item)` refuses a second item
while one is held; `drop()` calls `item.end_hold()`. `hold_position()` mirrors the player's
hold point for HUD/debug use.

## 3. LaundryItem (`scripts/entities/LaundryItem.gd`, `scenes/entities/LaundryItem.tscn`)

Root `RigidBody2D`: `collision_layer = ITEMS (4)`, `collision_mask = WORLD | ITEMS (5)`,
`continuous_cd = CCD_MODE_CAST_SHAPE`, `contact_monitor = true`, `max_contacts_reported = 4`.

| State | Rule |
|---|---|
| `setup(id, color, pattern, clean)` | loads `ItemData` from `ItemDatabase`, sets mass, radius, damping, per-item `PhysicsMaterial` (bounce/friction) and the visual |
| `begin_hold(holder)` | `is_held = true`, mask becomes **WORLD only**, gravity off, wakes the body, sock squelch |
| `end_hold()` | `is_held = false`, mask back to `WORLD | ITEMS`, arms exactly one throw, starts the sock drop timer |
| `throw_with_impulse(dir, grade)` | one impulse `dir * THROW_SPEED * force_multiplier(grade) * mass`; gas giant MISS ×0.5; moon MISS starts the perpendicular boomerang; a second call in the same action returns `false` |
| Speed safety | `_integrate_forces` clamps every free body to `MAX_ITEM_SPEED` (1600 px/s) after the solver applies the impulse |
| Held steering | `_integrate_forces`: `state.linear_velocity = ((target - pos) * HOLD_SPRING + player.velocity).limit_length(HOLD_MAX_SPEED)` |
| Visual | `Visual` is `top_level`, follows position, rotation forced to 0 — sprites never rotate |

`mark_clean()` flips `is_clean` and the visual sparkle. `report_fell_off_belt()` /
`report_delivered()` emit the contract signals for M3/M4 to wire up.

### Item behaviours (GDD §6)

| id | mass | wash | points | slots | physics in M2 |
|---|---|---|---|---|---|
| rocky | 1.0 | 6 s | 100 | 1 | `bounce = 0.4`, straight throw |
| sock | 0.3 | 4 s | 150 | 1 | `SQUELCH` signal on grab; dropped un-thrown slides after 0.4 s (scaled by `belt_speed_scale`) |
| moon | 0.8 | 7 s | 200 | 1 | MISS adds decaying `BOOMERANG_ACCEL` perpendicular for 0.6 s |
| gas_giant | 2.2 | 10 s | 350 | **2** | `bounce = 0.85`; MISS impulse ×0.5 |
| galaxy_core | 3.0 | 12 s | 1000 | 3 | wildcard; while carried, socks within 170 px are pulled at 220 px/s² with linear falloff |

## 4. Visuals (`scripts/entities/ItemVisual.gd`)

The item visual draws a flat palette silhouette per id (rocky ball + craters, sock, true
crescent moon, banded gas giant, ringed core) plus pattern overlay and clean sparkles. If
Track B ships `assets/sprites/<id>.png` + `.json`, `frame_texture()` builds an `AtlasTexture`
for the requested variant/animation row and the flat drawing is replaced, scaled to the
item's collision diameter. `char_pip` is used the same way for the player. With no art the
scene still renders — this is what the M2 screenshot shows.

## 5. Tuning constants that are not in `Config.gd`

`Config.gd` is lead-owned and frozen, so a few greybox-only feel values live next to the code
that owns them. They are named/exposed, not inline literals:

| Value | Where | Default | Why |
|---|---|---|---|
| `dash_cooldown_s` | `Player` (exported) | 0.24 s | contract says "short cooldown", Config has no constant |
| `rest_speed_ratio` | `Player` (exported) | 0.025 | snap sub-pixel drift to rest |
| `mouse_aim_timeout_ms` | `Player` (exported) | 1200 ms | mouse/stick arbitration |
| `STRIKE_CONE_DOT` | `Player` (const) | 0.5 | 60° half-angle for "in the aim direction" |
| `SOCK_SLIDE_DELAY_S` / `SOCK_SLIDE_SPEED` | `LaundryItem` (const) | 0.4 s / 120 px/s | GDD §6 sock rule; promote to Config/ItemData if M3 tunes it |
| `VISUAL_SCALE` | `ItemVisual` (const) | 2.2 | greybox legibility; art integration replaces it |

## 6. Measured numbers (headless, Godot 4.7.2, llvmpipe)

| Measurement | Result |
|---|---|
| Dash travel, 0.18 s | **122.2 px** (target 120 ± 12) |
| Dash into a wall 60 px away | stops at the wall face, `last_dash_distance ≈ 46 px` |
| Idle friction, 0.5 s from 340 px/s | 0 px/s (below the 2 % test bound after the rest snap) |
| Hold settle distance | 48.0 px from the player (within 0.001 px of the target) |
| PERFECT throw speed | ~1240 px/s (1260 before solver damping) |
| GOOD/MISS throw speed | 900 px/s |
| Gas giant MISS | 450 px/s (×0.5) |
| 40 bodies / 600 physics ticks | **0.544 ms/tick** (physics monitor; 600 ticks = 10 s of simulated time) |

The numbers above come from `tests/unit/test_player_*`, `tests/unit/test_item_*` and
`tests/integration/test_physics_items.gd`.

## 7. Dev sandbox

`scenes/dev/PlayerSandbox.tscn` builds the 1280×720 room and walls from `data/layout.json`,
shows the four washer bays and the central chute, spawns one of each item, and runs a HUD
(held item, last grade, beat Δt, FPS, physics ms, object count).

Controls: **1–5** spawn that item at the cursor, **R** resets the room, **LMB** grab/throw,
**RMB** rhythm strike, mouse aims (clicking also re-activates mouse aim).

Screenshot (taken with the shared harness; the Wayland compositor renders the window at
1900×1068, so the PNG is that size):

```bash
godot --path . -s tools/screenshot.gd --resolution 1280x720 --audio-driver Dummy -- \
  --scene=res://scenes/dev/PlayerSandbox.tscn --out=res://.work/screens/m2_sandbox.png --frames=30
```

Result: `.work/screens/m2_sandbox.png` (inspected). The FPS/physics figures in the HUD of that
capture are throttled because the window is not visible to the compositor; on a normal desktop
run the HUD reads 60 FPS and the measured physics cost.

## 8. Deferred / known issues

- Contract §A7 mentions an on-beat magnetic assist and a temporary mask change for PERFECT
  throws; M2 ships the graded impulse only. The assist needs the washer mouths (M4).
- Item sprites are scaled to the collision diameter until Track B's SpriteFrames land (M7).
- `SOCK_SLIDE_*` and the dash cooldown should move to `Config`/`ItemData` once the lead opens
  those files for M3+ balance.
- `Performance.TIME_PHYSICS_PROCESS` reads 0 in the isolated sandbox capture environment; the
  integration test measures it correctly (0.544 ms/tick).

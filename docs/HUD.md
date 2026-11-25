# HUD & Diegetic UX — layout, API and rationale

> Scope: the in-game HUD (`scripts/ui/HUD.gd`) and the world-space affordances
> (`scripts/ui/DiegeticLayer.gd`). Authority: `docs/UX_BIBLE.md` §5, §6, §8, §9, §11.
> This document is the map: where every pixel goes, what every caller may call, and which
> shape means what.

---

## 0. What was deleted and what replaced it

| Deleted | Why | Replacement |
|---|---|---|
| The 48 px full-width top bar | Four numbers shouting at the same volume; the fail state was the quietest thing on screen | Two 312×104 corner plaques with a deliberate type scale (40 / 28 / 20 / 12) |
| The bottom instruction strip (`WASD mover · ratón apuntar · …`) | A permanent control legend is what you write when the world does not teach; unreadable at 11 px, never contextual | Contextual prompt above Pip (one verb at a time), aim reticle with a destination, held-item chip, beat ring |
| The screen-centred 44 px grade label | Feedback at the screen centre is feedback at the wrong place | Grade popup at the action, from the world layer (the HUD `GradeLabel` node survives only as an invisible test surface) |
| The full-screen phase banner | It lived in the play field | The plaque A caption announces the phase for 4 s |

The play field (**x 104…1176, y 108…612**) is clear of persistent HUD controls. The only
HUD element that may enter its top edge is the 1.4 s feedback toast (see §3.4).

---

## 1. Layout map (1280×720)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ┌─ PLAQUE A (0,0,312,104) ─┐   ┌─ RIBBON (400,6,480,28) ──┐  ┌─ PLAQUE B ───┐│
│ │ 03:22          ● ● ● ●   │   │ OBJETIVO · LAVA Y …    │  │ ESTABILIDAD ◆││
│ │ TURNO · FASE 3   130 BPM │   └────────────────────────┘  │ ▓▓▓░░░░░░ 22 ││
│ └──────────────────────────┘        (TOAST 400,104,480,18) │ ×5   001 240 ││
│                                                             └──────────────┘│
│                          play field: y 108 … 612 clear                       │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Plaque A — time & phase, `Rect2(0, 0, 312, 104)`

| Element | Local rect | Type | Colour |
|---|---|---|---|
| `ClockLabel` | `(24, 4, 272, 52)` | Silkscreen **Bold 40** | `metal_4`, `yel_3` in the last 10 s |
| `BpmLabel` | `(196, 64, 92, 16)`, right | Regular 12 | `metal_2` (hidden in tutorial) |
| `CaptionLabel` | `(24, 64, 168, 16)` | Regular 12 | `metal_2` |
| Beat dots | centres `x = 232, 248, 264, 280`, `y = 34` | circles r 3 (active 4, downbeat ×1.3) | active `funk_cyan`, rest `metal_1` |
| Panel | fills the rect | `space_deep` 88 %, 2 px `metal_0`, `funk_cyan` corner ticks | `UITheme.panel` |

Caption states: `TURNO · FASE n` normally; for 4 s after a phase change it becomes
`FASE n · <NAME>` (the announcement drops `TURNO` so it never collides with the tempo
readout). Phase names are display copy in the HUD (`PHASE_NAMES`), not mechanics.

The clock label is the same node in tutorial mode: it shows `PASO n/m` at 28 px
(`STEP_CLOCK_FONT`) once `set_step()` has been called, and falls back to the clock when no
step exists.

### 1.2 Plaque B — stability / combo / score, `Rect2(968, 0, 312, 104)`

| Element | Local rect / centre | Type | Colour |
|---|---|---|---|
| `StabilityCaption` | `(24, 8, 120, 16)` | Regular 12 | `metal_2` |
| Stability diamond | centre `(280, 16)`, r 6 | filled diamond | same colour as the bar |
| Segmented bar | `(24, 26, 200, 16)`, 12 segments | `UITheme.draw_segments` | `> 60` `clean_green`, `35…60` `yel_2`, `< 35` `hazard_orange` |
| `StabilityValue` | `(238, 20, 50, 26)`, right | Bold 20 | the band colour |
| `ComboLabel` | `(24, 54, 120, 38)` | Bold 28 | `funk_magenta` at ≥ ×4, else `metal_3` |
| `ScoreLabel` | `(150, 54, 138, 30)`, right | Regular 20 | `metal_4`, grouped `001 240` |

The numeric value, the diamond and the bar colour are three channels for one number: a
desaturated screenshot still reads the value and the shape.

`set_danger(true)` (or `< 35` stability) pulses the bar and draws a 2 px `hazard_orange`
border over the plaque; under `Settings.reduce_motion` the border is static.

### 1.3 Mission ribbon, `Rect2(400, 6, 480, 28)`

One line, max **46 characters**, `space_void` at 55 % with a 1 px `metal_0` border at 45 %.
`ObjectiveLabel` is inset by 8 px and centred, Regular 14 `metal_3`.

Alpha: 100 % for 8 s after a change, then a 0.4 s settle to 55 % — it never disappears.
Default copy: `OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00`.

### 1.4 Feedback toast, `Rect2(400, 104, 480, 18)`

`GameState.feedback(text, kind)` draws one chip, as wide as its text, 1.4 s, replaced (never
stacked) by a newer message. It hangs **under the ribbon**, not inside it, because the level
draws the north belt inside the wall band (y 35…100) and a toast there would sit on moving
items. The toast is the one transient that dips into the field's top edge (y 104…127).

Colour by `kind`: `success` `clean_green`, `danger` `hazard_orange`, `warn` `yel_3`, anything
else `metal_3`.

### 1.5 Reward float, `Rect2(1156, 104, 100, 18)`

`flash_reward(points)` shows `+points` right-aligned at the right margin next to plaque B for
600 ms, floating up 16 px. Under `reduce_motion` it stays put and only fades — the number is
still readable.

### 1.6 HUD scale

`Settings.ui_scale` (1.0 / 1.25) is applied by scaling **only the two plaques**, from the
screen-edge corner:

- plaque A: pivot `(0, 0)` — grows right and down;
- plaque B: pivot `(312, 0)` — grows left and down, so it never leaves the screen;
- the ribbon, the toast and the reward float never scale.

At 125 % the plaques cover more of the wall band (expected). The world is never scaled.

---

## 2. Public API

### 2.1 `HUD` (`res://scenes/ui/HUD.tscn`)

| Method | Called by | Behaviour |
|---|---|---|
| `set_shift_time(t: float)` | MainLevel, every frame | Updates the clock; cheap when the displayed minute has not changed |
| `set_phase(index: int, bpm: int = -1)` | MainLevel `_apply_phase` | Caption + 4 s phase announcement + tempo |
| `set_bpm(bpm: int)` | anyone | Tempo label only |
| `set_objective(text: String)` | MainLevel | Ribbon copy, truncated to 46 chars, alpha reset to 100 % |
| `set_step(index: int, total: int)` | tutorial driver | 1-based `PASO n/m` in the clock slot (only rendered in tutorial mode) |
| `set_tutorial_mode(on: bool)` | MainLevel, tutorial screen | Hides BPM + score, keeps stability, swaps the clock for the step |
| `set_danger(on: bool)` | MainLevel, hazard band | Pulses the bar + plaque border |
| `show_grade(grade: int)` | MainLevel `_show_grade` | Forwards to the world layer; writes `GradeLabel.text` (invisible) for tests |
| `flash_reward(points: int)` | MainLevel on delivery | `+points` float near plaque B |
| `clock_text() -> String` | tests, debug | `Config.clock_string(shift_time)` — unaffected by tutorial mode |
| `set_hud_scale(factor: float)` | Settings callback | Clamped to `Config.HUD_SCALE_OPTIONS` |
| `readout() -> Dictionary` | tests | One snapshot of every label the layout tests assert |
| `plaque_rect(name) -> Rect2`, `stability_color() -> Color`, `diegetic_layer() -> Node` | tests | Layout/contract probes |

`clock_text()` always returns the shift clock; tutorial mode only changes what the label
*renders*, so the fail-safe (no step set → show the clock) keeps working.

The HUD mounts a `DiegeticLayer` on the nearest `Node2D` ancestor that exposes
`get_shift_time()` when no layer is in the `diegetic` group yet (deferred one frame). That is
a safety net so the grades are never mute; MainLevel may own the layer instead.

### 2.2 `DiegeticLayer` (`res://scenes/ui/DiegeticLayer.tscn`, `Node2D`, group `diegetic`)

| Method | Purpose |
|---|---|
| `refresh_now()` | Rescan groups + recompute state + repaint (tests, callers that cannot wait 0.5 s) |
| `advance(delta)` | Steppable `_process` body |
| `show_grade(grade: int)` | Grade popup at the action for 380 ms |
| `set_gamepad_hint(enabled: bool)` | Forces the Ⓐ/Ⓧ prompt glyphs (tests, sandbox) |
| `ring_radius()`, `ring_width()`, `ring_alpha()` | Pulse-ring geometry probes |
| `reticle_state() -> StringName` | `none` / `washer_ok` / `washer_no` / `chute` |
| `target() -> Node` | The destination under the aim ray |
| `prompt_text() -> String` | The single contextual prompt currently drawn |
| `item_chip_text() -> String` | `ROJO · ANILLADO · 100` for the held item |
| `grade_text() -> String`, `is_grade_active()` | Grade popup state |
| `turbulence_target() -> Node` | The one turbulent washer being signalled |
| `state_readout() -> Dictionary` | All of the above in one call |

Discovery is by group — `player`, `washers`, `chute`, `items` (`Config.GROUP_*`), refreshed
every 0.5 s or on `refresh_now()`. Every foreign read is duck-typed (`has_method` / `get`),
so the layer is correct with **zero washers and no chute**:

| Washer API used | Fallback when absent |
|---|---|
| `get_requirement() -> StringName` | `""` → never matches, so the reticle shows `NO` |
| `get_state() -> int` (2 = TURBULENT) | no turbulence path |
| `is_locked() -> bool` | treated as unlocked |
| `get_mouth_world() -> Vector2` | `global_position` |
| `strike(grade)` | never called by this layer (the player owns strikes) |
| chute `try_deliver` | never called by this layer |

Compatibility goes through `Compatibility.item_fits()` when the script is loadable and falls
back to the same colour/pattern/wildcard rule otherwise.

---

## 3. Diegetic affordances

### 3.1 Pulse ring (around Pip)

Radius **42 → 70**: at the beat it snaps wide (70) and contracts toward the next beat, so the
ring *arrives* where the press belongs. Width 2 px, `funk_cyan` at 22 % alpha; inside the
PERFECT window (`Config.WINDOW_PERFECT_S`, ±65 ms) it thickens to 4 px and brightens to 70 %.

`Settings.reduce_motion` keeps the radius fixed at 56 and moves **alpha** instead, so timing
information survives without motion.

When the player carries something, `¡AHORA!` appears under Pip during the PERFECT window and
nowhere else (one line, 12 px).

### 3.2 Aim reticle

At `player.global_position + aim × 96`. Four states, each with colour **and** shape **and**
(where it adds information) a word:

| State | Colour | Shape | Word |
|---|---|---|---|
| `none` | `metal_2` 60 % | thin cross | — |
| `washer_ok` | `funk_cyan` | cross + 4 corner brackets | `LANZAR`, suppressed while the prompt already says it |
| `washer_no` | `red_3` | cross + ✗ | `NO` |
| `chute` (clean item) | `clean_green` | cross + down chevron | `ENTREGAR` |
| `chute` + dirty item | `hazard_orange` | cross | `LAVA PRIMERO` |

A 2 px tracer runs from Pip to the destination at 30 % alpha whenever the target is valid.
Targets are scored by `perpendicular distance to the aim ray + 0.25 × |distance − 96|`;
candidates must project 16…260 px along the aim and stay within 64 px of it. The nearest
scoring destination wins, so the chute beats a washer only when it really is under the ray.

The reticle only resolves a destination when something is held: it answers "where does *this*
go", not "where am I". With empty hands it is a faint cross.

### 3.3 Contextual prompt (24 px above Pip's silhouette)

One at a time, priority order:

1. carrying → `ESPACIO · LANZAR` (`Ⓐ` on a pad)
2. an item within `Config.GRAB_RADIUS` (64 px) → `ESPACIO · AGARRAR`
3. a TURBULENT washer within `Config.STRIKE_RANGE_PX` (96 px) → `SHIFT · GOLPE` (`Ⓧ` on a pad)

Gamepad glyphs require a connected pad **and** that the most recent input event came from it;
any key or mouse button switches the prompt back. `set_gamepad_hint()` overrides for tests.

The prompt is suppressed while a grade popup is on screen (one thing at a time).

### 3.4 Held-item chip

Under the held item: `ROJO · LISO · 100` (colour, pattern, points), max 26 chars, on a
`space_void` 86 % chip. A clean item adds a separate `LIMPIA` tag above the chip in
`clean_green` (the spec text stays identical; the tag is the state).

### 3.5 Grade popup

At the action, not at the screen centre: PERFECTO (40 px, `funk_magenta`, 8-spark fan), BIEN
(32 px, `funk_cyan`), FUERA DE RITMO (28 px, `metal_1`). 380 ms, scale 1.3 → 1.0 with a float
up; under `reduce_motion` the scale and the rise are removed and only the fade remains.

### 3.6 Turbulence path

The nearest TURBULENT washer gets one thin dashed `hazard_orange` line from its mouth to Pip,
pulsing at 1.8 Hz. No full-screen flash, no strobe.

---

## 4. Colour and glyph table

| Meaning | Colour | Shape (`HudGlyphs`) | Word |
|---|---|---|---|
| Red / crimson requirement | `red_3` | ▲ `draw_triangle` | `ROJO` |
| Blue / nebula requirement | `blue_3` | ● `draw_circle` | `AZUL` |
| Yellow / solar requirement | `yel_3` | ■ `draw_square` | `AMARILLO` |
| Wildcard (galaxy core) | `metal_3` | ◆ `draw_diamond` | `CUALQUIERA` |
| Pattern liso | `metal_3` | ▬ bar | `LISO` |
| Pattern anillado | `metal_3` | ◎ ring | `ANILLADO` |
| Pattern moteado | `metal_3` | ⁘ three dots | `MOTEADO` |
| Stability > 60 | `clean_green` | bar + ◆ + number | — |
| Stability 35…60 | `yel_2` | bar + ◆ + number | — |
| Stability < 35 / `set_danger` | `hazard_orange` | bar + ◆ + number + pulsing border | — |
| Rhythm / player | `funk_cyan` | ring, brackets, cross, tracer | `¡AHORA!` |
| Reward / perfect | `funk_magenta` | sparks, combo ≥ ×4 | `PERFECTO` |
| Clean / delivered | `clean_green` | chevron, `LIMPIA` tag | `ENTREGAR` |
| Alert / reject | `hazard_orange`, `red_3` | ✗, dashed path | `NO`, `LAVA PRIMERO` |

All text is Silkscreen; sizes are 40 / 28 / 20 / 14 / 12 only. Captions are never below 12 px.

---

## 5. Performance notes

- **One node, one draw call each.** The HUD paints its plaques and the ribbon through three
  interior `PaintSlot` Controls; the world layer is a single `Node2D._draw()`. No textures, no
  shaders, no child nodes per affordance.
- **Group caching.** `get_nodes_in_group` runs at most twice a second
  (`RESCAN_INTERVAL = 0.5`), never per frame.
- **Redraw policy.** The HUD repaints the beat dots on beat and the stability bar only in the
  danger band. The world layer repaints while the ring animates (it is information), and
  under `reduce_motion` only on the beat or on a discrete state change.
- **No per-frame allocation** in the world layer beyond the handful of cached strings; the
  prompt text is rebuilt only when the prompt *kind* changes, and the spark fan is a fixed
  angle table.
- Measured: the layer adds one `draw_arc`, up to ~40 lines and ≤ 6 `draw_string` calls per
  frame — well inside the 0.4 ms budget at 1280×720 on llvmpipe.

---

## 6. Tutorial mode

`set_tutorial_mode(true)` collapses the HUD to what a learner needs:

| Element | Normal | Tutorial |
|---|---|---|
| Clock slot | `03:22` 40 px | `PASO n/m` 28 px once `set_step()` was called |
| BPM | shown | hidden |
| Score | shown | hidden |
| Stability | shown | **shown** (it teaches the fail state) |
| Combo | shown | shown |
| Ribbon | objective | the step's one-liner |

Fail-safe: with `set_step()` never called the clock keeps working; with
`set_tutorial_mode(false)` every element returns.

---

## 7. Design-time sandbox and screenshots

`scenes/dev/HudSandbox.tscn` (script `scripts/ui/HudSandbox.gd`) fakes one frame of the whole
diegetic state set on the real room plate: Pip holding a red ringed piece, a compatible red
washer, an incompatible blue one, a clean chute, stability 22, combo ×5, live conductor.

```bash
# diegetic states in one frame
godot --path . -s tools/screenshot.gd --audio-driver Dummy --display-driver wayland \
  --rendering-method gl_compatibility -- --scene=res://scenes/dev/HudSandbox.tscn \
  --out=res://docs/media/hud_diegetic.png --frames=61

# tutorial HUD (same scene, step 3 of 7)
godot --path . -s tools/screenshot.gd --audio-driver Dummy --display-driver wayland \
  --rendering-method gl_compatibility -- --scene=res://scenes/dev/HudSandbox.tscn \
  --tutorial --out=res://docs/media/hud_tutorial.png --frames=61

# the real level (before/after comparison)
godot --path . -s tools/screenshot.gd --audio-driver Dummy --display-driver wayland \
  --rendering-method gl_compatibility -- --scene=res://scenes/main/Main.tscn \
  --autostart=shift --out=res://docs/media/hud_after.png --frames=240
```

`docs/media/hud_before.png` is the same level frame captured from `main` before this change.

| Shot | Hierarchy | 100 % readability | "Where do I put this" | Cohesion | Belt overlap |
|---|---|---|---|---|---|
| `hud_before.png` | 2 | 2 | 1 | 2 | 2 (bottom strip over the floor) |
| `hud_after.png` | 5 | 4 | 3 (no washers exist yet) | 4 | 5 |
| `hud_diegetic.png` | 5 | 4 | 4 | 4 | 5 |
| `hud_tutorial.png` | 5 | 5 | 4 | 4 | 5 |

---

## 8. Wiring for the lead

MainLevel already calls `set_shift_time`, `set_phase`, `set_objective`, `show_grade`,
`flash_reward`, `set_danger` and `set_tutorial_mode` defensively, so nothing is required for
the HUD. For the world layer, either let the HUD mount it (it does, one frame after `_ready`)
or own it explicitly:

```gdscript
# scripts/main/MainLevel.gd — preferred explicit wiring
const DIEGETIC_SCENE := "res://scenes/ui/DiegeticLayer.tscn"

func _build_diegetic() -> void:
	if not ResourceLoader.exists(DIEGETIC_SCENE):
		return
	var packed := load(DIEGETIC_SCENE) as PackedScene
	if packed == null:
		return
	var layer := packed.instantiate() as Node2D
	layer.name = "DiegeticLayer"
	_entities.add_child(layer)   # after Player/Washers exist, so the group scan finds them
```

Tutorial/step API the tutorial driver should call: `_hud.set_tutorial_mode(true)` and
`_hud.set_step(index, total)` (1-based) whenever the tutorial step changes.

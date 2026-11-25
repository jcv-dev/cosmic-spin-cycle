# Cosmic Spin Cycle — UX & Art Direction Bible (M4–M6)

> Owner verdict that triggered this document: *"The UI/UX is absolutely horrendous. I played
> and had no idea what to do, where to throw items, or what the goal was."*
>
> This is not a UI skin. It is a re-declaration of what the game tells the player, when, and
> with what. Every screen below is specified in 1280×720 pixels, Spanish copy, and the frozen
> 30-colour palette. Anything that contradicts this document loses.
>
> Companion: `docs/UX_RESEARCH.md` (evidence + links), `docs/CONTRACTS.md` §9–§14 (APIs).

---

## 1. Diagnosis — why the current build fails to communicate

The greybox is technically honest and experientially mute. Five concrete failures:

1. **There is no destination.** Items exist to be thrown. The player can throw, but nothing
   anywhere says *where to*. Empty space is not a goal. A game whose verb has no object is a
   physics demo.
2. **The goal is invisible.** Win/lose is "stability > 0 at 480 s". Nothing on screen says
   that. The clock is the largest element on the HUD, but time is not the objective; it is the
   container for the objective.
3. **The bottom instruction strip is a confession.** A permanent line of controls is what a
   designer writes when the world does not teach. It is unreadable at 11 px, always present,
   never contextual, and it answers a question the player did not ask while the questions they
   *did* ask ("what is this item?", "which machine?", "when do I press?") go unanswered.
4. **No hierarchy.** Clock 26 px, combo 24 px, score 22 px, stability 12 px — four things shout
   at the same volume and the actual fail state (stability) is the quietest. Nothing is bigger
   because nothing is more important.
5. **No first contact.** The game starts mid-shift with items already moving, no title, no
   framing, no consent. A stranger has ~4 s before the first item reaches a shredder.

The fix is not "more HUD". It is **fewer words, stronger objects**: the washers carry their
requirements, the chute carries the goal, the beat ring carries the timing, and the room
carries the state. Text becomes a caption for something the player can already see.

---

## 2. The 20-second test (the acceptance criterion for the whole phase)

A player who has never seen the game presses **Iniciar turno** and, within 20 seconds of the
first frame of the shift, can answer all three questions **without reading a control list**:

| Question | Answer the world must give | Affordance that gives it |
|---|---|---|
| *What am I trying to do?* | Wash dirty items and deliver them to the chute until 06:00; don't let stability hit zero. | Chute beacon + objective plaque + clean/dirty visual language |
| *Where do I put things?* | Into the washer whose hologram matches the item. | Four washer holograms showing colour-glyph + pattern-glyph; incompatible ones dim when carrying |
| *When do I act?* | On the beat. | Contracting pulse ring around Pip + drum/neon pulse on every beat |

**Hard gate:** the first spawned item must not be able to reach a shredder before **20 s** in
the shift (current spawn interval 3.5 s → item travels the north belt in ~6 s). Fix: a 6 s
"grace" where the first item spawns stationary near the player on the floor, plus the
onboarding overlay. Measured by `tests/integration/test_first_20s.gd`.

A fourth, softer question — *"what happens if I fail?"* — is answered by the stability plaque
changing colour at 60 % and 35 %, and by the first wrong-washer feedback being loud, local and
non-fatal (−12).

---

## 3. Art direction

### 3.1 Mood in one line
**A night-shift laundromat parked at the edge of a nebula: industrially cosy, neon-cold, with
warm machinery glowing against deep space.** Funny, never cute; busy, never noisy.

### 3.2 Pillars
1. **Readability is the art.** Every object earns its silhouette at 1× before it earns detail.
   If an effect makes an item, a washer requirement or the chute harder to see, it is deleted.
2. **Light is information.** Light pools mark the four washers and the chute (the places that
   matter). Darkness is the rest of the room. Nothing glows decoratively.
3. **Mechanism is visible.** Drums spin on the beat, belts scroll in their flow direction,
   neon breathes on the measure. The room is a metronome you can read.
4. **Hand-made density.** Small authored details (grime, puddles, cable runs, stickers,
   warning stripes) at 1 art px = 4 world px. Density at the edges, calm in the play lanes.

### 3.3 Palette discipline (the 30 colours in `art/palette.json`)
The palette does not change. What changes is **how much of the screen each ramp is allowed**:

| Role | Share of screen | Colours |
|---|---|---|
| Structure (floor, walls, panels, metal) | 55–65 % | `space_*`, `metal_0..2` |
| Machinery bodies | 15–20 % | `metal_2..4`, `space_mid` |
| Item / requirement colour | ≤ 6 % | `red_2`, `blue_2`, `yel_2` (+ their `_3` highlight) |
| Rhythm / player accent | ≤ 4 % | `funk_cyan` |
| Reward | ≤ 2 % | `funk_magenta` (PERFECT), `clean_green` (done/delivered) |
| Danger | ≤ 3 % | `hazard_orange`, `red_3` |
| Deep shadow | remainder | `space_void`, `space_deep` |

Rule of thumb: **a screenshot should be ~70 % blue-grey, and the eye should land on exactly
one warm/bright thing.** If two unrelated areas compete, the composition is wrong.

### 3.4 Depth model (2.5D top-down, fixed camera)
Six layers, back to front. All coordinates are world px; all art is ×4 and integer-aligned.

| z | Layer | Content | Motion |
|---|---|---|---|
| −100 | `RoomBackground` | `env_room` (walls, panels, portholes) | static |
| −95 | `Backdrop` | parallax starfield, distant nebula bands, planet limb | 1–3 px/s horizontal drift |
| −90 | `Floor` | floor plate, stains, puddles, cable runs, floor markings | static + specular flicker |
| −5 | `Belts` + `Shredders` | conveyor, chevrons, grinder vortex | scroll at 8 fps, beat pulse |
| 0 | `Washers` | body, drum, hologram, progress ring, light pool | drum on beat, squash on load |
| 1–6 | `Items`, `Player`, `FX` | laundry, Pip, steam, sparks | physics |
| 20 | `Foreground` | ceiling pipes, hanging lamps, vignette | static |

**Never** scale, rotate (except 90° belt tiles) or sub-pixel-position art. Procedural geometry
(plates, plaques, beams, puddles) must land on integer pixels; a 1 px line at x = 12.5 will
shimmer and is a defect.

### 3.5 Lighting model (GL Compatibility, no normal maps)
We cannot author normal maps for 176 frames. So light is **tint + additive pools**, not
shaded geometry:

- One `CanvasModulate` (`#8C93B8`-ish, i.e. cool and ~55 % brightness) darkens the room.
- Each washer gets a `PointLight2D` with a radial `GradientTexture2D` (no new image assets),
  tinted by its requirement colour (`red_3` / `blue_3` / `yel_3`), radius ≈ 260 px, energy 0.5,
  pulsing 0.42→0.58 on the beat.
- The chute gets a vertical light cone (`clean_green`, energy 0.55) and a slowly rotating
  holographic ring.
- Two overhead cold lamps (`funk_cyan`, energy 0.22, radius 420) at the top corners for shape.
- Emissive details (neon strips, drum window, belt rails) are additive `ColorRect`s with a
  pulsing alpha, not lights.
- **Budget:** ≤ 8 PointLight2D, ≤ 6 additive quads, ≤ 3 CPUParticles2D emitters. This is an
  llvmpipe box; the target is 60 FPS at 1280×720.

### 3.6 Environment upgrade (what "dramatically richer" means concretely)
Beyond the shipped `env_room`:
1. **Backdrop parallax:** starfield + a huge dim planet arc at the top + drifting dust. Menu
   and game share it (see 3.7).
2. **Floor story:** 4–6 irregular grime decals, 2 wet puddles with a 1 px highlight, hazard
   stripes under each washer, a painted dashed path from washers to chute (subtle, `metal_0`).
3. **Machine dressing:** cable runs from washers to the wall, vent grilles, a mop + bucket
   silhouette, a stack of baskets, a "TURNOS" clipboard sign, valve wheels.
4. **Atmosphere:** steam plumes from washer tops (more when TURBULENT), dust motes in light
   cones, a slow ceiling fan shadow? (no — too much; cut).
5. **Beat life:** neon tubes breathe on the beat, drum windows pulse, belt chevrons step, chute
   ring rotates by one segment per beat.
6. **Foreground:** vignette + two hanging lamp cords with warm glow + ceiling pipe silhouettes.
   Foreground never covers the play lane between y = 120 and y = 600 outside 40 px margins.

### 3.7 The menu is a living diorama, not a frozen frame
Title screen background = the real room, camera zoomed to 1.15 and slowly panning ±18 px,
with: one washer mid-wash (drum spinning), steam, drifting dust, neon breathing on a 90 BPM
ambient loop, and Pip idling asleep on a basket. It is *the world*, not a jpeg. When the player
presses Iniciar, the camera eases back to 1.0 and the title elements fade in 180 ms — the game
"starts" as a continuation, not a cut.

### 3.8 Motion language
| Event | Motion | Duration |
|---|---|---|
| Button focus | caret slides + label brightens + 1 px lift | 120 ms |
| Button press | 2 px down + click | 80 ms |
| Screen enter | dim + slide up 12 px + fade | 180 ms |
| Screen exit | fade + slide down 8 px | 140 ms |
| Beat pulse | ring scale 1.15→0.92, neon alpha +18 % | 90 ms attack, 160 ms decay |
| Throw window | ring turns `funk_cyan` and thickens 1 px | per beat |
| Grade pop | scale 1.3→1.0 overshoot, float up 12 px, fade | 380 ms |
| Wrong washer | 6 px shake (3 frames), hologram flashes ✗ | 260 ms |
| Explosion | 8 px shake, 90 ms hitstop, orange flash 1 frame | 520 ms |
| Delivery | chute ring expands, +score floats, chime | 420 ms |
| Phase change | banner slides in, 1 s hold, slides out; stem crossfade | 1.6 s |

All of the above except the beat ring are disabled or reduced by **Reduce motion** (§11).

---

## 4. Screen map and flow

```
                 ┌──────────────────────────────┐
                 │        TITLE (menu)          │
                 │  Iniciar turno               │
                 │  Tutorial                    │
                 │  Calibración de audio        │
                 │  Opciones                    │
                 │  Salir                       │
                 └───────┬──────────────┬───────┘
        first run? ──────┘              │
                 ▼                     ▼
       ┌──────────────────┐    ┌──────────────────┐
       │ FIRST-RUN PROMPT │    │     TUTORIAL     │
       │ Tutorial primero │    │ 7 gated steps    │
       │ [Jugar] [Saltar] │    │ skippable (ESC)  │
       └────────┬─────────┘    └────────┬─────────┘
                │                       │ complete
                ▼                       ▼
       ┌──────────────────┐    ┌──────────────────┐
       │      SHIFT       │◄───│  TUTORIAL DONE   │
       │ 480 s, 4 phases  │    │ (back to title)  │
       └───┬──────────┬───┘    └──────────────────┘
           │ ESC      │ end
           ▼          ▼
    ┌────────────┐  ┌──────────────┐
    │   PAUSE    │  │  END SCREEN  │
    │ Reanudar   │  │ Victoria /   │
    │ Reiniciar  │  │ Derrota      │
    │ Opciones   │  │ stats + rank │
    │ Menú       │  │ [Repetir]    │
    └─────┬──────┘  │ [Menú]       │
          └────────►└──────────────┘
```

Rules:
- **No dead ends.** Every screen has a visible way back; ESC/START backs out of every overlay.
- **Restart is always < 0.5 s** and keeps the same seed unless the player asks for a new one.
- Focus is explicit on every screen: a 2 px `funk_cyan` bracket + caret `▶`, keyboard and
  gamepad share the same focus order; mouse hover moves focus.
- Transitions are fades over a persistent background; never a black flash.

---

## 5. HUD specification (in-game, 1280×720)

The bottom strip is **deleted**. The HUD is two corner plaques plus a thin mission ribbon in
the wall band; the play field (y = 40…616 between x = 120…1160) stays clear.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ┌─ CLOCK ────────────────┐        MISSION RIBBON        ┌─ STABILITY ─────┐ │ 0–104
│ │ 03:22   ● ● ○ ○  105   │  MANTÉN LA ESTABILIDAD HASTA  │ ▓▓▓▓▓▓▓░░ 72   │ │
│ │ TURNO · FASE 3         │           LAS 06:00           │ ×4   001 240   │ │
│ └────────────────────────┘                               └────────────────┘ │
│                                                                             │
│   [NW washer]                                        [NE washer]            │
│                                                                             │
│                          ( chute )                                          │
│                                                                             │
│   [SW washer]                                        [SE washer]            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.1 Plaque A — time & phase (rect `0,0,312,104`)
| Element | Type | Colour | Notes |
|---|---|---|---|
| Clock `HH:MM` | Silkscreen Bold 40 | `metal_4` | updates every frame; last 10 s turns `yel_3` |
| Caption `TURNO · FASE n` | Regular 12 | `metal_2` | phase name replaces `FASE n` in phase events |
| Beat dots `● ● ● ●` | 8 px circles | active `funk_cyan`, rest `metal_1` | downbeat dot 1.3× |
| BPM `105` | Regular 12 | `metal_2` | right-aligned; hidden in tutorial |

Panel: `space_deep` at 88 % + 2 px `metal_0` border + 4 px `funk_cyan` corner tick (top-left).

### 5.2 Plaque B — stability, combo, score (rect `968,0,312,104`)
| Element | Type | Colour | Notes |
|---|---|---|---|
| Caption `ESTABILIDAD` | Regular 12 | `metal_2` | — |
| Segmented bar 12 segments, 232×16 | rects | >60 `clean_green`, 35–60 `yel_2`, <35 `hazard_orange` + pulse | always shows **numeric** value right-aligned, 20 px |
| Glyph | 12 px diamond | same colour | colour-blind redundancy |
| `×n` combo | Bold 28 | `funk_magenta` at ≥4, else `metal_3` | pops on change |
| Score `001 240` | Regular 20, right | `metal_4` | groups of 3 with thin space |

At stability < 25 the plaque border pulses and a low heartbeat SFX plays every 2 beats.

### 5.3 Mission ribbon (rect `400,6,480,28`)
One line, max **46 characters**, Regular 14, `metal_3`, centred, on `space_void` at 55 %.
It changes with context and **fades to 55 % after 8 s** (still there, no longer shouting):
- Shift start: `OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00`
- Carrying: `LLEVA LA PIEZA AL DUCTO` (once washed) / `LAVADORA ROJA · LISO` (if dirty)
- Low stability: `¡ESTABILIDAD CRÍTICA!`
- Tutorial: the step's one-liner (see §7).

### 5.4 What is *not* in the HUD
No controls list, no seed, no FPS, no item names as a legend, no “objective complete” toasts
stacked. Those live in the pause screen (controls), the end screen (seed), and the debug
overlay (F3).

---

## 6. Diegetic affordances (the replacement for the instruction strip)

### 6.1 Washer hologram (above each washer, world space)
A floating panel 128×84 world px, anchored 40 px above the machine, drawn additively:
- **Row 1:** requirement glyphs at ×4: colour glyph (▲ red / ● blue / ■ yellow) tinted with the
  ramp's `_3` colour **and** pattern icon (liso / anillos / motas) in `metal_3`.
- **Row 2:** label `ROJO · LISO` — Bold 12, `metal_4`. In Spanish, max 14 chars.
- **State encoding** (always glyph + text, never colour alone):
  - IDLE: 60 % alpha, slow bob ±2 px.
  - MATCH (you carry a compatible item): 100 %, cyan underline, 1.06 scale pulse on the beat.
  - MISMATCH (you carry an incompatible item): 25 % alpha, label `NO COMPATIBLE`.
  - WASHING: progress ring around the drum (arc from 0→360°, 3 px, `funk_cyan`) + `%` text.
  - TURBULENT: hologram turns `hazard_orange`, shakes 2 px, shows `¡GOLPE!` + expanding rings.
  - DONE: `clean_green` check + `LISTO`, drum glows, clean items pop out with sparkle.
  - BROKEN: `metal_1` `AVERIADA` + a 4 s repair ring.

### 6.2 Chute beacon
- Idle: a slow-rotating dashed ring (radius 44) + `DUCTO` label, `metal_2`.
- Carrying clean item: ring turns `clean_green`, expands/pulses, a 3-chevron arrow points from
  Pip to the chute, label `ENTREGAR`.
- Delivering: ring collapses inward, +points float, `+3` stability chip, chime.
- Carrying dirty: `LAVA PRIMERO` in `hazard_orange`, no arrow.

### 6.3 Aim reticle (`ui_reticle`, world space at aim distance 96)
Four states, each **colour + shape + label**:

| State | Colour | Shape | Label |
|---|---|---|---|
| No target | `metal_2` | thin cross, 60 % | — |
| Compatible washer | `funk_cyan` | cross + 4 corner brackets | `LANZAR` |
| Incompatible washer | `red_3` | cross + ✗ | `NO` |
| Chute (clean item) | `clean_green` | cross + arrow | `ENTREGAR` |

The reticle is a *destination* indicator, not just a cursor. When a target is in range, a 2 px
tracer line runs from Pip to the target edge at 30 % alpha.

### 6.4 Pulse ring (the beat teacher)
Around Pip, radius 42→70 world px:
- Contracts linearly over the beat and **snaps** at the beat: `funk_cyan` at 22 % alpha,
  2 px thick, plus a 1-frame 4 px flash on the downbeat.
- Inside the PERFECT window (±65 ms) the ring thickens to 4 px and brightens to 70 %.
- On a thrown item: a small ring detaches and travels with the item for 200 ms.
- In tutorial step 4 the ring gains a `¡AHORA!` label under Pip at the beat and a “ghost”
  ring showing the window 130 ms after.

### 6.5 Contextual prompt (near Pip, max one at a time)
Small chip 24 px above Pip, Bold 12, `space_void` 80 % + border, icon + verb:
`ESPACIO · AGARRAR` when an item is within 64 px; `ESPACIO · LANZAR` when holding;
`SHIFT · GOLPE` when a washer within 96 px is TURBULENT; `F · DASH` never (dash is a strike).
On gamepad the icon switches to **Ⓐ / Ⓧ**. Max 22 chars.

### 6.6 Item label (when carried)
A 96×20 chip under the held item: `ROJO · LISO · 100` (colour, pattern, points). This is the
single most important teaching object: it *is* the matching puzzle. Dirty items show a grime
overlay and a `SUCIA` tag; washed items show `LIMPIA` + sparkle.

### 6.7 Turbulence alarm
Not a full-screen red flash (that is a 2005 idea and it fights the palette). Instead:
- Washer drum strobes `hazard_orange` at 2× beat rate, steam doubles, hologram shakes.
- A thin orange arc runs along the floor from the washer toward Pip (a “come here” path).
- Alarm SFX (`turbulent_alarm.ogg`, −8 dB) on the beat, muted after 6 s to avoid fatigue.
- Timer: a shrinking orange ring around the drum; under 2 s it flashes.

### 6.8 Shredder
The shredder is the **anti-goal**, so it gets one honest tell: a hazard-striped mouth that
pulses on the beat and a *red* `−8` chip the first time an item is lost (then only the chip).
No screen-wide shake for a loss — the loss should be legible, not punishing.

---

## 7. Tutorial — beat sheet (target 2:30–3:30, hard cap 4:00)

Mode: real `MainLevel` in `mode = "tutorial"`, fixed seed `7001`, spawner disabled, no shift
clock end, HUD in tutorial mode (clock replaced by step progress `PASO 2/7`), scripted items.
Steps gate on **doing**, not on timers. A step can be skipped individually with `TAB` after
12 s of being stuck (soft-skip), and the whole tutorial with `ESC → Saltar tutorial`.

| # | Title (ES) | World setup | Success condition | Copy on screen (≤ 46 chars) |
|---|---|---|---|---|
| 1 | `MUÉVETE` | Empty room, Pip centre. Ring on floor at radius 96. | Player travels ≥ 160 px. | `WASD / STICK para moverte` |
| 2 | `AGARRA` | One dirty RED·SOLID rocky item on the floor 80 px away, bobbing. | `grabbed` fires. | `ESPACIO para agarrar la pieza` |
| 3 | `LEE LA PIEZA` | Same item held; two washers lit: NW hologram `ROJO`, NE hologram `AZUL`. | 2.5 s dwell (no input needed). | `ROJO · LISO — así se lee la pieza` |
| 4 | `ELIGE` | Both washers visible; wrong one dims when aimed at. | Player aims at the red washer ≥ 0.4 s. | `Apunta a la lavadora ROJA` |
| 5 | `LANZA AL RITMO` | Beat ring active; first throw forgiving (window ×2). | Item enters the red washer (any grade). | `Espera el pulso y lanza` |
| 6 | `ESTABILIZA` | Washer forced TURBULENT at 50 % with a 12 s timer (forgiving). | Rhythm strike with grade ≥ GOOD within 12 s. | `SHIFT a tiempo para estabilizar` |
| 7 | `ENTREGA` | Clean item ejected; chute beacon green; arrow to chute. | Item delivered to chute. | `Lleva la pieza limpia al ducto` |
| 8 | `TURNO DE PRUEBA` | Banner + stats; `CONTINUAR` button. | Button pressed (any input). | `¡Listo! Ya sabes lavar el cosmos` |

Rules:
- **One instruction at a time.** Previous copy leaves with the step.
- Step 5 uses `WINDOW_SCALE_BY_PHASE`-style `tutorial_window_scale = 2.0`; the throw is graded
  for feedback but **never fails the step** on a MISS.
- Step 6 always resolves: if the timer hits 0, the washer fakes a recovery and re-prompts once
  (teaching, not punishing). Explosion is *shown* in a controlled beat only after success.
- The tutorial ends with a **real wash → deliver cycle** and writes
  `Settings.tutorial_completed = true`.
- Skipping at any point writes `Settings.tutorial_skipped = true` and returns to the title; the
  tutorial stays available from the menu forever.
- Completion unlocks nothing mechanical (no gate on content) — it only stops the recommendation
  prompt. Never punish a player for skipping.

### First-run prompt copy
```
¿PRIMERA VEZ?
El tutorial dura 3 minutos y te enseña a lavar y entregar.
[ HACER EL TUTORIAL ]   [ EMPEZAR EL TURNO ]
```
Pressing `EMPEZAR EL TURNO` persists `first_run_done = true` so the prompt never nags again.
The prompt appears **after** pressing Iniciar, not before, so the first interaction is always
the big one.

---

## 8. Feedback matrix

Intensity: ●○○ subtle · ●●○ clear · ●●● loud. Reduced-motion alternative in the last column.

| Event | Visual | Audio | Text | Int. | Reduce motion |
|---|---|---|---|---|---|
| Grab | item arcs to hold point, 1 px cyan tracer, squash 1.15→1.0 | `squelch_grab.ogg` (sock only), soft click | `AGARRADA` 400 ms | ●○○ | no tracer |
| Throw (any) | item ring detaches, 3 px motion smear for 120 ms | `throw_whoosh.ogg` | — | ●●○ | no smear |
| Throw PERFECT | 8 magenta sparks, 1-frame 2 px flash, ring pop | whoosh + pitched `ui_click` | `¡PERFECTO!` 44 px, 600 ms | ●●● | sparks ×3, no flash |
| Throw GOOD | 6 cyan sparks, smaller pop | whoosh | `BIEN` 32 px, 500 ms | ●●○ | sparks ×3 |
| Throw MISS | 3 grey puffs, ring collapses | whoosh (lower pitch) | `FUERA DE RITMO` 28 px, 500 ms | ●●○ | no collapse |
| Wrong washer | item bounces back, ✗ hologram, 6 px shake, red border 200 ms | `turbulent_alarm` −10 dB short | `LAVADORA EQUIVOCADA` | ●●● | no shake, ✗ stays 600 ms |
| Correct load | drum squash, 4 bubbles, slot fills with a clunk | `washer_drum` one-shot | `+3 s` wash time | ●●○ | no bubbles |
| Cycle start | drum spins on beat, progress ring appears | `washer_drum` loop −14 dB | — | ●○○ | — |
| Turbulence | orange strobe, steam ×2, floor path, timer ring | `turbulent_alarm` on beat | `¡TURBULENTA! GOLPE` | ●●● | no strobe, static icon |
| Strike resolves | ring bursts outward, drum calms, 1 beat of silence | short chime | `ESTABILIZADA` | ●●○ | burst ×1 |
| Explosion | 12 orange/yellow sparks, 8 px shake, 90 ms hitstop, drum opens | `washer_explode.ogg` | `−25 ESTABILIDAD` | ●●● | no shake/hitstop |
| Washer DONE | `LISTO` holo, drum glow, clean items ejected with sparkle + bubbles | `washer_done.ogg` | `¡LIMPIAS!` | ●●○ | no sparkle |
| Chute delivery | ring collapses, +points float up, stability chip +3 | `delivery_chime.ogg` | `+350 ×3` | ●●● | no float |
| Shredder loss | red `−8` chip at shredder, item vanishes | `turbulent_alarm` −12 dB | `PIEZA PERDIDA` | ●●○ | chip only |
| Phase change | banner + backdrop hue shift + drum pattern change | stem crossfade + `ui_click` | `FASE 2 · LLEGA LA CINTA SUR` | ●●● | banner only |
| Low stability | plaque pulse + heartbeat | heartbeat low | `¡ESTABILIDAD CRÍTICA!` | ●●● | static border |
| Shift end | fade to end screen (180 ms) | music resolves / stops | — | ●●● | fade only |

**Copy rules:** imperatives only. Never explain the mechanism ("pulsa para lanzar") when the
verb is already shown. Spanish, sentence case except the main verbs in caps for the pixel font.
No exclamation marks in tutorial copy (they read as shouting at 12 px); reserve `¡!` for alarm.

---

## 9. Typography and copy system

- **One family:** Silkscreen (OFL) Regular + Bold. No second face, ever.
- **Scale (px):** 40 / 28 / 20 / 16 / 14 / 12 / 10. Nothing below 10; body text never below 12.
- **Case:** ALL CAPS for labels and buttons (pixel font has a strong small-cap rhythm), sentence
  case for the mission ribbon and tutorial copy (longer strings read better).
- **Letter-spacing:** 0 for ≤14 px, +1 at 20 px, +2 at 40 px (Silkscreen is already wide).
- **Line height:** 1.35×; max 2 lines on any overlay; tutorial callouts max 46 chars.
- **Spanish specifics:** `ñ á é í ó ú ü ¿ ¡` are covered by Silkscreen (verified in
  `tools/verify_audio.py`); never abbreviate with accents stripped. Prefer `LAVADORA` over
  `MÁQUINA` (shorter to scan), `DUCTO` over `TOBOGÁN`, `TURNO` over `PARTIDA`.
- **Numbers:** clock `HH:MM` with a colon, score grouped `001 240`, combo `×4`, percentages `72%`
  (no space), stability never shown as a fraction.

---

## 10. Sound hooks (existing CC0 assets, no new dependencies)

| Moment | Asset | Bus | dB |
|---|---|---|---|
| Menu ambience | phase-1 stem at 60 % (low-pass? no — just −12 dB) | Music | −12 |
| Menu move / press | `ui_click.ogg` (2 pitches) | UI | −8 |
| Shift start | `washer_done.ogg` pitched down + `ui_click` | SFX | −10 |
| Throw | `throw_whoosh.ogg` | SFX | −6 |
| Grab sock | `squelch_grab.ogg` | SFX | −8 |
| Washer loop | `washer_drum.ogg` looping per active washer | SFX | −16 |
| Washer done | `washer_done.ogg` | SFX | −8 |
| Turbulence | `turbulent_alarm.ogg` on beat, 3 repeats then 2× slower | SFX | −9 |
| Explosion | `washer_explode.ogg` | SFX | −6 |
| Delivery | `delivery_chime.ogg` | SFX | −7 |
| Belt | `belt_hum.ogg` (one, shared) | SFX | −20 |

Rules: no sound plays more than 3× within 2 s; washer loops only while WASHING; the alarm
ducks the music by 3 dB while active (AudioServer bus volume tween).

---

## 11. Accessibility

1. **Colour is never the only channel.** Every colour-coded state also carries a glyph
   (▲ ● ■ for red/blue/yellow), a pattern icon, and text. Verified by a grayscale screenshot
   test (`tools/accessibility_check.gd` samples the frame, desaturates, asserts each washer's
   requirement is still distinguishable by shape).
2. **Contrast:** all HUD text ≥ 4.5:1 against its plaque (`metal_4` on `space_deep` ≈ 12:1;
   `metal_2` on `space_deep` ≈ 4.9:1). Captions at 12 px use `metal_3` when on busy art.
3. **Reduce motion** (`Settings.reduce_motion`): no camera shake, no hitstop, no full-screen
   flashes, particle counts ×0.35, grade popups fade instead of scale. The beat ring and
   progress rings stay (they are information, not decoration).
4. **Gamepad-first:** every screen navigable with d-pad/stick + A/B; focus order documented per
   screen; `B` always backs out; no action requires the mouse.
5. **Text size option:** HUD scale 100 % / 125 % (`Settings.ui_scale`), applied by scaling the
   two plaques (never the play field). Default 100 %.
6. **Timing:** tutorial window ×2; a `Tutorial` replay always available; pause is instant and
   never penalised.
7. **Skip everything:** tutorial skip, first-run skip, cutscene-free menus, ESC backs out.

---

## 12. Screens

### 12.1 Title
Layout: diorama full-bleed (dimmed 35 %), logo top-center-left at (96, 72) scaled ×4 from
`ui_logo` (640×192), tagline `LAVANDERÍA AL BORDE DEL VACÍO` 16 px `metal_2` under it.
Menu column at x = 120, y = 320: five items, 28 px Bold, 52 px row height, focus = `▶` caret at
x − 28 + cyan underline + label `metal_4`; unfocused `metal_2`. Bottom-right: version + seed +
`ESC` hint at 10 px. A small "RECORD" plaque shows the best rank/score from `Settings` (only if
a run exists — never invent data).

### 12.2 First-run prompt
A modal plaque 640×280 centred, `space_deep` 96 %, 2 px `metal_0`, cyan corner ticks.
Title `¿PRIMERA VEZ?` 32; body 2 lines 16; two buttons side by side, focus on
`HACER EL TUTORIAL` (the recommended action is the default focus — not the destructive one).

### 12.3 Pause
Full-screen dim 55 %, plaque 520×420 centred: `PAUSA` 40, then four rows (Reanudar, Reiniciar,
Opciones, Menú) + a controls block at 12 px in two columns (mover / apuntar / agarrar-lanzar /
golpe / pausa) + `Reduce motion` note if active. Resume is default focus.

### 12.4 Options
Plaque 760×520, two columns: **Audio** (master/music/SFX sliders + `Calibrar`), **Vídeo**
(fullscreen toggle, reduce motion toggle, HUD scale), **Juego** (tutorial: `Repetir tutorial`).
Every row is a focusable control with a value readout; sliders move with ←/→ and repeat.
`RESTABLECER` at the bottom, `VOLVER` always visible. Saves on change (no Apply button).

### 12.5 End screen
Plaque 720×560: verdict word (`TURNO COMPLETADO` / `DESGARRO UNIVERSAL`) 40 px in
`clean_green` / `hazard_orange`; a rank letter `S/A/B/C` 96 px with its colour; stats in a
two-column ledger (lavadas, entregadas, precisión, combo máx, puntos, semilla); buttons
`REPETIR` (default) and `MENÚ`. `REPETIR` restarts in < 0.5 s with the same seed; a secondary
`NUEVA SEMILLA` is available with →.

Rank colour: S `funk_magenta`, A `funk_cyan`, B `metal_3`, C `metal_1`. A loss is always C and
the rank letter is the only thing that scales in (240 ms).

---

## 13. Before → after intent (what the owner will judge)

| Screen | Before | After |
|---|---|---|
| Boot | straight into a moving shift, no frame | title diorama with logo, focus, ambience, fade |
| First run | none | prompt with recommended tutorial + persistent skip |
| Learn | 11 px bottom line of controls | 8 gated playable steps with highlights, 3 min |
| HUD | full-width 48 px bar, 4 competing numbers, bottom strip | two corner plaques, mission ribbon, beat dots, grade near action |
| Throwing | into empty space | into washers with visible requirements, reticle states, accept/reject |
| Goal | invisible | chute beacon + mission ribbon + end-screen rank |
| Failure | text label at 480 s | pause/end flow, rank, stats, instant restart |
| Room | flat shipped background | parallax, light pools, steam, decals, neon beat pulses, foreground |
| Feedback | a grade word appears | matrix §8: local, layered, accessible |

---

## 14. Performance budget (llvmpipe, 1280×720, 60 FPS)

| System | Budget |
|---|---|
| 2D lights | ≤ 8 PointLight2D, no shadows |
| Particles | ≤ 3 CPUParticles2D emitters, ≤ 120 particles total |
| Draw calls | ≤ 220; merge decals into one `_draw()` per layer where possible |
| Scripts | no per-frame `get_nodes_in_group` in `_process`; cache |
| Textures | atlas-free, 29 sheets already small; no new raster assets > 64×64 |
| Physics | 40 bodies, 60 Hz (measured 0.544 ms/tick) |
| Measure | `docs/PROGRESS.md` records a 60 s in-game trace FPS min/avg after integration |

If a rich effect costs > 1.5 ms/frame on llvmpipe, it is cut or reduced-motion-gated.

---

## 15. Non-goals (restraint)

- No second typeface, no gradients, no glow halos on art, no drop shadows on text beyond 2 px.
- No animated background behind HUD text.
- No tutorial video, no voice-over, no cutscene dialogue.
- No new palette colours. No new raster sprites unless CC0/OFL + provenance.
- No bottom instruction strip, no persistent control legend in the HUD, no tooltips on hover.
- No "juice" that obscures the play field: shake ≤ 8 px, hitstop ≤ 90 ms, flashes ≤ 1 frame.

---

## 16. Research addendum — measured refinements (supersedes §7 where they differ)

`docs/UX_RESEARCH.md` (21 sources, measured against this repo's own files) produced numbers that
override the first draft of §7 and parts of §3.8/§5. The binding changes:

1. **Pulse ring contracts over two beats, not one.** A single 423 ms beat at 142 BPM is not enough
   time to plan a move and aim. Contract 140 %→100 % over 2 beats (≈846 ms at 142 BPM), snap back in
   80 ms, extend the flash on the downbeat; add a small per-beat alpha accent so it still ticks at
   105 BPM. It is information, so it survives Reduce motion (only the scale snap is removed).
2. **Transient budget.** Every action-tied popup/burst lasts **≤ 0.45 × T_beat**:
   257 / 229 / 208 / 190 ms at 105 / 118 / 130 / 142 BPM. Grade words: 200 ms, not 380.
3. **Type floor.** No player-facing text below **12 px**; captions **14 px**; clock 40 px; ribbon 14 px.
   Silkscreen cap height is 0.70 em, so 9–11 px captions were the single worst readability defect.
4. **First 20 s:** no phase banner, no turbulence, no grade word, ≤ 2 text strings on screen, clock at
   00:00, only `rocky`+`solid` items. The starter item is placed within grab range (we place it 96 px
   from Pip instead of steering a belt item).
5. **Grades appear at the event**, never at screen centre — the chute occupies 576–704 × 296–424 and a
   centred 44 px label covers it.
6. **Shake is quantised to whole art pixels**, amplitude ∈ {4, 8} world px, decaying in 4 px steps.
   Vlambeer's 6 px kick is 1.5 art px here and would shimmer. No shake on the beat, no shake on a miss.
7. **No hitstop on graded actions** (it desyncs the player's internal clock); hitstop is reserved for
   explosions (33 ms) and gated by Reduce motion.
8. **Flash budget:** ≤ 25 % of screen area, at or below beat rate (142 BPM = 2.37 Hz).
9. **Contrast:** panel borders that carry meaning use `metal_1` (3.9:1), not `metal_0` (2.34:1).
   Captions use `metal_2` (4.9:1).
10. **Copy widths (Silkscreen):** 12/16/20/24 px fit ≈ 33/25/20/16 caps in 300 px. Persistent labels
    ≤ 12 chars @20 px (`ESTABILIDAD` = 166 px); contextual prompts ≤ 24 chars; buttons ≤ 14 chars.
    Spanish runs +20–60 % over English for short strings — size the zone, assert the string fits.

### 16.1 Tutorial — final seven-gate beat sheet (replaces §7's table)

The order is motor → concept → loop: a player who cannot move cannot be taught anything, and the
beat is the only novel concept. Stability loss is disabled until gate 7, so failure teaches without
punishing. Total ≈150 s at average pace, hard cap 240 s.

| # | Gate | Prompt (≤ 24 ch) | Success | Fail-forward |
|---|---|---|---|---|
| 1 | Move | `MUÉVETE` | 200 px travelled | after 4 s, dotted circle at 120 px |
| 2 | Grab | `AGARRA` | one grab | item steered inside `GRAB_RADIUS` |
| 3 | Throw | `LANZA` | one throw leaves the hold radius | aim assist ×1.5 until first success |
| 4 | Beat | `LANZA AL RITMO` | two throws ≥ GOOD | window widens to ±195 ms after 2 misses; granted after 3 |
| 5 | Match | `SUELTA AQUÍ` | one correct-colour insert (only the compatible washer is lit) | the wrong mouth bounces with `NO`, no penalty |
| 6 | Strike | `GOLPE AL RITMO` | one strike ≥ GOOD on a scripted turbulent washer | turbulence cannot explode in the tutorial |
| 7 | Deliver | `LLEVA EL LIMPIO AL DUCTO` | one clean delivery to the chute | beacon pulses every 2 s |

Skip: hold `ESC` 1 s or `START` → immediate skip, `tutorial_skipped = true`. Replay: title → Tutorial,
always available. Completion persists in `Settings.tutorial_completed`; nothing is gated behind it.

### 16.2 Evidence adopted for the screens

- The title keeps the owner's five entries but earns hierarchy through type size, not omission:
  `INICIAR TURNO` 28 px primary, `TUTORIAL`/`CALIBRACIÓN` 20 px, `OPCIONES`/`SALIR` 16 px dim.
- Every transition ≤ 250 ms and cancellable after 100 ms; no "press any key" gate; first frame
  interactive with the first item focused.
- Pause shows objective + controls (GAG: "remind controls and objectives"); End defaults to REPETIR.
- Options keeps one focus order across two columns (≤ 6 rows per column) so it is never more than
  one level deep.

### 16.3 What the research says we should NOT do (kept as guardrails)

- Do not widen the PERFECT/GOOD windows to "be kind": the 45.5 %–61.5 % random on-beat rate is our
  only skill axis. Kindness goes into the tutorial window (×2) and fail-forward, not into scoring.
- Do not make everything diegetic: object state in the world, global state in the corners.
- Do not add a second typeface, gradients, glows, or a per-light normal-map pipeline.
- Do not add a HUD queue/stack of every item: one body, four fixed machines; show the next deadline,
  not a spreadsheet.

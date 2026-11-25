# The Tutorial — seven gates on the real systems

*Cosmic Spin Cycle · owner: tutorial workstream · binding spec: `docs/UX_BIBLE.md` §16.1*

The owner said the game taught them nothing. This tutorial is the answer: **2–4 minutes,
skippable at every moment, replayable forever, and it runs the real `MainLevel`** — real
player, real physics, real washers, real chute. No fake screens, no scripted cinematics, no
"press any key" gates. It ends with a complete wash → strike → deliver cycle, which is the
whole game in miniature.

```
title → TUTORIAL (always available) → 7 gates → TURNO DE PRUEBA COMPLETADO → title
                                   ↘ ESC/START → ¿SALTAR TUTORIAL? → title
```

Completion is stored in `Settings.tutorial_completed`; skipping in
`Settings.tutorial_skipped`. **Nothing is gated behind either flag** — the tutorial never
locks content, it only stops the first-run recommendation.

---

## 1. The seven gates

Order is motor → concept → loop. A player who cannot move cannot be taught anything, and the
beat is the only genuinely new idea, so the beat arrives before the washing loop and comes
back for the strike.

| # | Gate | Prompt (≤ 24 chars) | Success | Fail-forward |
|---|---|---|---|---|
| 1 | `MUÉVETE` | `WASD / STICK` | 200 px travelled | after 4 s a dotted circle at 120 px |
| 2 | `AGARRA` | `ESPACIO O BOTÓN A` | one grab | after 6 s the item is steered inside `GRAB_RADIUS` |
| 3 | `LANZA` | `APUNTA Y LANZA` | one throw that leaves the hold | the item is re-staged if it flies away |
| 4 | `LANZA AL RITMO` | `ESPERA EL PULSO` | two throws ≥ GOOD | window widens after 2 misses, gate granted after 3 |
| 5 | `SUELTA AQUÍ` | `SUELTA EN LA ROJA` | one insert into the lit washer | a wrong mouth answers `NO ES ESA`, no penalty |
| 6 | `GOLPE AL RITMO` | `SHIFT AL PULSO` | one strike ≥ GOOD on the scripted turbulent washer | the washer cannot explode; re-forced, then an assisted GOOD strike |
| 7 | `LLEVA EL LIMPIO AL DUCTO` | `AL DUCTO DEL CENTRO` | one clean delivery | beacon reticle on the chute, pulsing every 2 s |

Then the plaque: **TURNO DE PRUEBA COMPLETADO** + `CONTINUAR` (any input) →
`MainLevel.complete_tutorial()`.

Gate titles are 20 px bold `metal_4`, prompts 14 px `metal_2`. One prompt at a time, anchored
to the object it is about (above the item / washer mouth / chute), never a modal — see
`docs/media/tutorial_step2.png`, `tutorial_beat.png`, `tutorial_deliver.png`.

### Safety nets (nobody is ever trapped)

| Net | When | What happens |
|---|---|---|
| Stability guard | gates 1–6 | `GameState.stability_protected = true`, so nothing can end the run |
| TAB soft-skip | 12 s stuck on a gate | grants that gate and moves on; the footer reads `TAB · SALTAR PASO` |
| Gate 4 grant | 3 misses | the gate is granted so a deaf or laggy player still reaches the loop |
| Gate 4 widening | 2 misses | the GOOD window grows by ×1.5 on top of the tutorial window |
| Gate 6 assist | 10 s / 20 s | re-force turbulence, then the director lands a GOOD strike on the same washer |
| Gate 7 beacon | immediately | a green reticle on the chute, so "ducto" is never a guess |
| Skip | ESC / START at any time | `¿SALTAR TUTORIAL?`, default focus **NO** |

The guard is cleared on **every** exit path — complete, skip, or the node being freed
(`TutorialRoot._exit_tree`).

---

## 2. Architecture

```
scenes/main/Tutorial.tscn           TutorialRoot (Node2D)
├─ MainLevel (MainLevel.tscn)        mode = "tutorial", fixed seed 7001, no spawner
├─ Overlay  (TutorialOverlay.tscn)   CanvasLayer 25: chip, world prompt, plaques, FX
└─ Director (TutorialDirector.gd)    Node: stages gates, listens, feeds the step machine
```

| File | Role |
|---|---|
| `scripts/tutorial/TutorialSteps.gd` | **Pure** 7-gate table + gating logic. No node, no audio. `advance(state, event)` is the only mutator. |
| `scripts/tutorial/TutorialDirector.gd` | Thin adapter: stages each gate's world state, listens to `Player`/washer/chute signals, feeds one event per frame. Every M4 system is behind `has_method`/`has_signal` guards. |
| `scripts/tutorial/TutorialRoot.gd` | Wiring + input: re-emits `tutorial_completed` / `tutorial_skipped` for `App.gd`, routes pause → skip plaque, TAB → soft-skip, any input → continue. |
| `scripts/ui/TutorialOverlay.gd` | Everything the player reads: step chip, world prompts, skip/completion plaques, dotted hint circle, beat ring, chute reticle. |

Why the split: the gate logic is a pure function of `(state, event)`, so all 30 thresholds and
fail-forward paths are unit-tested without a level (`tests/unit/test_tutorial_steps.gd`), and
the director is small enough to read in one sitting.

### Events the director feeds

| Event | Source | Used by |
|---|---|---|
| `{kind: travel, delta}` | player position delta per frame | gate 1 |
| `{kind: grab}` | `Player.grabbed` | gate 2 |
| `{kind: throw, left_hold, delta_t, grade}` | `Player.thrown` + Δt from `BeatConductor` | gates 3, 4 |
| `{kind: insert, correct}` | washer `item_loaded` or a `get_loaded_items()` poll | gate 5 |
| `{kind: strike, grade}` | `Player.struck` + Δt from `BeatConductor` | gate 6 |
| `{kind: deliver, clean}` | `DeliveryChute.delivered` | gate 7 |
| `{kind: tick, delta}` | `_process` | dwell, hints, soft-skip |
| `{kind: skip}` | TAB / debug | every gate |

`left_hold` is measured from **Pip's body**, not the prompt anchor: a held item sits at
`player + aim × 48`, so it is inside `GRAB_RADIUS` (64 px) and only a real throw clears it.

### Rhythm windows

The tutorial grades its own gates with the tutorial tolerance, and never punishes harder than
the grade the player already saw (`mini(player_grade, tutorial_grade)`):

* gate 4 base GOOD window: `max(195 ms, WINDOW_GOOD_S × TUTORIAL_WINDOW_SCALE)` = **±260 ms**
* after 2 misses: ×1.5 → **±390 ms**, and the gate is granted after 3 misses
* gate 6: flat `STRIKE_WINDOW_SCALE` (×2), and the washer cannot explode

`±195 ms` from UX_BIBLE §16.1 is honoured as a **floor**: if balance tunes
`TUTORIAL_WINDOW_SCALE` down, the gate never gets stricter than 195 ms. (The doc's "widen to
195" would otherwise *narrow* the ×2 window, which is why the operative widening multiplies
the base and the constant stays as the floor.)

---

## 3. Persistence keys

| Key (`user://settings.cfg`, section `game`) | Written by | Effect |
|---|---|---|
| `tutorial_completed` | `MainLevel.complete_tutorial()` → `Settings.mark_tutorial_completed()` | clears `tutorial_skipped`, sets `first_run_done`, stops the first-run prompt |
| `tutorial_skipped` | skip plaque → `Settings.mark_tutorial_skipped()` | sets `first_run_done`, never re-asks |
| `first_run_done` | both of the above | the prompt never nags again |

Replaying is unconditional: `TUTORIAL` is always on the title and always starts at gate 1.

---

## 4. Debug / evidence hooks

`tools/screenshot.gd` forwards user args to the scene, so the tutorial can be photographed at
any gate without playing:

```bash
godot --path . -s tools/screenshot.gd --audio-driver Dummy --display-driver wayland \
  --rendering-method gl_compatibility -- \
  --scene=res://scenes/main/Tutorial.tscn --out=res://docs/media/tutorial_step2.png \
  --frames=90 --tutorial-step=1
```

| Flag | Effect |
|---|---|
| `--tutorial-step=N` | jump to gate N (0-based) |
| `--tutorial-elapsed=S` | pretend the gate has been stuck for S seconds (hints, TAB footer) |
| `--tutorial-plaque=skip` | open the skip plaque |
| `--tutorial-plaque=complete` | open the completion plaque |
| `--tutorial-autoplay` | walk all seven gates on a 0.9 s timer (smoke test) |

API hooks on the director: `debug_advance()`, `debug_goto(index)`, `debug_set_elapsed(s)`,
`autoplay`, `debug_delta_t`.

---

## 5. Tests

| File | Covers |
|---|---|
| `tests/unit/test_tutorial_steps.gd` | table order/copy/widths, 200 px travel, travel only on gate 1, grab, throw leaving hold, 2 GOOD throws, widening + grant after 3 misses, wrong-washer rejection, strike grading, clean-only delivery, TAB soft-skip, immutability of a granted gate |
| `tests/unit/test_tutorial_director.gd` | start on gate 1, no auto-advance, staging per gate, wrong mouth ignored, washer locking/restoring, gate 7 drops the guard, exit always clears it, assisted strike, autoplay to the end — with a fake level so the M4 merge cannot break it |
| `tests/unit/test_tutorial_overlay.gd` | chip/underline, prompt anchoring above the anchor, 24-char budget, plaques and their signals, reduce-motion, TAB footer bounds, world→screen mapping |
| `tests/integration/test_tutorial_flow.gd` | `Tutorial.tscn` boots the real level in tutorial mode, chip + prompt at gate 1, guard on/off, pause → skip plaque, skip and completion persistence and re-emission, replay never blocked |

The real-washer end-to-end test is marked **pending** in this worktree: `CosmicWasher.tscn`
and `DeliveryChute.tscn` are owned by the `core-loop` workstream and are absent here. The
director already speaks their documented API (`configure`, `get_requirement`, `set_locked`,
`get_state`, `get_loaded_items`, `force_turbulent`, `force_finish`, `strike`,
`get_mouth_world`, `delivered`), and the fakes in `test_tutorial_director.gd` mirror it, so the
merge should light the pending test up without code changes.

---

## 6. Evidence

| Image | Gate | What it proves |
|---|---|---|
| [`tutorial_step2.png`](media/tutorial_step2.png) | 2 · AGARRA | chip `PASO 2/7`, world prompt over the item, prompt avoids Pip |
| [`tutorial_beat.png`](media/tutorial_beat.png) | 4 · LANZA AL RITMO | beat ring contracting on Pip's feet, `ESPERA EL PULSO` |
| [`tutorial_deliver.png`](media/tutorial_deliver.png) | 7 · LLEVA EL LIMPIO AL DUCTO | clean item + green chute reticle with corner brackets |
| [`tutorial_skip.png`](media/tutorial_skip.png) | skip | dimmed field, `¿SALTAR TUTORIAL?`, default focus **NO** |

Rendered with `--display-driver wayland --rendering-method gl_compatibility` (software GL is
fine) at exactly 1280×720. Three review passes were made: (1) chip/anchors, (2) plaques and
beacon legibility, (3) beat ring, reticle brackets and the TAB footer. Current self-score:
hierarchy 4–5, clarity 4–5, readability 5, *would a stranger know what to do* 4–5.

---

## 7. Layout contract

* The chip lives in the top safe band (`y 56–102`, below the 48 px HUD bar, inside the
  `y 0–104` band). It never covers a washer mouth or the chute.
* The world prompt is 24 px above its anchor and clamped to `y ≥ 108`; if the anchor lands on
  Pip's sprite the prompt slides sideways instead of covering the character.
* The TAB footer sits at `y 664`, right-aligned, and only appears when TAB is legal.
* Washers' mouths sit at world `y 320` (north) and `y 576` (south); the chute at `y 360`, so
  nothing in the tutorial's UI layer can occlude them.

## 8. Known limitations

* The HUD still shows the shift clock during the tutorial. The chip carries `PASO n/7`; a real
  `HUD.set_tutorial_mode()` (owned by the HUD workstream) would swap the clock for the chip and
  is the better long-term home for the step progress.
* With the washer/chute scenes absent, gates 5–7 can only be cleared with TAB, and the chute
  reticle anchors to `data/layout.json` instead of a live `DeliveryChute`. Gate 7 stages a clean
  item directly in that case so the flow is still observable.
* The beat ring is procedural (drawn by the overlay) rather than the diegetic `PulseRing` the
  HUD will own; when that lands, gate 4 can drop its own ring and point at the HUD's.

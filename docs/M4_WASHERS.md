# M4 — Washers and the delivery chute

*Implementation note for the core loop (`ws/core-loop`). Player-facing copy is Spanish; every
symbol below is the real API the lead wires into `MainLevel`.*

![Washer sandbox](media/m4_washers.png)

*`scenes/dev/WasherSandbox.tscn` — NW idle + matching carry, NE washing, SW turbulent, SE
locked, centre chute carrying a clean item.*

---

## 1. What M4 adds

| File | Role |
|---|---|
| `scripts/logic/WasherFSM.gd` | Every washer rule, pure and deterministic |
| `scripts/logic/WasherAssignments.gd` | Phase → four `(requirement, locked)` rows + coverage |
| `scripts/logic/ScoreRules.gd` | Delivery points, S/A/B/C rank, end-screen summary |
| `scripts/logic/ShiftRules.gd` | Win/lose evaluation, Final Load kept as stats only |
| `scripts/entities/CosmicWasher.gd` + `.tscn` | Machine node: renderer + event forwarder |
| `scripts/entities/WasherFX.gd` | Procedural holo/ring/gauge/chip/text visuals (no assets) |
| `scripts/environment/DeliveryChute.gd` + `.tscn` | The goal: clean-only delivery |
| `scenes/dev/WasherSandbox.gd` + `.tscn` | Dev/screenshot playground |
| `tests/unit/test_washer_fsm.gd` etc. | 64 new tests (suite total 379) |

## 2. WasherFSM

`extends RefCounted`, no scene, no autoload clock, no rendering. Time enters **only** through
`tick(dt)`; every rule input is an explicit call. That is what makes the whole loop
table-testable.

States: `IDLE → WASHING → (TURBULENT) → DONE`, and any state `→ BROKEN`, which repairs to
`IDLE` after `REPAIR_COOLDOWN_S` (6 s).

Mutators return a bool and queue events; `tick(dt)` advances time and returns the queue
(draining it); `take_events()` drains without advancing.

| Event | Payload | Meaning |
|---|---|---|
| `washing_started` | `cycle_time` | the drum started |
| `progress` | `progress`, `remaining`, `cycle` | one tick of wash progress |
| `turbulent` | `limit`, `reason` | entered TURBULENT (`cycle`/`accumulated`/`forced`) |
| `turbulence_resolved` | `grade` | a GOOD/PERFECT strike calmed it |
| `cycle_done` | `items` | the load is clean and collectable |
| `exploded` | `items`, `reason` | the drum collapsed (`turbulence`/`forced`) |
| `repaired` | — | usable again |

Rules as implemented (all covered by tests):

* **Capacity 3 slots.** `gas_giant` = 2, `galaxy_core` = 3 and a wildcard that needs an
  **empty** washer. `Compatibility.item_fits` decides colour/pattern requirements.
* **Cycle length** = `max(item.wash_s)` over the load, floored at
  `Config.MIN_WASH_TIME_S` (2 s); `Config.WASH_BASE_S` only for an empty explicit start.
* **Start** when the slots become full, or on an explicit rhythm strike with ≥ 1 item. No
  auto-timeout.
* **Beat reductions** (`PERFECT -3 s`, `GOOD -1 s`) apply once per throw. Before the cycle
  starts they are stored and consumed at `start_cycle`; while washing they hit `remaining`
  immediately. They never take `remaining` below 2 s and never *raise* a cycle that is
  already under the floor.
* **Turbulence** is 0..1; `≥ 1.0` enters TURBULENT. From phase index 2 (the GDD's phase 3)
  every 3rd cycle enters TURBULENT at 50 % progress (`AUTO_TURBULENCE_PHASE`). A MISS throw
  adds `Config.MISS_TURBULENCE_GAIN`. The limit is `min(5 s, 8 × beat)`.
* **Timeout** explodes; a strike of grade ≥ GOOD resolves (`RhythmEvaluator.resolves_turbulence`).
  During TURBULENT the wash keeps counting down but cannot complete until resolved.
* **DONE** waits `DONE_SETTLE_S` (0.35 s) before `collect()` releases the load, so the `done`
  animation can play.
* **BROKEN** clears the load (the event carries it) and auto-repairs after 6 s.

## 3. Washer assignments (the onboarding ramp)

| Phase | NW | NE | SW | SE |
|---|---|---|---|---|
| P1 (0–120 s) | `red` | `blue` | *locked* (`solid`) | *locked* (`spotted`) |
| P2 (120–270 s) | `red` | `blue` | `solid` | *locked* (`spotted`) |
| P3 (270–420 s) | `red` | `blue` | `solid` | `spotted` |
| P4 (420–480 s) | `yellow` | `red` | `solid` | `ringed` |

Locked rows are **pre-wired** with the requirement they will have when they unlock, so a
phase change only flips the lock. A locked washer never accepts and never costs stability.

`MainLevel` reads a phase with one call:

```gdscript
var assignments := WasherAssignments.for_phase(phase)
# { "washer_nw": {"requirement": &"red",   "locked": false},
#   "washer_ne": {"requirement": &"blue",  "locked": false},
#   "washer_sw": {"requirement": &"solid", "locked": true},
#   "washer_se": {"requirement": &"spotted", "locked": true} }   # P1
for washer_id in assignments:
    var washer: CosmicWasher = washers[StringName(washer_id)]
    var row: Dictionary = assignments[washer_id]
    washer.set_requirement(StringName(str(row["requirement"])))
    washer.set_locked(bool(row["locked"]))
```

`for_phase`, `requirement_for`, `is_locked` and `coverage_ok` are the four public names.

### Why this ramp

* **P1 — red/blue only.** The two first item colours of the GDD, one machine each, and the
  south half *visible but offline*. The first 20 seconds ask one question ("which colour?"),
  and an offline machine teaches the `FUERA DE SERVICIO` language without punishing anyone.
* **P2 — add `solid`.** Colour reading is established, so the first *pattern* home arrives.
  `ringed` items already have a colour home; the pattern washer is a shortcut, not a new
  failure mode, which keeps the phase-2 difficulty curve about throughput, not reading.
* **P3 — add `spotted`.** The phase where turbulence starts, so the player must read colour
  **and** pattern while the orange alarm is running. Yellow spawns from P3, and the blue/red
  colour homes still cover their own variants.
* **P4 — `yellow` + `red`, `solid` + `ringed`.** The final load is the climax: the north
  pair swaps blue for yellow so the *palette* visibly changes at 05:15 (warm machines, warm
  convoy) without changing the verb. `solid` stays (it has been online since P2) and `ringed`
  replaces `spotted` to keep the two pattern homes the ramp has taught. Red and yellow
  variants always fall back to a colour home; a blue variant can only reach `solid`/`ringed`,
  which is exactly the documented gap.

### The mathematical limit behind the gap

`Compatibility.item_fits` matches a washer on **one** channel: colour *or* pattern. Two
colour washers cover `2 × 3 = 6` variants; two pattern washers can cover the third colour in
only two of its three patterns. Four washers therefore top out at **8 of 9** variants. The
shipped ramp reaches that maximum; the missing one is `yellow_ringed` in P3 and `blue_spotted`
in P4. A `wild` washer (or a per-colour pattern restriction in `data/phases.tres`) would close
it, but both are outside this file's ownership.

### Known coverage gap (reported, not silently patched)

A requirement is a colour **or** a pattern, so four washers split 2 colours + 2 patterns cover
at most **8 of the 9** variants: the two colour washers take six, and the two pattern washers
can only reach the third colour in two of its three patterns.

* P3 leaves **`yellow_ringed`** without a home.
* P4 leaves **`blue_spotted`** without a home.

`WasherAssignments.coverage_ok(phase)` reports this honestly and
`uncovered_variants(phase)` names the orphans; `test_washer_assignments.gd` pins the exact
gap so a future fix updates both. Fix options for the lead (both outside this workstream's
ownership): restrict a phase's `allowed_patterns` per colour in the frozen `data/phases.tres`,
or make one washer per phase `wild`. Until then those two variants can be washed nowhere.

## 3.5 Feedback (measured UX notes)

The UX research measured the greybox feedback and fixed these rules; they override the
earlier "juice" defaults.

| Event | Local feedback | Duration |
|---|---|---|
| Correct insert | mouth rim `clean_green` 1 frame; drum loop + chime start **on the next beat** | 1 frame + beat |
| Wrong washer | `-12` chip at the mouth (down triangle + number + orange), porthole `red_1` 1 frame, item bounced, ~120 ms buzz. **No camera shake.** | 180 ms |
| Turbulence | persistent `TURBULENTO` label (14 px), 3-segment gauge + deadline countdown, orange porthole, 1 art px vibration @ 2 Hz, **2 alarm beeps then silence** | persistent |
| Clean done | `fx_bubbles` loop, 1 px `clean_green` rim, two bell notes | 180 ms + hold |
| Explosion | `fx_explosion` (6 frames @ 12 fps), `¡EXPLOSIÓN!` 24 px at the machine, 8 px shake in 4 px steps | 180 ms |
| Chute delivery | `accept` 3 authored frames, item shrinks into the iris, `+points` flies ≤ 200 px to the counter, `+3` chip at the chute | 200 ms / 180 ms |

* **Feedback budget:** every action feedback is `0.45 x T_beat` or shorter — 257/229/208/190 ms
  at 105/118/142 BPM. `CosmicWasher.FEEDBACK_S = 0.18` is the fixed value used for chips,
  flashes, the explosion shout and the points flight; only the turbulence label and gauge are
  persistent. The one authored exception is the chute's `accept` animation, which is exactly
  the 3 frames the sheet provides (250 ms at 12 fps); every added flash, chip or flight is
  `FEEDBACK_S`.
* **Colour is never the only channel.** Stability chips always carry a triangle glyph, the
  number and the colour (`red_1` alone is 1.82:1 on the background — effectively invisible).
* **Out of this workstream:** the camera hitstop (33 ms max), camera shake (8 px max) and the
  ≥ 300 ms stability-bar slide belong to `MainLevel`; the shredder's `-8` chip + 6 px sparks
  belong to `scripts/environment/Shredder.gd` (M3 owner). This branch only emits the events
  and keeps the local feedback small.

## 4. CosmicWasher node

Root `StaticBody2D` on `WASHER | WORLD` (**deviation:** the frozen player/item masks only
collide with `WORLD`, so the machine body carries both bits; masks are `0`). The root sits on
the mouth, so `mach_washer`'s bottom-centre pivot lands on the machine base.

State ordinals are a frozen contract for the camera punctuation: `IDLE=0`, `WASHING=1`,
`TURBULENT=2`, `DONE=3`, `BROKEN=4` (`CosmicWasher.State`, mirrored by `WasherFSM.State` and
asserted in `test_washer_scene.gd`).

Children after `_ready`: `Visual` (AnimatedSprite2D ×4, `centered=false`, `offset=-pivot`,
never rotated), `Holo` (procedural plaque + two `ui_holo_icons` glyphs + one text line),
`ProgressRing` (procedural arc around the drum), `Mouth` (Area2D, layer 0, mask ITEMS,
r = 60), `Audio` (`washer_drum` loop on SFX) plus three one-shot players, `SteamAnchor`.

**Holo anchors adapt to the frozen layout.** The north machines carry the panel 40 px above
them; the south row has only 64 world px between rows, so its panel is drawn 40 px **below**
the machine (`HOLO_ORIGIN_BELOW`). Colour is never the only channel: every state has a glyph
and Spanish text (`ROJO`, `NO COMPATIBLE`, `LAVANDO 64%`, `TURBULENTO`, `LISTO`, `AVERIADA`,
`FUERA DE SERVICIO`). Locked machines dim the sprite to 55 % and drop their glow.

Side effects (the authority): wrong washer `-12` + `wrong_washer_count`; explosion `-25` +
`exploded_count`; each clean item `+1 washed_count`, guarded per instance. A locked washer and
a wildcard rejection never cost stability; a full washer is not "wrong" either.

## 5. DeliveryChute node

Root `Area2D` on `CHUTE`, mask `ITEMS`. Signals: `delivered(item, points)` and
`dirty_rejected(item)`. Only `item.is_clean` delivers: `+3` stability,
`delivered_count += 1`, `score += item.points × combo` through `GameState.add_score`, chime,
`accept` animation, a `+3` chip at the chute and a `+points` label that flies at most 200 px
towards the HUD counter (no flight under reduce motion; the counter pulse is the HUD's). The
item shrinks into the iris for 200 ms (capped at `0.45 x T_beat`) and is then freed. Dirty items bounce out with
`LAVA PRIMERO` for 1.2 s and **no** penalty. Delivery is guarded per instance id, so a double
callback cannot pay twice.

The beacon (rotating dashed ring + outer pulse + 3 chevrons + label) and the floating points
are procedural; the hatch is the shipped `env_chute` sheet, with palette rings as fallback.

## 6. Provisional constants (promote to `Config` when signed off)

`WasherFSM`: `DONE_SETTLE_S = 0.35`, `REPAIR_COOLDOWN_S = 6.0`, `AUTO_TURBULENCE_PHASE = 2`,
`AUTO_TURBULENCE_EVERY = 3`.
`CosmicWasher`: `MOUTH_RADIUS = 60`, `BODY_SIZE = (176,176)`, `BODY_CENTER = (0,-96)`,
`EJECT_OFFSET`, `EJECT_IMPULSE`, `EXPLODE_IMPULSE`, `BOUNCE_IMPULSE`, `REJECT_COOLDOWN_S = 0.6`,
`RELEASE_COOLDOWN_S = 0.4`, `HOLO_GAP = 40`, `HOLO_ORIGIN(_BELOW)`, `SHAKE_PX = 6`,
`SHAKE_TIME_S = 0.26`, `LOAD_FLASH_S = 0.18`, `ALARM_MAX = 3`, audio dB values.
`CosmicWasher` feedback: `FEEDBACK_S = 0.18`, `RIM_FRAME_S = 0.02`, `BUZZ_S = 0.12`,
`BELL_GAP_S = 0.15`, `EXPLOSION_SHAKE_PX = 8`, `SHAKE_STEP_PX = 4`,
`TURBULENCE_VIBRATION_PX = 4` (1 art px @ 2 Hz), `ALARM_BEEPS = 2`.
`DeliveryChute`: `BEACON_RADIUS = 44`, `HINT_RADIUS = 84`, `HATCH_RADIUS = 64`,
`REJECT_LABEL_S = 1.2`, `ACCEPT_ANIM_S = 0.25` (3 frames @ 12 fps), `SWALLOW_S = 0.2`,
`POINTS_FLIGHT_PX = 200`, `COUNTER_HINT = (1124, 52)`, `FEEDBACK_S = 0.18`,
`BOUNCE_IMPULSE = 340`.
`ScoreRules.REFERENCE_COMBO = 4` (the documented max-possible assumption).

## 7. Wiring checklist for the lead

```gdscript
# once, from layout.json (washers: rect + mouth in art px)
washer.configure(&"washer_nw", Rect2(36, 32, 48, 48), Vector2(60, 80), &"red")

# at a phase boundary (one call, then a loop over four entries)
var assignments := WasherAssignments.for_phase(phase)
for washer_id in assignments:
    var w: CosmicWasher = washers[StringName(washer_id)]
    var row: Dictionary = assignments[washer_id]
    w.set_phase(phase)
    w.set_requirement(StringName(str(row["requirement"])))
    w.set_locked(bool(row["locked"]))

# per frame / on carry changes
washer.set_carry_hint(player.held_item)
player.struck.connect(func(w, grade): w.strike(grade))

# the chute
chute.configure(Rect2(144, 74, 32, 32), Vector2(160, 90))
chute.set_carry_hint(player.held_item)

# end screen
var summary := ScoreRules.summary(
    GameState.get_end_result(), ScoreRules.max_possible_score(schedule)
)
```

`MainLevel` still owns the HUD, the mission ribbon, the reticle and the end screen; the nodes
expose `get_glow_color()` for the lighting layer and `get_mouth_world()` for aiming.

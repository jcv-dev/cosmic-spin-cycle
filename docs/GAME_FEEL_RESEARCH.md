# Game-Feel Research — *Cosmic Spin Cycle*

**Author:** UX/Game-Design Research Lead · **2026-11-24** · branch `ux/research`
**Scope:** movement, camera, impact, throw feel and playtesting for Pip. Docs only.
**Method:** 6 new sources ([S22](UX_RESEARCH_SOURCES.md#s22)–[S27](UX_RESEARCH_SOURCES.md#s27)) on top of the 21 in the [UX appendix](UX_RESEARCH_SOURCES.md); all six read in full. Every number is sourced, measured from our constants, or labelled **[inference]** with the arithmetic.

**Starting point (from `AGENTS.md` §A5 and `CONTRACTS.md`):** accel 2400 px/s², vmax 340 px/s, friction `v *= 0.88^(60·dt)`, grab ≤ 64 px, hold 48 px, throw 900 px/s, dash 120 px in 0.18 s (= the rhythm strike), fixed camera, 60 Hz physics, 105–142 BPM.

---

## 0. Summary

Movement today is "functional and lifeless" for a measurable reason: **the numbers describe a game with 47 px of stopping slide, no input buffer, no camera response and no impact vocabulary.** The fix is not more effects — it is a small set of numbers and windows, each with a known target. Three findings drive the whole document:

1. **Our latency budget is tighter than our rhythm window.** Godot accumulates input by default ("all input events generated during a frame will be merged and emitted when the frame is done rendering"), and `use_accumulated_input` can be disabled "to get slightly more precise/reactive input" ([S24](UX_RESEARCH_SOURCES.md#s24)). At 60 Hz that is up to 16.7 ms of hidden latency on top of tick + render + display — enough to push us past the ±65 ms PERFECT window.
2. **Juice has an optimum, not a maximum.** A large-scale study found medium and high juiciness beat both extreme juiciness and none across player experience, motivation, play time and performance ([S22](UX_RESEARCH_SOURCES.md#s22)). Our budget table below is therefore bounded, not aspirational.
3. **The camera should never rotate.** The canonical trauma-shake recipe includes ±10° of roll ([S23](UX_RESEARCH_SOURCES.md#s23)); at 320×180 that would rotate the pixel grid and shimmer. We take the trauma model and drop the rotation.

---

## 1. Responsiveness and frame data

**Budget** (60 Hz, 1280×720, vsync on) **[inference; each term is one frame unless noted]**:

| Stage | Cost | Notes |
|---|---|---|
| OS/device poll → engine | 1–8 ms | keyboard vs XInput; unbounded, measure it |
| Input accumulation (`use_accumulated_input` = true by default) | 0–16.7 ms | merged "when the frame is done rendering" ([S24](UX_RESEARCH_SOURCES.md#s24)) |
| Event → physics tick | 0–16.7 ms | `_input()` fires immediately; `_physics_process` waits for the tick |
| Render + present | 16.7–33 ms | 1–2 frames |
| Display scan-out | 8–16 ms | panel-dependent |
| **Total** | **~50–75 ms typical, ~90 ms worst case** | ±65 ms PERFECT window ⇒ **we are grading near the noise floor** |

Two rules follow. **(a)** Keep rhythm evaluation in `_input()` (already `AGENTS.md` §A2.7) and set `input_devices/buffering/agile_event_flushing` or disable `use_accumulated_input` for the gameplay window, then re-measure. **(b)** Log `Input.get_ticks_usec()` at press and at grade emission; if the delta exceeds **25 ms** on the dev box, the tuning is invalid.

**Buffering** — same window for every player action, because inconsistency reads as unreliability:

| Window | Value | Why |
|---|---|---|
| Action buffer (grab / throw / strike) | **120 ms** (7 frames) | inside the 100–150 ms range used for jump buffering; Braid buffers 0.23 s, Mario 1–2 frames ([S22](UX_RESEARCH_SOURCES.md#s22)) |
| Grab "coyote" (grab still valid after leaving 64 px) | **100 ms** | coyote time is the canonical "support the player's intent" mechanism ([S22](UX_RESEARCH_SOURCES.md#s22)) |
| Throw-release tolerance (release slightly early) | **60 ms** | one third of a beat at 105 BPM; hides finger timing |
| Buffer consumption | on fire, clear it | never let one press trigger two actions |

Implement all windows in **seconds**, never frames, so a 144 Hz build behaves identically.

---

## 2. Movement: three candidate feels

Our current tuning reaches vmax in **142 ms / 24 px** (340 ÷ 2400; 340² ÷ 2a) — snappy up front — but coasts **47 px** and takes **300 ms** to reach 10 % speed under `0.88^n` at 60 Hz **[inference: Σ 340·0.88ⁿ/60 = 47.2 px; ln 0.1 / ln 0.88 = 18 frames]**. That mismatch (instant start, floaty stop) is the "lifeless" signature: it reads as ice, not weight.

| Parameter | A · Floaty | B · Snappy (recommended) | C · Weighty |
|---|---|---|---|
| `ACCEL` px/s² | 1600 | **2400** | 1200 |
| `MAX_SPEED` px/s | 360 | **340** | 300 |
| Friction factor / frame | 0.92 | **0.80** | 0.86 |
| Time to vmax | 225 ms | **142 ms** | 250 ms |
| Stop distance / time to 10 % (own max speed) | 75 px / 460 ms | **28 px / 172 ms** | 36 px / 254 ms |
| Turn-around (180°) | 450 ms | **283 ms → 212 ms with ×2 opposing accel** | 500 ms |
| Dash | 120 px / 0.18 s | **same, +1 frame squash** | 100 px / 0.20 s |
| Reads as | slippery, low stakes | **arcade, readable, forgiving** | heavy, deliberate, punishes |

**Recommendation: B, with a turn-around boost.** Reasoning: the loop is 4.4–6.0 beats long (UX doc §12), so the player changes direction 3–6 times per delivery; at 0.92 friction each reversal costs 450 ms ≈ 0.79–1.06 beat of drift — a full beat at 142 BPM, which is exactly the beat the player is trying to hit. B roughly halves that (283 ms), and the ×2 opposing acceleration (4800 px/s² while input opposes velocity) cuts it to **212 ms, i.e. 0.37–0.50 of a beat**, so a correction never eats the next hit.

**Why these three and not something else.** Swink frames feel as "real-time control of virtual objects in a simulated space, with interactions emphasised by polish" ([S22](UX_RESEARCH_SOURCES.md#s22)) — control, space, polish. A top-down game has no gravity axis, so two famous answers do not transfer: **Sonic-style momentum** (slope- and curve-driven acceleration) has nothing to conserve, and **Mario's parabola** (asymmetric rise/fall, terminal velocity) has no fall. What is left is *horizontal* control: how fast velocity is granted, revoked, and reversed. The three profiles above are exactly that triangle.

Also required regardless of profile: **normalise 8-way input** (diagonal must be 340, not 481 px/s), and shape the analog stick with a radial deadzone of **0.20** plus `v' = ((m − d)/(1 − d))^1.15`, so the first 30 % of travel is fine control rather than a light switch. `Input.get_vector()` already applies a circular deadzone ([S24](UX_RESEARCH_SOURCES.md#s24)) — use it instead of hand-rolled axis math.

---

## 3. Camera

Fixed camera is the right choice for a 320×180 room (it prevents shimmer and keeps the whole board legible), but fixed ≠ inert:

| Element | Spec | Source / note |
|---|---|---|
| Base | `Camera2D` at (640, 360), never moves off-centre by more than 48 px | keeps every washer on screen |
| Lead | `lead = clamp(velocity × 0.12 s, 48 px)` → 41 px at full speed | **[inference]** 0.12 s = 7 frames; 41 px = 10 art px of look-ahead |
| Deadzone | 32 × 32 px box around centre (±16 px per axis) | prevents micro-jitter from the hold spring |
| Smoothing | `x = lerp(x, target, 1 − exp(−k·dt))`, **k = 10** | critically damped, frame-rate independent; never `lerp(a, b, 0.1)` per frame |
| Trauma | `trauma = clamp(trauma + amount, 0, 1)`; `shake = trauma²`; `offset = noise(t) × shake × max_offset` | Eiserloh's model as implemented in [S23](UX_RESEARCH_SOURCES.md#s23): decay 0.5/s, exponent 2.0, "camera shakes don't feel punchy when they go up linearly" |
| Decay | **1.5 / s** (a 0.4 hit is gone in 267 ms) | faster than the 2 s default because our events are shorter |
| Max offset | **8 px x/y** (2 art px), quantised to 4 px | 20 px would be 5 art px and unreadable at this scale |
| Roll | **0°** | [S23](UX_RESEARCH_SOURCES.md#s23) uses ±10°; rotation breaks the pixel grid |
| Composition | additive trauma, clamped to 1.0 | three simultaneous +0.2 events ≠ +0.6 of shake |
| Apply | shake the *render* transform only, restore at frame start | [S23](UX_RESEARCH_SOURCES.md#s23): "the Transform stays 'normal' for the rest of the game logic" |
| Dash offset | +8 px in the dash direction for **120 ms**, eased back over 200 ms | sells the burst without moving the board |
| Throw offset | −4 px opposite the throw for **80 ms** | recoil; the only camera "kick" we allow |
| Zoom punch | **none** | a 1.05× zoom is an off-integer scale on a 320×180 canvas and shimmers (UX doc §4) |

```gdscript
# Camera feel. 4 px = 1 art px.
func _process(dt: float) -> void:
    var target := base + (velocity * LEAD_S).limit_length(MAX_LEAD)   # LEAD_S = 0.12, MAX_LEAD = 48
    if absf(target.x - base.x) < DEADZONE_HALF \
            and absf(target.y - base.y) < DEADZONE_HALF:               # DEADZONE_HALF = 16
        target = base
    position = position.lerp(target, 1.0 - exp(-SMOOTH_K * dt))        # SMOOTH_K = 10, frame-rate independent
    trauma = maxf(trauma - TRAUMA_DECAY * dt, 0.0)                     # TRAUMA_DECAY = 1.5 /s
    var amp := pow(trauma, 2.0) * MAX_SHAKE                            # MAX_SHAKE = 8 px
    offset = Vector2(_n(t + 100.0), _n(t + 200.0)) * amp               # 1D noise, never random
    offset = (offset / 4.0).round() * 4.0                              # quantise to art pixels
```

Shake is also the cheapest reduce-motion win: amplitude ×0 and a 1 px frame flash conveys the same event.

---

## 4. Impact and juice budget

**Evidence on quantity.** Medium and high juiciness outperformed *extreme* juiciness and *no* juiciness on player experience, intrinsic motivation, play time and in-game performance ([S22](UX_RESEARCH_SOURCES.md#s22), citing Kao). Juice also makes it "hard to learn what aspects of interactivity have mechanical importance" — which in a game about reading four machines is a direct cost.

| Event | Hitstop | Flash | Shake (trauma) | Particles | Haptics (weak/strong, ms) | Audio |
|---|---|---|---|---|---|---|
| Grab | 0 | — | 0 | 0 | 0.10 / 0.15, 30 | squelch/clank, pitch ±6 % |
| Throw (any grade) | 0 | 1 frame item white (PERFECT only) | 0.10 → 4 px | 0–1 puff | 0.15 / 0.20, 40 | whoosh + tick |
| Insert into washer | 0 | 1 frame rim | 0.15 → 4 px | 2 | 0.20 / 0.30, 50 | chime on the beat |
| Wrong washer | 1 frame (17 ms) | 1 frame `red_1` | 0.25 → 8 px | 3 | 0.35 / 0.55, 60 | buzz |
| Turbulence starts | 0 | — | 0 | 0 | 0.25 / 0.35, 80 ×2 | alarm, 2 beats |
| Explosion | **2 frames (33 ms)** | full object flash | 0.55 → 8 px | 8–12 | **0.60 / 0.90, 120** | boom + tail |
| Chute delivery | 1 frame (17 ms) | 1 frame iris | 0.15 → 4 px | 4 | 0.20 / 0.25, 50 | ding |
| Shredder loss | 0 | — | 0.15 → 4 px | 3 sparks | 0.15 / 0.25, 40 | whoosh |

Rules: never hitstop on a *grading* result (it desynchronises the internal clock); total vibration per second ≤ 300 ms; a haptic must always be paired with a visual (accessibility); all shake offsets multiples of 4 px; all durations ≤ `0.45 × T_beat` (190–257 ms) from the UX doc.

**Haptics specifics.** Godot exposes two motors — `Input.start_joy_vibration(device, weak, strong, duration)` — where weak is the high-frequency motor and strong the low-frequency one ([S24](UX_RESEARCH_SOURCES.md#s24)). Design in short *varying* envelopes, not flat buzzes: on haptic actuators "if there are no variations in the amplitude of the waveform, there is no perceived vibration" ([S25](UX_RESEARCH_SOURCES.md#s25)). Concretely: explosion = two pulses (0.9 for 60 ms, 0.0 for 20 ms, 0.6 for 40 ms), never a 500 ms hold. Always call `stop_joy_vibration()` on scene exit and on pause.

**Accessibility equivalents:** `Reduce motion` → shake 0, hitstop 0, haptics 0, bursts static; `Reduce flashing` → no 1-frame white flashes (keep the palette flash of the object only); both are single toggles, per the UX doc §8.

---

## 5. Throw and aim feel

The throw is the emotional core and currently "weightless" because it has no anticipation and no follow-through — the two phases that create weight. saint11's player-attack breakdown is the applicable rule: for a *player* action, compress anticipation hard (long anticipation reads as input lag), loop the action, then recover "with a little overshoot" ([S26](UX_RESEARCH_SOURCES.md#s26)).

| Phase | Duration | What happens |
|---|---|---|
| Wind-up | **60 ms** (4 frames) | sprite pulls back 1 art px; item pulls to 40 px; *no* input lock — the throw can still be cancelled |
| Release | 0 ms | impulse applied **on the input frame**, not at animation end (Hi-Fi Rush's queue-vs-contact problem, UX doc §1) |
| Follow-through | **90 ms** | Pip leans 1 px forward, arm overshoots 1 px, then settles |
| Cancel window | opens at **40 ms** | dash or strike can cancel recovery; grabbing cannot |

**Aim assist** — enough to forgive, not enough to aim for you. Assisted aiming is "oil", the measured exploitation of the illusion of control ([S22](UX_RESEARCH_SOURCES.md#s22)); Disc Room ships delayed hitboxes of up to 50 ms as an explicit accessibility feature, so assistance-as-forgiveness has precedent.

- **Magnetic grab:** 64 px radius, plus a 12 px "sticky" band (76 px) while the stick points within 45° of the item. Sticky only when moving toward it.
- **Throw magnetism:** if the aim is within **±12°** of a *compatible* washer mouth and range < 480 px, rotate the throw vector by at most **8°** toward the mouth. Capped at 8° because at 12°+ the player sees the game correct them.
- **Reticle feedback** (`ui_reticle` 16×16): `metal_2` = nothing in cone; `funk_cyan` = compatible washer in cone; `clean_green` = chute in cone and the item is clean; `hazard_orange` ring = the target washer is turbulent. This is the cheapest "do I have a target?" answer we can give.
- **Arc/leading:** no trajectory arc (the game is top-down; an arc would lie). Instead, 3 dots along the first 0.15 s of flight, fading at take-off — enough to read direction, gone before the beat.

---

## 6. Character readability in motion

Sprites cannot rotate (§A7/§B3), so all motion character must come from *offsets*, *silhouette changes* and *timing*:

| Element | Spec | Note |
|---|---|---|
| Idle | 2 frames @ **4 fps** (500 ms) | current spec says 3–4 fps; 4 avoids a "stuck" look |
| Run | 4 frames @ **10 fps** (100 ms/frame) | at 340 px/s that is 34 px = **8.5 art px per frame** |
| Dash | 1 frame squash (×0.85 y) + 3 solid afterimages | **solid `funk_cyan`, not alpha** — §B2 forbids semi-transparent pixels |
| Lean | sprite offset **1–2 art px opposite acceleration**, body unchanged | rotation is illegal; offset reads as lean |
| Dust | `fx_burst_*` style 8×8, 3 frames @12 fps, at the feet | on dash start and every 2nd footstep |
| Shadow | 12×4 px ellipse, alpha-free (solid `space_void`) | grounding; currently missing |
| Trail on hold | 2 dots, 40 ms apart | makes the magnetic hold legible |

**Footsteps: lock to the half-beat, not to distance.** A distance-based step interval drifts against the music; a time-based one is musical for free. Half-beat = **286 ms at 105 BPM, 211 ms at 142 BPM**, i.e. one step every 97 px / 72 px of travel **[inference from vmax]**. Alternate L/R by firing the step on `beat_hit` when `beat_index % 2 == 0` and the player is moving.

---

## 7. Measuring "does it feel good"

**Instrument first.** Three numbers, logged in debug builds: (1) input→grade latency (`get_ticks_usec` at press and at grade), target **< 25 ms** internal; (2) input→photon, measured by filming the monitor at 240 fps and counting frames from keypress to sprite motion — target **< 4 frames (66 ms)**; (3) time-to-first-meaningful-action from scene load — target **< 1.5 s**.

**Six tasks, one per session, 5 players.** Say only the task; never explain the controls.

| # | Task | Observe | Pass |
|---|---|---|---|
| 1 | "Llega a la lavadora de arriba y vuelve" | overshoot, wall-hugging, hesitation at reversals | no more than 1 collision; returns in < 6 s |
| 2 | "Coge el objeto más cercano" | missed grabs, double-presses | ≥ 4/5 grab on first press |
| 3 | "Tíralo hacia el centro" | cursor vs stick aiming; perceived weight | 4/5 land within 64 px of the chute |
| 4 | "Lánzalo 10 veces al ritmo" | do they watch the ring, speed up, or give up | ≥ 5/10 ≥ GOOD without coaching |
| 5 | "Cruza la sala con el impulso" | is dash used as movement or as the strike verb | they use it deliberately ≥ 3 times |
| 6 | "Entrega uno limpio en el ducto" | pathing, whether camera lead helps or confuses | delivery in < 25 s |

**Moderator rules** ([S27](UX_RESEARCH_SOURCES.md#s27), Bromley, PlayStation): ask high-level questions after the action dies down — "¿qué querías hacer?" not "¿por qué no fuiste al ducto?"; always confirm what you *think* you saw, because "the player hasn't seen the objective" and "the player is looking for something else" need different fixes; repeat their words back paraphrased to elicit more; probe until the note is actionable ("weird controls" is not); and discard projected opinions ("my brother would like this").

**Self-deceptions to guard against.** (a) *Expertise blindness* — after 200 hours the tuning feels fine; a new player's first 60 s is the data. (b) Watching the player's face instead of the screen recording; latency and overshoot are only visible in the recording. (c) Asking "does it feel good?" — leading and unactionable. (d) Tuning at an uncapped frame rate and shipping 60 Hz. (e) Mistaking better animation for better response; the two are independent and the second is what "lifeless" usually means.

---

## 8. What we already do and what to change

| Current constant | Reality | Verdict | Change |
|---|---|---|---|
| `ACCEL 2400`, `MAX 340` | vmax in 142 ms / 24 px | good | keep; add ×2 opposing accel on reversal |
| `friction 0.88^(60dt)` | 47 px slide, 300 ms to 10 % | **too floaty** | 0.80 → 28 px / 172 ms |
| `GRAB_RADIUS 64` | generous, no forgiveness | ok | +12 px sticky band, +100 ms coyote, +120 ms buffer |
| `HOLD_DISTANCE 48`, spring 18 | no damping term documented | risky | critically damp: `c = 2·√k` ≈ 8.5 |
| `THROW_SPEED 900` | 15 px/frame; 443 px to a washer = 0.49 s ≈ 1.2 beats @142 | fine | add 60 ms wind-up, 90 ms follow-through, 40 ms cancel |
| `DASH 120 px / 0.18 s` | 667 px/s, 2× vmax | good | +1 frame squash, 3 solid afterimages, dust |
| Fixed camera | no lead, no response | **lifeless** | lead 0.12 s (≤ 48 px), 32 px deadzone, k = 10 |
| No hitstop / haptics | every impact weighs the same | **lifeless** | §4 table |
| No footsteps / dust | no contact with the floor | **lifeless** | half-beat cadence + 8×8 dust |
| `_input()` for rhythm | correct, but accumulation may eat 16.7 ms | **unverified** | flip `agile_event_flushing`, re-measure (§1) |

**Prioritised backlog (10 items).**

- **P0 — do before any art pass**
  1. Fix input latency: enable agile event flushing / disable accumulated input for gameplay; log input→grade ms.
  2. Add the 120 ms action buffer + 100 ms grab coyote + 60 ms release tolerance.
  3. Retune friction to 0.80 and add ×2 opposing acceleration on direction reversal.
  4. Add throw wind-up (60 ms) / follow-through (90 ms) / cancel from 40 ms.
- **P1 — the feel pass**
  5. Camera: 0.12 s lead, 32 px deadzone, exponential smoothing k = 10.
  6. Trauma shake: decay 1.5/s, exponent 2, max 8 px, 4 px quantised, **zero rotation**.
  7. Hitstop + haptics per §4, both behind `Reduce motion`.
  8. Dash squash + 3 solid afterimages + 8×8 dust at the feet; add the 12×4 shadow.
- **P2 — polish**
  9. Footsteps on the half-beat + ±6 % SFX pitch variation (never on stems).
  10. Aim assist: 12° cone / 8° max correction / reticle state colours; verify it is invisible in playtest.

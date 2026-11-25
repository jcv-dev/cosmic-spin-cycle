# UX / Game-Design Research — *Cosmic Spin Cycle*

**Author:** UX/Game-Design Research Lead · **2026-11-24** · branch `ux/research`
**Scope:** evidence for the M6 screen-flow, HUD and tutorial overhaul. No code, no art assets.
**Method:** 21 sources; 17 read in full plus 1 transcript (quotes in [the appendix](UX_RESEARCH_SOURCES.md)), 1 skimmed, 2 search-only. Numbers are quoted from a source, measured from this worktree (`HUD.gd`, `data/layout.json`, Silkscreen via fontTools, WCAG luminance on the §B4 palette), or labelled **[inference]** with the arithmetic shown.

---

## 0. Executive summary

The owner's complaint is measurable, not stylistic: **the text is about half the readability floor, the information sits in the corners instead of at the objects it describes, and the screen centre — where the game's one goal, the chute, lives — is occupied by a grade label.** Fixing those three makes the same build legible without adding a mechanic. The evidence says the fix is relocation and sizing, not more HUD: Dead Space's UI lead closed his GDC talk by conceding diegetic purity loses to usability ([S06](UX_RESEARCH_SOURCES.md#s06)); every rhythm game playable by people "with no rhythm" ships an explicit beat visualiser ([S01](UX_RESEARCH_SOURCES.md#s01), [S02](UX_RESEARCH_SOURCES.md#s02)); chaotic co-op stays readable by putting the recipe on the ticket ([S05](UX_RESEARCH_SOURCES.md#s05)).

1. **Delete the 73-character bottom strip** — 11 px Silkscreen (7.7 px caps) in `metal_1` at **3.90:1**, under the 4.5:1 floor ([S08](UX_RESEARCH_SOURCES.md#s08)) and 41 % of the 19 px floor implied by EA's 28 px @1080p guidance ([S10](UX_RESEARCH_SOURCES.md#s10)). Nothing essential at y = 688 ([S07](UX_RESEARCH_SOURCES.md#s07)).
2. **Two corner clusters; keep the top-centre 608 px clear** for the north belt, which the 48 px band still clips by 8 px.
3. **Grade text off screen centre**: the chute is 576–704 × 296–424; the 44 px label spans y 286–346 and overlaps it.
4. **One beat source + one peripheral**: a ring contracting over 2 beats on Pip, plus a 4 px frame pulse. Never a full-screen flash — 142 BPM = 2.37 Hz, only 21 % under WCAG's 3 Hz ceiling ([S09](UX_RESEARCH_SOURCES.md#s09)).
5. **Every transient ≤ 0.45 × T_beat** = 257 / 229 / 208 / 190 ms. The current grade label fades over ~625 ms — still on screen when the next beat lands.
6. **Shape before colour**: `red_1` measures 1.82:1 and `funk_plum` 2.25:1 on `#0B0C10`; as the sole carrier of meaning they are invisible — the rule against colour-only coding is [S07](UX_RESEARCH_SOURCES.md#s07).
7. **Seven gated tutorial steps**, ≤ 6 words per prompt, always skippable and replayable ([S12](UX_RESEARCH_SOURCES.md#s12), [S07](UX_RESEARCH_SOURCES.md#s07)).
8. **Show the queue, not just the target**: a delivery loop is 4.4–6.0 beats while phase-3 spawns arrive every 3.7–4.0 beats — the player is structurally behind, so the HUD must answer "what explodes next" **[inference, §12 finding 5]**.

---

## 1. Rhythm onboarding: teaching "act on the beat" without a wall of text

**Question.** What do shipped rhythm games put on screen so a player with no rhythm can act on a beat — and what happens on a miss?

**Evidence.** *NecroDancer* gutted accuracy on purpose: Clark prototyped ±100 ms at 120 BPM, found "the times when you are least accurate are the times when you are most stressed", and widened the window until it "felt best at 100 percent" (half a beat), plus a leaky-integrator auto-calibration that bends the beat toward where the player *thinks* it is. He also found that putting player and enemies on the same beat is what makes the world feel synchronised ([S01](UX_RESEARCH_SOURCES.md#s01)). *Hi-Fi Rush* removed the punishment instead: everything syncs to the beat whatever you press, on-beat hits pay a bonus, and the game ships "a little visualizer that very clearly shows the beat" plus world cues (steam, finger snaps) ([S02](UX_RESEARCH_SOURCES.md#s02)). *Patapon* uses the screen edge as the metronome — a thin white frame pulsing on the beat, combo reset on a miss, fever at 10 ([S04](UX_RESEARCH_SOURCES.md#s04)). *Metal: Hellsinger* is the failure case: the miss chevron is *larger* and overlaps the beat chevron, so after one miss "you just trick into chaining misses" ([S03](UX_RESEARCH_SOURCES.md#s03)). A Polygon reader adds that Hi-Fi Rush's attack *queue* is on the beat while contact lands after it — they play better with sound off, watching the beat bar ([S02](UX_RESEARCH_SOURCES.md#s02)).

**Adopt.**
- `PulseRing` on Pip = *when*: contracts from 140 % to 100 % over **2 beats** (846 ms at 142 BPM), snaps back in 80 ms. Two beats, because 423 ms of anticipation is not enough to plan a move and aim.
- Frame pulse (4 px inset) = *where the bar is*: downbeat accent only, 1 frame `funk_cyan`, no fade.
- A toggleable beat bar in Options, **default on** — the owner is the target case, not an edge case.
- Grade bursts appear **at the event** (washer mouth, chute, item).
- On a miss: the cue must be *smaller* and spatially separate from the beat cue, never larger and on top of it. `fx_miss_puff` 12×12 at the item + 90 ms desaturation of that item only.

**Don't copy.** NecroDancer's 100 % leeway: its challenge is tactical combat, ours is routing under time pressure — widening our ±65/±130 ms windows (45.5 % random on-beat at 105 BPM, 61.5 % at 142) would delete our only skill axis. Copy the auto-calibration, which we already ship. Also don't use Patapon's frame pulse as the *primary* cue: one verb and a lane; we have four destinations.

---

## 2. Chaotic multi-task clarity

**Question.** In games deliberately about too much happening, how is "do this next" signalled, and how is overload avoided?

**Evidence.** *Overcooked*'s legibility lives in the ticket, not a tutorial: orders stack at the top and each ticket *is* the recipe, in ingredient icons — "these same visual cues keep players focused on the next ingredient and task at hand". Every cooking task and order has a visible timer, so prioritisation is comparison of clocks, not memory. One interact button does every stage. And the one system *without* a communicated timer — dirty plates — is the system players handle worst ([S05](UX_RESEARCH_SOURCES.md#s05)). Overload is managed by layout: a counter between stations makes one pair of hands physically insufficient. Roblox's onboarding guidance supplies the guidance timing: delay non-essential instruction, trigger it on first contact, and if most players solve a step within 10 s, highlight at 11 s, once ([S12](UX_RESEARCH_SOURCES.md#s12)).

**Adopt.**
- **Four washer chips, sorted by time-to-explosion**, each with requirement glyph, 3-segment progress ring, and a turbulence deadline bar that turns `hazard_orange` at 50 %. This is Overcooked's "visible clocks" applied to machines.
- **One context button**, as today (`grab_throw` = grab and throw; `rhythm_strike` = the beat verb). Never add a third verb.
- **A clock on everything**, including turbulence: show `min(5 s, 8 beats)` = 3.38–4.57 s from the moment it starts.
- **Idle escalation**: no input for 11 s while carrying clean → highlight the chute once per shift.

**Don't copy.** The ticket *stack*: Overcooked needs it because orders are fungible and there are up to four bodies. We have one body, one held item, four fixed machines — a stack would be five rectangles eating 25 % of a 320×180 screen. Also no "recommended action" arrow: highlight *state* (about to explode), never *intent*, or the routing game becomes follow-the-arrow.

---

## 3. Diegetic vs non-diegetic

**Question.** Does in-world HUD actually improve glanceability, or only immersion?

**Evidence.** Dead Space is the best-documented case *including its failure*. Dino Ignacio: "We were not just diegetic by design, we were diegetic by implementation" — the RIG is geometry, casts light, emits particles; non-diegetic information was moved *behind* the character; colour encodes interaction (blue/white interactive, red locked, amber ambient) ([S06](UX_RESEARCH_SOURCES.md#s06)). The same talk reports that the Dead Space 3 workbench was **"unusable"** — staff preferred the debug menu — and was replaced with a conventional full-screen UI: "none of that is important if your users really can't interact with your game". Splatoon's ink tank is a readable diegetic gauge with a sub-weapon threshold mark ([S19](UX_RESEARCH_SOURCES.md#s19)) but is reported unreadable when the character's back is occluded.

**Adopt.**
- **World-anchored for object state** (washer requirement, wash progress, turbulence deadline, compatibility); **screen-space for global state** (clock, stability, combo, score). This is the split Dead Space itself conceded to.
- **Diegetic and redundant**: every requirement appears twice — 12 px art hologram at the machine mouth, plus the same glyph in the corner chip. The player reads it where they look, and still reads it when a held gas giant (24×24) occludes a 48×48 washer.
- **Three-colour interaction language**: `funk_cyan` = act here now; `hazard_orange` = act soon; `clean_green` = done/deliverable; `metal_*` = inert. Never red for "wrong" alone.
- **A locator, not a map**: 1 px `clean_green` dotted line from carried-clean to chute, fading after 1.5 s.

**Don't copy.** *Only* diegetic — occlusion is fatal at this scale. And don't animate the HUD as geometry: Dead Space could afford per-object light and particles in a 3D scene; at 320×180 with 30 colours, "the HUD is made of particles" means "the HUD shimmers". Fake it: 1 px outline, no glow, no sub-pixel offsets.

---

## 4. Pixel-art presentation at 320×180

**Question.** What separates "pixel art" from "pixel art that reads at 1280×720"?

**Evidence.** Our internal resolution is **exactly Celeste's** — Berry: "Our screen resolution is tiny (320x180)", which is why 256 light masks fit one 2048² atlas ([S16](UX_RESEARCH_SOURCES.md#s16)). Celeste's lighting is a cutout mask (draw spotlight, wall quads erase shadow), chosen after a mesh+raycast version produced "edge cases, bugs, and floating point precision problems". *Dead Cells* gets light from a 3D pipeline: pixel-style colour render + normal render, layered PSB, Filter = Pixel, Compression = None, `_NormalMap` as secondary texture; the colour sprite "keeps only the flat colour, with no shading added" ([S17](UX_RESEARCH_SOURCES.md#s17)). Shimmer is arithmetic, not taste: non-integer scale/translation makes some texels fill a pixel and others straddle two, giving "shimmering artifacts (inconsistent line widths) and jaggies when rotating objects" ([S14](UX_RESEARCH_SOURCES.md#s14), [S15](UX_RESEARCH_SOURCES.md#s15)).

**Adopt.**
- Three invariants with tests: camera at `round(pos/4)*4`; every sprite scale exactly 4; no quarter-turn-free rotation in the world layer.
- **Shake in whole art pixels**: amplitude `4 × n`, decaying in 4 px steps. Vlambeer's 6 px kick is 1.5 art px and therefore illegal for us (§7).
- **Light as a palette operation**: pre-author `night` and `alarm` variants of `env_room` by remapping `space_*`/`metal_*` slots. Dead Cells' palette-swap idea at zero cost, impossible to break the palette.
- Impact FX 3–6 frames, 8–32 px, no additive blending; `fx_burst_perfect` 4 frames @18 fps = 222 ms, which fits every BPM except 142 (190 ms) — use 3 frames there.
- Dither only on surfaces ≥ 24×24 art px.

**Don't copy.** A normal-map pipeline: correct for a 3D-source game, wrong for 176 hand-drawn frames under a 30-colour rule — the normal map's value is shading *between* palette steps, which we forbid. Also don't run per-light masks for a static single room; bake the light and spend the budget on the beat ring.

---

## 5. Title, menu and first-run patterns

**Question.** What must the first screen do, and how do keyboard/gamepad users avoid dead ends?

**Evidence.** Menus are an accessibility surface: "Allow the game to be started without the need to navigate through multiple levels of menus"; "all areas of the user interface can be accessed using the same input method as the gameplay"; "ensure that all settings are saved/remembered"; "use an easily readable default font size" ([S07](UX_RESEARCH_SOURCES.md#s07)). Dead Space treated its frontend as part of the fiction, using the same design language the character sees ([S06](UX_RESEARCH_SOURCES.md#s06)) — for us, a title that looks like the laundromat's control panel costs one background and no new art. Prominence beats prose: text prompts "can be easily overlooked … If players don't notice them, they are of no benefit" ([S12](UX_RESEARCH_SOURCES.md#s12)). No source supports a "press any key" gate.

**Adopt.**
- **One screen, three items, focus already on the first**: `EMPEZAR TURNO` (default) · `AJUSTES` · `SALIR`. Logo, a 2 px `funk_cyan` rule, room at 40 % brightness with Pip idling and one washer spinning — the room *is* the menu.
- **No "press any key"**: the first frame is interactive, first item focused, `Enter`/`A` starts.
- **Focus is drawn**: 2 px `funk_cyan` + 4 px offset + 1 px `space_void` gap (10.9:1 on `space_deep`).
- **Directional only + pointer as bonus**; `Esc`/`B` always backs out.
- **Options one level deep, one screen**: volume (3), `Calibrar audio`, `Ritmo visible`, `Sacudida`, `Tamaño de texto`, `Pantalla completa`. All persisted.
- **First run is a modifier, not a mode**: `EMPEZAR TURNO ▸ TUTORIAL`.

**Don't copy.** Celeste-style granular assist menus (right for Celeste; six rows is right for a 480 s arcade game, and GAG warns on depth). And don't teach on the title screen — it will be skipped ([S12](UX_RESEARCH_SOURCES.md#s12)).

---

## 6. Tutorial design: gates, not paragraphs

**Question.** How to teach five verbs, a beat and a routing rule in 2–4 minutes?

**Evidence.** Teach at first contact: contextual ("just in time") tutorials raise retention, speed onboarding and cut first-minute cognitive load, and the usable heuristic is "if most players solve it in 10 s, hint at 11 s, once" ([S12](UX_RESEARCH_SOURCES.md#s12)). Valve's invisible tutorial is the ceiling: *Half-Life 2* teaches "sawblades cut zombies" in two staged beats with no words ([S18](UX_RESEARCH_SOURCES.md#s18)) — possible because physics is self-evident, impossible for a timing window. Hi-Fi Rush teaches "beat by beat, button by button" and frames it as accessibility ([S02](UX_RESEARCH_SOURCES.md#s02)); Overcooked teaches recipes as icons ([S05](UX_RESEARCH_SOURCES.md#s05)). Three guidelines constrain the form: interactive tutorials, prompts at the player's pace, replayable instructions, and never text alone ([S07](UX_RESEARCH_SOURCES.md#s07)).

**Adopt.** One verb per gate, seven gates (§14). Prompts are labels, not sentences: ≤ 6 words / ≤ 24 chars / ≤ 2 lines at 20 px, anchored to the object, no modal, no pause — the beat keeps running. Every gate shows its own success (ring fills, washer flashes green). Idle hint at 11 s, once. Skip (hold `Esc` 1 s / `Start`) and replay (Pause → `Ver tutorial`) always available. Fail-forward after 3 attempts.

**Don't copy.** Invisible-tutorial purism — stage the verbs we can stage, but *state the beat*, because no laundromat object demonstrates ±130 ms. And never pause the beat to explain the beat.

---

## 7. Game feel: a budget, not a vibe

**Question.** Which effects, at what magnitudes, kept accessible?

**Evidence.** The most concrete published numbers come from *Nuclear Throne* at **320×240 / 30 fps** — almost our resolution ([S13](UX_RESEARCH_SOURCES.md#s13)): shell 2–4 px/frame, bullet 16 px/frame, camera kicked **6 px** from aim, "add **4** to the screenshake" (degenerating quickly), weapon kick **2 px**, enemy knockback 3 px/frame, one white frame then two hit frames, and the game freezes **10–20 ms** on every hit. These were hand-tuned, not derived — so the budget below is a starting point, not a law.

| Effect | Magnitude | Duration | Reduce-motion |
|---|---|---|---|
| Hitstop on PERFECT | none (would desync the player's clock) | — | — |
| Hitstop on explosion | 2 frames | 33 ms | 0 frames |
| Screen shake | 4 px, decaying in 4 px steps | ≤ 120 ms | off → 1 px `hazard_orange` frame flash |
| White flash | 1 frame, **item only** | 16.7 ms | none |
| Grade burst | 16×16 @18 fps, 4 frames | 222 ms (3 frames at 142 BPM) | static icon, 200 ms |
| Scale pop | ×1.15, 3 frames | 50 ms | none |

Rules: no hitstop on grading; shake quantised to art pixels; nothing transient outlives `0.45 × T_beat`.

**Don't copy.** "More juice is better" — in a game whose failure mode is *not knowing what happened*, a screen-wide effect per throw is an anti-feature. And don't shake on the beat: charming in a GIF, nauseating over 480 s, and a 2.37 Hz shake is a motion-sickness trigger, not a rhythm aid.

---

## 8. Accessibility: the non-negotiables

| Guideline ([S07](UX_RESEARCH_SOURCES.md#s07) unless noted) | Our obligation |
|---|---|
| No essential info by fixed colour alone | Colour + glyph + position on washers, items **and HUD chips** |
| No essential info by sound alone | Every SFX has a visual twin: alarm → flashing ring, chute → green flash, miss → item puff |
| Contrast: text 4.5:1, large 3:1, non-text 3:1 ([S08](UX_RESEARCH_SOURCES.md#s08)) | Hint 3.90:1 **fails**; `metal_0` border 2.34:1 **fails** the 3:1 rule |
| ≤ 3 flashes/s ([S09](UX_RESEARCH_SOURCES.md#s09)) | 142 BPM = 2.37 Hz is legal; keep flash area ≤ 25 % of screen, never full-screen magenta/red |
| Nothing essential outside eye-line | Kill the bottom strip; prompts at the object |
| Remind controls + objectives | Pause shows both; `H`/`Select` toggles a 3 s overlay |
| Prompts at own pace; replayable instructions | Gates never auto-advance; tutorial replayable from Pause |
| Settings saved; no menu depth | `Settings.cfg`; title 1 level, options 1 level |
| Turn off background movement / sudden events | `Sacudida`, `Ritmo visible`, `Fondo animado` |
| Same input for UI and gameplay; remap | Gamepad + keyboard parity in M6; remap is a documented stretch |

**Adopt.** A single **`Reduce motion`** preset (shake 0, hitstop 0, static bursts, background off, ring becomes a tick) rather than five toggles; a **three-step text size** (20/24/28 px) so the conservative default is not a permanent sentence; and colour-blindness handled by *redundancy*, not a post-process filter that would push the palette off-spec and break the lint.

---

## 9. Typography and HUD layout: the measured case

`HUD.gd` renders labels at **9, 10, 11, 22, 24, 26 and 44 px**. Silkscreen metrics (fontTools, upm 1000): **cap height 0.70 em**, x-height 0.50 em, average lowercase advance **0.723 em**, caps **0.745 em**.

| Element | Now | Cap height | Floor at 720p | Verdict |
|---|---|---|---|---|
| Clock | 26 px | 18.2 px | ≈ 19 px | borderline |
| Combo / score | 24 / 22 px | 16.8 / 15.4 px | ≈ 19 px | below |
| Captions (`TURNO`…) | 9 px | 6.3 px | ≈ 19 px | **33 % of floor** |
| Bottom hint | 11 px | 7.7 px | ≈ 19 px | **41 % of floor** |

Floor derived from EA's "minimum of 28 pixels tall … on a 1080p screen" ([S10](UX_RESEARCH_SOURCES.md#s10)): 28 × 720/1080 = **18.7 px** **[inference: linear scaling; desktop viewing distance is shorter, so treat it as a floor, not a target]**.

**Spanish costs more than English — and short strings cost most.** Microsoft's growth table: 1–4 chars **+100 %**, 5–10 **+80 %**, 11–20 **+60 %**, 21–30 **+40 %**, 31–50 **+20 %**, >50 **+10 %** ([S11](UX_RESEARCH_SOURCES.md#s11)). Operational rule: never size a label to its text; size the zone and assert the string fits.

Measured widths (Silkscreen Regular):

| String | ch | @14 | @16 | @20 | @24 |
|---|---|---|---|---|---|
| `ESTABILIDAD DEL TEJIDO` | 22 | 196 | 224 | 280 | **336** |
| `Recoge: ESPACIO · Suelta: ESPACIO` | 33 | 294 | — | — | — |
| `Aprieta ESPACIO al ritmo` | 24 | — | 250 | 313 | — |
| `Lavadora equivocada` | 19 | — | 218 | — | — |
| `Empezar turno` | 13 | — | — | 188 | 259 |
| `Se acabó el turno` | 17 | — | — | — | 325 |

`ESTABILIDAD DEL TEJIDO` at 24 px is **336 px** — wider than the 300 px bar it labels. Shorten the label, not the bar. Capacity per line in a 300 px zone: **33/25/20/16** caps at 12/16/20/24 px.

**Copy rules.** Persistent labels ≤ 12 chars @20 px (`ESTABILIDAD` = 166 px). Contextual prompts ≤ 24 chars @20 px, max 2 lines. Buttons ≤ 14 chars @24 px. Grades at 32–40 px **at the event**.

**The layout evidence forces:**
- The 48 px top band still clips the north belt by 8 px (belt starts y = 40). Replace with corner clusters: left 0–330 × 0–120 (clock, turn), right 950–1280 × 0–120 (stability, combo, score); the middle 608 px stays clear.
- The chute is at the exact screen centre (640, 360); the grade label spans y 286–346 — **50 px of overlap**. Move grades to the event, or to a 300 px band at y 600–680.
- Time-critical prompts belong within ~200 px of the player or target; y = 688 is 300+ px from every washer — outside eye-line by definition.

---

## 10. The 20-second test

Five questions a stranger must answer, in order. If a second element competes at that moment, the guarantee breaks — so suppress phase banners, score pops and centre-screen grades for the first 20 s.

| # | By | Must perceive | Affordance that guarantees it |
|---|---|---|---|
| 1 | 0–3 s | "I'm the cyan guy; four machines, a hole in the middle." | Fixed camera; Pip idles at (640, 512) facing the chute; four portholes pulse once at 1 Hz, offset 250 ms each |
| 2 | 3–6 s | "Things arrive on belts and I can pick them up." | First item spawns on the nearest belt, steered inside `GRAB_RADIUS`; magnet dots; `AGARRA` (6 ch) at the item |
| 3 | 6–10 s | "On the beat is better." | Ring contracts over 2 beats; first throw graded; grade at the item; ring's disc flashes 1 frame |
| 4 | 10–15 s | "That machine wants this — the wrong one costs me." | Compatible: 12 px hologram + `funk_cyan` rim + 400 ms beam. Wrong insert: −12 % chip animates *at the washer* |
| 5 | 15–20 s | "Clean things go to the middle — that's the point." | Chute iris opens; 4×96 px `clean_green` beacon for 600 ms; `Lleva el limpio al ducto` (24 ch) above the chute, once |

**Must not be true in the first 20 s:** no phase banner, no turbulence, no belt reversal, ≤ 2 text strings on screen at once, clock at 00:00, only `rocky`+`solid` items.

**Protocol (5 strangers, 20 s each):** ask only "¿qué tienes que hacer?" and "¿dónde lo llevas?". Pass = 4/5 say "lavar / meter en la lavadora" and 4/5 say "el centro / el ducto". Otherwise an affordance above is failing — fix the affordance, not the copy.

---

## 11. Feedback matrix

L = local (≤ 16×16 art px at the event), M = object scale, H = screen scale (max twice per shift). All durations ≤ `0.45 × T_beat` (257/229/208/190 ms at 105/118/130/142 BPM).

| Event | Visual | Audio | Text (ES) | Intensity / duration | Reduced motion |
|---|---|---|---|---|---|
| Grab | Snap to hold in 60 ms; 1 px `funk_cyan` tether; sock squashes 2 frames | squelch / clank / thud by item | — | L / 60 ms | tether only |
| Throw PERFECT | `fx_burst_perfect` 16×16 @18 fps; item 1-frame white; ring ×1.2 | bright tick, music −2 dB for 80 ms | `PERFECTO` 32 px at item, 380 ms | L / 190–257 ms | static magenta icon |
| Throw GOOD | `fx_burst_good` 12×12 | softer tick | `BIEN` 24 px, 300 ms | L / 190–257 ms | static cyan icon |
| Throw MISS | `fx_miss_puff` 12×12, item desaturated 90 ms, **no shake** | dull thud, −2 semitones | `FUERA DE RITMO` 20 px at item, 300 ms | L / 190–257 ms | unchanged |
| Wrong washer | −12 % chip shakes 4 px ×2 at the washer; porthole `red_1` 1 frame; item ejected | buzz 120 ms @180 Hz | `Lavadora equivocada` 16 px, 600 ms | M / 250 ms | no shake; rim flashes at 2 Hz |
| Correct insert | Mouth rim `clean_green` 1 frame; drum starts on next beat | chime on the beat | — | L / 100 ms | same |
| Turbulence | Porthole → `hazard_orange`; 3-segment meter; 1 art px vibration @2 Hz | alarm 2 beats, then silent | `TURBULENTO` 14 px, persistent | M / until resolved | no vibration; meter + colour |
| Explosion (−25 %) | `fx_explosion` 32×32, 6 frames @12 fps; 2-frame hitstop; shake 8 px | boom + 400 ms tail | `¡EXPLOSIÓN!` 24 px at machine | H / 500 ms | 0 hitstop, 0 shake, 1 px orange frame |
| Clean done | `fx_bubbles` loop + `clean_green` 1 px rim; washer `done` | bell, 2 notes | — | L / 150 ms | bubbles static |
| Chute delivery (+3 %) | Chute `accept` 3 frames; item shrinks into iris 200 ms; score flies 200 px to counter | ding + 60 ms shimmer | `+3` at chute | M / 250 ms | no fly; counter pulses once |
| Shredder loss (−8 %) | Shredder + 6 px sparks; item erased in 2 frames | vacuum whoosh 200 ms | `−8` at the shredder | M / 250 ms | sparks off; rim flash |

**Cross-cutting.** Text always at the event (except the tutorial's first three throws). No colour carries two opposite meanings. Stability animates over ≥ 300 ms so −25 reads as a slide. The beat stem is never ducked more than 80 ms.

---

## 12. Contrarian findings

**1. "Diegetic HUD is better" is false as a general rule — its author says so.** The talk that made diegetic UI famous ends with him abandoning it for the workbench because testers preferred the debug menu. World-anchored UI wins for *object state you are looking at* and loses for *global state monitored peripherally*. The lesson is not "more diegetic", it is "put information where the eye already is".

**2. "Teach by level design, never by text" does not survive a rhythm mechanic.** *Half-Life 2* can stage "sawblades cut zombies" because physics is self-evident. Nothing in a laundromat demonstrates that a throw must land within ±130 ms of a beat. Every shipped rhythm game in the corpus therefore ships an explicit visualiser. Correct position: **stage the verbs, state the beat.**

**3. "Screen shake is free juice" is wrong at 320×180, and the canonical numbers are illegal for us.** Vlambeer's 6 px kick and 4 px shake come from a game drawn 1:1. At ×4, 6 px is 1.5 art px: sprites land between texels and the screen shimmers — exactly the artefact the pixel-art literature warns about. Amplitude must be a multiple of 4 world px, which makes our usable budget *smaller* than a native-resolution game's.

**4. "HUD too busy → remove HUD" misdiagnoses it.** We have 8 persistent labels — five at 9–10 px, plus a 73-character hint at 11 px — and *none* of them at the objects they describe. Removing labels makes it worse. The fix is relocation, consolidation (3 global numbers, not 8) and magnification (20 px floor) — a net *addition* of diegetic elements alongside a net removal of screen text.

**5. "One item at a time is the skill" may be structurally unfair in phases 3–4.** From `layout.json`: spawn (640,512) → nearest mouth (240,576) = 405 px = 1.19 s; mouth → chute (640,360) = 455 px = 1.34 s; a loop is **2.53 s = 4.4–6.0 beats**. Phase-3 spawns arrive every 1.7 s = **3.7–4.0 beats**. The loop costs more beats than the spawn interval grants; the deficit is absorbed only by the 3-slot buffer and overlapping wash time. That is a legitimate way to manufacture chaos, but no skill closes a 1.5× throughput gap with one pair of hands — so the HUD must show **queue depth**, not just the held item **[inference from §A5 constants + `layout.json`; confirm with `tools/balance_sim.gd`]**.

---

## 13. Menu and screen-flow spec

| Screen | Must contain | Focus order / default | Transition |
|---|---|---|---|
| **Title** | `ui_logo` 160×48 art px at y 200; three 320×48 buttons at y 380/440/500; room at 40 % brightness, Pip idle, one washer spinning; version+seed at 12 px | `EMPEZAR TURNO` (focused) → `AJUSTES` → `SALIR`; d-pad/arrows, `Enter`/`A`; `Esc`/`B` quits with confirm | 180 ms: logo drops 8 px + fades, buttons stagger 60 ms |
| **Options** | Six rows, label left / value right: `Volumen` (3), `Calibrar audio`, `Ritmo visible`, `Sacudida`, `Tamaño de texto`, `Pantalla completa`; footer `B: volver` | First row; left/right changes; `Esc`/`B` back | 120 ms cross-fade |
| **Calibration** | Existing 10 s wizard; live offset; `Repetir` / `Listo` | `Listo` when offset valid | reuse modal |
| **Pause** | Field dimmed 30 %; `REANUDAR` (default), `VER TUTORIAL`, `AJUSTES`, `SALIR AL TÍTULO`; legend 4 lines @14 px; objective 1 line @20 px | `REANUDAR`; `Esc`/`Start` resumes | 100 ms dim, audio low-pass |
| **End** | Result word, rank S/A/B/C @48 px, 4 stats (washed, accuracy %, max combo, score), seed, `REINICIAR` (default) / `TÍTULO` | `REINICIAR`; `R` shortcut | 250 ms fade |
| **Restart** | — | — | hard cut, **< 500 ms** (`RESTART_MAX_S`) |

Rules: ≤ 6 focusable items per screen; no screen requires a mouse; `Esc` never quits from Pause without confirm; every transition ≤ 250 ms and cancellable by input after the first 100 ms; `REINICIAR` focused on End so `Enter` alone retries.

**First-run prompt pattern:** `VERBO + OBJETO`, ≤ 24 chars, no articles where avoidable, no `!` except success. Canonical set: `AGARRA` · `LANZA AL RITMO` · `SUELTA AQUÍ` · `GOLPE AL RITMO` · `LLEVA EL LIMPIO AL DUCTO` · `EMPIEZA EL TURNO`.

---

## 14. Tutorial beat sheet

Seven gates, ~150 s at average pace, hard cap 240 s. The shift clock runs; stability loss is disabled until gate 7.

| # | Gate | Prompt (≤ 24 ch) | Success | Fail-forward | Words on screen |
|---|---|---|---|---|---|
| 1 | Move | `MUEVETE` | 200 px travelled | after 4 s, dotted circle at 120 px | 1 |
| 2 | Grab | `AGARRA` | 1 grab | item steered into `GRAB_RADIUS` | 1 |
| 3 | Throw | `LANZA` | 1 throw leaving the hold radius | aim assist ×1.5 until first success | 1 |
| 4 | Beat | `LANZA AL RITMO` | 2 throws ≥ GOOD | window widens to ±195 ms after 2 misses; granted after 3 | 3 |
| 5 | Match | `SUELTA AQUÍ` | 1 correct-colour insert | only the compatible washer is active | 3 |
| 6 | Strike | `GOLPE AL RITMO` | 1 strike ≥ GOOD on a turbulent washer | turbulence scripted once at 50 %, cannot explode | 3 |
| 7 | Deliver | `LLEVA EL LIMPIO AL DUCTO` | 1 clean delivery to the chute | beacon pulses every 2 s | 5 |

**Skip:** hold `Esc` 1 s or `Start` → immediate skip, `tutorial_done = true`, stability re-enabled. **Replay:** Pause → `VER TUTORIAL` (all gates, timers, hints; no stability loss). Never auto-triggers again, including after a crash.

**Why seven:** gates 1–3 are motor (a player who cannot move cannot be taught anything), gate 4 is the only novel concept, gates 5–7 are the loop. Collapsing 5–7 re-creates the owner's experience: three rules at once with no success signal between them.

---

## 15. Source table

Full citations, quotes and applicability: [appendix](UX_RESEARCH_SOURCES.md).

| Id | Title | Author / publisher | Year | Supports | Confidence |
|---|---|---|---|---|---|
| S01 | Finding the beat in Crypt of the NecroDancer | R. Clark / Game Developer | 2014 | §1 leeway, auto-calibration | verified-read |
| S02 | How to make a rhythm game for people who have no rhythm | A. Diaz / Polygon | 2023 | §1 sync-not-punish, visualiser | verified-read |
| S03 | Please redesign your UI for beat timing | Steam / Metal: Hellsinger | 2023 | §1 miss-cue failure | verified-read |
| S04 | Hands on with Patapon | T. Erickson / Pocket Gamer | 2008 | §1 frame metronome | verified-read |
| S05 | Overcooked: How Design Creates Teamwork | A. Iyer / SUPERJUMP | 2022 | §2 tickets, timers, layout | verified-read |
| S06 | Deliberately diegetic (GDC 2013) | D. Tach / Polygon | 2013 | §3 diegetic limits, colour | verified-read |
| S07 | Full list | Game Accessibility Guidelines | n.d. | §8 obligations | verified-read |
| S08 | Understanding SC 1.4.3 | W3C WAI | 2026 | contrast thresholds | verified-read |
| S09 | Understanding SC 2.3.1 | W3C WAI | n.d. | flash ceiling | verified-read |
| S10 | A quick guide to readable game text | K. Stevens / GamesIndustry.biz | 2020 | 28 px @1080p, 4.5:1 | verified-read |
| S11 | Diseñar la interfaz | Microsoft | n.d. | Spanish growth | verified-read |
| S12 | Onboarding techniques | Roblox Creator Docs | 2026 | contextual + 11 s hint | verified-read |
| S13 | Vlambeer feel numbers | T. Armitage quoting RPS | 2013 | §7 magnitudes | verified-read |
| S14 | Pixel Art Filtering | G. Sassone | 2021 | shimmer, integer scale | verified-read |
| S15 | Pixel Art (engine docs) | Excalibur | n.d. | shimmer/jaggies | verified-read |
| S16 | Remaking Celeste's Lighting | N. Berry | 2017 | 320×180, cutout lights | verified-read |
| S17 | Dead Cells art workflow | IWSE / GameRes | 2021 | 3D→2D normals, palette swap | verified-read |
| S18 | Half-Life 2's Invisible Tutorial | M. Brown / GMTK | 2015 | staging vs text | transcript-read |
| S19 | Ink Tank | Splatoon Wiki | n.d. | diegetic gauge | skimmed |
| S20 | Game UI Database | E. Coates | 2024 | screen-pattern reference | search-only |
| S21 | Visual metronome request | Steam | 2025 | optional beat bar | search-only |

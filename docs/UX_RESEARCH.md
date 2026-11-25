# UX / Game-Design Research — *Cosmic Spin Cycle*

**Author:** UX/Game-Design Research Lead · **Date:** 2026-11-24 · **Branch:** `ux/research`
**Scope:** evidence for the M6 screen-flow, HUD and tutorial overhaul. **Not** code, **not** art assets.
**Method:** 21 sources; 16 fetched and read in full (quotes in [the appendix](UX_RESEARCH_SOURCES.md)), 5 skimmed or search-only. Every number below is either quoted from a source, measured from this repo, or explicitly labelled **[inference]** with its arithmetic shown.

Measurements were taken from the worktree: `docs/CONTRACTS.md`, `scripts/ui/HUD.gd`, `data/layout.json`, `assets/fonts/Silkscreen-Regular.ttf` (via fontTools). Contrast ratios are WCAG relative-luminance calculations on the §B4 palette.

---

## 0. Executive summary

The owner's complaint is not a styling problem. Three independently measurable defects stack up: **the text is roughly half the size the industry considers the readability floor**, **the information is in the corners instead of at the objects it describes**, and **the centre of the screen — where the game's one true goal (the chute) sits — is occupied by a grade label**. Fix those and the same build becomes legible without adding a single mechanic. The evidence says the fix is *relocation and sizing*, not *more HUD*: Dead Space's own UI lead ended his GDC talk by conceding that diegetic purity loses to usability ([S06](UX_RESEARCH_SOURCES.md#s06)), rhythm games that people without rhythm can play all ship an explicit, optional metronome visual rather than trusting the music ([S01](UX_RESEARCH_SOURCES.md#s01), [S02](UX_RESEARCH_SOURCES.md#s02)), and chaotic co-op games stay readable by putting the recipe/timer *on the ticket* rather than in a manual ([S05](UX_RESEARCH_SOURCES.md#s05)).

The eight changes that follow from the evidence:

1. **Delete the 73-character bottom strip.** It is 11 px Silkscreen (7.7 px cap height) in `METAL_1` at **3.90:1** on the panel — under the 4.5:1 text floor ([S08](UX_RESEARCH_SOURCES.md#s08)) and roughly 58 % of the 19 px floor implied by EA's 28 px @1080p guidance ([S10](UX_RESEARCH_SOURCES.md#s10)). Nothing essential may live at y = 688 at all ([S07](UX_RESEARCH_SOURCES.md#s07)).
2. **Split the HUD into two corner clusters and keep the top-centre 608 px clear** for the north belt, which the current 48 px band still clips by 8 px (2 art px).
3. **Move the grade text off screen centre.** The chute occupies world 576–704 × 296–424; the current 44 px grade label spans y 286–346 and sits on top of it.
4. **One beat source plus one peripheral.** A contracting ring on Pip (2-beat lookahead) and a 4 px screen-frame pulse. Never a full-screen flash: at 142 BPM a per-beat flash is 2.37 Hz — legal under WCAG 2.3.1's 3 Hz ceiling but only 21 % under it ([S09](UX_RESEARCH_SOURCES.md#s09)).
5. **Every transient ≤ 0.45 × T_beat** = 257 / 229 / 208 / 190 ms for 105 / 118 / 130 / 142 BPM. The current grade label fades over ~625 ms, i.e. 1.1–1.5 beats — it is still on screen when the next beat lands.
6. **Shape before colour, always.** `red_1` is 1.82:1 and `funk_plum` 2.25:1 on `#0B0C10`; either as the sole carrier of "which washer" is invisible. Glyph + icon + position, colour only as reinforcement ([S07](UX_RESEARCH_SOURCES.md#s07)).
7. **Seven gated tutorial steps, ≤ 6 words per prompt, always skippable and replayable** — because players skip text ([S12](UX_RESEARCH_SOURCES.md#s12)) and because instructions must be replayable ([S07](UX_RESEARCH_SOURCES.md#s07)).
8. **Surface the queue, not just the target.** A delivery loop is 5.1–6.9 beats long while phase-3 spawns arrive every 3.7–4.0 beats, so the player is structurally behind; the HUD must answer "what is about to explode", not only "what am I holding" **[inference, arithmetic in §13]**.

---

## 1. Rhythm-game onboarding: teaching "act on the beat" without a text wall

### The question
What do shipped rhythm games actually put on screen so a player with no sense of rhythm can act on a beat, and what happens on a miss?

### Evidence
**NecroDancer deliberately gutted rhythm accuracy.** Ryan Clark prototyped ±100 ms (20 % of a 500 ms beat at 120 BPM), found that "the times when you are least accurate are the times when you are most stressed", widened the window, and reported it "felt best at 100 percent" leeway — half a beat either side — plus a leaky-integrator auto-calibration that bends the beat toward where the player *thinks* it is ([S01](UX_RESEARCH_SOURCES.md#s01)). He also found that moving the player on the beat and enemies between beats "doesn't feel like the whole game world is visually synchronized"; putting everything on the beat fixed the groove.

**Hi-Fi Rush removed the punishment, not the beat.** "The first thing that we did was make a system where no matter what you did, everything would sync up so it would land on the beat" — off-beat attacks still animate on the beat, on-beat attacks merely pay a bonus. It ships "a little visualizer that very clearly shows the beat", and the *world* carries cues: steam puffs, finger snaps, environment sway ([S02](UX_RESEARCH_SOURCES.md#s02)). They also cut a character-swap mechanic because "no one could get it … with the chaos of battle" and reduced partner calls to one timing-free button — a precedent for cutting, not teaching, complexity under chaos.

**Patapon uses the screen edge as the metronome**: "a thin white border encompassing the screen pulses to the beat", with combo reset on a missed beat and a fever state at 10 ([S04](UX_RESEARCH_SOURCES.md#s04)). The cue is peripheral, always visible, and never overlaps the play field.

**Metal: Hellsinger is the counter-example.** A player complaint documents the exact failure: the beat marker is "a narrow black chevron", the miss marker is a larger black chevron that overlaps it, so after one miss the wrong indicator becomes the more visible one — "you just trick into chaining misses" ([S03](UX_RESEARCH_SOURCES.md#s03)). Another player in the same thread asks for the beat widget to be "bigger or better configurable (size, position, bright of color)".

**Third-party reports confirm the visual channel is load-bearing.** A Polygon commenter on the Hi-Fi Rush interview says they play better with sound off, watching the optional beat bar, because the attack *queue* lands on the beat but contact lands after it ([S02](UX_RESEARCH_SOURCES.md#s02), comment). Separately, a Steam thread for an unnamed rhythm title asks for "a visual metronome … like the metronome bar you could have in Crypt of the Necrodancer, which could be deactivated" — the same request, twice, from players who own the genre.

### Adopt
- **Two channels, one job each.** `PulseRing` around Pip = *when to act* (contracts from 100 % radius to 100 % at the beat, then snaps back in 80 ms). Screen frame (4 px inset border) = *where the bar is* (downbeat accent only: 1 frame of `funk_cyan`, no fade).
- **2-beat lookahead, not 1.** At 142 BPM a single-beat ring gives 423 ms of anticipation, which is under the ~500 ms people need to plan a movement *and* aim. Start the contraction two beats out (846 ms) and mark the final beat with a tick.
- **An explicit, toggleable beat bar** in Options (`Ritmo visible: Sí/No`), default **on**, because our target player is the owner who "had no idea what to do".
- **Grade feedback attached to the event, not the centre**: the burst appears at the washer mouth, chute or item. A centre-screen word is only allowed for the *first* three throws of the tutorial.
- **On a miss, do not punish with a second signal.** NecroDancer's lesson plus Hellsinger's failure mode: the miss cue must be *smaller and further from* the beat cue than the hit cue, never larger and on top of it. Our miss is `fx_miss_puff` 12×12 at the item, plus a 90 ms desaturation of that item only.

### Don't copy
- **Don't copy NecroDancer's 100 % leeway.** Its challenge lives in tactical combat; ours lives in *routing under time pressure*, and the rhythm is the multiplier that makes routing expressive. Our windows (±65 / ±130 ms) are already in the generous band — 45.5 % of random presses at 105 BPM and 61.5 % at 142 BPM land ≥ GOOD per `AGENTS.md` §A5 — so widening further would delete the only skill axis we have. What we should copy is the *auto-calibration* idea, which we already ship as the 10 s wizard.
- **Don't copy Patapon's full-frame pulse as the primary cue.** It works because Patapon has one verb and a side-scrolling lane; we have four destinations and a 320×180 field where the frame is 1.1 % of the area but competes with 4 washers. Frame pulse stays secondary.

---

## 2. Chaotic multi-task clarity: what "do this next" looks like

### The question
In games that are deliberately about too much happening, how is the next action signalled, and how is overload avoided?

### Evidence
**Overcooked's legibility is carried by the ticket, not by the tutorial.** Orders stack at the top of the screen and each ticket *is* the recipe: ingredient icons in order. "As pending orders pile up on top of the screen, these same visual cues keep players focused on the next ingredient and task at hand" ([S05](UX_RESEARCH_SOURCES.md#s05)). Crucially, *every* task has a visible timer — chopping, cooking, and the customer order — so prioritisation is a comparison of three visible clocks rather than a memory task. One interact button does every stage, which removes the "which button" question entirely. The article's most useful negative finding: unwashed plates are the one system *without* a communicated timer, and they are the system players handle worst ("No YOU wash the plates this time!").

**Overload is managed by layout, not by HUD.** The first Overcooked level puts a counter between the cutting station and the pot so a single player physically cannot do the whole dish; the level *forces* a division of labour. Our analogue is the four-corner washer layout: the loop length is the difficulty dial.

**Contextual tutorials exist precisely to avoid front-loading.** Roblox's onboarding guidance names the mechanism: delay non-essential information, trigger instruction on first contact with a feature, and "players learn best by understanding the context of a situation" ([S12](UX_RESEARCH_SOURCES.md#s12)). The same document gives a usable timing heuristic: if playtests show most players find a button within 10 s, highlight it at 11 s — and show the hint only once.

### Adopt
- **A queue, always visible, ordered by deadline.** Four washer chips in the two corner clusters, each showing: requirement glyph (12 px art icon), remaining wash seconds as a 3-segment ring (we have `WASHER_CAPACITY = 3`), and a **turbulence deadline bar** that turns `hazard_orange` at 50 % progress. Sorted left-to-right by *time to explosion*, not by screen position. This is Overcooked's "three visible clocks" applied to four machines.
- **One button for context.** We already have it (`grab_throw` is grab *and* throw, `rhythm_strike` is the beat verb). Keep this and never add a third verb; Hi-Fi Rush cut a mechanic rather than teach a second rhythm ([S02](UX_RESEARCH_SOURCES.md#s02)).
- **Timer on everything, including the things we currently hide.** The plate-washing lesson says: if a system has no visible clock, players will deprioritise it until it fails. Turbulence must therefore show its countdown (`min(5 s, 8 beats)` = 3.38–4.57 s) from the moment it starts.
- **Highlight the *next* action for 11 s-then-once.** For a stuck player (no input for 8 s while carrying a clean item), edge-highlight the chute once per shift with a 2 px `clean_green` inset — and never again after the tutorial.

### Don't copy
- **Don't copy the ticket *stack* metaphor.** Overcooked tickets accumulate because orders are fungible and the player has 2–4 bodies. We have one body, one held item, and four fixed machines; a stack of tickets would be five competing rectangles at 320×180, i.e. 25 % of the screen for text we would then have to make 16 px. Fixed corner chips beat a scrolling list.
- **Don't add a "recommended action" arrow.** It converts a routing game into a follow-the-arrow game and destroys the only decision we have. Highlight *state* (about to explode), not *intent*.

---

## 3. Diegetic vs non-diegetic: when in-world HUD helps and when it hurts

### The question
Does putting information in the fiction actually help glanceability, or only immersion?

### Evidence
**Dead Space is the best-documented diegetic case, including its failure modes.** Dino Ignacio (Visceral, lead UI) at GDC 2013: "We were not just diegetic by design, we were diegetic by implementation" — the RIG bar is geometry, it casts light, it is not an overlay; non-diegetic information was placed *behind* the character ("Anything that didn't belong to him, we elegantly placed behind him"). The colour language was explicit: blue/white = interactive, red = locked, amber = ambient ([S06](UX_RESEARCH_SOURCES.md#s06)).

The same talk contains the counter-evidence. The Dead Space 3 workbench redesign was **"unusable"** — testers preferred the debug menu to the in-game one — and was replaced with a conventional full-screen UI. Ignacio's conclusion: "At the end of the day, none of that is important if your users really can't interact with your game" ([S06](UX_RESEARCH_SOURCES.md#s06)).

**Splatoon's ink tank shows the other edge.** The tank is a readable diegetic gauge — a white bar with a red sub-weapon threshold mark ([S19](UX_RESEARCH_SOURCES.md#s19)) — but community complaints (not officially confirmed) describe it becoming unreadable exactly when it matters: when the character's back is occluded by the roller animation or the player is in swim form.

**Eye-line is a guideline, not a taste.** The Game Accessibility Guidelines list, under Vision/Intermediate: "Avoid placing essential temporary information outside the player's eye-line", and under Vision/Basic: "Ensure no essential information is conveyed by a fixed colour alone" ([S07](UX_RESEARCH_SOURCES.md#s07)).

### Adopt
- **World-anchored for object state, screen-space for global state.** Washer requirement, wash progress, turbulence deadline, "this item is compatible" → anchored to the washer/item (holograms, progress ring, magnet dots). Stability, clock, combo, score → screen space. This is the split Dead Space itself conceded to.
- **Diegetic *and* redundant.** Every washer's requirement appears twice: as a 12 px art hologram at the machine's mouth (diegetic) and as a 12 px glyph in the corner chip (screen space). The player can read it where they look, and still read it when the machine is behind Pip.
- **A three-colour interaction language borrowed from Dead Space, remapped to our palette:** `funk_cyan` = you can act here now; `hazard_orange` = act soon or lose it; `clean_green` = done / deliverable. `metal_*` = inert. Never red for "wrong" alone — red_1/red_2 are the weakest hues on our background (1.82:1 / 3.35:1).
- **A locator, not a minimap.** Dead Space's locator line "replaced a more traditional mapping system" and was added "in the last minute". For us: a 1 px `clean_green` dotted line from a carried clean item to the chute, fading after 1.5 s — the only persistent world-space path in the game.

### Don't copy
- **Don't make the HUD *only* diegetic.** Our washers are 48×48 art px in the corners; the camera never rotates, but Pip's 24×24 body plus a 24×24 gas giant is 48 px of occlusion at the exact moment of insertion. A tank on a back is fine in third person; a requirement hologram behind a held gas giant is not.
- **Don't animate UI as geometry.** Dead Space could afford per-object light and particles because it rendered a 3D scene at 720p with a dozen UI objects. At 320×180 with a 30-colour palette, "the HUD is made of particles" means "the HUD shimmers". We fake it: 1 px outline, no glow, no sub-pixel offsets (see §4).

---

## 4. Pixel-art presentation at 320×180

### The question
What separates "pixel art" from "pixel art that reads at 1280×720", and which techniques are cheap at our scale?

### Evidence
**Our internal resolution is exactly Celeste's.** Noel Berry: "Our screen resolution is tiny (320x180)" — which is why he could pack 256 light masks into one 2048² texture and draw all lights in two passes ([S16](UX_RESEARCH_SOURCES.md#s16)). Two consequences: (a) we are in good company and (b) any technique that costs "per screen pixel" is 16× cheaper for us than for a 1280×720 native game.

**Celeste's lighting is cutout masks, not normal maps.** Lights are drawn to a mask, then wall shadow quads *erase* the light. Berry replaced a mesh-and-raycast implementation because it had "a lot of edge cases, bugs, and floating point precision problems". For a top-down room with four machines and no walls to speak of, we need neither: a mask + a screen-space vignette is enough, and it is palette-safe.

**Dead Cells gets its light from a 3D pipeline.** The documented workflow: render in Maya with AA off and filter `closest`, once for flat base colour and once for normals; import as layered PSB; in Unity set Filter = Pixel, Compression = None, slice with `smart` + bottom pivot, attach the `_NormalMap` as a secondary texture, and enable "Use Normal Map" on the 2D light. The colour sprite "only keeps the flat colour, no shading" — all shading comes from the normal ([S17](UX_RESEARCH_SOURCES.md#s17)). This is the single biggest lesson for our art direction: **do not paint light into the sprite.** But it is also explicitly *not* our pipeline: we have no 3D source, and generating normals for 176 hand-authored frames is out of scope for M6–M7.

**Shimmer is a maths problem, not a taste problem.** Non-integer scale or translation makes some texels fill a screen pixel and others straddle two; nearest-neighbour then produces "shimmering artifacts (inconsistent line widths) and jaggies when rotating objects" ([S15](UX_RESEARCH_SOURCES.md#s15)). Sassone's survey states the only free lunch: integer camera steps and integer scale work "if you don't add any zoom or rotation"; everything else needs a custom filter ([S14](UX_RESEARCH_SOURCES.md#s14)).

### Adopt
- **Lock three invariants and add a test for each:** camera position is `round(pos/4)*4`; every sprite scale is exactly 4; no `Node2D` in the world layer has a non-multiple-of-π/2 rotation. These are cheap asserts and they kill 90 % of shimmer.
- **Screen shake in whole art pixels.** Shake amplitude is quantised to `4 × n` world px and decays in 4 px steps. A 6 px shake (Vlambeer's number, §7) is 1.5 art px and therefore illegal for us.
- **Light as a palette operation, not a shader.** Pre-author a `night` and `alarm` variant of `env_room` by remapping `space_*`/`metal_*` slots (a 30-colour palette makes this a lookup table, not a render pass). This is Dead Cells' palette-swap idea at zero cost, and it cannot introduce off-palette colours.
- **Impact FX are 3–6 frames, sized 8–32 px, palette-locked, additive-free.** `fx_burst_perfect` 16×16 @ 4 frames / 18 fps = 222 ms, which fits the ≤ 0.45 T_beat budget at every BPM except 142 (190 ms) — at 142 BPM drop to 3 frames.
- **A 2×2 checker dither only on surfaces ≥ 24×24 art px**, per §B2; at 16×16 it eats the silhouette.

### Don't copy
- **Don't build a normal-map pipeline for M6/M7.** It is the correct answer for a 3D-source game and the wrong answer for 176 hand-drawn frames with a 30-colour palette: the normal map's whole value is shading detail *between* palette steps, which our palette discipline forbids.
- **Don't copy Celeste's per-light masks for a *static* room.** We have one room, no cave geometry, and a fixed camera. Bake the light into the room tile and spend the budget on the beat ring instead.
- **Don't copy Dead Cells' 3D→2D animation flow.** It trades artist time for pipeline time; we have neither, and our art is already shipped.

---

## 5. Title, menu and first-run patterns

### The question
What must the first screen do, and how do keyboard/gamepad users get through it without a dead end?

### Evidence
**Menus are an accessibility surface, not decoration.** The guidelines say: "Allow the game to be started without the need to navigate through multiple levels of menus"; "Ensure that all areas of the user interface can be accessed using the same input method as the gameplay"; "Ensure that all settings are saved/remembered"; and, for cognitive load, "Use an easily readable default font size" ([S07](UX_RESEARCH_SOURCES.md#s07)). Dead Space's frontend was treated as part of the fiction — same design language as the in-game UI, with the *same* elements the character sees ([S06](UX_RESEARCH_SOURCES.md#s06)) — which is a cheap win for us: a title screen that looks like the laundromat's control panel costs one background and no new art.

**Prominence beats text.** Roblox's guidance is blunt: text prompts "can be easily overlooked … If players don't notice them, they are of no benefit", and "players generally don't like to read instructions and skip through text prompts to get to gameplay" ([S12](UX_RESEARCH_SOURCES.md#s12)). The recommended fix is a spotlighted element with everything else dimmed — one unmistakable next action.

**Nothing in the sources supports a "press any key" gate.** It adds a state with no information, requires a second input to reach the first real choice, and is unreachable for a player whose keyboard layout or controller is not yet known to the game.

### Adopt
- **One screen, three items, focus already on the first:** `EMPEZAR TURNO` (default focus), `AJUSTES`, `SALIR`. Logo above, 2 px `funk_cyan` rule, room background at 40 % brightness as a live attract loop (Pip idles, one washer spins) — the room *is* the menu, per Dead Space's frontend principle.
- **No "press any key".** The first frame is already interactive and the first item is already focused; `Enter`/`A` starts. This satisfies "started without navigating multiple levels" and removes an input the player has not been taught.
- **Focus is drawn, not implied:** 2 px `funk_cyan` outline + 4 px offset + a 1 px `space_void` gap so the ring reads on any background; contrast of the ring against `space_deep` is 10.9:1.
- **Directional navigation only, plus pointer as a bonus.** D-pad/arrows move focus, `Enter`/`A` confirms, `Esc`/`B` backs out — the same buttons as gameplay (§7).
- **Options is one level deep and fits one screen:** volume (3 sliders), `Calibrar audio`, `Ritmo visible`, `Sacudida de pantalla`, `Tamaño de texto`, `Pantalla completa`. No sub-pages. Every setting persists (`Settings.cfg` already exists).
- **First-run injection, not a separate mode.** If `first_run == true`, `EMPEZAR TURNO` becomes `EMPEZAR TURNO ▸ TUTORIAL` and the tutorial is a modifier on the shift, not a menu branch.
- **Attract loop must not flash.** The idle washer animation runs at 3 fps and the logo holds; per WCAG 2.3.1 a title screen that strobes is the highest-risk surface in the game ([S09](UX_RESEARCH_SOURCES.md#s09)).

### Don't copy
- **Don't copy the "quit to desktop" default.** On a first-run menu, `SALIR` should sit last and require a confirm; the failure mode we are fixing is a player who bounces off the game before playing it.
- **Don't put settings on the title screen's first level.** Celeste-style granular assist menus are right for Celeste; six settings in one column is right for a 480 s arcade game, and GAG explicitly warns against menu depth.
- **Don't use the title screen to teach.** Every attempt to explain the loop in text on the title screen will be skipped ([S12](UX_RESEARCH_SOURCES.md#s12)); the tutorial exists for that.

---

## 6. Tutorial design: gates, not paragraphs

### The question
How do we teach five verbs, a beat and a routing rule in 2–4 minutes without a text wall?

### Evidence
**Teach at the moment of first contact.** Contextual ("just in time") tutorials are triggered by normal play, not by a menu; the stated benefits are retention, speed and reduced cognitive load in the first minutes ([S12](UX_RESEARCH_SOURCES.md#s12)). The same source's timing heuristic is the most actionable number in this document: if most players solve a step within 10 s, highlight at 11 s, once.

**Valve's invisible tutorial is the ceiling, not the floor.** *Half-Life 2* teaches "sawblades cut zombies" in two beats with no words: a bisected zombie is visible, the exit is blocked by blades, the player pulls a blade with the gravity gun and a zombie walks in ([S18](UX_RESEARCH_SOURCES.md#s18), subtitle transcript). That works because the *world* can stage a demonstration. Our world cannot stage "throw on the beat" — nothing in a laundromat demonstrates tempo — so the honest conclusion is that one verb (the beat) must be taught explicitly and the rest can be taught by staging.

**Hi-Fi Rush teaches "beat by beat, button by button"**, and its director frames that as an accessibility decision, not a difficulty one ([S02](UX_RESEARCH_SOURCES.md#s02)). **Overcooked teaches recipes with visual shorthand** — icons, not sentences ([S05](UX_RESEARCH_SOURCES.md#s05)).

**Three guidelines constrain the form:** include interactive tutorials; let players progress through text prompts at their own pace; allow instructions and narrative to be replayed; never convey essential information by text alone ([S07](UX_RESEARCH_SOURCES.md#s07)).

### Adopt
- **One verb per gate, one gate at a time.** Seven gates (§14). A gate opens only when the previous one's success condition is met; no timers except the shift clock.
- **Prompts are labels, not sentences.** ≤ 6 words, ≤ 24 characters, ≤ 2 lines, 20 px Silkscreen, anchored to the object (washer mouth, item, chute). No modal, no pause, no darkened screen. The beat keeps running.
- **Every gate has a visible success condition** (a ring fills, a washer flashes `clean_green`) so the player knows the gate ended without reading anything.
- **Idle hint at 11 s, once.** If no input for 11 s during a gate, the target pulses twice at 1 Hz. Never repeats within the gate.
- **Skip and replay are always available:** hold `Esc` 1 s or press `Start`; replayable from Pause → `Ver tutorial`. Skipping sets `tutorial_done = true` and never re-triggers automatically.
- **Fail-forward:** after 3 failed attempts at a gate, grant it, show the correct action once (200 ms ghost animation), and continue. A stuck player must never be stuck in the tutorial.

### Don't copy
- **Don't copy the invisible-tutorial purism.** It requires a world that can stage failure safely; ours has a 480 s clock and a stability bar that only goes down. We use *staged* first encounters (first item always lands near Pip, first washer always compatible) rather than pure environmental teaching.
- **Don't pause the beat to explain the beat.** Every rhythm game in the corpus keeps time running; a paused tutorial teaches a game that does not exist.
- **Don't teach turbulence before the player has successfully washed once.** It is a failure state; introducing it early teaches "the game punishes you" before it teaches "the game rewards you".

---

## 7. Game feel: a budget, not a vibe

### The question
Which feedback effects, at what magnitudes, and how do we keep them accessible?

### Evidence
The most concrete published numbers come from Vlambeer's Nuclear Throne, at **320×240 / 30 fps** — almost exactly our resolution ([S13](UX_RESEARCH_SOURCES.md#s13)):

| Element | Published value | At our 320×180, 60 fps, ×4 |
|---|---|---|
| Hit freeze | "about 10-20 milliseconds" | 10–20 ms = 1 frame at 60 fps; use 0 or 1 frame |
| Camera kick | "6 pixels" from aim direction | 6 px = 1.5 art px → **quantise to 4 or 8 world px** |
| Screen shake | "add 4 to the screenshake", degenerates quickly | 4 px = 1 art px; 8 px = 2 art px |
| Weapon kick | 2 px, snaps back | 1 art px |
| Enemy knockback | 3 px/frame | 12 world px/frame — too fast for our 340 px/s player; halve |
| Hit flash | first frame white, then 2 frames of "hit" pose | 1 frame white = 16.7 ms; safe |

The same source's framing is the important part: these were tuned by hand "until it's right", not derived. So the budget below is a *starting point to tune*, not a law.

### Adopt (the budget)

| Effect | Magnitude | Duration | Reduce-motion variant |
|---|---|---|---|
| Hitstop on PERFECT | 0 (never) | — | — |
| Hitstop on explosion | 2 frames | 33 ms | 0 frames |
| Screen shake | 4 px, decaying in 4 px steps | ≤ 120 ms | off, replaced by a 1 px `hazard_orange` frame flash |
| Camera punch on grade | none | — | — |
| White flash on insert | 1 frame, item only (not screen) | 16.7 ms | none |
| Grade burst | `fx_burst_perfect` 16×16, 4 frames @18 fps | 222 ms (3 frames @142 BPM) | static icon, 200 ms |
| Item scale pop | ×1.15 for 3 frames | 50 ms | none |

Rules: no hitstop on rhythm grading (it would desynchronise the player's internal clock); shake is quantised to art pixels; nothing transient outlives `0.45 × T_beat`.

### Don't copy
- **Don't copy "more juice is better".** The counter-talk ("Indies, resist the urge to 'juice it or lose it'", GDC Europe 2014) exists because juice competes with clarity. In a game whose failure mode is *not knowing what happened*, a screen-wide effect on every throw is an anti-feature.
- **Don't shake the camera on the beat.** It looks great in a 20-second GIF and makes 480 s nauseating; and a beat-synced shake at 2.37 Hz is a motion-sickness trigger, not a rhythm aid.

---

## 8. Accessibility: the non-negotiables

### Evidence → requirement
| Guideline ([S07](UX_RESEARCH_SOURCES.md#s07) unless noted) | Our concrete obligation |
|---|---|
| No essential info by fixed colour alone | Colour + glyph + position on every washer and item (already §B2; now enforced in HUD chips too) |
| No essential info by sound alone | Every SFX has a visual twin: turbulence alarm → flashing ring; chute accept → green flash; miss → item puff |
| Text contrast ≥ 4.5:1; large text ≥ 3:1; non-text UI ≥ 3:1 ([S08](UX_RESEARCH_SOURCES.md#s08)) | Current hint 3.90:1 **fails**; `metal_0` panel border 2.34:1 **fails** the 3:1 non-text rule |
| No more than 3 flashes/second ([S09](UX_RESEARCH_SOURCES.md#s09)) | 142 BPM = 2.37 Hz, legal; but keep flashing area ≤ 25 % of the screen and never full-screen magenta/red |
| Avoid placing essential temporary information outside eye-line | Kill the bottom strip; prompts go at the object |
| Indicate/allow reminder of controls and objectives | Pause shows controls + current goal; `H`/`Select` toggles a 3 s overlay |
| Allow text prompts at own pace; replay instructions | Prompts never auto-advance a gate; tutorial replayable from Pause |
| Settings saved/remembered; start without menu depth | `Settings.cfg`; title is 1 level, options 1 level |
| Provide option to turn off background movement / sudden events | `Sacudida`, `Ritmo visible`, `Fondo animado` toggles |
| Remap controls; all UI reachable by same input | Gamepad + keyboard parity from M6; remap is a stretch goal, documented as such |

### Adopt
- **A `Reduce motion` preset** that in one toggle sets shake 0, hitstop 0, bursts static, background animation off, beat ring to a non-scaling tick. GAG's "avoid any sudden unexpected movement" and Microsoft's accessibility tags both treat this as a single user-facing switch, not five.
- **A text-size setting with three steps: 20 / 24 / 28 px** for all body and prompt text. This is the cheapest possible fix for the readability defect and it is a *setting*, so the default can stay conservative.
- **A colour-blind check built into the palette usage, not a filter.** Our colour coding is already redundant by design (triangle/circle/square); the HUD must not introduce a *new* colour-only code (e.g. red vs green chips). Enforce: every chip carries a glyph.

### Don't copy
- **Don't ship a deuteranopia/protanopia post-process filter as the accessibility story.** At 30 colours with hand-picked ramps, a filter shifts the whole palette off-spec and breaks the lint. Redundancy is the fix; filters are a last resort.
- **Don't hide the beat bar behind "accessibility".** It belongs in Options → Gameplay, default on, because the owner's complaint is the target case, not an edge case.

---

## 9. Typography and HUD layout: the measured case

### What the repo actually renders today
`HUD.gd` builds labels at **9, 10, 11, 22, 24, 26 and 44 px**. Silkscreen's metrics (measured with fontTools on `Silkscreen-Regular.ttf`, upm 1000): **cap height 0.70 em**, x-height 0.50 em, average lowercase advance 0.723 em, average cap advance 0.745 em.

| Element | Size now | Cap height now | Floor at 720p | Verdict |
|---|---|---|---|---|
| Clock | 26 px | 18.2 px | ≈ 19 px | borderline |
| Combo / score | 24 / 22 px | 16.8 / 15.4 px | ≈ 19 px | **below** |
| Captions (`TURNO`, `COMBO`, `PUNTOS`) | 9 px | 6.3 px | ≈ 19 px | **~33 % of floor** |
| Bottom hint | 11 px | 7.7 px | ≈ 19 px | **~41 % of floor** |

The floor is derived from EA Sports' accessibility lead: text should be "a minimum of 28 pixels tall … on a 1080p screen", measured from user research ([S10](UX_RESEARCH_SOURCES.md#s10)). 28 px × (720/1080) = **18.7 px at 720p** **[inference: linear scaling of a viewing-distance rule; desktop viewing distance is shorter than a TV's, so this is conservative in the wrong direction — it is a floor, not a target]**.

### Spanish costs more than English — and short strings cost the most
Microsoft's localisation guidance gives growth *by source length*: 1–4 chars **+100 %**, 5–10 **+80 %**, 11–20 **+60 %**, 21–30 **+40 %**, 31–50 **+20 %**, >50 **+10 %** ([S11](UX_RESEARCH_SOURCES.md#s11)). Our copy is Spanish-first, so this matters in reverse when we stub English later — but the operational rule holds now: **never size a label to its text; size the zone and assert the string fits.**

Measured widths in Silkscreen Regular (px at the given size):

| String | chars | @14 | @16 | @20 | @24 |
|---|---|---|---|---|---|
| `ESTABILIDAD DEL TEJIDO` | 22 | 196 | 224 | 280 | 336 |
| `Recoge: ESPACIO · Suelta: ESPACIO` | 33 | 294 | — | — | — |
| `Aprieta ESPACIO al ritmo` | 24 | — | 250 | — | — |
| `Lavadora equivocada` | 19 | — | 218 | — | — |
| `Empezar turno` | 13 | — | — | 188 | 259 |
| `Se acabó el turno` | 17 | — | — | — | 325 |

Note that `ESTABILIDAD DEL TEJIDO` at 24 px is **336 px** — wider than the 300 px stability bar it is supposed to label. The label must shorten (see below), not the bar.

**Copy rules for 1280×720.** Capacity per line, Silkscreen Regular: 300 px zone holds **33/25/20/16** caps at 12/16/20/24 px. So:
- Persistent labels: **≤ 12 chars at 20 px** (`ESTABILIDAD`, 20 px = 166 px — fits a 180 px slot).
- Contextual prompts: **≤ 24 chars at 20 px, max 2 lines** (`Aprieta ESPACIO al ritmo` = 24 ch / 313 px — fits a 340 px bubble).
- Buttons: **≤ 14 chars at 24 px** (`Empezar turno` = 13 ch / 259 px).
- Grade words: **PERFECTO / BIEN / FUERA DE RITMO** are fine at 32–40 px *at the event*, not centre-screen (`FUERA DE RITMO` = 14 ch / 222 px at 24 px, 370 px at 40 px).

### The layout the evidence forces
`data/layout.json` in world px: north belt 336–944 × 40–104; west belt 40–104 × 240–560; south belt 336–944 × 616–680; washers at 144–336 / 944–1136 × 128–320 and 384–576; chute **576–704 × 296–424**; player spawn (640, 512).

- The **top band 0–48 px still clips the north belt by 8 px** (belt starts at y = 40). The band must become two **corner clusters**: left 0–330 × 0–120 (clock, turn), right 950–1280 × 0–120 (stability, combo, score). The 608 px between them stays clear for the belt.
- The **chute is at the exact screen centre** (640, 360) and the grade label currently occupies y 286–346 — 50 px of overlap with the chute's top edge. **Move all grade text to the event or to a 300 px band at y 600–680** (below the south belt, above nothing).
- Time-critical prompts must be within ~200 px of the player or the target; the bottom strip at y = 688 is 176 px from the south belt and 300+ px from the washers — outside eye-line by GAG's definition.

---

## 10. The 20-second test

A stranger who has never seen the build must be able to answer five questions in 20 s, in this order. Each row is a question, the moment it must be answerable, and the *single* affordance that guarantees it. If a second element competes for attention at that moment, the guarantee breaks — so M6 must suppress phase banners, score pop-ups and grade text for the first 20 s.

| # | By | The stranger must perceive | Affordance that guarantees it |
|---|---|---|---|
| 1 | 0–3 s | "I am the small cyan guy in a room with four machines and a hole in the middle." | Fixed camera on the room; Pip idles at (640, 512) facing the chute; the four washer portholes pulse once at 1 Hz, offset by 250 ms each, so the eye sweeps the room. |
| 2 | 3–6 s | "Things arrive on the belts and I can pick them up." | The **first** item spawns on the nearest active belt and is steered to land within `GRAB_RADIUS` of Pip; magnet dots connect item→Pip; prompt `AGARRA` (6 ch) at the item, not at the screen edge. |
| 3 | 6–10 s | "Doing it on the beat is better." | `PulseRing` contracts over 2 beats; the first throw is graded and the grade appears **at the item**; the ring's inner disc flashes 1 frame on the beat. |
| 4 | 10–15 s | "That machine wants this thing — and the wrong one costs me." | Compatible washer: 12 px hologram at the mouth + 1 px `funk_cyan` rim + a 400 ms beam. Incompatible: no rim, porthole dimmed 20 %. On a wrong insert, the −12 % stability chip animates *at the washer*, and the bar in the corner flashes once. |
| 5 | 15–20 s | "Clean things go to the middle, and that's the point." | Chute iris opens 3 frames, emits a `clean_green` beacon column (4 px wide, 96 px tall) for 600 ms; prompt `Lleva el limpio al ducto` (24 ch) anchored 40 px above the chute, once. |

**What must not be true in the first 20 s:** no phase banner; no turbulence; no belt reversal; no more than two text strings ever on screen at once; no shift clock urgency (start at 00:00 with 480 s ahead); no item type other than `rocky` + `solid` (the Phase 1 palette per §A6 #10).

**Test protocol (5 strangers, 20 s each):** ask only "¿qué tienes que hacer?" and "¿dónde lo llevas?". Pass = 4/5 name "lavar/meter en la lavadora" and 4/5 name "el centro/el ducto". Anything less means an affordance in the table above is not doing its job — fix the affordance, not the copy.

---

## 11. Feedback matrix

Intensity scale: **L** = local (≤ 16×16 art px at the event), **M** = object-scale (the machine), **H** = screen-scale (used twice per shift, maximum). All durations obey `≤ 0.45 × T_beat` (257/229/208/190 ms at 105/118/130/142 BPM). Reduced-motion column is what replaces the effect when `Reduce motion = on`.

| Event | Visual | Audio | Text (ES) | Intensity / duration | Reduced motion |
|---|---|---|---|---|---|
| **Grab** | Item snaps to hold point in 60 ms, 1 px `funk_cyan` tether to glove; sock only: 2-frame squelch squash | short squelch (sock) / soft clank (rocky) / low thud (gas) | none | L / 60 ms | tether only, no squash |
| **Throw — PERFECT** | `fx_burst_perfect` 16×16 @18 fps; item 1-frame white; ring flares ×1.2 | bright "tick" + music duck −2 dB for 80 ms | `PERFECTO` 32 px at the item, 380 ms | L / 190–257 ms | static magenta icon, 250 ms |
| **Throw — GOOD** | `fx_burst_good` 12×12 @18 fps; no white flash | softer tick | `BIEN` 24 px, 300 ms | L / 190–257 ms | static cyan icon, 250 ms |
| **Throw — MISS** | `fx_miss_puff` 12×12, item desaturated 90 ms; **no screen shake** | dull thud, pitch −2 semitones | `FUERA DE RITMO` 20 px **at the item**, 300 ms | L / 190–257 ms | same (already minimal) |
| **Wrong washer** | −12 %: stability chip at the washer shakes 4 px × 2; washer porthole flashes `red_1` 1 frame; ejected item spins | buzz 120 ms, 180 Hz | `Lavadora equivocada` 16 px, 600 ms | M / 250 ms | no shake; rim flashes twice at 2 Hz |
| **Correct insert** | Mouth rim `clean_green` 1 frame; drum spin starts on the next beat | soft chime, on the beat | none | L / 100 ms | same |
| **Turbulence start** | Porthole → `hazard_orange`; 3-segment meter appears; machine vibrates 1 art px at 2 Hz | alarm loop, 2 beats, then silent | `TURBULENTO` 14 px, persistent until resolved | M / until resolved | no vibration; meter + colour only |
| **Explosion (−25 %)** | `fx_explosion` 32×32, 6 frames @12 fps = 500 ms; 2-frame hitstop; shake 8 px in 4 px steps | boom + 400 ms noise tail | `¡EXPLOSIÓN!` 24 px at the machine | H / 500 ms | 0 hitstop, 0 shake, 1 px orange frame flash |
| **Clean done** | Item gains `fx_bubbles` 8×8 loop + `clean_green` 1 px rim; washer `done` 2 frames | microwave bell, 2 notes | none | L / 150 ms | bubbles static |
| **Chute delivery (+3 %)** | Chute `accept` 3 frames; item shrinks into the iris over 200 ms; score flies 200 px to the corner counter | cash-register "ding" + 60 ms shimmer | `+3` at the chute, and the item name once | M / 250 ms | no fly-to-corner; counter pulses once |
| **Shredder loss (−8 %)** | Shredder `idle` 3 frames + 6 px sparks; item erased with a 2-frame shrink | vacuum whoosh, 200 ms | `−8` at the shredder | M / 250 ms | sparks off; shredder rim flashes |

**Cross-cutting rules.** (1) Text is always *at the event*, never centre-screen, except the tutorial's first three throws. (2) No two events may use the same colour for opposite meanings: `clean_green` is always gain, `hazard_orange` always threat, `funk_magenta` always precision. (3) The stability bar is the only feedback allowed to change *global* state, and it must animate over ≥ 300 ms so a −25 % reads as a slide, not a teleport. (4) Sounds are mixed so the beat stem is never ducked for more than 80 ms.

---

## 12. Contrarian findings

**1. "Diegetic HUD is better" is false as a general rule — and Dead Space's own designer says so.** The talk that made diegetic UI famous ends with its author abandoning it for the workbench because testers preferred the debug menu. World-anchored UI is better *for object state the player is looking at* and worse *for global state the player must monitor peripherally*. We should be diegetic for "which washer wants what" and stubbornly non-diegetic for clock, stability and combo. The industry lesson is not "more diegetic", it is "put information where the eye already is".

**2. "Teach by level design, never by text" does not survive contact with a rhythm mechanic.** *Half-Life 2* can stage "sawblades cut zombies" because physics is self-evident. Nothing in a laundromat demonstrates that a throw must land within ±130 ms of a beat; there is no diegetic object that can show a timing window. Every shipped rhythm game in the corpus therefore ships an explicit visualiser (Hi-Fi Rush's beat bar, Patapon's frame pulse, NecroDancer's beat bar). The correct position is: **stage the verbs, state the beat**. Six words at the right moment beat an elegant level that teaches nothing about tempo.

**3. "Screen shake is free juice" is wrong at 320×180, and the canonical numbers are illegal for us.** Vlambeer's 6 px camera kick and 4 px shake come from a 320×240 game drawn 1:1. At ×4, 6 px is 1.5 art pixels: the sprite lands between texels and the whole screen shimmers, which is precisely the artefact the pixel-art literature warns about. Every shake amplitude must be a multiple of 4 world px, which means the effective granularity is coarse (1 art px = 4 screen px) and the budget is *smaller*, not larger, than a native-resolution game's.

**4. "The HUD is too busy, so remove HUD" misdiagnoses the problem.** The owner's failure was not too much information; it was information in the wrong place at the wrong size. Our screen has 7 persistent text labels, 4 of them at 9–11 px, and *none* at the objects they describe. Removing labels would make it worse. The fix is relocation (world-anchored), consolidation (3 global numbers, not 7) and magnification (20 px floor) — a *net addition* of diegetic elements alongside a net removal of screen-space text.

**5. "One item at a time is the skill" may be structurally unfair in phases 3–4.** From `layout.json`: spawn (640, 512) → nearest washer mouth (240, 576) = 405 px = 1.19 s at 340 px/s; mouth → chute (640, 360) = 455 px = 1.34 s; a full loop is **2.5–2.9 s = 5.1–6.9 beats**. Phase-3 spawns arrive every 1.7 s = **3.7–4.0 beats**. So the loop costs more beats than the spawn interval grants, and the deficit can only be absorbed by the 3-slot washer buffer and by wash time overlapping travel. That is a legitimate design (it manufactures the chaos) but it means the HUD must show the *queue depth*, because no amount of skill closes a 1.5× throughput gap with one pair of hands **[inference from `AGENTS.md` §A5 constants and `layout.json`; verify with `tools/balance_sim.gd`]**.

---

## 13. Menu and screen-flow spec

**Screens (6):** Title → Options / Calibration → Shift (with tutorial modifier) → Pause (overlay) → End → Retry.

| Screen | Must contain | Focus order & default | Transition |
|---|---|---|---|
| **Title** | `ui_logo` 160×48 art px centred at y 200; three buttons stacked at y 380/440/500, each 320×48; room background at 40 % brightness, Pip idle loop, one washer spinning; version + seed in the corner at 12 px | `EMPEZAR TURNO` (default, focused) → `AJUSTES` → `SALIR`. D-pad/arrows; `Enter`/`A`; `Esc`/`B` quits only with a confirm | 180 ms: logo drops 8 px + fades in, buttons stagger 60 ms |
| **Options** | 6 rows, single column, label left / value right: `Volumen` (3), `Calibrar audio`, `Ritmo visible`, `Sacudida`, `Tamaño de texto`, `Pantalla completa`. Footer: `B: volver` | First row focused; left/right changes value; `Esc`/`B` returns to Title | 120 ms cross-fade, no slide |
| **Calibration** | Existing 10 s wizard; big tap target, live offset readout, `Repetir` / `Listo` | `Listo` focused when offset is valid | reuse existing modal |
| **Pause** | Frozen play field at 30 % dim; `REANUDAR` (default), `VER TUTORIAL`, `AJUSTES`, `SALIR AL TÍTULO`; below: controls legend (4 lines, 14 px) + current objective (1 line, 20 px) | `REANUDAR`; `Esc`/`Start` also resumes | 100 ms dim, audio low-pass |
| **End** | Result word (`TURNO COMPLETO` / `COLAPSO`), rank `S/A/B/C` at 48 px, 4 stats (washed, accuracy %, max combo, score), seed, `REINICIAR` (default) / `TÍTULO` | `REINICIAR`; `R` is a shortcut | 250 ms fade from gameplay |
| **Restart** | — | must complete in **< 500 ms** (`RESTART_MAX_S`) | hard cut |

**Rules.** No screen has more than 6 focusable items. No screen requires the mouse. `Esc` never quits from Pause without a confirm. Every transition is ≤ 250 ms and skippable by any input except during the 100 ms dim. The End screen's `REINICIAR` is always focused so a keyboard player can retry with `Enter` alone.

**First-run prompt copy pattern** (the only strings a stranger reads before playing): `VERBO + OBJETO`, ≤ 24 chars, no articles where avoidable, no exclamation marks except on success. Canonical set: `AGARRA` · `LANZA AL RITMO` · `SUELTA AQUÍ` · `GOLPE AL RITMO` · `LLEVA EL LIMPIO AL DUCTO` · `EMPIEZA EL TURNO`.

---

## 14. Tutorial beat sheet

Seven gates, ~150 s total at average pace, hard-capped at 240 s. The shift clock runs but stability loss is disabled until gate 7 (fail-forward). Each gate: one verb, one success condition, one prompt, max 3 s of text.

| # | Gate | Prompt (ES, ≤ 24 ch) | Success condition | Fail-forward | Max on-screen words |
|---|---|---|---|---|---|
| 1 | Move | `MUEVETE` | 200 px travelled in any direction | after 4 s, a 1 px dotted circle at 120 px radius | 1 |
| 2 | Grab | `AGARRA` | 1 successful grab | item is steered into `GRAB_RADIUS` | 1 |
| 3 | Throw | `LANZA` | 1 throw that leaves the hold radius | auto-aim assist ×1.5 until first success | 1 |
| 4 | Beat | `LANZA AL RITMO` | 2 throws ≥ GOOD | window widens to ±195 ms after 2 misses; gate granted after 3 | 3 |
| 5 | Match | `SUELTA AQUÍ` | 1 correct-colour insert | the only active washer is the compatible one | 3 |
| 6 | Strike | `GOLPE AL RITMO` | 1 strike ≥ GOOD on a `TURBULENT` washer | turbulence is scripted once, at 50 % progress, and cannot explode during the gate | 3 |
| 7 | Deliver | `LLEVA EL LIMPIO AL DUCTO` | 1 clean item delivered to the chute | chute beacon pulses every 2 s until first delivery | 5 |

**Skip rules.** Hold `Esc` 1 s or press `Start` at any time → immediate skip, `tutorial_done = true`, stability loss re-enabled. Replay from Pause → `VER TUTORIAL` (replays gates 1–7 with all timers and hints, no stability). The tutorial never auto-triggers again, including after a crash (`Settings.cfg`).

**Why seven and not three:** gates 1–3 are motor (a player who cannot move cannot be taught anything), gate 4 is the only genuinely novel concept, gates 5–7 are the *loop*. Collapsing 5–7 into one gate would re-create the owner's experience: three rules at once with no success signal between them.

---

## 15. Source table

Full citations, quotes and applicability are in [the appendix](UX_RESEARCH_SOURCES.md).

| Id | Title | Author / publisher | Year | Supports | Confidence |
|---|---|---|---|---|---|
| S01 | Finding the beat in Crypt of the NecroDancer | Ryan Clark / Game Developer | 2014 | §1 leeway, auto-calibration, world-on-beat | verified-read |
| S02 | How to make a rhythm game for people who have no rhythm | A. Diaz / Polygon | 2023 | §1 sync-instead-of-punish, beat visualiser, cut mechanics | verified-read |
| S03 | Please redesign your UI for beat timing | Steam community / Metal: Hellsinger | 2023 | §1 miss-indicator overlap failure | verified-read |
| S04 | Hands on with Patapon | T. Erickson / Pocket Gamer | 2008 | §1 peripheral frame metronome, combo reset | verified-read |
| S05 | Overcooked: How Design Creates Teamwork | A. Iyer / SUPERJUMP | 2022 | §2 tickets-as-recipe, visible timers, layout | verified-read |
| S06 | Deliberately diegetic (GDC 2013) | D. Tach / Polygon | 2013 | §3 diegetic limits, colour language | verified-read |
| S07 | Full list | Game Accessibility Guidelines | n.d. | §8 all obligations | verified-read |
| S08 | Understanding SC 1.4.3 Contrast | W3C WAI | 2026 | 4.5:1 / 3:1 thresholds | verified-read |
| S09 | Understanding SC 2.3.1 Three Flashes | W3C WAI | n.d. | 3 Hz flash ceiling | verified-read |
| S10 | A quick guide to readable game text | K. Stevens via GamesIndustry.biz | 2020 | 28 px @1080p floor, 4.5:1 | verified-read |
| S11 | Diseñar la interfaz (string growth) | Microsoft | n.d. | Spanish expansion by length | verified-read |
| S12 | Onboarding techniques | Roblox Creator Docs | 2026 | contextual/timed hints, 11 s rule | verified-read |
| S13 | Vlambeer/Nuclear Throne feel numbers | T. Armitage quoting RPS | 2013 | §7 magnitudes | verified-read |
| S14 | Pixel Art Filtering | G. Sassone | 2021 | shimmer, integer scale | verified-read |
| S15 | Pixel Art (engine docs) | Excalibur | n.d. | shimmer/jaggies statement | verified-read |
| S16 | Remaking Celeste's Lighting | N. Berry | 2017 | 320×180, cutout lights | verified-read |
| S17 | Dead Cells art workflow | IWSE / GameRes | 2021 | 3D→2D normals, palette swap | verified-read |
| S18 | Half-Life 2's Invisible Tutorial | M. Brown / GMTK | 2016 | staging vs text | transcript-read |
| S19 | Ink Tank | Splatoon Wiki | n.d. | diegetic gauge design | skimmed |
| S20 | Game UI Database | E. Coates | 2024 | screen-pattern reference | search-only |
| S21 | Visual metronome request (Steam) | Steam community | 2025 | optional beat bar demand | search-only |

<!-- END -->

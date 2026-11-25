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

<!-- END -->

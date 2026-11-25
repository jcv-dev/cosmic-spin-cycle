# UX Research — Sources Appendix

Companion to [UX_RESEARCH.md](UX_RESEARCH.md). **All URLs accessed 2026-11-24.**
Confidence: **verified-read** (fetched, read, quotes checked against page text) · **transcript-read** (read via subtitle track) · **skimmed** · **search-only** (no full text available). Quotes ≤ 30 words, verbatim except where marked as a translation.

> Publishers that truncate or block plain fetches were read through a text-extraction proxy; quotes were checked against the extracted article text and the original publisher is cited. Nothing is quoted from a search snippet.

---

### S01
**Game Design Deep Dive: Finding the beat in *Crypt of the NecroDancer***
Ryan Clark (Brace Yourself Games) · Game Developer · 2014-09-16 · <https://www.gamedeveloper.com/audio/game-design-deep-dive-finding-the-beat-in-i-crypt-of-the-necrodancer-i-> · **verified-read**
- Prototyped ±100 ms at 120 BPM ("what rhythm games traditionally do"); accuracy collapses under stress.
- Widened to half a beat each way — "it felt best at 100 percent".
- Leaky-integrator auto-calibration bends the beat toward the player's perceived beat, capped at ½ beat.
- Player and enemies act on the same beat so the world feels synchronised.

> "I tried increasing this leeway value and was surprised to discover that it felt best at 100 percent!"

**Applicability:** our ±65/±130 ms windows are already generous — copy the auto-calibration (we ship it as the wizard), not the widening; put all world motion on the beat.

---

### S02
**How to make a rhythm game for people who have no rhythm**
Ana Diaz · Polygon · 2023-02-11 · <https://www.polygon.com/gaming/23594230/hi-fi-rush-interview-rhythm-game-development/> · **verified-read**
- Everything syncs to the beat whatever the input; on-beat hits pay a bonus instead of off-beat hits failing.
- Ships "a little visualizer that very clearly shows the beat"; world cues (steam, finger snaps).
- Cut a mid-battle rhythm swap: "no one could get it … with the chaos of battle"; partner call reduced to one timing-free button.
- A reader reports the attack *queue* is on the beat while contact lands after it; they play better watching the bar with sound off.

> "The first thing that we did was make a system where no matter what you did, everything would sync up so it would land on the beat."

**Applicability:** grade the input, animate the effect; cut rather than teach secondary rhythm verbs; the beat bar is a feature, not a crutch.

---

### S03
**"Please redesign your UI for beat timing"**
Steam community thread · Metal: Hellsinger · 2023-12-09 · <https://steamcommunity.com/app/1061910/discussions/0/4027970229989779667/> · **verified-read** (single user case)
- Beat marker: a narrow black chevron. Miss marker: a *larger* black chevron that overlaps it.
- After one miss the wrong indicator is the more legible one, producing chains of misses.
- Others ask for size/position/brightness configurability.

> "The visual indicator for a missed beat is a larger black chevron, more or less overlapping the actual timer."

**Applicability:** the miss cue must be smaller and spatially separate from the beat cue; expose beat-widget size in Options.

---

### S04
**Hands on with Patapon on PSP**
Tracy Erickson · Pocket Gamer · 2008-01-02 · <https://www.pocketgamer.com/patapon/hands-on-with-patapon-on-psp/> · **verified-read**
- Four-button drum language; commands are four-beat patterns.
- The metronome is the screen border, pulsing on the beat.
- Missing a beat or resting a measure resets combo; combo 10 triggers fever mode.

> "A thin white border encompassing the screen pulses to the beat, giving you a visual indication of when to press buttons."

**Applicability:** a peripheral frame pulse is a legitimate secondary channel; borrow "fever" as visible combo state.

---

### S05
**Overcooked: How Design Creates Teamwork**
Abhishek Iyer · SUPERJUMP · 2022-11-17 · <https://www.superjumpmagazine.com/overcooked-how-design-creates-teamwork/> · **verified-read**
- Orders stack at the top; each ticket *is* the recipe, in ingredient icons.
- Every cooking task and order has a visible timer → prioritisation by comparison, not memory.
- One interact button performs every stage; level geometry forces cooperation.
- Negative case: unwashed plates are the one system without a communicated timer, and players handle them worst.

> "As pending orders pile up on top of the screen, these same visual cues keep players focused on the next ingredient and task at hand."

**Applicability:** washer chips must carry the requirement glyph (ticket = recipe); give turbulence a visible clock; layout is the difficulty dial.

---

### S06
**Deliberately diegetic: Dead Space's lead interface designer at GDC**
Dave Tach · Polygon · 2013-03-31 (Dino Ignacio, Visceral) · <https://www.polygon.com/2013/3/31/4166250/dead-space-user-interface-gdc-2013/> · **verified-read**
- Diegetic "by design *and* implementation": geometry, light, particles — not overlays.
- Non-diegetic information moved behind the character; colour encodes interaction (blue/white interactive, red locked, amber ambient).
- The Dead Space 3 workbench was "unusable" — staff preferred the debug menu — and was replaced by a conventional full-screen UI.

> "At the end of the day, none of that is important if your users really can't interact with your game."

**Applicability:** diegetic for object state, screen-space for global state; adopt a three-colour interaction language; "the player can't read it" vetoes any in-world UI idea.

---

### S07
**Full list**
Game Accessibility Guidelines · n.d. · <https://gameaccessibilityguidelines.com/full-list/> · **verified-read**
- Vision: no essential info by fixed colour alone; high contrast; avoid placing essential temporary information outside the player's eye-line.
- Cognitive: interactive tutorials; text prompts at own pace; start without multiple menu levels; readable default font size; no essential info by text alone; remind controls and objectives; contextual help.
- Advanced: replay all narrative and instructions; avoid sudden unexpected movement.
- General: settings saved/remembered; offer a means to bypass non-core gameplay.

> "Avoid placing essential temporary information outside the player's eye-line"

**Applicability:** generates most M6 acceptance criteria; §8 maps each clause to an obligation.

---

### S08
**Understanding SC 1.4.3: Contrast (Minimum)**
W3C WAI · WCAG 2.1 Understanding · updated 2026-10-04 · <https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html> · **verified-read**
- Text ≥ 4.5:1; large text (≥ 18 pt / 14 pt bold ≈ 24 px / 18.5 px) ≥ 3:1; non-text UI 3:1 under 1.4.11.
- Luminance-based, so hue is irrelevant to legibility; advisory against red-on-black for protanopia.
- 4.5:1 ≈ 20/40 acuity; 7:1 ≈ 20/80.

> "The visual presentation of text and images of text has a contrast ratio of at least 4.5:1"

**Applicability:** `metal_1` on `space_deep` = 3.90:1 → our hint fails; `metal_0` borders 2.34:1 → fail the 3:1 rule; red-on-black advisory applies to `red_1`/`red_2`.

---

### S09
**Understanding SC 2.3.1: Three Flashes or Below Threshold**
W3C WAI · WCAG 2.1 Understanding · n.d. · <https://www.w3.org/WAI/WCAG21/Understanding/three-flashes-or-below-threshold.html> · **verified-read**
- ≤ 3 flashes in any one second, or below the general/red flash thresholds.
- A general flash is a ≥ 10 % relative-luminance change pair; red flashes treated separately.
- Combined flashing area ≤ ~25 % of a 10° field.

> "Web pages do not contain anything that flashes more than three times in any one second period"

**Applicability:** 142 BPM = 2.37 Hz is legal in rate; the risk is area and saturation — no full-screen magenta/red flashes.

---

### S10
**A quick guide to readable game text**
Karen Stevens (EA Sports) via GamesIndustry.biz · 2020-08-05 · <https://www.gamesindustry.biz/a-quick-guide-to-readable-game-text> · **verified-read**
- Minimum text 28 px tall at 1080p, from user research; broadcast caption guidance is 80 px.
- Offer resizing, but never ship a tiny default; contrast 4.5:1.
- Sans-serif; a "fancy" display font should be toggleable.

> "If no one can read your text, it may as well as not exist."

**Applicability:** 28 px @1080p ⇒ ≈ 19 px @720p; our 9–11 px labels are 33–41 % of that; a three-step text size is cheap and sourced.

---

### S11
**Diseñar la interfaz (localisation string growth)**
Microsoft · MSDN (VS 2005 docs, Spanish) · n.d. · <https://learn.microsoft.com/es-es/previous-versions/cc450452(v=vs.71)> · **verified-read**
- Growth by English source length: 1–4 chars +100 %, 5–10 +80 %, 11–20 +60 %, 21–30 +40 %, 31–50 +20 %, >50 +10 %.
- Reserve the space or translators must redesign the UI; avoid abbreviations and text baked into bitmaps.

> "La longitud de las cadenas de texto varía de un idioma a otro."

**Applicability:** short labels are the most expensive to translate — never size a control to its current string.

---

### S12
**Onboarding techniques**
Roblox Creator Docs · updated 2026-11-24 · <https://create.roblox.com/docs/en-us/production/game-design/onboarding-techniques> · **verified-read**
- Text pop-ups "can be easily overlooked"; world-anchored visuals are harder to miss.
- Contextual ("just in time") tutorials improve retention, speed onboarding, cut first-session load.
- Timed-hint heuristic: if most players act within 10 s, highlight at 11 s, once.

> "Players generally don't like to read instructions and skip through text prompts to get to gameplay."

**Applicability:** the 11 s idle hint is directly sourced; prompts must be labels at objects, not paragraphs in corners.

---

### S13
**Vlambeer / *Nuclear Throne* feel numbers**
Tom Armitage (infovore.org), quoting Rock Paper Shotgun's 2013-10-21 Nijman interview · <https://infovore.org/tag/vlambeer> · **verified-read**
- One pistol shot, 320×240 @30 fps: shell 2–4 px/frame, bullet 16 px/frame.
- Camera kicked 6 px opposite aim; "add 4 to the screenshake", degenerating quickly; weapon kick 2 px.
- Enemy knockback 3 px/frame; hit anim = 1 white frame + 2 hit frames.
- The game freezes 10–20 ms on every hit.

> "The game also freezes for about 10-20 milliseconds whenever you hit something."

**Applicability:** reference magnitudes for §7 — authored at 1:1, so at ×4 they must be quantised to 4 px.

---

### S14
**Pixel Art Filtering**
Gabriel Sassone · 2021-04-12 · <https://jorenjoestar.github.io/post/pixel_art_filtering/> · **verified-read**
- Non-integer scale/translation makes some texels fill a pixel and others straddle two → shimmer.
- Integer camera steps and integer scale work only without zoom or rotation.
- Nearest is right inside texels and wrong at edges; bilinear alone blurs; six shader fixes documented with code.

> "One of the most annoying problem we are seeing … is the pixel 'shimmering' happening when scaling or moving a pixel art image with non-integer values."

**Applicability:** lock camera to integer steps and scale ×4; if zoom is ever added, budget a filter or forbid zoom.

---

### S15
**Pixel Art (engine documentation)**
Excalibur.js docs · n.d. · <https://github.com/excaliburjs/excalibur/blob/27ced7508b75926ee5bf8ee0a37dd68d04d35e3e/site/docs/04-graphics/06.0-pixel-art.mdx> · **verified-read**
- The naive nearest + no-AA approach ships widely but has artefacts.
- Names them: inconsistent line widths and rotation jaggies; suggests a higher internal pixel ratio for very low logical resolutions.

> "shimmering artifacts (inconsistent line widths) and jaggies when rotating objects"

**Applicability:** the two artefacts our M7 screenshot comparison must test for. (The pixelRatio advice does not apply — we want fixed 320×180.)

---

### S16
**Remaking Celeste's Lighting**
Noel Berry · 2017-09-25 · <https://noelfb.com/posts/celeste_lighting/> · **verified-read**
- Celeste's internal resolution is 320×180 — identical to ours.
- A mesh+raycast light implementation was abandoned for "edge cases, bugs, and floating point precision problems".
- Replaced with a cutout mask (draw spotlight, walls erase shadow), then one light per colour channel, then all lights in one 2048² atlas.

> "Our screen resolution is tiny (320x180)"

**Applicability:** our resolution is proven and per-screen-pixel effects are cheap; for one static room, bake light into the room tile instead of running lights.

---

### S17
**关于《死亡细胞》美术工作流的初步探索 (Dead Cells art workflow)**
IWSE / INDIENOVA, republished on GameRes · 2021-04-19 · <https://www.gameres.com/883032.html> · **verified-read** (Chinese)
- *Dead Cells* renders 3D in Maya to pixel-style colour + normal sequences (AA off, `closest` filter).
- Colour sprites keep only flat base colour; the normal map supplies all lighting.
- Unity: Filter = Pixel, Compression = None, `smart` slicing, bottom pivot, `_NormalMap` secondary texture, 2D light with "Use Normal Map".
- Palette-swap variants are shader-driven (sample a palette texture), not repainted.

> 颜色精灵上的只保留了固有色，并没有添加阴影 ("the colour sprite keeps only the flat colour, with no shading added") — my translation.

**Applicability:** don't paint light into sprites; palette-swap is our cheapest variant mechanism; the normal-map half is out of scope for us.

---

### S18
**Half-Life 2's Invisible Tutorial**
Mark Brown · Game Maker's Toolkit · 2015-01-26 · <https://youtu.be/MMggqenxuZc> · **transcript-read** (zh-CN subtitle track via Amara; passage translated)
- Contrasts a hypothetical *Dead Space*-style tutorial (blood message, pop-up, audio log, NPC call, second pop-up) with two silent beats.
- Ravenholm sawblade sequence: bisected zombie visible → exit blocked → gravity gun pulls a blade → zombie walks in → discovery.
- Argues Valve teaches mechanics, weapons, enemies and puzzles without pop-ups, by staging and sight-lines.

> "《戰慄時空2》成功解釋一樣的東西，只用了兩個橋段，而且一個字都沒講" ("Half-Life 2 explained the same thing in two beats, without a single word") — my translation.

**Applicability:** stage the verbs we can stage; don't try to stage the beat window — nothing in the fiction demonstrates tempo.

---

### S19
**Ink Tank**
Splatoon Wiki (Fandom) · n.d. · <https://splatoon.fandom.com/wiki/Ink_Tank> · **skimmed**
- Back-worn tank is the game's ammo display; a white bar shows ink, a red triangle marks the sub-weapon threshold.
- A light flashes when empty and when the special is ready; refill has its own icon.

> "It has a white-colored bar for the current amount of Ink inside, with a red bar … that indicates how much Ink is enough to use their Sub Weapon."

**Applicability:** a diegetic gauge can carry a *threshold*, not just a quantity — our washer ring should mark the turbulence point the same way.

---

### S20
**Game UI Database 2.0**
Edd Coates · Game UI Database / 80.lv · 2024-08-06 · <https://gameuidatabase.com/about.php> · **search-only**
- Free reference library filterable by screen type, controls, textures, patterns, HUD elements, colour.
- 2.0 added 55,500 screenshots/videos across 1,000+ games; invites screenshots of each settings category.

> "over 55,500 new game screenshots and videos, all filterable by screen types, controls, textures, patterns, HUD elements, color, and more"

**Applicability:** use for the M6 layout review; no layout claim in the main doc rests on it (individual entries not browsed).

---

### S21
**"Feedback: Visual Metronome"**
Steam community · 2025-06-14 · <https://steamcommunity.com/app/3404260/discussions/0/555745354809663411> · **search-only**
- Player cannot tell whether they are in sync; asks for an optional visual metronome "like the metronome bar you could have in Crypt of the Necrodancer".
- Describes a felt latency between stick input and feedback.

> (no quote used — page body not retrieved)

**Applicability:** corroborates S03/S04 that a *toggleable* beat visual is a recurring request; not sole support for any recommendation.

---

## Claims I could not verify

1. **NecroDancer's "100 percent" in milliseconds** — Clark gives the percentage only; "half a beat each way" is my interpretation (the 20 % → ±100 ms figure *is* stated).
2. **Hi-Fi Rush's judgement windows** — never published; no number claimed.
3. **Metal: Hellsinger's chevron dimensions/colours** — described qualitatively only.
4. **Overcooked's ticket cap; PlateUp!/Cook Serve Delicious queue limits** — no fetchable primary source; no numbers used.
5. **Splatoon ink-tank occlusion** — only forum posts (search-only); treated as anecdote.
6. **28 px @1080p → 19 px @720p** — the 28 px figure is sourced, the conversion is my arithmetic and is labelled inference.
7. **Dead Cells' original Gamasutra article** — redirected; claims come from the verified Chinese reproduction (S17), which cites it.
8. **Metroid Prime, Return of the Obra Dinn, Celeste assist mode, TLOU2, Hades, Forza, PlateUp!, Moving Out, BPM, Rhythm Heaven** — requested in the brief but *not* fetched as primary sources in this pass. Nothing in the main document depends on them; the gap is listed rather than hidden.
9. **Game UI Database entries** — not browsed individually; no screenshot described.
10. **Xbox accessibility feature tags** — only localised renderings surfaced; reduce-motion is cited via S07 instead.

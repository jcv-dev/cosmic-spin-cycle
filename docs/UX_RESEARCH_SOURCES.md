# UX Research — Sources Appendix

Companion to [UX_RESEARCH.md](UX_RESEARCH.md). **All URLs accessed 2026-11-24.** Confidence marks: **verified-read** (fetched and read; quotes checked against the page), **transcript-read** (read via a subtitle/transcript track), **skimmed** (fetched, partially read), **search-only** (only the search result/summary was available; no full text). Quotes are ≤ 30 words and verbatim except where marked as a translation.

> Method note: several publishers truncate server-side or block plain fetches. Where a page body was reachable only through a text-extraction proxy, the quote was still checked against the extracted article text, and the citation names the original publisher. Nothing here is quoted from a search snippet.

---

## S01 · Game Design Deep Dive: Finding the beat in *Crypt of the NecroDancer*
**Ryan Clark (Brace Yourself Games) · Game Developer (ex-Gamasutra) · 2014-09-16.**
<https://www.gamedeveloper.com/audio/game-design-deep-dive-finding-the-beat-in-i-crypt-of-the-necrodancer-i-> · **verified-read**
- Prototyped ±100 ms leeway at 120 BPM (20 % of a 500 ms beat) because that is "what rhythm games traditionally do".
- Found accuracy collapses under stress; widened the window until "it felt best at 100 percent" (half a beat either side).
- Uses a leaky-integrator auto-calibration that bends the beat toward the player's perceived beat, capped at ½ beat.
- Player and enemies both act on the beat because split timing "doesn't feel like the whole game world is visually synchronized".
- Explicitly concludes he was "unwise to emulate rhythm games" on accuracy.

> "I tried increasing this leeway value and was surprised to discover that it felt best at 100 percent!"

**Applicability.** (a) Our ±65/±130 ms windows are already generous; the lesson is *auto-calibration*, which we ship as the 10 s wizard. (b) Put all world motion on the beat, not between beats, so the room itself teaches tempo. (c) Justify a per-phase window scale only if playtests show stress-driven misses.

---

## S02 · How to make a rhythm game for people who have no rhythm
**Ana Diaz · Polygon · 2023-02-11.**
<https://www.polygon.com/gaming/23594230/hi-fi-rush-interview-rhythm-game-development/> · **verified-read**
- Tango made everything land on the beat regardless of input; on-beat hits pay a bonus instead of off-beat hits failing.
- Ships "a little visualizer that very clearly shows the beat"; the world carries cues (steam, finger snaps, sway).
- Cut a mid-battle character-swap rhythm because "no one could get it … with the chaos of battle".
- Partner call reduced to one timing-free button.
- Framed as accessibility ("people who have difficulty … can probably play to the end").
- Reader comment (not developer): the attack *queue* is on the beat but contact lands after it, which reads as input lag; that player plays better with sound off, watching the beat bar.

> "The first thing that we did was make a system where no matter what you did, everything would sync up so it would land on the beat."

**Applicability.** (a) Grade the *input*, animate the *effect* — never let the visual contact frame be the timing reference. (b) Cut, don't teach, any secondary rhythm verb. (c) A visible beat bar is a first-class feature, not a crutch.

---

## S03 · "Please redesign your UI for beat timing"
**Steam community thread · Metal: Hellsinger · 2023-12-09.**
<https://steamcommunity.com/app/1061910/discussions/0/4027970229989779667/> · **verified-read** (user-generated; single case)
- Beat marker is a narrow black chevron; the miss marker is a *larger* black chevron that overlaps it.
- After one miss the wrong indicator becomes the more legible one, producing chains of misses.
- Other posters defend the UI and advise disabling it; two ask for size/position/brightness configurability.

> "The visual indicator for a missed beat is a larger black chevron, more or less overlapping the actual timer."

**Applicability.** (a) The miss cue must be smaller and spatially separate from the beat cue. (b) Beat-widget size/position/brightness belongs in Options.

---

## S04 · Hands on with Patapon on PSP
**Tracy Erickson · Pocket Gamer · 2008-01-02.**
<https://www.pocketgamer.com/patapon/hands-on-with-patapon-on-psp/> · **verified-read**
- Four-button drum language; commands are four-beat patterns.
- The metronome is the screen border: a thin white frame pulses on the beat.
- Missing a beat or resting a measure resets the combo; combo 10 triggers "fever mode".
- Percussive music is the second channel.

> "A thin white border encompassing the screen pulses to the beat, giving you a visual indication of when to press buttons."

**Applicability.** (a) A peripheral frame pulse is a legitimate secondary beat channel. (b) Combo-as-visible-state (fever) is a reward we can borrow for `COMBO ×8`.

---

## S05 · Overcooked: How Design Creates Teamwork
**Abhishek Iyer · SUPERJUMP · 2022-11-17.**
<https://www.superjumpmagazine.com/overcooked-how-design-creates-teamwork/> · **verified-read**
- Orders stack at the top of the screen; each ticket *is* the recipe, in ingredient icons.
- Every cooking task and customer order has a visible timer, so prioritisation is comparison, not memory.
- One interact button performs every stage of a dish.
- Level geometry (a counter between stations) forces cooperation rather than role-locking.
- Negative case: unwashed plates are the one system without a communicated timer, and players handle them worst.

> "As pending orders pile up on top of the screen, these same visual cues keep players focused on the next ingredient and task at hand."

**Applicability.** (a) Ticketing works because tickets carry the recipe; our washer chips must carry the requirement glyph. (b) Give *every* timed system a visible clock, including turbulence. (c) Layout is a difficulty dial — our four-corner loop is that dial.

---

## S06 · Deliberately diegetic: Dead Space's lead interface designer chronicles the UI's evolution at GDC
**Dave Tach · Polygon · 2013-03-31** (reporting Dino Ignacio, Visceral Games, GDC 2013).
<https://www.polygon.com/2013/3/31/4166250/dead-space-user-interface-gdc-2013/> · **verified-read**
- Diegetic "by design *and* implementation": RIG elements are geometry, cast light, emit particles; not overlays.
- Non-diegetic information was moved behind the character.
- Colour language: blue/white = interactive, red = locked, amber = ambient.
- The Dead Space 3 workbench was "unusable" — staff preferred the debug menu; it was replaced by a conventional full-screen UI.
- Ignacio's closing position: usability outranks diegetic purity.

> "At the end of the day, none of that is important if your users really can't interact with your game."

**Applicability.** (a) Diegetic for object state, screen-space for global state. (b) Adopt a three-colour interaction language (ours: cyan/orange/green). (c) Treat "the player can't read it" as a veto over any in-world UI idea.

---

## S07 · Full list
**Game Accessibility Guidelines · n.d. (living document).**
<https://gameaccessibilityguidelines.com/full-list/> · **verified-read**
- Vision/Basic: "Ensure no essential information is conveyed by a fixed colour alone"; high contrast between text/UI and background.
- Vision/Intermediate: "Avoid placing essential temporary information outside the player's eye-line"; option to turn off/hide background movement.
- Cognitive/Basic: interactive tutorials; progress text prompts at own pace; start without navigating multiple levels of menus; easily readable default font size.
- Cognitive/Intermediate: no essential information by text alone; indicate/allow reminder of controls and objectives; contextual in-game help.
- Advanced: replay all narrative and instructions; avoid sudden unexpected movement or events.

> "Avoid placing essential temporary information outside the player's eye-line"

**Applicability.** This single page generates most of our M6 acceptance criteria; §8 of the main doc maps each clause to an obligation.

---

## S08 · Understanding SC 1.4.3: Contrast (Minimum)
**W3C WAI · WCAG 2.1 Understanding document · updated 2026-10-04.**
<https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html> · **verified-read**
- Text ≥ 4.5:1; large text (≥ 18 pt, or 14 pt bold ≈ 24 px / 18.5 px) ≥ 3:1.
- Non-text UI components fall under 1.4.11 at 3:1.
- Contrast is luminance-based so hue is irrelevant to legibility.
- Includes an advisory against red-on-black for protanopia.
- 4.5:1 corresponds to ~20/40 acuity; 7:1 to ~20/80.

> "The visual presentation of text and images of text has a contrast ratio of at least 4.5:1"

**Applicability.** (a) `metal_1` on `space_deep` = 3.90:1 → our hint fails. (b) `metal_0` borders = 2.34:1 → fail the 3:1 non-text rule. (c) Red-on-black advisory is directly relevant to `red_1`/`red_2` on `#0B0C10`.

---

## S09 · Understanding SC 2.3.1: Three Flashes or Below Threshold
**W3C WAI · WCAG 2.1 Understanding document · n.d.**
<https://www.w3.org/WAI/WCAG21/Understanding/three-flashes-or-below-threshold.html> · **verified-read**
- No more than three flashes in any one-second period, or below the general/red flash thresholds.
- A general flash is a ≥ 10 % relative-luminance change pair; red flashes are treated separately.
- Combined flashing area must stay ≤ ~25 % of a 10° visual field.
- Blinking faster than 3/s is treated as flashing.

> "Web pages do not contain anything that flashes more than three times in any one second period"

**Applicability.** 142 BPM = 2.37 Hz, legal in rate; the risk is *area* and *saturation*, so no full-screen magenta/red flashes and keep large flashes ≤ 2 per second.

---

## S10 · A quick guide to readable game text
**Karen Stevens (EA Sports) via GamesIndustry.biz · 2020-08-05** (GDC Summer talk).
<https://www.gamesindustry.biz/a-quick-guide-to-readable-game-text> · **verified-read**
- Minimum text size 28 px tall at 1080p, derived from user research; TV caption guidance is 80 px.
- Offer text resizing, but never ship a tiny default.
- Contrast 4.5:1.
- Sans-serif for readability; an alternative "fancy" font should be toggleable.
- "One of the biggest issues we have for accessibility in the games industry at this time" is legible fonts.

> "If no one can read your text, it may as well as not exist."

**Applicability.** (a) 28 px @1080p ⇒ ≈ 19 px @720p; our 9–11 px labels are 33–41 % of that. (b) A three-step text-size setting is cheap and sourced.

---

## S11 · Diseñar la interfaz (localisation string growth)
**Microsoft · MSDN Library (Visual Studio 2005 docs, Spanish) · n.d.**
<https://learn.microsoft.com/es-es/previous-versions/cc450452(v=vs.71)> · **verified-read**
- Average translated-string growth by English source length: 1–4 chars +100 %, 5–10 +80 %, 11–20 +60 %, 21–30 +40 %, 31–50 +20 %, >50 +10 %.
- Reserve space for growth or translators must redesign the UI.
- Avoid abbreviations (they may not exist in other languages) and avoid baking text into bitmaps.

> "La longitud de las cadenas de texto varía de un idioma a otro."

**Applicability.** (a) Short labels are the *most* expensive to translate — never size a button to its current string. (b) Our Spanish-first copy means the English stub must be checked against the same zones, not the reverse.

---

## S12 · Onboarding techniques
**Roblox Creator Docs · last updated 2026-11-24.**
<https://create.roblox.com/docs/en-us/production/game-design/onboarding-techniques> · **verified-read**
- Text pop-ups "can be easily overlooked"; visual elements in the world are harder to miss.
- Contextual ("just in time") tutorials raise retention, speed onboarding and reduce first-session cognitive load.
- Timed-hint heuristic: if most players act within 10 s, highlight at 11 s — and only the first time.
- Hints should be sufficient once; what players skip, they skip entirely.

> "Players generally don't like to read instructions and skip through text prompts to get to gameplay."

**Applicability.** (a) Our 11 s idle hint is directly sourced. (b) Prompt copy must be a label at the object, not a paragraph in a corner.

---

## S13 · Vlambeer / *Nuclear Throne* feel numbers
**Tom Armitage (infovore.org), quoting Rock Paper Shotgun's 2013-10-21 interview with Jan Willem Nijman.**
<https://infovore.org/tag/vlambeer> · **verified-read**
- One pistol shot: shell at 2–4 px/frame, bullet at 16 px/frame, 30 fps, 320×240.
- Camera kicked 6 px opposite the aim; "add 4 to the screenshake", which degenerates quickly.
- Weapon kick 2 px, snapping back.
- Enemy knockback 3 px/frame; hit animation starts with one white frame then two hit frames.
- The game freezes 10–20 ms on every hit.

> "The game also freezes for about 10-20 milliseconds whenever you hit something."

**Applicability.** (a) These are the reference magnitudes for §7 — but authored at 1:1, so at ×4 they must be quantised to 4 px. (b) A one-frame white flash plus a short freeze is enough; we do not need full-screen shake.

---

## S14 · Pixel Art Filtering
**Gabriel Sassone · 2021-04-12.**
<https://jorenjoestar.github.io/post/pixel_art_filtering/> · **verified-read**
- Non-integer scale/translation makes some texels fill a pixel and others straddle two → shimmer.
- Integer-only camera steps and integer scale work only without zoom or rotation.
- Nearest is correct inside texels and wrong at edges; bilinear alone blurs. Practical fixes need a custom UV filter.
- Documents six shader approaches (CSantos, Cole Cecil, Klems, IQ, BGolus, "fat pixel") with code.

> "One of the most annoying problem we are seeing … is the pixel 'shimmering' happening when scaling or moving a pixel art image with non-integer values."

**Applicability.** (a) Lock camera to integer steps and scale ×4 exactly. (b) If we ever add zoom (e.g. Final Load), budget for a filter — otherwise forbid zoom.

---

## S15 · Pixel Art (engine documentation)
**Excalibur.js docs · n.d.**
<https://github.com/excaliburjs/excalibur/blob/main/site/docs/04-graphics/06.0-pixel-art.mdx> · **verified-read**
- The naive nearest-neighbour + no-AA approach ships in many games but has artefacts.
- Names them: "shimmering artifacts (inconsistent line widths) and jaggies when rotating objects".
- Suggests rendering at a higher internal `pixelRatio` (2–3) when the logical resolution is very low (< 500 px).

> "shimmering artifacts (inconsistent line widths) and jaggies when rotating objects"

**Applicability.** Confirms the two artefacts we must test for in M7 screenshot comparison: inconsistent line width and rotation jaggies. (The `pixelRatio` advice does not apply — we want fixed 320×180.)

---

## S16 · Remaking Celeste's Lighting
**Noel Berry · 2017-09-25.**
<https://noelfb.com/posts/celeste_lighting/> · **verified-read**
- Celeste's internal resolution is 320×180 — identical to ours.
- First implementation built a mesh per light with raycasts; abandoned for "edge cases, bugs, and floating point precision problems".
- Replaced with a cutout mask: draw the spotlight, then have wall quads erase shadow.
- Optimised by packing one light per colour channel, then all lights into one 2048² atlas (256 lights).
- Lights became "some of the fastest code in the game".

> "Our screen resolution is tiny (320x180)"

**Applicability.** (a) We are at a proven resolution; per-screen-pixel effects are cheap. (b) For a static single room, bake light into the room tile instead of running lights at all.

---

## S17 · 关于《死亡细胞》美术工作流的初步探索 (Dead Cells art workflow)
**IWSE / INDIENOVA, republished on GameRes · 2021-04-19.**
<https://www.gameres.com/883032.html> · **verified-read** (Chinese; figures described)
- *Dead Cells* renders 3D in Maya to pixel-style colour + normal sequences (AA off, filter `closest`).
- Colour sprites keep only flat base colour, no painted shading; the normal map supplies all lighting.
- Unity import: Filter = Pixel, Compression = None, `smart` slicing, bottom pivot, `_NormalMap` as a secondary texture, 2D light with "Use Normal Map".
- Palette-swap variants are done in shader by sampling a palette texture rather than repainting.
- Cites the original Gamasutra "Art Design Deep Dive: Using a 3D pipeline for 2D animation in Dead Cells".

> 颜色精灵上的只保留了固有色，并没有添加阴影 ("the colour sprite keeps only the flat colour, with no shading added") — translation mine.

**Applicability.** (a) Do not paint light into sprites; keep ramps flat and light the scene. (b) Palette-swap is our cheapest variant mechanism (already used for the 9 item variants). (c) The normal-map half of this pipeline is out of scope for us — see main doc §4.

---

## S18 · Half-Life 2's Invisible Tutorial
**Mark Brown · Game Maker's Toolkit (video) · 2016.**
<https://www.youtube.com/watch?v=MMggqenxuZc> · **transcript-read** (zh-TW subtitle track via Amara; passage translated)
- Contrasts a hypothetical *Dead Space*-style tutorial (blood message, pop-up, audio log, NPC call, second pop-up) with *Half-Life 2*'s two silent beats.
- The Ravenholm sawblade sequence: bisected zombie visible → exit blocked by blades → gravity gun pulls a blade → a zombie walks in → the player discovers the interaction.
- Argues Valve teaches mechanics, weapons, enemies and puzzles without pop-ups, by staging and sight-lines.

> "《戰慄時空2》成功解釋一樣的東西，只用了兩個橋段，而且一個字都沒講" ("Half-Life 2 explained the same thing in two beats, without a single word") — translation mine.

**Applicability.** (a) Stage the verbs we *can* stage (carry, insert, deliver). (b) Do not attempt to stage the beat window — nothing in the fiction can demonstrate tempo; state it explicitly.

---

## S19 · Ink Tank
**Splatoon Wiki (Fandom) · n.d.**
<https://splatoon.fandom.com/wiki/Ink_Tank> · **skimmed**
- The tank is worn on the back and holds ink; it is the game's ammo display.
- A white bar shows current ink with a red triangle marking the sub-weapon threshold.
- A red light flashes when empty and when full (special ready).
- Swimming shows an icon for refill rate.

> "It has a white-colored bar for the current amount of Ink inside, with a red bar marked with a triangle that indicates how much Ink is enough to use their Sub Weapon."

**Applicability.** (a) A diegetic gauge can carry a *threshold*, not just a quantity — our washer ring should mark the turbulence point the same way. (b) Community complaints (search-only, not verified) that the tank is unreadable when the back is occluded support keeping a redundant screen-space chip.

---

## S20 · Game UI Database 2.0
**Edd Coates · Game UI Database / 80.lv launch article · 2024-08-06.**
<https://gameuidatabase.com/about.php> · <https://80.lv/articles/game-ui-database-2-0-has-been-released> · **search-only**
- Free reference library of game interfaces, filterable by screen type, controls, textures, patterns, HUD elements and colour.
- 2.0 added 55,500 screenshots/videos across 1,000+ games.
- Explicitly invites screenshots of each settings category (Display, Audio, Accessibility).

> "over 55,500 new game screenshots and videos, all filterable by screen types, controls, textures, patterns, HUD elements, color, and more"

**Applicability.** Use for the M6 layout mockup review (title, options, pause, end) — but note I could not browse individual entries, so no layout claim in the main doc rests on this source.

---

## S21 · "Feedback: Visual Metronome"
**Steam community thread · 2025-06-14.**
<https://steamcommunity.com/app/3404260/discussions/0/555745354809663411> · **search-only**
- Player cannot tell whether they are in sync; asks for an optional visual metronome "like the metronome bar you could have in Crypt of the Necrodancer".
- Describes a felt latency between stick input and feedback.

> (no quote used — page body not retrieved; summary only)

**Applicability.** Corroborates S03/S04 that a *toggleable* beat visual is a recurring player request. Not used as the sole support for any recommendation.

---

## Claims I could not verify

1. **NecroDancer's "100 percent" in milliseconds.** Clark states the percentage, not the resulting window. My reading (½ beat each way) is an interpretation; the 20 % → ±100 ms figure *is* stated.
2. **Hi-Fi Rush's actual judgement windows.** Never published; no number is claimed in the main doc.
3. **Metal: Hellsinger's chevron dimensions/colours.** The thread describes them qualitatively; I quote only the description.
4. **Overcooked's max simultaneous tickets, and PlateUp!/Cook Serve Delicious ticket limits.** No fetchable primary source found; no numbers used.
5. **Splatoon ink-tank occlusion.** Only forum posts (Chinese-language, search-only) assert it; treated as anecdote, not evidence.
6. **"28 px at 1080p → 19 px at 720p".** The 28 px figure is sourced; the 720p conversion is my arithmetic and is labelled as inference.
7. **Dead Cells' original Gamasutra article** redirected/failed to fetch; the workflow claims come from the verified Chinese reproduction (S17), which cites it.
8. **Metroid Prime, Return of the Obra Dinn, Celeste assist mode, The Last of Us Part II, Hades, Forza accessibility menus, PlateUp!, Moving Out, BPM: Bullets Per Minute, Rhythm Heaven.** Requested in the brief but *not* successfully fetched as primary sources in this pass. Nothing in the main document depends on them; they are listed here so the gap is explicit rather than hidden.
9. **Game UI Database individual entries.** Database browsable only in principle; no screenshot was described from it, so no layout claim cites it.
10. **Xbox / Microsoft accessibility feature tags.** Read only in localised (IT/FR/ZH) renderings during search; the reduce-motion requirement is therefore cited via S07 instead of a half-read page.

<!-- END -->

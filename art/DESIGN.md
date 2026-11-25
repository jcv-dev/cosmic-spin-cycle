# Cosmic Spin Cycle — art bible

*Cosmic Retro-Futurism · top-down 2.5D · 1 art px = 4 world px · 320×180 art canvas.*

This file is the source of truth for pixels.  The palette is frozen in `art/palette.json`
(30 colours); the asset contract is frozen in `art/contract.py`; the build is
`python3 tools/make_art.py`.

---

## 1. Direction

A laundromat at the edge of the void: chunky industrial machines, cold steel, and then one
hot cosmic item swirling through it.  The room is dark and quiet (`#0B0C10`-led) so that
**items, the player and rhythm feedback are the brightest things on screen**.  Funny,
friendly, zero violence: machines are "black-hole" appliances, not weapons.

Readability order, always: **silhouette → colour → pattern → detail.**  Every item must
be identifiable as a black shape at 1× before its colour is read.  Colour is never the
only signal: the washer holograms and the items carry a shape glyph as well
(red = triangle, blue = circle, yellow = square; solid = disc, ringed = ring,
spotted = dots, wild = star).

## 2. Pixel rules (enforced by `tools/lint_sprites.py`)

1. **Palette only.** Every opaque pixel is one of the 30 colours; any other colour raises
   `PaletteError` at build time.  No colour is added without a DECISIONS entry.
2. **Binary alpha.** 0 or 255, never in between.  No soft shadows, no glows, no AA.
3. **Light from the top-left.** Every part gets a lit top/left edge and a shaded
   bottom/right edge; sphere shading is banded, never gradient.
4. **3 tones + 1 highlight** from the 5-step ramps.  Slot `_0` is reserved for the
   selective outline, slot `_2` is the body fill.
5. **Selective outline.** 1 px, the object's own darkest ramp colour (`*_0`) or a
   `space_*` shadow; accents hue-shift to `space_deep` / `funk_plum` / `yel_0`.
6. **Dither only as a 2×2 checker** and only on large surfaces (the UI panel interior).
7. **One pixel scale.** No mixed resolution; no rotated or scaled baked art (rotation is
   only 0/90° for belt tiles, done in engine).
8. **Budget:** ≤ 5 ramp colours + 2 accents per frame (warn at 8, fail above 8).

### Ramps

| family | 0 | 1 | 2 (body) | 3 | 4 (highlight) |
|---|---|---|---|---|---|
| metal | #4A5278 | #6B7599 | #9AA4C4 | #CDD3E8 | #F4F6FC |
| red | #3D0A1C | #7A1230 | #C41E3A | #F0526B | #FF9AA8 |
| blue | #0E1A4D | #1E3A9A | #3B6DF0 | #7FA6FF | #C3D8FF |
| yel | #5C3A00 | #B07A00 | #FFC21A | #FFE066 | #FFF5B8 |
| space | #0B0C10 void | #14172A deep | #1F2340 mid | #2E3460 haze | (haze) |

Accents and meaning: `funk_cyan` Pip / rhythm / aim / neon · `funk_magenta` PERFECT ·
`clean_green` clean & done · `hazard_orange` turbulent & broken · `funk_teal` secondary
cyan shadow · `funk_plum` magenta shadow.

## 3. Item grammar

All nine item variants share **one authored silhouette**; only ramp swaps and pattern
masks differ, so a player learns "the round one", "the sock", "the crescent" once.

| item | silhouette | solid | ringed | spotted |
|---|---|---|---|---|
| rocky 16 | sphere r=6, two craters on solid | craters with lit far rim | equatorial band | planet03 continents |
| sock 16 | cuff + leg + turned foot (hand-built spans) | star stitch | two stripes | four dots |
| moon 16 | crescent, opening up-right | clean | band across the body | crater dots |
| gas 24 | sphere r=10, belts | belts + calm spot | bold tilted ring | planet07 storms |
| core 32 | filled spiral disc + golden nucleus | — (4-frame rotation) | — | — |

Pattern masks stay **inside the silhouette**; the linter checks that all colour variants of
a pattern share an identical mask, that frames of one animation do not change silhouette,
and that no variant paints outside the union mask.

## 4. Machines and environment

* **Washer 48×48** — chunky front-loader: plinth, two feet, hazard band, recessed control
  deck with a hologram mount, an oversized porthole with a drum and water, door hinge and
  handle.  Pivot `(24, 46)` (bottom-centre).  Six states differ by drum, lamp and hazard
  colour, not by silhouette, so it never pops.
* **Belt 16×16** — two-tone slats with a 2 px gap and a lit rail top/bottom, scrolling
  4 px per frame; designed to survive a 90° rotation (rails end up on the other edges).
* **Chute 32×32** — pneumatic iris: four blades close/open over a cyan throat; `accept`
  flashes clean green.
* **Shredder 32×32** — funnel with a hazard band, a rotating six-tooth intake and cyan
  suction dashes.
* **Floor 16×16** — a bordered steel plate from the Roguelike pack, mapped onto the space
  ramp so the deck stays dark; three variants (clean, scuffed, hatch corner).
* **Room 320×180** — **top-down**: the deck fills the canvas, the wall trim is only the
  8 px perimeter, and all detail is read from above (deck plates, rivets, two drains, two
  vents, three hatches, cable runs, a dashed spin decal around the chute).  No horizon, no
  belts, washers or chute baked in; contrast is kept under the items on purpose.

## 5. Pip

24×24, pivot feet `(12, 22)`, side strip drawn facing right (engine mirrors).
Big helmet + visor, compact torso with a chest badge, stubby legs, oversized gravity
gloves in `funk_cyan`.  All 30 frames come from one parametric body plan
(`art/src/pip.py`): poses only change offsets, arm length, glove direction and leg
length, so proportions never drift.  Head bob is always downward, which keeps the helmet
off the cell edge.

| animation | frames | fps | loop |
|---|---|---|---|
| idle_down/side/up | 2 | 4 | yes |
| run_down/side/up | 4 | 10 | yes |
| throw_down/side/up | 2 | 18 | no |
| strike_down/side/up | 2 | 18 | no |

## 6. FX and UI

FX are geometry, not sprites-with-outlines: rings and rays on a hard pixel grid, one
accent per effect, one-shot playback.  The UI is a cool metal frame with exactly one
accent per meaning; `ui_panel` is a 9-slice with uniform border strips (corner 8) so
`NinePatchRect` can tile it, and its interior 8×8 checker tiles cleanly.  The stability
fill is neutral so the engine can tint it green→orange by threshold.  The logo is the
built-in 5×7 bitmap font at ×2 plus a drum mark.

## 7. Timings

idle 3–4 fps · run 10 · throw/strike 18 · belt scroll 8 · washing 8 · turbulent 14 ·
explosion 12 · sparkle 8 · done 6 · broken 4 · chute opening/accept 12.
The pulse ring, washer progress ring, vibration meter and magnet trail are procedural in
Godot — they are deliberately **not** in the sheets.

## 8. Determinism

`make_art.py` builds every sheet from committed sources and authored code: same input →
byte-identical PNGs.  Hashes are recorded in `art/preview/hashes.txt`;
`python3 tools/make_art.py --check` re-derives the pixels and compares, and
`python3 tools/lint_sprites.py` fails if the recorded hashes are stale.

## 9. Deviations from AGENTS §B5 (deliberate, documented)

* **`char_pip` has 12 animations / 12 rows**, not "9 rows": §B5 asks for 4 animations × 3
  directions, which is 12, and §B6 names the animations explicitly.  The sheet is
  24×24 with 12 rows padded to 4 columns; unused cells are transparent padding, not
  frames (the linter only validates declared frames).
* **`item_grime` ships as three single-frame sheets** `item_grime_16/24/32`, because a
  sheet has one uniform frame size.
* **`ui_bar_stability` is split** into `ui_bar_stability` (96×10) and
  `ui_bar_stability_fill` (8×6) per DECISIONS D012.
* **Pattern variants share a union silhouette** rather than an identical one: a ringed gas
  giant's ring may sit outside the unringed sphere, but every colour variant of the same
  pattern is mask-identical.  The linter implements exactly this rule (see its docstring).
* **`env_room` is top-down**, per the supervisor review: floor fills the canvas and the
  wall is an 8 px perimeter trim.
* **Pip / sock / core are `authored-fallback`** — see `docs/PROVENANCE.md`.

## 10. Known weak spots

* `item_core`'s spiral reads as a pinwheel at 1×; the 4-frame rotation carries it more
  than the single frame does.
* The sock's cuff is slightly heavy against a 16 px leg; at 1× it still reads as a sock.
* `env_room`'s dashed spin decal is subtle to the point of being optional at 1×.
* FX bursts are centred rings rather than directional impacts; they will be layered with
  the engine's hit-stop/flash.

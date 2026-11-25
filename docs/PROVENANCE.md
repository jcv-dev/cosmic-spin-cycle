# Provenance — Cosmic Spin Cycle art

Every shipped sprite is traceable to a pinned CC0 source, or is explicitly marked as
authored when no source fitted.  Packs are downloaded by `tools/fetch_sources.py`,
verified against the archive SHA-256, and their licence text is committed next to them in
`art/sources/<pack>/LICENSE.txt`.

## Pinned source packs

| id | title | author | page | licence | archive SHA-256 | retrieved |
|---|---|---|---|---|---|---|
| `kenney-planets` | Planets | Kenney (Kenney Vleugels) | https://kenney.nl/assets/planets | CC0-1.0 | `289386e1cbc4a9a727654795b857c1f3f3447b170c7ba1ceeb9b007d1b84f683` | 2026-11-24 |
| `kenney-roguelike` | Roguelike/RPG pack | Kenney (Kenney Vleugels), with Lynn Evers | https://kenney.nl/assets/roguelike-rpg-pack | CC0-1.0 | `8e7d2378f8f794245645f6d7dc7aeeb246791410a7e512293c594b46a5a9524b` | 2026-11-24 |
| `kenney-industrial` | Pixel Platformer: Industrial Expansion | Kenney (Kenney Vleugels) | https://kenney.nl/assets/pixel-platformer-industrial-expansion | CC0-1.0 | `c46e8fee3528434d1680d50a2373c77eb33b1d5db5c7b000d495edecc854fd3e` | 2026-11-24 |

All three packs are **CC0-1.0**: no attribution is required, it is given anyway.
The archives themselves are not committed (`art/sources/.gitignore`); the extracted
tiles/planets that the build actually reads *are* committed, so a fresh clone rebuilds
without network access.

## Per-asset provenance

| id | class | source | transform | png sha-256 (16) |
|---|---|---|---|---|
| `item_rocky` | adapted | kenney-planets `planets/planet03.png` | Content-cropped 64x64 thumbnail, box-downscaled to 16x16, dark structure thresholded at p58, morphologically cleaned to 3 blobs, used as the continent mask inside an authored sphere; luminance mapped onto the crimson/blue/solar ramps; sel-out outline. | `60ecb73b0d52a591` |
| `item_moon` | composed | kenney-planets `planets/planet04.png` | Crater field taken from the source at p34 and used only on lit pixels; crescent silhouette authored as outer disc minus bite disc; 4-connected spur removed. | `5334d33c30d08e64` |
| `item_gas` | adapted | kenney-planets `planets/planet07.png` | Storm mask at p54 cleaned to 2 blobs, modulated into an authored banded sphere; belts authored; ramps swapped for the 3 colours. | `a70a930987d76977` |
| `item_grime_16` | composed | kenney-planets `planet04.png` + kenney-roguelike `tile_0702.png` | Splat body from the planet crater mask (p68, 2 components), drip authored, crack network from the roguelike cracked plate (p22) clipped inside the splat. | `23231a0f144f9a46` |
| `item_grime_24` | composed | same as item_grime_16 | Same transform sampled at 24x24. | `b9e22fd19c209d30` |
| `item_grime_32` | composed | same as item_grime_16 | Same transform sampled at 32x32. | `a5feab92c4a2f900` |
| `env_floor` | adapted | kenney-roguelike `tiles/tile_0692.png` | 16x16 bordered steel plate, luminance mapped onto the space ramp slots 1..3 so the deck stays dark; bevel reinforced with space_mid/space_haze; variants add one authored blemish. | `a7057e657044ab5b` |
| `mach_washer` | composed | kenney-industrial `tiles/tile_0085.png` | Console plate cropped 12x8 at 1:1, luminance mapped to metal slots (0,1,1,2,3); chassis, porthole, water, hazard band and states authored around it. | `78b38e5d03f23ecf` |
| `item_sock` | authored-fallback | kenney-roguelike sheet (inspected) | No 16x16 sock, cloth or laundry silhouette exists in the pack: the closest items are bags, pots and scrolls whose silhouettes read as the wrong object, and B2 makes silhouette identity. Authored instead; pattern masks (ring/stripe/spots) are authored geometry. | `22f89ae862ed2edc` |
| `item_core` | authored-fallback | kenney-roguelike gems/orbs (inspected) | The galaxy core is a 32x32 multicolour spiral with a 4-frame rotation; roguelike gems are 16px single-hue facets and downscaling one to 32px only produced a diamond blob. Authored instead. | `00024d371b24b532` |
| `char_pip` | authored-fallback | kenney pixel-platformer packs (attempted) | The pinned Pixel Platformer: Industrial Expansion ships tiles only - no character sprites. The base Pixel Platformer pack holds the characters, but the download failed twice (curl exit 56 / truncated archive) and its 18x18 hooded humans do not read as a cosmic janitor at 24x24. Authored instead, parametric across all 30 frames. | `a81eacc15788c709` |
| `fx_clean_sparkle` | authored | - | Hand-placed 8x8 four-point sparkle, 4 frames. | `01e7b01c3d622e72` |
| `fx_burst_perfect` | authored | - | Expanding magenta ring + 8 rays, 16x16, 4 frames. | `aefb36ec9d2466f6` |
| `fx_burst_good` | authored | - | Expanding cyan ring + 6 rays, 12x12, 3 frames. | `48bb846d46cac5b4` |
| `fx_miss_puff` | authored | - | Metal smoke puffs, 12x12, 3 frames. | `9b7027b6ab5f9360` |
| `fx_explosion` | authored | - | Rings + debris then smoke, 32x32, 6 frames. | `288458c42a75047d` |
| `fx_bubbles` | authored | - | Three bobbing bubbles, 8x8, 3 frames. | `e22d3bfca80b7be2` |
| `ui_holo_icons` | authored | - | Colour glyphs + pattern glyphs, 12x12, 7 single-frame anims. | `3c399df2f99c40ae` |
| `ui_panel` | authored | - | 24x24 9-slice, corner 8, uniform border strips. | `80093242168ba47b` |
| `ui_bar_stability` | authored | - | 96x10 frame with 8px segment ticks. | `1a136db1529bbb6f` |
| `ui_bar_stability_fill` | authored | - | 8x6 neutral fill tile, tinted in engine. | `1f46037c91c7ac86` |
| `ui_icons` | authored | - | Clock, shield and combo glyphs, 8x8. | `f98f4ac5323dbdc4` |
| `ui_reticle` | authored | - | Corner brackets + centre dot, 16x16. | `9a00defe9f7bb0dc` |
| `ui_logo` | authored | - | 5x7 bitmap wordmark (built-in font) + drum mark, 160x48. | `9a81a70a03585db0` |

Class meanings are defined in `art/MANIFEST.md`.  Full output hashes for every sheet and
the determinism check live in `art/preview/hashes.txt`; `python3 tools/make_art.py
--check` re-derives the pixels and compares.

## Attempts and refusals (recorded, not hidden)

* **Base Pixel Platformer (characters)** — `https://kenney.nl/assets/pixel-platformer`.
  The pinned *Industrial Expansion* contains tiles only.  The base pack's download was
  attempted twice on 2026-11-24 and both times the transfer was cut (curl exit 56,
  truncated zip, `unzip` reported no central directory).  Its 18x18 hooded humans were
  also judged wrong for a 24x24 cosmic janitor.  `char_pip` is therefore authored; the
  parametric builder is documented in `art/DESIGN.md`.
* **Roguelike cloth/bag props for `item_sock`** — the pack's 16x16 bags, pots and scrolls
  were inspected at 8x; none read as a sock, and silhouette identity wins (AGENTS B2).
* **Roguelike gems/orbs for `item_core`** — 16px single-hue facets; downscaled/upscaled to
  32px they produced an unreadable diamond.  Authored instead.
* **Kenney Industrial floor tiles for `env_floor`** — `tile_0056`/`tile_0057` tiled as a
  repeating column of hooks at 16px (interior crop included), so the floor uses the
  Roguelike bordered plate `tile_0692` instead, which tiles cleanly.
* Rejected planet renders (recorded in `SOURCES.json`): `planet00` (low contrast) and
  `planet05` (hue too warm for the crimson ramp).

## Licence texts

Committed verbatim from the archives:

* `art/sources/kenney-planets/LICENSE.txt` — Planets (1.0), Kenney, CC0.
* `art/sources/kenney-roguelike/LICENSE.txt` — Roguelike/RPG pack, Kenney + Lynn Evers, CC0.
* `art/sources/kenney-industrial/LICENSE.txt` — Pixel Platformer: Industrial Expansion (1.0), Kenney, CC0.

## Tools and dates

All pixels were produced by the in-repo deterministic pipeline (`tools/pxlib.py`,
`tools/make_art.py`, builders in `art/src/`) on 2026-11-24.  No AI-generated images were
used, and Open Design was not available in this environment (see `art/TOOLS.md`), so
`art/od/` boards were not produced; review happens through `art/preview/`.

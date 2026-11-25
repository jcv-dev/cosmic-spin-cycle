# Sprite manifest — Tier A

Generated/maintained by the art session (`a1-art`). One row per shipped id;
`tools/lint_sprites.py` fails if a shipped sheet is missing here or listed but absent.

Status: `planned` → `built` → `reviewed`. Provenance is the adaptation class:

* `adapted` — a CC0 source is the actual geometry/texture, palette-remapped.
* `composed` — CC0 source(s) provide part of the shape/pattern; the rest is authored.
* `authored-fallback` — a CC0 attempt was made and judged worse than the authored
  version; the reason is recorded in `docs/PROVENANCE.md` and in the report.
* `authored` — pure `pxlib` work with no suitable CC0 source (UI glyphs, FX).

Details, URLs, hashes and transforms: `docs/PROVENANCE.md`.

| id | size | anims | frames | status | provenance | source |
|---|---|---|---|---|---|---|
| `item_rocky` | 16x16 | 9 | 18 | built | adapted | kenney-planets planet03 continents |
| `item_sock` | 16x16 | 9 | 18 | built | authored-fallback | see PROVENANCE: no CC0 sock at 16px |
| `item_moon` | 16x16 | 9 | 9 | built | composed | kenney-planets planet04 craters + authored crescent |
| `item_gas` | 24x24 | 9 | 18 | built | adapted | kenney-planets planet07 storm |
| `item_core` | 32x32 | 1 | 4 | built | authored-fallback | see PROVENANCE: no CC0 galaxy core |
| `item_grime_16` | 16x16 | 1 | 1 | built | composed | kenney-planets planet04 mask + roguelike 0702 cracks |
| `item_grime_24` | 24x24 | 1 | 1 | built | composed | kenney-planets planet04 mask + roguelike 0702 cracks |
| `item_grime_32` | 32x32 | 1 | 1 | built | composed | kenney-planets planet04 mask + roguelike 0702 cracks |
| `char_pip` | 24x24 | 12 | 30 | built | authored-fallback | see PROVENANCE: platformer pack has no usable character |
| `env_belt` | 16x16 | 1 | 4 | built | composed | authored slats/rails, industrial language |
| `env_belt_cap` | 16x16 | 1 | 1 | built | composed | authored portal + bracket |
| `env_shredder` | 32x32 | 1 | 3 | built | composed | authored funnel + hazard band |
| `env_chute` | 32x32 | 4 | 9 | built | composed | authored iris hatch |
| `env_floor` | 16x16 | 3 | 3 | built | adapted | kenney-roguelike tile_0692 plate |
| `env_room` | 320x180 | 1 | 1 | built | composed | authored top-down deck + trim + drains |
| `fx_clean_sparkle` | 8x8 | 1 | 4 | built | authored | hand-authored pxlib geometry |
| `fx_burst_perfect` | 16x16 | 1 | 4 | built | authored | hand-authored pxlib geometry |
| `fx_burst_good` | 12x12 | 1 | 3 | built | authored | hand-authored pxlib geometry |
| `fx_miss_puff` | 12x12 | 1 | 3 | built | authored | hand-authored pxlib geometry |
| `fx_explosion` | 32x32 | 1 | 6 | built | authored | hand-authored pxlib geometry |
| `fx_bubbles` | 8x8 | 1 | 3 | built | authored | hand-authored pxlib geometry |
| `ui_holo_icons` | 12x12 | 7 | 7 | built | authored | hand-authored UI geometry |
| `ui_panel` | 24x24 | 1 | 1 | built | authored | hand-authored UI geometry |
| `ui_bar_stability` | 96x10 | 1 | 1 | built | authored | hand-authored UI geometry |
| `ui_bar_stability_fill` | 8x6 | 1 | 1 | built | authored | hand-authored UI geometry |
| `ui_icons` | 8x8 | 3 | 3 | built | authored | hand-authored UI geometry |
| `ui_reticle` | 16x16 | 1 | 1 | built | authored | hand-authored UI geometry |
| `ui_logo` | 160x48 | 1 | 1 | built | authored | hand-authored UI geometry |
| `mach_washer` | 48x48 | 6 | 17 | built | composed | kenney-industrial console tile + authored chassis |

## Totals

- 29 sheets, 176 frames.

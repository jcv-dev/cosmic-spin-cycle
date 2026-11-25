# Sprite manifest — Tier A

Generated/maintained by the art session (`a1-art`). One row per shipped id;
`tools/lint_sprites.py` fails if a shipped sheet is missing here or listed but absent.

Status: `planned` → `built` → `reviewed`. Provenance is the adaptation class:
`adapted` (CC0 source geometry/texture, palette-remapped), `composed` (assembled
from CC0 parts + authored primitives) or `procedural` (fully authored in `pxlib`;
no suitable CC0 source existed). Details and hashes: `docs/PROVENANCE.md`.

| id | size | anims | frames | status | provenance | source |
|---|---|---|---|---|---|---|
| `item_rocky` | 16x16 | 9 | 18 | built | adapted | kenney-planets / planet03 continents |
| `item_sock` | 16x16 | 9 | 18 | built | procedural | authored in pxlib |
| `item_moon` | 16x16 | 9 | 9 | built | adapted | kenney-planets / planet04 craters + crescent |
| `item_gas` | 24x24 | 9 | 18 | built | adapted | kenney-planets / planet07 storm |
| `item_core` | 32x32 | 1 | 4 | built | procedural | authored in pxlib (spiral disc) |
| `item_grime_16` | 16x16 | 1 | 1 | built | procedural | authored in pxlib |
| `item_grime_24` | 24x24 | 1 | 1 | built | procedural | authored in pxlib |
| `item_grime_32` | 32x32 | 1 | 1 | built | procedural | authored in pxlib |
| `char_pip` | 24x24 | 12 | 30 | planned | TBD | TBD |
| `env_belt` | 16x16 | 1 | 4 | planned | TBD | TBD |
| `env_belt_cap` | 16x16 | 1 | 1 | planned | TBD | TBD |
| `env_shredder` | 32x32 | 1 | 3 | planned | TBD | TBD |
| `env_chute` | 32x32 | 4 | 9 | planned | TBD | TBD |
| `env_floor` | 16x16 | 3 | 3 | planned | TBD | TBD |
| `env_room` | 320x180 | 1 | 1 | planned | TBD | TBD |
| `fx_clean_sparkle` | 8x8 | 1 | 4 | planned | TBD | TBD |
| `fx_burst_perfect` | 16x16 | 1 | 4 | planned | TBD | TBD |
| `fx_burst_good` | 12x12 | 1 | 3 | planned | TBD | TBD |
| `fx_miss_puff` | 12x12 | 1 | 3 | planned | TBD | TBD |
| `fx_explosion` | 32x32 | 1 | 6 | planned | TBD | TBD |
| `fx_bubbles` | 8x8 | 1 | 3 | planned | TBD | TBD |
| `ui_holo_icons` | 12x12 | 7 | 7 | planned | TBD | TBD |
| `ui_panel` | 24x24 | 1 | 1 | planned | TBD | TBD |
| `ui_bar_stability` | 96x10 | 1 | 1 | planned | TBD | TBD |
| `ui_bar_stability_fill` | 8x6 | 1 | 1 | planned | TBD | TBD |
| `ui_icons` | 8x8 | 3 | 3 | planned | TBD | TBD |
| `ui_reticle` | 16x16 | 1 | 1 | planned | TBD | TBD |
| `ui_logo` | 160x48 | 1 | 1 | planned | TBD | TBD |
| `mach_washer` | 48x48 | 6 | 17 | built | composed | kenney-industrial console + authored chassis |

## Totals

- 29 sheets, 176 frames.

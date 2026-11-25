# Handoff — Track A ↔ Track B

## What is frozen

- `assets/sprites/<id>.png` + `<id>.json` per `AGENTS.md` §B6, with the deviations in
  `docs/DECISIONS.md` (D012).
- `art/palette.json`: 30 colours, no additions without a DECISIONS entry.
- `data/layout.json`: art-pixel coordinates, ×4 world scale, top-left origin.
- Runtime loader: `scripts/visual/ArtCatalog.gd` (`sprite_path`, `has_sprite`, `texture`).
  Nodes must render a flat placeholder when the texture is absent.

## Scene anchors (art px → world px)

| Anchor | Art px | World px |
|---|---|---|
| Player spawn | (160, 128) | (640, 512) |
| Chute centre | (160, 90) | (640, 360) |
| Washer NW mouth | (60, 80) | (240, 320) |
| Washer NE mouth | (260, 80) | (1040, 320) |
| Washer SW mouth | (60, 144) | (240, 576) |
| Washer SE mouth | (260, 144) | (1040, 576) |
| Belt north | (84,10,152,16) | (336,40,608,64) |
| Belt south | (84,154,152,16) | (336,616,608,64) |
| Belt west | (10,60,16,80) | (40,240,64,320) |

## Import rules (Godot)

- Texture filter **Nearest**, mipmaps **off**, compress **Lossless**, no alpha-border fix.
- AnimatedSprite2D scale ×4, `centered = false`, `offset = -pivot`.
- Sprite nodes never rotate with physics bodies (no shimmer).
- `ui_panel`: NinePatchRect, patch margin 8.

## Open items for Track B

1. Source and adapt Tier A sprites (A1). Keep the JSON contract exact; run
   `tools/lint_sprites.py` and `tools/preview.py`.
2. Source four BPM-matched music loops (105/118/130/142) with known first-beat offset,
   seamless bar-aligned loops, plus SFX set and an OFL pixel font with Spanish glyphs (A2).
3. Every asset must be traceable in `docs/PROVENANCE.md` (URL, author, license, date,
   transformations applied).
4. Do not touch `assets/sprites/` from Track A code except `ArtCatalog`.

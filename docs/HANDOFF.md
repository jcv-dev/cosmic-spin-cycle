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

## M0–M3 integration state (2026-11-24)

**Art is live, not just promised.**

- All 29 Tier A sheets live in `assets/sprites/` with their `.json`; the runtime loader is
  `scripts/visual/SpriteSheet.gd` (builds `SpriteFrames`/`AtlasTexture`, scale ×4, pivot
  from JSON, Nearest). `ItemVisual` and `Player` use it; flat palette silhouettes remain as
  a fallback if a sheet is missing.
- `env_room` is top-down; RoomBuilder uses it directly and skips the repeating tile overlay.
  `env_floor` is only used when no room art exists (`RoomBuilder._build_floor`).
- `assets/sprites/*.import` are committed lossless/no-mipmaps/no-alpha-fix (D025).
  `art/sources/` has a `.gdignore`; raw scans are not imported.
- Washer/chute/holo/FX sheets are ready for M4 but not yet instantiated by MainLevel.

**Audio is live.**

- `assets/audio/music.json` → `MainLevel._setup_music()` assigns the phase-1 stem before
  `BeatConductor.start`; phase changes assign the next stem and `set_bpm` restarts it at the
  new downbeat (`MainLevel._apply_phase`).
- `Settings._ensure_buses()` creates Music/SFX/UI; the conductor player is on Music, the
  sock squelch and belt warning on SFX.
- `assets/audio/sfx/` names are stable; M4 can use `washer_done`, `washer_explode`,
  `delivery_chime`, `turbulent_alarm` without renaming.

**Level anchors** (unchanged, from `data/layout.json`): washer mouths at (240,320),
(1040,320), (240,576), (1040,576); chute centre (640,360); player spawn (640,512).

**Rebuild everything**

```bash
python3 tools/make_art.py && python3 tools/lint_sprites.py && python3 tools/preview.py
python3 tools/verify_audio.py
./tools/dev.sh check
```

**Do not** edit `assets/sprites/*.json` frame sizes/rows or `data/layout.json` without a
DECISIONS entry: both are consumed by code and tests.

## For M4 (washers)

- `mach_washer` states map to FSM states: `idle`, `load_flash`, `washing`, `turbulent`,
  `done`, `broken` (48×48, pivot 24,46). Use `SpriteSheet.configure` and keep the node
  unrotated.
- `ui_holo_icons` animations are `red`, `blue`, `yellow`, `solid`, `ringed`, `spotted`,
  `wild` (12×12); `Compatibility.item_fits` is already pure-tested.
- `env_chute` animations `closed/opening/open/accept`; `fx_explosion` 6 frames at 12 fps.
- Washer Area mouths should use `Config.CollisionLayer.WASHER` (64) with mask ITEMS; the
  player's `struck` signal already fires for group `washers` within 96 px.

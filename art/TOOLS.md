# Art toolchain — what ran, what did not

## Open Design (AGENTS §B7)

**Status: Plan B.**  The Open Design MCP/daemon was not available in this environment and
no image provider was configured, so no style-board, viewer or critique projects were
generated.  Nothing in `art/od/` is claimed.  Review instead happens through the generated
previews:

* `art/preview/contact_sheet.png` — every sheet, labelled, at a readable zoom.
* `art/preview/sheets/<id>_xN.png` — one file per sheet with all animation strips.
* `art/preview/readability_1x.png` — items at true 1× and at ×8 on `#0B0C10`.
* `art/preview/in_scene.png` — the 320×180 composite from `data/layout.json` at ×4
  (1280×720), i.e. the "does this look like a laundromat" check.
* `art/preview/hud.png` — the HUD strip assembled.

If Open Design is installed later, the art bible (`art/DESIGN.md`) is already written as a
design-system document and can be registered without rewriting it.

## In-repo tools (authoritative for pixels)

| tool | role |
|---|---|
| `tools/fetch_sources.py` | downloads the three CC0 packs, verifies archive SHA-256, extracts the exact tiles/planets, writes `art/sources/SOURCES.json` and `LICENSE.txt`. `--verify` checks every pin without network. |
| `tools/pxlib.py` | palette-strict canvas (raises on off-palette colours), primitives, `shade_sphere`, `outline` (sel-out), dither, pattern masks, mask morphology (`clean_mask`), source adaptation (`source_to_canvas`, `source_pattern_mask`), 5×7 font, `Sheet`/`Registry`. |
| `tools/make_art.py` | imports every builder in `art/src/`, validates ids against `art/contract.py`, writes PNG+JSON, records hashes. `--check` compares committed pixels against a fresh build; `--only <family>` builds one family. |
| `tools/lint_sprites.py` | AGENTS §B9 rules 1–9, contract validation, manifest coverage, hash freshness. Non-zero on failure. |
| `tools/preview.py` | builds the previews listed above, including the layout composite. |
| `tools/pixelize.py` | reference-only quantiser: image → palette at a target size (never writes to `assets/sprites/`). |

## Build commands

```bash
python3 tools/fetch_sources.py --verify      # pins + licence evidence
python3 tools/make_art.py                    # all 29 sheets -> assets/sprites/
python3 tools/make_art.py --check            # reproducibility gate
python3 tools/lint_sprites.py                # AGENTS B9 gate
python3 tools/preview.py                     # contact sheet + scene composite
export XDG_DATA_HOME="$PWD/.work/xdg/data" XDG_CACHE_HOME="$PWD/.work/xdg/cache" \
       XDG_CONFIG_HOME="$PWD/.work/xdg/config"
godot --headless --path . --import           # .import sidecars
```

## Notes

* The archives are *not* committed; the extracted sources are, so the build works offline.
* Every builder is deterministic: no wall-clock, no unseeded randomness.  The only PRNG is
  `pxlib._Lcg`, seeded per use.
* `art/src/` holds one builder per family: `items.py`, `washer.py`, `env.py`, `pip.py`,
  `fx.py`, `ui.py`.
* Godot import settings used for the sidecars: lossless compression, mipmaps off, filter
  inherited from the project default (Nearest).

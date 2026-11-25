# Asset provenance

Every third-party asset must have a row here **before** it is committed. Fields:
file(s), author/publisher, source URL, license, date retrieved, transformations applied.
Licenses must allow redistribution and commercial use in a game; prefer **CC0 / public
domain**. CC-BY is acceptable only with attribution displayed in-game and in this file.
No unlicensed rips, no "found on Google Images", no AI-generated images copied as final
pixels.

## Policy

- Sprites: adapted to the frozen contract (palette-quantised, frame-packed, recoloured
  variants). Keep the original download hashes/URLs and a copy of the license text in
  `art/sources/`.
- Music: loops trimmed to whole bars, tempo-matched to 105/118/130/142 BPM, documented
  with BPM, key, loop length and first-beat offset.
- Fonts: OFL or equivalent; must contain á é í ó ú ñ ü ¿ ¡.
- Code dependencies: GUT (MIT) vendored; record the tag.

## Registry

| Asset | Author / source | License | Retrieved | Transformations |
|---|---|---|---|---|
| *(pending A1/A2)* | | | | |

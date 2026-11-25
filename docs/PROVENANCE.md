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
| `art/sources/audio/music/holizna_bassic_{01_eat,02_sleep,03_breath,04_make_money}.ogg` | HoliznaCC0 — *BASSIC* (2020-01-10), Free Music Archive — https://freemusicarchive.org/music/holiznacc0/bassic | CC0 1.0 Universal | 2026-11-24 | Kept verbatim as the build source; SHA-256 pinned in `art/sources/audio/SOURCES.json`, CC0 legal text vendored at `art/sources/audio/LICENSE-CC0-1.0.txt` |
| `assets/audio/music/phase1_105.ogg` | HoliznaCC0 — "Breath" (*BASSIC*) | CC0 1.0 Universal | 2026-11-24 | 16-bar excerpt from bar 1 (downbeat-aligned), atempo 0.98954 (106.00 → 105.00 BPM), exact 64-beat trim, 5 ms seam fades, decoded peak −2.14 dBFS, Vorbis q6 44.1 kHz stereo |
| `assets/audio/music/phase2_118.ogg` | HoliznaCC0 — "Sleep" (*BASSIC*) | CC0 1.0 Universal | 2026-11-24 | 16 bars from bar 3, atempo 0.98333 (120.00 → 118.00 BPM), 5 ms seam fades, decoded peak −2.18 dBFS |
| `assets/audio/music/phase3_130.ogg` | HoliznaCC0 — "Eat" (*BASSIC*) | CC0 1.0 Universal | 2026-11-24 | 16 bars from bar 16, atempo 1.08333 (120.00 → 130.00 BPM), 5 ms seam fades, decoded peak −2.05 dBFS |
| `assets/audio/music/phase4_142.ogg` | HoliznaCC0 — "Make Money" (*BASSIC*) | CC0 1.0 Universal | 2026-11-24 | 16 bars from bar 70, atempo 1.09797 (129.34 → 142.00 BPM), 5 ms seam fades, decoded peak −2.05 dBFS |
| `assets/audio/sfx/{squelch_grab,washer_done,washer_explode,ui_click,throw_whoosh,delivery_chime,turbulent_alarm}.ogg` | rubberduck — *100 CC0 SFX* — https://opengameart.org/content/100-cc0-sfx | CC0 1.0 Universal | 2026-11-24 | One-shots layered from `plop_02`/`splash_02`, `bell_02`, `explosion`+`slam_01`, `switch_01`, `noise_02`+`other_06`, `gong_01`, `bell_02` (×4, odd hits pitched ×1.26); decay-shaped, mono 44.1 kHz Vorbis q5, peak −1.3…−1.6 dBFS |
| `assets/audio/sfx/belt_hum.ogg` | bretbernhoft — *General Household Sound Effects*, `computerfans01.wav` — https://opengameart.org/content/general-household-sound-effects | CC0 1.0 Universal | 2026-11-24 | 4.0 s excerpt, equal-power 120 ms crossfade loop, mono Vorbis q5 |
| `assets/audio/sfx/washer_drum.ogg` | bretbernhoft — *General Household Sound Effects*, `washer01.wav` | CC0 1.0 Universal | 2026-11-24 | 4.5 s excerpt of a real washing machine, equal-power 250 ms crossfade loop |
| `assets/fonts/Silkscreen-Regular.ttf`, `assets/fonts/Silkscreen-Bold.ttf` | Jason Kottke / The Silkscreen Project Authors — https://fonts.google.com/specimen/Silkscreen | SIL Open Font License 1.1 (`assets/fonts/OFL.txt`) | 2026-11-24 | Unmodified; cmap verified for `á é í ó ú ñ ü ¿ ¡` plus uppercase; SHA-256 in `assets/fonts/font.json` |

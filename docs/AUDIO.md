# Audio — music, SFX, fonts

Owner: session `a2-audio`. Everything here is sourced from the internet under
**CC0 1.0** (music, SFX) or the **SIL Open Font License 1.1** (font), adapted
deterministically, and verified by `tools/verify_audio.py`.

Rebuild everything from scratch:

```bash
python3 tools/fetch_audio.py fetch    # verify/download sources, write SOURCES.json
python3 tools/fetch_audio.py music    # 4 stems + assets/audio/music.json
python3 tools/fetch_audio.py sfx      # 9 SFX  + assets/audio/sfx/sfx.json
python3 tools/verify_audio.py         # exit 0 + table
```

## 1. Phase stems

Four 16-bar loops, one per phase, from four tracks of the same album so the OST
keeps one production voice (same bass, drums and mix), while each phase gets its
own groove.

| stem | file | BPM | bars | beats | duration | source track | source BPM (track / window) | atempo |
|---|---|---|---|---|---|---|---|---|
| phase1 | `assets/audio/music/phase1_105.ogg` | 105 | 16 | 4/4 | 36.571069 s | Breath | 106.00 / 106.11 | 0.98954 |
| phase2 | `assets/audio/music/phase2_118.ogg` | 118 | 16 | 4/4 | 32.542373 s | Sleep | 120.00 / 120.00 | 0.98333 |
| phase3 | `assets/audio/music/phase3_130.ogg` | 130 | 16 | 4/4 | 29.538462 s | Eat | 120.00 / 120.00 | 1.08333 |
| phase4 | `assets/audio/music/phase4_142.ogg` | 142 | 16 | 4/4 | 27.042254 s | Make Money | 129.34 / 129.33 | 1.09797 |

`atempo = target / window BPM`, so the stretch ratio follows the tempo measured
*inside the chosen 16 bars*, not the whole-track average.

### Source measurements (`tools/bpm_analyze.py FILE`)

| track | BPM | coarse confidence | grid coherence | fit residual (median / p95) | 16 bars chosen | window BPM |
|---|---|---|---|---|---|---|
| Breath | 106.00 | 0.348 | 0.67 | 2.6 / 8.6 ms | 1–16 | 106.11 |
| Sleep | 120.00 | 0.580 | 0.73 | 3.7 / 16.2 ms | 3–18 | 120.00 |
| Eat | 120.00 | 0.102 | 0.69 | 3.6 / 11.0 ms | 16–31 | 120.00 |
| Make Money | 129.34 | 0.182 | 0.65 | 38.1 / 92.4 ms (whole track) | 70–85 | 129.33 (2.9 / 12.9 ms in window) |

The coarse `confidence` is deliberately conservative (winner versus the best
tempo ≥6 % away); `coherence` is the peak-versus-neighbour contrast of the
phase-coherent grid and is the stronger signal. *Make Money* is played looser
than the others over the whole track, which is why the section was re-measured
before stretching: inside bars 70–85 it is tight to 2.9 ms, so the loop lives on
the grid even though the track as a whole is not a click track.

Album: **HoliznaCC0 — BASSIC** (Free Music Archive, released 2020-01-10),
[album page](https://freemusicarchive.org/music/holiznacc0/bassic),
**CC0 1.0 Universal**. The four source OGGs are vendored verbatim in
`art/sources/audio/music/`; `art/sources/audio/SOURCES.json` pins their SHA-256
and the per-track page.

Stretch is between −1.7 % and +9.8 %, so there is no audible atempo artefact
(the quality bar rejects > 25 %). The source material is already funk/jazz
hip-hop; speeding up *Eat* by 8 % and *Make Money* by 10 % pushes the energy
from phase 3 to 4 without changing pitch.

### How each loop was made

1. **Measure the source** with `tools/bpm_analyze.py FILE --bars`: spectral-flux
   onsets → high-passed autocorrelation with a harmonic comb → phase-coherent
   beat grid → onset-to-grid linear fit. Beat phase, bar phase and a 16-bar
   section without dropouts come out of the same run.
2. **Cut exactly 16 bars** of 4/4 starting on a downbeat, using the fitted grid
   and then the sample-domain attack (`attack_time`) so the cut lands on the
   transient, not on the analysis frame.
3. **Re-measure the window** and cut it again to exactly 64 beats at that local
   tempo, so internal tempo drift cannot accumulate over the loop.
4. **Stretch** with one `ffmpeg -af atempo=target/measured` pass (pitch
   preserving), then force the exact sample count `64 × 60 / target × 44100`.
5. **5 ms edge fade** — in every stem the raw seam step measured between −0.8
   and −21.3 dBFS, i.e. a click; the fade removes it. Compromise: a 5 ms
   amplitude dip at the loop point (≤ 0.9 % of one beat). Documented, inaudible
   against the beat, and the alternative (a longer crossfade) would shorten the
   loop and break the 64-beat grid.
6. **DC** removed when |mean| > 0.001 (never triggered above −0.0003 here).
7. **Encode** Vorbis q6 at 44.1 kHz stereo, then correct the PCM gain so the
   *decoded* peak lands at −2 dBFS (Vorbis overshoots the PCM peak by up to
   3 dB on dense masters; normalising before encoding would ship files that
   decode above budget).
8. **Pin the Ogg serial** and recompute every page CRC (`normalise_ogg_serial`):
   ffmpeg otherwise derives a random serial per encode, so two builds of the
   same samples differed in 24 header bytes. With that fixed, `music`/`sfx`
   rebuilds are byte-identical, which is what the manifest SHA-256 values rely
   on (verified by rebuilding twice and comparing hashes).

### Measurements (from `tools/verify_audio.py` and `tools/bpm_analyze.py`)

| stem | duration drift vs 64 beats | decoded peak | RMS | beat-grid residual (p95) | downbeat attack |
|---|---|---|---|---|---|
| phase1 | +0.00 ms | −2.14 dBFS | −12.8 dBFS | 11.5 ms | +24.5 dB @ 4 ms |
| phase2 | +0.01 ms | −2.18 dBFS | −13.4 dBFS | 2.7 ms | +20.6 dB @ 47 ms |
| phase3 | −0.00 ms | −2.05 dBFS | −11.8 dBFS | 8.2 ms | +20.2 dB @ 56 ms |
| phase4 | −0.01 ms | −2.05 dBFS | −12.6 dBFS | 7.7 ms | +17.6 dB @ 18 ms |

`--known-bpm` verifies the processed tempo: at the declared BPM the onsets snap
to a beat grid whose regression residual is 2.7–11.5 ms (p95), i.e. the tempo
after `atempo` is exact to better than 0.4 ms per beat. The downbeat check
measures how far energy rises in the first 60 ms of the decoded file: every stem
opens on a transient of +17 to +25 dB, so `first_beat_offset_s = 0.0` is honest.

Blind tempo estimation on a 30 s loop is *ambiguous* (a groove repeats at the
beat, half-bar, bar and 8th-note levels, and the autocorrelation happily picks
65 BPM for a 130 BPM loop). That is why the manifest records the **target**
tempo and the verifier checks that known tempo instead of re-estimating it.

### First-beat offset

All four stems have `first_beat_offset_s = 0.0` and `loop_start_s = 0.0`.
`BeatConductor.get_song_time()` subtracts `_stem_first_beat_offset`, so the
conductor needs **no** per-stem offset; it must, however, reset its musical
clock on `set_bpm()` when the phase changes (contract behaviour).

Residual alignment uncertainty is ±10 ms (one analysis frame), well inside the
±65 ms PERFECT window and inside the calibration wizard's correction.

### Phase switching

The stems are independent loops at different tempos, so a switch is a cut on a
**measure boundary**: at the phase boundary the ShiftManager asks for the new
stem, the conductor calls `set_bpm(new_bpm)` and restarts beat/measure counting
from 0. `PHASE_TRANSITION_MODE` (GDD §8.2-1) has two options:

* `HARD_CUT` (default, implemented): stop the old stream, start the new one on
  the next downbeat. The 5 ms fades make the cut click-free.
* `DRUM_BRIDGE`: needs a transition asset (a one-bar drum fill that ends on the
  new tempo). **Not shipped**: a bridge has to be tempo-matched to *both* the
  outgoing and incoming stem, so it is a 3 per-boundary set. Flagged as a gap;
  until then `HARD_CUT` is the only mode with assets behind it.

Phase durations (120/150/150/60 s) are not multiples of the loop lengths
(36.6/32.5/29.5/27.0 s), so every stem loops 2–5 times inside its phase. Because
each loop is exactly 64 beats and the conductor counts beats from the stream
restart, the measure grid stays locked across loop wraps.

### Manifest and path convention

`assets/audio/music.json` and `assets/audio/sfx/sfx.json` store **bare
filenames** (`"file": "phase1_105.ogg"`), as frozen by `docs/CONTRACTS.md`: the
beat engine prefixes `res://assets/audio/music/` (or `res://assets/audio/sfx/`
for SFX). `tools/verify_audio.py` resolves each entry against the directory the
manifest lives in, and still accepts an explicit relative path, so the check
works either way. `sha256` in both manifests is the hash of the shipped Ogg.

## 2. SFX

Mono 44.1 kHz Vorbis, peak −1.3…−1.6 dBFS (budget ≤ −1 dBFS), `sfx.json` records
duration, peak, RMS, loop flag, recipe and SHA-256.

| id | file | dur | loop | recipe | source |
|---|---|---|---|---|---|
| `squelch_grab` | `squelch_grab.ogg` | 0.34 s | no | wet plop + short splash, decay-shaped | `plop_02`, `splash_02` |
| `belt_hum` | `belt_hum.ogg` | 4.00 s | yes | steady fan hum, equal-power 120 ms loop | `computerfans01` |
| `washer_drum` | `washer_drum.ogg` | 4.50 s | yes | real washing-machine drum, 250 ms loop | `washer01` |
| `washer_done` | `washer_done.ogg` | 0.70 s | no | short bell ding | `bell_02` |
| `washer_explode` | `washer_explode.ogg` | 1.10 s | no | explosion + metal debris, delayed hit | `explosion`, `slam_01` |
| `ui_click` | `ui_click.ogg` | 0.09 s | no | switch click, 3 ms de-click | `switch_01` |
| `throw_whoosh` | `throw_whoosh.ogg` | 0.45 s | no | noise swish + flick transient | `noise_02`, `other_06` |
| `delivery_chime` | `delivery_chime.ogg` | 1.60 s | no | warm gong, long decay | `gong_01` |
| `turbulent_alarm` | `turbulent_alarm.ogg` | 1.08 s | no | two-tone alarm, 4 × 0.26 s | `bell_02` (pitch-shifted ×1.26 on odd beats) |

Sources: **100 CC0 SFX** by *rubberduck* (OpenGameArt, CC0) and **General
Household Sound Effects** by *bretbernhoft* (OpenGameArt, CC0) — the latter
gives the two loops a real domestic-machine character (a fan and an actual
washer) instead of synthesised noise.

Loop seams: `belt_hum` step 1.9× the file's own 95th-percentile sample motion,
`washer_drum` 0.62×, i.e. both continue the waveform rather than jumping. The
equally-weighted crossfade is 120 ms for the hum and 250 ms for the drum (a
shorter fade left the drum's transient audible at the seam).

## 3. Font

**Silkscreen** Regular + Bold (`assets/fonts/Silkscreen-{Regular,Bold}.ttf`),
OFL 1.1, Jason Kottke / The Silkscreen Project Authors. 228 glyphs each.
`font.json` records family, files, licence, hashes and the verified cmap
coverage; the OFL text ships as `assets/fonts/OFL.txt`.

Coverage verified with fontTools: `á é í ó ú ñ ü ¿ ¡` **and** their uppercase
forms are all present. The font is a true 8-px pixel face, so it stays crisp
under Godot's Nearest filter at ×4.

## 4. Bus / mix plan

Buses to create in `default_bus_layout.tres` (owner: lead — this file is not in
the audio session's paths, so this is a recommendation, not an edit):

```
Master ── Music ── SFX ── UI ── Loops
```

| bus | level | why |
|---|---|---|
| `Master` | 0 dB, `limiter` ceiling −1 dBFS | the mix must never clip: SFX peaks are −1.3 dBFS |
| `Music` | −4 dB | stems are normalised to −2 dBFS; −4 leaves room for SFX transients |
| `SFX` | 0 dB | one-shots at −1.3…−1.6 dBFS |
| `UI` | −6 dB | `ui_click` and `delivery_chime` are feedback, not foreground |
| `Loops` | `belt_hum` −14 dB, `washer_drum` −10 dB per instance | continuous, must sit under music |

Headroom arithmetic: music at −4 dB (peak −6) plus four washer loops (−10 dB
each per instance, incoherent so they sum by power ≈ +6 dB → −4 dB) plus one
explosion (−1.5) plus the alarm (−1.4) stays below 0 dBFS; the master limiter is
the safety net, not the working point. The SFX are mono, so panning per washer
mouth (layout.json positions) is free.

## 5. Known compromises

* 5 ms fade at both ends of every music loop (see above).
* `belt_hum` and `washer_drum` are crossfaded excerpts, not authored loops: the
  hum has a faint 4 s period; the drum keeps the real machine's cycle.
* `turbulent_alarm` is a repeated bell, not a bespoke siren.
* Blind BPM estimation is unreliable on loops shorter than ~60 s (documented
  above); source tempos were measured on full tracks, outputs verified against
  known tempos.
* FMA serves this album through its web player only, so `fetch` cannot
  re-download the music headlessly; the sources are vendored instead and the
  hashes pinned.

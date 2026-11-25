# Audio calibration protocol

Status: **implemented (M1)**. Manual Windows/Linux tap measurements remain the owner's
TODO; the automated maths, click tracks and wizard are complete and tested.

## Why

The rhythm windows are ±65 ms (PERFECT) and ±130 ms (GOOD), while OS audio latency commonly
ranges 10–150 ms and Bluetooth can exceed 200 ms. `AudioServer.get_output_latency()` reports
the driver's estimate, which is often wrong or zero. `BeatConductor` compensates with that
estimate, and the 10 s wizard measures the residual offset with a human tap-along.

## Time equation

Every beat/measure event is derived from `BeatConductor.get_song_time()`:

```
song = playback_position
     + AudioServer.get_time_since_last_mix()
     − AudioServer.get_output_latency()
     − Settings.user_calibration_offset      # seconds; positive = player hears beats late
     − stem_first_beat_offset                # leading silence in the stem
song = max(song, 0)
```

The same equation is a pure static helper,
`BeatConductor.compensated_song_time(playback, mix, output_latency, calibration, stem_offset)`,
so the unit tests exercise the production path.

Frame-to-frame monotonic policy (`BeatConductor.monotonic_time`):

* candidate ≥ previous → accept;
* candidate < previous by **≤ 5 ms** → hold the previous sample (mixer jitter);
* candidate < previous by **> 5 ms** → accept as a new audio anchor (loop wrap / stem
  restart) and re-grid the next beat one period later, keeping the global beat index
  monotonic.

Without a playing stream the conductor free-runs from accumulated `_process` delta.
`advance_clock(seconds)` is the deterministic, audio-independent stepping hook used by tests
and simulations; `get_song_time()` returns the same monotonic value in every mode.

## Wizard maths

For a tap at song time `t` and beat period `T = 60 / BPM`:

```
sample_ms = wrap_signed(t, T) × 1000        # ∈ [−T/2, +T/2)
wrap_signed(t, T) = fposmod(t + T/2, T) − T/2
```

Sign convention: **positive means the tap landed after the beat** (late). Applying a
positive offset makes `get_song_time()` smaller, so beats are emitted later and line up with
what the player actually heard.

Robust reduction (`scripts/logic/CalibrationMath.gd`, pure and unit-tested):

1. Discard the window's blunders with a median-absolute-deviation cut:
   `|x − median| > max(3 × 1.4826 × MAD, 1 ms)`.
2. Take the **median** of the survivors (even counts average the two middle samples).
3. Clamp to **±500 ms**.
4. Require at least **3 taps** before Apply is enabled.

`Wrap`, empty-set and clamp boundaries are covered in `tests/unit/test_calibration_math.gd`;
the wizard flow itself is covered in `tests/unit/test_calibration_modal.gd`.

## Wizard flow

1. Open the modal at one of the four phase tempos (105/118/130/142 BPM).
2. Three-second countdown (`3 · 2 · 1 · TAP!`).
3. Ten seconds of the generated click track, first beat at sample 0.
4. The player taps `grab_throw` (SPACE / left mouse / gamepad A) on every click. Taps are
   read in `_input()`; each one becomes one signed millisecond sample.
5. The window closes and shows tap count, median and rejected outliers.
6. **Apply** writes the median through `Settings.set_calibration_samples()` and
   `Settings.set_calibration_offset_ms()` (persisted to `user://settings.cfg` under
   `audio/calibration_offset_s`). **Reset** writes 0 ms. **Cancel** leaves the stored value
   untouched.

The modal owns its click player, and BeatLab stops the conductor click first, so the player
never hears two metronomes at once. Missing click audio is non-fatal: the wizard still runs a
silent window, and a normal playthrough free-runs the conductor without audio.

## Running BeatLab

```bash
cd /home/moravak/proyecto/.worktrees/m1-beat
export XDG_DATA_HOME="$PWD/.work/xdg/data" XDG_CACHE_HOME="$PWD/.work/xdg/cache" \
       XDG_CONFIG_HOME="$PWD/.work/xdg/config"
godot --path . res://scenes/dev/BeatLab.tscn
```

| Key | Action |
|---|---|
| `1`–`4` | select 105/118/130/142 BPM and play the matching click loop |
| `SPACE` | start/stop the click |
| `C` | open the calibration wizard at the selected tempo |
| `R` | restart the selected tempo from beat 0 |
| `F3` (`toggle_debug`) | show/hide the rhythm overlay |

The overlay shows BPM, beat/measure, signed Δt in ms, the last grade in palette colour, the
±65/±130 ms window bar with a live marker, song time, reported output latency, user
calibration and stem offset, plus a beat flash. It reads the existing `BeatConductor`
autoload; no autoload changes are needed.

## Click tracks

`tools/make_click_track.py` uses only the Python standard library (`wave` + `array`) and is
byte-deterministic: re-running it produces identical SHA-256 hashes. It writes
`assets/audio/metronome/`:

* `click_<bpm>.wav` — 8 bars of 4/4 (32 beats), accent every 4th beat, first beat at sample 0,
  44.1 kHz, 16-bit, mono, seamless loop. Beat *i* starts at `round(i × frames / 32)`, so the
  file boundary is exactly the next downbeat and the last click has decayed well before it.
* `countin_<bpm>.wav` — 4 click beats + 4 silent beats (one bar of each).
* `manifest.json` — exact/effective BPM, frames, durations, samples per beat, sizes and
  SHA-256.

Measured with `ffprobe` (sample rate 44100, 1 channel, 16 bits for every file):

| File | Frames | Duration (s) | Effective BPM | Bytes |
|---|---:|---:|---:|---:|
| `click_105.wav` | 806 400 | 18.285714 | 105.000000 | 1 612 844 |
| `click_118.wav` | 717 559 | 16.271179 | 118.000053 | 1 435 162 |
| `click_130.wav` | 651 323 | 14.769229 | 130.000015 | 1 302 690 |
| `click_142.wav` | 596 282 | 13.521134 | 141.999926 | 1 192 608 |
| `countin_105.wav` | 201 600 | 4.571429 | 105.000000 | 403 244 |
| `countin_118.wav` | 179 390 | 4.067800 | 117.999889 | 358 824 |
| `countin_130.wav` | 162 831 | 3.692313 | 129.999816 | 325 706 |
| `countin_142.wav` | 149 070 | 3.380272 | 142.000402 | 298 184 |

Sub-sample rounding is why 118/130/142 are not exactly integral BPM; the error is under
0.0004 BPM, i.e. below 0.03 ms per beat. Every loop is far under the 2.5 MB budget (largest
1.61 MB). Regenerate and verify with:

```bash
python3 tools/make_click_track.py
for f in assets/audio/metronome/click_*.wav; do
  ffprobe -v error -show_entries stream=sample_rate,channels,bits_per_sample,duration \
          -of default=nw=1 "$f"
done
```

## Acceptance

- [x] BeatConductor subtracts reported latency, user calibration and stem offset.
- [x] 4 BPMs produce the expected beat counts (32 beats: 105 BPM = 18.285714 s).
- [x] Monotonic clamp < 5 ms, larger re-anchors accepted.
- [x] Median / MAD / wrap / empty / clamp unit tests.
- [x] 480 s virtual shift: 972 beats ±1 (210 + 295 + 325 + 142).
- [x] Wizard applies through `Settings.set_calibration_offset_ms()`.
- [ ] Manual tap measurement on Windows and Linux hardware (owner TODO).
- [ ] Offset reproducibility within ±10 ms across two runs on real hardware (owner TODO).

## Measurement log

| Date | OS | Output | Reported latency | Measured offset | Tester |
|---|---|---|---|---|---|
| 2026-11-24 | Linux host probe (headless display) | PulseAudio | 52.84 ms | n/a — no human tap | automated probe |
| 2026-11-24 | Linux (headless GUT run) | dummy driver | 0.0 ms | n/a — no tap device | automated suite |
| — | Linux (owner desktop) | wired | TODO | TODO | owner |
| — | Windows (owner desktop) | wired | TODO | TODO | owner |
| — | Windows (owner laptop) | Bluetooth | TODO | TODO | owner |

The Linux probe (`godot --display-driver headless --audio-driver PulseAudio -s probe.gd`)
reported a 52.84 ms output latency at a 44.1 kHz mix rate, which is already inside the GOOD
window and shows why the residual tap wizard is still needed. Windows is the owner's TODO:
the wizard, click tracks and tests are platform-neutral, but the reported latency and residual
tap offset must be recorded on the two target machines.

## Known limitations

- The reported output latency comes from the driver; the wizard only corrects the residual.
- Keyboard taps add USB polling jitter (typically 1–8 ms); a gamepad or mouse may be steadier.
- One global offset is stored, not a per-device profile. Bluetooth and wired headphones will
  need separate runs; re-run calibration when changing output.
- The wizard measures the residual against its own click track, so it assumes the same audio
  path is used for the music stems.

# Audio calibration protocol

Status: **stub** — M1 fills this with the implemented wizard and measured numbers.

## Why

The beat windows are ±65 ms / ±130 ms, while OS audio latency commonly ranges 10–150 ms.
`BeatConductor.get_song_time()` subtracts `AudioServer.get_output_latency()` and the
user's calibration offset. Hardware output latency is imperfectly reported, so a human
tap-along offset is still required.

## Wizard (M1)

1. 10 s of metronome at the phase-1 tempo with a visible beat flash.
2. Player presses `grab_throw` on each click.
3. For every tap: `sample = nearest_beat_time − tap_time` (in ms, wrapped to ±T/2).
4. Offset = **median** of samples (robust to one or two bad taps); clamp ±500 ms.
5. Persist to `user://settings.cfg` (`audio/calibration_offset_s`), show the value.
6. Re-test button; "reset to 0" for headphones with known-good drivers.

## Measurement log

| Date | OS | Output | Reported latency | Measured offset | Tester |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

## Acceptance

- Offset reproducibility across two runs within ±10 ms.
- Perfect window still feels fair at 105 and 142 BPM.

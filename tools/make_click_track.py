#!/usr/bin/env python3
"""Generate the M1 metronome click tracks.

Outputs, under ``assets/audio/metronome/`` by default:

* ``click_<bpm>.wav`` — 8 bars of 4/4 (32 beats) for BPM 105/118/130/142, with an
  accented downbeat every 4th beat and the first beat at sample 0. The loop is
  seamless: the last click has fully decayed before the file ends, and beat
  positions are spread as ``round(i * frames / 32)`` so the file boundary is the
  33rd beat.
* ``countin_<bpm>.wav`` — one bar of clicks followed by one bar of silence.
* ``manifest.json`` — exact tempo, sample layout, hashes and durations.

Everything is synthesised with the Python standard library (``wave`` + ``array``);
numpy is deliberately not required. Re-running the script produces byte-identical
files, and it refuses to emit a track at or above the 2.5 MB budget.

Usage:
    python3 tools/make_click_track.py
    python3 tools/make_click_track.py --out /tmp/metronome --no-manifest
"""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import sys
import wave
from dataclasses import dataclass
from pathlib import Path

SAMPLE_RATE = 44_100
CHANNELS = 1
BIT_DEPTH = 16
BEATS_PER_MEASURE = 4
BARS_PER_LOOP = 8
BEATS_PER_LOOP = BEATS_PER_MEASURE * BARS_PER_LOOP
BPMS = (105, 118, 130, 142)

# Click timbre. The two partials keep the click audible on laptop speakers without
# adding noise (noise would need a seeded PRNG; sines are exactly deterministic).
DOWNBEAT_HZ = 1_560.0
BEAT_HZ = 1_040.0
DOWNBEAT_GAIN = 0.82
BEAT_GAIN = 0.50
OVERTONE_GAIN = 0.32
OVERTONE_RATIO = 2.0
DOWNBEAT_DECAY_S = 0.030
BEAT_DECAY_S = 0.020
ATTACK_S = 0.0015
CLICK_LENGTH_S = 0.090
PEAK_LIMIT = 0.98
BYTES_BUDGET = 2_500_000  # decimal MB, stricter than MiB


@dataclass(frozen=True)
class Track:
    """One rendered mono track plus the numbers written to the manifest."""

    filename: str
    bpm: int
    frames: int
    beats: int
    clicks: int

    @property
    def duration_s(self) -> float:
        return self.frames / SAMPLE_RATE

    @property
    def effective_bpm(self) -> float:
        return 60.0 * SAMPLE_RATE * self.beats / self.frames

    @property
    def samples_per_beat(self) -> float:
        return self.frames / self.beats


class ClickSynth:
    """Additive, fully deterministic click renderer."""

    def __init__(self, sample_rate: int = SAMPLE_RATE) -> None:
        self.sample_rate = sample_rate
        self.click_frames = int(round(CLICK_LENGTH_S * sample_rate))

    def click(self, downbeat: bool) -> array.array:
        """Render one click as float samples in [-1, 1]."""
        frames = self.click_frames
        frequency = DOWNBEAT_HZ if downbeat else BEAT_HZ
        gain = DOWNBEAT_GAIN if downbeat else BEAT_GAIN
        decay = DOWNBEAT_DECAY_S if downbeat else BEAT_DECAY_S
        samples = array.array("f", [0.0]) * frames
        attack_frames = max(1, int(round(ATTACK_S * self.sample_rate)))
        for index in range(frames):
            time = index / self.sample_rate
            envelope = math.exp(-time / decay)
            if index < attack_frames:
                envelope *= index / attack_frames
            phase = 2.0 * math.pi * frequency * time
            overtone = OVERTONE_GAIN * math.sin(phase * OVERTONE_RATIO)
            samples[index] = gain * envelope * (math.sin(phase) + overtone)
        return samples

    def render(self, track: Track, clicks: int) -> array.array:
        """Mix `clicks` evenly spaced clicks into a track-length float buffer."""
        buffer = array.array("f", [0.0]) * track.frames
        downbeat = self.click(True)
        beat = self.click(False)
        for beat_index in range(clicks):
            start = int(round(beat_index * track.frames / track.beats))
            source = downbeat if beat_index % BEATS_PER_MEASURE == 0 else beat
            end = min(start + len(source), track.frames)
            for offset in range(end - start):
                buffer[start + offset] += source[offset]
        return buffer


def to_pcm16(samples: array.array) -> bytes:
    """Clamp/convert float samples to little-endian signed 16-bit PCM."""
    peak = max((abs(value) for value in samples), default=0.0)
    scale = (PEAK_LIMIT / peak) if peak > PEAK_LIMIT else 1.0
    pcm = array.array("h")
    for value in samples:
        scaled = max(-1.0, min(1.0, value * scale))
        pcm.append(int(round(scaled * 32767.0)))
    return pcm.tobytes()


def write_wav(path: Path, payload: bytes, sample_rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(CHANNELS)
        handle.setsampwidth(BIT_DEPTH // 8)
        handle.setframerate(sample_rate)
        handle.writeframes(payload)


def frames_for(bpm: int, beats: int, sample_rate: int) -> int:
    return int(round(beats * sample_rate * 60.0 / bpm))


def build_tracks(sample_rate: int) -> tuple[list[Track], list[Track]]:
    loops: list[Track] = []
    countins: list[Track] = []
    for bpm in BPMS:
        loops.append(
            Track(
                filename=f"click_{bpm}.wav",
                bpm=bpm,
                frames=frames_for(bpm, BEATS_PER_LOOP, sample_rate),
                beats=BEATS_PER_LOOP,
                clicks=BEATS_PER_LOOP,
            )
        )
        # One bar of clicks + one bar of silence = 8 beats, clicks on the first 4.
        countin_beats = BEATS_PER_MEASURE * 2
        countins.append(
            Track(
                filename=f"countin_{bpm}.wav",
                bpm=bpm,
                frames=frames_for(bpm, countin_beats, sample_rate),
                beats=countin_beats,
                clicks=BEATS_PER_MEASURE,
            )
        )
    return loops, countins


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def track_record(track: Track, path: Path) -> dict:
    size = path.stat().st_size
    return {
        "file": track.filename,
        "bpm": track.bpm,
        "beats": track.beats,
        "clicks": track.clicks,
        "frames": track.frames,
        "duration_s": round(track.duration_s, 6),
        "samples_per_beat": round(track.samples_per_beat, 6),
        "effective_bpm": round(track.effective_bpm, 6),
        "bytes": size,
        "sha256": sha256(path),
    }


def build_manifest(loops: list[Track], countins: list[Track], out_dir: Path) -> dict:
    return {
        "generated_by": "tools/make_click_track.py",
        "format": "wav",
        "encoding": "pcm_s16le",
        "sample_rate": SAMPLE_RATE,
        "channels": CHANNELS,
        "bit_depth": BIT_DEPTH,
        "beats_per_measure": BEATS_PER_MEASURE,
        "bars_per_loop": BARS_PER_LOOP,
        "beats_per_loop": BEATS_PER_LOOP,
        "downbeat_every": BEATS_PER_MEASURE,
        "first_beat_sample": 0,
        "loop_seam": "beat 32 is the file boundary; the last click has decayed by then",
        "click": {
            "downbeat_hz": DOWNBEAT_HZ,
            "beat_hz": BEAT_HZ,
            "downbeat_gain": DOWNBEAT_GAIN,
            "beat_gain": BEAT_GAIN,
            "overtone_ratio": OVERTONE_RATIO,
            "overtone_gain": OVERTONE_GAIN,
            "downbeat_decay_s": DOWNBEAT_DECAY_S,
            "beat_decay_s": BEAT_DECAY_S,
            "attack_s": ATTACK_S,
        },
        "tracks": [track_record(track, out_dir / track.filename) for track in loops],
        "countin": [track_record(track, out_dir / track.filename) for track in countins],
        "countin_layout": "4 click beats (accent on 0) + 4 silent beats",
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--out",
        type=Path,
        default=repo_root / "assets" / "audio" / "metronome",
        help="output directory (default: assets/audio/metronome)",
    )
    parser.add_argument("--no-manifest", action="store_true", help="skip manifest.json")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    out_dir: Path = args.out
    synth = ClickSynth()
    loops, countins = build_tracks(SAMPLE_RATE)

    written: list[Track] = []
    for track in loops + countins:
        payload = to_pcm16(synth.render(track, track.clicks))
        write_wav(out_dir / track.filename, payload, SAMPLE_RATE)
        size = (out_dir / track.filename).stat().st_size
        if size >= BYTES_BUDGET:
            print(
                f"error: {track.filename} is {size} bytes, budget is < {BYTES_BUDGET}",
                file=sys.stderr,
            )
            return 1
        written.append(track)
        print(
            f"{track.filename:>18}  {track.duration_s:7.3f} s  "
            f"{track.samples_per_beat:9.3f} samples/beat  {size / 1e6:5.2f} MB"
        )

    if not args.no_manifest:
        manifest = build_manifest(loops, countins, out_dir)
        manifest_path = out_dir / "manifest.json"
        manifest_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        print(f"{manifest_path}  ({len(written)} tracks)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

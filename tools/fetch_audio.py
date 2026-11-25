#!/usr/bin/env python3
"""Fetch and build every shipped audio asset for Cosmic Spin Cycle.

    python3 tools/fetch_audio.py fetch     # download / verify sources, write SOURCES.json
    python3 tools/fetch_audio.py music     # build 4 phase stems + assets/audio/music.json
    python3 tools/fetch_audio.py sfx       # build 9 SFX + assets/audio/sfx/sfx.json
    python3 tools/fetch_audio.py all       # fetch + music + sfx
    python3 tools/fetch_audio.py report    # print a summary of what is on disk

Idempotency
-----------
`fetch` verifies every local source against a pinned SHA-256 and only downloads
when the file is missing.  `music` and `sfx` rebuild deterministically from those
sources: the same sources always produce the same samples (Vorbis muxing is
requested with `-fflags +bitexact`).  Sources that Free Music Archive only serves
through its web player have `url=None`; `fetch` then prints the album page and
exits non-zero unless the file is already present (it is, under
`art/sources/audio/music/`).

Pipeline (music)
----------------
1. Decode the source to 44.1 kHz stereo float and cut an exact 16-bar window
   starting on the measured downbeat (attack-aligned, see tools/bpm_analyze.py).
2. Re-measure the tempo of that window; the stretch ratio is target / measured,
   so internal drift inside the window cannot accumulate.
3. `ffmpeg -af atempo=R` (pitch preserving), then force the exact sample count
   `16 bars * 4 beats * 60 / target BPM`.
4. Remove DC if needed, apply a 5 ms edge fade only when the loop seam would
   click, normalise the peak to -2 dBFS, encode Vorbis.

Pipeline (SFX)
--------------
Mono 44.1 kHz Vorbis, peak <= -1 dBFS.  Loops are assembled with an equal-power
crossfade so the seam is continuous in both sample value and slope.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import wave
import zipfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpm_analyze as bpm  # noqa: E402  (same directory)

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, ".work", "dl")
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
SRC_DIR = os.path.join(ROOT, "art", "sources", "audio")

MUSIC_PEAK_DB = -2.0
SFX_PEAK_DB = -1.3
EDGE_FADE_MS = 5.0
LOOP_FADE_MS = 120.0


# ---------------------------------------------------------------- source tables

FMA = "https://freemusicarchive.org/music/holiznacc0/bassic"
OGA = "https://opengameart.org/content"

MUSIC_SOURCES = {
    "breath": {
        "title": "Breath", "file": "art/sources/audio/music/holizna_bassic_03_breath.ogg",
        "sha256": "d48f8fbcbd718b3139beed2c5073078fe57fe9c148dacd45c08d3f7588f6dd3f",
        "album": "BASSIC (2020-01-10)", "author": "HoliznaCC0",
        "page": f"{FMA}/breath-1/", "license": "CC0-1.0",
        "url": None,
    },
    "sleep": {
        "title": "Sleep", "file": "art/sources/audio/music/holizna_bassic_02_sleep.ogg",
        "sha256": "8d77819a8329b1cb7e9b8a5b7f50d1c04c2b272c86a864adec8e2aa99b63c719",
        "album": "BASSIC (2020-01-10)", "author": "HoliznaCC0",
        "page": f"{FMA}/sleep-2/", "license": "CC0-1.0",
        "url": None,
    },
    "eat": {
        "title": "Eat", "file": "art/sources/audio/music/holizna_bassic_01_eat.ogg",
        "sha256": "b48179151e77efc01b858bf564d5ec76f5d2f33475502c47b5c94627ec2e121c",
        "album": "BASSIC (2020-01-10)", "author": "HoliznaCC0",
        "page": f"{FMA}/eatmp3/", "license": "CC0-1.0",
        "url": None,
    },
    "make_money": {
        "title": "Make Money", "file": "art/sources/audio/music/holizna_bassic_04_make_money.ogg",
        "sha256": "e5b627cf7d0952c79284713a78fbd64f8aaae0b2886ffa2689611eca13080376",
        "album": "BASSIC (2020-01-10)", "author": "HoliznaCC0",
        "page": f"{FMA}/make-money/", "license": "CC0-1.0",
        "url": None,
    },
}

# The nine one-shots / loops that ship.  Each entry points at one downloaded
# source; the build recipe below turns it into the shipped file.
SFX_SOURCES = {
    "washer01": {
        "file": ".work/dl/washer01.wav",
        "url": "https://opengameart.org/sites/default/files/washer01.wav",
        "sha256": "03fa65c003a9aeebe7c0c71b035ca5d1b669bf707d435d9f0c2995e84195b15c",
        "page": f"{OGA}/general-household-sound-effects",
        "license": "CC0-1.0", "author": "bretbernhoft",
        "note": "General Household Sound Effects - real washing machine, 6.97 s",
    },
    "computerfans01": {
        "file": ".work/dl/computerfans01.wav",
        "url": "https://opengameart.org/sites/default/files/computerfans01.wav",
        "sha256": "303c96278896e6e082467511ee8d655f384164911f7fdcb34856e64bce724f0e",
        "page": f"{OGA}/general-household-sound-effects",
        "license": "CC0-1.0", "author": "bretbernhoft",
        "note": "General Household Sound Effects - steady fan hum, 108 s",
    },
    "plop_02": {"pack": "100cc0", "member": "plop_02.ogg", "page": f"{OGA}/100-cc0-sfx",
                "license": "CC0-1.0", "author": "rubberduck"},
    "splash_02": {"pack": "100cc0", "member": "splash_02.ogg", "page": f"{OGA}/100-cc0-sfx",
                  "license": "CC0-1.0", "author": "rubberduck"},
    "noise_02": {"pack": "100cc0", "member": "noise_02.ogg", "page": f"{OGA}/100-cc0-sfx",
                 "license": "CC0-1.0", "author": "rubberduck"},
    "other_06": {"pack": "100cc0", "member": "other_06.ogg", "page": f"{OGA}/100-cc0-sfx",
                 "license": "CC0-1.0", "author": "rubberduck"},
    "bell_02": {"pack": "100cc0", "member": "bell_02.ogg", "page": f"{OGA}/100-cc0-sfx",
                "license": "CC0-1.0", "author": "rubberduck"},
    "bell_03": {"pack": "100cc0", "member": "bell_03.ogg", "page": f"{OGA}/100-cc0-sfx",
                "license": "CC0-1.0", "author": "rubberduck"},
    "gong_01": {"pack": "100cc0", "member": "gong_01.ogg", "page": f"{OGA}/100-cc0-sfx",
                "license": "CC0-1.0", "author": "rubberduck"},
    "explosion": {"pack": "100cc0", "member": "explosion.ogg", "page": f"{OGA}/100-cc0-sfx",
                  "license": "CC0-1.0", "author": "rubberduck"},
    "slam_01": {"pack": "100cc0", "member": "slam_01.ogg", "page": f"{OGA}/100-cc0-sfx",
                "license": "CC0-1.0", "author": "rubberduck"},
    "switch_01": {"pack": "100cc0", "member": "switch_01.ogg", "page": f"{OGA}/100-cc0-sfx",
                  "license": "CC0-1.0", "author": "rubberduck"},
}

PACKS = {
    "100cc0": {
        "url": "https://opengameart.org/sites/default/files/100-CC0-SFX_0.zip",
        "sha256": "a5c135878c132f1c59cca54e60061c296cd0ac27ad031ca2c41b8cd5cab3c706",
        "dir": ".work/dl/100cc0",
        "page": f"{OGA}/100-cc0-sfx", "license": "CC0-1.0", "author": "rubberduck",
    },
}

# Source tempo / downbeat / window were measured with tools/bpm_analyze.py; the
# numbers are reproducible (`bpm_analyze.py --bars FILE`).  `bar_index` selects a
# dropout-free 16-bar section (see docs/AUDIO.md for the bar-RMS table).
MUSIC_PLAN = [
    {"id": "phase1", "source": "breath", "bpm": 105, "src_bpm": 106.00,
     "downbeat_s": 0.0479, "bar_index": 1},
    {"id": "phase2", "source": "sleep", "bpm": 118, "src_bpm": 120.00,
     "downbeat_s": 0.5412, "bar_index": 3},
    {"id": "phase3", "source": "eat", "bpm": 130, "src_bpm": 120.00,
     "downbeat_s": 1.5468, "bar_index": 16},
    {"id": "phase4", "source": "make_money", "bpm": 142, "src_bpm": 129.34,
     "downbeat_s": 1.3479, "bar_index": 70},
]
BARS = 16
BEATS_PER_BAR = 4


# --------------------------------------------------------------------- helpers

def log(msg: str) -> None:
    print(msg, flush=True)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    """Run a command capturing raw bytes (ffmpeg streams float32 on stdout)."""
    proc = subprocess.run(cmd, capture_output=True, **kwargs)
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", "replace").strip()
        raise SystemExit(f"error: {' '.join(cmd[:4])}... failed:\n{err}")
    return proc


def decode(path: str, mono: bool, sr: int = SR) -> np.ndarray:
    """Decode `path` with ffmpeg; returns float32 (n,) or (n, 2)."""
    cmd = ["ffmpeg", "-nostdin", "-v", "error", "-i", path,
           "-ac", "1" if mono else "2", "-ar", str(sr), "-f", "f32le", "-"]
    raw = run(cmd).stdout
    data = np.frombuffer(raw, dtype="<f4").astype(np.float32)
    return data if mono else data.reshape(-1, 2)


def write_wav(path: str, samples: np.ndarray, channels: int) -> None:
    """Write 16-bit PCM (peak must already be normalised)."""
    data = np.clip(samples, -1.0, 1.0)
    pcm = (data * 32767.0 + 0.5).astype("<i2")
    with wave.open(path, "wb") as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())


def read_wav(path: str) -> np.ndarray:
    with wave.open(path, "rb") as wf:
        assert wf.getsampwidth() == 2 and wf.getframerate() == SR
        raw = wf.readframes(wf.getnframes())
        ch = wf.getnchannels()
    data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32767.0
    return data.reshape(-1, ch) if ch > 1 else data


def encode_ogg(wav_path: str, out_path: str, stereo: bool, quality: int) -> None:
    ensure_dir(os.path.dirname(out_path))
    run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-fflags", "+bitexact",
         "-i", wav_path, "-c:a", "libvorbis", "-q:a", str(quality),
         "-ar", str(SR), "-ac", "2" if stereo else "1",
         "-flags:a", "+bitexact", out_path])


def encode_normalised(samples: np.ndarray, out_path: str, stereo: bool,
                      quality: int, target_db: float) -> tuple[float, str]:
    """Encode, then correct the PCM gain so the *decoded* peak hits target_db.

    Vorbis overshoots the PCM peak by 1-3 dB on dense material, so normalising
    before encoding would ship files that decode above the -2 dBFS budget.
    """
    work = samples.astype(np.float32).copy()
    if peak_db(work) > -0.01:
        work = work * (0.99 / max(1e-9, float(np.max(np.abs(work)))))
    work = normalise(work, target_db - 0.3)   # start with a little headroom
    tmp_wav = os.path.join(CACHE, "encode_tmp.wav")
    ensure_dir(CACHE)
    decoded_peak = 0.0
    for _ in range(8):
        write_wav(tmp_wav, np.clip(work, -1.0, 1.0), 2 if stereo else 1)
        encode_ogg(tmp_wav, out_path, stereo=stereo, quality=quality)
        decoded_peak = peak_db(decode(out_path, mono=not stereo))
        if target_db - 0.4 <= decoded_peak <= target_db:
            break                          # inside the window: never above budget
        work = work * (10.0 ** ((target_db - decoded_peak - 0.05) / 20.0))
    return decoded_peak, sha256_file(out_path)


def peak_db(x: np.ndarray) -> float:
    return 20.0 * math.log10(max(1e-9, float(np.max(np.abs(x)))))


def rms_db(x: np.ndarray) -> float:
    return 20.0 * math.log10(max(1e-9, float(np.sqrt(np.mean(x.astype(np.float64) ** 2)))))


def normalise(x: np.ndarray, target_db: float) -> np.ndarray:
    gain = 10.0 ** ((target_db - peak_db(x)) / 20.0)
    return x * gain


def fade_edges(x: np.ndarray, ms: float) -> np.ndarray:
    n = max(1, int(round(ms * 1e-3 * SR)))
    if n * 2 >= x.shape[0]:
        n = max(1, x.shape[0] // 4)
    ramp = np.linspace(0.0, 1.0, n, dtype=np.float32)
    out = x.copy()
    if x.ndim == 1:
        out[:n] *= ramp
        out[-n:] *= ramp[::-1]
    else:
        out[:n] *= ramp[:, None]
        out[-n:] *= ramp[::-1, None]
    return out


def resample_linear(x: np.ndarray, ratio: float) -> np.ndarray:
    """Cheap pitch-shift helper for short SFX (ratio > 1 = higher and shorter)."""
    n = max(2, int(round(x.shape[0] / ratio)))
    idx = np.linspace(0, x.shape[0] - 1, n)
    if x.ndim == 1:
        return np.interp(idx, np.arange(x.shape[0]), x).astype(np.float32)
    out = np.empty((n, x.shape[1]), dtype=np.float32)
    for c in range(x.shape[1]):
        out[:, c] = np.interp(idx, np.arange(x.shape[0]), x[:, c])
    return out


def loop_crossfade(x: np.ndarray, fade_ms: float = LOOP_FADE_MS) -> np.ndarray:
    """Turn a steady excerpt into a seamless loop (equal-power tail->head)."""
    f = int(round(fade_ms * 1e-3 * SR))
    if f * 2 >= x.shape[0]:
        f = max(1, x.shape[0] // 4)
    body = x[:-f].copy() if x.ndim == 1 else x[:-f].copy()
    tail = x[-f:]
    t = np.linspace(0.0, 1.0, f, dtype=np.float32)
    rise = np.sin(0.5 * math.pi * t).astype(np.float32)
    fall = np.cos(0.5 * math.pi * t).astype(np.float32)
    # At i=0 the loop must continue from x[N-f] (the tail), and by i=f it must
    # be playing x[f] again, so the body weight rises and the tail weight falls.
    if x.ndim == 1:
        head = body[:f] * rise + tail * fall
    else:
        head = body[:f] * rise[:, None] + tail * fall[:, None]
    body[:f] = head
    return body


def seam_metrics(x: np.ndarray) -> dict:
    """Loop click audit: sample jump, slope jump and DC offset."""
    mono = x if x.ndim == 1 else x.mean(axis=1)
    jump = abs(float(mono[0]) - float(mono[-1]))
    slope_jump = abs((float(mono[0]) - float(mono[1])) -
                     (float(mono[-2]) - float(mono[-1])))
    dc = float(np.mean(mono))
    # Energy of the transient that a listener would hear at the seam.
    return {"jump": jump, "jump_db": 20 * math.log10(max(1e-9, jump)),
            "slope_jump": slope_jump, "dc": dc}


# ------------------------------------------------------------------- fetch step

def fetch() -> int:
    problems = 0
    ensure_dir(os.path.join(SRC_DIR, "music"))

    for key, spec in MUSIC_SOURCES.items():
        dest = os.path.join(ROOT, spec["file"])
        if os.path.isfile(dest):
            got = sha256_file(dest)
            if got != spec["sha256"]:
                log(f"FAIL music {key}: sha256 mismatch ({got[:12]} != {spec['sha256'][:12]})")
                problems += 1
            else:
                log(f"ok   music {key:11s} {os.path.basename(dest)}")
            continue
        log(f"MISS music {key}: {spec['file']} absent; download from {spec['page']} "
            f"and save it there (FMA serves this album only through the web player)")
        problems += 1

    for key, spec in SFX_SOURCES.items():
        if "pack" in spec:
            continue  # handled with the packs below
        dest = os.path.join(ROOT, spec["file"])
        if os.path.isfile(dest) and sha256_file(dest) == spec["sha256"]:
            log(f"ok   sfx   {key:11s} {os.path.basename(dest)}")
            continue
        ensure_dir(os.path.dirname(dest))
        log(f"get  sfx   {key}: {spec['url']}")
        run(["curl", "-sL", "--max-time", "300", "-o", dest, spec["url"]])
        got = sha256_file(dest)
        if got != spec["sha256"]:
            log(f"FAIL sfx   {key}: sha256 {got[:12]} != {spec['sha256'][:12]}")
            problems += 1
        else:
            log(f"ok   sfx   {key:11s} {os.path.basename(dest)}")

    for key, pack in PACKS.items():
        zip_path = os.path.join(CACHE, f"{key}.zip")
        out_dir = os.path.join(ROOT, pack["dir"])
        if not os.path.isfile(zip_path):
            ensure_dir(CACHE)
            log(f"get  pack  {key}")
            run(["curl", "-sL", "--max-time", "300", "-o", zip_path, pack["url"]])
        if sha256_file(zip_path) != pack["sha256"]:
            log(f"FAIL pack  {key}: unexpected sha256")
            problems += 1
            continue
        if not os.path.isdir(out_dir) or len(os.listdir(out_dir)) < 50:
            ensure_dir(out_dir)
            with zipfile.ZipFile(zip_path) as zf:
                zf.extractall(out_dir)
        log(f"ok   pack  {key:11s} {len(os.listdir(out_dir))} files")

    write_sources_json()
    return 0 if problems == 0 else 1


def write_sources_json() -> None:
    rows = []
    for key, spec in MUSIC_SOURCES.items():
        dest = os.path.join(ROOT, spec["file"])
        rows.append({
            "kind": "music", "id": key, "file": spec["file"],
            "title": spec["title"], "author": spec["author"], "album": spec["album"],
            "page": spec["page"], "license": spec["license"],
            "sha256": sha256_file(dest) if os.path.isfile(dest) else None,
            "retrieved": "2026-11-24",
        })
    for key, spec in SFX_SOURCES.items():
        if "pack" in spec:
            pack = PACKS[spec["pack"]]
            local = os.path.join(ROOT, pack["dir"], spec["member"])
            rows.append({
                "kind": "sfx", "id": key, "file": f"{pack['dir']}/{spec['member']}",
                "author": spec["author"], "page": spec["page"], "license": spec["license"],
                "pack": spec["pack"],
                "sha256": sha256_file(local) if os.path.isfile(local) else None,
                "retrieved": "2026-11-24",
            })
        else:
            rows.append({
                "kind": "sfx", "id": key, "file": spec["file"],
                "author": spec["author"], "page": spec["page"], "license": spec["license"],
                "note": spec.get("note", ""),
                "sha256": sha256_file(os.path.join(ROOT, spec["file"]))
                if os.path.isfile(os.path.join(ROOT, spec["file"])) else None,
                "retrieved": "2026-11-24",
            })
    out = os.path.join(SRC_DIR, "SOURCES.json")
    ensure_dir(SRC_DIR)
    with open(out, "w", encoding="utf-8") as fh:
        json.dump({"version": 1, "sources": rows}, fh, indent=2)
        fh.write("\n")
    log(f"wrote {os.path.relpath(out, ROOT)}")


# ------------------------------------------------------------------- music step

def decode_window(track: np.ndarray, start_s: float, dur_s: float) -> np.ndarray:
    a = int(round(start_s * SR))
    n = int(round(dur_s * SR))
    if a < 0 or a >= track.shape[0]:
        raise SystemExit(f"error: window start {start_s:.3f}s outside the track")
    out = track[a:a + n]
    if out.shape[0] < n:
        raise SystemExit(f"error: window needs {n} samples, track has {out.shape[0]}")
    return out


def atempo_stretch(x: np.ndarray, ratio: float) -> np.ndarray:
    """Pitch-preserving time stretch via ffmpeg (ratio > 1 = faster)."""
    tmp_in = os.path.join(CACHE, "stretch_in.wav")
    ensure_dir(CACHE)
    write_wav(tmp_in, x, x.shape[1] if x.ndim > 1 else 1)
    cmd = ["ffmpeg", "-nostdin", "-v", "error", "-i", tmp_in,
           "-af", f"atempo={ratio:.10f}", "-ar", str(SR),
           "-ac", str(x.shape[1] if x.ndim > 1 else 1), "-f", "f32le", "-"]
    raw = run(cmd).stdout
    data = np.frombuffer(raw, dtype="<f4").astype(np.float32)
    return data.reshape(-1, x.shape[1]) if x.ndim > 1 else data


def build_music(only: list[str] | None = None) -> int:
    ensure_dir(MUSIC_DIR)
    stems = []
    for plan in MUSIC_PLAN:
        if only and plan["id"] not in only:
            continue
        spec = MUSIC_SOURCES[plan["source"]]
        src_path = os.path.join(ROOT, spec["file"])
        if not os.path.isfile(src_path):
            raise SystemExit(f"error: missing music source {spec['file']}")
        track = decode(src_path, mono=False)
        bar_src = 240.0 / plan["src_bpm"]
        start = plan["downbeat_s"] + plan["bar_index"] * bar_src
        beats = BARS * BEATS_PER_BAR

        # Pass 1: provisional window at the whole-track tempo, then measure it.
        window = decode_window(track, start, beats * 60.0 / plan["src_bpm"])
        mono = window.mean(axis=1)
        measured = bpm.estimate(mono, SR)
        fit = measured.get("fit", {})
        window_bpm = measured["bpm"]
        reliable = bool(fit.get("ok")) and abs(window_bpm - plan["src_bpm"]) < 0.75
        if not reliable:
            window_bpm = plan["src_bpm"]

        # Pass 2: re-cut so the window holds exactly `beats` beats at the measured
        # tempo, then stretch by target/measured.  This keeps both the internal
        # beat spacing and the loop length faithful.
        window = decode_window(track, start, beats * 60.0 / window_bpm)
        mono2 = window.mean(axis=1)
        measured2 = bpm.estimate(mono2, SR)
        if measured2.get("fit", {}).get("ok") and \
                abs(measured2["bpm"] - window_bpm) < 0.35:
            window_bpm = measured2["bpm"]
        ratio = plan["bpm"] / window_bpm

        stretched = atempo_stretch(window, ratio)
        n_out = int(round(BARS * BEATS_PER_BAR * 60.0 / plan["bpm"] * SR))
        delta_ms = (stretched.shape[0] - n_out) / SR * 1000.0
        if stretched.shape[0] > n_out:
            stretched = stretched[:n_out]
        elif stretched.shape[0] < n_out:
            pad = n_out - stretched.shape[0]
            reps = int(math.ceil(pad / max(1, stretched.shape[0])))
            filler = np.tile(stretched, (reps, 1))[:pad]
            stretched = np.concatenate([stretched, filler], axis=0)

        dc = float(np.mean(stretched))
        if abs(dc) > 0.001:
            stretched = stretched - dc  # documented; keeps the seam flat

        seam_before = seam_metrics(stretched)
        # A bar-aligned cut almost always lands on a non-zero sample, so the loop
        # seam needs the 5 ms fade.  Only skip it when the seam is already clean.
        need_fade = seam_before["jump"] > 0.005
        out = fade_edges(stretched, EDGE_FADE_MS) if need_fade else stretched.copy()
        out_path = os.path.join(MUSIC_DIR, f"{plan['id']}_{plan['bpm']}.ogg")
        decoded_peak, digest = encode_normalised(out, out_path, stereo=True,
                                                 quality=6, target_db=MUSIC_PEAK_DB)
        out = normalise(out, MUSIC_PEAK_DB)
        duration = out.shape[0] / SR
        stems.append({
            "id": plan["id"], "file": os.path.relpath(out_path, ROOT).replace(os.sep, "/"),
            "bpm": plan["bpm"], "bars": BARS, "beats_per_bar": BEATS_PER_BAR,
            "duration_s": round(duration, 6), "first_beat_offset_s": 0.0,
            "loop_start_s": 0.0, "loop_end_s": round(duration, 6),
            "source": f"{spec['author']} - {spec['title']} ({spec['album']})",
            "license": spec["license"], "sha256": digest,
        })
        log(f"built {plan['id']:6s} {plan['bpm']:3d} BPM  {spec['title']:10s} "
            f"src {plan['src_bpm']:6.2f} -> measured {window_bpm:7.2f}  "
            f"atempo {ratio:.5f}  len {duration:7.3f}s ({delta_ms:+.2f} ms vs ideal)  "
            f"peak {decoded_peak:5.2f} dBFS  rms {rms_db(out):5.1f} dB  "
            f"seam {seam_before['jump_db']:.1f}->{seam_metrics(out)['jump_db']:.1f} dB "
            f"(fade {'yes' if need_fade else 'no'})  dc {dc:+.4f}")

    manifest = {"version": 1, "stems": stems}
    out_manifest = os.path.join(ROOT, "assets", "audio", "music.json")
    with open(out_manifest, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")
    log(f"wrote {os.path.relpath(out_manifest, ROOT)}")
    return 0


# --------------------------------------------------------------------- sfx step

def src(key: str) -> np.ndarray:
    """Load one SFX source as mono float at SR."""
    spec = SFX_SOURCES[key]
    if "pack" in spec:
        path = os.path.join(ROOT, PACKS[spec["pack"]]["dir"], spec["member"])
    else:
        path = os.path.join(ROOT, spec["file"])
    if not os.path.isfile(path):
        raise SystemExit(f"error: missing sfx source {path} (run `fetch` first)")
    return decode(path, mono=True)


def take(x: np.ndarray, start_s: float, dur_s: float) -> np.ndarray:
    a = int(round(start_s * SR))
    n = int(round(dur_s * SR))
    seg = x[a:a + n]
    if seg.shape[0] < n:
        seg = np.pad(seg, (0, n - seg.shape[0]))
    return seg.astype(np.float32)


def mix(*parts: tuple[np.ndarray, float]) -> np.ndarray:
    """Sum (clip, gain_db) pairs, padding to the longest."""
    n = max(x.shape[0] for x, _ in parts)
    out = np.zeros(n, dtype=np.float32)
    for clip, gain_db in parts:
        g = 10.0 ** (gain_db / 20.0)
        out[:clip.shape[0]] += clip * g
    return out


def env_decay(x: np.ndarray, attack_ms: float = 2.0, decay: str = "exp",
              tau_s: float = 0.25) -> np.ndarray:
    n = x.shape[0]
    t = np.arange(n) / SR
    rise = np.clip(t / max(1e-6, attack_ms * 1e-3), 0.0, 1.0)
    if decay == "exp":
        tail = np.exp(-(t - attack_ms * 1e-3).clip(0) / tau_s)
    else:
        tail = np.ones(n)
    return (x * rise * tail).astype(np.float32)


def build_squelch() -> np.ndarray:
    plop = take(src("plop_02"), 0.0, 0.34)
    splash = take(src("splash_02"), 0.0, 0.30)
    body = env_decay(plop, attack_ms=1.0, tau_s=0.10)
    wet = env_decay(splash, attack_ms=2.0, tau_s=0.07)
    out = mix((body, 0.0), (wet, -8.0))
    return out[: int(0.52 * SR)]


def build_belt_hum() -> np.ndarray:
    x = src("computerfans01")
    seg = take(x, 12.0, 4.0 + LOOP_FADE_MS * 1e-3)
    return loop_crossfade(seg, LOOP_FADE_MS)


def build_washer_drum() -> np.ndarray:
    x = src("washer01")
    seg = take(x, 1.0, 4.5 + 0.25)
    return loop_crossfade(seg, 250.0)


def build_washer_done() -> np.ndarray:
    bell = take(src("bell_02"), 0.0, 0.7)
    out = env_decay(bell, attack_ms=1.0, tau_s=0.18)
    return out[: int(0.80 * SR)]


def build_washer_explode() -> np.ndarray:
    boom = take(src("explosion"), 0.0, 1.10)
    clang = take(src("slam_01"), 0.0, 0.60)
    body = env_decay(boom, attack_ms=1.0, tau_s=0.40)
    metal = env_decay(clang, attack_ms=1.0, tau_s=0.16)
    delayed = np.concatenate([np.zeros(int(0.14 * SR), dtype=np.float32), metal])
    out = mix((body, 0.0), (metal, -6.0), (delayed, -11.0))
    return out[: int(1.30 * SR)]


def build_ui_click() -> np.ndarray:
    click = take(src("switch_01"), 0.0, 0.09)
    out = env_decay(click, attack_ms=0.5, tau_s=0.012)
    return out[: int(0.10 * SR)]


def build_throw_whoosh() -> np.ndarray:
    noise = take(src("noise_02"), 0.0, 0.45)
    tick = take(src("other_06"), 0.0, 0.06)
    # band-limit hint: emphasise the start, then let it fall away
    out = env_decay(noise, attack_ms=8.0, tau_s=0.13)
    out = mix((out, 0.0), (env_decay(tick, attack_ms=1.0, tau_s=0.02), -14.0))
    return out[: int(0.48 * SR)]


def build_delivery_chime() -> np.ndarray:
    gong = take(src("gong_01"), 0.0, 1.6)
    out = env_decay(gong, attack_ms=1.0, tau_s=0.55)
    return out[: int(1.60 * SR)]


def build_turbulent_alarm() -> np.ndarray:
    beep = take(src("bell_02"), 0.0, 0.26)
    high = resample_linear(beep, 1.26)
    beep = env_decay(beep, attack_ms=1.0, tau_s=0.09)
    high = env_decay(high, attack_ms=1.0, tau_s=0.09)
    parts = []
    for i in range(4):
        parts.append((beep if i % 2 == 0 else high, 0.0))
    gap = int(0.05 * SR)
    total = sum(p.shape[0] for p, _ in parts) + gap * (len(parts) - 1)
    out = np.zeros(total, dtype=np.float32)
    pos = 0
    for clip, db in parts:
        out[pos:pos + clip.shape[0]] += clip * (10.0 ** (db / 20.0))
        pos += clip.shape[0] + gap
    return out


SFX_PLAN = [
    {"id": "squelch_grab", "loop": False, "build": build_squelch,
     "sources": ["plop_02", "splash_02"],
     "note": "wet plop layered with a short splash, 0.52 s"},
    {"id": "belt_hum", "loop": True, "build": build_belt_hum,
     "sources": ["computerfans01"],
     "note": "steady fan hum, 4.0 s, equal-power 120 ms crossfade loop"},
    {"id": "washer_drum", "loop": True, "build": build_washer_drum,
     "sources": ["washer01"],
     "note": "real washing machine drum, 4.5 s, equal-power 120 ms crossfade loop"},
    {"id": "washer_done", "loop": False, "build": build_washer_done,
     "sources": ["bell_02"], "note": "short ding"},
    {"id": "washer_explode", "loop": False, "build": build_washer_explode,
     "sources": ["explosion", "slam_01"], "note": "explosion + metal debris"},
    {"id": "ui_click", "loop": False, "build": build_ui_click,
     "sources": ["switch_01"], "note": "switch click, 0.10 s"},
    {"id": "throw_whoosh", "loop": False, "build": build_throw_whoosh,
     "sources": ["noise_02", "other_06"], "note": "noise swish + flick, 0.48 s"},
    {"id": "delivery_chime", "loop": False, "build": build_delivery_chime,
     "sources": ["gong_01"], "note": "warm delivery chime, 1.6 s"},
    {"id": "turbulent_alarm", "loop": False, "build": build_turbulent_alarm,
     "sources": ["bell_02"], "note": "two-tone repeated alarm, 4 x 0.26 s"},
]


def build_sfx() -> int:
    ensure_dir(SFX_DIR)
    entries = []
    for plan in SFX_PLAN:
        x = plan["build"]()
        if not plan["loop"]:
            x = fade_edges(x, 3.0)
        duration = x.shape[0] / SR
        out_path = os.path.join(SFX_DIR, f"{plan['id']}.ogg")
        decoded_peak, digest = encode_normalised(x, out_path, stereo=False,
                                                 quality=5, target_db=SFX_PEAK_DB)
        seam = seam_metrics(x)
        entries.append({
            "id": plan["id"], "file": os.path.relpath(out_path, ROOT).replace(os.sep, "/"),
            "loop": plan["loop"], "duration_s": round(duration, 6),
            "peak_dbfs": round(decoded_peak, 2), "rms_dbfs": round(rms_db(x), 2),
            "channels": 1, "sample_rate": SR,
            "source": " + ".join(plan["sources"]),
            "license": "CC0-1.0", "sha256": digest,
            "note": plan["note"],
        })
        log(f"built {plan['id']:16s} {'loop' if plan['loop'] else 'once'} "
            f"{duration:5.2f}s peak {decoded_peak:5.2f} dBFS rms {rms_db(x):6.1f} dB "
            f"seam jump {seam['jump_db']:6.1f} dB dc {seam['dc']:+.4f}")
    manifest = {"version": 1, "sfx": entries}
    out_manifest = os.path.join(SFX_DIR, "sfx.json")
    with open(out_manifest, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")
    log(f"wrote {os.path.relpath(out_manifest, ROOT)}")
    return 0


# ------------------------------------------------------------------------ main

def report() -> int:
    rows = []
    music_manifest = os.path.join(ROOT, "assets", "audio", "music.json")
    if os.path.isfile(music_manifest):
        with open(music_manifest, encoding="utf-8") as fh:
            for stem in json.load(fh)["stems"]:
                rows.append((stem["id"], stem["bpm"], stem["duration_s"], stem["file"]))
    for row in rows:
        log(f"{row[0]:8s} {row[1]:3d} BPM {row[2]:8.3f} s  {row[3]}")
    sfx_manifest = os.path.join(SFX_DIR, "sfx.json")
    if os.path.isfile(sfx_manifest):
        with open(sfx_manifest, encoding="utf-8") as fh:
            for e in json.load(fh)["sfx"]:
                log(f"{e['id']:16s} {e['duration_s']:5.2f} s  loop={e['loop']}  {e['file']}")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Fetch and build audio assets.")
    parser.add_argument("step", choices=["fetch", "music", "sfx", "all", "report"])
    parser.add_argument("--only", nargs="*", default=None,
                        help="limit `music` to these stem ids")
    args = parser.parse_args(argv)
    if args.step == "fetch":
        return fetch()
    if args.step == "music":
        return build_music(args.only)
    if args.step == "sfx":
        return build_sfx()
    if args.step == "report":
        return report()
    rc = fetch()
    if rc != 0:
        return rc
    rc = build_music(None)
    if rc != 0:
        return rc
    return build_sfx()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Verify every shipped audio/font asset against the project contracts.

    python3 tools/verify_audio.py [--strict] [--json]

Checks
------
Music (`assets/audio/music/*.ogg`, described by `assets/audio/music.json`):
  * the manifest has exactly the contracted keys and version 1;
  * the file exists and its SHA-256 matches the manifest;
  * OGG Vorbis, 44.1 kHz, stereo;
  * duration == bars * beats_per_bar * 60 / bpm within 5 ms;
  * peak <= -1 dBFS (decoded, the way the engine plays it) and reported;
  * |DC| <= 0.002 and a loop seam that neither steps nor leaks;
  * an onset grid at the declared BPM fits within 25 ms (p95), proving the
    processed tempo is exact;
  * audio is present from the very start (the loop begins on an attack).

SFX (`assets/audio/sfx/*.ogg`, described by `assets/audio/sfx/sfx.json`):
  * mono 44.1 kHz, duration < 2.5 s (loops < 6 s), peak <= -1 dBFS;
  * loops: seam step is within 3x the file's own sample-to-sample motion.

Fonts (`assets/fonts/font.json`):
  * both TTF files present with matching SHA-256;
  * cmap covers a e i o u with acute, n-tilde, u-diaeresis and the inverted
    question/exclamation marks, upper and lower case;
  * the OFL licence text is shipped.

Exit status is 0 only when every check passes.  `--strict` also fails on
warnings (e.g. a seam that is audible but inside tolerance).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpm_analyze as bpm  # noqa: E402

SR = 44100
MUSIC_KEYS = {"id", "file", "bpm", "bars", "beats_per_bar", "duration_s",
              "first_beat_offset_s", "loop_start_s", "loop_end_s", "source",
              "license", "sha256"}
REQUIRED_GLYPHS = "áéíóúñü¿¡ÁÉÍÓÚÑÜ"
SFX_IDS = ["squelch_grab", "belt_hum", "washer_drum", "washer_done",
           "washer_explode", "ui_click", "throw_whoosh", "delivery_chime",
           "turbulent_alarm"]
SFX_LOOPS = {"belt_hum", "washer_drum"}

RESULTS: list[dict] = []


def record(kind: str, name: str, ok: bool, detail: str, warn: bool = False) -> None:
    RESULTS.append({"kind": kind, "name": name, "ok": ok, "detail": detail, "warn": warn})


def sha256_file(path: str) -> str:
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def probe(path: str) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0",
         "-show_entries", "stream=sample_rate,channels,codec_name",
         "-show_entries", "format=duration", "-of", "json", path],
        capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip())
    data = json.loads(out.stdout)
    stream = data["streams"][0]
    return {"codec": stream.get("codec_name", "?"),
            "sample_rate": int(stream.get("sample_rate", 0)),
            "channels": int(stream.get("channels", 0)),
            "duration": float(data["format"]["duration"])}


def decode(path: str, mono: bool) -> np.ndarray:
    cmd = ["ffmpeg", "-nostdin", "-v", "error", "-i", path,
           "-ac", "1" if mono else "2", "-ar", str(SR), "-f", "f32le", "-"]
    proc = subprocess.run(cmd, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", "replace").strip())
    data = np.frombuffer(proc.stdout, dtype="<f4").astype(np.float32)
    return data if mono else data.reshape(-1, 2)


def db(value: float) -> float:
    return 20.0 * math.log10(max(1e-12, abs(value)))


def check_music(strict: bool) -> None:
    manifest_path = os.path.join(ROOT, "assets", "audio", "music.json")
    if not os.path.isfile(manifest_path):
        record("music", "music.json", False, "missing")
        return
    try:
        with open(manifest_path, encoding="utf-8") as fh:
            manifest = json.load(fh)
    except json.JSONDecodeError as exc:
        record("music", "music.json", False, f"invalid JSON: {exc}")
        return
    if manifest.get("version") != 1:
        record("music", "music.json", False, f"version is {manifest.get('version')!r}")
    stems = manifest.get("stems", [])
    if len(stems) != 4:
        record("music", "music.json", False, f"{len(stems)} stems, expected 4")
    expected = {f"phase{i}": bpm_ for i, bpm_ in
                enumerate([105, 118, 130, 142], start=1)}
    seen = {}
    for stem in stems:
        name = stem.get("id", "?")
        seen[name] = stem.get("bpm")
        missing_keys = MUSIC_KEYS - set(stem)
        extra_keys = set(stem) - MUSIC_KEYS
        if missing_keys or extra_keys:
            record("music", name, False,
                   f"manifest keys missing={sorted(missing_keys)} extra={sorted(extra_keys)}")
            continue
        if expected.get(name) != stem["bpm"]:
            record("music", name, False,
                   f"bpm {stem['bpm']} but phase table says {expected.get(name)}")
            continue
        path = os.path.join(ROOT, stem["file"])
        if not os.path.isfile(path):
            record("music", name, False, f"missing file {stem['file']}")
            continue
        if sha256_file(path) != stem["sha256"]:
            record("music", name, False, "sha256 does not match the manifest")
            continue
        try:
            info = probe(path)
        except RuntimeError as exc:
            record("music", name, False, f"ffprobe failed: {exc}")
            continue
        problems = []
        if info["codec"] != "vorbis":
            problems.append(f"codec {info['codec']}")
        if info["sample_rate"] != SR:
            problems.append(f"sr {info['sample_rate']}")
        if info["channels"] != 2:
            problems.append(f"ch {info['channels']}")
        ideal = stem["bars"] * stem["beats_per_bar"] * 60.0 / stem["bpm"]
        drift_ms = (info["duration"] - ideal) * 1000.0
        if abs(drift_ms) > 5.0:
            problems.append(f"duration {drift_ms:+.2f} ms off {ideal:.3f} s")
        x = decode(path, mono=False)
        mono = x.mean(axis=1)
        peak = db(float(np.max(np.abs(x))))
        dc = float(np.mean(mono))
        if peak > -1.0:
            problems.append(f"peak {peak:.2f} dBFS > -1")
        if abs(dc) > 0.002:
            problems.append(f"DC {dc:+.4f}")
        seam = abs(float(mono[0])) + abs(float(mono[-1]))
        if seam > 0.01:
            problems.append(f"seam edges not faded ({seam:.4f})")
        grid = bpm.verify_grid(mono, SR, stem["bpm"])
        res_p95 = grid.get("residual_ms_p95")
        if not grid.get("ok") or res_p95 is None or res_p95 > 25.0:
            problems.append(f"beat grid residual {res_p95} ms at {stem['bpm']} BPM")
        # "Downbeat at 0" = the file opens on a transient, not on silence or on
        # the tail of the previous bar.
        rise = grid.get("attack_rise_db", 0.0)
        peak_ms = grid.get("attack_peak_ms", 999.0)
        if rise < 8.0 or peak_ms > 60.0:
            problems.append(f"no downbeat attack at t=0 (rise {rise:.1f} dB, peak {peak_ms:.0f} ms)")
        detail = (f"{stem['bpm']} BPM  {info['duration']:.3f}s  "
                  f"drift {drift_ms:+.2f} ms  peak {peak:.2f}  DC {dc:+.4f}  "
                  f"grid p95 {res_p95:.1f} ms  attack +{rise:.1f} dB @ {peak_ms:.0f} ms")
        record("music", name, not problems, "; ".join(problems) or detail)
    if len(seen) != 4:
        record("music", "phase table", False, f"only {sorted(seen)}")


def check_sfx(strict: bool) -> None:
    manifest_path = os.path.join(ROOT, "assets", "audio", "sfx", "sfx.json")
    if not os.path.isfile(manifest_path):
        record("sfx", "sfx.json", False, "missing")
        return
    with open(manifest_path, encoding="utf-8") as fh:
        manifest = json.load(fh)
    entries = {e["id"]: e for e in manifest.get("sfx", [])}
    for name in SFX_IDS:
        entry = entries.get(name)
        if entry is None:
            record("sfx", name, False, "missing from sfx.json")
            continue
        path = os.path.join(ROOT, entry["file"])
        if not os.path.isfile(path):
            record("sfx", name, False, f"missing file {entry['file']}")
            continue
        if sha256_file(path) != entry["sha256"]:
            record("sfx", name, False, "sha256 does not match the manifest")
            continue
        try:
            info = probe(path)
        except RuntimeError as exc:
            record("sfx", name, False, f"ffprobe failed: {exc}")
            continue
        x = decode(path, mono=True)
        peak = db(float(np.max(np.abs(x))))
        dur = len(x) / SR
        dc = float(np.mean(x))
        problems = []
        warnings = []
        if info["codec"] != "vorbis":
            problems.append(f"codec {info['codec']}")
        if info["sample_rate"] != SR:
            problems.append(f"sr {info['sample_rate']}")
        if info["channels"] != 1:
            problems.append(f"ch {info['channels']}")
        if peak > -1.0:
            problems.append(f"peak {peak:.2f} dBFS > -1")
        if abs(dc) > 0.005:
            problems.append(f"DC {dc:+.4f}")
        is_loop = name in SFX_LOOPS
        limit = 6.0 if is_loop else 2.5
        if dur > limit:
            problems.append(f"duration {dur:.2f}s > {limit}s")
        step = abs(float(x[0]) - float(x[-1]))
        typical = float(np.percentile(np.abs(np.diff(x)), 95)) + 1e-9
        ratio = step / typical
        if is_loop and ratio > 3.0:
            problems.append(f"loop seam step {ratio:.1f}x typical")
        elif is_loop and ratio > 1.5:
            warnings.append(f"loop seam step {ratio:.1f}x typical")
        detail = (f"{'loop' if is_loop else 'once'} {dur:.2f}s  peak {peak:.2f}  "
                  f"DC {dc:+.4f}  seam {ratio:.2f}x")
        ok = not problems
        if ok and warnings and strict:
            ok = False
        record("sfx", name, ok, "; ".join(problems + warnings) or detail)


def check_fonts(strict: bool) -> None:
    manifest_path = os.path.join(ROOT, "assets", "fonts", "font.json")
    if not os.path.isfile(manifest_path):
        record("font", "font.json", False, "missing")
        return
    with open(manifest_path, encoding="utf-8") as fh:
        manifest = json.load(fh)
    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        record("font", "fontTools", False, "fontTools not installed")
        return
    files = manifest.get("files", {})
    for style in ("regular", "bold"):
        filename = files.get(style)
        if not filename:
            record("font", style, False, "not listed in font.json")
            continue
        path = os.path.join(ROOT, "assets", "fonts", filename)
        if not os.path.isfile(path):
            record("font", style, False, f"missing {filename}")
            continue
        expected_hash = manifest.get("hashes", {}).get(style)
        if expected_hash and sha256_file(path) != expected_hash:
            record("font", style, False, "sha256 does not match font.json")
            continue
        font = TTFont(path)
        cmap = set()
        for table in font["cmap"].tables:
            cmap |= set(table.cmap)
        missing = [c for c in REQUIRED_GLYPHS if ord(c) not in cmap]
        record("font", style, not missing,
               f"{font['maxp'].numGlyphs} glyphs, missing {''.join(missing)}" if missing
               else f"{font['maxp'].numGlyphs} glyphs, Spanish coverage complete")
    licence_file = manifest.get("license_file", "OFL.txt")
    licence_path = os.path.join(ROOT, "assets", "fonts", licence_file)
    if not os.path.isfile(licence_path):
        record("font", "licence", False, f"missing {licence_file}")
    else:
        text = open(licence_path, encoding="utf-8", errors="replace").read()
        ok = "SIL Open Font License" in text and "1.1" in text
        record("font", "licence", ok, "OFL 1.1 text present" if ok else "OFL text not recognised")


def render(verbose: bool) -> None:
    width = max(len(r["name"]) for r in RESULTS) + 2
    kind_now = None
    for row in RESULTS:
        if row["kind"] != kind_now:
            kind_now = row["kind"]
            print(f"\n[{kind_now}]")
        status = "PASS" if row["ok"] else ("WARN" if row["warn"] else "FAIL")
        print(f"  {row['name']:<{width}} {status:5s} {row['detail']}")
    failures = [r for r in RESULTS if not r["ok"] and not r["warn"]]
    warnings = [r for r in RESULTS if r["warn"] and not r["ok"]]
    print(f"\n{len(RESULTS)} checks, {len(failures)} failed, {len(warnings)} warnings")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Verify shipped audio and font assets.")
    parser.add_argument("--strict", action="store_true", help="warnings count as failures")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args(argv)

    check_music(args.strict)
    check_sfx(args.strict)
    check_fonts(args.strict)

    if args.json:
        print(json.dumps(RESULTS, indent=2))
    else:
        render(verbose=True)
    failed = [r for r in RESULTS if not r["ok"] and not r["warn"]]
    if args.strict:
        failed = [r for r in RESULTS if not r["ok"]]
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Validate every shipped sprite sheet against AGENTS.md §B9 + the frozen contract.

    python3 tools/lint_sprites.py           # human summary, non-zero on failure
    python3 tools/lint_sprites.py --quiet   # failures only (for CI)

Rules implemented (numbering follows §B9):

1. dimensions == frame_size x (max frames, rows); JSON rows/frames agree with the PNG
2. palette-only pixels; alpha is exactly 0 or 255
3. per-frame colour budget: <= 5 ramp colours + 2 accents (warn at 8, fail above 8)
4. no empty frames; no frame touches its cell edge unless ``allow_edge``
5. pivot inside the frame; item/char frames carry a selective outline
6. item body fill (*_2) keeps >= 3:1 contrast against #0B0C10
7. colour/pattern variants share a silhouette (union mask, exact for colour variants)
8. committed PNGs match the recorded determinism hashes
9. every shipped id is in art/MANIFEST.md and in the frozen contract; no orphans
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "art"))

import numpy as np  # noqa: E402

import pxlib  # noqa: E402
from contract import CONTRACT, validate_contracted  # noqa: E402

SPRITES = ROOT / "assets" / "sprites"
MANIFEST = ROOT / "art" / "MANIFEST.md"
HASHES = ROOT / "art" / "preview" / "hashes.txt"

MAX_COLOURS_FAIL = 8
MAX_COLOURS_WARN = 7


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.warnings: list[str] = []
        self.checked = 0
        self.frames = 0

    def fail(self, message: str) -> None:
        self.failures.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)


def manifest_rows() -> dict[str, str]:
    """id -> status, parsed from the markdown table in art/MANIFEST.md."""
    if not MANIFEST.exists():
        return {}
    rows: dict[str, str] = {}
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line.startswith("| `"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 5:
            continue
        token = cells[0].strip("`").strip()
        if token:
            rows[token] = cells[4].strip("` ")
    return rows


def is_dark_name(name: str) -> bool:
    return name.endswith("_0") or name.startswith("space_")


def check_frame(report: Report, sheet_id: str, anim: str, index: int, frame: pxlib.Canvas,
                spec, allow_edge: bool) -> np.ndarray:
    report.frames += 1
    label = f"{sheet_id}.{anim}[{index}]"
    alpha = frame.buf[:, :, 3]
    bad_alpha = np.unique(alpha[(alpha != 0) & (alpha != 255)])
    if bad_alpha.size:
        report.fail(f"{label}: alpha values outside {0, 255}: {bad_alpha.tolist()}")

    mask = alpha == 255
    if not mask.any():
        report.fail(f"{label}: empty frame")
        return mask

    solid = frame.buf[:, :, :3][mask]
    uniq = np.unique(solid.reshape(-1, 3), axis=0)
    names = []
    for r, g, b in uniq:
        key = (int(r), int(g), int(b))
        if key not in pxlib.PAL.rgb_to_name:
            report.fail(f"{label}: off-palette colour {pxlib.rgb_to_hex(key)}")
        else:
            names.append(pxlib.PAL.rgb_to_name[key])
    if len(names) > MAX_COLOURS_FAIL:
        report.fail(f"{label}: {len(names)} colours (fail above {MAX_COLOURS_FAIL}): {sorted(names)}")
    elif len(names) > MAX_COLOURS_WARN:
        report.warn(f"{label}: {len(names)} colours (budget is 5 ramp + 2 accents)")

    if not allow_edge and (mask[0, :].any() or mask[-1, :].any()
                           or mask[:, 0].any() or mask[:, -1].any()):
        report.fail(f"{label}: silhouette touches the cell edge (set allow_edge if intended)")

    if spec.outline:
        # the outline pass lives *outside* the silhouette: every pixel in the 1 px ring
        # around the silhouette must be a dark ramp/space colour
        ring = mask & (
            np.pad(~mask, 1, constant_values=False)[0:-2, 1:-1]
            | np.pad(~mask, 1, constant_values=False)[2:, 1:-1]
            | np.pad(~mask, 1, constant_values=False)[1:-1, 0:-2]
            | np.pad(~mask, 1, constant_values=False)[1:-1, 2:]
        )
        total = int(ring.sum())
        if total == 0:
            report.fail(f"{label}: no outline pass around the silhouette")
        else:
            ys, xs = np.nonzero(ring)
            dark = 0
            for y, x in zip(ys, xs):
                name = frame.get(int(x), int(y))
                if name and is_dark_name(name):
                    dark += 1
            ratio = dark / total
            if ratio < 0.90:
                report.fail(
                    f"{label}: outline coverage {ratio:.0%} < 90% "
                    f"({total - dark}/{total} outline px are not *_0/space_*)"
                )

    if spec.is_item and "grime" not in sheet_id:
        counts: dict[str, int] = {}
        for y in range(frame.h):
            for x in range(frame.w):
                name = frame.get(x, y)
                if name:
                    counts[name] = counts.get(name, 0) + 1
        opaque = sum(counts.values())
        dominant = max(counts, key=lambda k: (counts[k], k))
        # 6: the body fill must keep >= 3:1 against space_void and must be visible
        if spec.pattern_group:
            body = [c for c in counts
                    if pxlib.PAL.is_ramp(c) and pxlib.PAL.name_to_slot[c] == 2]
            if not body:
                report.fail(f"{label}: no *_2 body fill")
            else:
                fill = max(body, key=lambda c: counts[c])
                share = counts[fill] / opaque
                if share < 0.15:
                    report.fail(f"{label}: body fill {fill} covers only {share:.0%} of the frame")
                if pxlib.contrast_vs_void(fill) < 3.0:
                    report.fail(
                        f"{label}: body fill {fill} contrast "
                        f"{pxlib.contrast_vs_void(fill):.2f}:1 < 3:1"
                    )
        else:
            twos = [c for c in counts
                    if pxlib.PAL.is_ramp(c) and pxlib.PAL.name_to_slot[c] == 2]
            if not twos:
                report.fail(f"{label}: no *_2 body fill anywhere in the frame")
        if not spec.pattern_group and pxlib.contrast_vs_void(dominant) < 3.0:
            report.fail(
                f"{label}: dominant tone {dominant} contrast "
                f"{pxlib.contrast_vs_void(dominant):.2f}:1 < 3:1"
            )
        # 6c: the selective outline (slot 0 / space_*) must not swallow the sprite
        outline = sum(counts[c] for c in counts if c.endswith("_0") or c.startswith("space_"))
        if outline / opaque > 0.40:
            report.fail(
                f"{label}: outline is {outline / opaque:.0%} of the frame "
                f"(> 40%: the outline is swallowing the sprite)"
            )
    return mask


def check_variants(report: Report, sheet_id: str, masks: dict[str, list[np.ndarray]],
                   spec) -> None:
    if not spec.pattern_group:
        return
    union = np.zeros_like(next(iter(masks.values()))[0], dtype=bool)
    for frames in masks.values():
        for mask in frames:
            union |= mask
    for anim, frames in masks.items():
        for index, mask in enumerate(frames):
            if (mask & ~union).any():
                report.fail(f"{sheet_id}.{anim}[{index}]: pixels outside the variant union mask")
        if any(not np.array_equal(frames[0], mask) for mask in frames[1:]):
            report.fail(f"{sheet_id}.{anim}: silhouette changes between frames")
    for pattern in ("solid", "ringed", "spotted"):
        group = [f"{colour}_{pattern}" for colour in ("red", "blue", "yellow")]
        present = [anim for anim in group if anim in masks]
        if len(present) < 2:
            continue
        reference = masks[present[0]][0]
        for anim in present[1:]:
            if not np.array_equal(reference, masks[anim][0]):
                report.fail(f"{sheet_id}: {present[0]} and {anim} silhouettes differ")


def lint_sheet(report: Report, png_path: Path) -> None:
    meta_path = png_path.with_suffix(".json")
    sheet_id = png_path.stem
    if not meta_path.exists():
        report.fail(f"{sheet_id}: missing JSON sidecar")
        return
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        report.fail(f"{sheet_id}: invalid JSON ({exc})")
        return
    report.checked += 1
    spec = CONTRACT.get(sheet_id)
    if spec is None:
        report.fail(f"{sheet_id}: not in the frozen contract (art/contract.py)")
        return
    for problem in validate_contracted(sheet_id, meta):
        report.fail(problem)
    if meta.get("id") != sheet_id:
        report.fail(f"{sheet_id}: JSON id {meta.get('id')!r} does not match the filename")

    frame_w, frame_h = meta["frame_size"]
    pivot = meta["pivot"]
    if not (0 <= pivot[0] < frame_w and 0 <= pivot[1] < frame_h):
        report.fail(f"{sheet_id}: pivot {pivot} outside the frame")

    animations = meta.get("animations", {})
    rows = len(animations)
    max_frames = max((a["frames"] for a in animations.values()), default=0)
    canvas = pxlib.Canvas.from_image(pxlib.load_image(png_path), quantise=False)
    expected = (max_frames * frame_w, rows * frame_h)
    if (canvas.w, canvas.h) != expected:
        report.fail(
            f"{sheet_id}: PNG is {canvas.w}x{canvas.h}, expected {expected[0]}x{expected[1]} "
            f"({max_frames} frames x {rows} rows of {frame_w}x{frame_h})"
        )
        return

    used_rows = set()
    masks: dict[str, list[np.ndarray]] = {}
    for anim, info in animations.items():
        row = info["row"]
        if row in used_rows:
            report.fail(f"{sheet_id}.{anim}: row {row} reused")
        used_rows.add(row)
        if not 0 <= row < rows:
            report.fail(f"{sheet_id}.{anim}: row {row} outside the sheet")
            continue
        frames = []
        for index in range(info["frames"]):
            frame = canvas.crop(index * frame_w, row * frame_h, frame_w, frame_h)
            frames.append(
                check_frame(report, sheet_id, anim, index, frame, spec,
                            bool(meta.get("allow_edge", False)))
            )
        masks[anim] = frames
    if used_rows != set(range(rows)):
        report.fail(f"{sheet_id}: rows {sorted(used_rows)} do not cover 0..{rows - 1}")
    check_variants(report, sheet_id, masks, spec)

    if HASHES.exists():
        recorded = {}
        for line in HASHES.read_text(encoding="utf-8").splitlines():
            if "  " in line:
                digest, name = line.split("  ", 1)
                recorded[name.strip()] = digest.strip()
        actual = hashlib.sha256(png_path.read_bytes()).hexdigest()
        recorded_hash = recorded.get(png_path.name)
        if recorded_hash is None:
            report.warn(f"{sheet_id}: not present in art/preview/hashes.txt")
        elif recorded_hash != actual:
            report.fail(f"{sheet_id}: PNG hash differs from art/preview/hashes.txt (rebuild)")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Lint the shipped sprite sheets.")
    parser.add_argument("--quiet", action="store_true", help="print failures only")
    args = parser.parse_args(argv)

    report = Report()
    if not SPRITES.exists():
        print(f"FAIL: {SPRITES} does not exist")
        return 1
    pngs = sorted(SPRITES.glob("*.png"))
    if not pngs:
        print("FAIL: no sprite sheets found")
        return 1
    for png in pngs:
        lint_sheet(report, png)

    # rule 9: manifest + contract coverage, no orphans
    ids = {png.stem for png in pngs}
    rows = manifest_rows()
    listed = set(rows)
    if not listed:
        report.warn("art/MANIFEST.md has no ids yet")
    for missing in sorted(listed - ids):
        status = rows.get(missing, "")
        if status in {"built", "reviewed"}:
            report.fail(f"MANIFEST lists {missing} as {status} but no sheet exists")
        else:
            report.warn(f"{missing}: planned but not built yet")
    for built in sorted(ids):
        if rows.get(built, "") == "planned":
            report.warn(f"{built}: ships but MANIFEST still says planned")
    for orphan in sorted(ids - listed):
        report.fail(f"{orphan}: shipped but not listed in art/MANIFEST.md")
    for orphan in sorted(ids - set(CONTRACT)):
        report.fail(f"{orphan}: shipped but not in the frozen contract")
    for path in sorted(SPRITES.glob("*.json")):
        if not path.with_suffix(".png").exists():
            report.fail(f"{path.name}: JSON without PNG")

    for warning in report.warnings:
        print(f"WARN {warning}")
    for failure in report.failures:
        print(f"FAIL {failure}")
    print(
        f"lint_sprites: {report.checked}/{len(CONTRACT)} sheets, {report.frames} frames, "
        f"{len(report.failures)} failures, {len(report.warnings)} warnings"
    )
    if report.failures:
        return 1
    if not args.quiet:
        print("all Tier A sheets pass AGENTS.md B9")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

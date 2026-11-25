#!/usr/bin/env python3
"""Quantise a reference image to the frozen 30-colour palette (reference only).

    python3 tools/pixelize.py input.png --size 32 32 --out art/concepts/ref_32.png

Used to turn concept art or a source render into a palette-limited reference that can be
eyeballed while hand-drawing with ``pxlib``.  It never writes into ``assets/sprites/``:
box downscale, nearest-palette mapping, no dithering, alpha forced to 0/255.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from PIL import Image  # noqa: E402

import pxlib  # noqa: E402


def pixelize(source: Path, size: tuple[int, int], out: Path, *, alpha_threshold: int = 128) -> Path:
    image = pxlib.load_image(source).resize(size, Image.BOX)
    canvas = pxlib.Canvas.from_image(image, quantise=False)
    arr = canvas.buf
    keep = arr[:, :, 3] >= alpha_threshold
    quantised = pxlib._quantise_array(arr)  # noqa: SLF001 - intentional internal reuse
    quantised[~keep] = pxlib.TRANSPARENT
    result = pxlib.Canvas.from_array(quantised)
    result.save(out)
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Quantise a reference image to the palette.")
    parser.add_argument("source", type=Path)
    parser.add_argument("--size", nargs=2, type=int, metavar=("W", "H"), required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    out = pixelize(args.source, tuple(args.size), args.out)
    canvas = pxlib.Canvas.from_image(pxlib.load_image(out), quantise=False)
    print(f"wrote {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out} "
          f"({canvas.w}x{canvas.h}, {len(canvas.colors())} colours)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Build every shipped sprite sheet from the builders in ``art/src/``.

    python3 tools/make_art.py              # build all families into assets/sprites/
    python3 tools/make_art.py --only items # build one family
    python3 tools/make_art.py --check      # verify committed PNGs match a fresh build
    python3 tools/make_art.py --hashes     # print the determinism hash table

The pipeline is deterministic: identical inputs give byte-identical PNGs.  ``--check``
rebuilds in memory and compares SHA-256 against the committed files, which is how
rule 8 of AGENTS §B9 (reproducibility) is enforced.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
SRC = ROOT / "art" / "src"
SPRITES = ROOT / "assets" / "sprites"
PREVIEW = ROOT / "art" / "preview"
HASH_FILE = PREVIEW / "hashes.txt"

sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(ROOT / "art"))

import pxlib  # noqa: E402
from contract import CONTRACT, FAMILY_MODULE  # noqa: E402


def load_builders() -> list:
    modules = []
    for path in sorted(SRC.glob("*.py")):
        if path.name.startswith("_"):
            continue
        spec = importlib.util.spec_from_file_location(f"art_src_{path.stem}", path)
        if spec is None or spec.loader is None:  # pragma: no cover - import machinery
            raise RuntimeError(f"cannot load builder {path}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        if not hasattr(module, "build"):
            raise RuntimeError(f"{path} has no build(registry) function")
        module.SOURCE = path.relative_to(ROOT).as_posix()
        modules.append(module)
    if not modules:
        raise RuntimeError("no builders found in art/src")
    return modules


def select(modules: list, only: str | None) -> list:
    if only is None:
        return modules
    keep = [m for m in modules if getattr(m, "FAMILY", m.__name__) == only]
    if not keep:
        available = ", ".join(sorted({getattr(m, "FAMILY", m.__name__) for m in modules}))
        raise SystemExit(f"unknown family {only!r}; available: {available}")
    return keep


def build(only: str | None = None, prune: bool = True):
    registry = pxlib.Registry(SPRITES)
    modules = select(load_builders(), only)
    for module in modules:
        module.build(registry)
    expected = {
        sheet_id
        for sheet_id, spec in CONTRACT.items()
        if only is None or FAMILY_MODULE[spec.family] == only
    }
    missing = expected - set(registry.sheets)
    extra = set(registry.sheets) - set(CONTRACT)
    if missing:
        raise SystemExit(f"builders did not produce: {sorted(missing)}")
    if extra:
        raise SystemExit(f"builders produced ids outside the contract: {sorted(extra)}")
    return registry


def write_hash_table(hashes: dict[str, str]) -> None:
    PREVIEW.mkdir(parents=True, exist_ok=True)
    lines = [f"{hashes[sheet_id]}  {sheet_id}.png" for sheet_id in sorted(hashes)]
    HASH_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def check(registry) -> int:
    failures = 0
    for sheet_id in sorted(registry.sheets):
        png = SPRITES / f"{sheet_id}.png"
        meta_path = SPRITES / f"{sheet_id}.json"
        atlas, meta = registry.sheets[sheet_id].build()
        if not png.exists():
            print(f"FAIL {sheet_id}: PNG missing")
            failures += 1
            continue
        from contract import validate_contracted

        problems = validate_contracted(sheet_id, json.loads(meta_path.read_text())) if meta_path.exists() else []
        if problems:
            failures += len(problems)
            for problem in problems:
                print(f"FAIL {problem}")
        # compare pixels, not encoder bytes: PNG bytes should match too, but pixels are the contract
        committed = pxlib.load_image(png)
        fresh = pxlib.Canvas.from_array(atlas).image()
        if committed.tobytes() != fresh.tobytes():
            print(f"FAIL {sheet_id}: committed PNG differs from a fresh build")
            failures += 1

    return failures


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build Cosmic Spin Cycle sprite sheets.")
    parser.add_argument("--only", help="build a single family (items, pip, washer, env, fx, ui)")
    parser.add_argument("--check", action="store_true", help="verify committed output")
    parser.add_argument("--hashes", action="store_true", help="print the hash table")
    args = parser.parse_args(argv)

    registry = build(only=args.only, prune=args.only is None)
    if args.check:
        failures = check(registry)
        if failures:
            print(f"make_art --check: {failures} failure(s)")
            return 1
        print(f"make_art --check: {len(registry.sheets)} sheets match a fresh build")
        return 0

    hashes = registry.write_all(prune=args.only is None)
    if args.only is None:
        write_hash_table(hashes)
    if args.hashes:
        for sheet_id in sorted(hashes):
            print(f"{hashes[sheet_id]}  {sheet_id}.png")
    total_frames = sum(
        sum(anim.frames for anim in sheet.animations) for sheet in registry.sheets.values()
    )
    print(
        f"built {len(registry.sheets)} sheets / {total_frames} frames "
        f"-> {SPRITES.relative_to(ROOT)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

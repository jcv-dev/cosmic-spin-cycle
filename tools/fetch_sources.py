#!/usr/bin/env python3
"""Fetch, pin and verify the CC0 art sources used by the Cosmic Spin Cycle pipeline.

Kenney's download links are short-lived signed URLs, so the lockfile pins the **asset
page** plus the SHA-256 of the archive and of every extracted file.  A source is only
accepted when its archive carries a licence file that grants CC0; anything else is
refused by name.

Usage
-----
    python3 tools/fetch_sources.py            # download (cached), extract, write SOURCES.json
    python3 tools/fetch_sources.py --verify   # verify lockfile + extracted hashes (no network)
    python3 tools/fetch_sources.py --offline  # extract from cached archives only

Layout (committed unless noted)::

    art/sources/SOURCES.json                       # lockfile: URLs, SHA-256, licence, members
    art/sources/kenney-planets/LICENSE.txt         # licence as shipped in the archive
    art/sources/kenney-planets/planets/*.png       # the four planet renders used
    art/sources/kenney-industrial/LICENSE.txt
    art/sources/kenney-industrial/tiles/*.png      # the 20 industrial tiles used
    art/sources/_downloads/*.zip                   # archives - git-ignored, never committed
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "art" / "sources"
DOWNLOADS = SOURCES / "_downloads"
LOCKFILE = SOURCES / "SOURCES.json"
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)
RETRIEVED = "2026-11-24"

# --------------------------------------------------------------------------------------
# Pin table: explicit page URLs, archive hashes and the exact members we use.
# --------------------------------------------------------------------------------------

INDUSTRIAL_TILES = [
    # piece                         tile   why we use it
    ("tile_0056", "metal floor / tread plate"),
    ("tile_0057", "metal floor, variant"),
    ("tile_0062", "diagonal hazard stripe (blue)"),
    ("tile_0063", "diagonal hazard stripe (orange)"),
    ("tile_0068", "red status lamp"),
    ("tile_0073", "green status sign"),
    ("tile_0079", "vertical pipe segment"),
    ("tile_0084", "console plate, left"),
    ("tile_0085", "console plate, centre"),
    ("tile_0086", "console plate, right"),
    ("tile_0087", "hazard bar, small"),
    ("tile_0088", "hazard bar, long"),
    ("tile_0094", "pipe elbow"),
    ("tile_0099", "large ring / washer hardware"),
    ("tile_0100", "hinge plate, left"),
    ("tile_0101", "hinge plate, centre"),
    ("tile_0102", "hinge plate, right"),
    ("tile_0103", "hazard bar, worn"),
    ("tile_0108", "steel bar, short"),
    ("tile_0110", "steel beam, horizontal"),
    ("tile_0111", "steel beam, joints"),
]

PACKS = [
    {
        "id": "kenney-planets",
        "title": "Planets",
        "author": "Kenney (Kenney Vleugels)",
        "page": "https://kenney.nl/assets/planets",
        "license": "CC0-1.0",
        "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
        "license_member": "License.txt",
        "dir": "kenney-planets",
        "archive": "kenney-planets.zip",
        "sha256": "289386e1cbc4a9a727654795b857c1f3f3447b170c7ba1ceeb9b007d1b84f683",
        "uses": [
            ("Planets/planet03.png", "planets/planet03.png", "rocky, teal continents"),
            ("Planets/planet04.png", "planets/planet04.png", "cratered grey moon"),
            ("Planets/planet07.png", "planets/planet07.png", "blue gas giant"),
            ("Planets/planet09.png", "planets/planet09.png", "violet banded giant"),
        ],
        "rejected": [
            ("Planets/planet00.png", "pale mint; low contrast against space_void"),
            ("Planets/planet05.png", "brown/tan; hue too warm for the crimson ramp"),
        ],
    },
    {
        "id": "kenney-industrial",
        "title": "Pixel Platformer: Industrial Expansion",
        "author": "Kenney (Kenney Vleugels)",
        "page": "https://kenney.nl/assets/pixel-platformer-industrial-expansion",
        "license": "CC0-1.0",
        "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
        "license_member": "License.txt",
        "dir": "kenney-industrial",
        "archive": "kenney-industrial.zip",
        "sha256": "c46e8fee3528434d1680d50a2373c77eb33b1d5db5c7b000d495edecc854fd3e",
        "uses": [
            (f"Tiles/{name}.png", f"tiles/{name}.png", note) for name, note in INDUSTRIAL_TILES
        ],
        "rejected": [
            ("Tiles/tile_0000.png", "grass/stone terrain; wrong genre"),
            ("Tiles/tile_0045.png", "outdoor pipe; no industrial read"),
        ],
    },
]

NOTE = (
    "Content-addressed source lockfile. Every entry is CC0. Archives live in "
    "art/sources/_downloads/ (git-ignored) and are verified against sha256 on every fetch. "
    "Kenney download URLs are short-lived signed links, so the lockfile pins the asset page "
    "plus the archive hash instead of the signed URL."
)


# --------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------

def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def http_get(url: str, referer: str | None = None) -> bytes:
    request = urllib.request.Request(url)
    request.add_header("User-Agent", USER_AGENT)
    if referer:
        request.add_header("Referer", referer)
    with urllib.request.urlopen(request, timeout=180) as response:  # noqa: S310 - pinned https
        return response.read()


def resolve_archive_url(page: str) -> str:
    """Resolve the current signed download URL from the asset page."""
    html = http_get(page).decode("utf-8", "replace")
    ids = re.findall(r"data-download-id='([0-9a-f]+)'", html)
    if not ids:
        raise SystemExit(f"no data-download-id on {page} (page layout changed?)")
    payload = http_get(f"https://kenney.nl/download-link/{ids[0]}", referer=page)
    try:
        return json.loads(payload.decode("utf-8", "replace"))["url"]
    except Exception as exc:  # pragma: no cover - upstream shape change
        raise SystemExit(f"unexpected download-link payload: {payload[:200]!r}") from exc


def archive_path(pack: dict) -> Path:
    return DOWNLOADS / pack["archive"]


def ensure_archive(pack: dict, offline: bool) -> Path:
    path = archive_path(pack)
    if path.exists() and sha256_file(path) == pack["sha256"]:
        print(f"  cached  {pack['id']}")
        return path
    if offline:
        raise SystemExit(f"{pack['id']}: archive missing and --offline was requested")
    print(f"  fetch   {pack['id']}  {pack['page']}")
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    url = resolve_archive_url(pack["page"])
    data = http_get(url, referer=pack["page"])
    actual = sha256_bytes(data)
    if actual != pack["sha256"]:
        raise SystemExit(
            f"{pack['id']}: SHA-256 mismatch\n  expected {pack['sha256']}\n"
            f"  actual   {actual}\n  pin the new archive deliberately before using it"
        )
    path.write_bytes(data)
    print(f"  saved   {pack['id']}  {len(data)} bytes")
    return path


class LicenceError(RuntimeError):
    """The archive does not carry a CC0/public-domain grant."""


def read_licence(pack: dict, archive: zipfile.ZipFile) -> str:
    member = pack["license_member"]
    if member not in archive.namelist():
        raise LicenceError(f"{pack['id']}: {member} missing from the archive - refusing source")
    text = archive.read(member).decode("utf-8", "replace")
    normalised = text.lower().replace("\n", " ")
    if "cc0" not in normalised and "public domain" not in normalised:
        raise LicenceError(f"{pack['id']}: {member} grants neither CC0 nor public domain")
    return text


def extract(pack: dict, archive: zipfile.ZipFile) -> list[dict]:
    dest = SOURCES / pack["dir"]
    extracted: list[dict] = []
    for member, rel, note in pack["uses"]:
        try:
            data = archive.read(member)
        except KeyError as exc:
            raise SystemExit(f"{pack['id']}: member {member} missing from archive") from exc
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        extracted.append(
            {
                "path": target.relative_to(ROOT).as_posix(),
                "sha256": sha256_bytes(data),
                "note": note,
            }
        )
    licence = read_licence(pack, archive)
    licence_path = dest / "LICENSE.txt"
    licence_path.write_text(licence, encoding="utf-8")
    extracted.append(
        {
            "path": licence_path.relative_to(ROOT).as_posix(),
            "sha256": sha256_file(licence_path),
            "note": f"{pack['license']} licence as shipped in the archive",
        }
    )
    return extracted


def write_lockfile(manifests: list[dict]) -> None:
    payload = {"version": 1, "note": NOTE, "packs": manifests}
    LOCKFILE.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def verify() -> int:
    if not LOCKFILE.exists():
        print("FAIL: art/sources/SOURCES.json is missing")
        return 1
    lock = json.loads(LOCKFILE.read_text(encoding="utf-8"))
    failures = 0
    seen = set()
    for pack in lock["packs"]:
        pin = next((p for p in PACKS if p["id"] == pack["id"]), None)
        if pin is None:
            print(f"FAIL {pack['id']}: not in the script's pin table")
            failures += 1
            continue
        if pin["sha256"] != pack["sha256"]:
            print(f"FAIL {pack['id']}: lockfile pins {pack['sha256'][:12]}")
            failures += 1
        if pin["page"] != pack["page"]:
            print(f"FAIL {pack['id']}: page differs from pin table")
            failures += 1
        for entry in pack["extracted"]:
            seen.add(entry["path"])
            path = ROOT / entry["path"]
            if not path.exists():
                print(f"FAIL {pack['id']}: missing {entry['path']}")
                failures += 1
            elif sha256_file(path) != entry["sha256"]:
                print(f"FAIL {pack['id']}: hash mismatch {entry['path']}")
                failures += 1
        archive = archive_path(pin)
        archive_state = "cached" if archive.exists() else "not cached"
        if archive.exists() and sha256_file(archive) != pin["sha256"]:
            print(f"FAIL {pack['id']}: cached archive hash mismatch")
            failures += 1
        if archive.exists():
            with zipfile.ZipFile(archive) as zf:
                try:
                    read_licence(pin, zf)
                except LicenceError as exc:
                    print(f"FAIL {exc}")
                    failures += 1
        print(
            f"ok   {pack['id']:<20} {len(pack['extracted']):>2} files  "
            f"archive {archive_state}  {pack['license']}"
        )
    # no unlisted files in the source tree (ignoring the archives dir)
    for path in sorted(SOURCES.rglob("*")):
        if path.is_dir() or DOWNLOADS in path.parents:
            continue
        rel = path.relative_to(ROOT).as_posix()
        if rel not in seen and path.name != "SOURCES.json" and not path.name.startswith("."):
            print(f"WARN orphan source file {rel}")
    return 1 if failures else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Fetch and pin CC0 art sources.")
    parser.add_argument("--verify", action="store_true", help="verify pins, no network")
    parser.add_argument("--offline", action="store_true", help="never touch the network")
    args = parser.parse_args(argv)

    if args.verify:
        return verify()

    SOURCES.mkdir(parents=True, exist_ok=True)
    manifests = []
    for pack in PACKS:
        archive_file = ensure_archive(pack, args.offline)
        with zipfile.ZipFile(archive_file) as zf:
            try:
                extracted = extract(pack, zf)
            except LicenceError as exc:
                raise SystemExit(str(exc)) from exc
        manifests.append(
            {
                "id": pack["id"],
                "title": pack["title"],
                "author": pack["author"],
                "page": pack["page"],
                "license": pack["license"],
                "license_url": pack["license_url"],
                "license_member": pack["license_member"],
                "dir": pack["dir"],
                "retrieved": RETRIEVED,
                "sha256": pack["sha256"],
                "uses": [{"member": m, "as": rel, "sha256": e["sha256"]}
                         for (m, rel, _), e in zip(pack["uses"], extracted)],
                "extracted": [
                    {"path": e["path"], "sha256": e["sha256"]} for e in extracted
                ],
                "rejected": [{"member": m, "reason": r} for m, r in pack.get("rejected", [])],
            }
        )
        print(f"  licence ok {pack['id']:<20} {len(extracted)} files")
    write_lockfile(manifests)
    print(f"  wrote   {LOCKFILE.relative_to(ROOT)}")
    return verify()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

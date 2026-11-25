#!/usr/bin/env python3
"""Frozen sprite contract for Tier A (AGENTS.md §B5/§B6 + DECISIONS D012).

Single source of truth shared by ``make_art.py`` (build), ``lint_sprites.py`` (validate)
and ``preview.py`` (render).  If a builder and this table disagree, the build fails.

Deviations from the literal wording of §B5 are recorded in ``art/DESIGN.md``:

* ``char_pip`` is 12 animations / 12 rows (4 animations x 3 directions).  §B5's "9 rows"
  cannot express 4 animations x 3 directions; §B6 names the animations explicitly
  (``idle_down``, ``run_side``, ...), which is what the engine consumes.
* ``ui_bar_stability`` is split into ``ui_bar_stability`` (96x10 frame) and
  ``ui_bar_stability_fill`` (8x6 tile) per D012.
* ``item_grime`` ships as three single-frame sheets: ``item_grime_16/24/32``.
"""

from __future__ import annotations

from dataclasses import dataclass

FPS = {
    "idle": 4,
    "idle_shimmer": 3,
    "run": 10,
    "throw": 18,
    "strike": 18,
    "belt": 8,
    "washing": 8,
    "turbulent": 14,
    "explosion": 12,
    "sparkle": 8,
    "flash": 18,
    "chute": 12,
    "done": 6,
    "broken": 4,
    "one": 1,
}


@dataclass(frozen=True)
class Anim:
    frames: int
    fps: float
    loop: bool = True


@dataclass(frozen=True)
class Asset:
    size: tuple[int, int]
    pivot: tuple[int, int]
    anims: dict[str, Anim]
    family: str
    tier: str = "A"
    allow_edge: bool = False
    outline: bool = False
    pattern_group: str = ""  # items: variants grouped by colour/pattern for mask checks
    note: str = ""

    @property
    def is_item(self) -> bool:
        return self.family == "item"


def _variants(frames: int, fps: float) -> dict[str, Anim]:
    colors = ("red", "blue", "yellow")
    patterns = ("solid", "ringed", "spotted")
    return {
        f"{color}_{pattern}": Anim(frames, fps)
        for color in colors
        for pattern in patterns
    }


ITEM_FRAMES = {"rocky": 2, "sock": 2, "moon": 1, "gas": 2}


def _item_assets() -> dict[str, Asset]:
    assets: dict[str, Asset] = {}
    for name, size in (("rocky", (16, 16)), ("sock", (16, 16)),
                       ("moon", (16, 16)), ("gas", (24, 24))):
        assets[f"item_{name}"] = Asset(
            size=size,
            pivot=(size[0] // 2, size[1] // 2),
            anims=_variants(ITEM_FRAMES[name], FPS["idle_shimmer"]),
            family="item",
            outline=True,
            pattern_group=name,
            note="9 colour/pattern variants of one authored silhouette",
        )
    assets["item_core"] = Asset(
        size=(32, 32),
        pivot=(16, 16),
        anims={"idle": Anim(4, 6)},
        family="item",
        outline=True,
        note="galaxy core, unique wildcard; 4-frame swirl",
    )
    for size in (16, 24, 32):
        assets[f"item_grime_{size}"] = Asset(
            size=(size, size),
            pivot=(size // 2, size // 2),
            anims={"overlay": Anim(1, 1)},
            family="item",
            note="grime overlay, drawn on top while dirty",
        )
    return assets


def _pip_assets() -> dict[str, Asset]:
    anims: dict[str, Anim] = {}
    for direction in ("down", "side", "up"):
        anims[f"idle_{direction}"] = Anim(2, FPS["idle"])
        anims[f"run_{direction}"] = Anim(4, FPS["run"])
        anims[f"throw_{direction}"] = Anim(2, FPS["throw"], loop=False)
        anims[f"strike_{direction}"] = Anim(2, FPS["strike"], loop=False)
    return {
        "char_pip": Asset(
            size=(24, 24),
            pivot=(12, 22),
            anims=anims,
            family="char",
            outline=True,
            note="gravity gloves in funk_cyan; side strip is drawn facing right",
        )
    }


def _env_assets() -> dict[str, Asset]:
    return {
        "env_belt": Asset(
            size=(16, 16),
            pivot=(8, 8),
            anims={"scroll": Anim(4, FPS["belt"])},
            family="env",
            allow_edge=True,
            note="seamless in 90-degree rotations",
        ),
        "env_belt_cap": Asset(
            size=(16, 16),
            pivot=(8, 8),
            anims={"start": Anim(1, FPS["one"])},
            family="env",
            allow_edge=True,
            note="portal/dispenser end cap",
        ),
        "env_shredder": Asset(
            size=(32, 32),
            pivot=(16, 30),
            anims={"idle": Anim(3, 8)},
            family="env",
            note="vacuum shredder at the belt end",
        ),
        "env_chute": Asset(
            size=(32, 32),
            pivot=(16, 16),
            anims={
                "closed": Anim(1, FPS["one"]),
                "opening": Anim(3, FPS["chute"], loop=False),
                "open": Anim(2, FPS["done"]),
                "accept": Anim(3, FPS["chute"], loop=False),
            },
            family="env",
            note="pneumatic central hatch",
        ),
        "env_floor": Asset(
            size=(16, 16),
            pivot=(8, 8),
            anims={"variant_a": Anim(1, FPS["one"]), "variant_b": Anim(1, FPS["one"]),
                   "variant_c": Anim(1, FPS["one"])},
            family="env",
            allow_edge=True,
            note="three subtle floor variants, seamless",
        ),
        "env_room": Asset(
            size=(320, 180),
            pivot=(160, 90),
            anims={"bg": Anim(1, FPS["one"])},
            family="env",
            allow_edge=True,
            note="backdrop only: no belts, washers or chute baked in",
        ),
    }


def _fx_assets() -> dict[str, Asset]:
    return {
        "fx_clean_sparkle": Asset((8, 8), (4, 4), {"play": Anim(4, FPS["sparkle"])}, "fx"),
        "fx_burst_perfect": Asset((16, 16), (8, 8), {"play": Anim(4, 14)}, "fx"),
        "fx_burst_good": Asset((12, 12), (6, 6), {"play": Anim(3, 14)}, "fx"),
        "fx_miss_puff": Asset((12, 12), (6, 6), {"play": Anim(3, 10)}, "fx"),
        "fx_explosion": Asset((32, 32), (16, 16), {"play": Anim(6, FPS["explosion"])}, "fx"),
        "fx_bubbles": Asset((8, 8), (4, 4), {"play": Anim(3, 8)}, "fx"),
    }


def _ui_assets() -> dict[str, Asset]:
    return {
        "ui_holo_icons": Asset(
            (12, 12),
            (6, 6),
            {name: Anim(1, FPS["one"]) for name in
             ("red", "blue", "yellow", "solid", "ringed", "spotted", "wild")},
            "ui",
            note="washer requirement holograms: colour glyph + pattern glyph",
        ),
        "ui_panel": Asset((24, 24), (12, 12), {"panel": Anim(1, FPS["one"])}, "ui",
                          allow_edge=True, note="9-slice, corner 8 px"),
        "ui_bar_stability": Asset((96, 10), (48, 5), {"bar": Anim(1, FPS["one"])}, "ui",
                                  allow_edge=True, note="segmented stability frame"),
        "ui_bar_stability_fill": Asset((8, 6), (4, 3), {"fill": Anim(1, FPS["one"])}, "ui",
                                       allow_edge=True, note="8x6 fill tile"),
        "ui_icons": Asset((8, 8), (4, 4),
                          {name: Anim(1, FPS["one"]) for name in ("clock", "stability", "combo")},
                          "ui"),
        "ui_reticle": Asset((16, 16), (8, 8), {"aim": Anim(1, FPS["one"])}, "ui"),
        "ui_logo": Asset((160, 48), (80, 24), {"logo": Anim(1, FPS["one"])}, "ui",
                         allow_edge=True, note="COSMIC SPIN CYCLE wordmark"),
    }


def _washer_assets() -> dict[str, Asset]:
    return {
        "mach_washer": Asset(
            size=(48, 48),
            pivot=(24, 46),
            anims={
                "idle": Anim(2, 3),
                "load_flash": Anim(3, FPS["flash"], loop=False),
                "washing": Anim(4, FPS["washing"]),
                "turbulent": Anim(4, FPS["turbulent"]),
                "done": Anim(2, FPS["done"]),
                "broken": Anim(2, FPS["broken"]),
            },
            family="mach",
            note="black-hole porthole drum, hazard stripe; pivot bottom-centre",
        )
    }


CONTRACT: dict[str, Asset] = {}
for _part in (_item_assets(), _pip_assets(), _env_assets(), _fx_assets(), _ui_assets(),
              _washer_assets()):
    CONTRACT.update(_part)

#: Which builder module owns each id (used by make_art --only).
FAMILY_MODULE = {
    "char": "pip",
    "item": "items",
    "env": "env",
    "fx": "fx",
    "ui": "ui",
    "mach": "washer",
}

TIER_A_IDS = list(CONTRACT)


def validate_contracted(sheet_id: str, meta: dict) -> list[str]:
    """Return a list of human-readable contract violations for one sheet's JSON."""
    problems: list[str] = []
    spec = CONTRACT.get(sheet_id)
    if spec is None:
        return [f"{sheet_id}: not in the frozen contract"]
    if tuple(meta.get("frame_size", ())) != spec.size:
        problems.append(f"{sheet_id}: frame_size {meta.get('frame_size')} != {list(spec.size)}")
    if tuple(meta.get("pivot", ())) != spec.pivot:
        problems.append(f"{sheet_id}: pivot {meta.get('pivot')} != {list(spec.pivot)}")
    if meta.get("scale") != 4:
        problems.append(f"{sheet_id}: scale {meta.get('scale')} != 4")
    if meta.get("tier") != spec.tier:
        problems.append(f"{sheet_id}: tier {meta.get('tier')} != {spec.tier}")
    anims = meta.get("animations", {})
    if set(anims) != set(spec.anims):
        missing = sorted(set(spec.anims) - set(anims))
        extra = sorted(set(anims) - set(spec.anims))
        problems.append(f"{sheet_id}: animations mismatch missing={missing} extra={extra}")
    for name, expected in spec.anims.items():
        got = anims.get(name)
        if not isinstance(got, dict):
            continue
        if got.get("frames") != expected.frames:
            problems.append(
                f"{sheet_id}.{name}: frames {got.get('frames')} != {expected.frames}"
            )
        if float(got.get("fps", -1)) != float(expected.fps):
            problems.append(f"{sheet_id}.{name}: fps {got.get('fps')} != {expected.fps}")
        if bool(got.get("loop")) != expected.loop:
            problems.append(f"{sheet_id}.{name}: loop {got.get('loop')} != {expected.loop}")
    if spec.allow_edge and not meta.get("allow_edge"):
        problems.append(f"{sheet_id}: allow_edge must be true for this asset")
    return problems

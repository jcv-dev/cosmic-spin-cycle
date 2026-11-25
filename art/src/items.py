#!/usr/bin/env python3
"""Items: rocky planets, socks, moons, gas giants, the galaxy core and grime overlays.

Adaptation notes
----------------
* ``item_rocky`` / ``item_moon`` / ``item_gas`` take their *surface structure* from the
  Kenney Planets renders (CC0): continent masks, crater fields and storm swirls are
  box-downscaled to the sprite size, morphologically cleaned into a few readable blobs,
  and used as hard pattern masks.  Colour and top-left sphere shading come from
  ``pxlib``, so every pixel is palette-exact and nothing is resampled in the final art.
* ``item_sock``, ``item_grime`` and ``item_core`` are authored here with primitives: no
  CC0 16 px laundry item survived inspection (see docs/PROVENANCE.md).
* One authored silhouette per item, nine variants by ramp swap + pattern mask.  Frames
  only change *inside* the silhouette (a 1 px shimmer), which the linter checks.
"""

from __future__ import annotations

import numpy as np

import pxlib
from pxlib import Canvas, PAL, Sheet

FAMILY = "items"

SOURCE = "art/src/items.py"

ROCKY_MASK = None
MOON_CRATERS = None
GAS_STORM = None


def _lazy_sources() -> None:
    global ROCKY_MASK, MOON_CRATERS, GAS_STORM
    if ROCKY_MASK is not None:
        return
    ROCKY_MASK = pxlib.clean_mask(
        pxlib.source_pattern_mask(
            pxlib.load_source("kenney-planets", "planets/planet03.png"), 16, 16, percentile=45
        ),
        keep=2,
        min_px=7,
    )
    MOON_CRATERS = pxlib.clean_mask(
        pxlib.source_pattern_mask(
            pxlib.load_source("kenney-planets", "planets/planet04.png"), 16, 16, percentile=34
        ),
        keep=4,
        min_px=2,
        smooth=0,
    )
    GAS_STORM = pxlib.clean_mask(
        pxlib.source_pattern_mask(
            pxlib.load_source("kenney-planets", "planets/planet07.png"), 24, 24, percentile=54
        ),
        keep=2,
        min_px=14,
    )


# --------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------


def disc_mask(w: int, h: int, cx: float, cy: float, r: float) -> np.ndarray:
    ys, xs = np.mgrid[0:h, 0:w]
    return ((xs - cx) ** 2 + (ys - cy) ** 2) <= r * r


def shift(mask: np.ndarray, dx: int, dy: int) -> np.ndarray:
    out = np.zeros_like(mask)
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    for y, x in zip(ys, xs):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w:
            out[ny, nx] = True
    return out


def modulate(canvas: Canvas, mask: np.ndarray, family: str, delta: int,
             *, floor: int = 1, only_slots: tuple[int, ...] | None = None) -> None:
    """Shift the ramp slot of every masked pixel (keeps the sphere's own light).

    ``floor`` keeps shadow modulation from turning body pixels into the outline slot:
    slot 0 belongs to the selective outline, so the body never reaches it.
    """
    ramp = PAL.ramp(family)
    for y, x in np.argwhere(mask):
        name = canvas.get(int(x), int(y))
        if name is None or name not in PAL.name_to_ramp or PAL.name_to_ramp[name] != family:
            continue
        if only_slots is not None and PAL.name_to_slot[name] not in only_slots:
            continue
        slot = PAL.name_to_slot[name] + delta
        canvas.set(int(x), int(y), ramp[max(floor, min(4, slot))])


def shimmer(canvas: Canvas, family: str, at: tuple[int, int]) -> Canvas:
    """Frame 2: a two-pixel specular sparkle, strictly inside the silhouette."""
    out = canvas.copy()
    ramp = PAL.ramp(family)
    x, y = at
    if out.get(x, y) is not None:
        out.set(x, y, ramp[4])
    if out.get(x + 1, y) is not None:
        out.set(x + 1, y, ramp[3])
    return out


def tint(canvas: Canvas, family: str) -> Canvas:
    return pxlib.ramp_swap_family(canvas, family)


# --------------------------------------------------------------------------------------
# item_rocky
# --------------------------------------------------------------------------------------


def build_rocky(colour: str, pattern: str) -> list[Canvas]:
    _lazy_sources()
    size, cx, cy, r = 16, 7.5, 7.5, 6.0
    body = Canvas(size, size)
    pxlib.shade_sphere(body, cx, cy, r, "red", bands=(0.0, 0.12, 0.50, 0.84), rim=False)
    sphere = disc_mask(size, size, cx, cy, r)
    inner = disc_mask(size, size, cx, cy, r - 1.2)

    if pattern == "spotted":
        # continents from planet03: dark land, lit upper edge
        land = ROCKY_MASK & inner
        modulate(body, land, "red", -1)
        modulate(body, shift(land, 0, 1) & ~land & inner, "red", 1)
    elif pattern == "ringed":
        band = pxlib.ringed_mask(size, size, radius=6.6, thickness=2, tilt=-0.40) & inner
        modulate(body, band, "red", 1)
        modulate(body, shift(band, 0, 2) & ~band & inner, "red", -1)
    else:  # solid: two craters with a lit far rim
        for ccx, ccy, cr in ((6.0, 6.0, 1.3), (10.2, 10.4, 1.0)):
            crater = disc_mask(size, size, ccx, ccy, cr) & inner
            rim = pxlib.dilate(crater, 1) & ~crater & inner
            modulate(body, crater, "red", -1)
            modulate(body, shift(rim & ~shift(crater, 0, -1), 0, 0), "red", 1)

    pxlib.outline(body)
    frames = [tint(body, colour)]
    frames.append(tint(shimmer(body, "red", (5, 5)), colour))
    return frames


# --------------------------------------------------------------------------------------
# item_sock — hand-authored silhouette
# --------------------------------------------------------------------------------------

# (y, x0, x1) inclusive spans: ribbed cuff, narrow leg, foot turning right with a round toe
SOCK_SPANS = [
    (2, 3, 9),
    (3, 3, 9),
    (4, 3, 9),
    (5, 4, 8),
    (6, 4, 8),
    (7, 4, 8),
    (8, 4, 8),
    (9, 4, 9),
    (10, 4, 11),
    (11, 4, 12),
    (12, 5, 13),
    (13, 6, 12),
]


def sock_mask() -> np.ndarray:
    mask = np.zeros((16, 16), dtype=bool)
    for y, x0, x1 in SOCK_SPANS:
        mask[y, x0 : x1 + 1] = True
    return mask


def build_sock(colour: str, pattern: str) -> list[Canvas]:
    canvas = Canvas(16, 16)
    mask = sock_mask()
    ramp = PAL.ramp("red")

    for y, x0, x1 in SOCK_SPANS:
        for x in range(x0, x1 + 1):
            if x == x0:
                slot = 3
            elif x == x1:
                slot = 1
            else:
                slot = 2
            canvas.set(x, y, ramp[slot])

    # cuff: ribbed top, a fold shadow under it, and a lit lower lip
    for x in range(3, 10):
        canvas.set(x, 2, ramp[3])
        canvas.set(x, 3, ramp[1] if x % 2 else ramp[2])
        canvas.set(x, 4, ramp[1])
    for x in range(4, 9):
        canvas.set(x, 5, ramp[2])
    # foot: lit top edge, no dark sole (a sole reads as a boot)
    for x in range(5, 12):
        canvas.set(x, 10, ramp[3])
    for x in range(6, 13):
        canvas.set(x, 12, ramp[2])
    canvas.set(13, 11, ramp[1])
    canvas.set(13, 12, ramp[1])
    canvas.set(12, 13, ramp[2])

    if pattern == "ringed":
        for y in (6, 7, 11):
            for x in range(16):
                if mask[y, x]:
                    canvas.set(x, y, ramp[3] if y in (6, 11) else ramp[1])
    elif pattern == "spotted":
        for x, y in ((6, 6), (8, 8), (7, 11), (10, 12)):
            if mask[y, x]:
                canvas.set(x, y, ramp[1])
                if mask[y - 1, x]:
                    canvas.set(x, y - 1, ramp[3])
    else:
        canvas.set(6, 7, ramp[4])
        canvas.set(5, 7, ramp[3])
        canvas.set(6, 8, ramp[1])

    pxlib.outline(canvas)
    frames = [tint(canvas, colour)]
    frames.append(tint(shimmer(canvas, "red", (10, 11)), colour))
    return frames


# --------------------------------------------------------------------------------------
# item_moon — crescent
# --------------------------------------------------------------------------------------


def moon_mask() -> np.ndarray:
    outer = disc_mask(16, 16, 7.5, 7.6, 6.2)
    bite = disc_mask(16, 16, 11.2, 5.2, 5.0)
    # keep the main crescent and drop the 4-connected spur at the lower horn
    return pxlib.clean_mask(outer & ~bite, keep=1, min_px=20, smooth=0)


def build_moon(colour: str, pattern: str) -> Canvas:
    _lazy_sources()
    canvas = Canvas(16, 16)
    mask = moon_mask()
    ramp = PAL.ramp("red")
    outer = disc_mask(16, 16, 7.5, 7.6, 6.2)
    bite = disc_mask(16, 16, 11.2, 5.2, 5.0)
    # tube shading: lit outer edge (top/left), dark inner edge facing the bite
    for y in range(16):
        for x in range(16):
            if not mask[y, x]:
                continue
            dist_outer = ((x - 7.5) ** 2 + (y - 7.6) ** 2) ** 0.5
            dist_bite = ((x - 11.2) ** 2 + (y - 5.2) ** 2) ** 0.5
            if 6.2 - dist_outer < 0.95 and (y < 9):
                slot = 3
            elif 0.0 < 5.0 - dist_bite < 0.85:
                slot = 1
            else:
                slot = 2
            canvas.set(x, y, ramp[slot])
    # a lit crescent tip and a shadow under the lower tip
    for x, y in ((4, 3), (5, 2), (12, 13)):
        if mask[y, x]:
            canvas.set(x, y, ramp[3] if (x, y) != (12, 13) else ramp[1])

    inner = mask & pxlib.erode(mask, 1)
    craters = MOON_CRATERS & inner
    modulate(canvas, craters, "red", -1, only_slots=(3,))
    if pattern == "ringed":
        band = pxlib.ringed_mask(16, 16, radius=7.0, thickness=2, tilt=-0.45) & inner
        modulate(canvas, band, "red", 1)
        modulate(canvas, shift(band, 0, 2) & ~band & inner, "red", -1)
    elif pattern == "spotted":
        for y, x in ((4, 4), (10, 5), (6, 11), (11, 11)):
            if mask[y, x]:
                canvas.set(x, y, ramp[1])
                if mask[y - 1, x]:
                    canvas.set(x, y - 1, ramp[3])
    else:
        for y, x in ((4, 8), (9, 11)):
            if mask[y, x]:
                canvas.set(x, y, ramp[3])

    pxlib.outline(canvas)
    return tint(canvas, colour)


# --------------------------------------------------------------------------------------
# item_gas — 24x24 banded giant
# --------------------------------------------------------------------------------------


def gas_belts(size: int) -> np.ndarray:
    mask = np.zeros((size, size), dtype=bool)
    for y in range(size):
        if (y + 3) % 7 in (0, 1):
            mask[y, :] = True
    return mask


def build_gas(colour: str, pattern: str) -> list[Canvas]:
    _lazy_sources()
    size, cx, cy, r = 24, 11.5, 11.5, 10.0
    body = Canvas(size, size)
    pxlib.shade_sphere(body, cx, cy, r, "red", bands=(0.0, 0.14, 0.52, 0.86), rim=False)
    sphere = disc_mask(size, size, cx, cy, r)
    inner = disc_mask(size, size, cx, cy, r - 1.3)

    belts = gas_belts(size) & inner
    modulate(body, belts, "red", 1)
    modulate(body, shift(belts, 0, -1) & ~belts & inner, "red", -1)

    if pattern == "spotted":
        storm = GAS_STORM & inner
        modulate(body, storm, "red", -1)
        modulate(body, shift(storm, 0, -1) & ~storm & inner & shift(storm, 0, -1), "red", 1)
        eye = disc_mask(size, size, 8.6, 8.2, 1.5) & inner
        modulate(body, eye, "red", -1)
        modulate(body, shift(eye, 0, -1) & ~eye & inner, "red", 1)
    elif pattern == "ringed":
        band = pxlib.ringed_mask(size, size, radius=10.2, thickness=2, tilt=-0.34) & inner
        modulate(body, band, "red", 1)
        modulate(body, shift(band, 0, 2) & ~band & inner, "red", -1)
    else:
        # solid: keep the belts, add one calm dark storm spot low-right
        spot = disc_mask(size, size, 14.0, 15.0, 1.8) & inner
        modulate(body, spot, "red", -1)

    pxlib.outline(body)
    frames = [tint(body, colour)]
    frames.append(tint(shimmer(body, "red", (8, 8)), colour))
    return frames


# --------------------------------------------------------------------------------------
# item_core — 32x32 galaxy core, four-frame swirl
# --------------------------------------------------------------------------------------


def build_core() -> list[Canvas]:
    """A dense spiral disc with a golden nucleus, rotated 90 degrees per frame.

    The silhouette is a filled disc (not open arcs) so the 1 px selective outline stays
    a thin rim instead of swallowing the sprite; the arms are read from the magenta /
    plum split across the disc.
    """
    size = 32
    cx = cy = 16.0
    frames: list[Canvas] = []
    for frame_index in range(4):
        canvas = Canvas(size, size)
        phase = frame_index * (np.pi / 2)
        for y in range(size):
            for x in range(size):
                dx, dy = x - cx + 0.5, y - cy + 0.5
                dist = (dx * dx + dy * dy) ** 0.5
                if dist > 13.2:
                    continue
                angle = np.arctan2(dy, dx)
                spiral = (angle - phase + 4.2 * np.log(max(dist, 1.0) / 4.4)) % np.pi
                width = 1.30 + 0.30 * (1.0 - dist / 14.0)
                if dist > 12.2:
                    canvas.set(x, y, "funk_plum")          # dark rim
                elif spiral < 0.62:
                    canvas.set(x, y, "funk_plum")          # dust lane
                else:
                    canvas.set(x, y, "funk_magenta")       # arm
        # hot golden nucleus, lit from the top-left like everything else
        pxlib.shade_sphere(canvas, cx, cy, 5.2, "yel", bands=(0.0, 0.0, 0.58, 0.88),
                           rim=False)
        canvas.set(14, 14, "metal_4")
        canvas.set(15, 13, "yel_4")
        canvas.set(13, 15, "yel_4")
        # stars caught in the gravity well, rotating with the arms
        stars = [(5, 8), (26, 7), (25, 25), (6, 24)]
        for index in range(2):
            sx, sy = stars[(frame_index + index * 2) % len(stars)]
            canvas.set(sx, sy, "metal_4")
            if index == 0:
                canvas.set(sx + 1, sy, "metal_4")
        pxlib.outline(canvas, color="space_deep")
        frames.append(canvas)
    return frames


# --------------------------------------------------------------------------------------
# grime overlays
# --------------------------------------------------------------------------------------


def build_grime(size: int) -> Canvas:
    """Grime overlay: splat body from a Kenney Planets mask, cracks from a Roguelike tile.

    Both masks are CC0 and box-downscaled to the overlay size, then hard-thresholded:
    planet04's dark craters give the organic splat, tile_0702's cracks give the thin
    fractures that sell "this item has been on the floor".  The 3-tone shading is
    authored so the stain keeps the project's top-left light.
    """
    planet = pxlib.load_source("kenney-planets", "planets/planet04.png")
    body = pxlib.clean_mask(
        pxlib.source_pattern_mask(planet, size, size, percentile=68),
        keep=2, min_px=max(6, size // 2), smooth=1,
    )
    # a drip off the lowest blob keeps the stain from reading as a clean circle
    ys, xs = np.nonzero(body)
    if len(ys):
        drip_x = int(np.median(xs))
        drip_y = int(ys.max())
        for step in range(1, max(2, size // 5) + 1):
            y = min(size - 2, drip_y + step)
            if 1 <= y < size - 1:
                body[y, min(size - 2, drip_x)] = True
    crack = pxlib.clean_mask(
        pxlib.source_pattern_mask(
            pxlib.load_source("kenney-roguelike", "tiles/tile_0702.png"),
            size, size, percentile=22,
        ),
        keep=2, min_px=3, smooth=0,
    )

    shape = np.zeros((size, size), dtype=bool)
    shape[1:size - 1, 1:size - 1] = body[1:size - 1, 1:size - 1]
    canvas = Canvas(size, size)
    for y, x in np.argwhere(shape):
        canvas.set(int(x), int(y), "yel_0")
    lit = shape & ~shift(shape, -1, -1)
    shadow = shape & ~shift(shape, 1, 1)
    for y, x in np.argwhere(lit):
        canvas.set(int(x), int(y), "yel_1")
    for y, x in np.argwhere(shadow):
        canvas.set(int(x), int(y), "space_haze")
    # cracks: only inside the stain, dark recess with a lit lip
    inside = shape & crack
    for y, x in np.argwhere(inside):
        canvas.set(int(x), int(y), "space_haze")
        if 0 <= y - 1 < size and inside[y - 1, x] is False and shape[y - 1, x]:
            canvas.set(int(x), int(y) - 1, "yel_1")
    return canvas


# --------------------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------------------


def build(registry: pxlib.Registry) -> None:
    _lazy_sources()
    colours = ("red", "blue", "yellow")
    patterns = ("solid", "ringed", "spotted")

    rocky = Sheet("item_rocky", (16, 16), (8, 8), SOURCE, note="rocky planet, 9 variants")
    for colour in colours:
        for pattern in patterns:
            rocky.add(f"{colour}_{pattern}", build_rocky(colour, pattern), 3)
    registry.add(rocky)

    sock = Sheet("item_sock", (16, 16), (8, 8), SOURCE, note="stellar sock, 9 variants")
    for colour in colours:
        for pattern in patterns:
            sock.add(f"{colour}_{pattern}", build_sock(colour, pattern), 3)
    registry.add(sock)

    moon = Sheet("item_moon", (16, 16), (8, 8), SOURCE, note="crescent moon, 9 variants")
    for colour in colours:
        for pattern in patterns:
            moon.add(f"{colour}_{pattern}", [build_moon(colour, pattern)], 3)
    registry.add(moon)

    gas = Sheet("item_gas", (24, 24), (12, 12), SOURCE, note="gas giant, 2-slot weight")
    for colour in colours:
        for pattern in patterns:
            gas.add(f"{colour}_{pattern}", build_gas(colour, pattern), 3)
    registry.add(gas)

    registry.add(
        Sheet("item_core", (32, 32), (16, 16), SOURCE, note="galaxy core, wildcard").add(
            "idle", build_core(), 6
        )
    )

    for size in (16, 24, 32):
        registry.add(
            Sheet(f"item_grime_{size}", (size, size), (size // 2, size // 2), SOURCE,
                  note="grime overlay").add("overlay", [build_grime(size)], 1)
        )

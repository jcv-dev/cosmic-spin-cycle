#!/usr/bin/env python3
"""Feedback effects: sparkle, hit bursts, miss puff, explosion, clean bubbles.

FX are drawn without a sel-out outline on purpose: they sit on top of items and world
art, so a dark ring would read as a hole.  Every effect is hand-placed geometry on a
16 or 32 px grid, with hard edges and a 1 px margin so nothing clips the cell.
"""

from __future__ import annotations

import math

import pxlib
from pxlib import Canvas, Sheet

FAMILY = "fx"
SOURCE = "art/src/fx.py"


# --------------------------------------------------------------------------------------
# fx_clean_sparkle 8x8, 4 frames
# --------------------------------------------------------------------------------------


def sparkle(frame: int) -> Canvas:
    c = Canvas(8, 8)
    cx = cy = 3
    if frame == 0:
        c.set(cx, cy, "metal_4")
        return c
    arms = (1, 2, 3, 2)[frame]
    core = "metal_4" if frame < 3 else "metal_3"
    c.set(cx, cy, core)
    for step in range(1, arms + 1):
        for dx, dy in ((step, 0), (-step, 0), (0, step), (0, -step)):
            x, y = cx + dx, cy + dy
            if 1 <= x <= 6 and 1 <= y <= 6:
                c.set(x, y, "metal_3" if step == arms else core)
    if frame >= 2:
        for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            c.set(cx + dx, cy + dy, "metal_3")
    if frame == 3:
        c.set(cx - 2, cy - 1, "clean_green")
        c.set(cx + 2, cy + 1, "clean_green")
    return c


# --------------------------------------------------------------------------------------
# bursts
# --------------------------------------------------------------------------------------


def burst(size: int, frame: int, frames: int, color: str, fade: str,
          rays: int = 8) -> Canvas:
    c = Canvas(size, size)
    cx = cy = (size - 1) / 2
    progress = frame / max(1, frames - 1)
    radius = 1.6 + progress * (size / 2 - 3.4)
    if frame == 0:
        c.disc(cx, cy, 1.6, "metal_4")
        return c
    for y in range(1, size - 1):
        for x in range(1, size - 1):
            dist = math.hypot(x - cx, y - cy)
            if abs(dist - radius) <= 1.0:
                c.set(x, y, color if dist < radius else fade)
    if progress < 0.8:
        for index in range(rays):
            angle = index * (2 * math.pi / rays) + 0.2
            for step in range(2, int(radius) + 1):
                x = int(round(cx + math.cos(angle) * step))
                y = int(round(cy + math.sin(angle) * step))
                if 0 <= x < size and 0 <= y < size and step > radius - 2:
                    c.set(x, y, color if step > radius - 1 else fade)
    if frame >= frames - 2:
        c.disc(cx, cy, max(0.8, 2.2 - progress * 2), "metal_4")
    return c


# --------------------------------------------------------------------------------------
# miss puff 12x12, 3 frames
# --------------------------------------------------------------------------------------


def miss_puff(frame: int) -> Canvas:
    c = Canvas(12, 12)
    puffs = ((4.5, 8.0, 2.2), (7.0, 6.0, 2.6), (8.5, 9.0, 2.0), (6.0, 9.5, 1.6))
    spread = 0.8 + frame * 1.0
    for index, (px, py, pr) in enumerate(puffs):
        cx = min(10.0, max(1.5, px + (index % 2) * spread - spread / 2))
        cy = min(8.6, max(1.8, py - frame * 0.9))
        c.disc(cx, cy, max(0.8, min(1.8, pr - frame * 0.25)), "metal_1")
        c.set(int(cx), int(cy), "metal_2")
    if frame == 0:
        c.disc(6.0, 7.0, 2.4, "metal_2")
    if frame == 2:
        c.set(3, 3, "metal_0")
        c.set(8, 4, "metal_0")
    return c


# --------------------------------------------------------------------------------------
# explosion 32x32, 6 frames
# --------------------------------------------------------------------------------------


def explosion(frame: int) -> Canvas:
    c = Canvas(32, 32)
    cx = cy = 15.5
    radius = (3.0, 7.0, 11.0, 13.0, 12.0, 9.0)[frame]
    if frame == 0:
        c.disc(cx, cy, 3.0, "yel_4")
        c.disc(cx, cy, 2.0, "metal_4")
        return c
    # fireball rings: yellow core, orange body, then smoke
    if frame <= 3:
        c.disc(cx, cy, radius, "hazard_orange")
        c.disc(cx, cy, radius * 0.72, "yel_2")
        c.disc(cx, cy, radius * 0.40, "yel_3")
        if frame <= 2:
            c.disc(cx, cy, radius * 0.18, "yel_4")
        # debris chunks on the rim
        for index in range(10):
            angle = index * (2 * math.pi / 10) + frame * 0.3
            dist = radius + (1.5 if index % 2 else 0.5)
            x = int(round(cx + math.cos(angle) * dist))
            y = int(round(cy + math.sin(angle) * dist))
            if 0 <= x < 32 and 0 <= y < 32:
                c.set(x, y, "yel_2" if index % 3 else "hazard_orange")
    else:
        # smoke cloud, cooler and darker
        c.disc(cx, cy, radius, "metal_1")
        c.disc(cx - 2, cy - 1, radius * 0.7, "metal_2")
        c.disc(cx + 2, cy + 2, radius * 0.5, "metal_0")
        for index in range(8):
            angle = index * (2 * math.pi / 8)
            x = int(round(cx + math.cos(angle) * (radius + 1)))
            y = int(round(cy + math.sin(angle) * (radius + 1)))
            if 0 <= x < 32 and 0 <= y < 32:
                c.set(x, y, "space_haze")
    return c


# --------------------------------------------------------------------------------------
# bubbles 8x8, 3 frames
# --------------------------------------------------------------------------------------


def bubbles(frame: int) -> Canvas:
    c = Canvas(8, 8)
    spots = ((2, 5, 1.2), (5, 3, 0.9), (4, 6, 0.8))
    for index, (bx, by, br) in enumerate(spots):
        bob = 1 if (index + frame) % 2 else 0
        x, y = bx, by - bob
        c.disc(x, y, br, "metal_3")
        c.set(x, y, "metal_4")
        if br > 1:
            c.set(x + 1, y - 1, "funk_cyan")
    return c


# --------------------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------------------


def build(registry: pxlib.Registry) -> None:
    registry.add(
        Sheet("fx_clean_sparkle", (8, 8), (4, 4), SOURCE,
              note="clean sparkle on delivered items").add(
            "play", [sparkle(i) for i in range(4)], 8, loop=False)
    )

    registry.add(
        Sheet("fx_burst_perfect", (16, 16), (8, 8), SOURCE, note="PERFECT burst").add(
            "play", [burst(16, i, 4, "funk_magenta", "funk_plum") for i in range(4)],
            14, loop=False)
    )

    registry.add(
        Sheet("fx_burst_good", (12, 12), (6, 6), SOURCE, note="GOOD burst").add(
            "play", [burst(12, i, 3, "funk_cyan", "funk_teal", rays=6) for i in range(3)],
            14, loop=False)
    )

    registry.add(
        Sheet("fx_miss_puff", (12, 12), (6, 6), SOURCE, note="MISS puff").add(
            "play", [miss_puff(i) for i in range(3)], 10, loop=False)
    )

    registry.add(
        Sheet("fx_explosion", (32, 32), (16, 16), SOURCE,
              note="washer singularity explosion").add(
            "play", [explosion(i) for i in range(6)], 12, loop=False)
    )

    registry.add(
        Sheet("fx_bubbles", (8, 8), (4, 4), SOURCE, note="bubbles on clean items").add(
            "play", [bubbles(i) for i in range(3)], 8)
    )

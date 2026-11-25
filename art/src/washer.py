#!/usr/bin/env python3
"""mach_washer: 48x48 black-hole washer with six animation states.

Composition: the chassis, porthole and hazard band are authored here with primitives;
the console plate is a real Kenney Industrial Expansion tile (CC0), box-cropped and
luminance-mapped onto the metal ramp so its screws survive at 1:1.  Per-frame colour
budget stays at 8: metal_0..3, space_deep, plus the state accents (yel_2 / clean_green /
hazard_orange) and the drum's funk_teal + funk_cyan.

Pivot is bottom-centre (24, 46): the chassis stands on two feet, the mouth sits at the
bottom edge, matching data/layout.json.
"""

from __future__ import annotations

import numpy as np

import pxlib
from pxlib import Canvas, Sheet

FAMILY = "washer"
SOURCE = "art/src/washer.py"

M = ["metal_0", "metal_1", "metal_2", "metal_3"]
DARK = "space_deep"

CX, CY = 24.0, 30.0


def _console_plate() -> Canvas:
    # real Kenney console plate: screws survive the luminance mapping, but the plate is
    # pushed onto the darker metal slots so it reads as a recess, not a white sticker
    tile = pxlib.load_source("kenney-industrial", "tiles/tile_0085.png").crop((2, 1, 14, 9))
    return pxlib.source_to_canvas(tile, 12, 8, "metal", slots=(0, 1, 1, 2, 3))


_CONSOLE = None


def console_plate() -> Canvas:
    global _CONSOLE
    if _CONSOLE is None:
        _CONSOLE = _console_plate()
    return _CONSOLE


# --------------------------------------------------------------------------------------
# chassis
# --------------------------------------------------------------------------------------


def rounded_body(c: Canvas) -> None:
    x0, y0, x1, y1 = 3, 3, 44, 43
    c.rect(x0 + 1, y0, x1 - x0 - 1, y1 - y0 + 1, M[2])
    c.rect(x0, y0 + 1, x1 - x0 + 1, y1 - y0 - 1, M[2])
    # bevel: lit top/left, shaded bottom/right
    c.hline(x0 + 2, x1 - 2, y0, M[3])
    c.vline(x0, y0 + 2, y1 - 2, M[3])
    c.hline(x0 + 2, x1 - 2, y1, M[1])
    c.vline(x1, y0 + 2, y1 - 2, M[1])
    # corner wedges
    for dx, dy in ((1, 1), (1, 0), (0, 1)):
        c.set(x0 + dx, y0 + dy, M[3] if (dx, dy) != (1, 1) else M[2])
        c.set(x1 - dx, y0 + dy, M[1])
        c.set(x0 + dx, y1 - dy, M[1])
        c.set(x1 - dx, y1 - dy, M[1])
    # plinth: a darker skirt anchors the machine to the floor
    c.rect(x0 + 2, 41, x1 - x0 - 3, 2, M[1])
    c.hline(x0 + 2, x1 - 2, 41, M[0])
    # side seams
    c.vline(x0 + 2, 20, 39, M[1])
    c.vline(x1 - 2, 20, 39, M[1])


def top_panel(c: Canvas, accent: str) -> None:
    # recessed control deck
    c.rect(6, 5, 36, 9, DARK)
    c.hline(6, 41, 5, M[1])
    c.vline(6, 5, 13, M[1])
    # hologram mount: runtime draws ui_holo_icons here
    c.rect(19, 6, 10, 7, DARK, fill=False)
    c.set(19, 6, M[1])
    for x in (20, 24, 28):
        c.set(x, 11, M[0])
    # status lamp
    c.rect(8, 7, 3, 3, accent)
    c.set(8, 7, M[3])


def hazard_band(c: Canvas, stripe: str, gap: str) -> None:
    for y in range(15, 18):
        for x in range(5, 43):
            if (x + (y - 15) * 2) % 8 < 4:
                c.set(x, y, stripe)
            else:
                c.set(x, y, gap)
    c.hline(5, 42, 14, M[1])
    c.hline(5, 42, 18, M[0])


def vent(c: Canvas) -> None:
    for y in (23, 26, 29):
        c.hline(6, 12, y, M[0])
        c.hline(6, 12, y + 1, M[1])


def porthole(c: Canvas, *, water: str, foam: str, glow: str | None, phase: int,
             empty: bool = False, cracked: bool = False) -> None:
    """Bezel, drum, water at the bottom of the drum, foam and a fixed specular arc."""
    # bezel: dark outer lip, lit face, shadowed inner lip
    c.disc(CX, CY, 13.2, M[0])
    c.disc(CX, CY, 12.3, M[1])
    c.arc(CX, CY, 12.7, 1, M[2], np.pi * 0.95, np.pi * 1.70)
    c.arc(CX, CY, 11.5, 1, M[0], np.pi * 1.05, np.pi * 1.70)
    c.disc(CX, CY, 10.8, M[0])
    c.disc(CX, CY, 10.2, DARK)
    # drum back wall
    if not empty:
        for y in range(int(CY - 9), int(CY + 10)):
            for x in range(int(CX - 10), int(CX + 11)):
                if (x - CX) ** 2 + (y - CY) ** 2 <= 92:
                    c.set(x, y, M[0])
        # water fills the bottom of the drum; the surface bobs and ripples per frame
        for y in range(int(CY), int(CY + 11)):
            for x in range(int(CX - 11), int(CX + 12)):
                if (x - CX) ** 2 + (y - CY) ** 2 > 88:
                    continue
                ripple = 0 if (x + phase * 2) % 6 in (0, 1) else 1
                if y >= CY + 1 + ripple:
                    c.set(x, y, water)
        # foam crests on the ripple line
        for x in range(int(CX - 9), int(CX + 10)):
            for y in range(int(CY), int(CY + 3)):
                if (x - CX) ** 2 + (y - CY) ** 2 <= 92 and c.get(x, y) == water:
                    if (x + phase) % 5 == 0:
                        c.set(x, y, foam)
                        c.set(x, y - 1, foam)
        # rotating suds ring, one quadrant per frame
        for index in range(6):
            angle = phase * (np.pi / 2) + index * (np.pi / 3)
            sx = int(CX + np.cos(angle) * 6.5)
            sy = int(CY + np.sin(angle) * 6.5)
            if c.get(sx, sy) in (water, M[0], DARK):
                c.set(sx, sy, foam)
        # drain plug
        c.set(23, 36, M[1])
        c.set(24, 36, M[1])
        if glow:
            c.set(int(CX - 5), int(CY + 6), glow)
            c.set(int(CX + 4), int(CY + 7), glow)
    # glass specular: top-left arc, constant across frames (light never moves)
    for x, y in ((17, 21), (18, 20), (19, 19), (20, 18), (16, 23), (15, 25), (14, 28)):
        c.set(x, y, M[3])
    if cracked:
        for x, y in ((20, 23), (21, 24), (22, 24), (23, 25), (22, 26), (24, 27), (26, 28),
                     (25, 28), (27, 29)):
            c.set(x, y, M[1])
        for x, y in ((21, 23), (24, 26), (26, 29)):
            c.set(x, y, M[3])
    # door hinge + handle
    c.rect(40, 26, 2, 7, M[1])
    c.set(40, 27, M[2])
    c.rect(5, 27, 2, 5, M[1])
    c.set(5, 27, M[3])
    # bezel bolts: one lit pixel each, so they read as hardware rather than dots
    for bx, by in ((15, 21), (32, 21), (15, 39), (32, 39)):
        c.set(bx, by, M[2])
        c.set(bx, by + 1, M[0])


def feet(c: Canvas) -> None:
    c.rect(9, 43, 7, 3, M[1])
    c.rect(32, 43, 7, 3, M[1])
    c.hline(9, 15, 43, M[2])
    c.hline(32, 38, 43, M[2])
    c.hline(9, 15, 45, M[0])
    c.hline(32, 38, 45, M[0])


def smoke(c: Canvas, frame: int) -> None:
    puffs = [(14, 2), (17, 0), (20, 2), (34, 2), (37, 1)]
    for index, (x, y) in enumerate(puffs):
        if (index + frame) % 3 == 0:
            c.set(x, y + 1, M[2])
            c.set(x + 1, y + 1, M[1])
            c.set(x, y, M[3])


# --------------------------------------------------------------------------------------
# states
# --------------------------------------------------------------------------------------


def state_frame(state: str, phase: int) -> Canvas:
    c = Canvas(48, 48)
    accent = {
        "idle": M[3],
        "load_flash": "funk_cyan",
        "washing": "funk_cyan",
        "turbulent": "hazard_orange",
        "done": "clean_green",
        "broken": "hazard_orange",
    }[state]
    rounded_body(c)
    top_panel(c, accent)

    if state == "turbulent":
        hazard_band(c, "hazard_orange", DARK)
    elif state == "broken":
        hazard_band(c, "hazard_orange", M[0])
    else:
        hazard_band(c, "yel_2", DARK)

    vent(c)
    c.blit(console_plate(), 33, 8)
    c.set(34, 9, accent)

    if state == "idle":
        porthole(c, water="space_deep", foam="funk_teal", glow=None, phase=phase)
        c.set(21, 35, "funk_cyan" if phase else "funk_teal")
    elif state == "load_flash":
        porthole(c, water="funk_teal", foam="funk_cyan", glow="funk_cyan", phase=phase + 1)
        # flash rings: brighten the ring for the first two frames
        if phase < 2:
            c.ring(CX, CY, 11.6, 1, "funk_cyan" if phase == 0 else M[3])
    elif state == "washing":
        porthole(c, water="funk_teal", foam="funk_cyan", glow="funk_cyan", phase=phase)
        c.set(12, 20 + phase % 2, M[3])
    elif state == "turbulent":
        porthole(c, water=M[0], foam="hazard_orange", glow="hazard_orange", phase=phase)
        # vibration arcs beside the drum
        for y in range(20, 40, 4):
            c.set(8 + phase % 2, y, "hazard_orange")
            c.set(39 - phase % 2, y + 2, "hazard_orange")
    elif state == "done":
        porthole(c, water="space_deep", foam=M[3], glow=None, phase=phase, empty=True)
        c.set(19, 26, M[3])
        c.set(20, 25, M[3])
        c.set(28, 34, "clean_green")
    elif state == "broken":
        porthole(c, water="space_deep", foam=M[1], glow="hazard_orange", phase=phase,
                 empty=True, cracked=True)
        smoke(c, phase)
    feet(c)
    pxlib.outline(c)
    return c


def build(registry: pxlib.Registry) -> None:
    sheet = Sheet("mach_washer", (48, 48), (24, 46), SOURCE,
                  note="black-hole porthole drum, hazard band, bottom-centre pivot")
    for state, frames, fps, loop in (
        ("idle", 2, 3, True),
        ("load_flash", 3, 18, False),
        ("washing", 4, 8, True),
        ("turbulent", 4, 14, True),
        ("done", 2, 6, True),
        ("broken", 2, 4, True),
    ):
        sheet.add(state, [state_frame(state, i) for i in range(frames)], fps, loop=loop)
    registry.add(sheet)

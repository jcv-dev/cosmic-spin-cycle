#!/usr/bin/env python3
"""UI: hologram requirement icons, panel, stability bar, HUD icons, reticle, logo.

The UI is the loudest surface in the game, so it follows one rule: cool metal frame,
one accent per meaning.  funk_cyan = Pip/rhythm/aim, funk_magenta = PERFECT, clean_green
= clean/done, hazard_orange = turbulent, yellow = solar.  Nothing else gets colour.

The panel is authored as a 9-slice (corner 8): its border strips are uniform so Godot's
NinePatchRect can tile them, and its interior dither tiles on the 8x8 middle cell.
"""

from __future__ import annotations

import math

import pxlib
from pxlib import Canvas, Sheet

FAMILY = "ui"
SOURCE = "art/src/ui.py"

M = ["metal_0", "metal_1", "metal_2", "metal_3", "metal_4"]
DARK = "space_deep"


# --------------------------------------------------------------------------------------
# ui_holo_icons 12x12 — glyph + colour for washer requirements
# --------------------------------------------------------------------------------------

HOLO_COLOURS = {"red": "red_2", "blue": "blue_2", "yellow": "yel_2"}


def holo_colour_icon(colour: str) -> Canvas:
    c = Canvas(12, 12)
    ramp = {"red": "red", "blue": "blue", "yellow": "yel"}[colour]
    edge = pxlib.PAL.ramp(ramp)[1]
    fill = pxlib.PAL.ramp(ramp)[2]
    lite = pxlib.PAL.ramp(ramp)[3]
    if colour == "red":  # triangle
        c.poly([(5.5, 1.5), (10.5, 10.0), (0.5, 10.0)], fill)
        c.line(5.5, 2, 2, 9, lite)
        c.line(5.5, 2, 9, 9, edge)
        c.hline(1, 10, 10, edge)
    elif colour == "blue":  # circle
        c.disc(5.5, 5.5, 4.6, fill)
        c.arc(5.5, 5.5, 4.4, 1, lite, math.pi * 0.9, math.pi * 1.6)
    else:  # square
        c.rect(1, 1, 10, 10, fill)
        c.hline(2, 9, 1, lite)
        c.vline(1, 2, 9, lite)
        c.hline(2, 9, 10, edge)
        c.vline(10, 2, 9, edge)
    return c


def holo_pattern_icon(pattern: str) -> Canvas:
    c = Canvas(12, 12)
    if pattern == "solid":
        c.disc(5.5, 5.5, 4.4, "metal_3")
        c.arc(5.5, 5.5, 4.2, 1, "metal_4", math.pi * 0.9, math.pi * 1.5)
    elif pattern == "ringed":
        c.ring(5.5, 5.5, 4.4, 2, "metal_3")
        c.arc(5.5, 5.5, 4.4, 1, "metal_4", math.pi * 0.9, math.pi * 1.5)
        c.set(5, 5, "metal_1")
    elif pattern == "spotted":
        for x, y, r in ((3, 3, 1.2), (7, 4, 1.0), (5, 7, 1.1)):
            c.disc(x, y, r, "metal_3")
        c.set(3, 2, "metal_4")
    else:  # wild: four point star
        c.poly([(5.5, 0.5), (7.0, 4.0), (10.5, 5.5), (7.0, 7.0),
                (5.5, 10.5), (4.0, 7.0), (0.5, 5.5), (4.0, 4.0)], "funk_cyan")
        c.set(5, 4, "metal_4")
    return c


# --------------------------------------------------------------------------------------
# ui_panel 24x24 (9-slice, corner 8)
# --------------------------------------------------------------------------------------


def panel() -> Canvas:
    c = Canvas(24, 24)
    c.rect(0, 0, 24, 24, "metal_1")
    # uniform border strips: top lit, bottom shaded, sides mid
    c.hline(0, 23, 0, "metal_3")
    c.hline(0, 23, 1, "metal_2")
    c.hline(0, 23, 22, "metal_0")
    c.hline(0, 23, 23, "metal_1")
    c.vline(0, 0, 23, "metal_2")
    c.vline(1, 1, 22, "metal_2")
    c.vline(22, 1, 22, "metal_0")
    c.vline(23, 0, 23, "metal_1")
    # interior: dark with a 2x2 checker that tiles on the 8 px middle
    c.rect(2, 2, 20, 20, "space_mid")
    for y in range(2, 22):
        for x in range(2, 22):
            if (x + y) % 2 == 0:
                c.set(x, y, DARK)
    # corner rivets (inside the 8 px corner, so they survive 9-slice)
    for x, y in ((4, 4), (19, 4), (4, 19), (19, 19)):
        c.set(x, y, "metal_3")
        c.set(x + 1, y, "metal_1")
        c.set(x, y + 1, "metal_1")
    return c


# --------------------------------------------------------------------------------------
# stability bar
# --------------------------------------------------------------------------------------


def bar_frame() -> Canvas:
    c = Canvas(96, 10)
    c.rect(0, 0, 96, 10, "metal_1")
    c.hline(0, 95, 0, "metal_3")
    c.hline(0, 95, 9, "metal_0")
    c.rect(2, 2, 92, 6, DARK)
    # segment ticks every 8 px align with the 8 px fill tile
    for x in range(10, 92, 8):
        c.vline(x, 2, 7, "metal_0")
    # end caps
    c.vline(0, 1, 8, "metal_2")
    c.vline(95, 1, 8, "metal_2")
    c.set(1, 1, "funk_cyan")
    c.set(94, 1, "funk_cyan")
    return c


def bar_fill() -> Canvas:
    """Neutral bright fill tile: the engine tints it green -> orange by threshold."""
    c = Canvas(8, 6)
    c.rect(0, 0, 8, 6, "metal_3")
    c.hline(0, 7, 0, "metal_4")
    c.hline(0, 7, 5, "metal_2")
    c.set(7, 2, "metal_2")
    c.set(7, 3, "metal_2")
    return c


# --------------------------------------------------------------------------------------
# HUD icons 8x8
# --------------------------------------------------------------------------------------


def icon(name: str) -> Canvas:
    c = Canvas(8, 8)
    if name == "clock":
        c.ring(3.5, 3.5, 2.9, 1, "metal_3")
        c.vline(3, 2, 3, "metal_4")
        c.hline(3, 5, 3, "metal_4")
        c.set(3, 3, "metal_2")
        c.set(5, 5, "funk_cyan")
    elif name == "stability":
        # shield
        c.poly([(0.5, 1.0), (6.5, 1.0), (6.5, 4.5), (3.5, 7.0), (0.5, 4.5)], "metal_3")
        c.line(1, 2, 1, 4, "metal_4")
        c.line(1, 4, 3, 6, "metal_2")
        c.set(3, 3, "clean_green")
    else:  # combo: two chevrons
        for offset in (0, 2):
            c.line(2 + offset, 1, 4 + offset, 3, "metal_4")
            c.line(4 + offset, 3, 2 + offset, 5, "metal_3")
            c.set(2 + offset, 2, "funk_cyan")
    return c


# --------------------------------------------------------------------------------------
# reticle
# --------------------------------------------------------------------------------------


def reticle() -> Canvas:
    c = Canvas(16, 16)
    # four corner brackets
    for x0, y0, dx, dy in ((2, 2, 1, 1), (12, 2, -1, 1), (2, 12, 1, -1), (12, 12, -1, -1)):
        for step in range(4):
            c.set(x0 + dx * step, y0, "funk_cyan")
            c.set(x0, y0 + dy * step, "funk_cyan")
        c.set(x0 + dx, y0 + dy, "funk_teal")
    # centre dot + gap cross
    c.set(7, 7, "metal_4")
    c.set(8, 8, "metal_4")
    for step in (2, 3):
        c.set(7, 7 - step, "funk_cyan") if False else None
    c.set(7, 4, "funk_teal")
    c.set(7, 11, "funk_teal")
    c.set(4, 7, "funk_teal")
    c.set(11, 7, "funk_teal")
    return c


# --------------------------------------------------------------------------------------
# logo 160x48
# --------------------------------------------------------------------------------------


def logo() -> Canvas:
    c = Canvas(160, 48)
    # drum mark on the left: a tilted porthole with a spin arrow
    c.disc(25, 24, 15, "metal_1")
    c.disc(25, 24, 13, "metal_2")
    c.arc(25, 24, 14, 1, "metal_3", math.pi * 0.9, math.pi * 1.6)
    c.disc(25, 24, 10, DARK)
    c.disc(25, 24, 7, "funk_cyan")
    c.disc(25, 24, 4, DARK)
    for index in range(6):
        angle = index * (math.pi / 3) + 0.4
        c.set(int(25 + math.cos(angle) * 8.5), int(24 + math.sin(angle) * 8.5), "metal_3")
    c.set(20, 20, "metal_4")
    c.set(21, 20, "metal_4")

    # wordmark
    pxlib.draw_text(c, 45, 8, "COSMIC", "metal_4", scale=2, spacing=1, shadow="metal_1")
    pxlib.draw_text(c, 45, 26, "SPIN CYCLE", "funk_cyan", scale=2, spacing=1,
                    shadow="funk_teal")
    c.hline(45, 45 + pxlib.text_width("SPIN CYCLE", scale=2) - 1, 45, "funk_magenta")
    return c


# --------------------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------------------


def build(registry: pxlib.Registry) -> None:
    holo = Sheet("ui_holo_icons", (12, 12), (6, 6), SOURCE,
                 note="washer requirement holograms")
    for name in ("red", "blue", "yellow"):
        holo.add(name, [holo_colour_icon(name)], 1)
    for name in ("solid", "ringed", "spotted", "wild"):
        holo.add(name, [holo_pattern_icon(name)], 1)
    registry.add(holo)

    registry.add(
        Sheet("ui_panel", (24, 24), (12, 12), SOURCE, allow_edge=True,
              note="9-slice, corner 8").add("panel", [panel()], 1)
    )

    registry.add(
        Sheet("ui_bar_stability", (96, 10), (48, 5), SOURCE, allow_edge=True,
              note="segmented stability frame").add("bar", [bar_frame()], 1)
    )
    registry.add(
        Sheet("ui_bar_stability_fill", (8, 6), (4, 3), SOURCE, allow_edge=True,
              note="neutral fill tile; tinted by threshold").add("fill", [bar_fill()], 1)
    )

    icons = Sheet("ui_icons", (8, 8), (4, 4), SOURCE, note="HUD icons")
    for name in ("clock", "stability", "combo"):
        icons.add(name, [icon(name)], 1)
    registry.add(icons)

    registry.add(
        Sheet("ui_reticle", (16, 16), (8, 8), SOURCE, note="aim crosshair").add(
            "aim", [reticle()], 1)
    )

    registry.add(
        Sheet("ui_logo", (160, 48), (80, 24), SOURCE, allow_edge=True,
              note="COSMIC SPIN CYCLE wordmark").add("logo", [logo()], 1)
    )

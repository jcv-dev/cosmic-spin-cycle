#!/usr/bin/env python3
"""Environment: conveyor belt, dispenser cap, shredder, chute, floor tiles and the room.

The belt, floor and shredder take their *plate language* from the Kenney Industrial
Expansion tiles (CC0) - treadplate seams, rivets, hazard bands - then rebuild it on the
frozen palette so it tiles seamlessly at 16 px and stays under the 8-colour frame budget
(the room is the only asset where that budget is spent on atmosphere instead of detail).

The room is deliberately backless: no belts, washers or chute are baked in.  It provides
the wall, the recessed washer bays, two viewports, the conduit run and the floor base.
"""

from __future__ import annotations

import math

import numpy as np

import pxlib
from pxlib import Canvas, Sheet

FAMILY = "env"
SOURCE = "art/src/env.py"

M = ["metal_0", "metal_1", "metal_2", "metal_3"]


# --------------------------------------------------------------------------------------
# env_belt — 16x16, seamless, scrolls in 4 frames
# --------------------------------------------------------------------------------------

BELT_FRAMES = 4


def belt_frame(step: int) -> Canvas:
    c = Canvas(16, 16)
    c.rect(0, 0, 16, 16, "space_deep")
    # slats: 2 px treads with a 2 px gap, scrolling four pixels per frame (seamless)
    for base in range(0, 16, 4):
        x = (base + step * 4) % 16
        for yy in range(3, 13):
            c.set(x, yy, "metal_1")
            c.set((x + 1) % 16, yy, "metal_0")
        c.set(x, 3, "metal_2")
    # one magnetic stud per tile rides the centre line
    sx = (6 + step * 4) % 16
    c.set(sx, 8, "metal_3")
    # rails top and bottom (rotating the tile keeps them on the belt edge)
    for y, tone in ((0, "metal_2"), (1, "metal_1"), (2, "metal_0"),
                    (13, "metal_0"), (14, "metal_1"), (15, "metal_2")):
        c.hline(0, 15, y, tone)
    return c


# --------------------------------------------------------------------------------------
# env_belt_cap — 16x16, dispenser / portal end
# --------------------------------------------------------------------------------------


def belt_cap() -> Canvas:
    c = Canvas(16, 16)
    c.rect(0, 0, 16, 16, "space_deep")
    # bracket
    c.rect(0, 0, 9, 16, "metal_1")
    c.hline(0, 8, 0, "metal_2")
    c.vline(0, 0, 15, "metal_2")
    c.vline(8, 0, 15, "metal_0")
    c.rect(2, 3, 4, 10, "space_deep")
    c.set(2, 3, "metal_0")
    # portal mouth
    c.disc(10.5, 7.5, 6.2, "metal_1")
    c.disc(10.5, 7.5, 5.0, "space_deep")
    c.disc(10.5, 7.5, 3.6, "funk_cyan")
    c.disc(10.5, 7.5, 2.0, "space_deep")
    c.set(10, 7, "metal_3")
    c.set(9, 6, "metal_3")
    # bolts and rail stubs
    for y in (2, 13):
        c.set(6, y, "metal_2")
    c.hline(0, 15, 0, "metal_2")
    c.hline(0, 15, 1, "metal_1")
    c.hline(0, 15, 15, "metal_2")
    c.hline(0, 15, 14, "metal_1")
    return c


# --------------------------------------------------------------------------------------
# env_shredder — 32x32, grinding teeth, 3 frames
# --------------------------------------------------------------------------------------


def shredder_frame(step: int) -> Canvas:
    c = Canvas(32, 32)
    # funnel body: trapezoid
    c.poly([(7, 14), (25, 14), (22, 27), (10, 27)], "metal_1")
    c.hline(8, 24, 14, "metal_2")
    # vertical ribs
    for x in (12, 16, 20):
        c.vline(x, 16, 26, "metal_0")
    # hazard band across the funnel
    for y in (18, 19, 20):
        for x in range(8, 25):
            if (x + (y - 18) * 2) % 6 < 3:
                c.set(x, y, "yel_2")
            else:
                c.set(x, y, "space_deep")
    # mouth
    c.ellipse(16, 13, 10.5, 5.0, "metal_2")
    c.ellipse(16, 13, 9.0, 3.8, "space_deep")
    c.ellipse(16, 12.4, 8.2, 3.0, "metal_0")
    # grinding teeth rotate one step per frame
    for index in range(6):
        angle = step * (math.pi / 6) + index * (math.pi / 3)
        tx = 16 + math.cos(angle) * 7.2
        ty = 12.4 + math.sin(angle) * 2.5
        c.set(int(round(tx)), int(round(ty)), "metal_3")
        c.set(int(round(tx - math.cos(angle))), int(round(ty - math.sin(angle) * 0.5)), "metal_2")
        c.set(int(round(tx - math.cos(angle) * 2)), int(round(ty - math.sin(angle))), "metal_2")
    # suction dashes at the sides of the intake (never a floating lid)
    for index, (dx, dy) in enumerate(((-12, -2), (-13, 2), (11, -3), (12, 1))):
        if (index + step) % 2 == 0:
            c.set(16 + dx, 12 + dy, "funk_cyan")
            c.set(16 + dx + 1, 12 + dy, "funk_cyan")
    # base and bolts
    c.rect(9, 27, 14, 3, "metal_0")
    c.hline(9, 22, 27, "metal_1")
    for x in (10, 21):
        c.set(x, 25, "metal_3")
    c.set(16, 28, "hazard_orange")
    # one explicit dark outline keeps the frame inside the 8-colour budget
    pxlib.outline(c, color="metal_0")
    return c


# --------------------------------------------------------------------------------------
# env_chute — 32x32, iris hatch
# --------------------------------------------------------------------------------------


def chute_frame(state: str, step: int) -> Canvas:
    c = Canvas(32, 32)
    cx = cy = 16.0
    # hatch ring
    c.disc(cx, cy, 13.2, "metal_0")
    c.disc(cx, cy, 12.4, "metal_1")
    c.disc(cx, cy, 11.6, "metal_2")
    c.arc(cx, cy, 12.0, 1, "metal_3", math.pi * 0.95, math.pi * 1.7)
    c.disc(cx, cy, 10.6, "space_deep")
    # iris petals: four blades retract as the hatch opens
    if state == "closed":
        radii = (10.2, 2.0)
    elif state == "opening":
        radii = (10.2 - step * 2.2, 3.4 + step * 1.4)
    elif state == "open":
        radii = (10.2, 8.7 + step * 0.2)
    else:  # accept
        radii = (10.2, 8.7)
    if state != "open" and state != "accept":
        for blade in range(4):
            start = blade * (math.pi / 2) + math.pi / 4
            for y in range(32):
                for x in range(32):
                    dx, dy = x - cx + 0.5, y - cy + 0.5
                    dist = (dx * dx + dy * dy) ** 0.5
                    if not (radii[1] - 0.2 <= dist <= radii[0]):
                        continue
                    angle = math.atan2(dy, dx) % (2 * math.pi)
                    delta = (angle - start) % (2 * math.pi)
                    if delta < math.pi / 2 - 0.10:
                        c.set(x, y, "metal_1" if dist > radii[1] + 2.4 else "metal_0")
    if state == "closed":
        c.disc(cx, cy, 2.4, "metal_2")
        c.set(15, 15, "metal_3")
        c.set(16, 15, "metal_1")
    if state == "open":
        # open throat: dark well with a cyan lip
        c.disc(cx, cy, 8.5, "space_deep")
        c.ring(cx, cy, 8.6, 1, "funk_cyan")
        c.disc(cx, cy, 6.0, "space_deep")
    if state == "accept":
        c.disc(cx, cy, 8.5, "clean_green")
        c.disc(cx, cy, 7.4, "space_deep")
        for index in range(3):
            angle = step * 1.2 + index * 2.1
            c.set(int(cx + math.cos(angle) * 5.5), int(cy + math.sin(angle) * 5.5),
                  "clean_green")
        c.set(13, 10, "metal_3")
    # bolts on the hatch ring
    for angle in (0.6, 2.2, 3.8, 5.4):
        bx = int(cx + math.cos(angle) * 12.0)
        by = int(cy + math.sin(angle) * 12.0)
        c.set(bx, by, "metal_3")
        c.set(bx, by + 1, "metal_0")
    pxlib.outline(c, color="metal_0")
    return c


# --------------------------------------------------------------------------------------
# env_floor — three 16x16 seamless plates
# --------------------------------------------------------------------------------------


def floor_tile(variant: int) -> Canvas:
    """A quiet, seamless deck plate: dark base, edge seams, rivets, one blemish.

    Low contrast on purpose - the floor must never compete with items.  Authored here
    after the industrial tiles proved too busy at 16 px to tile as a floor.
    """
    c = Canvas(16, 16)
    c.rect(0, 0, 16, 16, "space_deep")
    # plate seams on the tile edges keep the floor seamless
    c.hline(0, 15, 0, "space_mid")
    c.vline(0, 0, 15, "space_mid")
    c.hline(0, 15, 15, "space_mid")
    c.vline(15, 0, 15, "space_mid")
    # rivets at the quarter points
    for x, y in ((3, 3), (11, 3), (3, 11), (11, 11)):
        c.set(x, y, "space_haze")
        c.set(x + 1, y, "space_mid")
        c.set(x, y + 1, "space_mid")
    if variant == 1:
        for dx, dy in ((5, 6), (6, 7), (7, 7), (8, 8), (9, 9)):
            c.set(dx, dy, "space_mid")
        c.set(6, 6, "space_haze")
    elif variant == 2:
        c.rect(9, 9, 5, 5, "space_mid", fill=False)
        c.set(11, 11, "space_haze")
        c.set(10, 10, "metal_0")
    return c


# --------------------------------------------------------------------------------------
# env_room — 320x180 backdrop
# --------------------------------------------------------------------------------------


def porthole(c: Canvas, cx: int, cy: int, radius: int = 15) -> None:
    c.disc(cx, cy, radius, M[1])
    c.disc(cx, cy, radius - 1, M[2])
    c.arc(cx, cy, radius - 0.4, 1, M[3], math.pi * 0.95, math.pi * 1.7)
    c.disc(cx, cy, radius - 2.4, "space_deep")
    # a grey moon inside; the viewport never competes with the items for hue
    c.disc(cx - 1, cy + 1, radius - 7.5, M[1])
    c.disc(cx - 2, cy, radius - 8.5, M[2])
    for x, y in ((cx - 5, cy - 2), (cx - 4, cy - 2), (cx - 4, cy - 1), (cx - 3, cy - 3)):
        c.set(x, y, M[3])
    for x, y in ((cx, cy + 3), (cx + 1, cy + 3), (cx + 1, cy + 4), (cx - 2, cy + 4)):
        c.set(x, y, M[0])
    for x, y in ((cx + 7, cy - 3), (cx - 8, cy + 4), (cx + 6, cy + 6)):
        c.set(x, y, "funk_cyan")
    c.arc(cx, cy, radius - 3.2, 1, M[3], math.pi * 1.1, math.pi * 1.5)


def conduit(c: Canvas) -> None:
    c.hline(0, 319, 3, "metal_0")
    c.hline(0, 319, 4, "metal_1")
    c.hline(0, 319, 5, "metal_0")
    for x in range(16, 320, 48):
        c.rect(x, 2, 3, 5, "metal_2")
        c.set(x, 2, "metal_3")
        c.vline(x + 1, 3, 5, "metal_1")


def wall(c: Canvas) -> None:
    c.rect(0, 6, 320, 86, "metal_1")
    # panel seams every 32 px, with a lit top edge
    for x in range(0, 320, 32):
        c.vline(x, 6, 91, "metal_0")
        c.vline(x + 1, 6, 91, "metal_2")
    c.hline(0, 319, 6, "metal_2")
    # rivets
    for x in range(4, 320, 32):
        for y in (10, 84):
            c.set(x, y, "metal_2")
            c.set(x, y + 1, "metal_0")
    # lower wall shading and the beam that separates wall from floor
    c.rect(0, 88, 320, 4, "metal_0")
    c.hline(0, 319, 88, "metal_2")
    # horizontal wall seam breaks the big panel field
    c.hline(0, 319, 52, "metal_0")
    c.hline(0, 319, 53, "metal_2")
    # vertical pipes at the far edges
    for px in (12, 306):
        c.vline(px, 6, 91, "metal_0")
        c.vline(px + 1, 6, 91, "metal_2")
        c.vline(px + 2, 6, 91, "metal_0")
        for y in (20, 52, 78):
            c.rect(px - 1, y, 5, 2, "metal_1")


def floor(c: Canvas) -> None:
    c.rect(0, 96, 320, 84, "space_deep")
    # plate grid every 32 px, aligned with the 16 px floor tiles (two tiles per plate)
    for y in range(96, 180, 32):
        c.hline(0, 319, y, "space_mid")
    for x in range(0, 320, 32):
        c.vline(x, 96, 179, "space_mid")
    for x in range(16, 320, 32):
        for y in (112, 144):
            c.set(x, y, "metal_0")
    # a single dark row under the beam settles the room
    c.hline(0, 319, 96, "space_void")
    # two neon tubes along the beam lip, with dark gaps at the ends
    for x0, x1 in ((36, 124), (196, 284)):
        c.hline(x0, x1, 93, "funk_cyan")
        c.set(x0, 92, "metal_1")
        c.set(x1, 92, "metal_1")


def neon_sign(c: Canvas) -> None:
    x, y = 148, 14
    pxlib.draw_text(c, x + 1, y + 1, "SPIN", "metal_0")
    pxlib.draw_text(c, x, y, "SPIN", "funk_cyan")
    c.hline(x, x + pxlib.text_width("SPIN") - 1, y + 8, "funk_cyan")
    c.hline(x, x + pxlib.text_width("SPIN") - 1, y + 9, "metal_0")


def room() -> Canvas:
    c = Canvas(320, 180)
    c.rect(0, 0, 320, 180, "space_void")
    wall(c)
    conduit(c)
    floor(c)
    # recessed bays last: nothing paints across them
    for bx in (36, 236):
        for by in (32, 96):
            c.rect(bx, by, 48, 48, "space_mid")
            c.hline(bx, bx + 47, by, "metal_0")
            c.vline(bx, by, by + 47, "metal_0")
            c.hline(bx, bx + 47, by + 47, "space_void")

    porthole(c, 106, 30)
    porthole(c, 214, 30)
    neon_sign(c)
    # vignette: a one pixel void frame keeps the play area reading as a lit stage
    c.rect(0, 0, 320, 180, "space_void", fill=False)
    for x, y in ((320 - 2, 0), (320 - 1, 0), (0, 179), (1, 179)):
        c.set(x, y, "space_void")
    return c


# --------------------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------------------


def build(registry: pxlib.Registry) -> None:
    belt = Sheet("env_belt", (16, 16), (8, 8), SOURCE, allow_edge=True,
                 note="seamless, rotates in 90 degree steps")
    belt.add("scroll", [belt_frame(i) for i in range(BELT_FRAMES)], 8)
    registry.add(belt)

    registry.add(
        Sheet("env_belt_cap", (16, 16), (8, 8), SOURCE, allow_edge=True,
              note="dispenser / portal end").add("start", [belt_cap()], 1)
    )

    registry.add(
        Sheet("env_shredder", (32, 32), (16, 30), SOURCE,
              note="vacuum shredder at the belt end").add(
            "idle", [shredder_frame(i) for i in range(3)], 8)
    )

    chute = Sheet("env_chute", (32, 32), (16, 16), SOURCE, note="pneumatic iris hatch")
    chute.add("closed", [chute_frame("closed", 0)], 1)
    chute.add("opening", [chute_frame("opening", i) for i in range(3)], 12, loop=False)
    chute.add("open", [chute_frame("open", i) for i in range(2)], 6)
    chute.add("accept", [chute_frame("accept", i) for i in range(3)], 12, loop=False)
    registry.add(chute)

    floors = Sheet("env_floor", (16, 16), (8, 8), SOURCE, allow_edge=True,
                   note="three subtle variants, seamless")
    for index, name in enumerate(("variant_a", "variant_b", "variant_c")):
        floors.add(name, [floor_tile(index)], 1)
    registry.add(floors)

    registry.add(
        Sheet("env_room", (320, 180), (160, 90), SOURCE, allow_edge=True,
              note="wall, bays, viewports, conduit and floor base; no props baked in").add(
            "bg", [room()], 1)
    )

#!/usr/bin/env python3
"""char_pip: the interdimensional janitor, 24x24, 12 animations (4 x 3 directions).

Pip is hand-authored with primitives: no CC0 character survived inspection at this scale
and in this palette (docs/PROVENANCE.md).  The whole sheet is parametric - one body plan,
pose offsets per frame - so the 30 frames never drift in proportion.

Design rules
------------
* Big helmet, short body, oversized gravity gloves: silhouette first at 1x.
* Light from the top-left on every part; every part has a lit top/left edge.
* funk_cyan is reserved for the gloves and the visor glint, so the player's eye lands on
  the part of the character that does the work.
* Feet sit on y=21, pivot is (12, 22); the side strip faces right and is mirrored in
  engine for the left-facing pose.
"""

from __future__ import annotations

import pxlib
from pxlib import Canvas, Sheet

FAMILY = "pip"
SOURCE = "art/src/pip.py"

M = ["metal_0", "metal_1", "metal_2", "metal_3"]
DARK = "space_deep"
CYAN = "funk_cyan"
TEAL = "funk_teal"


# --------------------------------------------------------------------------------------
# parts  (proportions: head 8x8, torso 8x7, legs 3 px wide, gloves 3x3)
# --------------------------------------------------------------------------------------


def head_down(c: Canvas, x: int, y: int) -> None:
    c.rect(x + 1, y, 6, 8, M[2])
    c.rect(x, y + 1, 8, 6, M[2])
    c.hline(x + 2, x + 5, y, M[3])
    c.hline(x + 1, x + 6, y + 1, M[3])
    c.vline(x, y + 2, y + 5, M[3])
    c.vline(x + 7, y + 2, y + 6, M[1])
    c.hline(x + 1, x + 6, y + 7, M[1])
    c.rect(x + 1, y + 3, 6, 4, DARK)
    c.hline(x + 2, x + 5, y + 3, TEAL)
    c.set(x + 2, y + 4, CYAN)
    c.set(x + 1, y + 2, M[1])
    c.set(x + 6, y + 2, M[1])


def head_side(c: Canvas, x: int, y: int) -> None:
    c.rect(x + 1, y, 6, 8, M[2])
    c.rect(x, y + 1, 8, 6, M[2])
    c.hline(x + 2, x + 5, y, M[3])
    c.hline(x + 1, x + 6, y + 1, M[3])
    c.vline(x, y + 2, y + 5, M[3])
    c.vline(x + 7, y + 2, y + 6, M[1])
    c.hline(x + 1, x + 6, y + 7, M[1])
    c.rect(x + 3, y + 3, 5, 4, DARK)
    c.hline(x + 4, x + 7, y + 3, TEAL)
    c.set(x + 5, y + 4, CYAN)
    c.set(x + 7, y + 4, M[1])


def head_back(c: Canvas, x: int, y: int) -> None:
    c.rect(x + 1, y, 6, 8, M[2])
    c.rect(x, y + 1, 8, 6, M[2])
    c.hline(x + 2, x + 5, y, M[3])
    c.hline(x + 1, x + 6, y + 1, M[3])
    c.vline(x, y + 2, y + 5, M[3])
    c.vline(x + 7, y + 2, y + 6, M[1])
    c.hline(x + 1, x + 6, y + 7, M[1])
    c.vline(x + 4, y + 1, y + 6, M[1])
    for yy in (y + 3, y + 4):
        c.set(x + 3, yy, TEAL)
        c.set(x + 5, yy, TEAL)


def torso(c: Canvas, x: int, y: int, w: int, h: int, *, pack: bool = False) -> None:
    c.rect(x, y, w, h, M[2])
    c.hline(x + 1, x + w - 2, y, M[3])
    c.vline(x, y + 1, y + h - 2, M[3])
    c.vline(x + w - 1, y + 1, y + h - 1, M[1])
    c.hline(x + 1, x + w - 2, y + h - 1, M[1])
    # belt line separates torso from legs
    c.hline(x + 1, x + w - 2, y + h - 1, M[0])
    if pack:
        c.rect(x + 1, y + 1, w - 2, h - 3, M[1])
        c.hline(x + 2, x + w - 3, y + 1, M[0])
        c.set(x + 2, y + 2, TEAL)
        c.set(x + w - 3, y + 2, TEAL)
        c.set(x + w // 2, y + h - 3, CYAN)
    else:
        # chest badge + zip
        c.set(x + w // 2, y + 2, TEAL)
        c.set(x + w // 2, y + 3, CYAN)
        c.vline(x + w // 2, y + 4, y + h - 3, M[1])


def arm(c: Canvas, x: int, y: int, length: int, glove_dir: int = 1) -> None:
    """A 2 px arm anchored at the shoulder (x, y) with a 3x3 glove at its end.

    ``glove_dir`` = 1 hangs the arm down, -1 raises it: the arm always stays attached to
    the shoulder, only its length and glove position change.
    """
    if glove_dir > 0:
        c.rect(x, y, 2, length, M[1])
        c.vline(x, y, y + length - 1, M[2])
        gy = y + length
    else:
        c.rect(x, y - length, 2, length, M[1])
        c.vline(x, y - length, y - 1, M[2])
        gy = y - length - 3
    c.rect(x - 1, gy, 4, 3, CYAN)
    c.set(x - 1, gy + 2, TEAL)
    c.set(x, gy + 2, TEAL)
    c.set(x + 2, gy, TEAL)


def leg(c: Canvas, x: int, y: int, length: int, *, boot_dx: int = 0) -> None:
    c.rect(x, y, 3, length, M[1])
    c.vline(x, y, y + length - 1, M[2])
    by = y + length
    c.rect(x + boot_dx, by, 4, 2, M[0])
    c.hline(x + boot_dx, x + boot_dx + 3, by, M[1])
    c.set(x + boot_dx, by + 1, M[1])


# --------------------------------------------------------------------------------------
# down / up
# --------------------------------------------------------------------------------------


def draw_front(pose: dict, up: bool = False) -> Canvas:
    c = Canvas(24, 24)
    hdy = pose.get("head_dy", 0)
    tdy = pose.get("torso_dy", 0)
    if up:
        head_back(c, 8, 2 + hdy)
    else:
        head_down(c, 8, 2 + hdy)
    torso(c, 8, 10 + tdy, 8, 7, pack=up)

    for sx, glove_dir, length in pose.get("arms", ((-1, 1, 5), (1, 1, 5))):
        if sx < 0:
            arm(c, 5, 11 + tdy, length, glove_dir)
        else:
            arm(c, 17, 11 + tdy, length, glove_dir)

    for index, (dx, dy) in enumerate(pose.get("legs", ((0, 0), (0, 0)))):
        lx = 8 + index * 5 + dx
        leg(c, lx, 17 + tdy, 3 + dy)
    pxlib.outline(c)
    return c


# --------------------------------------------------------------------------------------
# side (facing right)
# --------------------------------------------------------------------------------------


def draw_side(pose: dict) -> Canvas:
    c = Canvas(24, 24)
    hdy = pose.get("head_dy", 0)
    tdy = pose.get("torso_dy", 0)
    # backpack first (behind the body)
    c.rect(6, 11 + tdy, 3, 5, M[1])
    c.set(6, 11 + tdy, M[2])
    c.set(7, 15 + tdy, TEAL)
    head_side(c, 8, 2 + hdy)
    torso(c, 8, 10 + tdy, 7, 7)
    far = pose.get("far_arm", (0, 1, 5))
    arm(c, 7 + far[0], 11 + tdy, far[2], far[1])
    front, back = pose.get("side_legs", ((0, 4), (0, 4)))
    leg(c, 11 + front[0], 17 + tdy, min(3, front[1]), boot_dx=1)
    leg(c, 8 + back[0], 17 + tdy, min(3, back[1]))
    near = pose.get("near_arm", (2, 1, 5))
    arm(c, 13 + near[0], 11 + tdy, near[2], near[1])
    pxlib.outline(c)
    return c


# --------------------------------------------------------------------------------------
# poses
# --------------------------------------------------------------------------------------

FRONT_POSES = {
    "idle": [
        dict(arms=((-1, 1, 5), (1, 1, 5))),
        dict(head_dy=1, torso_dy=0, arms=((-1, 1, 4), (1, 1, 4))),
    ],
    "run": [
        dict(legs=((0, 0), (0, -1)), arms=((-1, 1, 4), (1, 1, 5))),
        dict(head_dy=1, legs=((0, -1), (0, 0)), arms=((-1, 1, 5), (1, 1, 4))),
        dict(legs=((0, 0), (0, -1)), arms=((-1, 1, 4), (1, 1, 5))),
        dict(head_dy=1, legs=((0, -1), (0, 0)), arms=((-1, 1, 5), (1, 1, 4))),
    ],
    "throw": [
        dict(head_dy=1, torso_dy=0, arms=((-1, -1, 3), (1, -1, 3))),
        dict(head_dy=0, torso_dy=0, arms=((-1, 1, 3), (1, 1, 3))),
    ],
    "strike": [
        dict(head_dy=1, arms=((-1, -1, 4), (1, -1, 4))),
        dict(head_dy=1, torso_dy=0, arms=((-1, 1, 5), (1, 1, 5))),
    ],
}

SIDE_POSES = {
    "idle": [
        dict(),
        dict(head_dy=1, near_arm=(2, 1, 4)),
    ],
    "run": [
        dict(side_legs=((1, 4), (-1, 3)), near_arm=(1, 1, 4), far_arm=(-1, 1, 4)),
        dict(side_legs=((0, 3), (0, 4)), near_arm=(2, 1, 5), far_arm=(0, 1, 3), head_dy=1),
        dict(side_legs=((-1, 3), (1, 4)), near_arm=(0, 1, 4), far_arm=(1, 1, 5)),
        dict(side_legs=((0, 4), (0, 3)), near_arm=(2, 1, 3), far_arm=(0, 1, 5), head_dy=1),
    ],
    "throw": [
        dict(near_arm=(-3, -1, 3), far_arm=(-1, 1, 3), head_dy=1),
        dict(near_arm=(3, 1, 3), far_arm=(0, 1, 4), head_dy=0, torso_dy=0),
    ],
    "strike": [
        dict(near_arm=(0, -1, 4), far_arm=(0, -1, 3), head_dy=1),
        dict(near_arm=(3, 1, 4), far_arm=(1, 1, 4), head_dy=1, torso_dy=0),
    ],
}


def build(registry: pxlib.Registry) -> None:
    sheet = Sheet("char_pip", (24, 24), (12, 22), SOURCE,
                  note="gravity gloves in funk_cyan; side strip faces right")
    for direction, poses in (("down", FRONT_POSES), ("side", SIDE_POSES),
                             ("up", FRONT_POSES)):
        for anim in ("idle", "run", "throw", "strike"):
            frames = []
            for pose in poses[anim]:
                if direction == "side":
                    frames.append(draw_side(pose))
                else:
                    frames.append(draw_front(pose, up=(direction == "up")))
            fps = {"idle": 4, "run": 10, "throw": 18, "strike": 18}[anim]
            loop = anim in ("idle", "run")
            sheet.add(f"{anim}_{direction}", frames, fps, loop=loop)
    registry.add(sheet)

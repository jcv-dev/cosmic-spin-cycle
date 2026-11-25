#!/usr/bin/env python3
"""pxlib — deterministic, palette-strict pixel art primitives for Cosmic Spin Cycle.

Everything here is integer-only pixel work: no anti-aliasing, no gradients, no alpha
blending, no floating-point resampling in the final art (sources are quantised onto a
5-step ramp first).  Coordinates are art pixels, origin top-left, y down.

The palette in ``art/palette.json`` is the single source of truth.  ``Canvas.set``
raises ``PaletteError`` for any colour that is not in it, so a builder cannot ship an
off-palette pixel by accident.

Typical use::

    c = Canvas(16, 16)
    shade_sphere(c, 8, 8, 6, "red")
    outline(c)
    Sheet("item_rocky", (16, 16), (8, 8), "art/src/items.py").add("red_solid", [c, c2], 3)
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PALETTE_PATH = ROOT / "art" / "palette.json"
SPRITES_DIR = ROOT / "assets" / "sprites"
SOURCES_DIR = ROOT / "art" / "sources"

TRANSPARENT = (0, 0, 0, 0)

#: Ramp families: index 0 is the darkest (used for sel-out), index 4 the highlight.
RAMPS = ("space", "metal", "red", "blue", "yel")

#: Item colour names (GDD: red/blue/yellow) -> palette ramp names.
COLOUR_FAMILY = {"red": "red", "blue": "blue", "yellow": "yel"}

#: Accent -> the darkest palette colour used for its selective outline.
ACCENT_OUTLINE = {
    # accents hue-shift to a deep space shadow for their 1 px sel-out (palette rule 4/5)
    "funk_cyan": "space_deep",
    "funk_teal": "space_deep",
    "funk_magenta": "funk_plum",
    "funk_plum": "space_deep",
    "clean_green": "space_deep",
    "hazard_orange": "yel_0",
}


class PaletteError(ValueError):
    """Raised when an operation would introduce a colour outside the 30-colour palette."""


class _Palette:
    def __init__(self, path: Path = PALETTE_PATH) -> None:
        data = json.loads(path.read_text(encoding="utf-8"))
        self.colors: dict[str, tuple[int, int, int]] = {}
        self.order: list[str] = []
        for entry in data["colors"]:
            name = entry["name"]
            self.colors[name] = hex_to_rgb(entry["hex"])
            self.order.append(name)
        self.rgb_to_name = {rgb: name for name, rgb in self.colors.items()}
        # the space family has four named steps (void, deep, mid, haze); the fifth slot
        # repeats haze so a 5-step lookup never falls off the ramp
        self.ramps = {
            family: [f"{family}_{i}" for i in range(5)]
            for family in ("metal", "red", "blue", "yel")
        }
        self.ramps["space"] = ["space_void", "space_deep", "space_mid", "space_haze",
                               "space_haze"]
        self.accents = [
            n for n in self.order if not any(n.startswith(f + "_") for f in RAMPS)
        ]
        self.name_to_slot = {}
        for members in self.ramps.values():
            for slot, color in enumerate(members):
                self.name_to_slot.setdefault(color, slot)
        self.name_to_ramp = {
            color: family for family, members in self.ramps.items() for color in members
        }

    def rgb(self, color: str | tuple[int, int, int]) -> tuple[int, int, int]:
        if isinstance(color, tuple):
            if color not in self.rgb_to_name:
                raise PaletteError(f"RGB {color} is not in art/palette.json")
            return color
        try:
            return self.colors[color]
        except KeyError as exc:
            raise PaletteError(f"unknown palette colour {color!r}") from exc

    def ramp(self, family: str) -> list[str]:
        family = COLOUR_FAMILY.get(family, family)
        if family not in self.ramps:
            raise PaletteError(f"unknown ramp {family!r}")
        return self.ramps[family]

    def darkest(self, color: str) -> str:
        if color in self.name_to_ramp:
            return self.ramps[self.name_to_ramp[color]][0]
        if color in ACCENT_OUTLINE:
            return ACCENT_OUTLINE[color]
        if color.startswith("space_"):
            return "space_void"
        raise PaletteError(f"{color!r} has no selective outline colour")

    def is_ramp(self, color: str) -> bool:
        return color in self.name_to_ramp

    def ramp_family(self, color: str) -> str:
        return self.name_to_ramp[color]


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    return "#%02X%02X%02X" % rgb


def relative_luminance(rgb: tuple[int, int, int]) -> float:
    """WCAG relative luminance, used by the linter's 3:1 contrast rule."""
    channels = []
    for value in rgb:
        c = value / 255.0
        channels.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


PAL = _Palette()


def contrast_vs_void(color: str) -> float:
    a = relative_luminance(PAL.rgb(color)) + 0.05
    b = relative_luminance(PAL.rgb("space_void")) + 0.05
    return max(a, b) / min(a, b)


# --------------------------------------------------------------------------------------
# Canvas
# --------------------------------------------------------------------------------------


class Canvas:
    """An RGBA pixel buffer that only accepts palette colours and binary alpha."""

    __slots__ = ("w", "h", "buf")

    def __init__(self, w: int, h: int, fill: str | None = None) -> None:
        if w <= 0 or h <= 0:
            raise ValueError("canvas must be at least 1x1")
        self.w, self.h = int(w), int(h)
        self.buf = np.zeros((self.h, self.w, 4), dtype=np.uint8)
        if fill is not None:
            self.buf[:, :, :3] = PAL.rgb(fill)
            self.buf[:, :, 3] = 255

    # -- construction -------------------------------------------------------------
    @classmethod
    def from_array(cls, array: np.ndarray) -> "Canvas":
        if array.ndim != 3 or array.shape[2] != 4:
            raise ValueError("expected HxWx4 RGBA array")
        c = cls(array.shape[1], array.shape[0])
        c.buf = array.astype(np.uint8).copy()
        c._validate()
        return c

    @classmethod
    def from_image(cls, image: Image.Image, *, quantise: bool = True) -> "Canvas":
        image = image.convert("RGBA")
        arr = np.array(image, dtype=np.uint8)
        if quantise:
            arr = _quantise_array(arr)
        return cls.from_array(arr)

    def copy(self) -> "Canvas":
        return Canvas.from_array(self.buf.copy())

    # -- validation ---------------------------------------------------------------
    def _validate(self) -> None:
        alpha = self.buf[:, :, 3]
        if not np.isin(alpha, (0, 255)).all():
            bad = sorted({int(v) for v in np.unique(alpha) if v not in (0, 255)})
            raise PaletteError(f"semi-transparent alpha values present: {bad}")
        solid = alpha == 255
        if not solid.any():
            return
        rgb = self.buf[:, :, :3][solid]
        uniq = np.unique(rgb.reshape(-1, 3), axis=0)
        for value in uniq:
            key = (int(value[0]), int(value[1]), int(value[2]))
            if key not in PAL.rgb_to_name:
                raise PaletteError(f"off-palette colour {rgb_to_hex(key)}")

    def colors(self) -> list[str]:
        solid = self.buf[:, :, 3] == 255
        uniq = np.unique(self.buf[:, :, :3][solid].reshape(-1, 3), axis=0)
        return [PAL.rgb_to_name[(int(r), int(g), int(b))] for r, g, b in uniq]

    # -- primitives ---------------------------------------------------------------
    def set(self, x: int, y: int, color: str) -> None:
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.buf[y, x, :3] = PAL.rgb(color)
            self.buf[y, x, 3] = 255

    def clear_at(self, x: int, y: int) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.buf[y, x] = TRANSPARENT

    def get(self, x: int, y: int) -> str | None:
        if not (0 <= x < self.w and 0 <= y < self.h):
            return None
        if self.buf[y, x, 3] == 0:
            return None
        r, g, b = (int(v) for v in self.buf[y, x, :3])
        return PAL.rgb_to_name[(r, g, b)]

    def hline(self, x0: int, x1: int, y: int, color: str) -> None:
        for x in range(min(x0, x1), max(x0, x1) + 1):
            self.set(x, y, color)

    def vline(self, x: int, y0: int, y1: int, color: str) -> None:
        for y in range(min(y0, y1), max(y0, y1) + 1):
            self.set(x, y, color)

    def rect(self, x: int, y: int, w: int, h: int, color: str, *, fill: bool = True) -> None:
        if fill:
            for yy in range(y, y + h):
                for xx in range(x, x + w):
                    self.set(xx, yy, color)
        else:
            self.hline(x, x + w - 1, y, color)
            self.hline(x, x + w - 1, y + h - 1, color)
            self.vline(x, y, y + h - 1, color)
            self.vline(x + w - 1, y, y + h - 1, color)

    def line(self, x0: int, y0: int, x1: int, y1: int, color: str) -> None:
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.set(x0, y0, color)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def disc(self, cx: float, cy: float, r: float, color: str) -> None:
        """Filled circle, pixel-centre test (no anti-aliasing)."""
        r2 = (r + 0.15) ** 2
        for y in range(int(math.floor(cy - r - 1)), int(math.ceil(cy + r + 1)) + 1):
            for x in range(int(math.floor(cx - r - 1)), int(math.ceil(cx + r + 1)) + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r2:
                    self.set(x, y, color)

    def ellipse(self, cx: float, cy: float, rx: float, ry: float, color: str) -> None:
        for y in range(int(math.floor(cy - ry - 1)), int(math.ceil(cy + ry + 1)) + 1):
            for x in range(int(math.floor(cx - rx - 1)), int(math.ceil(cx + rx + 1)) + 1):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    self.set(x, y, color)

    def ring(self, cx: float, cy: float, r: float, thickness: int, color: str) -> None:
        inner = (r - thickness + 0.4) ** 2
        outer = (r + 0.3) ** 2
        for y in range(int(math.floor(cy - r - 1)), int(math.ceil(cy + r + 1)) + 1):
            for x in range(int(math.floor(cx - r - 1)), int(math.ceil(cx + r + 1)) + 1):
                d2 = (x - cx) ** 2 + (y - cy) ** 2
                if inner <= d2 <= outer:
                    self.set(x, y, color)

    def arc(self, cx: float, cy: float, r: float, thickness: int, color: str,
            a0: float, a1: float) -> None:
        """Arc from a0 to a1 radians (0 = east, clockwise in screen space)."""
        for y in range(int(math.floor(cy - r - 1)), int(math.ceil(cy + r + 1)) + 1):
            for x in range(int(math.floor(cx - r - 1)), int(math.ceil(cx + r + 1)) + 1):
                d = math.hypot(x - cx, y - cy)
                if not (r - thickness + 0.4 <= d <= r + 0.3):
                    continue
                angle = math.atan2(y - cy, x - cx) % (2 * math.pi)
                if _angle_in(angle, a0, a1):
                    self.set(x, y, color)

    def poly(self, points: list[tuple[float, float]], color: str) -> None:
        """Scanline-filled convex/concave polygon (even-odd rule)."""
        if len(points) < 3:
            return
        ys = [p[1] for p in points]
        for y in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
            hits: list[float] = []
            for i in range(len(points)):
                x0, y0 = points[i]
                x1, y1 = points[(i + 1) % len(points)]
                if (y0 <= y < y1) or (y1 <= y < y0):
                    t = (y - y0) / (y1 - y0)
                    hits.append(x0 + t * (x1 - x0))
            hits.sort()
            for i in range(0, len(hits) - 1, 2):
                for x in range(int(math.ceil(hits[i])), int(math.floor(hits[i + 1])) + 1):
                    self.set(x, y, color)

    # -- composition --------------------------------------------------------------
    def blit(self, src: "Canvas", dx: int, dy: int) -> None:
        for y in range(src.h):
            for x in range(src.w):
                if src.buf[y, x, 3]:
                    self.buf[dy + y, dx + x] = src.buf[y, x]

    def blit_mask(self, mask: np.ndarray, dx: int, dy: int, color: str) -> None:
        ys, xs = np.nonzero(mask)
        for y, x in zip(ys, xs):
            self.set(dx + int(x), dy + int(y), color)

    def flip_x(self) -> "Canvas":
        out = self.copy()
        out.buf = np.ascontiguousarray(out.buf[:, ::-1])
        return out

    def flip_y(self) -> "Canvas":
        out = self.copy()
        out.buf = np.ascontiguousarray(out.buf[::-1])
        return out

    def rotate90(self, times: int = 1) -> "Canvas":
        arr = self.buf
        for _ in range(times % 4):
            arr = np.rot90(arr, k=-1)  # clockwise
        return Canvas.from_array(np.ascontiguousarray(arr))

    def crop(self, x: int, y: int, w: int, h: int) -> "Canvas":
        out = Canvas(w, h)
        for yy in range(h):
            for xx in range(w):
                sx, sy = x + xx, y + yy
                if 0 <= sx < self.w and 0 <= sy < self.h:
                    out.buf[yy, xx] = self.buf[sy, sx]
        return out

    def crop_content(self) -> "Canvas":
        mask = self.mask()
        if not mask.any():
            return Canvas(1, 1)
        ys, xs = np.nonzero(mask)
        return self.crop(int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1),
                         int(ys.max() - ys.min() + 1))

    def pad(self, w: int, h: int, dx: int = 0, dy: int = 0) -> "Canvas":
        out = Canvas(w, h)
        out.blit(self, dx, dy)
        return out

    def mask(self) -> np.ndarray:
        return self.buf[:, :, 3] == 255

    def recolor(self, mapping: dict[str, str]) -> "Canvas":
        out = self.copy()
        for y in range(self.h):
            for x in range(self.w):
                if out.buf[y, x, 3]:
                    name = PAL.rgb_to_name[tuple(int(v) for v in out.buf[y, x, :3])]
                    if name in mapping:
                        out.buf[y, x, :3] = PAL.rgb(mapping[name])
        return out

    def replace(self, old: str, new: str) -> "Canvas":
        return self.recolor({old: new})

    def erase(self, color: str) -> "Canvas":
        out = self.copy()
        target = np.array(PAL.rgb(color), dtype=np.uint8)
        hit = (out.buf[:, :, :3] == target).all(axis=2) & (out.buf[:, :, 3] == 255)
        out.buf[hit] = TRANSPARENT
        return out

    def keyset(self) -> set[str]:
        return set(self.colors())

    def trimmed_to(self, w: int, h: int) -> "Canvas":
        """Crop to content, then centre-pad into a w x h cell."""
        content = self.crop_content()
        if content.w > w or content.h > h:
            content = content.crop(0, 0, min(content.w, w), min(content.h, h))
        out = Canvas(w, h)
        out.blit(content, (w - content.w) // 2, (h - content.h) // 2)
        return out

    def image(self) -> Image.Image:
        return Image.fromarray(self.buf, mode="RGBA")

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self._validate()
        self.image().save(path, format="PNG", optimize=False, compress_level=9)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"Canvas({self.w}x{self.h}, {len(self.colors())} colours)"


# --------------------------------------------------------------------------------------
# palette / array helpers
# --------------------------------------------------------------------------------------


def _angle_in(angle: float, a0: float, a1: float) -> bool:
    two_pi = 2 * math.pi
    a0 %= two_pi
    a1 %= two_pi
    if a0 <= a1:
        return a0 <= angle <= a1
    return angle >= a0 or angle <= a1


def _quantise_array(arr: np.ndarray) -> np.ndarray:
    """Snap an RGBA array to the nearest palette colour; alpha becomes 0 or 255."""
    rgb = arr[:, :, :3].astype(np.int32)
    alpha = arr[:, :, 3]
    names = list(PAL.colors)
    lut = np.array([PAL.colors[n] for n in names], dtype=np.int32)
    # Distance in a perceptual-ish space: weight green more, blue a little less.
    flat = rgb.reshape(-1, 3)
    dist = (
        ((flat[:, None, :] - lut[None, :, :]) ** 2)
        * np.array([2, 4, 3], dtype=np.int32)
    ).sum(axis=2)
    nearest = dist.argmin(axis=1)
    out = np.zeros_like(arr)
    out[:, :, :3] = lut[nearest].reshape(rgb.shape)
    out[:, :, 3] = np.where(alpha >= 128, 255, 0)
    out[out[:, :, 3] == 0] = TRANSPARENT
    return out


def load_image(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def load_source(pack: str, rel: str) -> Image.Image:
    """Load a committed source file, e.g. load_source("kenney-planets", "planets/planet03.png")."""
    path = SOURCES_DIR / pack / rel
    if not path.exists():
        raise FileNotFoundError(
            f"missing source {path}; run python3 tools/fetch_sources.py"
        )
    return load_image(path)


def ramp_values(family: str) -> list[str]:
    return PAL.ramp(family)


def ramp_swap_family(canvas: Canvas, family: str) -> Canvas:
    """Map every ramp-coloured pixel of `canvas` onto `family`, preserving the slot."""
    family = COLOUR_FAMILY.get(family, family)
    mapping: dict[str, str] = {}
    for color in canvas.keyset():
        if PAL.is_ramp(color):
            slot = PAL.name_to_slot[color]
            mapping[color] = PAL.ramp(family)[slot]
    return canvas.recolor(mapping)


# --------------------------------------------------------------------------------------
# shading
# --------------------------------------------------------------------------------------


def shade_sphere(
    canvas: Canvas,
    cx: float,
    cy: float,
    r: float,
    family: str,
    *,
    light: tuple[float, float] = (-0.55, -0.72),
    bands: tuple[float, ...] = (0.18, 0.42, 0.66, 0.86),
    rim: bool = True,
    rim_start: float = 0.32,
    squash: float = 1.0,
) -> None:
    """Banded, hard-edged sphere shading in a 5-step ramp (light from the top-left).

    ``bands`` are normalised light thresholds for slots 1..4; pixels dimmer than
    ``bands[0]`` get slot 0.  With ``rim`` the last 2 px of the silhouette fall back to
    slot 1 so the shape reads against the background.
    """
    colors = PAL.ramp(family)
    lx, ly = light
    norm = math.sqrt(lx * lx + ly * ly + 0.55 ** 2)
    lx, ly, lz = lx / norm, ly / norm, 0.55 / norm
    ry = r * squash
    for y in range(int(math.floor(cy - ry - 1)), int(math.ceil(cy + ry + 1)) + 1):
        for x in range(int(math.floor(cx - r - 1)), int(math.ceil(cx + r + 1)) + 1):
            nx = (x - cx) / r
            ny = (y - cy) / ry
            d2 = nx * nx + ny * ny
            if d2 > 1.0:
                continue
            nz = math.sqrt(max(0.0, 1.0 - d2))
            lam = max(0.0, nx * lx + ny * ly + nz * lz)
            if rim and nz < rim_start:
                lam *= 0.55
            slot = 0
            for i, threshold in enumerate(bands, start=1):
                if lam >= threshold:
                    slot = i
            canvas.set(x, y, colors[slot])


def shade_cylinder(
    canvas: Canvas,
    x: int,
    y: int,
    w: int,
    h: int,
    family: str,
    *,
    bands: tuple[float, ...] = (0.30, 0.55, 0.78, 0.92),
) -> None:
    """Vertical cylinder shading: a highlight strip left of centre (light top-left)."""
    colors = PAL.ramp(family)
    centre = x + (w - 1) * 0.42
    half = max(1.0, w / 2)
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            t = 1.0 - abs(xx - centre) / half
            slot = 0
            for i, threshold in enumerate(bands, start=1):
                if t >= threshold:
                    slot = i
            canvas.set(xx, yy, colors[min(slot, 4)])


def outline(
    canvas: Canvas,
    *,
    diagonal: bool = False,
    only: np.ndarray | None = None,
    color: str | None = None,
    default: str = "space_deep",
) -> None:
    """1 px selective outline in each neighbour's own darkest ramp colour.

    The outline is added *outside* the existing silhouette, so the caller must leave a
    1 px margin.  ``only`` restricts which pixels count as silhouette.
    """
    mask = canvas.mask() if only is None else only
    height, width = canvas.h, canvas.w
    offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    if diagonal:
        offsets += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
    additions: list[tuple[int, int, str]] = []
    for y in range(height):
        for x in range(width):
            if mask[y, x]:
                continue
            chosen = None
            for dx, dy in offsets:
                nx, ny = x + dx, y + dy
                if not (0 <= nx < width and 0 <= ny < height) or not mask[ny, nx]:
                    continue
                neighbour = canvas.get(nx, ny)
                if neighbour is None:
                    continue
                chosen = PAL.darkest(neighbour)
                break
            if chosen is None:
                continue
            additions.append((x, y, color or chosen))
    for x, y, value in additions:
        canvas.set(x, y, value)
    if not additions and not mask.any():
        _ = default  # nothing to do; keeps the parameter meaningful for callers


def dither_rect(
    canvas: Canvas,
    x: int,
    y: int,
    w: int,
    h: int,
    color_a: str,
    color_b: str,
    *,
    mask: np.ndarray | None = None,
    phase: int = 0,
) -> None:
    """2x2 checker dithering, only for large surfaces."""
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if mask is not None and not mask[yy, xx]:
                continue
            checker = (xx + yy + phase) % 2 == 0
            canvas.set(xx, yy, color_a if checker else color_b)


def dither_mask(
    canvas: Canvas,
    mask: np.ndarray,
    color_a: str,
    color_b: str,
    *,
    phase: int = 0,
) -> None:
    ys, xs = np.nonzero(mask)
    for y, x in zip(ys, xs):
        canvas.set(int(x), int(y), color_a if (int(x) + int(y) + phase) % 2 == 0 else color_b)


# --------------------------------------------------------------------------------------
# patterns
# --------------------------------------------------------------------------------------


def ringed_mask(w: int, h: int, *, cx: float | None = None, cy: float | None = None,
                radius: float | None = None, thickness: int = 2, tilt: float = -0.38) -> np.ndarray:
    """A tilted ellipse band: the 'ringed' pattern, clipped by the caller's silhouette."""
    cx = (w - 1) / 2 if cx is None else cx
    cy = (h - 1) / 2 if cy is None else cy
    radius = min(w, h) * 0.44 if radius is None else radius
    mask = np.zeros((h, w), dtype=bool)
    ry = radius * 0.34
    for y in range(h):
        for x in range(w):
            dx, dy = x - cx, y - cy
            # rotate by tilt, then test the ellipse band
            ca, sa = math.cos(tilt), math.sin(tilt)
            rx_ = dx * ca - dy * sa
            ry_ = dx * sa + dy * ca
            d = (rx_ / radius) ** 2 + (ry_ / ry) ** 2
            if 0.72 <= d <= 1.0:
                mask[y, x] = True
    return mask


def spotted_mask(w: int, h: int, *, seed: int = 7, count: int = 7, radius: float = 1.0) -> np.ndarray:
    """Deterministic cluster of round spots (the 'spotted' pattern)."""
    mask = np.zeros((h, w), dtype=bool)
    rng = _Lcg(seed)
    for _ in range(count):
        cx = rng.uniform(2, w - 3)
        cy = rng.uniform(2, h - 3)
        rr = radius + rng.uniform(0, 0.9)
        for y in range(h):
            for x in range(w):
                if (x - cx) ** 2 + (y - cy) ** 2 <= rr * rr:
                    mask[y, x] = True
    return mask


def banded_mask(w: int, h: int, *, period: int = 4, thickness: int = 2, offset: int = 0) -> np.ndarray:
    """Horizontal bands for gas giants."""
    mask = np.zeros((h, w), dtype=bool)
    for y in range(h):
        if (y + offset) % period < thickness:
            mask[y, :] = True
    return mask


class _Lcg:
    """Tiny deterministic PRNG (numeric recipes only; art layout stays hand-placed)."""

    def __init__(self, seed: int) -> None:
        self.state = (seed * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF

    def next(self) -> int:
        self.state = (self.state * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        return (self.state >> 33) & 0xFFFFFFFF

    def uniform(self, lo: float, hi: float) -> float:
        return lo + (hi - lo) * (self.next() / 0xFFFFFFFF)


# --------------------------------------------------------------------------------------
# 5x7 bitmap font (original glyphs, used by the logo and dev boards)
# --------------------------------------------------------------------------------------

FONT_5X7: dict[str, list[str]] = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    " ": ["00000"] * 7,
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    "!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
}


def text_width(text: str, *, spacing: int = 1, scale: int = 1) -> int:
    return (len(text) * 5 + (len(text) - 1) * spacing) * scale


def draw_text(
    canvas: Canvas,
    x: int,
    y: int,
    text: str,
    color: str,
    *,
    spacing: int = 1,
    scale: int = 1,
    shadow: str | None = None,
) -> None:
    """Draw upper-case 5x7 text. Unknown glyphs raise, so typos fail the build."""
    cx = x
    for char in text.upper():
        glyph = FONT_5X7.get(char)
        if glyph is None:
            raise KeyError(f"no glyph for {char!r} in the 5x7 font")
        for row, bits in enumerate(glyph):
            for col, bit in enumerate(bits):
                if bit == "1":
                    for sy in range(scale):
                        for sx in range(scale):
                            if shadow:
                                canvas.set(cx + col * scale + sx + scale,
                                           y + row * scale + sy + scale, shadow)
                            canvas.set(cx + col * scale + sx, y + row * scale + sy, color)
        cx += (5 + spacing) * scale


# --------------------------------------------------------------------------------------
# sheet + registry
# --------------------------------------------------------------------------------------


@dataclass
class Anim:
    name: str
    frames: list[Canvas]
    fps: float
    loop: bool


@dataclass
class Sheet:
    id: str
    frame_size: tuple[int, int]
    pivot: tuple[int, int]
    source: str
    tier: str = "A"
    allow_edge: bool = False
    note: str = ""
    animations: list[Anim] = field(default_factory=list)

    def add(self, name: str, frames: list[Canvas], fps: float = 8, *, loop: bool = True) -> "Sheet":
        w, h = self.frame_size
        for i, frame in enumerate(frames):
            if (frame.w, frame.h) != (w, h):
                raise ValueError(
                    f"{self.id}.{name}[{i}] is {frame.w}x{frame.h}, expected {w}x{h}"
                )
            frame._validate()
        if not frames:
            raise ValueError(f"{self.id}.{name} has no frames")
        self.animations.append(Anim(name, frames, fps, loop))
        return self

    def build(self) -> tuple[np.ndarray, dict]:
        w, h = self.frame_size
        cols = max(len(a.frames) for a in self.animations)
        rows = len(self.animations)
        atlas = np.zeros((rows * h, cols * w, 4), dtype=np.uint8)
        animations: dict[str, dict] = {}
        for row, anim in enumerate(self.animations):
            for col, frame in enumerate(anim.frames):
                atlas[row * h : (row + 1) * h, col * w : (col + 1) * w] = frame.buf
            animations[anim.name] = {
                "row": row,
                "frames": len(anim.frames),
                "fps": anim.fps,
                "loop": anim.loop,
            }
        meta = {
            "id": self.id,
            "frame_size": [w, h],
            "scale": 4,
            "pivot": [self.pivot[0], self.pivot[1]],
            "animations": animations,
            "tier": self.tier,
            "source": self.source,
        }
        if self.allow_edge:
            meta["allow_edge"] = True
        if self.note:
            meta["note"] = self.note
        return atlas, meta

    def save(self, dest: Path = SPRITES_DIR) -> tuple[Path, Path, str]:
        import hashlib

        atlas, meta = self.build()
        canvas = Canvas.from_array(atlas)
        canvas._validate()
        png = dest / f"{self.id}.png"
        js = dest / f"{self.id}.json"
        canvas.save(png)
        js.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
        digest = hashlib.sha256(png.read_bytes()).hexdigest()
        return png, js, digest


class Registry:
    """Collects sheets from every builder and writes them to assets/sprites."""

    def __init__(self, dest: Path = SPRITES_DIR) -> None:
        self.dest = dest
        self.sheets: dict[str, Sheet] = {}
        self.hashes: dict[str, str] = {}

    def add(self, sheet: Sheet) -> Sheet:
        if sheet.id in self.sheets:
            raise ValueError(f"duplicate sheet id {sheet.id}")
        self.sheets[sheet.id] = sheet
        return sheet

    def write_all(self, *, prune: bool = True) -> dict[str, str]:
        self.dest.mkdir(parents=True, exist_ok=True)
        written = set()
        for sheet_id in sorted(self.sheets):
            _, _, digest = self.sheets[sheet_id].save(self.dest)
            self.hashes[sheet_id] = digest
            written.add(f"{sheet_id}.png")
            written.add(f"{sheet_id}.json")
        if not prune:
            return self.hashes
        # remove orphans (png/json without a builder) so the linter's manifest check is honest
        for path in sorted(self.dest.glob("*")):
            if path.suffix in {".png", ".json"} and path.name not in written:
                if path.suffix == ".import":
                    continue
                path.unlink()
        return self.hashes


# --------------------------------------------------------------------------------------
# source-adaptation helpers
# --------------------------------------------------------------------------------------


def source_to_canvas(
    image: Image.Image,
    w: int,
    h: int,
    family: str,
    *,
    slots: tuple[int, ...] = (0, 1, 2, 3, 4),
    alpha_threshold: int = 110,
) -> Canvas:
    """Box-downscale a source render, then map luminance onto one ramp's slots.

    This is the deterministic 'adapt a real source' step: the shape and the internal
    light/dark structure come from the CC0 source, the colours come from the palette.
    """
    resized = image.convert("RGBA").resize((w, h), Image.BOX)
    arr = np.array(resized, dtype=np.float32)
    alpha = arr[:, :, 3]
    lum = (0.2126 * arr[:, :, 0] + 0.7152 * arr[:, :, 1] + 0.0722 * arr[:, :, 2])
    body = alpha >= alpha_threshold
    out = Canvas(w, h)
    if not body.any():
        return out
    values = lum[body]
    # Percentile thresholds keep the result stable when the source changes size.
    cuts = [float(np.percentile(values, p)) for p in (10, 35, 62, 84)]
    ramp = PAL.ramp(family)
    colors = [ramp[slot] for slot in slots] if slots else ramp
    for y in range(h):
        for x in range(w):
            if not body[y, x]:
                continue
            value = lum[y, x]
            slot = 0
            for i, cut in enumerate(cuts, start=1):
                if value >= cut:
                    slot = i
            out.set(x, y, colors[slot])
    return out


def source_pattern_mask(
    image: Image.Image,
    w: int,
    h: int,
    *,
    percentile: float = 60.0,
    alpha_threshold: int = 110,
    invert: bool = False,
) -> np.ndarray:
    """Binary mask of the darker (or lighter) structure of a source, e.g. continents."""
    resized = image.convert("RGBA").resize((w, h), Image.BOX)
    arr = np.array(resized, dtype=np.float32)
    alpha = arr[:, :, 3] >= alpha_threshold
    lum = 0.2126 * arr[:, :, 0] + 0.7152 * arr[:, :, 1] + 0.0722 * arr[:, :, 2]
    if not alpha.any():
        return np.zeros((h, w), dtype=bool)
    cut = float(np.percentile(lum[alpha], percentile))
    mask = (lum < cut) if not invert else (lum > cut)
    return (mask & alpha).astype(bool)



# --------------------------------------------------------------------------------------
# mask morphology (source adaptation cleanup)
# --------------------------------------------------------------------------------------


def erode(mask: np.ndarray, steps: int = 1) -> np.ndarray:
    out = mask.copy()
    for _ in range(steps):
        padded = np.pad(out, 1, constant_values=False)
        out = (
            padded[0:-2, 1:-1] & padded[2:, 1:-1] & padded[1:-1, 0:-2] & padded[1:-1, 2:]
            & padded[1:-1, 1:-1]
        )
    return out


def dilate(mask: np.ndarray, steps: int = 1) -> np.ndarray:
    out = mask.copy()
    for _ in range(steps):
        padded = np.pad(out, 1, constant_values=False)
        out = (
            padded[0:-2, 1:-1] | padded[2:, 1:-1] | padded[1:-1, 0:-2] | padded[1:-1, 2:]
            | padded[1:-1, 1:-1]
        )
    return out


def components(mask: np.ndarray) -> list[np.ndarray]:
    """4-connected components, ordered by size (desc), then top-left position."""
    seen = np.zeros_like(mask, dtype=bool)
    found: list[tuple[int, int, int, np.ndarray]] = []
    h, w = mask.shape
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or seen[y, x]:
                continue
            stack = [(y, x)]
            seen[y, x] = True
            pixels: list[tuple[int, int]] = []
            while stack:
                cy, cx = stack.pop()
                pixels.append((cy, cx))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            piece = np.zeros_like(mask, dtype=bool)
            ys = [p[0] for p in pixels]
            xs = [p[1] for p in pixels]
            piece[ys, xs] = True
            found.append((len(pixels), min(ys), min(xs), piece))
    found.sort(key=lambda item: (-item[0], item[1], item[2]))
    return [item[3] for item in found]


def clean_mask(mask: np.ndarray, *, keep: int = 3, min_px: int = 5, smooth: int = 1) -> np.ndarray:
    """Turn a noisy downscaled source mask into a few readable blobs.

    Deterministic: binary close (dilate+erode), drop tiny components, keep the largest
    ``keep`` ones in size order.  This is the step that makes a 1280 px planet render
    usable as a 16 px pattern without turning into noise.
    """
    work = dilate(mask, smooth)
    work = erode(work, smooth)
    pieces = components(work)
    out = np.zeros_like(mask, dtype=bool)
    kept = 0
    for piece in pieces:
        if int(piece.sum()) < min_px:
            continue
        out |= piece
        kept += 1
        if kept >= keep:
            break
    return out


__all__ = [
    "ACCENT_OUTLINE",
    "COLOUR_FAMILY",
    "Anim",
    "Canvas",
    "FONT_5X7",
    "PAL",
    "PALETTE_PATH",
    "PaletteError",
    "RAMPS",
    "Registry",
    "SOURCES_DIR",
    "SPRITES_DIR",
    "Sheet",
    "banded_mask",
    "clean_mask",
    "components",
    "dilate",
    "erode",
    "contrast_vs_void",
    "dither_mask",
    "dither_rect",
    "draw_text",
    "load_image",
    "outline",
    "ramp_swap_family",
    "relative_luminance",
    "rgb_to_hex",
    "ringed_mask",
    "shade_cylinder",
    "shade_sphere",
    "load_source",
    "source_pattern_mask",
    "source_to_canvas",
    "spotted_mask",
    "text_width",
]

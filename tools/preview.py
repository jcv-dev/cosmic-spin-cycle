#!/usr/bin/env python3
"""Render review previews: per-sheet zooms, a contact sheet, 1x readability and a scene.

    python3 tools/preview.py

Outputs (all under ``art/preview/``, none of it shipped):

    sheets/<id>_x8.png      every animation strip, nearest-neighbour zoom, 1 px grid
    contact_sheet.png       all sheets with ids, so a vision model can review everything
    readability_1x.png      items at true 1x and at 8x, on #0B0C10
    in_scene.png            320x180 composite from data/layout.json, scaled x4 -> 1280x720
    hud.png                 the HUD strip in place

The scene composite is the important one: it answers "does this look like a dark
retro-futuristic laundromat" before a single Godot node exists.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "art"))

from PIL import Image, ImageDraw  # noqa: E402

import pxlib  # noqa: E402
from contract import CONTRACT  # noqa: E402

SPRITES = ROOT / "assets" / "sprites"
PREVIEW = ROOT / "art" / "preview"
BG = (11, 12, 16, 255)          # space_void
GRID = (31, 35, 64, 255)        # space_mid
LABEL = (154, 164, 196, 255)    # metal_2


def load_meta(sheet_id: str) -> dict:
    path = SPRITES / f"{sheet_id}.json"
    if not path.exists():
        raise SystemExit(f"missing {path}; run python3 tools/make_art.py first")
    return json.loads(path.read_text(encoding="utf-8"))


def load_sheet(sheet_id: str) -> pxlib.Canvas:
    return pxlib.Canvas.from_image(pxlib.load_image(SPRITES / f"{sheet_id}.png"), quantise=False)


def frame(sheet_id: str, anim: str, index: int = 0) -> pxlib.Canvas:
    meta = load_meta(sheet_id)
    info = meta["animations"][anim]
    w, h = meta["frame_size"]
    sheet = load_sheet(sheet_id)
    return sheet.crop(index * w, info["row"] * h, w, h)


def first_anim(sheet_id: str, anim: str | None = None) -> pxlib.Canvas:
    meta = load_meta(sheet_id)
    name = anim or next(iter(meta["animations"]))
    return frame(sheet_id, name)


def zoom(image: Image.Image, scale: int, *, grid: bool = True) -> Image.Image:
    image = image.convert("RGBA")
    if scale == 1:
        return image
    big = image.resize((image.width * scale, image.height * scale), Image.NEAREST)
    if grid and scale >= 4:
        draw = ImageDraw.Draw(big)
        for x in range(0, big.width, scale):
            draw.line([(x, 0), (x, big.height - 1)], fill=GRID)
        for y in range(0, big.height, scale):
            draw.line([(0, y), (big.width - 1, y)], fill=GRID)
    return big


def render_sheet(sheet_id: str) -> Path:
    meta = load_meta(sheet_id)
    w, h = meta["frame_size"]
    sheet = load_sheet(sheet_id)
    scale = 8 if max(w, h) <= 24 else 6 if max(w, h) <= 48 else 4 if max(w, h) <= 96 else 1
    image = zoom(sheet.image(), scale)
    background = Image.new("RGBA", (image.width + 8, image.height + 22), BG)
    background.alpha_composite(image, (4, 18))
    draw = ImageDraw.Draw(background)
    draw.text((4, 3), f"{sheet_id}  {w}x{h}  x{scale}", fill=LABEL)
    out = PREVIEW / "sheets" / f"{sheet_id}_x{scale}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    background.save(out)
    return out


def contact_sheet() -> Path:
    cells = []
    for sheet_id, spec in CONTRACT.items():
        meta = load_meta(sheet_id)
        w, h = meta["frame_size"]
        scale = 8 if max(w, h) <= 16 else 6 if max(w, h) <= 24 else 3 if max(w, h) <= 48 else 1
        image = zoom(load_sheet(sheet_id).image(), scale, grid=scale >= 4)
        cells.append((sheet_id, image, scale))
    pad, label_h, columns = 12, 16, 3
    column_width = max(cell[1].width for cell in cells) + pad * 2
    rows: list[list[tuple[str, Image.Image, int]]] = [[]]
    used = 0
    for cell in cells:
        if used >= columns:
            rows.append([])
            used = 0
        rows[-1].append(cell)
        used += 1
    row_heights = [max(c[1].height for c in row) + label_h + pad for row in rows]
    width = column_width * columns
    height = sum(row_heights) + pad
    sheet = Image.new("RGBA", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    y = pad
    for row, row_height in zip(rows, row_heights):
        x = pad
        for sheet_id, image, scale in row:
            sheet.alpha_composite(image, (x, y + label_h))
            draw.text((x, y + 2), f"{sheet_id} x{scale}", fill=LABEL)
            x += column_width
        y += row_height
    out = PREVIEW / "contact_sheet.png"
    sheet.save(out)
    return out


def readability() -> Path:
    items = ["item_rocky", "item_sock", "item_moon", "item_gas", "item_core"]
    variants = [("red", "solid"), ("blue", "ringed"), ("yellow", "spotted")]
    tile = 24
    width = tile * len(items) * len(variants) + 16
    height = 12 + tile + 10 + tile * 8 + 24
    sheet = Image.new("RGBA", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    draw.text((4, 2), "items at 1x (top) and x8 (bottom) on #0B0C10", fill=LABEL)
    x = 8
    for sheet_id in items:
        spec = CONTRACT[sheet_id]
        for colour, pattern in variants:
            anim = f"{colour}_{pattern}"
            if anim not in spec.anims:
                continue
            meta = load_meta(sheet_id)
            w, h = meta["frame_size"]
            patch = frame(sheet_id, anim).image()
            sheet.alpha_composite(patch.resize((w, h), Image.NEAREST), (x, 14))
            big = patch.resize((w * 8, h * 8), Image.NEAREST)
            sheet.alpha_composite(big, (x, 20 + tile))
            draw.text((x, 20 + tile + big.height + 2), f"{colour}_{pattern}", fill=LABEL)
            x += max(w * 8, tile) + 10
    out = PREVIEW / "readability_1x.png"
    sheet.save(out)
    return out


def tile_into(canvas: pxlib.Canvas, sprite: pxlib.Canvas, x: int, y: int, w: int, h: int) -> None:
    for yy in range(0, h, sprite.h):
        for xx in range(0, w, sprite.w):
            piece = sprite
            if xx + sprite.w > w or yy + sprite.h > h:
                piece = sprite.crop(0, 0, min(sprite.w, w - xx), min(sprite.h, h - yy))
            canvas.blit(piece, x + xx, y + yy)


def scene() -> Path:
    layout = json.loads((ROOT / "data" / "layout.json").read_text(encoding="utf-8"))
    canvas = pxlib.Canvas(layout["canvas"]["w"], layout["canvas"]["h"])
    canvas.blit(first_anim("env_room", "bg"), 0, 0)

    floor = [first_anim("env_floor", name) for name in ("variant_a", "variant_b", "variant_c")]
    for ty in range(28, 164, 16):
        for tx in range(8, 312, 16):
            pick = floor[((tx // 16) * 7 + (ty // 16) * 3) % 3]
            canvas.blit(pick, tx, ty)

    belt = first_anim("env_belt", "scroll")
    for entry in layout["belts"]:
        if entry["w"] >= entry["h"]:
            tile_into(canvas, belt, entry["x"], entry["y"], entry["w"], entry["h"])
        else:
            tile_into(canvas, belt.rotate90(1), entry["x"], entry["y"], entry["w"], entry["h"])

    for entry in layout["shredders"]:
        canvas.blit(first_anim("env_shredder", "idle"), entry["x"], entry["y"])

    for entry in layout["washers"]:
        canvas.blit(first_anim("mach_washer", "idle"), entry["x"], entry["y"])

    chute = layout["chute"]
    canvas.blit(first_anim("env_chute", "open"), chute["x"], chute["y"])

    pip = first_anim("char_pip", "idle_down")
    spawn_x, spawn_y = layout["player_spawn"]
    canvas.blit(pip, spawn_x - 12, spawn_y - 22)

    # a few items to judge contrast and scale
    canvas.blit(frame("item_rocky", "red_solid"), 100, 22)
    canvas.blit(frame("item_sock", "yellow_spotted"), 124, 22)
    canvas.blit(frame("item_gas", "blue_ringed"), 150, 26)
    canvas.blit(frame("item_moon", "blue_solid"), 200, 22)
    canvas.blit(frame("item_core", "idle"), 176, 120)
    canvas.blit(frame("item_rocky", "red_ringed"), 100, 22)
    grime = first_anim("item_grime_16")
    canvas.blit(grime, 216, 160)

    # HUD strip is drawn separately; keep the scene clean of baked UI
    out = PREVIEW / "in_scene.png"
    zoom(canvas.image(), 4, grid=False).save(out)
    return out


def hud() -> Path:
    bar = first_anim("ui_bar_stability", "bar")
    canvas = pxlib.Canvas(160, 40)
    canvas.blit(first_anim("ui_panel", "panel"), 0, 0)
    canvas.blit(bar, 4, 4)
    fill = first_anim("ui_bar_stability_fill", "fill")
    for x in range(6, 62, 8):
        canvas.blit(fill, x, 6)
    for index, name in enumerate(("clock", "stability", "combo")):
        canvas.blit(first_anim("ui_icons", name), 4 + index * 12, 18)
    canvas.blit(first_anim("ui_holo_icons", "red"), 44, 16)
    canvas.blit(first_anim("ui_reticle", "aim"), 96, 14)
    canvas.blit(first_anim("fx_burst_perfect", "play"), 116, 12)
    zoom(canvas.image(), 8, grid=True).save(PREVIEW / "hud.png")
    return PREVIEW / "hud.png"


def main() -> int:
    PREVIEW.mkdir(parents=True, exist_ok=True)
    missing = [sheet_id for sheet_id in CONTRACT if not (SPRITES / f"{sheet_id}.png").exists()]
    if missing:
        print(f"preview: {len(missing)} sheets missing, building what exists")
    for sheet_id in CONTRACT:
        if (SPRITES / f"{sheet_id}.png").exists() and (SPRITES / f"{sheet_id}.json").exists():
            render_sheet(sheet_id)
    outputs = []
    if all((SPRITES / f"{sheet_id}.png").exists() for sheet_id in CONTRACT):
        outputs = [contact_sheet(), readability(), scene(), hud()]
    print("preview:", ", ".join(str(p.relative_to(ROOT)) for p in outputs) or "sheets only")
    if missing:
        print(f"preview: missing {missing}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

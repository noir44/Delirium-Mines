"""Placeholder art for Delirium Mines until the Meshy rocks are rendered:
36 frames 128x256 (2x) - a stepped isometric block per cell, the work face
in a cut colour with ore specks - plus tiles.json for build-tilepack.ps1
and a 256x256 poster.

  python art/make_placeholder.py

Sprite index = (kind * 2 + facing) * 9 + dy * 3 + dx (DM_Shared.lua);
kind 0 quarry, 1 mine; facing 0 S, 1 E; (dx, dy) from the north-west cell.
Frame: floor diamond in the bottom 64 px, front point at (64, 256); the
south side of a cell is its lower-left face, the east side its lower-right.
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = os.path.join(HERE, "frames")
W, H = 128, 256

KINDS = {
    "quarry": {"rock": (196, 190, 172), "cut": (226, 222, 205), "specks": [(240, 238, 228), (170, 160, 140)]},
    "mine": {"rock": (88, 84, 80), "cut": (110, 100, 92), "specks": [(170, 85, 40), (60, 150, 120)]},
}
FACINGS = ["S", "E"]
SHADE = {"top": 1.0, "left": 0.78, "right": 0.62}


def corners(height):
    n, e, s, w = (64, 192), (128, 224), (64, 256), (0, 224)
    up = lambda p: (p[0], p[1] - height)
    return {
        "top": [up(n), up(e), up(s), up(w)],
        "left": [w, s, up(s), up(w)],
        "right": [s, e, up(e), up(s)],
    }


def fill(img, poly, colour, shade, specks, rng, density):
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    m = np.array(mask) > 0
    noise = rng.normal(1.0, 0.07, (H, W))
    base = np.array(colour, dtype=float) * shade
    rgb = np.clip(base[None, None, :] * noise[:, :, None], 0, 255)
    px = np.array(img)
    px[m, :3] = rgb[m].astype(np.uint8)
    px[m, 3] = 255
    ys, xs = np.nonzero(m)
    for _ in range(int(len(xs) * density)):
        i = rng.integers(len(xs))
        c = np.array(specks[rng.integers(len(specks))], dtype=float) * shade
        y, x = ys[i], xs[i]
        px[y:y + 2, x:x + 2, :3] = c.astype(np.uint8)
    img.paste(Image.fromarray(px))
    ImageDraw.Draw(img).line(poly + [poly[0]], fill=(0, 0, 0, 90), width=1)


def frame(kind, facing, dx, dy, rng):
    spec = KINDS[kind]
    # Back cells higher, the face lower: a rock stepping down to the face.
    depth = dy if facing == "S" else dx
    height = 150 - depth * 30 + int(rng.integers(-6, 7))
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    c = corners(height)
    face_left = facing == "S" and dy == 2
    face_right = facing == "E" and dx == 2
    fill(img, c["top"], spec["rock"], SHADE["top"], spec["specks"], rng, 0.002)
    fill(img, c["left"], spec["cut"] if face_left else spec["rock"], SHADE["left"], spec["specks"], rng,
         0.02 if face_left else 0.002)
    fill(img, c["right"], spec["cut"] if face_right else spec["rock"], SHADE["right"], spec["specks"], rng,
         0.02 if face_right else 0.002)
    return img


def main():
    os.makedirs(FRAMES, exist_ok=True)
    rng = np.random.default_rng(1717)
    tiles = []
    for k, kind in enumerate(KINDS):
        for f, facing in enumerate(FACINGS):
            for dy in range(3):
                for dx in range(3):
                    index = (k * 2 + f) * 9 + dy * 3 + dx
                    name = f"delmines_01_{index}.png"
                    frame(kind, facing, dx, dy, rng).save(os.path.join(FRAMES, name))
                    tiles.append({
                        "index": index,
                        "png": f"frames/{name}",
                        "props": {
                            "BlocksPlacement": "",
                            "CustomName": "Quarry" if kind == "quarry" else "Mine",
                            "GroupName": "Delirium",
                            "solidtrans": "",
                        },
                    })
    spec = {"pack": "delmines", "tileset": "delmines_01", "columns": 8, "rows": 8, "tiles": tiles}
    with open(os.path.join(HERE, "tiles.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(spec, fh, indent=2)
        fh.write("\n")

    # Preview: both kinds, both facings, each 3x3 assembled back to front.
    sheet = Image.new("RGBA", (4 * 400, 420), (60, 90, 60, 255))
    for k, kind in enumerate(KINDS):
        for f, facing in enumerate(FACINGS):
            ox = (k * 2 + f) * 400 + 136
            for dy in range(3):
                for dx in range(3):
                    index = (k * 2 + f) * 9 + dy * 3 + dx
                    tile = Image.open(os.path.join(FRAMES, f"delmines_01_{index}.png"))
                    sx = ox + (dx - dy) * 64
                    sy = 40 + (dx + dy) * 32
                    sheet.alpha_composite(tile, (sx, sy))
    sheet.save(os.path.join(HERE, "placeholder_preview.png"))

    poster = Image.new("RGBA", (256, 256), (45, 60, 45, 255))
    for dy in range(3):
        for dx in range(3):
            tile = Image.open(os.path.join(FRAMES, f"delmines_01_{18 + dy * 3 + dx}.png")).resize((64, 128))
            poster.alpha_composite(tile, (96 + (dx - dy) * 32, 40 + (dx + dy) * 16))
    poster.convert("RGB").save(os.path.join(HERE, "poster.png"))


if __name__ == "__main__":
    main()

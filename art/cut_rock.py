"""Cuts the renders of render_rock.py into the 36 frames (128x256, 2x),
then makes the preview sheet and the poster.

  python art/cut_rock.py

Reads art/raw/<kind>_<facing>_color.png and _mask.png (1536x1536, 4x of
the 384x384 area). Sprite index = (kind * 2 + facing) * 9 + dy * 3 + dx.
Cell (dx, dy)'s frame sits at x = 128 + (dx - dy) * 64, y = (dx + dy) * 32
of the 2x area. Every 2x pixel goes whole to the cell that owns most of its
16 subpixels (mask), so the nine frames drawn back to front add up to the
full picture without seams or double edges. tiles.json comes from
make_placeholder.py and names the same frame files.
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
FRAMES = os.path.join(HERE, "frames")
KINDS = ["quarry", "mine"]
FACINGS = ["S", "E"]
SCALE = 4
AREA = 384


def load(path):
    return np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32) / 255.0


def cut(kind, facing, base):
    color = load(os.path.join(RAW, f"{kind}_{facing}_color.png"))
    mask = load(os.path.join(RAW, f"{kind}_{facing}_mask.png"))
    # Premultiplied box filter to 2x.
    pm = color.copy()
    pm[..., :3] *= pm[..., 3:4]
    pm = pm.reshape(AREA, SCALE, AREA, SCALE, 4).mean(axis=(1, 3))
    # Cell id per 4x pixel: column R, row G, each 0 / 0.5 / 1.
    col = np.clip(np.rint(mask[..., 0] * 2), 0, 2).astype(int)
    row = np.clip(np.rint(mask[..., 1] * 2), 0, 2).astype(int)
    ids = np.where(mask[..., 3] > 0.5, row * 3 + col, -1)
    votes = np.stack([(ids == k).reshape(AREA, SCALE, AREA, SCALE).sum(axis=(1, 3)) for k in range(9)])
    owner = np.where(votes.max(axis=0) > 0, votes.argmax(axis=0), -1)
    # Edge pixels with colour but no mask hit go to their 2x neighbours' owner.
    for _ in range(3):
        lost = (owner < 0) & (pm[..., 3] > 0.002)
        if not lost.any():
            break
        grown = owner.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            shifted = np.roll(owner, (dy, dx), axis=(0, 1))
            grown = np.where((grown < 0) & (shifted >= 0), shifted, grown)
        owner = np.where(lost, grown, owner)
    for dy in range(3):
        for dx in range(3):
            x0, y0 = 128 + (dx - dy) * 64, (dx + dy) * 32
            cell = dy * 3 + dx
            win = pm[y0:y0 + 256, x0:x0 + 128].copy()
            win[owner[y0:y0 + 256, x0:x0 + 128] != cell] = 0
            a = win[..., 3:4]
            rgb = np.where(a > 1e-6, win[..., :3] / np.maximum(a, 1e-6), 0)
            out = (np.concatenate([rgb, a], axis=2) * 255 + 0.5).clip(0, 255).astype(np.uint8)
            Image.fromarray(out, "RGBA").save(os.path.join(FRAMES, f"delmines_01_{base + cell}.png"))
    # Pixels outside every frame window are lost: report them.
    inside = np.zeros((AREA, AREA), bool)
    for dy in range(3):
        for dx in range(3):
            x0, y0 = 128 + (dx - dy) * 64, (dx + dy) * 32
            inside[y0:y0 + 256, x0:x0 + 128] |= owner[y0:y0 + 256, x0:x0 + 128] == dy * 3 + dx
    lost = (pm[..., 3] > 0.05) & ~inside
    print(kind, facing, "pixels outside their frame:", int(lost.sum()))


def assemble(base):
    img = Image.new("RGBA", (AREA, AREA), (0, 0, 0, 0))
    for dy in range(3):
        for dx in range(3):
            tile = Image.open(os.path.join(FRAMES, f"delmines_01_{base + dy * 3 + dx}.png"))
            img.alpha_composite(tile, (128 + (dx - dy) * 64, (dx + dy) * 32))
    return img


def main():
    os.makedirs(FRAMES, exist_ok=True)
    sheet = Image.new("RGBA", (4 * AREA, AREA), (74, 96, 58, 255))
    for k, kind in enumerate(KINDS):
        for f, facing in enumerate(FACINGS):
            base = (k * 2 + f) * 9
            cut(kind, facing, base)
            sheet.alpha_composite(assemble(base), ((k * 2 + f) * AREA, 0))
    sheet.save(os.path.join(HERE, "rocks_preview.png"))
    poster = Image.new("RGBA", (AREA, AREA), (52, 66, 46, 255))
    poster.alpha_composite(assemble(18))
    poster.resize((256, 256), Image.LANCZOS).convert("RGB").save(os.path.join(HERE, "poster.png"))


if __name__ == "__main__":
    main()

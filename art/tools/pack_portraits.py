"""Copy the painted busts into the game, and cut a square face from each.

The originals are 640x800. The game shows a bust at most ~170 px wide (the camp's hero
card), so 256x320 is enough. The face crops (160x160, in portraits/faces/) are what
`Px.face` sets in its roundel wherever the game used to cut a head from the battle sprite.

Pixels the background remover left at alpha 1-7 are cleared: invisible on any ground, but
they would stretch the used rect the crop is measured from.

The face is found by where the skin is in the top of the picture. Half-figure portraits
with a quiver, a pack or a club beside the head, and the animals, are placed by hand.
"""
import colorsys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'art/originals/portraits'
OUT = ROOT / 'prototype/art/original/portraits'
SIZE = (256, 320)
FACE = 160

# name: (centre x, centre y, side), as fractions of the packed picture's width and height
# (side as a fraction of the width).
BY_HAND = {
    'merc_archer': (.59, .25, .50),
    'npc_trader': (.60, .25, .50),
    'heracles': (.53, .28, .50),
    'marsh_snake': (.68, .22, .55),
    'hydra_head': (.66, .36, .62),
}


def face(im: Image.Image, name: str) -> Image.Image:
    w, h = im.size
    x0, y0, x1, y1 = im.getchannel('A').point(lambda v: 255 if v > 128 else 0).getbbox()
    if name in BY_HAND:
        fx, fy, fs = BY_HAND[name]
        cx, cy, side = fx * w, fy * h, round(fs * w)
    elif y1 - y0 < h * .8:
        # Drawn whole and not reaching the bottom (the crab): show all of it.
        side = max(x1 - x0, y1 - y0)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    else:
        px = im.load()
        sx = sy = n = 0
        for y in range(y0, y0 + round(h * .42)):
            for x in range(x0, x1):
                r, g, b, a = px[x, y]
                if a < 200:
                    continue
                hue, sat, val = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                if .02 < hue < .11 and .25 < sat < .65 and .35 < val < .95:
                    sx, sy, n = sx + x, sy + y, n + 1
        side = round(w * .5)
        cx, cy = (sx / n, sy / n) if n > 300 else ((x0 + x1) / 2, y0 + side * .45)
        cy += side * .04
    left = min(max(0, round(cx - side / 2)), w - side)
    top = min(max(0, round(cy - side / 2)), h - side)
    return im.crop((left, top, left + side, top + side)).resize((FACE, FACE), Image.Resampling.LANCZOS)


def pack(path: Path) -> None:
    im = Image.open(path).convert('RGBA')
    im.putalpha(im.getchannel('A').point(lambda a: 0 if a < 8 else a))
    im = im.resize(SIZE, Image.Resampling.LANCZOS)
    target = OUT / path.name
    # The hero's three busts were packed before this script; leave them byte for byte.
    if not target.exists():
        im.save(target, optimize=True)
    face(im, path.stem).save(OUT / 'faces' / path.name, optimize=True)


if __name__ == '__main__':
    (OUT / 'faces').mkdir(parents=True, exist_ok=True)
    for p in sorted(SRC.glob('*.png')):
        pack(p)
        print(p.name)

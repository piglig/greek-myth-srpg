"""Bake the hydra's two stumps (raw and sealed) into one small pixel strip.

    python art/tools/bake_hydra_stump.py

art/originals/hydra_stump.png holds both, side by side. Each is cut to its drawing, brought
down to about a third of a standing head's height on the battle sprite, and reduced to a
small palette with hard edges, so it sits beside the pixel units as one of them. The strip
is two 64x48 cells: raw on the left, sealed on the right.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CELL = (64, 48)
HEIGHT = 44


def frame(drawing: Image.Image) -> Image.Image:
    drawing = drawing.crop(drawing.getchannel('A').point(lambda a: 255 if a > 40 else 0).getbbox())
    scale = HEIGHT / drawing.height
    small = drawing.resize((round(drawing.width * scale), HEIGHT), Image.Resampling.LANCZOS)
    alpha = small.getchannel('A').point(lambda a: 255 if a > 128 else 0)
    paint = small.convert('RGB').quantize(colors=20, method=Image.Quantize.MEDIANCUT).convert('RGB')
    small = paint.convert('RGBA')
    small.putalpha(alpha)
    cell = Image.new('RGBA', CELL)
    cell.alpha_composite(small, ((CELL[0] - small.width) // 2, CELL[1] - small.height))
    return cell


if __name__ == '__main__':
    source = Image.open(ROOT / 'art/originals/hydra_stump.png').convert('RGBA')
    half = source.width // 2
    strip = Image.new('RGBA', (CELL[0] * 2, CELL[1]))
    for i in range(2):
        strip.alpha_composite(frame(source.crop((i * half, 0, (i + 1) * half, source.height))), (i * CELL[0], 0))
    out = ROOT / 'prototype/art/pixel/hydra_head/stump.png'
    strip.save(out, optimize=True)
    print(out)

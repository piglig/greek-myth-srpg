"""Bake Lerna's painted shrine and three marsh trees into pixel standees.

    python art/tools/bake_lerna_props.py

Each drawing in art/originals is cut to what is drawn (the background remover left alpha
1-40 haze round them), brought down to the pixel density of the battle sprites, reduced
to a small palette with hard edges, and written to prototype/art/pixel/props/.

The battle sprites show about 0.015 cell per pixel (prototype/view/unit_view.gd: height /
208 / 0.5 on a 1.2 world-unit cell). The widths below are in cells, so a prop stands at
the same pixel size as the people beside it; lerna_field.gd draws them at that density.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CELL_PER_PIXEL = .015
# name: (source, width in cells, colours)
PROPS = {
    'lerna_shrine': ('lerna-shrine.png', 4.9, 40),
    'marsh_willow': ('marsh-willow.png', 3.2, 32),
    'marsh_alder': ('marsh-alder.png', 2.3, 32),
    'marsh_snag': ('marsh-snag.png', 2.1, 28),
}


def bake(source: str, width: float, colours: int) -> Image.Image:
    drawing = Image.open(ROOT / 'art/originals' / source).convert('RGBA')
    drawing = drawing.crop(drawing.getchannel('A').point(lambda a: 255 if a > 40 else 0).getbbox())
    w = round(width / CELL_PER_PIXEL)
    h = round(drawing.height * w / drawing.width)
    small = drawing.resize((w, h), Image.Resampling.LANCZOS)
    alpha = small.getchannel('A').point(lambda a: 255 if a > 128 else 0)
    paint = small.convert('RGB').quantize(colors=colours, method=Image.Quantize.MEDIANCUT).convert('RGBA')
    paint.putalpha(alpha)
    return paint


if __name__ == '__main__':
    out = ROOT / 'prototype/art/pixel/props'
    out.mkdir(parents=True, exist_ok=True)
    for name, (source, width, colours) in PROPS.items():
        picture = bake(source, width, colours)
        picture.save(out / (name + '.png'), optimize=True)
        print(name, picture.size)

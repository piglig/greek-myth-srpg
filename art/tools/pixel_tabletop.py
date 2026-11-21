"""Bake the three tabletop pieces. Pass the checkout of agent-sprite-forge (25203d0)."""
import argparse
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

parser = argparse.ArgumentParser()
parser.add_argument("forge", type=Path)
args = parser.parse_args()
sys.path.insert(0, str(args.forge / "shared"))
import forge_hibit as forge

folder = Path(__file__).resolve().parents[1] / "originals/tabletop"
# Tint source luminance groups so bronze, hide and bristles separate on limestone.
ramps = {
    "hero": ("232035 423043 65373c 8e433b b2523b d47045 b1875c e3a863 ffd68e f8e2bb", 60),
    "atalanta": ("232234 37353b 51443d 755238 91663c b28148 c99d64 e1b57f f9d8a1 fcebc3", 63),
    "boar_w": ("271e30 422e36 593737 794634 995736 b77143 c99361 d6aa80 ead2a6 f9eac7", 60),
}
for name, (swatches, height) in ramps.items():
    im = Image.open(folder / (name + ".png")).convert("RGBA")
    # Remove stippling from the painted resin before taking the majority in each cell.
    rgb = im.convert("RGB").filter(ImageFilter.MedianFilter(5))
    rgb.putalpha(im.getchannel("A"))
    palette = [forge.parse_hex(color) for color in swatches.split()]
    idx, pal, _ = forge.pixelize_rgba(np.asarray(rgb), height, palette=palette,
                                       coverage=.24, outline="#302732")
    result = Image.fromarray(forge.render(idx, pal))
    # One-cell strokes restore the highlights and string swallowed by majority sampling.
    pen = ImageDraw.Draw(result)
    if name == "hero":
        pen.line([(6,2),(7,7)], fill="#f8e2bb")
        pen.line([(9,25),(10,46)], fill="#b1875c")
        pen.ellipse((25,25,28,30), fill="#8e433b")
        pen.line([(26,26),(26,28)], fill="#e3a863")
        pen.point((21,11), fill="#65373c")
    elif name == "atalanta":
        pen.line([(27,2),(21,14)], fill="#91663c")
        pen.line([(21,16),(29,34)], fill="#91663c")
        pen.line([(24,15),(39,15)], fill="#c99d64")
        pen.point((19,12), fill="#37353b")
    else:
        pen.line([(2,35),(3,38),(4,38)], fill="#ead2a6")
        pen.line([(11,39),(13,37),(14,35)], fill="#f9eac7")
        pen.line([(11,40),(13,38)], fill="#d6aa80")
        pen.point((12,28), fill="#c99361")
    result.save(folder / "pixel" / (name + ".png"))
    print(name, result.size)

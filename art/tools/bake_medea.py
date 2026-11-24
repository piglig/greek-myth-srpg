"""Register the six painted Medea keys, then bake walking and casting inbetweens."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

from bake_motion import ROOT, WD, HT, bake


def register():
    source = Image.open(Path(__file__).resolve().parents[1] / "originals/medea.png").convert("RGBA")
    atlas = Image.new("RGBA", (3 * WD, 2 * HT))
    for row in range(2):
        for col in range(3):
            key = source.crop((512*col, 512*row, 512*(col+1), 512*(row+1)))
            # UnitView expects the front plate to look left and the rear plate right.
            key = ImageOps.mirror(key)
            mask = key.getchannel("A").point(lambda a: 255 if a > 64 else 0)
            left, top, right, bottom = mask.getbbox()
            scale = 208 / (bottom-top)
            head = np.asarray(mask)[top+10:top+48]
            anchor = np.median(np.where(head)[1])
            body = key.crop((left, top, right, bottom)).resize(
                (round((right-left)*scale), 208), Image.Resampling.LANCZOS)
            atlas.alpha_composite(body, (col*WD+round(160-(anchor-left)*scale), row*HT+24))
    path = ROOT / "actors/medea.png"
    atlas.save(path)
    bake(path)


if __name__ == "__main__":
    register()

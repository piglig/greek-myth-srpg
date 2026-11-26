"""Register the wetland enemies' six gouache poses and bake them with agent-sprite-forge.

Run with the path to an agent-sprite-forge checkout as the first argument.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
# Use one scale for the entire animal, so the coiled snake's body stays thick
# when it extends, and the crab's walking legs never change shell size.
SCALE = {"marsh_snake": .62, "giant_crab": .60, "hera_priestess": .49,
         "stymphalian_bird": .60, "marsh_flock": .50, "hydra_head": .46}
FLIGHT_BASELINE = {"stymphalian_bird": 208, "marsh_flock": 202}


def register(name):
    source = Image.open(ROOT / "art/originals" / (name + ".png")).convert("RGBA")
    atlas = Image.new("RGBA", (960, 512))
    for row in range(2):
        for col in range(3):
            key = source.crop((col*512, row*512, (col+1)*512, (row+1)*512))
            key = ImageOps.mirror(key.crop(key.getbbox()))
            scale = SCALE[name]
            key = key.resize((round(key.width*scale), round(key.height*scale)), Image.Resampling.LANCZOS)
            # Center the weight-bearing mass, excluding the priestess's raised
            # staff, the snake's striking head and the crab's lifted pincer.
            alpha = np.asarray(key)[:, :, 3]
            band = alpha[round(key.height*.61):round(key.height*.88)]
            center = np.median(np.where((alpha if name in FLIGHT_BASELINE else band) > 128)[1])
            left = max(2, min(318-key.width, round(160-center)))
            atlas.alpha_composite(key, (col*320+left, row*256+FLIGHT_BASELINE.get(name, 238)-key.height))
    return atlas


if __name__ == "__main__":
    forge = sys.argv[1]
    with tempfile.TemporaryDirectory() as work:
        for name in sys.argv[2:] or SCALE:
            plates = Path(work) / (name + ".png")
            register(name).save(plates)
            subprocess.run([sys.executable, str(Path(__file__).with_name("bake_look.py")),
                            forge, name, name, str(plates)], check=True)

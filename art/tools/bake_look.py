"""Bake a whole set of sheets for a look repainted from another kind's drawings.

    python art/tools/bake_look.py <agent-sprite-forge checkout> <look> <base kind> <repainted actors sheet>

The repainted sheet has the layout of prototype/art/original/actors/<base kind>.png: the
same poses in the same places, with only the paint changed. It goes through the steps the
base kind went through (in-betweens, pixel bake, falls and special clips), and the result
is written to prototype/art/pixel/<look>/.
"""
from pathlib import Path
import shutil
import sys
import tempfile

forge, look, base, sheet = sys.argv[1:5]
sys.argv = [sys.argv[0], forge]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bake_motion
import bake_pixel_cast

with tempfile.TemporaryDirectory() as work:
    work = Path(work)
    for part in ("actors", "motion"):
        (work / "original" / part).mkdir(parents=True)
    plates = work / "original/actors" / (base + ".png")
    shutil.copyfile(sheet, plates)
    bake_motion.ROOT = work / "original"
    bake_motion.bake(plates)
    bake_pixel_cast.src = work / "original"
    bake_pixel_cast.dst = work / "pixel"
    bake_pixel_cast.bake(base)
    target = bake_pixel_cast.root / "prototype/art/pixel" / look
    target.mkdir(exist_ok=True)
    for baked in (work / "pixel" / base).glob("*.png"):
        shutil.copyfile(baked, target / baked.name)
print(look, "from", base)

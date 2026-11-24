"""Bake battle effects from a pixelfx checkout (https://github.com/patch-gg/pixelfx, MIT).

    python art/tools/bake_pixelfx.py <pixelfx checkout>

Each effect is rendered by pixelfx's own tool, recoloured to our pigments, then repacked
as one row of square frames centred on the point the game spawns it at, which is the
layout `view/battle_fx.gd` plays. Needs Node 18+ and Pillow.
"""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import numpy as np
from PIL import Image

kit = Path(sys.argv[1]).resolve()
out = Path(__file__).resolve().parents[2] / "prototype/art/thirdparty/pixelfx"
out.mkdir(parents=True, exist_ok=True)

BRONZE = ["#2a1a12", "#6b3a22", "#b5622e", "#e0a050", "#f5d9a0", "#fff6e0"]
DUST = ["#3d2e22", "#6a5340", "#93795d", "#b89f7f", "#d6c2a2", "#efe2c8"]
# The kit's own colours are made for dark fantasy backdrops: scarlet, violet, acid green.
# On pale limestone they shout. These ramps keep every effect inside the game's pigments.
EMBER = ["#2e2119", "#5c4433", "#a3552a", "#d98a3c", "#f2c887", "#fff3d6"]
OLIVE = ["#20260f", "#3a4520", "#5c6b2e", "#88964a", "#b7c07a", "#e4e8b8"]
INK = (38, 22, 14)


def tone_map(strip, ramp):
    """Repaint by brightness. Some effects keep their own colours whatever palette they get."""
    pixels = np.asarray(strip).astype(np.float32)
    value = pixels[..., :3] @ np.array([.2126, .7152, .0722], np.float32) / 255
    value = (value - value[pixels[..., 3] > 0].min()) / max(1e-3, np.ptp(value[pixels[..., 3] > 0]))
    stops = np.array([[int(c[i:i + 2], 16) for i in (1, 3, 5)] for c in ramp], np.float32)
    at = np.clip(value, 0, 1) * (len(stops) - 1)
    low = np.floor(at).astype(int).clip(0, len(stops) - 2)
    pixels[..., :3] = stops[low] + (stops[low + 1] - stops[low]) * (at - low)[..., None]
    return Image.fromarray(pixels.astype(np.uint8))


def ink_edge(strip):
    """A dark rim round the solid pixels: sparks drawn for a night sky must read on pale stone."""
    pixels = np.asarray(strip).copy()
    solid = pixels[..., 3] >= 200
    near = np.zeros_like(solid)
    near[1:] |= solid[:-1]; near[:-1] |= solid[1:]; near[:, 1:] |= solid[:, :-1]; near[:, :-1] |= solid[:, 1:]
    rim = near & (pixels[..., 3] < 120)
    pixels[rim] = (*INK, 215)
    return Image.fromarray(pixels)


# name -> (pixelfx id, fps, palette or None, centre in frame pixels or None for the pivot)
EFFECTS = {
    "hit": ("impacts/hit-spark", 20, BRONZE, None),
    "slash": ("melee/sword-slash", 20, BRONZE, (95, 48)),
    "dust": ("impacts/heavy-landing", 15, DUST, None),
    "flame": ("fire/campfire", 12, None, None),
    # What things carried do, and what happens to whoever they land on. Effects that draw
    # a stand-in body of their own (holy/heal, status/poisoned) are no use here. Nor are
    # the kit's skull-and-violet curse or its root snare: neither reads as ours whatever
    # the colour, and the game has only four ailments to show in any case.
    "bless": ("holy/blessing", 15, None, None),
    "burst": ("explosions/small-explosion", 18, None, None),
    "thud": ("impacts/blunt-hit", 20, BRONZE, None),
    "burning": ("status/burning", 15, None, None),
    "poisoned": ("nature/toxic-puddle", 15, None, None),
    "stunned": ("status/stunned", 15, None, None),
}
# Options an effect is rendered with besides its palette.
OPTIONS = {}
# Effects that run long: (every nth frame, how many). A strip wider than 16384 pixels will
# not load as a texture, and nobody waits five seconds for smoke to clear.
TAKE = {"burst": (2, 9), "bless": (2, 20), "poisoned": (2, 14)}
# Effects repainted by brightness into one of our ramps.
TONE = {"dust": DUST, "burst": EMBER, "thud": BRONZE, "poisoned": OLIVE}
manifest = {}
for name, (effect, fps, palette, centre) in EFFECTS.items():
    command = ["node", "tools/render.mjs", effect, "--sheet", "--fps", str(fps)]
    options = dict(OPTIONS.get(name, {}))
    if palette:
        options["palette"] = palette
    if options:
        command += ["--opts", json.dumps(options)]
    subprocess.run(command, cwd=kit, check=True, stdout=subprocess.DEVNULL)
    stem = kit / "records" / effect / effect.split("/")[1]
    meta = json.loads(stem.with_suffix(".json").read_text())["meta"]["pixelfx"]
    sheet = Image.open(stem.with_suffix(".png")).convert("RGBA")
    width, height = meta["frameSize"]
    cx, cy = centre or meta["pivot"]
    if name == "flame":
        side, cx, cy = max(width, height), width // 2, height // 2
    else:
        side = 2 * max(cx, width - cx, cy, height - cy)
    step, count = TAKE.get(name, (1, meta["frames"]))
    picked = list(range(0, meta["frames"], step))[:count]
    strip = Image.new("RGBA", (side * len(picked), side))
    for place, index in enumerate(picked):
        column, row = index % meta["columns"], index // meta["columns"]
        frame = sheet.crop((column * width, row * height, (column + 1) * width, (row + 1) * height))
        strip.paste(frame, (place * side + side // 2 - cx, side // 2 - cy))
    if name in TONE:
        strip = tone_map(strip, TONE[name])
    if name not in ("dust", "flame"):
        strip = ink_edge(strip)
    strip.save(out / f"{name}.png")
    manifest[name] = {"source": effect, "frames": len(picked), "fps": meta["fps"] / step, "frame": side,
                      "seconds": round(len(picked) * step / meta["fps"], 3), "pivot": meta["pivot"]}
    print(name, effect, strip.size, manifest[name])
(out / "effects.json").write_text(json.dumps(manifest, indent=1) + "\n")
for notice in ("LICENSE", "NOTICE.md"):
    shutil.copy(kit / notice, out / notice)

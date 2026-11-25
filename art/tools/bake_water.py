"""Pack the looping water pictures the marsh battles use into two atlases.

    python art/tools/bake_water.py <waves3 folder> <caustics frames folder>

Sources, both CC0 on OpenGameArt (see prototype/art/thirdparty/CREDITS.md):
  waves3  from "Seamless looping waves heightmaps" (waves.zip): 100 frames, 512 px, tiling
  frames  from "Water Caustics Effect (Small)" (Caustics.zip): 16 frames, 256 px, tiling

waves.png     10 x 5 cells, every other frame of the loop. Red and green are the slope of
              the surface (0.5 is level), blue its height.
caustics.png  4 x 4 cells, the light the ripples throw on the bed.

Each cell carries PAD pixels of its own far side round it, so a smooth sample near the
edge of a cell wraps onto itself and not onto the next frame. The water shader holds the
same numbers (view/lerna_water.gdshader).
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "prototype/art/thirdparty/water"
TILE = 256
PAD = 4


def padded(tile: np.ndarray) -> np.ndarray:
    return np.pad(tile, ((PAD, PAD), (PAD, PAD), (0, 0)), mode="wrap")


def atlas(tiles, columns):
    cell = TILE + 2 * PAD
    rows = (len(tiles) + columns - 1) // columns
    sheet = np.zeros((rows * cell, columns * cell, tiles[0].shape[2]), np.uint8)
    for i, tile in enumerate(tiles):
        y, x = divmod(i, columns)
        sheet[y * cell:(y + 1) * cell, x * cell:(x + 1) * cell] = padded(tile)
    return sheet


def main():
    waves, caustics = Path(sys.argv[1]), Path(sys.argv[2])
    OUT.mkdir(parents=True, exist_ok=True)
    tiles = []
    for path in sorted(waves.glob("*.png"))[::2]:
        height = np.asarray(Image.open(path).convert("L").resize((TILE, TILE), Image.LANCZOS), np.float32) / 255.0
        # Slope by central difference, wrapping, since the picture tiles.
        dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5
        dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5
        slope = np.clip(np.stack([dx, dy], -1) * 9.0 + 0.5, 0, 1)
        tiles.append((np.dstack([slope, height]) * 255).astype(np.uint8))
    assert len(tiles) == 50, len(tiles)
    Image.fromarray(atlas(tiles, 10)).save(OUT / "waves.png", optimize=True)
    light = []
    for path in sorted(caustics.glob("*.png")):
        light.append(np.asarray(Image.open(path).convert("L").resize((TILE, TILE), Image.LANCZOS))[:, :, None])
    assert len(light) == 16, len(light)
    Image.fromarray(atlas(light, 4)[:, :, 0]).save(OUT / "caustics.png", optimize=True)
    print("waves", len(tiles), "caustics", len(light))


if __name__ == "__main__":
    main()

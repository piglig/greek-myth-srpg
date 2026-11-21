"""Register the six isolated poses in each centaur painting on a common hoof line."""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image
from bake_motion import bake, ROOT

originals = Path(__file__).resolve().parents[1] / "originals"
sheets = {name: Image.new("RGBA", (1280, 512)) for name in ("centaur", "chiron")}
for side, suffix in enumerate(("", "-rear")):
    rgba = np.asarray(Image.open(originals / f"pholoe-centaurs{suffix}.png").convert("RGBA"))
    _, labels, boxes, _ = cv2.connectedComponentsWithStats(np.uint8(rgba[:, :, 3] > 10))
    bodies = sorted(range(1, len(boxes)), key=lambda i: -boxes[i, 4])[:6]
    for row, name in enumerate(sheets):
        poses = sorted((i for i in bodies if (boxes[i, 1] > 400) == bool(row)), key=lambda i: boxes[i, 0])
        assert len(poses) == 3
        for pose, index in enumerate(poses):
            x, y, w, h, area = boxes[index]
            crop = rgba[y:y+h, x:x+w].copy()
            crop[:, :, 3] *= (labels[y:y+h, x:x+w] == index)
            # Exclude the spear and bow from the body registration point.
            ys, xs = np.where(crop[int(.50*h):int(.78*h), :, 3] > 100)
            center = int(np.mean(xs))
            scale = .445 if name == "centaur" else .407
            sprite = Image.fromarray(crop).resize((round(w*scale), round(h*scale)), Image.Resampling.LANCZOS)
            frame = Image.new("RGBA",(320,256))
            frame.paste(sprite,(160-round(center*scale),239-sprite.height))
            dest = [0,1,2] if name == "centaur" else [0,2,3]
            sheets[name].paste(frame,(dest[pose]*320,side*256))
            if name == "chiron" and pose == 0:
                # Keep the wounded standing pose for the resting half of the gait.
                sheets[name].paste(frame,(320,side*256))
            if name == "centaur" and pose == 2:
                sheets[name].paste(frame,(960,side*256))
for name, image in sheets.items():
    path = ROOT/"actors"/f"{name}.png"
    image.save(path)
    bake(path)

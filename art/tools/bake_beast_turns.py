"""Register the chapter's painted quadrupeds to the existing 2D turning frames."""
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2] / "prototype/art"
CELL = (160, 128)


def silhouette_map(source, target):
    """Carry paint along the outline of each horizontal section."""
    src = np.array(source)
    dst = np.array(target)
    sy = np.where(src[:,:,3].max(axis=1)>100)[0]
    dy = np.where(dst[:,:,3].max(axis=1)>100)[0]
    mx = np.zeros((128,160), np.float32)
    my = np.zeros_like(mx)
    for y in dy:
        iy = round(np.interp(y,[dy[0],dy[-1]],[sy[0],sy[-1]]))
        sx = np.where(src[iy,:,3]>100)[0]
        dx = np.where(dst[y,:,3]>100)[0]
        if sx.size and dx.size:
            mx[y] = np.interp(np.arange(160),[dx[0],dx[-1]],[sx[0],sx[-1]])
            my[y] = iy
    return cv2.remap(src,mx,my,cv2.INTER_NEAREST)


def bake(kind):
    folder = ROOT / "original" / "cast" / kind
    frames = json.loads((folder / "frames.json").read_text())
    views = [Image.open(folder / f"view_{i}.webp").convert("RGBA") for i in range(8)]
    idle = Image.open(ROOT / "pixel" / kind / "actors.png").convert("RGBA")
    keys = {}
    for idx in (8,24,40,56):
        rear = int(idx in (24,40))
        pic = idle.crop((0,128*rear,160,128*(rear+1)))
        if idx in (8,40):
            pic = pic.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        keys[idx] = pic

    atlas = Image.new("RGBA",(1280,1024))
    for f in range(64):
        anchor = ((f//16)*16+8)%64
        offset = f-anchor
        # View zero was captured fifteen degrees left of the camera axis.
        phase = (f+64/24)%64
        view, sub = divmod(int(round(phase)),8)
        x,y,w,h,cx,cy = frames["turn_right"][view%8][sub]
        painted = views[view%8].crop((x,y,x+w,y+h))
        base = keys[anchor]
        ref = frames["idle"][(anchor//8)%8][0]
        bounds = base.getbbox()
        scale = (bounds[3]-bounds[1])/ref[3]
        center = (bounds[0]+bounds[2])/2
        cut = painted.resize((round(w*scale),round(h*scale)),Image.Resampling.LANCZOS)
        target = Image.new("RGBA",CELL)
        target.paste(cut,(round(center+(cx-ref[4]-ref[2]/2)*scale),
                          round(bounds[3]+(cy-ref[5]-ref[3])*scale)))
        # Match the settled painting at the diagonals. Both sources follow
        # the same intermediate silhouette, including on the moving feet.
        mix = min(1.,abs(offset)/5.)
        mix = mix*mix*(3-2*mix)
        if mix < 1 and offset:
            from_box,to_box = np.array(base.getbbox()),np.array(target.getbbox())
            box = np.rint(from_box*(1-mix)+to_box*mix).astype(int)
            cut = target.crop(tuple(to_box)).resize(tuple(box[2:]-box[:2]),Image.Resampling.LANCZOS)
            target = Image.new("RGBA",CELL)
            target.paste(cut,tuple(box[:2]))
            textured = silhouette_map(base,target)
            rgba = np.array(target)
            valid = textured[:,:,3]>100
            rgba[valid,:3] = (1-mix)*textured[valid,:3]+mix*rgba[valid,:3]
            target = Image.fromarray(rgba)
        if offset == 0:
            target = base
        target.putalpha(target.getchannel("A").point(lambda a:255 if a>=128 else 0))
        atlas.paste(target,(160*(f%8),128*(f//8)))
    atlas.save(ROOT / "pixel" / kind / "turns.png")


if __name__ == "__main__":
    for species in ("wolf","boar"):
        bake(species)

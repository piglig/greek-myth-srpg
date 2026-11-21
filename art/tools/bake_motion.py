"""Bake motion-compensated inbetweens from the registered original poses."""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2] / "prototype/art/original"
WD, HT = 320, 256
SUBSTEPS = 8
COLS = 16
solver = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
yy, xx = np.mgrid[:HT, :WD].astype(np.float32)


def prepare(frame):
    rgba = np.asarray(frame, dtype=np.float32) / 255
    rgba[:, :, :3] *= rgba[:, :, 3:]
    # Include silhouette edges in the correspondence search.
    gray = cv2.cvtColor(rgba[:, :, :3], cv2.COLOR_RGB2GRAY)
    return rgba, np.uint8((.72 * gray + .28 * rgba[:, :, 3]) * 255)


def warp_towards(paint, flow, fraction):
    # Invert the forward field at the intermediate pixel, not at the source.
    x, y = xx, yy
    for _ in range(3):
        sampled = cv2.remap(flow, x, y, cv2.INTER_LINEAR,
                            borderMode=cv2.BORDER_REPLICATE)
        x = xx - fraction * sampled[:, :, 0]
        y = yy - fraction * sampled[:, :, 1]
    return cv2.remap(paint, x, y, cv2.INTER_LINEAR)


# Landmarks on the original spear keys: tip, grip, face, shoulder, belt,
# trailing cloth, planted foot and the other foot. Coordinates are tile-local.
SPEAR_GUIDES = [
    {0: [(118,65),(145,132),(162,84),(180,108),(164,154),(193,174),(146,212),(180,232)],
     11:[(112,65),(144,148),(154,86),(174,110),(158,156),(199,162),(142,212),(179,233)],
     12:[(105,105),(148,146),(145,85),(167,105),(160,154),(209,138),(126,231),(181,203)],
     13:[(72,216),(136,161),(170,98),(186,112),(178,151),(239,139),(136,232),(236,206)],
     14:[(108,80),(153,149),(147,87),(169,111),(154,155),(205,144),(129,232),(186,206)]},
    {0: [(205,64),(179,133),(156,86),(164,105),(149,157),(119,177),(132,221),(171,232)],
     11:[(206,65),(180,134),(170,87),(170,108),(154,157),(116,176),(133,219),(166,232)],
     12:[(215,81),(185,114),(168,86),(170,104),(153,154),(107,151),(119,231),(173,199)],
     13:[(239,81),(201,103),(162,98),(168,113),(145,155),(95,162),(89,231),(183,203)],
     14:[(208,76),(180,138),(174,91),(171,110),(150,159),(117,170),(121,232),(181,221)]},
]


def guide_maps(source, target, t, intermediate=None, size=(WD,HT)):
    width,height=size
    gy,gx=(yy,xx) if size==(WD,HT) else np.mgrid[:height,:width].astype(np.float32)
    border = [(0,0),(width-1,0),(width-1,height-1),(0,height-1)]
    a, b = (np.float32(points + border) for points in (source, target))
    mid = (1-t)*a + t*b if intermediate is None else np.float32(list(intermediate) + border)
    mesh = cv2.Subdiv2D((0,0,width,height))
    for x, y in mid:
        mesh.insert((float(x),float(y)))
    maps = [np.dstack((gx, gy)).copy() for _ in range(2)]
    for tri in mesh.getTriangleList().reshape(-1,3,2):
        ids = np.argmin(np.sum((mid[None,:,:]-tri[:,None,:])**2,axis=2),axis=1)
        left, top, w, h = cv2.boundingRect(tri)
        coords = np.dstack((gx[top:top+h,left:left+w], gy[top:top+h,left:left+w]))
        mask = np.zeros((h,w),np.uint8)
        cv2.fillConvexPoly(mask,np.int32(np.rint(tri-[left,top])),1)
        for output, keys in zip(maps, (a,b)):
            transform = cv2.getAffineTransform(tri, keys[ids])
            patch = output[top:top+h,left:left+w]
            patch[mask!=0] = cv2.transform(coords,transform)[mask!=0]
    return maps


def between(a, b, guides=None):
    src, gray_a = a
    dst, gray_b = b
    if guides is None:
        forward = solver.calc(gray_a, gray_b, None)
        reverse = solver.calc(gray_b, gray_a, None)
    for i in range(SUBSTEPS):
        t = i / SUBSTEPS
        if guides is None:
            left = warp_towards(src, forward, t)
            right = warp_towards(dst, reverse, 1 - t)
        else:
            ma, mb = guide_maps(*guides, t)
            left = cv2.remap(src, ma, None, cv2.INTER_LINEAR)
            right = cv2.remap(dst, mb, None, cv2.INTER_LINEAR)
        # Registered, premultiplied paint keeps hands and shafts attached while
        # opacity covers or reveals the silhouette as the occlusion changes.
        rgba = left * (1 - t) + right * t
        rgba[:, :, :3] /= np.maximum(rgba[:, :, 3:], .00001)
        yield Image.fromarray(np.uint8(np.clip(rgba * 255 + .5, 0, 255)))


def bake(path):
    source = Image.open(path).convert("RGBA")
    count = source.width // WD
    gait = list(range(count-10, count-4)) if path.stem in ("hero", "wolf") else [0, 1]
    if path.stem == "refugee":
        gait = [0, 1, 0, 2]
    if path.stem == "hero":
        strike = [0,count-4,count-3,count-2,count-1,0]
    elif path.stem == "wolf":
        strike = [0,count-4,count-3,count-2,count-1,0]
    else:
        strike = [0,2,0]
    pairs = list(zip(gait, gait[1:]+gait[:1])) + list(zip(strike, strike[1:]))
    if path.stem in ("hero", "wolf"):
        pairs += [(0, 2), (2, 0), (gait[0], 0)]
    if path.stem == "chiron":
        pairs += [(2,3),(3,0)]
    if path.stem == "lion":
        pairs += [(0, 3), (3, 2), (2, 4), (4, 0)]
    rows = (len(pairs)*SUBSTEPS + COLS-1)//COLS
    sheet = Image.new("RGBA", (WD*COLS, HT*rows*2))
    for side in range(2):
        poses = [prepare(source.crop((i*WD,side*HT,(i+1)*WD,(side+1)*HT))) for i in range(count)]
        for pair, (a,b) in enumerate(pairs):
            landmarks = SPEAR_GUIDES[side] if path.stem == "hero" else {}
            guides = (landmarks[a], landmarks[b]) if a in landmarks and b in landmarks else None
            for i, frame in enumerate(between(poses[a], poses[b], guides)):
                index = pair*SUBSTEPS+i
                sheet.paste(frame, (index%COLS*WD, (side*rows+index//COLS)*HT))
    if path.stem == "atalanta":
        from bake_archer_turn import key, sample, bake_pivot
        bake_pivot(source)
        for side in range(2):
            carry,draw = key(source,side,0),key(source,side,2)
            for transition in range(2):
                for part in range(SUBSTEPS):
                    progress = part/SUBSTEPS
                    index = (len(gait)+transition)*SUBSTEPS+part
                    frame = sample(carry,draw,1-progress if transition else progress)
                    sheet.paste(frame,(index%COLS*WD,(side*rows+index//COLS)*HT))
    if path.stem == "heracles":
        from bake_heracles_motion import bake as bake_locomotion
        sheet = bake_locomotion(source, sheet)
    sheet.save(ROOT/"motion"/path.name)


if __name__ == "__main__":
    (ROOT/"motion").mkdir(exist_ok=True)
    for source in sorted((ROOT/"actors").glob("*.png")):
        bake(source)

"""Bake the spear hero's directional pivot from the approved drawings."""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageOps

from bake_motion import ROOT, WD, HT, SPEAR_GUIDES, prepare, guide_maps

SOURCE = Path(__file__).resolve().parents[1] / "originals/hero-turn.png"
STEPS = 8
# Tip, grip, face, shoulder, belt, cape and two soles in each new drawing.
GUIDES = [
    [(295,15),(307,244),(390,102),(439,180),(392,319),(510,350),(366,684),(413,685)],
    [(159,31),(264,243),(302,110),(360,182),(329,318),(467,356),(299,684),(417,653)],
    [(430,14),(423,232),(336,101),(365,178),(326,332),(209,406),(305,684),(359,684)],
]


def generated_key(sheet, i):
    cell = sheet.crop((724*i, 0, 724*(i+1), 724))
    factor = .25
    pivot = [(390,686),(333,686),(334,686)][i]
    origin = np.rint([160-pivot[0]*factor, 232-pivot[1]*factor]).astype(int)
    frame = Image.new("RGBA",(WD,HT))
    frame.paste(cell.resize((181,181),Image.Resampling.LANCZOS),tuple(origin))
    return frame, np.array(GUIDES[i])*factor + origin


def mirror(key):
    frame, points = key
    reflected = points.copy()
    reflected[:,0] = WD-1-reflected[:,0]
    return ImageOps.mirror(frame), reflected


def layers(frame, points):
    paint = prepare(frame)[0]
    tip, grip = points[:2]
    axis = grip-tip
    yy,xx = np.mgrid[:HT,:WD]
    along = ((xx-tip[0])*axis[0]+(yy-tip[1])*axis[1])/np.dot(axis,axis)
    across = abs((xx-tip[0])*axis[1]-(yy-tip[1])*axis[0])/np.linalg.norm(axis)
    shaft = (along > -.12) & (along < .91) & (across < 8.)
    weapon = paint * shaft[:,:,None]
    body = paint-weapon
    return body, weapon, body_guides(body,points[2,1],max(points[6:,1]),points[2,0])


def body_guides(body,head,foot,center=WD/2):
    mask = body[:,:,3] > .50
    # Register the visible sides of the torso in screen order. Anatomical
    # shoulder/cape landmarks swap sides during a pivot and fold a triangle.
    anchors = []
    for frac in [-.07, .0, .17, .32, .49, .65, .82, .96]:
        y = int(round(head + frac*(foot-head)))
        _,xs = np.where(mask[y-2:y+3])
        left,right = np.percentile(xs,[2,98]) if len(xs) else (center-3,center+3)
        anchors += [(left,y),(right,y)]
    return np.asarray(anchors,dtype=float)


def warp_shaft(layer, source, target):
    # Similarity about the grip keeps the straight shaft out of the torso mesh.
    def triangle(ends):
        tip,grip = ends
        dx,dy = tip-grip
        return np.float32([tip,grip,grip + [-dy,dx]])
    matrix = cv2.getAffineTransform(triangle(source),triangle(target))
    return cv2.warpAffine(layer,matrix,(WD,HT),flags=cv2.INTER_LINEAR)


def bake():
    source = Image.open(SOURCE).convert("RGBA")
    actor = Image.open(ROOT/"actors/hero.png").convert("RGBA")
    front, profile, rear = (generated_key(source,i) for i in range(3))
    near, far = [(actor.crop((0,i*HT,WD,(i+1)*HT)), np.array(SPEAR_GUIDES[i][0],float)) for i in range(2)]
    keys = [front,mirror(near),mirror(profile),far,rear,mirror(far),profile,near]
    atlas = Image.new("RGBA",(WD*8,HT*8))
    for sector,(frame,a) in enumerate(keys):
        next_frame,b = keys[(sector+1)%8]
        src, spear_a, guides_a = layers(frame,a)
        dst, spear_b, guides_b = layers(next_frame,b)
        for k in range(STEPS):
            t = k/STEPS
            mid = (1-t)*guides_a+t*guides_b
            mid[:10] -= .08*np.sin(np.pi*t)*(guides_b-guides_a)[:10]
            support = (sector//2)%2
            mid[12+support::2] = guides_a[12+support::2] + (guides_b-guides_a)[12+support::2]*t**2
            mid[13-support::2,1] -= 3*np.sin(np.pi*t)
            ma,mb = guide_maps(guides_a.tolist(),guides_b.tolist(),t,mid)
            l = cv2.remap(src,ma,None,cv2.INTER_LINEAR)
            r = cv2.remap(dst,mb,None,cv2.INTER_LINEAR)
            w = t*t*(3-2*t)
            ink = l*(1-w)+r*w
            ends = a[:2]*(1-t)+b[:2]*t
            ends[0,1] -= 2.2*np.sin(np.pi*t)
            weapon = warp_shaft(spear_a,a[:2],ends)*(1-w)+warp_shaft(spear_b,b[:2],ends)*w
            ink += weapon*(1-ink[:,:,3:])
            ink[:,:,:3] /= np.maximum(ink[:,:,3:],.00001)
            atlas.paste(Image.fromarray(np.uint8(np.clip(ink*255+.5,0,255))), (k*WD,sector*HT))
    folder = ROOT/"turns"
    folder.mkdir(exist_ok=True)
    atlas.save(folder/"hero.png")


if __name__ == "__main__":
    bake()

"""Register Atalanta's painted bow separately from her torso for turns and draws."""
import cv2
import numpy as np
from PIL import Image
from bake_motion import ROOT, WD, HT, prepare, guide_maps
from bake_hero_turn import body_guides, warp_shaft

# Per view and pose: face, grip, upper limb tip, and the weapon cutout.
MARKS = [
    [(66,(140,151),(120,78),[(115,74),(127,76),(143,119),(146,151),(145,202),(138,202),(137,157),(117,135)]),
     (75,(114,112),(143,40),[(139,36),(149,39),(124,98),(121,105),(120,125),(151,169),(146,181),(108,144),(105,120),(80,122),(79,112),(104,103),(104,76)])],
    [(70,(185,151),(199,86),[(189,83),(204,82),(207,134),(190,159),(181,203),(173,202),(179,154),(184,142)]),
     (69,(206,72),(182,25),[(177,21),(186,19),(213,46),(213,55),(228,54),(229,65),(214,69),(214,108),(191,144),(183,141),(198,87),(198,68)])],
]


def key(image, side, pose, mirrored=False):
    face,grip,tip,outline = MARKS[side][int(pose==2)]
    cell = image.crop((pose*WD,side*HT,(pose+1)*WD,(side+1)*HT))
    paint = prepare(cell)[0]
    mask = np.zeros((HT,WD),np.uint8)
    cv2.fillPoly(mask,[np.int32(outline)],1)
    bow = paint * mask[:,:,None]
    body = paint-bow
    ends = np.float32([tip,grip])
    if mirrored:
        body,bow = body[:,::-1].copy(),bow[:,::-1].copy()
        ends[:,0] = WD-1-ends[:,0]
    return body,bow,body_guides(body,face,237),ends


def sample(a,b,t,pivot=False):
    left,wl,ga,ea = a
    right,wr,gb,eb = b
    if t == 0 or t == 1:
        body,bow = (left,wl) if t==0 else (right,wr)
        ink = body+bow
    else:
        mid = ga*(1-t)+gb*t
        sway = np.sin(np.pi*t)
        if pivot:
            mid[12::2] = ga[12::2]+(gb-ga)[12::2]*t*t
            mid[13::2,1] -= 3*sway
        # Keep the wrists registered while the upper limb travels in an arc.
        ends = ea*(1-t)+eb*t
        ends[:,1] -= sway*(2 if pivot else 5)
        ma,mb = guide_maps(ga.tolist()+[ea[1].tolist()],gb.tolist()+[eb[1].tolist()],t,
                           np.vstack((mid,ends[1])))
        w = t*t/(t*t+(1-t)**2)
        ink = cv2.remap(left,ma,None,cv2.INTER_LINEAR)*(1-w)+cv2.remap(right,mb,None,cv2.INTER_LINEAR)*w
        weapon = warp_shaft(wl,ea,ends)*(1-w)+warp_shaft(wr,eb,ends)*w
        ink += weapon*(1-ink[:,:,3:])
    ink[:,:,:3] /= np.maximum(ink[:,:,3:],.00001)
    return Image.fromarray(np.uint8(np.clip(ink*255+.5,0,255)))


def bake_pivot(image):
    # The four carry keys look diagonally out from the board. Each intervening
    # quarter-turn has sixteen registered poses, including the wrap at north.
    ring = [key(image,0,0,True),key(image,1,0),key(image,1,0,True),key(image,0,0)]
    atlas = Image.new("RGBA",(8*WD,8*HT))
    for i in range(64):
        sector,part = divmod((i-8)%64,16)
        frame = sample(ring[sector],ring[(sector+1)%4],part/16,True)
        atlas.paste(frame,((i%8)*WD,(i//8)*HT))
    folder = ROOT/"turns"
    folder.mkdir(exist_ok=True)
    atlas.save(folder/"atalanta.png")

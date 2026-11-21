"""Register the new walk and turn drawings against the in-game idle silhouettes."""
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

from bake_motion import ROOT, WD, HT, COLS, SUBSTEPS, prepare, between, guide_maps
from bake_hero_turn import body_guides, warp_shaft

SOURCE = Path(__file__).resolve().parents[1] / "originals/heracles-motion.png"


def cut(sheet, row, col):
    edges = [0, 348, 696, sheet.height]
    width = sheet.width // 4
    cell = np.array(sheet.crop((col*width, edges[row], (col+1)*width, edges[row+1])))
    rgb = cell[:, :, :3].copy()
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    mask = np.where(hsv[:, :, 1] > 42, cv2.GC_PR_FGD, cv2.GC_PR_BGD).astype('uint8')
    mask[:3] = mask[-3:] = mask[:, :3] = mask[:, -3:] = cv2.GC_BGD
    cv2.grabCut(rgb, mask, None, np.zeros((1,65)), np.zeros((1,65)), 4, cv2.GC_INIT_WITH_MASK)
    _, labels, stats, _ = cv2.connectedComponentsWithStats(mask % 2)
    body = labels == 1 + stats[1:,cv2.CC_STAT_AREA].argmax()
    frame = Image.fromarray(np.dstack([rgb, body.astype('uint8') * 255]))
    return frame.crop(frame.getbbox())


def register(image, idle, factor, baseline=240):
    image = image.resize((round(image.width*factor), round(image.height*factor)), Image.Resampling.LANCZOS)
    # Match the painted palette and register the belt, not the swinging club.
    data = np.array(image)
    ref = np.array(idle)
    pigment = data[data[:,:,3]>200, :3]
    reference = ref[ref[:,:,3]>200, :3]
    gain = np.clip(np.median(reference,axis=0)/np.maximum(1,np.median(pigment,axis=0)),.72,1.25)
    data[:,:,:3] = np.clip(data[:,:,:3]*gain,0,255)
    def hips(alpha):
        y = round(alpha.shape[0]*.52)
        return np.median(np.where(alpha[y,:]>150)[0])
    bounds = idle.getbbox()
    center = bounds[0]+hips(ref[bounds[1]:bounds[3],bounds[0]:bounds[2],3])
    cell = Image.new("RGBA",(WD,HT))
    cell.paste(Image.fromarray(data),(round(center-hips(data[:,:,3])), baseline-image.height))
    return cell


# Tip and grip on each registered facing. Keep the club rigid through a pivot.
CLUB = [
    [(129,217),(138,171)], [(196,206),(172,161)], [(189,219),(172,171)],
    [(197,211),(177,174)], [(211,220),(203,171)], [(125,210),(141,174)],
    [(150,219),(166,172)], [(121,207),(149,160)],
]


def turn_key(image, ends):
    paint, _ = prepare(image)
    bounds = image.getbbox()
    head = bounds[1]+(bounds[3]-bounds[1])*.09
    ends = np.float32(ends)
    tip,grip = ends
    axis = grip-tip
    yy,xx = np.mgrid[:HT,:WD]
    along = ((xx-tip[0])*axis[0]+(yy-tip[1])*axis[1])/np.dot(axis,axis)
    across = abs((xx-tip[0])*axis[1]-(yy-tip[1])*axis[0])/np.linalg.norm(axis)
    club = paint * ((along>-.24)&(along<.97)&(across<10-6*np.clip(along,0,1)))[:,:,None]
    body = paint-club
    return body, body_guides(body,head,bounds[3]-3), club, ends


# Sole centres in tile space (screen-left, screen-right) for idle + four keys.
SOLES = [
    [[(151,217),(189,234)],[(166,231),(183,212)],[(165,231),(181,220)],
     [(153,230),(200,206)],[(158,205),(173,230)]],
    [[(129,218),(169,231)],[(141,233),(164,211)],[(150,232),(146,211)],
     [(143,232),(168,213)],[(142,229),(171,210)]],
]


def walk_guides(frame, soles):
    paint,_ = prepare(frame)
    bounds = frame.getbbox()
    head = bounds[1]+.09*(bounds[3]-bounds[1])
    torso = body_guides(paint,head,bounds[3]-3)[:12]
    return torso.tolist()+soles


def bake(source, combat):
    sheet = Image.open(SOURCE).convert("RGBA")
    cv2.setRNGSeed(42)
    art = [[cut(sheet,row,col) for col in range(4)] for row in range(3)]
    idle = [source.crop((0,side*HT,WD,(side+1)*HT)) for side in range(2)]
    heights = [cell.getbbox()[3]-cell.getbbox()[1] for cell in idle]
    # Keep the crown within three pixels of idle as the weight passes over a foot.
    rows = []
    for side in range(2):
        rows.append([register(frame,idle[side],(heights[side]-3*(i%2))/frame.height)
                     for i,frame in enumerate(art[side])])
    old_rows = combat.height//(2*HT)
    walk_frames = 6*SUBSTEPS
    total_rows = old_rows + walk_frames//COLS
    atlas = Image.new("RGBA",(WD*COLS,2*total_rows*HT))
    for side in range(2):
        atlas.paste(combat.crop((0,side*old_rows*HT,WD*COLS,(side+1)*old_rows*HT)),(0,side*total_rows*HT))
        a,b,c,d = rows[side]
        cycle = [idle[side],a,b,idle[side],c,d,idle[side]]
        sole_cycle = [SOLES[side][i] for i in (0,1,2,0,3,4,0)]
        guides = [walk_guides(frame,feet) for frame,feet in zip(cycle,sole_cycle)]
        for k,(first,last) in enumerate(zip(cycle,cycle[1:])):
            for i,frame in enumerate(between(prepare(first),prepare(last),(guides[k],guides[k+1]))):
                # Optical occlusion can thin the planted sole below the game's
                # alpha cutoff. Register its visible toe without moving the belt.
                if i:
                    visible = np.where(np.asarray(frame)[:,:,3] > 127)[0]
                    sole = int(visible.max())
                    belt = 166
                    if sole != 239:
                        lower = frame.crop((0,belt,WD,sole+1)).resize((WD,240-belt),Image.Resampling.BILINEAR)
                        frame.paste((0,0,0,0),(0,belt,WD,HT))
                        frame.paste(lower,(0,belt))
                index = k*SUBSTEPS+i
                atlas.paste(frame,((index%COLS)*WD,(side*total_rows+old_rows+index//COLS)*HT))
    front,left,back,right = [register(p,idle[0],heights[0]/max(im.height for im in art[2])) for p in art[2]]
    around = [front,ImageOps.mirror(idle[0]),right,idle[1],back,ImageOps.mirror(idle[1]),left,idle[0]]
    pivot = Image.new("RGBA",(WD*8,HT*8))
    for sector in range(8):
        a,ga,wa,ea = turn_key(around[sector],CLUB[sector])
        nxt = (sector+1)%8
        b,gb,wb,eb = turn_key(around[nxt],CLUB[nxt])
        for i in range(8):
            t = i/8
            ea_grip,eb_grip = ea[1].tolist(),eb[1].tolist()
            ma,mb = guide_maps(ga.tolist()+[ea_grip],gb.tolist()+[eb_grip],t)
            w = t*t*(3-2*t)
            ink = cv2.remap(a,ma,None,cv2.INTER_LINEAR)*(1-w)+cv2.remap(b,mb,None,cv2.INTER_LINEAR)*w
            ends = ea*(1-t)+eb*t
            ends[0,1] += np.sin(np.pi*t)*1.5
            weapon = warp_shaft(wa,ea,ends)*(1-w)+warp_shaft(wb,eb,ends)*w
            ink += weapon*(1-ink[:,:,3:])
            ink[:,:,:3] /= np.maximum(ink[:,:,3:],.00001)
            pivot.paste(Image.fromarray(np.uint8(np.clip(ink*255+.5,0,255))),(i*WD,sector*HT))
    pivot.save(ROOT/"turns/heracles.png")
    return atlas

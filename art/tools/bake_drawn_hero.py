"""Build this camera study from the registered drawings and their 2D inbetweens."""
import math
from pathlib import Path
import sys
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageOps
from bake_motion import ROOT, WD, HT, guide_maps

sys.path.insert(0, str(Path(sys.argv[1]) / "shared"))
import forge_hibit as fh

out = Path(__file__).resolve().parents[1] / "originals/hero-pixel-study"
actor = Image.open(ROOT / "actors/hero.png").convert("RGBA")
motion = Image.open(ROOT / "motion/hero.png").convert("RGBA")
pivot = Image.open(ROOT / "turns/hero.png").convert("RGBA")
palette = np.array([fh.parse_hex(s) for s in
    "211e24 32282b 4a3533 68483a 79604d 987960 b39a7e d0b497 eed7b5 63372e 894732 a35b3d c17c4e cb9b67 e8bc7b f9db9c".split()])
frames = []

def tile(sheet,x,y):
    return sheet.crop((x*WD,y*HT,(x+1)*WD,(y+1)*HT))

def finish(body, angle, lift=0, recoil=0, shield_pose=None):
    # Fit the shield strap to the near upper arm. Far-side shields sit behind the cloak.
    alpha = np.asarray(body)[:,:,3]
    yy,xx = np.where(alpha[106:126,100:216]>174)
    cx = np.median(xx)+100
    sy = 143 + np.median(yy)*.25 - lift*28 + recoil*5
    cx += 12 + lift*13 - recoil*4
    shield = Image.new("RGBA",body.size)
    pen = ImageDraw.Draw(shield)
    rx = 12+5*math.cos(angle)+8*lift
    ry = 27
    if shield_pose is not None:
        cx, sy, rx, flash = shield_pose
    def oval(dx,dy,a,b,ink):
        pen.ellipse((cx+dx-a,sy+dy-b,cx+dx+a,sy+dy+b),fill=ink)
    oval(0,0,rx,ry,"#35292a")
    oval(-1,-1,rx-1,ry-1,"#b99063")
    oval(-1,0,rx-3,ry-3,"#6e4233")
    oval(-2,-2,rx-4,ry-5,"#995237")
    # A raised bronze rim, lacquer shade bands and stamped bosses read at battle scale.
    box=(cx-rx+3,sy-ry+3,cx+rx-3,sy+ry-3)
    pen.arc(box,185,286,fill="#eed1a0",width=2)
    pen.arc(box,5,112,fill="#51372e",width=3)
    pen.arc((cx-rx+6,sy-ry+5,cx+rx-6,sy+ry-5),8,104,fill="#794632",width=3)
    for deg in range(0,360,45):
        phi=math.radians(deg)
        x=cx+(rx-5)*math.cos(phi)
        y=sy+(ry-5)*math.sin(phi)
        pen.ellipse((x-1.1,y-1.1,x+1.1,y+1.1),fill="#cb9b67")
    oval(-1,0,rx*.29,ry*.21,"#513b32")
    oval(-2,-1,rx*.24,ry*.17,"#bb905f")
    oval(-3,-2,rx*.13,ry*.08,"#edd2a4")
    if shield_pose is not None and flash > .15:
        pen.arc(box,295,350,fill="#f9db9c" if flash>.6 else "#cb9b67",width=3)
    if angle>math.pi*.57:
        shield.alpha_composite(body)
        body=shield
    else:
        body=Image.alpha_composite(body,shield)
    a=np.asarray(body)
    idx=fh.index_rgba(a,palette,75)
    small=fh.mode_downsample_blocks(idx,2,len(palette),coverage=.33)
    small=fh.clean_isolated(small,palette,passes=1)
    frames.append(Image.fromarray(fh.render(small,palette)))

rear=tile(actor,0,1)
finish(rear,3*math.pi/4)
for k in range(48):
    finish(tile(motion,k%16,7+k//16),3*math.pi/4)
# A short drawn landing bridges the stride to the planted, turning foot.
for k in range(8):
    t=104+k
    finish(tile(motion,t%16,7+t//16),3*math.pi/4)
for tick in range(24,7,-1):
    finish(tile(pivot,tick%8,tick//8),tick*math.pi/32)
idle=tile(actor,0,0)
# Redraw the shield arm over a clean patch of the original tunic and cloak.
base=np.array(ImageOps.mirror(idle))
mask=Image.new("L",idle.size)
ImageDraw.Draw(mask).polygon([(136,125),(146,120),(147,133),(143,146),(148,157),
                              (150,164),(143,166),(136,160),(134,151),(130,137)],fill=255)
base[:,:,:3]=cv2.inpaint(base[:,:,:3].copy(),np.array(mask),5,cv2.INPAINT_TELEA)
base=base.astype(np.float32)/255
base[:,:,:3]*=base[:,:,3:]
# Painted contours provide deformation guides, including the two soles and knees.
guides=np.float32([(201,65),(174,132),(157,84),(139,118),(155,154),(126,174),
                   (139,232),(173,210),(140,191),(170,184),(187,213)])

def bend_points(points, changes):
    return np.asarray(points)+np.asarray(changes)

def brace(lift, shield, elbow, load, flash):
    raised=np.float32([(2,0),(3,-1),(3,2),(3,2),(0,2),(-1,2),
                       (0,0),(0,0),(-2,1),(0,1),(0,0)])
    loaded=np.float32([(-18,8),(-12,8),(-17,9),(-13,9),(-16,11),(-17,10),
                       (0,0),(0,0),(-9,4),(-5,4),(0,0)])
    dst=bend_points(guides,raised*lift+loaded*load)
    remap,_=guide_maps(guides.tolist(),guides.tolist(),0,dst)
    ink=cv2.remap(base,remap,None,cv2.INTER_LINEAR)
    ink[:,:,:3]/=np.maximum(ink[:,:,3:],1e-5)
    body=Image.fromarray(np.uint8(np.clip(ink,0,1)*255))
    shoulder=dst[3]
    fore=shoulder + np.array([-1+13*lift-13*elbow,23-6*lift+3*elbow])
    grip=fore + np.array([4+17*lift-4*elbow,19-28*lift-3*elbow])
    # Draw the upper arm, brachial crease, forearm and wrist wrap at each pose.
    pen=ImageDraw.Draw(body)
    def stroke(a,b,r,s,color):
        axis=b-a
        normal=np.array([-axis[1],axis[0]])/np.linalg.norm(axis)
        pen.polygon([tuple(v) for v in (a+r*normal,b+s*normal,b-s*normal,a-r*normal)],fill=color)
    stroke(shoulder,fore,5.7,4.8,"#674333")
    stroke(shoulder+[1,1],fore+[1,-2],3.8,3.3,"#b78154")
    stroke(shoulder+[2,2],fore+[0,-6],2.0,2.5,"#d0a877")
    stroke(fore,grip,4.6,3.1,"#694534")
    stroke(fore+[1,-1],grip+[0,-1],3,2.2,"#bc8e63")
    stroke(fore*.28+grip*.72,grip,3.8,3.1,"#884734")
    center=grip + np.array([20.0-7*lift-3*shield,-16+10*lift+shield*1.5])
    radius=15.54+4*lift-4.8*shield
    finish(body,math.pi/4,shield_pose=(*center,radius,flash))

def curve(t,keys):
    for (start,a),(end,b) in zip(keys,keys[1:]):
        if t<=end:
            u=np.clip((t-start)/(end-start),0,1)
            return a+(b-a)*u*u*(3-2*u)
    return keys[-1][1]

for k in range(24):
    t=k/23
    brace(t*t*(3-2*t),0,0,0,0)
for k in range(40):
    t=k/39
    shield=curve(t,[(0,0),(.06,1),(.17,.64),(.39,.50),(.83,0)])
    elbow=curve(t,[(0,0),(.055,0),(.23,1),(.43,.91),(.82,0)])
    load=curve(t,[(0,0),(.12,.03),(.39,1),(.52,.98),(.88,.09),(1,0)])
    brace(1,shield,elbow,load,max(0.,1.-t/.12))
atlas=Image.new("RGBA",(160*12,128*math.ceil(len(frames)/12)))
for i,f in enumerate(frames): atlas.paste(f,(160*(i%12),128*(i//12)))
atlas.save(out/"hero-brace.png")
print(len(frames),atlas.size)

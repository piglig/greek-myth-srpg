"""Register original painted poses to the chapter camera and derive eight view samples.

These actors have front and rear paintings. Preserve their hand-painted action
keys and interpolate the apparent depth locally around their silhouettes.
"""
from pathlib import Path
import math
import sys
import cv2
import numpy as np
from PIL import Image
from bake_motion import prepare, between

root=Path(__file__).resolve().parents[2]/"prototype/art/original"
destination=Path(sys.argv[1])
height={"centaur":2.28,"chiron":2.28,"lion":1.75}
yy,xx=np.mgrid[:256,:320].astype(np.float32)

def render(kind):
    sheets=Image.open(root/"actors"/(kind+".png")).convert("RGBA")
    motion=Image.open(root/"motion"/(kind+".png")).convert("RGBA")
    out=destination/kind
    out.mkdir(parents=True,exist_ok=True)
    rows=motion.height//512
    scale=height.get(kind,1.88)/208/.015
    def tile(sheet,index,back,columns,side_rows):
        x=index%columns*320
        y=(index//columns+back*side_rows)*256
        return np.asarray(sheet.crop((x,y,x+320,y+256)))
    def row(clip,frame,images,lean=0):
        canvas=Image.new("RGBA",(2560,320))
        for idx in range(8):
            a=idx*math.pi/4-math.pi/12
            back=math.cos(a)<0
            img=images[int(back)]
            # Original poses face screen left in the front drawing.
            flip=(math.sin(a)>0) != back
            depth=cv2.distanceTransform((img[:,:,3]>90).astype(np.uint8),cv2.DIST_L2,3)
            depth=cv2.GaussianBlur(depth,(0,0),3)
            drift=math.cos(2*a)*(.28 if kind in ("chiron","centaur","lion") else .36)
            width=1-.14*math.cos(2*a)
            weight=np.clip((237-yy)/170,0,1)
            mx=160+(xx-160)/width+drift*depth+lean*weight**1.5
            warped=cv2.remap(img,mx.astype('float32'),yy,cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)
            pic=Image.fromarray(warped)
            if flip: pic=pic.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            pic=pic.resize((round(320*scale),round(256*scale)),Image.Resampling.LANCZOS)
            canvas.paste(pic,(320*idx+160-pic.width//2,round(222-240*scale)))
        canvas.save(out/f"{clip}-{frame:02}.png",compress_level=1)
    poses=sheets.width//320
    pairlist=[(0,2),(2,0)]
    gait=4 if kind=="refugee" else 2
    if kind=="chiron": pairlist += [(2,3),(3,0)]
    if kind=="lion": pairlist += [(0,3),(3,2),(2,4),(4,0)]
    idle=[tile(sheets,0,b,poses,1) for b in range(2)]
    for k in range(poses):
        row("pose"+str(k),0,[tile(sheets,k,b,poses,1) for b in range(2)])
    row("idle",0,idle)
    for f in range(gait*8):
        row("walk",f,[tile(motion,f,b,16,rows) for b in range(2)])
    for k,(a,b) in enumerate(pairlist):
        for f in range(8):
            row(f"from{a}to{b}",f,[tile(motion,(gait+k)*8+f,side,16,rows) for side in range(2)])
    for f in range(18):
        t=f/17
        row("hit",f,idle,15*math.sin(t*2*math.pi)*math.exp(-3*t))
    turns(out)

def turns(out):
    # Register neighboring painted views before interpolating a pivot. The same
    # sequence runs backwards for left turns so weapon lengths stay consistent.
    strip=Image.open(out/"idle-00.png").convert("RGBA")
    views=[prepare(strip.crop((320*d,0,320*(d+1),256))) for d in range(8)]
    phases=[Image.new("RGBA",(2560,320)) for _ in range(8)]
    for d,view in enumerate(views):
        for f,pic in enumerate(between(view,views[(d+1)%8])):
            phases[f].paste(pic,(320*d,0))
    for f,canvas in enumerate(phases):
        canvas.save(out/f"turn-{f:02}.png",compress_level=1)

if __name__=="__main__":
    for actor in sys.argv[2:]:
        render(actor)

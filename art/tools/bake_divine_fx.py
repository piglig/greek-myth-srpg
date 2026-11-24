"""Animate the five illustrated divine effects as neutral, tintable 96px strips."""
from pathlib import Path
import math
import shutil
import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[2]
FX=ROOT/"art/originals/fx"
GAME=ROOT/"prototype/art/original/fx"
FRAMES={"lightning":10,"skyfire":12,"thunderstep":8,"dome":10,"thunderbody":8}
Y,X=np.indices((96,96),dtype=np.float32)


def stamp(canvas,source,width,height,baseline,opacity=1):
    p=source.resize((max(1,round(width)),max(1,round(height))),Image.Resampling.LANCZOS)
    p.putalpha(p.getchannel("A").point(lambda a: int(a*opacity)))
    canvas.alpha_composite(p,((96-p.width)//2,round(baseline)-p.height))


def sparks(image,age):
    pen=ImageDraw.Draw(image)
    for k in range(13):
        angle=k*2.39996
        radius=(13+k%4*3)+age*22
        x=round(48+math.cos(angle)*radius)
        y=round(81+math.sin(angle)*radius*.25-math.sin(age*math.pi)*(7+k%4*2))
        light=int(222*(1-age))
        pen.line((x,y,x+round(2*math.cos(angle)),y-1),fill=(251,236,203,light),width=1)


def frame(name,key,i,count):
    out=Image.new("RGBA",(96,96))
    t=i/(count-1)
    if name=="lightning":
        if i<3:
            reveal=key.copy()
            alpha=np.asarray(key.getchannel("A")).copy()
            alpha[int((i+1)/3*key.height):]=0
            reveal.putalpha(Image.fromarray(alpha))
            stamp(out,reveal,65,87,85,.62+i*.13)
        elif i<7:
            stamp(out,key,[64,71,58,49][i-3],85,85,[1.,.76,.94,.37][i-3])
        if i>=3:sparks(out,(i-3)/7)
    elif name=="skyfire":
        if i<=5:
            stamp(out,key,16+4*i,29+5*i,13+72*(i/5)**1.6,.6+.08*i)
        else:
            u=(i-6)/5
            stamp(out,key,53+35*u,43-36*u,85,1-.8*u)
            for sign in (-1,1):
                side=Image.new("RGBA",out.size)
                stamp(side,key,18+6*u,24-16*u,83,.76-.60*u)
                out.alpha_composite(side,(sign*round(19+19*u),0))
            sparks(out,u*.90)
    elif name=="thunderstep":
        stamp(out,key,[17,43,75,85,74,69,63,51][i],[19,62,90,89,81,61,31,10][i],87,[.4,.75,1,.96,.75,.54,.36,.16][i])
    elif name=="dome":
        extent=[.12,.31,.61,.87,.99,1,1,.98,.96,.94][i]
        alpha=[.32,.58,.79,.90,.99,.78,1,.64,.34,.13][i]
        stamp(out,key,85+5*extent,62*extent,82,alpha)
    else:
        a=np.array(key.resize((96,96),Image.Resampling.LANCZOS))
        angle=2*math.pi*i/count
        bend=2.0*np.sin(angle+Y*.10)
        moved=cv2.remap(a,(X+bend).astype(np.float32),(Y+1.6*np.cos(angle+X*.08)).astype(np.float32),cv2.INTER_NEAREST)
        moved[:,:,3]=(moved[:,:,3]*(.72+.28*np.sin(angle+Y*.16))).astype(np.uint8)
        stamp(out,Image.fromarray(moved),68,90,91)
    # Keep the painterly value steps and clearing between marks at battlefield scale.
    a=np.array(out)
    coverage=a[:,:,3].astype(np.float32)
    a[:,:,3]=np.where(coverage<10,0,np.minimum(255,np.round(coverage/12)*12))
    return Image.fromarray(a)


if __name__=="__main__":
    for name,count in FRAMES.items():
        key=Image.open(FX/"divine-keys"/(name+".png")).convert("RGBA")
        strip=Image.new("RGBA",(96*count,96))
        for i in range(count):strip.paste(frame(name,key,i,count),(96*i,0))
        strip.save(FX/(name+".png"))
        shutil.copyfile(FX/(name+".png"),GAME/(name+".png"))

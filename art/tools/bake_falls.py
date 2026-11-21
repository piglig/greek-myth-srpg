"""Animate painted cutouts, registered to the same ground line as their idle cell."""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

FRAMES=56

def ramp(t,a,b):
    u=np.clip((t-a)/(b-a),0,1)
    return u*u*(3-2*u)

def rotate(degrees):
    a=np.deg2rad(degrees)
    return np.array([[np.cos(a),-np.sin(a)],[np.sin(a),np.cos(a)]])

def eased_distance(value, center, width):
    return np.clip((value-center)/width+.5,0,1)

def samples(paint):
    y,x=np.nonzero(paint[:,:,3])
    sub=(np.arange(4)+.5)/4-.5
    dx,dy=np.meshgrid(sub,sub)
    pos=np.stack([(x[:,None]+dx.ravel()).ravel(),(y[:,None]+dy.ravel()).ravel()],axis=1)
    return pos, np.repeat(paint[y,x],16,axis=0)

def pose(kind,points,colors,rear,t):
    x,y=points.T
    # Both source plates face left in this working space.
    front=ramp(t,.11,.48)
    hind=ramp(t,.28,.69)
    spill=ramp(t,.24,.73)
    recoil=np.sin(np.pi*ramp(t,0,.21))
    settle=np.sin(np.pi*ramp(t,.68,.90))
    if kind=='bandit':
        hip=np.array([78,80])
        root_angle=8*recoil+80*spill-4*settle
        leg_groups=[(x<81,(72,84),(69,99),-75*front+175*spill,96*hind),
                    (x>=81,(91,84),(95,101),-53*hind+147*spill,117*spill)]
        cut=86 if not rear else 88
    elif kind=='wolf':
        hip=np.array([85,65])
        root_angle=5*recoil+(-15*front+40*hind if not rear else -34*front+7*hind)
        if rear:
            leg_groups=[(x<78,(59,67),(59,89),-76*front,112*front),
                        (x>=78,(91,86),(99,101),78*hind,-96*hind)]
            cut=np.where(x<78,75,91)
        else:
            leg_groups=[(x<83,(66,74),(65,98),-85*front,108*front),
                        (x>=83,(102,54),(108,75),68*hind,-98*hind)]
            cut=np.where(x<83,np.where(x<50,99,81),62)
    else:
        hip=np.array([83,81])
        root_angle=4*recoil-16*front+18*hind-2*settle
        leg_groups=[(x<78,(58,86),(56,103),-89*front,114*front),
                    (x>=78,(92,85),(95,101),76*hind,-113*hind)]
        cut=89
    def transform(data, pivot, dest, angle):
        return (data-pivot)@rotate(angle).T+dest

    root=hip+np.array([3*recoil,0])
    body=transform(points,hip,root,root_angle)
    deformed=body.copy()
    for zone,upper,knee,thigh,shin in leg_groups:
        upper,knee=np.array(upper),np.array(knee)
        if kind=="bandit":
            thigh-=root_angle*spill
            shin-=root_angle*spill
        elbow=transform(upper,hip,root,root_angle)
        folded=transform(points,upper,elbow,root_angle+thigh)
        tip=transform(knee,upper,elbow,root_angle+thigh)
        lower=transform(points,knee,tip,root_angle+shin)
        folded+=(lower-folded)*eased_distance(y,knee[1],11)[:,None]
        weight=zone*eased_distance(y,cut,12)
        if kind=='wolf' and not rear:
            weight*=1-eased_distance(x,114,7)  # the tail follows the spine
        if kind=='centaur':
            weight*=1-eased_distance(x,106,8)
        deformed+=(folded-body)*weight[:,None]

    if kind=='centaur':
        waist=np.array([67 if not rear else 71,72])
        folded=transform(points,waist,transform(waist,hip,root,root_angle),
                         root_angle-71*spill+3*settle)
        human=(1-eased_distance(y,73,15))*(1-eased_distance(x,84 if not rear else 83,10))
        deformed+=(folded-body)*human[:,None]
    if kind=='wolf':
        # Set the flank onto the ground after the near foreleg folds.
        deformed[:,1]-=(deformed[:,1]-78)*.22*spill
    deformed[:,1]+=np.max(y)-np.max(deformed[:,1])
    px,py=np.rint(deformed).astype(int).T
    inside=(px>=0)&(px<160)&(py>=0)&(py<128)
    canvas=np.zeros((128,160,4),np.uint8)
    canvas[py[inside],px[inside]]=colors[inside]
    if t>.14:
        count,labels,stats,_=cv2.connectedComponentsWithStats(canvas[:,:,3])
        for i in range(1,count):
            if stats[i,cv2.CC_STAT_AREA]<8:
                canvas[labels==i]=0
    return Image.fromarray(canvas)

def bake(folder: Path,grapple=False):
    with Image.open(folder/'actors.png') as source:
        if folder.name in ('boar','lion'):
            from bake_beast_contact import bake as bake_contact
            sheet=bake_contact(source,folder.name,grapple)
            sheet.save(folder/('wrestle.png' if grapple else 'fall.png'),compress_level=4)
            return
        atlas=Image.new('RGBA',(8*160,14*128))
        for side in (0,1):
            cell=source.crop((0,side*128,160,(side+1)*128))
            if side:cell=cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            points,colors=samples(np.array(cell))
            for frame in range(FRAMES):
                tile=pose(folder.name,points,colors,side,frame/(FRAMES-1))
                if side:tile=tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                atlas.paste(tile,(frame%8*160,(side*7+frame//8)*128))
        atlas.save(folder/'fall.png',compress_level=4)

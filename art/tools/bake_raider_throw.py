"""Paired grab keys, registered to the first chapter's painted bodies and fall."""
import cv2
import numpy as np
from PIL import Image
from bake_motion import guide_maps
from bake_player_falls import sample_keys

def cell(sheet, col, row):
    return sheet.crop((160*col,128*row,160*(col+1),128*(row+1)))

# Face, forward hand, shield/shoulder, pelvis, forward boot and rear boot.
# The low thrust painting carries the spear back across the shoulder.
HOLDER = [
    [[(80,42),(71,66),(93,73),(82,82),(74,104),(91,116)],
     [(68,56),(55,70),(80,73),(85,84),(56,116),(105,106)],
     [(78,55),(65,73),(93,74),(89,84),(66,116),(116,109)]],
    [[(81,42),(87,66),(70,70),(78,83),(91,106),(68,116)],
     [(84,52),(98,65),(69,70),(77,85),(100,101),(59,116)],
     [(84,56),(104,63),(71,70),(76,83),(94,111),(63,103)]]]

def render_pose(plates, guides, a, b, dest, t):
    left,right=guide_maps(guides[a].tolist(),guides[b].tolist(),t,dest,size=(160,128))
    mix=cv2.addWeighted(cv2.remap(plates[a],left,None,cv2.INTER_LINEAR),1-t,
                        cv2.remap(plates[b],right,None,cv2.INTER_LINEAR),t,0.)
    rgba=cv2.cvtColor(mix,cv2.COLOR_mRGBA2RGBA)
    rgba[:,:,3]=np.where(rgba[:,:,3]>=128,255,0)
    return Image.fromarray(rgba)

def bake(folder):
    source=Image.open(folder/'actors.png').convert('RGBA')
    hero=folder.name=='hero'
    fall=None if hero else Image.open(folder/'fall.png').convert('RGBA')
    sheet=Image.new('RGBA',(1280,1792))
    for rear in (0,1):
        if hero:
            guides=np.array(HOLDER[rear],float)
            poses=[cv2.cvtColor(np.array(cell(source,i,rear)),cv2.COLOR_RGBA2mRGBA) for i in (0,3,4)]
            idle,low,turn=guides
            sign=1 if rear else -1
            grip=low.copy();grip[:2]+=[sign*5,-3];grip[1]+=[sign*4,0]
            grip[4:]=idle[4:]+[[sign*6,0],[-sign*3,0]]
            sink=grip.copy();sink[:4,1]+=[6,4,5,7]
            release=turn.copy();release[1]+=[sign*12,-9];release[3]+=[sign*3,-3]
            release[4:]=grip[4:]+[[sign*2,0],[sign*7,-3]]
            stages=[(0,0,idle),(12,1,grip),(17,1,grip),(24,1,sink),(32,2,release),
                    (40,2,turn),(55,0,idle)]
            for (f,a,start),(g,b,end) in zip(stages,stages[1:]):
                for k in range(f,g+1):
                    t=(k-f)/(g-f);t=t*t*(3-2*t)
                    tile=render_pose(poses,guides,a,b,start*(1-t)+end*t,t)
                    sheet.paste(tile,(160*(k%8),128*(7*rear+k//8)))
        else:
            # Meet the sleeve with the upper body first. At landing use the
            # identical painted fall cell that the fatal sequence resumes from.
            stages=[(0,0,0,0),(12,4,-9,2),(17,4,-9,2),(24,10,-13,5),
                    (32,28,4,0),(40,34,0,0),(44,46,0,0),(48,28,-1,0),(52,12,-2,0),(55,0,0,0)]
            y,x=np.mgrid[:128,:160].astype(np.float32)
            weight=np.clip((117-y)/55,0,1)
            for k in range(56):
                key,reach,dip=sample_keys(stages,k)
                def pose(n):
                    return np.array(cell(fall,n%8,7*rear+n//8))
                lo=int(key);t=key-lo
                rgba=cv2.addWeighted(pose(lo),1-t,pose(min(55,lo+1)),t,0.)
                tuck=max(0,1-abs(k-32)/8)
                shin=np.clip((y-95)/20,0,1)
                map_x=x+weight*reach*(-1 if not rear else 1)
                map_y=y-weight*dip+5*tuck*shin
                rgba=cv2.remap(rgba,map_x.astype(np.float32),map_y.astype(np.float32),cv2.INTER_NEAREST)
                rgba[:,:,3]=np.where(rgba[:,:,3]>=128,255,0)
                sheet.paste(Image.fromarray(rgba),(160*(k%8),128*(7*rear+k//8)))
    sheet.save(folder/'throw.png',compress_level=4)

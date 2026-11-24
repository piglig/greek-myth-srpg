"""Relax the bowstring on the approved draw key, then return to the painted idle."""
import cv2
import numpy as np
from PIL import Image, ImageDraw
from bake_motion import between, prepare

def release(draw, rear):
    paint = np.array(draw)
    grip = (111,37) if rear else (49,44)
    top, bottom = ((95,12),(97,68)) if rear else ((67,15),(65,75))
    # Erase only the exposed shaft and the isolated, drawn-back string.
    if rear:
        paint[32:36,115:] = 0
        paint[33:36,85:108] = 0
    else:
        paint[39:43,:46] = 0
        paint[40:42,53:69] = 0
    for y in range(top[1]+2,bottom[1]-1):
        occupied = np.flatnonzero(paint[y,:,3])
        for run in np.split(occupied,np.where(np.diff(occupied)>1)[0]+1):
            if len(run) and len(run)<=2:
                x=run.mean()
                if (rear and 82<x<min(98,grip[0])) or (not rear and 66<x<82):
                    paint[y,run]=0
    backing=Image.new("RGBA",draw.size)
    ImageDraw.Draw(backing).line([top,bottom],fill=(94,70,54,255))
    # Recoil originates at the drawing elbow and fades before it reaches the waist.
    y,x=np.indices((128,160),dtype=np.float32)
    elbow=(53,36) if rear else (109,42)
    w=np.exp(-((x-elbow[0])/15)**2-((y-elbow[1])/12)**2)
    sign=-1 if rear else 1
    body=cv2.remap(paint,x-sign*3*w,y+w,cv2.INTER_NEAREST)
    backing.alpha_composite(Image.fromarray(body))
    return backing

def phalerus_release(draw, rear):
    # Trace the empty space beside his forearm in each native painted key.
    # The wrist and wooden limbs stay in place as the shaft clears the bow.
    pose = draw.copy()
    erase = ImageDraw.Draw(pose)
    if rear:
        top, bottom = (112,14), (112,73)
        string_gaps = [[(111,15),(110,19),(93,39),(92,36)],
                       [(96,54),(112,72),(108,70),(95,56)]]
        shaft = (99,40,136,42)
        wrist = (123,40,127,42)
        elbow = (54,41)
    else:
        top, bottom = (45,17), (45,74)
        string_gaps = [[(47,18),(68,38),(67,40),(47,22)],
                       [(45,72),(60,56),(61,59),(46,74)]]
        shaft = (24,40,59,43)
        wrist = (31,40,34,43)
        elbow = (92,44)
    for polygon in string_gaps:
        erase.polygon(polygon, fill=0)
    erase.rectangle(shaft, fill=0)
    x,y,r,b = wrist
    pose.paste(draw.crop((x,y-2,r+1,y)).resize((r-x+1,b-y+1)),(x,y))
    y,x = np.indices((128,160),dtype=np.float32)
    recoil = np.exp(-((x-elbow[0])/14)**2-((y-elbow[1])/10)**2)
    body = cv2.remap(np.array(pose),x+(3 if rear else -3)*recoil,y+recoil,cv2.INTER_NEAREST)
    relaxed = Image.new("RGBA", draw.size)
    ImageDraw.Draw(relaxed).line([top,bottom],fill=(161,126,82,255))
    relaxed.alpha_composite(Image.fromarray(body))
    return relaxed


def bake_release(folder, release_key=release):
    with Image.open(folder/'actors.png') as source, Image.open(folder/'motion.png') as motion:
        actors=Image.new('RGBA',(640,256))
        actors.paste(source,(0,0))
        rows=motion.height//256
        sheet=Image.new('RGBA',(motion.width,(rows+1)*256))
        for side in range(2):
            top=side*128
            idle=source.crop((0,top,160,top+128))
            pose=release_key(source.crop((320,top,480,top+128)),bool(side))
            actors.paste(pose,(480,top))
            offset=side*(rows+1)*128
            sheet.paste(motion.crop((0,side*rows*128,motion.width,(side+1)*rows*128)),(0,offset))
            def large(image):
                return prepare(image.resize((320,256),Image.Resampling.NEAREST))
            for i,frame in enumerate(between(large(pose),large(idle))):
                cell=frame.resize((160,128),Image.Resampling.NEAREST)
                cell.putalpha(cell.getchannel('A').point(lambda a:255 if a>=128 else 0))
                sheet.paste(cell,(160*i,offset+rows*128))
    actors.save(folder/'actors.png')
    sheet.save(folder/'motion.png')

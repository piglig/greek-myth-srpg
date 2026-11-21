"""First-chapter raiders, from their two painted idle views."""
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageOps
from bake_falls import eased_distance, rotate, samples
from bake_player_falls import bent_knee, sample_keys, segment, stamp

# Pelvis offset, torso lean, foot slide and bow arm swing.
ARCHER=[(0,0,0,0,0,0),(5,1,1,5,0,2),(12,1,3,8,0,13),
        (20,0,7,12,.03,30),(29,-1,15,29,.18,39),(40,-2,24,67,.72,38),
        (47,-2,27,83,1,30),(55,-2,27,81,1,28)]
CHIEF=[(0,0,0,0,0,0),(7,2,2,8,0,0),(15,-1,6,-8,.02,0),
       (28,-1,7,-9,.03,0),(33,0,10,-5,.05,0),(38,1,17,17,.19,0),
       (44,2,25,65,.7,0),(47,3,29,89,.95,0),(51,3,27,83,1,0),(55,3,28,86,1,0)]

def bake(plates,archer):
    atlas=Image.new('RGBA',(1280,1792))
    for rear,plate in enumerate(plates):
        paint=np.array(ImageOps.mirror(plate) if rear else plate)
        hip=np.array([85.,81.])
        if archer:
            limb=([(54,37),(58,40),(61,46),(61,55),(65,62),(69,67),(72,75),(78,83)]
                  if not rear else [(58,35),(62,42),(60,50),(59,58),(63,66),(65,71),(65,80),(70,91)])
            grip=np.array(limb[5],dtype=float)
            shoulder=np.array([76.,45.] if not rear else [73.,46.])
            mask=np.zeros((128,160),np.uint8)
            cv2.polylines(mask,[np.int32(limb)],False,255,3)
            prop=paint.copy()
            prop[mask==0]=0
            wood,wood_color=samples(prop)
            paint[mask!=0]=0
        points,color=samples(paint)
        x,y=points.T
        legs=([(79,81,79,95,73,105),(90,82,99,99,99,117)] if not rear else
              [(76,82,76,98,71,117),(89,82,94,95,97,110)])
        if not archer:
            legs=([(77,82,76,96,69,106),(88,82,94,99,97,116)] if not rear else
                  [(75,84,71,99,68,113),(94,85,99,97,101,110)])
        for frame in range(56):
            dx,dy,lean,slide,swing=sample_keys(ARCHER if archer else CHIEF,frame)
            pelvis=hip+[dx,dy]
            upper=(points-hip)@rotate(lean).T+pelvis
            body=upper.copy()
            for j,leg in enumerate(legs):
                h,k,a=np.array(leg,float).reshape(3,2)
                H=(h-hip)@rotate(lean).T+pelvis
                A=a+slide*np.array([-24 if j else -30,1 if j else 5])
                K=bent_knee(H,A,np.linalg.norm(k-h),np.linalg.norm(a-k),1)
                thigh=segment(points,h,k,H,K)
                shin=segment(points,k,a,K,A)
                split=eased_distance(x,85,4)
                w=(split if j else 1-split)*eased_distance(y,86,10)*min(1,dy/5)
                body+=(thigh+(shin-thigh)*eased_distance(y,k[1],8)[:,None]-upper)*w[:,None]
            if archer:
                # Rotate from the shoulder, keeping the hand on the wooden grip.
                S=(shoulder-hip)@rotate(lean).T+pelvis
                lower=rotate(lean)@np.array([0.,swing*.12])
                hand=(grip-shoulder)@rotate(lean+swing*.48).T+S+lower
                arm=(points-shoulder)@rotate(lean+swing*.48).T+S+lower
                w=np.exp(-((x-grip[0])/8)**2)*eased_distance(y,48,12)*(1-eased_distance(y,72,8))
                body+=(arm-upper)*w[:,None]
                # The freed drawing hand recoils briefly before the shoulders drop.
                twitch=sample_keys([(0,0),(4,1),(10,.15),(16,0),(55,0)],frame)[0]
                body+=np.exp(-((x-98)/7)**2-((y-73)/10)**2)[:,None]*[2*twitch,-2*twitch]
                angle=lean-swing*.84
            excess=max(0,body[:,1].max()-119)
            body[:,1]-=excess
            canvas=np.zeros((128,160,4),np.uint8)
            if archer:
                hand[1]-=excess
                # On contact let the bow roll around the fingers until its
                # lowest tip fits the ground plane. Keep the grip registered.
                tips=np.array([limb[0],limb[-1]])-grip
                for step in range(86):
                    candidates=[angle+step,angle-step]
                    chosen=min(candidates,key=lambda a:(tips@rotate(a).T)[:,1].max())
                    if (tips@rotate(chosen).T)[:,1].max()+hand[1]<=119:
                        angle=chosen
                        break
                bow=(wood-grip)@rotate(angle).T+hand
                ends=(np.array([limb[0],limb[-1]])-grip)@rotate(angle).T+hand
                loose=sample_keys([(0,1),(3,-.22),(6,.14),(10,0),(55,0)],frame)[0]
                middle=(ends[0]+ends[1])*.5+rotate(angle)@np.array([4.2*loose,0])
                img=Image.fromarray(canvas)
                ImageDraw.Draw(img).line([tuple(v) for v in (ends[0],middle,ends[1])],fill=(104,84,64,255))
                canvas=np.array(img)
                stamp(canvas,bow,wood_color)
            stamp(canvas,body,color)
            result=Image.fromarray(canvas)
            if rear:result=ImageOps.mirror(result)
            atlas.paste(result,(frame%8*160,(7*rear+frame//8)*128))
    return atlas

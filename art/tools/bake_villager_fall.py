"""A startled escort shields his face, takes a missed step and folds onto his side."""
import cv2
import numpy as np
from PIL import Image, ImageOps
from bake_falls import rotate, samples, eased_distance
from bake_player_falls import bent_knee, sample_keys, segment, stamp

# Pelvis x/y, trunk angle, protective gesture, near/far foot offsets.
KEYS = [(0,0,0,0,0,0,0,0,0), (5,2,1,8,.65,0,0,0,0),
        (10,3,3,13,1,0,0,1,-2), (18,6,4,19,1,0,0,10,-6),
        (23,8,5,12,.96,1,0,13,0), (29,9,9,21,.88,3,-2,13,0),
        (37,8,18,48,.81,-5,-3,10,0), (46,7,28,79,.72,-16,2,-10,0),
        (50,7,30,86,.68,-18,3,-12,0), (55,7,29,84,.66,-18,3,-12,0)]

def bake(plates):
    atlas=Image.new('RGBA',(1280,1792))
    for rear,plate in enumerate(plates):
        paint=np.array(ImageOps.mirror(plate) if rear else plate)
        if rear:
            outline=[(67,43),(72,47),(70,54),(67,61),(65,69),(64,74),(60,76),(58,72),(61,60),(62,54)]
            shoulder,elbow,wrist=np.array([(69,45),(65,57),(61,72)],float)
        else:
            outline=[(87,42),(92,43),(94,49),(94,54),(91,57),(86,57),(77,54),(73,53),(71,50),(73,47),(77,48),(82,50),(87,50)]
            shoulder,elbow,wrist=np.array([(88,42),(91,53),(74,50)],float)
        cut=np.zeros(paint.shape[:2],np.uint8)
        cv2.fillPoly(cut,[np.int32(outline)],255)
        mask=(cut>0)&(paint[:,:,3]>0)
        arm=paint.copy()
        arm[~mask]=0
        arm_points,arm_color=samples(arm)
        # Restore a narrow backing of cloth under the lifted arm. Pixels at
        # the outside edge of the sleeve reveal the background as it moves.
        core=cv2.erode(paint[:,:,3],np.ones((5,5),np.uint8))>0
        paint[:,:,:3]=cv2.inpaint(paint[:,:,:3],mask.astype(np.uint8),3,cv2.INPAINT_TELEA)
        paint[mask & ~core,3]=0
        points,color=samples(paint)
        x,y=points.T
        hip=np.array([78.,80.])
        legs=([(70,80,71,98,66,113),(83,81,84,99,84,117)] if not rear else
              [(69,81,70,98,69,116),(83,80,85,97,84,111)])
        forearm=arm_points-elbow
        axis=wrist-elbow
        blend=np.clip((forearm@axis)/(axis@axis)*5+.24,0,1)[:,None]
        for frame in range(56):
            dx,dy,lean,guard,ax,ay,bx,by=sample_keys(KEYS,frame)
            pelvis=hip+[dx,dy]
            upper=(points-hip)@rotate(lean).T+pelvis
            body=upper.copy()
            for j,leg in enumerate(legs):
                h,k,a=np.array(leg,float).reshape(3,2)
                H=(h-hip)@rotate(lean).T+pelvis
                A=a+([bx,by] if j else [ax,ay])
                K=bent_knee(H,A,np.linalg.norm(k-h),np.linalg.norm(a-k),1)
                thigh=segment(points,h,k,H,K)
                shin=segment(points,k,a,K,A)
                split=eased_distance(x,77,4)
                weight=eased_distance(y,86,10)*(split if j else 1-split)*min(1,dy/4)
                body+=(thigh+(shin-thigh)*eased_distance(y,98,6)[:,None]-upper)*weight[:,None]
            S=(shoulder-hip)@rotate(lean).T+pelvis
            lift=(38 if rear else 43)*guard
            E=(elbow-shoulder)@rotate(lean+lift).T+S
            sleeve=(arm_points-shoulder)@rotate(lean+lift).T+S
            hand=forearm@rotate(lean+(-147 if rear else 62)*guard).T+E
            raised=sleeve+(hand-sleeve)*blend
            excess=max(0,body[:,1].max()-119,raised[:,1].max()-119)
            canvas=np.zeros((128,160,4),np.uint8)
            stamp(canvas,body-[0,excess],color)
            stamp(canvas,raised-[0,excess],arm_color)
            tile=Image.fromarray(canvas)
            if frame==0:tile=ImageOps.mirror(plate) if rear else plate
            if rear:tile=ImageOps.mirror(tile)
            atlas.paste(tile,(frame%8*160,(7*rear+frame//8)*128))
    return atlas

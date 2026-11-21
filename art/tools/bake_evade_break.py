"""Non-lethal reactions drawn from the hunter and axe chief's registered paintings."""
import numpy as np
from PIL import Image, ImageOps
from bake_falls import rotate, samples, eased_distance
from bake_player_falls import sample_keys, bent_knee, segment, stamp

# Pelvis x/y, upper-body tilt, lead/trailing ankle x/y. The hunter drives
# off one foot and clears the strike before bringing the trailing foot in.
EVADE=[(0,0,0,0,0,0,0,0),(5,-2,3,-5,0,0,0,0),
       (12,7,7,16,0,0,15,-6),(19,19,8,24,9,-5,22,0),
       (24,21,9,18,16,-1,22,0),(31,20,7,15,17,0,22,0),
       (40,11,4,6,3,-4,20,0),(49,2,2,-3,0,0,7,-2),(55,0,0,0,0,0,0,0)]
# His hips drift past the planted foot. The corrective step lands late,
# leaving the weapon arm low for a beat before he can raise the axe.
BREAK=[(0,0,0,0,0,0,0,0),(6,1,3,12,0,0,0,0),(14,5,9,24,0,0,4,-3),
       (23,9,17,34,1,0,16,-5),(29,11,18,31,3,1,18,0),
       (36,10,16,25,4,0,18,0),(45,6,11,12,1,0,14,0),
       (50,3,6,4,0,0,6,-3),(55,0,0,0,0,0,0,0)]

def bake(plates, hunter):
    sheet=Image.new('RGBA',(1280,1792))
    for rear,plate in enumerate(plates):
        source=ImageOps.mirror(plate) if rear else plate
        pts,ink=samples(np.asarray(source))
        x,y=pts.T
        if hunter:
            legs=[(80,83,77,99,75,116),(85,84,87,97,92,106)] if not rear else [(79,85,76,98,72,114),(91,84,94,99,97,113)]
        else:
            legs=[(77,82,76,96,69,106),(88,82,94,99,97,116)] if not rear else [(75,84,71,99,68,113),(94,85,99,97,101,110)]
        hip=np.array([(legs[0][0]+legs[1][0])/2,83.])
        for frame in range(56):
            dx,dy,lean,ax,ay,bx,by=sample_keys(EVADE if hunter else BREAK,frame)
            pelvis=hip+[dx,dy]
            upper=(pts-hip)@rotate(lean).T+pelvis
            body=upper.copy()
            for j,marks in enumerate(legs):
                h,k,a=np.reshape(np.array(marks,float),(3,2))
                H=(h-hip)@rotate(lean).T+pelvis
                A=a+([bx,by] if j else [ax,ay])
                K=bent_knee(H,A,np.linalg.norm(k-h),np.linalg.norm(a-k),1)
                thigh=segment(pts,h,k,H,K)
                shin=segment(pts,k,a,K,A)
                split=eased_distance(x,hip[0],4)
                w=eased_distance(y,h[1]+3,10)*(split if j else 1-split)*min(1,dy/4)
                body+=(thigh+(shin-thigh)*eased_distance(y,k[1],8)[:,None]-upper)*w[:,None]
            # Keep the painted bow/axe rigid, pivoting at the shoulder while
            # the forearm follows. Cloth and the quiver stay on the torso.
            shoulder=np.array([76.,45.])
            weight=(1-eased_distance(x,73 if hunter else 70,10))*(1-eased_distance(y,96 if hunter else 73,6))
            swing=sample_keys([(0,0),(8,5),(22,11),(34,9),(55,0)] if hunter else
                              [(0,0),(6,-4),(23,-27),(36,-22),(47,-11),(55,0)],frame)[0]
            carried=(pts-shoulder)@rotate(lean+swing).T+(shoulder-hip)@rotate(lean).T+pelvis
            body+=(carried-upper)*weight[:,None]
            canvas=np.zeros((128,160,4),np.uint8)
            stamp(canvas,body,ink)
            tile=Image.fromarray(canvas)
            if rear:tile=ImageOps.mirror(tile)
            sheet.paste(tile,(frame%8*160,(7*rear+frame//8)*128))
    return sheet

"""Chiron shelters his bow and braces before his forelegs give way."""
import numpy as np
from PIL import Image, ImageOps
from bake_falls import rotate, eased_distance, samples
from bake_player_falls import sample_keys, stamp, bent_knee, segment

# Frame, bow tuck, front/hind barrel drop, barrel roll, human lean, leg fold.
STAGES = [(0,0,0,0,0,0,0), (5,.12,1,0,0,5,0),
          (15,1,2,0,.04,-3,0), (24,1,3,1,.06,-2,0),
          (31,1,13,2,.18,5,.16), (36,1,22,6,.32,23,.38),
          (43,1,26,20,.65,61,.83), (48,1,29,27,.78,82,1),
          (55,1,28,27,.77,80,1)]

def bake(plates):
    sheet=Image.new('RGBA',(1280,1792))
    for rear,plate in enumerate(plates):
        tile=ImageOps.mirror(plate) if rear else plate
        points,colors=samples(np.array(tile))
        x,y=points.T
        # Anchors on the normalized left-facing original, from chest to rump.
        legs=([(53,83,55,99,51,117),(64,84,63,100,64,117),
               (88,80,90,99,81,117),(97,79,98,99,100,117)] if not rear else
              [(61,82,62,99,60,115),(69,83,72,99,71,114),
               (80,79,82,99,82,117),(94,78,95,99,97,115)])
        waist=np.array([61.,73.] if not rear else [68.,68.])
        # The bow extends below the hand, clear of the front hoof. Its
        # lower tip follows the hand even when the forelegs fold underneath.
        line_y=[25,42,55,69,80,93,104]
        line_x=[36,40,37,40,43,50,51] if not rear else [49,51,48,50,52,57,56]
        bow=1-eased_distance(x,np.interp(y,line_y,line_x)+3,2)
        bow*=1-eased_distance(y,104 if not rear else 97,2)
        # Below the fist the dark wooden limb crosses the pale foreleg.
        # Keep wood rigid and let the coat and hoof fold independently.
        low_wood=(np.abs(x-np.interp(y,line_y,line_x))<3.2)&(colors[:,0]<135)
        bow=np.where(y>(76 if not rear else 71),low_wood*(y<(104 if not rear else 97)),bow)
        centers=[np.interp(y,[h[1],h[3],h[5]],[h[0],h[2],h[4]]) for h in legs]
        for frame in range(56):
            tuck,fore,hind,roll,lean,fold=sample_keys(STAGES,frame)
            def barrel(p):
                px,py=p.T
                drop=fore+(hind-fore)*eased_distance(px,79,40)
                return np.stack([px+roll*(py-77)*.64,py+drop-roll*(py-77)*.74],axis=-1)
            horse=barrel(points)
            new=horse.copy()
            for j,coords in enumerate(legs):
                hip,knee,hoof=np.array(coords,dtype=float).reshape(3,2)
                H=barrel(hip)
                A=hoof+np.array([(17 if j<2 else -13)*fold,-4*fold])
                K=bent_knee(H,A,np.linalg.norm(knee-hip),np.linalg.norm(hoof-knee),1 if j<2 else -1)
                thigh=segment(points,hip,knee,H,K)
                shin=segment(points,knee,hoof,K,A)
                leg=thigh+(shin-thigh)*eased_distance(y,knee[1],6)[:,None]
                w=np.ones_like(y)
                if j:w*=eased_distance(x,(centers[j-1]+centers[j])/2,3)
                if j<3:w*=1-eased_distance(x,(centers[j+1]+centers[j])/2,3)
                else:w*=1-eased_distance(x,103 if not rear else 102,3)
                new+=(leg-horse)*(w*eased_distance(y,87,12)*min(1,fore/5))[:,None]
            # Bring the wooden limbs in as one shape. Blend the wrist motion
            # through the painted sleeve towards the shoulder.
            arm=(1-eased_distance(x,52 if not rear else 58,18))*eased_distance(y,48,12)
            arm=np.maximum(arm,bow)
            local=points-waist
            local+=(np.array([6,-7])*tuck)*arm[:,None]
            upper=local@rotate(lean).T+barrel(waist)
            torso=(1-eased_distance(y,73 if not rear else 69,13))*(1-eased_distance(x,79,10))
            w=np.maximum(torso,bow)
            new+=(upper-new)*w[:,None]
            new[:,1]-=max(0,new[:,1].max()-119)
            canvas=np.zeros((128,160,4),np.uint8)
            stamp(canvas,new,colors)
            if fold>.1:
                foreground=(torso>.65)|(bow>.8)
                stamp(canvas,new[foreground],colors[foreground])
            pic=Image.fromarray(canvas)
            if rear:pic=ImageOps.mirror(pic)
            sheet.paste(pic,(frame%8*160,(7*rear+frame//8)*128))
    return sheet

"""Pose painted limbs around fixed feet and keep the shield rim or bow rigid."""
import cv2
import numpy as np
from PIL import Image, ImageOps
from bake_falls import rotate, samples, eased_distance

# Frame, pelvis displacement, chest rotation, and displacement of each ankle.
HERO=[(0,0,0,0,0,0,0,0),(6,-2,0,-6,-1,0,0,0),
      (17,-1,19,14,-3,6,2,0),(27,0,21,19,-4,6,3,0),
      (37,0,21,-16,1,6,7,0),(48,0,20,-71,23,4,27,-4),
      (55,0,21,-82,28,3,31,-5)]
HUNTER=[(0,0,0,0,0,0,0,0),(6,2,0,7,0,0,0,0),
        (15,-1,7,-6,0,0,-3,4),(25,-3,16,19,-4,-1,-7,6),
        (38,-3,21,63,-20,-4,-24,4),(47,-3,23,79,-26,-6,-29,2),
        (55,-3,23,77,-26,-6,-29,2)]
# Rim center shift and roll. Between 17 and 27 the lower rim stays planted.
SHIELD=[(0,0,0,0),(6,-1,1,-6),(17,5,0,6),(27,5,0,6),
        (37,1,0,-17),(48,-17,0,-62),(55,-22,0,-75)]
BOW=[(0,0,0,0),(6,1,-1,0),(15,8,-9,-12),(25,9,-10,-10),
     (38,8,-9,2),(47,6,-8,5),(55,6,-8,4)]

def sample_keys(keys,f):
    for a,b in zip(keys,keys[1:]):
        if f<=b[0]:
            t=(f-a[0])/(b[0]-a[0])
            t=t*t*(3-2*t)
            return (1-t)*np.array(a[1:])+t*np.array(b[1:])
    return np.array(keys[-1][1:])

def segment(points,a,b,c,d):
    ab=b-a
    cd=d-c
    angle=np.arctan2(cd[1],cd[0])-np.arctan2(ab[1],ab[0])
    return (points-a)@rotate(np.rad2deg(angle)).T + c

def bent_knee(hip,ankle,upper,lower,side):
    axis=ankle-hip
    length=max(.01,np.linalg.norm(axis))
    axis=axis/length
    along=np.clip((upper**2-lower**2+length**2)/(2*length),-upper,upper)
    return hip+along*axis+side*np.array([-axis[1],axis[0]])*np.sqrt(max(0,upper**2-along**2))

def stamp(canvas,coords,color):
    pos=np.rint(coords).astype(int)
    x,y=pos.T
    use=(x>=0)&(x<160)&(y>=0)&(y<128)
    canvas[y[use],x[use]]=color[use]

def bow_mask(cell,rear):
    # Follow both recurved limbs up to the fingers on the registered painting.
    line=[(60,39),(65,45),(61,56),(62,64),(71,74),(72,93),(75,99)]
    if rear:line=[(60,43),(65,47),(59,59),(60,69),(67,77),(69,92),(73,97)]
    mask=np.zeros((128,160),np.uint8)
    cv2.polylines(mask,[np.int32(line)],False,255,3)
    return (mask!=0)&(np.array(cell)[:,:,3]>0)

def bake(plates,shields):
    hero=shields is not None
    atlas=Image.new('RGBA',(1280,1792))
    for rear,plate in enumerate(plates):
        cell=ImageOps.mirror(plate) if rear else plate
        paint=np.array(cell)
        if hero:
            prop=np.array(ImageOps.mirror(shields[rear]) if rear else shields[rear])
            yy,xx=np.nonzero(prop[:,:,3])
            grip=np.array([(xx.min()+xx.max())/2,(yy.min()+yy.max())/2])
        else:
            mask=bow_mask(cell,rear)
            prop=paint.copy()
            prop[~mask]=0
            paint[mask]=0
            grip=np.array([68.,76.]) if rear else np.array([71.,74.])
        points,color=samples(paint)
        prop_points,prop_color=samples(prop)
        x,y=points.T
        hip=np.array([81.,82.] if hero else [82.,84.])
        if rear:hip=np.array([84.,84.])
        if hero:
            feet=[(77,85,79,98,73,106),(85,84,90,99,90,116)] if not rear else [(78,84,80,100,75,116),(88,84,93,98,95,109)]
        else:
            feet=[(80,83,77,99,75,116),(85,84,87,97,92,106)] if not rear else [(79,85,76,98,72,114),(91,84,94,99,97,113)]
        for frame in range(56):
            dx,dy,lean,ax,ay,bx,by=sample_keys(HERO if hero else HUNTER,frame)
            pelvis=hip+[dx,dy]
            upper=(points-hip)@rotate(lean).T+pelvis
            body=upper.copy()
            split=eased_distance(x,82 if not rear else 85,3)
            for j,foot in enumerate(feet):
                h,k,a=np.array(foot,dtype=float).reshape(3,2)
                newh=pelvis+rotate(lean)@(h-hip)
                newa=a+([bx,by] if j else [ax,ay])
                # Bend towards the fall, keeping both soles registered until the hip tips.
                sign=-1 if hero else 1
                newk=bent_knee(newh,newa,np.linalg.norm(k-h),np.linalg.norm(a-k),sign)
                thigh=segment(points,h,k,newh,newk)
                shin=segment(points,k,a,newk,newa)
                leg=thigh+(shin-thigh)*eased_distance(y,k[1],9)[:,None]
                weight=eased_distance(y,h[1],9)*(split if j else 1-split)
                body+=(leg-upper)*weight[:,None]
            px,py,roll=sample_keys(SHIELD if hero else BOW,frame)
            if hero:
                prop_local=(prop_points-grip)@rotate(roll).T
                touch_y=117.-prop_local[:,1].max()
                approach=sample_keys([(0,0),(6,.05),(17,1),(55,1)],frame)[0]
                hand=np.array([grip[0]+px,(grip[1]+py)*(1-approach)+touch_y*approach])
            else:
                hand=(grip-hip+[px,py])@rotate(lean).T+pelvis
                prop_local=(prop_points-grip)@rotate(lean+roll).T
            # Carry the forearm into the equipment grip, fading to the painted shoulder.
            arm_center=grip if not hero else grip+[0,-2]
            w=np.exp(-((x-arm_center[0])/9)**2-((y-arm_center[1])/13)**2)
            body+=(hand-((grip-hip)@rotate(lean).T+pelvis))*w[:,None]
            shield_or_bow=prop_local+hand
            # At contact, let the side and quiver rest on the ground plane.
            excess=max(0,body[:,1].max()-119)
            body[:,1]-=excess
            if not hero:shield_or_bow[:,1]-=excess
            canvas=np.zeros((128,160,4),np.uint8)
            if rear and hero:stamp(canvas,shield_or_bow,prop_color)
            stamp(canvas,body,color)
            if not (rear and hero):stamp(canvas,shield_or_bow,prop_color)
            tile=Image.fromarray(canvas)
            if rear:tile=ImageOps.mirror(tile)
            atlas.paste(tile,(frame%8*160,(7*rear+frame//8)*128))
    return atlas

def bake_heracles(plates):
    """Keep the thick end of the painted club planted through the brace."""
    # Pelvis moves only slightly until the knees buckle. The shoulder hits
    # quickly, followed by a small settling movement from the lower body.
    body_keys=[(0,0,0,0),(6,2,0,8),(15,-1,8,-9),(25,-2,10,-13),
               (31,-1,12,-8),(36,0,21,17),(42,2,25,62),
               (45,3,28,87),(49,3,26,80),(55,3,28,85)]
    club_keys=[(0,0,0,0),(6,2,-1,6),(15,5,0,-18),(29,5,0,-18),
               (36,6,0,-8),(42,10,0,21),(46,14,0,51),(55,15,0,55)]
    atlas=Image.new("RGBA",(1280,1792))
    for rear,plate in enumerate(plates):
        paint=np.array(ImageOps.mirror(plate) if rear else plate)
        # The haft meets the underside of the fist. Trace that seam to keep
        # every wood and leather colour from the two original painted views.
        outline=[(52,111),(52,99),(68,84),(72,79),(74,81),(72,88),(67,102),(65,111)]
        if rear:outline=[(53,111),(53,98),(64,91),(68,84),(71,86),(69,93),(65,109)]
        mask=np.zeros((128,160),np.uint8)
        cv2.fillPoly(mask,[np.int32(outline)],255)
        prop=paint.copy()
        prop[mask==0]=0
        paint[mask!=0]=0
        wood,wood_color=samples(prop)
        points,color=samples(paint)
        x,y=points.T
        grip=np.array([70,86] if rear else [73,81])
        hip=np.array([85,86])
        tip=wood[wood[:,1]>=wood[:,1].max()-.5].mean(axis=0)
        legs=[(81,86,79,99,73,109),(90,86,93,100,94,117)]
        if rear:legs=[(82,86,79,102,76,116),(90,86,94,98,96,108)]
        for frame in range(56):
            dx,dy,lean=sample_keys(body_keys,frame)
            pelvis=hip+[dx,dy]
            upper=(points-hip)@rotate(lean).T+pelvis
            body=upper.copy()
            slip=sample_keys([(0,0),(29,0),(36,.12),(45,.9),(55,1)],frame)[0]
            for j,leg in enumerate(legs):
                h,k,a=np.array(leg,float).reshape(3,2)
                H=(h-hip)@rotate(lean).T+pelvis
                A=a+slip*np.array([-26 if j else -30,-2 if j else 3])
                K=bent_knee(H,A,np.linalg.norm(k-h),np.linalg.norm(a-k),-1)
                thigh=segment(points,h,k,H,K)
                shin=segment(points,k,a,K,A)
                w=eased_distance(x,85,4)
                body+=(thigh+(shin-thigh)*eased_distance(y,k[1],8)[:,None]-upper)*(eased_distance(y,88,10)*(w if j else 1-w))[:,None]
            sx,sy,roll=sample_keys(club_keys,frame)
            plant=sample_keys([(0,0),(6,.04),(15,1),(55,1)],frame)[0]
            local=(wood-tip)@rotate(roll).T
            end=np.array([tip[0]+sx,(tip[1]+sy)*(1-plant)+(118-local[:,1].max())*plant])
            hand=(grip-tip)@rotate(roll).T+end
            # Hand and forearm settle against the haft during the collapse.
            follow=np.exp(-((x-grip[0])/6.8)**2-((y-grip[1])/11)**2)
            body[:,1]-=max(0,body[:,1].max()-119)
            painted_hand=(grip-hip)@rotate(lean).T+pelvis
            body+=(hand-painted_hand)*follow[:,None]
            canvas=np.zeros((128,160,4),np.uint8)
            stamp(canvas,local+end,wood_color)
            stamp(canvas,body,color)
            tile=Image.fromarray(canvas)
            if rear:tile=ImageOps.mirror(tile)
            atlas.paste(tile,(frame%8*160,(7*rear+frame//8)*128))
    return atlas

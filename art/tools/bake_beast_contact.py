"""Register the painted running, crouching and landing keys through contact."""
import cv2
import numpy as np
from PIL import Image
from bake_motion import guide_maps
from bake_falls import samples, eased_distance

# Near and far view landmarks in the left-facing 160px cell, ordered muzzle,
# shoulder, rump, front paws, hind paw and tail. The extra control at each joint
# keeps texture registration local as the body passes in front of the legs.
LION=[
 [[(56,81),(73,62),(94,55),(49,105),(73,114),(105,92),(112,72),(75,87),(97,71)],
  [(47,106),(68,86),(91,74),(46,115),(67,112),(90,109),(109,58),(79,99),(95,88)],
  [(65,99),(78,84),(100,82),(39,113),(81,114),(123,104),(112,58),(86,97),(110,91)]],
 [[(56,51),(67,65),(86,79),(55,99),(78,112),(103,110),(113,113),(63,83),(87,94)],
  [(48,71),(61,74),(92,79),(41,99),(75,114),(105,111),(112,52),(63,90),(88,99)],
  [(43,77),(63,80),(86,89),(27,99),(73,114),(128,111),(116,68),(57,93),(98,104)]]]
BOAR=[
 [[(35,101),(57,59),(100,39),(54,111),(85,116),(117,96),(124,60),(81,91),(113,74)],
  [(32,98),(58,59),(102,46),(48,116),(89,101),(110,94),(128,43),(73,96),(110,73)],
  [(27,94),(57,59),(101,47),(30,116),(55,115),(135,71),(128,35),(74,89),(116,63)]],
 [[(45,41),(61,43),(99,65),(60,101),(80,98),(114,109),(124,87),(61,79),(98,88)],
  [(40,39),(63,46),(95,64),(63,90),(94,102),(111,116),(127,83),(65,74),(100,91)],
  [(35,27),(61,40),(88,61),(39,64),(92,98),(113,115),(122,71),(58,61),(98,82)]]]

def lion_break_stages(idle, brace):
    # First forepaw slides while the second still carries weight. The rear
    # claws plant before the shoulder bottoms out. Keep the chin off the dirt.
    check=idle.copy()
    check[:3]+=[2,-2]
    slip=.73*idle+.27*brace
    slip[3]=brace[3]+[-6,0]
    slip[4]=idle[4]
    low=brace.copy()
    low[0]+=[2,-3]
    low[1]+=[-2,4]
    low[3]+=[-6,0]
    low[5]+=[4,1]
    alert=low.copy()
    alert[0]+=[2,-6]
    alert[1]+=[1,-2]
    inhale=alert.copy()
    inhale[:3,1]-=[2,1.5,1]
    inhale[6]+=[2,-2]
    flinch=alert.copy()
    flinch[:2]+=[4,2]
    return [(0,0,idle),(5,0,check),(12,0,slip),(20,1,low),(25,1,low),
            (32,1,alert),(42,1,inhale),(43,1,alert),(47,1,flinch),(55,1,alert)]


def bake(source,kind,wrestle=False,broken=False):
    atlas=Image.new('RGBA',(1280,1792))
    for rear in (0,1):
        keys=[0,3,4] if kind=='lion' else [0,1,2]
        marks=np.array((LION if kind=='lion' else BOAR)[rear],np.float32)
        art=[]
        for k in keys:
            c=source.crop((k*160,rear*128,(k+1)*160,(rear+1)*128))
            if rear:c=c.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            art.append(cv2.cvtColor(np.array(c),cv2.COLOR_RGBA2mRGBA))
        points,colors=samples(cv2.cvtColor(art[2],cv2.COLOR_mRGBA2RGBA))
        x,y=points.T
        idle,brace,landing=marks
        recoil=idle.copy()
        recoil[:3]+=[3,-2]
        strained=brace.copy()
        strained[0]+=[-5,-5]
        strained[3:5,0]-=3
        if broken:
            stages=lion_break_stages(idle,brace)
        elif wrestle:
            stages=[(0,0,idle),(13,1,.37*idle+.63*brace),(24,1,strained),
                    (32,1,brace),(40,2,landing),(46,1,brace),(55,0,idle)]
        else:
            stages=[(0,0,idle),(6,0,recoil),(19,1,brace),(34,2,landing),
                    (55,2,landing)]
            if kind=="lion":
                stages.insert(2,(14,1,.37*idle+.63*brace))
        for (start,a,first),(end,b,last) in zip(stages,stages[1:]):
            for f in range(start,end+1):
                t=(f-start)/(end-start)
                t=t*t*(3-2*t)
                dest=(1-t)*first+t*last
                if not wrestle and not broken and start==34:
                    # Roll the entire flank as one painted surface. Corner-pinned
                    # interpolation here would stretch the back while the legs fold.
                    u=min(1.,(f-start)/16.)
                    u=u*u*(3.-2.*u)
                    angle=(33 if rear else -31) if kind=='boar' else (9 if rear else -8)
                    pivot=tuple(map(float,landing[1]))
                    xf=cv2.getRotationMatrix2D(pivot,angle*u,1.)
                    at=points@xf[:,:2].T+xf[:,2]
                    if kind=='boar':
                        hooves=eased_distance(y,102 if not rear else 99,18)
                        muzzle=(1-eased_distance(x,47,18))*(1-eased_distance(y,98 if not rear else 45,12))
                        at[:,1]+=u*(8*muzzle-16*hooves)
                        at[:,0]+=u*(7*hooves-4)
                    else:
                        chin=(1-eased_distance(x,73,22))*(1-eased_distance(y,103,16))
                        tail=eased_distance(x,101,10)*(1-eased_distance(y,79,15))
                        paws=eased_distance(y,106,14)
                        at[:,1]+=u*(11*chin+20*tail-8*paws)
                        at[:,0]+=u*(6*paws-3)
                    at[:,1]+=y.max()-at[:,1].max()
                    px,py=np.rint(at).astype(int).T
                    valid=(px>=0)&(px<160)&(py>=0)&(py<128)
                    pixels=np.zeros((128,160,4),np.uint8)
                    pixels[py[valid],px[valid]]=colors[valid]
                    tile=Image.fromarray(pixels)
                    if rear:tile=tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                    atlas.paste(tile,(f%8*160,(7*rear+f//8)*128))
                    continue
                maps=guide_maps(marks[a].tolist(),marks[b].tolist(),t,dest,size=(160,128))
                left=cv2.remap(art[a],maps[0],None,cv2.INTER_LINEAR)
                right=cv2.remap(art[b],maps[1],None,cv2.INTER_LINEAR)
                img=cv2.cvtColor(cv2.addWeighted(left,1-t,right,t,0),cv2.COLOR_mRGBA2RGBA)
                img[:,:,3]=np.where(img[:,:,3]>=128,255,0)
                tile=Image.fromarray(img)
                if rear:tile=tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                atlas.paste(tile,(f%8*160,(7*rear+f//8)*128))
    return atlas

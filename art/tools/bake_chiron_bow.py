"""Paint the wounded archer's shot between his registered front and rear originals."""
import cv2
import numpy as np
from PIL import Image
from bake_motion import guide_maps

# Bow tips, bow hand, shooting hand, head, shooting elbow, withers, rump and four hooves.
MARKS = [
    [[(36,36),(51,91),(43,72),(61,80),(58,27),(72,52),(58,83),(94,79),(51,117),(65,117),(80,117),(100,117)],
     [(48,16),(43,75),(31,41),(60,41),(63,30),(86,42),(58,80),(95,76),(40,117),(58,117),(82,117),(108,117)],
     [(43,16),(41,78),(28,46),(81,43),(68,31),(93,48),(59,80),(96,77),(41,117),(58,117),(82,117),(110,117)]],
    [[(110,30),(100,95),(109,65),(100,56),(94,26),(79,52),(91,84),(68,79),(100,117),(90,117),(63,117),(79,117)],
     [(111,11),(116,68),(124,35),(97,35),(95,27),(74,42),(91,80),(70,78),(116,117),(99,117),(54,117),(70,117)],
     [(118,16),(118,72),(126,40),(78,40),(96,29),(68,44),(92,81),(71,78),(118,117),(100,117),(54,117),(70,117)]]]

# Control the recurved limbs independently of the elbow crossing behind them.
LIMBS = [
    [[(40,45),(37,60),(42,81)],[(38,24),(31,33),(31,60)],[(37,25),(28,36),(29,62)]],
    [[(109,39),(112,51),(107,81)],[(118,20),(124,28),(123,55)],[(123,24),(127,32),(126,55)]]]

def bake(source, pixelize):
    atlas=Image.new('RGBA',(8*160,14*128))
    for side in range(2):
        keys=[np.array(source.crop((i*320,side*256,(i+1)*320,(side+1)*256))) for i in (0,2,3)]
        clean=keys[1].copy()
        # Clear exposed shaft pixels at release. Keep the nearby arm and bow silhouette.
        for x0,x1,y0,y1 in ([(24,29,39,43),(35,56,39,42)] if not side else
                             [(126,132,32,36),(105,120,33,36)]):
            clean[y0*2:y1*2,x0*2:x1*2]=0
        keys.append(clean)
        paint=[cv2.cvtColor(k,cv2.COLOR_RGBA2mRGBA) for k in keys]
        marks=[body+limb for body,limb in zip(MARKS[side],LIMBS[side])]
        guides=np.array(marks+[marks[1]],dtype=float)
        idle,draw,loose=guides[:3]
        settle=idle.copy()
        settle[:8,1]+=[2,1,2,3,3,3,3,1]
        settle[:8,0]+=1 if side else -1
        settle[12:]+=settle[2]-idle[2]
        brace=settle.copy()
        brace[8:10,0]+=(draw[8:10,0]-idle[8:10,0])*.72
        brace[8:10,1]=idle[8:10,1]
        lower=idle.copy()
        lower[:8,1]+=2
        lower[8:10]=brace[8:10]
        lower[12:,1]+=2
        stages=[(0,0,idle),(6,0,settle),(12,0,brace),(26,1,draw),(30,1,draw),
                (31,3,draw),(35,2,loose),(39,2,loose),(51,0,lower),(55,0,idle)]
        for (a,ka,start),(b,kb,end) in zip(stages,stages[1:]):
            for frame in range(a,b+1):
                t=(frame-a)/(b-a)
                t=t*t*(3-2*t)
                mid=2*((1-t)*start+t*end)
                maps=guide_maps((guides[ka]*2).tolist(),(guides[kb]*2).tolist(),t,mid)
                left=cv2.remap(paint[ka],maps[0],None,cv2.INTER_LINEAR)
                right=cv2.remap(paint[kb],maps[1],None,cv2.INTER_LINEAR)
                tile=cv2.cvtColor(cv2.addWeighted(left,1-t,right,t,0),cv2.COLOR_mRGBA2RGBA)
                atlas.paste(pixelize(Image.fromarray(tile)),((frame%8)*160,(7*side+frame//8)*128))
    return atlas

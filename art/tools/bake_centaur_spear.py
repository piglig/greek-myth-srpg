"""Register the original painted spear and hooves through a single attack."""
import cv2
import numpy as np
from PIL import Image
from bake_motion import guide_maps

# Tip, grip, shoulder, head, free hand, chest, croup, tail, two fore and two hind hooves.
GUIDES = [
    [[(71,48),(89,66),(113,47),(104,29),(124,73),(104,83),(138,79),(161,99),(95,117),(112,117),(127,117),(147,117)],
     [(60,51),(87,64),(111,47),(99,35),(138,60),(103,81),(141,78),(176,81),(83,102),(110,102),(155,115),(176,108)],
     [(38,57),(65,57),(91,55),(88,41),(142,57),(100,84),(139,81),(164,98),(70,117),(112,108),(123,116),(163,117)]],
    [[(175,41),(158,66),(145,47),(141,28),(120,70),(144,82),(124,80),(102,95),(149,116),(138,116),(127,117),(114,116)],
     [(187,41),(165,58),(153,46),(153,32),(113,57),(149,79),(117,78),(90,90),(162,93),(142,96),(100,116),(88,116)],
     [(211,43),(187,49),(163,51),(159,37),(111,57),(149,81),(119,82),(93,89),(181,107),(133,108),(108,117),(92,116)]]]

def bake(originals, pixelize):
    sheet=Image.new('RGBA',(8*256,14*128))
    for side,suffix in enumerate(['','-rear']):
        rgba=np.array(Image.open(originals/f'pholoe-centaurs{suffix}.png').convert('RGBA'))
        _,labels,boxes,_=cv2.connectedComponentsWithStats(np.uint8(rgba[:,:,3]>10))
        bodies=sorted(range(1,len(boxes)),key=lambda i:-boxes[i,4])[:6]
        keys=[]
        for i in sorted((i for i in bodies if boxes[i,1]<400),key=lambda i:boxes[i,0]):
            x,y,w,h,_=boxes[i]
            crop=rgba[y:y+h,x:x+w].copy()
            crop[:,:,3]*=(labels[y:y+h,x:x+w]==i)
            center=int(np.where(crop[int(.5*h):int(.78*h),:,3]>100)[1].mean())
            paint=Image.fromarray(crop).resize((round(w*.445),round(h*.445)),Image.Resampling.LANCZOS)
            canvas=Image.new('RGBA',(512,256))
            canvas.paste(paint,(256-round(center*.445),239-paint.height))
            keys.append(cv2.cvtColor(np.array(canvas),cv2.COLOR_RGBA2mRGBA))

        idle,drive,point=np.array(GUIDES[side],dtype=float)
        forward=1 if side else -1
        loaded=idle.copy()
        loaded[:8]+=[-3*forward,3]
        loaded[8:10,1]-=2
        drive=drive.copy()
        drive[10:]=idle[10:]  # keep the planted hind hooves through the shoulder drive
        # Let the reaching forehoof clear the ground until after the spear lands.
        point=point.copy()
        point[8,1]-=5
        landed=point.copy()
        landed[8,1]=idle[8,1]
        landed[:8]+=[forward,3]
        over=idle.copy()
        over[:5]+=[-5*forward,-1]
        over[5:8,0]-=forward
        correct=idle.copy()
        correct[:5]+=[2*forward,1]
        stages=[(0,0,idle),(10,0,loaded),(16,1,drive),(21,2,point),
                (26,2,landed),(38,0,over),(47,0,correct),(55,0,idle)]
        for (start,a,first),(end,b,last) in zip(stages,stages[1:]):
            left=(2*np.array(GUIDES[side][a])).tolist()
            right=(2*np.array(GUIDES[side][b])).tolist()
            for frame in range(start,end+1):
                t=(frame-start)/(end-start)
                t=t*t*(3-2*t)
                mid=2*((1-t)*first+t*last)
                ma,mb=guide_maps(left,right,t,mid,size=(512,256))
                pa=cv2.remap(keys[a],ma,None,cv2.INTER_LINEAR)
                pb=cv2.remap(keys[b],mb,None,cv2.INTER_LINEAR)
                mix=cv2.cvtColor(cv2.addWeighted(pa,1-t,pb,t,0),cv2.COLOR_mRGBA2RGBA)
                sheet.paste(pixelize(Image.fromarray(mix)),(frame%8*256,(side*7+frame//8)*128))
    return sheet

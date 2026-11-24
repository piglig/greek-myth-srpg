"""Register named heroes' gouache keys and bake their timed attack strips."""
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps
from bake_motion import guide_maps

ROOT = Path(__file__).resolve().parents[2]
ORIGINALS = ROOT / "art/originals"


def registered(pic, scale):
    pic = ImageOps.mirror(pic.convert("RGBA"))
    pic = pic.crop(pic.getchannel("A").getbbox())
    pic = pic.resize((round(pic.width*scale), round(pic.height*scale)), Image.Resampling.LANCZOS)
    cell = Image.new("RGBA", (320,256))
    torso = np.asarray(pic)[int(pic.height*.47):int(pic.height*.72),:,3]
    center = np.median(np.where(torso>96)[1])
    x = min(318-pic.width, max(2, round(160-center)))
    cell.alpha_composite(pic,(x,234-pic.height))
    return cell


def plates(name):
    sheet = Image.open(ORIGINALS / (name+".png"))
    scale = {"idas":.437, "eurytion":.64, "merc_captain":.45, "merc_lancer":.55, "merc_sword":.44, "merc_archer":.44}[name]
    atlas = Image.new("RGBA",(1280,512))
    for side in range(2):
        for col in range(4):
            idx = col if col<3 else 0
            pic = sheet.crop((idx*512,side*512,(idx+1)*512,(side+1)*512))
            key = registered(pic,scale)
            atlas.paste(key,(320*col,256*side))
    return atlas


# Coordinates on the native 160x128 plates. Match the blade/tip and grip
# before blending pigment so a fast swing cannot leave a second weapon.
# Human: crest, face, axe blade, both grips, shoulder, belt, cape and feet.
# Centaur: spear tip, grip, head, shoulder, free wrist, breast, rump, tail,
# four separate hooves. Row order is idle, loaded and contact.
GUIDES = {
    "merc_captain": [
        [[(67,16),(66,30),(46,51),(57,54),(77,66),(83,40),(76,72),(100,83),(56,105),(89,113)],
         [(73,31),(70,44),(135,78),(115,76),(97,74),(95,51),(84,79),(119,80),(63,107),(131,110)],
         [(77,23),(72,36),(39,72),(55,72),(72,70),(87,46),(82,74),(123,75),(54,107),(128,113)]],
        [[(94,15),(96,27),(117,47),(106,48),(97,54),(97,43),(84,72),(57,77),(72,110),(104,112)],
         [(92,29),(95,40),(27,81),(44,80),(58,77),(91,53),(83,78),(38,69),(29,110),(114,110)],
         [(98,22),(99,32),(123,67),(111,66),(104,62),(102,43),(84,74),(38,77),(38,112),(120,106)]]],
    "merc_lancer": [
        [[(10,53),(37,53),(59,18),(72,32),(68,48),(62,65),(96,67),(117,91),(51,113),(64,112),(85,110),(99,113)],
         [(10,52),(37,52),(58,20),(73,32),(68,49),(61,66),(95,68),(121,93),(43,98),(52,113),(76,110),(108,109)],
         [(2,46),(27,47),(51,24),(67,35),(57,46),(59,66),(94,68),(121,90),(29,111),(69,113),(88,109),(112,112)]],
        [[(147,48),(125,48),(102,13),(107,28),(114,44),(99,63),(61,67),(43,88),(97,109),(111,111),(57,109),(76,112)],
         [(149,47),(127,48),(104,15),(109,29),(117,44),(100,64),(63,68),(39,90),(117,97),(107,108),(49,107),(85,113)],
         [(157,42),(133,42),(107,19),(110,30),(119,42),(100,66),(60,67),(30,91),(129,109),(90,109),(46,113),(65,113)]]],
    "idas": [
        [[(75,18),(70,35),(44,63),(59,62),(85,74),(86,45),(77,78),(105,92),(59,107),(91,114)],
         [(70,28),(67,42),(92,14),(80,20),(62,29),(84,38),(69,70),(106,79),(49,109),(101,113)],
         [(75,28),(66,45),(35,91),(49,77),(62,69),(77,48),(78,76),(117,77),(56,108),(116,114)]],
        [[(87,16),(90,32),(123,57),(112,59),(100,67),(99,42),(84,78),(54,84),(68,110),(101,114)],
         [(88,29),(91,42),(67,15),(81,21),(97,30),(99,44),(90,73),(51,80),(62,111),(114,110)],
         [(94,20),(93,38),(129,79),(118,68),(107,58),(99,45),(84,74),(35,80),(45,114),(110,105)]]],
    "eurytion": [
        [[(23,34),(49,56),(62,28),(71,42),(80,65),(62,68),(95,69),(114,91),(50,113),(64,113),(79,113),(95,113)],
         [(10,39),(44,55),(54,36),(65,45),(97,55),(58,73),(97,74),(123,84),(33,90),(58,95),(99,114),(122,110)],
         [(4,50),(38,53),(77,37),(78,49),(129,54),(82,75),(116,76),(146,91),(46,113),(90,103),(108,113),(137,113)]],
        [[(131,25),(112,54),(99,22),(104,39),(80,54),(92,64),(63,68),(48,91),(110,111),(97,111),(80,113),(65,113)],
         [(150,34),(121,47),(105,24),(111,38),(66,47),(94,65),(63,70),(36,82),(118,84),(94,98),(82,113),(49,111)],
         [(155,40),(120,42),(80,26),(86,41),(31,41),(76,66),(43,71),(11,84),(123,109),(74,99),(53,114),(23,111)]]]
}


def attack_strip(name, original, pixelize):
    sheet=Image.new("RGBA",(1280,1792))
    wind=Image.open(ORIGINALS/(name+"-windup.png")) if name in ("idas","merc_captain") else None
    # A slow load, a short acceleration, a visible contact, then recovery.
    stops=[0,16,21,26,55]
    for side in range(2):
        row=original.crop((0,side*256,960,(side+1)*256))
        idle,step,hit=[row.crop((n*320,0,(n+1)*320,256)) for n in range(3)]
        load=registered(wind.crop((wind.width//2*side,0,wind.width//2*(side+1),wind.height)),.228 if name=="idas" else .28) if wind else step
        keys=[cv2.cvtColor(np.array(im),cv2.COLOR_RGBA2mRGBA) for im in (idle,load,hit)]
        stages=[0,1,2,2,0]
        guides=np.asarray(GUIDES[name][side],dtype=float)*2
        for start,end,a,b in zip(stops,stops[1:],stages,stages[1:]):
            for frame in range(start,end+1):
                t=(frame-start)/(end-start)
                t=t*t*(3-2*t)
                if a==b or frame in (start,end):
                    paint=keys[b if frame==end else a]
                else:
                    ma,mb=guide_maps(guides[a].tolist(),guides[b].tolist(),t)
                    first=cv2.remap(keys[a],ma,None,cv2.INTER_LINEAR)
                    last=cv2.remap(keys[b],mb,None,cv2.INTER_LINEAR)
                    w=np.clip((t-.27)/.46,0.,1.)
                    paint=cv2.addWeighted(first,1-w,last,w,0)
                key=Image.fromarray(cv2.cvtColor(paint,cv2.COLOR_mRGBA2RGBA))
                sheet.paste(pixelize(key),(frame%8*160,(side*7+frame//8)*128))
    return sheet


if __name__=="__main__":
    for name,base in [('idas','bandit_chief'),('eurytion','centaur'),('merc_captain','bandit_chief'),('merc_lancer','centaur'),('merc_sword','bandit'),('merc_archer','bandit_archer')]:
        if sys.argv[2:] and name not in sys.argv[2:]: continue
        path=ROOT/'prototype/art/original/actors'/(name+'.png')
        plates(name).save(path)
        subprocess.run([sys.executable,str(Path(__file__).with_name('bake_look.py')),sys.argv[1],name,base,str(path)],check=True)

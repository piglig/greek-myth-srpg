"""Bake the playable cast from registered 2D art. Pass an agent-sprite-forge checkout."""
from pathlib import Path
import json
import math
import sys
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageOps

sys.path.insert(0,str(Path(sys.argv[1])/"shared"))
import forge_hibit as forge

root=Path(__file__).resolve().parents[2]
src=root/"prototype/art/original"
dst=root/"prototype/art/pixel"
approved=Image.open(root/"art/originals/hero-pixel-study/hero-brace.png")
hero_palette="211e24 32282b 4a3533 68483a 79604d 987960 b39a7e d0b497 eed7b5 63372e 894732 a35b3d c17c4e cb9b67 e8bc7b f9db9c"
yy,xx=np.mgrid[:128,:160].astype(np.float32)

# Midtone paint samples from each approved sheet, with small RGB offsets.
# A soft falloff includes adjacent shades without lifting the ink outlines.
paint_accents = {
    "hero":         [((203,155,103), (5,3,0)), ((163,91,61), (4,1,0))],
    "heracles":     [((169,112,69), (5,3,0)), ((99,62,42), (-2,-1,0))],
    "refugee":      [((79,102,95), (0,4,3)), ((175,150,119), (4,3,1))],
    "bandit":       [((129,100,57), (2,4,0))],
    "bandit_archer":[((114,96,85), (1,3,5))],
    "bandit_chief": [((80,65,79), (4,1,5)), ((125,59,42), (4,1,0))],
    "chiron":       [((58,90,95), (0,4,5)), ((209,186,159), (4,3,2))],
    "centaur":      [((128,47,41), (5,1,0)), ((94,75,71), (3,2,2))],
    "lion":         [((190,130,67), (5,3,-1)), ((96,69,50), (-2,-1,0))],
}

def pigment_offsets(kind):
    samples = paint_accents.get(kind)
    if not samples:
        return None
    grid = np.indices((32,32,32), dtype=np.float32).transpose(1,2,3,0)*8+4
    offsets = np.zeros_like(grid)
    for center, delta in samples:
        weight = np.maximum(0, 1 - np.linalg.norm(grid-center, axis=3)/48)
        offsets += weight[...,None]*delta
    return np.rint(offsets).astype(np.int16)

def save_sheet(sheet, path, offsets):
    if offsets is not None:
        pixels = np.array(sheet)
        rgb = pixels[:,:,:3]
        r,g,b = (rgb >> 3).transpose(2,0,1)
        rgb[:] = np.clip(rgb.astype(np.int16) + offsets[r,g,b], 0, 255)
        sheet = Image.fromarray(pixels)
    sheet.save(path, compress_level=4)

def cell(sheet,index,columns,w,h):
    x=index%columns*w
    y=index//columns*h
    return sheet.crop((x,y,x+w,y+h))

def shield_layer(pic,side,raised=0):
    a=np.asarray(pic)[:,:,3]
    ys,xs=np.where(a[52:64,48:112]>180)
    if len(xs)==0:return Image.new("RGBA",pic.size)
    cx=int(np.median(xs)+48+side*(8+raised*9))
    cy=73-raised*9
    r=8+raised*2
    lay=Image.new("RGBA",pic.size)
    pen=ImageDraw.Draw(lay)
    pen.ellipse((cx-r,cy-14,cx+r,cy+14),fill="#cb9b67",outline="#32282b")
    pen.ellipse((cx-r+2,cy-12,cx+r-2,cy+12), fill="#894732",outline="#68483a")
    pen.arc((cx-r+2,cy-12,cx+r-2,cy+12),185,280,fill="#e8bc7b")
    pen.ellipse((cx-2,cy-3,cx+2,cy+2),fill="#cb9b67",outline="#68483a")
    return lay

def disk(pic,side,raised=0,back=False):
    lay=shield_layer(pic,side,raised)
    return Image.alpha_composite(lay,pic) if back else Image.alpha_composite(pic,lay)

def warp(pic,side,load,dip,animal=False):
    # Keep the support soles fixed. Shift the neck first, then let the hips settle.
    w=np.clip((116-yy)/(52 if animal else 72),0,1)
    swing=w*w*(3-2*w)
    mx=xx+side*load*swing
    my=yy-dip*w
    return Image.fromarray(cv2.remap(np.asarray(pic),mx.astype(np.float32),my.astype(np.float32),cv2.INTER_NEAREST))

def envelope(t,heavy):
    times=[0,.10,.34,.57,.86,1] if heavy else [0,.17,.34,.62,1]
    return np.interp(t,times,[0,.78,1,.78,.12,0] if heavy else [0,1,.72,.18,0])

def bake(kind):
    offsets=pigment_offsets(kind)
    folder=dst/kind
    folder.mkdir(parents=True,exist_ok=True)
    source=Image.open(src/"actors"/(kind+".png")).convert("RGBA")
    data=np.array(source)
    if kind=="hero": palette=np.array([forge.parse_hex(h) for h in hero_palette.split()],np.uint8)
    else: palette=forge.kmeans_palette(data[:,:,:3][data[:,:,3]>190],22,sample=12000,iters=8)
    # Map all clips to one fixed palette. A 32-cubed lookup amortizes the per-frame colour search.
    grid=np.indices((32,32,32)).transpose(1,2,3,0)*8+4
    lookup=forge.index_rgb(grid,palette)
    # Change pigments after indexing so the original silhouettes and line clusters stay registered.
    display_palette=palette.copy()
    for i,color in enumerate(palette):
        r,g,b=map(int,color)
        delta=(0,0,0)
        if kind=="atalanta" and r>g+15 and 85<g<165:
            delta=(5,2,-2)
        elif kind=="wolf" and max(color)-min(color)<36 and 95<g<185:
            delta=(3,4,5)
        elif kind=="boar" and min(r,g,b)>131:
            delta=(6,4,0)
        display_palette[i]=np.clip(color.astype(int)+delta,0,255)
    def pixelize(pic):
        a=np.array(pic)
        rgb=(a[:,:,:3]>>3).astype(int)
        indices=lookup[rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]]
        indices[a[:,:,3]<76]=-1
        small=forge.mode_downsample_blocks(indices,2,len(palette),coverage=.32)
        return Image.fromarray(forge.render(small,display_palette))
    for name in ["actors","motion","turns"]:
        path=src/name/(kind+".png")
        if not path.exists():continue
        sheet=Image.open(path).convert("RGBA")
        cols,rows=sheet.width//320,sheet.height//256
        baked=Image.new("RGBA",(cols*160,rows*128))
        for k in range(cols*rows):
            original=cell(sheet,k,cols,320,256)
            pic=pixelize(original)
            if kind=="hero":
                back=k//cols>=rows/2
                side=-1 if back else 1
                if name=="turns":
                    angle=(k//8+k%8/8)*math.pi/4
                    back=math.cos(angle)<-.01
                    side=1 if math.sin(angle)>=0 else -1
                pic=disk(pic,side,back=back)
            baked.paste(pic,(k%cols*160,k//cols*128))
        save_sheet(baked,folder/(name+".png"),offsets)
    near=pixelize(cell(source,0,source.width//320,320,256))
    rear_art=cell(source,source.width//320,source.width//320,320,256)
    rear=pixelize(rear_art)
    turns=src/"turns"/(kind+".png")
    turn_sheet=Image.open(turns) if turns.exists() else None
    animal=kind in ("wolf","boar","lion","centaur","chiron")
    # Each direction is a row; clips have a fixed baseline and frame count.
    clips={"light":12,"heavy":24}
    if kind=="hero":clips.update(guard=24,block=40)
    for clip,count in clips.items():
        sheet=Image.new("RGBA",(160*count,128*8))
        for d in range(8):
            ang=d*math.pi/4
            side=1 if d<=4 else -1
            back=2<d<6
            if turn_sheet:
                body=pixelize(cell(turn_sheet,d*8,8,320,256))
            else:
                body=(rear if back else near).copy()
                if (side>0)!=back:body=ImageOps.mirror(body)
                # Foreshorten front and rear views from the two original plates.
                width=round(160*(1-.13*math.cos(ang)**2))
                small=body.resize((width,128),Image.Resampling.NEAREST)
                body=Image.new("RGBA",(160,128));body.paste(small,((160-width)//2,0))
            for k in range(count):
                t=k/(count-1)
                if kind=="hero" and d in [1,2,6,7] and clip in ["guard","block"]:
                    pic=cell(approved,(74 if clip=="guard" else 98)+k,12,160,128)
                    if d in [2,6]:
                        # Carry the approved bent elbow, elbow lag and heel registration into profile.
                        narrow=pic.resize((141,128),Image.Resampling.NEAREST)
                        pic=Image.new("RGBA",(160,128))
                        pic.paste(narrow,(10,0))
                    if d in [6,7]:pic=ImageOps.mirror(pic)
                else:
                    heavy=clip in ("heavy","block")
                    r=envelope(t,heavy)
                    if clip=="guard": r=t*t*(3-2*t)
                    lateral=(10 if heavy else 3.8)*(.52+.48*abs(math.sin(ang)))
                    dip=(6 if heavy else 2.2)*(1.18 if animal else 1)
                    if clip=="guard":lateral,dip=-1.6,1.8
                    if clip in ("light","heavy"):
                        # Neck checks first; on strong blows the pelvis follows,
                        # the near knee gives, and the forefoot catches the fall.
                        w=np.clip((116-yy)/(53 if animal else 70),0,1)
                        catch=envelope(np.clip((t-.10)/.90,0,1),heavy)
                        toe=np.exp(-((xx-(80+side*12))/11)**2-((yy-109)/10)**2)
                        upper=np.clip((83-yy)/37,0,1)
                        shift=lateral*(upper*r+.52*w*(1-upper)*catch)
                        mx=xx+side*shift
                        my=yy-dip*w*catch+(3.6 if heavy else .65)*toe*math.sin(t*math.pi)**2
                        pic=Image.fromarray(cv2.remap(np.asarray(body),mx.astype(np.float32),my.astype(np.float32),cv2.INTER_NEAREST))
                    else:
                        pic=warp(body,side,lateral*r,dip*r,animal)
                    if kind=="hero":
                        lift=r if clip=="guard" else float(clip=="block")
                        pic=disk(pic,side,lift,back=back)
                sheet.paste(pic,(k*160,d*128))
        save_sheet(sheet,folder/(clip+".png"),offsets)
    if kind=="heracles":
        from bake_player_falls import bake_heracles
        save_sheet(bake_heracles([near,rear]),folder/"fall.png",offsets)
        # Use the reaching club drawing, separating the hands from the club for
        # a two-handed shove, clinch or a bow held across the chest.
        for action in ["push","hold","bow"]:
            sheet=Image.new("RGBA",(160*12,128*8))
            for d in range(8):
                back=2<d<6
                raw=cell(source,2+int(back)*3,3,320,256)
                for k in range(12):
                    t=k/11
                    im=raw.copy()
                    pen=ImageDraw.Draw(im)
                    if back:
                        pen.polygon([(185,99),(222,63),(244,75),(215,96),(183,108)],fill=(0,0,0,0))
                        grip=np.array([179,109])
                        sign=1
                    else:
                        pen.polygon([(146,160),(137,177),(94,218),(75,215),(77,192),(116,174)],fill=(0,0,0,0))
                        grip=np.array([147,161])
                        sign=-1
                    hand=grip+np.array([sign*(12+10*t),-4-10*t])
                    pen.line([tuple(grip),tuple(hand)],fill="#71503a",width=9)
                    pen.line([tuple(grip+[0,-1]),tuple(hand+[0,-1])],fill="#bb8961",width=5)
                    if action=="bow":
                        center=hand
                        arc=[tuple(center+np.array([sign*(4-16*abs(y/42)**1.7),y])) for y in range(-42,43,3)]
                        pen.line(arc,fill="#6c442b",width=5)
                        pen.line(arc,fill="#c39763",width=2)
                        nock=tuple(center+np.array([-sign*(14+20*t),1]))
                        pen.line([arc[0],nock,arc[-1]],fill="#d7c49f",width=2)
                    elif action=="hold":
                        pen.arc((hand[0]-6,hand[1]-7,hand[0]+5,hand[1]+5),10,270,fill="#d3a072",width=4)
                    pic=pixelize(im)
                    if ((d<=4)!=back):pic=ImageOps.mirror(pic)
                    pic=warp(pic,-1 if d<=4 else 1,t*4,t*2)
                    sheet.paste(pic,(160*k,128*d))
            save_sheet(sheet,folder/(action+".png"),offsets)
    if kind=="centaur":
        from bake_centaur_spear import bake as bake_spear
        save_sheet(bake_spear(root/"art/originals",pixelize),folder/"spear.png",offsets)
    if kind=="chiron":
        from bake_chiron_fall import bake as bake_chiron_fall
        save_sheet(bake_chiron_fall([near,rear]),folder/"fall.png",offsets)
        from bake_chiron_bow import bake as bake_bow
        save_sheet(bake_bow(source,pixelize),folder/"bow.png",offsets)
    if kind in ("atalanta","bandit_chief"):
        from bake_evade_break import bake as bake_evade_break
        hunter=kind=="atalanta"
        save_sheet(bake_evade_break([near,rear],hunter),folder/("evade.png" if hunter else "break.png"),offsets)
    if kind=="refugee":
        from bake_villager_fall import bake as bake_villager_fall
        save_sheet(bake_villager_fall([near,rear]),folder/"fall.png",offsets)
    if kind in ("bandit_archer","bandit_chief"):
        from bake_raider_falls import bake as bake_raider_fall
        save_sheet(bake_raider_fall([near,rear],kind=="bandit_archer"),folder/"fall.png",offsets)
    if kind=="bandit_archer":
        from bake_bandit_release import bake_release
        bake_release(folder)
    if kind in ("hero","atalanta"):
        from bake_player_falls import bake as bake_player_fall
        shields=[shield_layer(near,1),shield_layer(rear,-1)] if kind=="hero" else None
        save_sheet(bake_player_fall([near,rear],shields),folder/"fall.png",offsets)
    if kind in ("bandit","wolf","centaur","boar","lion"):
        from bake_falls import bake as bake_fall
        bake_fall(folder)
        if kind=="lion":
            bake_fall(folder,grapple=True)
            from bake_beast_contact import bake as bake_contact
            with Image.open(folder/"actors.png") as plates:
                bake_contact(plates,kind,broken=True).save(folder/"break.png",compress_level=4)
    if kind in ("hero","bandit"):
        from bake_raider_throw import bake as bake_throw
        bake_throw(folder)
    print(kind,flush=True)

if __name__=="__main__":
    kinds=sys.argv[2:] or json.loads((root/"prototype/data/tables/units.json").read_text()).keys()
    for kind in kinds:bake(kind)

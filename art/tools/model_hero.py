"""Build the skinned valley hero from the approved paintings, in metres, facing +Z."""
import argparse
from skinned_glb import write_skin
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image

parser = argparse.ArgumentParser(description="Build a painted, skinned chapter-one figure")
parser.add_argument("--actor", choices=("hero","atalanta","heracles"), default="hero")
actor = parser.parse_args().actor
archer = actor == "atalanta"
strongman = actor == "heracles"
rng = random.Random(197)
nodes = []
parts = {}
parents = {}
tau = math.tau
skin, light, hair, leather = "a76847", "bf855a", "392720", "553929"
linen, copper, bronze, cloak = "c1a17a", "bb9257", "796241", "963f2b"


def joint(name, parent, pos):
    index = len(nodes)
    nodes.append(dict(name=name, translation=list(pos)))
    if parent is not None:
        nodes[parent].setdefault("children", []).append(index)
    parents[index] = parent
    parts[index] = [[], [], [], []]
    return index


# Sample opaque interior regions of the approved front and rear paintings.
# Quadrilaterals follow the chin, cloth hems and folds rather than a square crop.
art_root = Path(__file__).resolve().parents[1]
source = Image.open(art_root/"originals"/"figures.png").convert("RGBA")
rear_x = 3*source.width//4
swatches = {
    "face": [(158,50),(164,70),(175,70),(179,49)],
    "curls": [(153,35),(147,50),(179,47),(173,33)],
    "back_hair": [(rear_x+126,37),(rear_x+122,57),(rear_x+145,59),(rear_x+149,37)],
    "mantle": [(rear_x+110,80),(rear_x+84,158),(rear_x+131,195),(rear_x+151,104)],
    "fold": [(191,76),(157,108),(153,120),(211,95)],
    "linen": [(154,148),(144,178),(160,184),(166,147)],
    "skin": [(196,121),(194,148),(199,154),(204,130)],
    "wrap": [(190,248),(193,273),(200,273),(198,248)],
    "calf": [(183,215),(190,240),(199,238),(195,219)],
    "shaft": [(117,72),(127,97),(130,97),(120,72)],
    "patina": [(99,38),(104,48),(111,58),(106,40)],
}
if archer:
    source = Image.open(art_root.parent/"prototype/art/original/actors/atalanta.png").convert("RGBA")
    def patch(x,y,w,h):
        return [(x,y),(x,y+h),(x+w,y+h),(x+w,y)]
    swatches = {
        "face":patch(159,62,12,14), "curls":patch(156,53,14,7), "back_hair":patch(154,52,12,9),
        "mantle":patch(151,85,20,12), "fold":patch(145,92,19,9), "linen":patch(163,132,13,22),
        "skin":patch(146,125,5,12), "wrap":patch(175,190,4,12), "calf":patch(157,160,5,12),
    }
    skin,light,hair,leather = "a77450","bd8966","422e22","5a3c2c"
    linen,cloak = "ac8662","614a38"
if strongman:
    source = Image.open(art_root.parent/"prototype/art/original/actors/heracles.png").convert("RGBA")
    def region(x,y,w,h):
        return [(x,y),(x,y+h),(x+w,y+h),(x+w,y)]
    swatches = {
        "face":region(173,92,5,7), "curls":region(166,86,8,4), "back_hair":region(165,87,6,4),
        "mantle":region(169,117,6,5), "fold":region(171,116,5,6), "linen":region(159,156,6,15),
        "skin":region(153,116,7,9), "wrap":region(186,196,4,10), "calf":region(186,192,5,12),
        "wood":region(126,192,6,11), "sash":region(167,146,9,5),
    }
    skin,light,hair,leather = "99613a","bf8756","3e2c22","63432b"
    linen,cloak = "825538","56443b"
tile_size = 64
atlas = Image.new("RGB",(256,192))
for i,(name,quad) in enumerate(swatches.items()):
    patch = source.transform((tile_size,tile_size),Image.Transform.QUAD,
                             sum((list(q) for q in quad),[]),Image.Resampling.BILINEAR)
    atlas.paste(patch.convert("RGB"),((i%4)*tile_size,(i//4)*tile_size))
if actor == "hero":
    # Preserve the resolution of the approved frontal turnaround for the face,
    # shoulder wrap and chiton. The smaller islands still serve the reverse.
    import cv2
    crop=np.asarray(Image.open(art_root/"originals/hero-turn.png").convert("RGBA").crop((225,38,555,345)))
    outside=(crop[:,:,3]<160).astype(np.uint8)
    _,labels=cv2.distanceTransformWithLabels(outside,cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
    rgb=crop[:,:,:3].copy()
    rgb[outside==1]=rgb[outside==0][labels[outside==1]-1]
    frontal=Image.fromarray(rgb)
    expanded=Image.new("RGB",(640,512))
    expanded.paste(atlas)
    expanded.paste(frontal,(256,0))
    atlas=expanded
if archer or strongman:
    import cv2
    expanded=Image.new("RGB",(896,256))
    expanded.paste(atlas)
    for rear in range(2):
        layer=np.asarray(source.crop((0,256*rear,320,256*(rear+1))))
        outside=(layer[:,:,3]<128).astype(np.uint8)
        _,labels=cv2.distanceTransformWithLabels(outside,cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
        rgb=layer[:,:,:3].copy()
        rgb[outside==1]=rgb[outside==0][labels[outside==1]-1]
        expanded.paste(Image.fromarray(rgb),(256+320*rear,0))
    atlas=expanded
atlas.save(art_root.parent/f"prototype/art/original/{actor}_pigments.png")
tiles = {key:i for i,key in enumerate(swatches)}


def paint_uv(part, point, center, pigment):
    x,y,z = point
    name = nodes[part]["name"]
    patch,u,v,weight = None,0,0,0
    if archer or strongman:
        rear=center[2]<-.027
        side=-1 if rear else 1
        def painted(px,py):
            return [(256+320*int(rear)+px)/atlas.width,py/atlas.height],.98
        if name=="Head":
            cx=(156 if rear else 164) if archer else (147 if rear else 173)
            hair_part=pigment in ("423023",hair)
            if hair_part:
                return painted(cx+side*x*59,(60 if archer else 90)-(.12+y-.22)*45)
            return painted(cx+side*x*57,(79 if archer else 107)-(y-.045)*87)
        if name in ("Chest","Mantle","Hips"):
            cx=(152 if rear else 165) if archer else (148 if rear else 174)
            if name=="Chest":
                return painted(cx+side*x*76,(131 if archer else 145)-y*(109 if archer else 91))
            if name=="Mantle":
                return painted(cx+side*x*71,(86 if archer else 108)-y*87)
            return painted(cx+side*x*79,(137 if archer else 151)-y*97)
        if name.startswith(("Arm","Fore","Hand")) and pigment in (skin,light):
            px=(172 if rear else 191) if archer else (167 if rear else 194)
            return painted(px+side*x*49,(117 if archer else 123)-y*89+z*33)
        if name.startswith(("Thigh","Shin","Foot")):
            px=(164 if rear else 175) if archer else (162 if rear else 190)
            if name[-1]=="R": px-=23 if archer else 35
            py=(152 if archer else 169) if name.startswith("Thigh") else 190 if name.startswith("Shin") else 222
            return painted(px+side*x*73,py-y*92+z*28)
    if actor == "hero":
        def original(px,py):
            return [(256+px)/atlas.width,py/atlas.height],.98
        if name=="Head" and pigment=="ac795a":
            # Front projection narrows toward the chin, wrapping the cheek
            # pigment around the side instead of projecting empty space.
            width=np.interp(y,[.046,.074,.10,.16,.21,.26],[11,20,24,28,32,28])
            side=np.clip((.045-z)/.052,0,1)
            px=164+np.clip(x*221,-width,width)
            py=113-(y-.046)*382
            return original(px*(1-side)+(164+np.sign(x)*24)*side,py*(1-side)+(98-(y-.12)*56)*side)
        if name=="Head" and pigment=="423023":
            if center[2]<-.015:
                cell=tiles["back_hair"]
                return [((cell%4)*64+32+x*196)/atlas.width,
                        ((cell//4)*64+4+np.clip((.314-y)*279,0,55))/atlas.height],.98
            return original(163+x*249,np.clip(22+(.308-y)*308,23,61))
        if name=="Chest" and pigment in ("baab83","934a32","b78a5e"):
            return original(np.clip(168+380*x,107,273),np.clip(273-326*(y+.011),111,274))
        if name.startswith("Arm") and pigment in (skin,light):
            return original(250+x*148,211+np.clip(-y*306,0,81))
        if name=="Head" and pigment==skin:
            return original(163+x*130,115+np.clip((.045-y)*141,0,12))
    if strongman and name == "Club":
        patch,u,v,weight = "wood",.5+x/.18,-y/.96,.84
    elif strongman and pigment == "c68b49":
        patch,u,v,weight = "sash",.5+x/.39,(.10-y)/.41,.75
    elif strongman and name == "Chest" and pigment in (skin,light):
        patch,u,v,weight = "skin",.5+x/.57,(.44-y)/.53,.58
    elif name == "Head":
        if pigment in (hair,"473226","382820","54392b") and center[1]>.181:
            patch = "curls" if center[2]>0 else "back_hair"
            u,v,weight = .5+x/.29,(.319-y)/.16,.92
        elif pigment == light and center[2]>.052:
            patch,u,v,weight = "face",.5+x/.223,(.200-y)/.156,.88
    elif name == "Mantle" and pigment != "ba8558":
        patch,u,v,weight = "mantle",(x+.16)/.49,(.025-y)/.82,.97
    elif name == "Chest" and pigment in ("a54c32","cf905d","99412e",cloak):
        # Along the diagonal shoulder wrap, keeping the painted hem parallel.
        u=(x+.135)/.32
        v=1-(y-.055-.326*u)/.14
        patch,weight = "fold",.94
    elif name == "Hips" and pigment == linen:
        patch,u,v,weight = "linen",.5+x/.45,(.09-y)/.33,.88
    elif name.startswith(("Arm","Fore","Thigh","Shin")) and pigment in (skin,light):
        if name.startswith("Shin"):
            patch,u,v,weight = "calf",.5+x/.13,-y/.35,.61
        else:
            patch,u,v,weight = "skin",.5+x/.18,-y/.30,.58
    elif name.startswith("Shin") and pigment == leather:
        patch,u,v,weight = "wrap",.5+x/.135,-y/.36,.65
    elif name=="Spear" and pigment=="70472e":
        patch,u,v,weight = "shaft",.5+x/.036,(1.18-y)/2.02,.72
    elif name=="Shield" and pigment in ("843d30","97513a"):
        patch,u,v,weight = "mantle",.5+x/.62,.5-y/.62,.22
    elif name=="Shield" and pigment in (copper,"b68d50","e2bb73"):
        patch,u,v,weight = "patina",.5+x/.65,.5-y/.65,.45
    if patch is None:
        return [0,0],0
    cell=tiles[patch]
    # A two-texel inset prevents adjacent swatches bleeding at game distance.
    return [((cell%4)*64+2+60*min(1,max(0,u)))/atlas.width,
            ((cell//4)*64+2+60*min(1,max(0,v)))/atlas.height],weight


def polygon(part, points, color):
    pts = np.array(points)
    normal = np.cross(pts[1]-pts[0], pts[2]-pts[0])
    norm = np.linalg.norm(normal)
    if norm < 1e-8:
        return
    normal /= norm
    tint = rng.uniform(.94, 1.04)
    rgb = [(int(color[i:i+2], 16)/255)**2.2*tint for i in (0, 2, 4)]
    p, n, c, uv = parts[part]
    center = pts.mean(axis=0)
    for j in range(1, len(pts)-1):
        for v in (pts[0], pts[j], pts[j+1]):
            p.append(v)
            n.append(normal)
            coords, weight = paint_uv(part,v,center,color)
            c.append([*rgb,weight])
            uv.append(coords)


def curved_surface(part,rings,color,closed=True):
    points=np.asarray(rings)
    tangent=(np.roll(points,-1,axis=1)-np.roll(points,1,axis=1)
             if closed else np.gradient(points,axis=1))
    normals=np.cross(np.gradient(points,axis=0),tangent)
    normals/=np.maximum(1e-9,np.linalg.norm(normals,axis=2,keepdims=True))
    for h in range(len(points)-1):
        for i in range(len(points[h]) if closed else len(points[h])-1):
            j=(i+1)%len(points[h])
            corners=((h,i),(h+1,i),(h+1,j),(h,j))
            polygon(part,[points[a,b] for a,b in corners],color)
            parts[part][1][-6:]=[normals[corners[k]] for k in (0,1,2,0,2,3)]


def shell(part, rows, color, sides=12, pleat=0):
    # Each ring specifies its own centre, width and depth for a sculpted silhouette.
    if not pleat:
        sides=max(sides,24)
    levels = []
    for y, x, z, rx, rz in rows:
        ring = []
        for i in range(sides):
            a = tau*i/sides
            k = 1-pleat*(i % 2)
            hem = (.039*math.sin(3*a+.8)+.017*math.sin(7*a)) if pleat and y<-.15 else 0.
            ring.append((x+rx*k*math.cos(a), y+hem, z+rz*k*math.sin(a)))
        levels.append(ring)
    if pleat==0:
        curved_surface(part,levels,color)
        polygon(part,levels[0],color)
        polygon(part,levels[-1][::-1],color)
        return
    for low, high in zip(levels, levels[1:]):
        for i in range(sides):
            j = (i+1) % sides
            polygon(part, [low[i], high[i], high[j], low[j]], color)
    polygon(part, levels[0], color)
    polygon(part, levels[-1][::-1], color)


def oval(part, center, radii, color, sides=10):
    x,y,z = center
    w,h,d = radii
    shell(part, [(y+h*v,x,z,w*r,d*r) for v,r in
                 [(-1,.15),(-.67,.75),(-.15,1),(.43,.91),(.83,.55),(1,.13)]],color,sides)


def rod(part, a, b, radii, color, sides=8):
    a,b = np.array(a),np.array(b)
    axis = (b-a)/np.linalg.norm(b-a)
    ref = (0,1,0) if abs(axis[1])<.9 else (1,0,0)
    u = np.cross(axis,ref)
    u /= np.linalg.norm(u)
    v = np.cross(axis,u)
    circles = [[p+r*(u*math.cos(tau*i/sides)+v*math.sin(tau*i/sides)) for i in range(sides)]
               for p,r in zip((a,b),radii)]
    for i in range(sides):
        j=(i+1)%sides
        polygon(part,[circles[0][i],circles[0][j],circles[1][j],circles[1][i]],color)
    polygon(part,circles[0][::-1],color)
    polygon(part,circles[1],color)


root=joint("Figure",None,(0,0,0))
hips=joint("Hips",root,(0,.88,0))
torso=joint("Chest",hips,(0,.10,0))
if actor=="hero":
    shell(torso,[(-.12,0,0,.149,.111),(.012,0,0,.160,.124),(.14,0,0,.179,.135),
                 (.245,0,-.005,.210,.147),(.33,0,-.012,.225,.151),
                 (.383,0,-.016,.221,.135),(.433,0,0,.133,.094)],"baab83",40)
else:
    shell(torso,[(-.12,0,0,.15,.108),(.04,0,.002,.158,.12),(.15,0,0,.177,.126),
                 (.32,0,-.01,.227,.153),(.39,0,-.012,.234,.133),(.44,0,0,.133,.094)],skin)
# Folded chiton skirt, studded belt and individual leather tabs.
shell(hips,[(-.22,0,.008,.227,.168),(-.19,0,.007,.226,.169),(.025,0,0,.164,.13),
            (.09,0,0,.154,.12)],linen,24,.105)
shell(hips,[(.027,0,0,.167,.135),(.042,0,0,.17,.137),(.096,0,0,.165,.13)],leather)
if archer:
    # Short hide mantle and a fitted leather tunic, with a diagonal quiver strap.
    shell(torso,[(-.11,0,0,.155,.112),(.10,0,0,.163,.125),(.28,0,0,.19,.142),
                 (.38,0,0,.19,.119)],"a54c32")
    mantle=joint("Mantle",torso,(0,.39,-.07))
    shell(mantle,[(-.18,0,.052,.224,.154),(-.09,0,.07,.234,.158),
                  (.02,0,.065,.185,.128),(.048,0,.066,.105,.092)],cloak,18,.12)
    # The loose shoulder flap and laced hide skirt define the huntress in silhouette.
    for j in range(8):
        def flap(k):
            t=k/8
            return [(-.185+.22*t,.01,.10+.046*t),
                    (-.29+.24*t,-.18+.11*t,.105+.092*t),
                    (-.265+.22*t,-.32+.19*t-.019*(k%2),.128+.076*t)]
        a,b=flap(j),flap(j+1)
        for row in range(2):
            polygon(mantle,[a[row],b[row],b[row+1],a[row+1]],cloak)
    for strand in range(5):
        angle=.26+strand*.55
        for sense in [-1,1]:
            def lace(t):
                a=angle+sense*.46*t
                return ((.176+.059*t)*math.cos(a),.013-.217*t,(.14+.038*t)*math.sin(a)+.011)
            rod(hips,lace(0),lace(.5),(.008,.009),leather)
            rod(hips,lace(.5),lace(1),(.009,.008),leather)
    for j in range(9):
        a=j/9; b=(j+1)/9
        def belt(t,dx):
            return (-.136+.285*t+dx,.018+.338*t,.135+.021*math.sin(tau*.5*t))
        polygon(torso,[belt(a,0),belt(b,0),belt(b,.036),belt(a,.036)],leather)
    rod(torso,(-.13,.018,-.15),(.169,.49,-.181),(.062,.082),leather,14)
    rod(torso,(.153,.467,-.18),(.17,.495,-.183),(.087,.087),copper,14)
    for i in range(6):
        x=.141+.039*math.cos(tau*i/6)
        z=-.18+.044*math.sin(tau*i/6)
        rod(torso,(x,.48,z),(x+.083,.626+.013*(i%3),z),(.006,.005),"926843")
        rod(torso,(x+.057,.578,z),(x+.083,.627+.013*(i%3),z),(.013,.009),"bd8155")
elif strongman:
    mantle=joint("Mantle",torso,(0,.39,-.06))
    for sign in [-1,1]:
        oval(torso,(sign*.102,.303,.102),(.124,.091,.070),light)
        oval(torso,(sign*.11,.28,-.085),(.127,.125,.080),skin)
    for j in range(8):
        def sash(t,h,side):
            return (-.19+.38*t,.025+.36*t+h,side*(.139+.036*math.sin(math.pi*t)))
        a,b=j/8,(j+1)/8
        for side in [-1,1]:
            polygon(torso,[sash(a,0,side),sash(b,0,side),sash(b,.090,side),sash(a,.090,side)],cloak)
    oval(mantle,(.162,.008,.063),(.085,.052,.102),cloak)
    shell(hips,[(.015,0,0,.179,.145),(.053,0,.002,.178,.143),(.088,0,0,.168,.14)],"c68b49",16)
    for x in [-.027,.031]:
        polygon(hips,[(x-.031,.074,.145),(x+.028,.056,.151),(x+.059,-.201,.170),
                      (x+.007,-.245,.183),(x-.013,-.115,.174)],"c68b49")
    # Folded leather cradle at the right end of the sash, open on top.
    for z in [-.045,.045]:
        edge = [(-.141,.035,z),(-.221,-.014,z),(-.280,-.042,z),(-.302,-.009,z)]
        for a,b in zip(edge,edge[1:]):
            polygon(torso,[a,b,(b[0],b[1],z+.020),(a[0],a[1],z+.020)],leather)
    rod(torso,(-.293,-.018,-.046),(-.293,-.018,.060),(.012,.013),leather)
    club=joint("Club",torso,(0,.20,-.18))
    shell(club,[(-.83,.063,.032,.047,.053),(-.78,.068,.025,.090,.085),
                (-.61,.049,.016,.094,.084),(-.39,.028,.008,.068,.057),
                (-.15,0,0,.034,.034),(.073,0,0,.029,.029)],"775137",11)
    for y in [-.11,-.073,-.036,.004]:
        rod(club,(0,y,0),(0,y+.012,0),(.036,.035),leather)
else:
    for i in range(13):
        a=tau*i/13
        x,z=math.cos(a),math.sin(a)
        w=.024
        points=[(.166*x-w*z,.046,.132*z+w*x),(.166*x+w*z,.046,.132*z-w*x),
                (.204*x+w*z,-.103,.162*z-w*x),(.206*x,-.139,.164*z),(.204*x-w*z,-.103,.162*z+w*x)]
        polygon(hips,points,"80533a")
        oval(hips,(.168*x,.072,.137*z),(.011,.01,.011),copper,6)
    # Cape falls from the left shoulder across the back in a fan of irregular folds.
    mantle=joint("Mantle",torso,(0,.39,-.07))
    for i in range(14):
        def edge(k):
            f=k/14
            return [(-.16+.38*f,.026-.03*math.sin(f*math.pi),-.03),
                    (-.19+.44*f,-.135,-.095-.042*(k%2)+.078*f**4),
                    (-.15+.50*f,-.61-.14*math.sin(f*2.8)-.023*(k%2),-.17-.070*(k%2)+.095*f**4)]
        a,b=edge(i),edge(i+1)
        for j in range(2):
            polygon(mantle,[a[j],b[j],b[j+1],a[j+1]],["8f4233","aa5039","7a372b"][i%3])
        polygon(mantle,[a[2],b[2],(b[2][0],b[2][1]+.014,b[2][2]-.003),
                        (a[2][0],a[2][1]+.014,a[2][2]-.003)],"ba8558")
    # Cross-body wool wrap: radiating ridges gather at the brooch,
    # and the outside edge turns over the shield-side deltoid.
    cloth=[]
    for t in np.linspace(0,1,27):
        band=[]
        for u in np.linspace(0,1,49):
            x=-.134+.426*u
            low=.332-.229*math.sin(u*2.26)-.044*u
            high=.363+.085*math.sin(math.pi*u)-.088*u**3
            y=low+(high-low)*t
            z=.160-.044*(1-u)**3-.137*u**4+.026*math.sin(math.pi*t)
            z+=.012*(.27+.73*u)*math.cos(t*15+2.8*u)
            band.append((x,y,z))
        cloth.append(band)
    curved_surface(torso,cloth,"934a32",False)
    # Return the woven hem rather than leaving a paper-thin edge.
    hem=np.array(cloth[0])
    curved_surface(torso,[hem+[0,.005,-.012],hem],"b78a5e",False)
    oval(torso,(-.110,.370,.140),(.028,.029,.012),bronze,24)
    oval(torso,(-.110,.370,.151),(.020,.021,.008),copper,24)
neck=joint("Head",torso,(0,.45,0))
oval(neck,(0,.02,0),(.079,.079,.075),skin)
# Orbit, cheekbone, nose bridge and chin belong to one continuous face.
face=[]
profile=[(.045,.054,.059),(.066,.074,.084),(.094,.092,.092),(.130,.105,.097),
         (.162,.111,.100),(.193,.113,.101),(.225,.112,.099),(.254,.099,.089)]
for y in np.linspace(.045,.254,41):
    w=np.interp(y,*np.asarray(profile)[:,[0,1]].T)
    d=np.interp(y,*np.asarray(profile)[:,[0,2]].T)
    ring=[]
    for a in np.arange(64)*tau/64:
        x=w*math.cos(a)
        front=max(0,math.sin(a))
        def ridge(cx,cy,sx,sy):
            return math.exp(-((abs(x)-cx)/sx)**2-((y-cy)/sy)**2)
        relief=(.026*ridge(0,.151,.017,.042)+.030*ridge(0,.124,.023,.013)
                -.015*ridge(.049,.158,.029,.014)+.014*ridge(.051,.181,.042,.013)
                +.015*ridge(.071,.135,.034,.025)+.012*ridge(0,.090,.044,.012)
                +.018*ridge(0,.064,.042,.023))
        ring.append((x,y,.014+d*math.sin(a)+front**2*relief))
    face.append(ring)
curved_surface(neck,face,"ac795a")
for side in (-1,1):
    oval(neck,(side*.111,.148,-.003),(.021,.033,.021),skin)
curls=[]
for t in np.linspace(0,1,21):
    ring=[]
    for a in np.arange(80)*tau/80:
        fringe=.145+.054*math.sin(a)+.009*math.sin(9*a)
        y=fringe+(.314-fringe)*t
        wave=.006*math.cos(15*a+4*t)+.004*math.cos(7*a-12*t)
        r=math.sqrt(max(.0002,1-((y-.218)/.096)**2))
        ring.append(((.131+wave)*r*math.cos(a),y,-.011+(.121+wave)*r*math.sin(a)))
    curls.append(ring)
curved_surface(neck,curls,"423023")
if archer:
    oval(neck,(0,.181,-.112),(.081,.075,.065),hair)
    for j in range(5):
        oval(neck,(.014*math.sin(j),.146-.036*j,-.122-.007*j),
             (.044-.004*j,.041,.039-.003*j),hair)
if strongman:
    for i in range(12):
        angle=math.pi*i/11
        oval(neck,(.093*math.cos(angle),.087-.032*math.sin(angle),.052+.052*math.sin(angle)),
             (.034,.049,.026),hair,8)
# Segmented limbs pivot at shoulder, elbow, hip and knee.
for side,sign in [('L',1),('R',-1)]:
    thigh=joint('Thigh'+side,hips,(sign*.114,-.065,0))
    shell(thigh,[(-.335,0,.015,.057,.061),(-.25,0,.008,.074,.076),
                 (-.09,0,0,.09,.087),(0,0,0,.082,.077)],skin,10)
    shin=joint('Shin'+side,thigh,(0,-.33,.019))
    oval(shin,(0,-.012,0),(.063,.064,.066),skin)
    shell(shin,[(-.345,0,-.012,.04,.048),(-.28,0,-.015,.047,.055),(-.12,0,-.028,.066,.071),(-.037,0,0,.058,.06)],light,10)
    for y in [-.28,-.251,-.21,-.11]:
        r=.052 if y<-.15 else .067
        shell(shin,[(y,0,-.017,r,r+.009),(y+.018,0,-.017,r+.002,r+.011)],leather,10)
    foot=joint("Foot"+side,shin,(0,-.345,-.012))
    oval(foot,(0,-.015,.055),(.066,.047,.126),skin)
    oval(foot,(0,-.046,.060),(.068,.014,.128),leather)
    rod(foot,(-.045,.001,.102),(.045,.001,.085),(.014,.014),leather)
    arm=joint('Arm'+side,torso,(sign*(.253 if strongman else .211),.354,0))
    oval(arm,(sign*.012,-.016,0),(.081,.085,.081),skin)
    shell(arm,[(-.242,sign*.022,.024,.048,.048),(-.153,sign*.026,.021,.061,.066),
               (-.06,sign*.014,.002,.070,.069),(0,0,0,.069,.069)],light,10)
    fore=joint('Fore'+side,arm,(sign*.022,-(.262 if strongman else .232),.024))
    rod(fore,(0,0,0),(0,-.059,.177),(.055,.039),light,10)
    rod(fore,(0,-.038,.094),(0,-.06,.167),(.054,.045),leather)
    rod(fore,(0,-.049,.131),(0,-.053,.143),(.052,.049),copper)
    hand=joint("Hand"+side,fore,(0,-.055,.225 if strongman else .193))
    oval(hand,(0,0,0),(.043,.048,.041),skin)
    # Bent finger segments wrap around the weapon socket, moving with the wrist.
    for finger in range(4):
        y = .028-finger*.017
        fingertip = (sign*.018,y-.004,.043)
        knuckle = (sign*.043,y,.020)
        if strongman:
            x=sign*(.030-finger*.018)
            rod(hand,(x,.021,.008),(x,.047,.018),(.011,.010),light,7)
            rod(hand,(x,.047,.018),(x,.080-abs(finger-1)*.009,.023),(.010,.007),skin,7)
            continue
        rod(hand,(sign*.030,y,-.008),knuckle,(.011,.010),light,7)
        rod(hand,knuckle,fingertip,(.010,.008),skin,7)
    rod(hand,(-sign*.029,.026,.004),(-sign*.012,.007,.044),(.015,.011),light,7)
    if actor == "hero":
        if side=='L':
            shield=joint('Shield',hand,(.036,.010,.042))
        else:
            spear=joint('Spear',hand,(0,.005,.007))


if actor == "hero":
    # Convex aspis with a returned lip, inner wood, two bronze bands and painted laurel.
    def shield_ring(rad,depth):
        return [np.array((rad*math.cos(tau*i/64),rad*math.sin(tau*i/64),depth)) for i in range(64)]
    profile=[(.012,.090),(.115,.085),(.263,.054),(.309,.015),(.323,.012),(.328,-.010),
             (.321,-.035),(.295,-.038),(.13,.040),(.012,.048)]
    for (ra,za),(rb,zb),col in zip(profile,profile[1:],["bc995d","843d30","97513a","e2bb73","b68d50","745332","b38b55","584031","634a36"]):
        a,b=shield_ring(ra,za),shield_ring(rb,zb)
        for i in range(64):
            j=(i+1)%64
            polygon(shield,[a[i],b[i],b[j],a[j]],col)
    oval(shield,(0,0,.09),(.070,.070,.043),copper,32)
    for sign in [-1,1]:
        for i in range(7):
            a=-1.15+i*.30
            x,y=sign*.209*math.cos(a),.209*math.sin(a)
            z=.072
            polygon(shield,[(x,y,z),(x-sign*.026,y+.023,z+.003),(x-sign*.044,y+.022,z+.006),(x-sign*.024,y,z+.004)],"d0ad70")
            a2=a+.3
            rod(shield,(x,y,z),(sign*.209*math.cos(a2),.209*math.sin(a2),z),(.004,.004),copper,5)
    # Grip and arm strap remain visible when the shield turns edge-on.
    rod(shield,(-.105,-.006,-.041),(.105,-.006,-.041),(.020,.020),leather)
    for x in [-.106,.106]:
        rod(shield,(x,-.006,-.041),(x,-.006,.041),(.014,.016),bronze)
    for i in range(16):
        a=tau*(i+.5)/16
        oval(shield,(.290*math.cos(a),.290*math.sin(a),.038),(.007,.007,.006),copper,6)
    # Ash shaft, bronze bindings, ridged leaf-shaped head and butt spike.
    rod(spear,(0,-.84,0),(0,1.18,0),(.017,.014),"70472e")
    rod(spear,(0,-.12,0),(0,.11,0),(.022,.021),leather)
    for y in [1.12,1.145,1.17]:
        rod(spear,(0,y,0),(0,y+.012,0),(.023,.022),copper)
    blade=[(0,1.17,0),(-.054,1.245,0),(0,1.49,0),(.054,1.245,0)]
    for side in [-1,1]:
        for i in range(4):
            polygon(spear,[blade[i],blade[(i+1)%4],(0,1.267,side*.023)],["e1bd80","917043"][i%2])
    rod(spear,(0,-.87,0),(0,-.77,0),(.002,.022),bronze)

def smooth(lo, hi, x):
    t = min(1., max(0., (x-lo)/(hi-lo)))
    return t*t*(3.-2.*t)


# Bind vertices in a common rest space. Across each flexion zone the same
# weight gradient is used on both sides of the joint. Hardware stays rigid.
bone_ids = {node["name"]: i for i,node in enumerate(nodes)}
origins = []
for i,node in enumerate(nodes):
    offset = np.array(node["translation"], dtype=float)
    origins.append(offset if parents[i] is None else origins[parents[i]]+offset)


def influences(i, point):
    name = nodes[i]["name"]
    x,y,z = point
    other, w = i, 0.
    side = name[-1]
    if name.startswith("Thigh"):
        if y < -.22:
            other,w = bone_ids["Shin"+side], .52*smooth(.22,.33,-y)
        else:
            other,w = hips, .46*(1-smooth(0,.105,-y))
    elif name.startswith("Shin"):
        if y < -.24:
            other,w = bone_ids["Foot"+side], .5*smooth(.265,.345,-y)
        else:
            other,w = parents[i], .48*(1-smooth(0,.095,-y))
    elif name.startswith("Foot"):
        other,w = parents[i], .5*(1-smooth(0,.11,abs(z)+abs(y)))
    elif name.startswith("Arm"):
        if y < -.13:
            other,w = bone_ids["Fore"+side], .52*smooth(.15,.232,-y)
        else:
            other,w = torso, .45*(1-smooth(.005,.10,-y))
    elif name.startswith("Fore"):
        if z>.11:
            other,w = bone_ids["Hand"+side], .52*smooth(.125,.193,z)
        else:
            other,w = parents[i], .48*(1-smooth(0,.085,z))
    elif name == "Mantle":
        other,w = torso, 1-smooth(0,.40,-y)
    elif name == "Chest":
        other,w = hips, .65*(1-smooth(-.10,.12,y))
    elif name == "Hips" and y < 0:
        other = bone_ids["ThighL" if x>0 else "ThighR"]
        w = .48*smooth(0,.20,-y)*smooth(0,.09,abs(x))
    return [i,other,0,0], [1-w,w,0.,0.]


positions, normals, colors, texcoords, indices, weights = [], [], [], [], [], []
for i,(pos,nrm,col,uv) in parts.items():
    if not pos:
        continue
    points = np.asarray(pos)
    if archer and nodes[i]["name"].startswith(("Arm","Fore","Shin","Thigh","Chest","Head")):
        points = points * [.90,1.,.95]
    if strongman:
        name = nodes[i]["name"]
        if name.startswith("Arm"):
            points = points * [1.27,1.12,1.18]
        elif name in ("Chest","Mantle","Hips") or name.startswith(("Thigh","Shin","Hand")):
            points = points * [1.21,1.,1.16]
        elif name.startswith("Fore"):
            points = points * [1.22,1.,1.16]
    positions.extend(points+origins[i])
    normals.extend(nrm)
    colors.extend(col)
    texcoords.extend(uv)
    for point in pos:
        idx, w = influences(i,point)
        indices.append(idx)
        weights.append(w)

out=art_root.parent/"prototype/art/original"/("hero_valley.glb" if actor == "hero" else actor+".glb")
write_skin(out,"Hero",nodes,root,origins,positions,normals,colors,texcoords,indices,weights)

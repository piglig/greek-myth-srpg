"""Build the ten camp props in metres, with UVs on the shared painted albedo atlas."""
from pathlib import Path
import json
import math
import struct
import numpy as np
from PIL import Image, ImageDraw, ImageOps

DEST = Path(__file__).resolve().parents[2] / 'prototype/art/camp'
LINEN, WOOD, BRONZE, CLAY, STONE, FUR, KEY, FRIEZE, OWL, RED, GLAZE, COAL, LEAF, TIMBER, HIDE, WOOL = range(16)
PI = math.pi
TAU = math.tau


def make_atlas():
    source = DEST.parents[2] / 'art/originals/camp'
    m=Image.open(source/'surfaces.webp').convert('RGB')
    w,h=m.size
    tiles=[]
    for r in range(2):
     for c in range(3):
      tiles.append(m.crop((c*w//3+5,r*h//2+5,(c+1)*w//3-5,(r+1)*h//2-5)).resize((512,512),Image.Resampling.LANCZOS))
    def tint(tile,low,high):
     return ImageOps.colorize(ImageOps.grayscale(tile),low,high,blackpoint=15,whitepoint=235)
    # An ochre madder key woven into the same flax.
    trim=tiles[0].copy();pattern=Image.new('L',(512,512));d=ImageDraw.Draw(pattern)
    for y in [74,435]:d.line((0,y,511,y),fill=255,width=18)
    for x in range(-64,600,128):
     d.line([(x-1,165),(x+97,165),(x+97,348),(x+31,348),(x+31,222),(x+65,222),(x+65,287)],fill=255,width=17)
     d.line([(x+97,348),(x+128,348),(x+128,165)],fill=255,width=17)
    trim.paste(tint(trim,'#592c21','#a35235'),mask=pattern)
    tiles.extend([trim,Image.open(source/'ceramics.webp').convert('RGB').resize((512,512),Image.Resampling.LANCZOS),
     Image.open(source/'shield.webp').convert('RGB').resize((512,512),Image.Resampling.LANCZOS),
     tint(tiles[0],'#522d2a','#ad6847'),tint(tiles[3],'#241e20','#52433a'),
     tint(tiles[4],'#361d22','#f98330'),tint(tiles[5],'#372f26','#878650'),
     tint(tiles[1],'#2e2320','#916744'),tint(tiles[0],'#492e25','#aa7952'),tint(tiles[0],'#43392f','#918b65')])
    atlas=Image.new('RGB',(2048,2048))
    for i,tile in enumerate(tiles):atlas.paste(tile,(i%4*512,i//4*512))
    atlas.save(DEST/'camp-pigments.jpg',quality=93,subsampling=0)


class Model:
    def __init__(self):
        self.vertices = []

    def face(self, points, tile, uv=None):
        points = np.asarray(points)
        uv = uv if uv is not None else [(0,1),(1,1),(1,0),(0,0)]
        for k in range(1,len(points)-1):
            normal = np.cross(points[k]-points[0],points[k+1]-points[0])
            length = np.linalg.norm(normal)
            if length < 1e-7:
                continue
            for j in (0,k,k+1):
                u,v = uv[j]
                self.vertices.append([*points[j],*(normal/length),
                    (tile%4+.008+.984*u)/4,(tile//4+.008+.984*v)/4])

    def rod(self,a,b,r,tile=WOOD,sides=8,end=None):
        a,b=np.array(a),np.array(b)
        axis=b-a
        axis=axis/np.linalg.norm(axis)
        right=np.cross(axis,[0,0,1] if abs(axis[2])<.85 else [1,0,0])
        right=right/np.linalg.norm(right)
        front=np.cross(right,axis)
        ring=[right*math.cos(TAU*i/sides)+front*math.sin(TAU*i/sides) for i in range(sides)]
        for i,n in enumerate(ring):
            m=ring[(i+1)%sides]
            rr=r if end is None else end
            self.face([a+r*n,b+rr*n,b+rr*m,a+r*m],tile,
                      [(i/sides,1),(i/sides,0),((i+1)/sides,0),((i+1)/sides,1)])
        for center,radius,reverse in [(a,r,False),(b,r if end is None else end,True)]:
            circle=[center+radius*n for n in ring]
            if reverse:circle.reverse()
            self.face(circle,tile,[(.5+.45*math.cos(TAU*i/sides),.5+.45*math.sin(TAU*i/sides)) for i in range(sides)])

    def tube(self,points,r,tile,sides=6):
        for a,b in zip(points,points[1:]):self.rod(a,b,r,tile,sides)

    def body(self, rings, tile, center=(0,0), sides=24, bands=None):
        # Ring order follows the outside up and the inside back down, giving open vessel mouths.
        for j,((y,r),(ny,nr)) in enumerate(zip(rings,rings[1:])):
            mat=(bands or {}).get(j,tile)
            for i in range(sides):
                def point(radius,height,t):
                    return (center[0]+radius*math.sin(t),height,center[1]+radius*math.cos(t))
                a,b=TAU*i/sides,TAU*(i+1)/sides
                self.face([point(r,y,a),point(r,y,b),point(nr,ny,b),point(nr,ny,a)],mat,
                          [(i/sides,1),((i+1)/sides,1),((i+1)/sides,0),(i/sides,0)])

    def box(self,c,dim,tile):
        x,y,z=c; w,h,d=np.array(dim)/2
        for side in [-1,1]:
            self.face([(x-w,y-h,z+side*d),(x+w,y-h,z+side*d),(x+w,y+h,z+side*d),(x-w,y+h,z+side*d)][::side],tile)
            self.face([(x+side*w,y-h,z+d),(x+side*w,y-h,z-d),(x+side*w,y+h,z-d),(x+side*w,y+h,z+d)][::side],tile)
            self.face([(x-w,y+side*h,z+d),(x+w,y+side*h,z+d),(x+w,y+side*h,z-d),(x-w,y+side*h,z-d)][::side],tile)

    def export(self,name,limit):
        data=np.array(self.vertices,dtype='<f4')
        low,high=data[:,:3].min(0),data[:,:3].max(0)
        data[:,:3]-=[(low[0]+high[0])/2,low[1],(low[2]+high[2])/2]
        count=len(data)
        assert count//3<=limit,(name,count//3)
        doc={'asset':{'version':'2.0','generator':'Nemea camp workshop'},'scene':0,
             'scenes':[{'nodes':[0]}],'nodes':[{'name':name,'mesh':0}],
             'meshes':[{'primitives':[{'attributes':{'POSITION':0,'NORMAL':1,'TEXCOORD_0':2},'material':0}]}],
             'images':[{'uri':'camp-pigments.jpg'}],'textures':[{'source':0}],
             'materials':[{'name':'Camp pigment','doubleSided':True,'pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicFactor':0,'roughnessFactor':1}}],
             'buffers':[{'byteLength':data.nbytes}],'bufferViews':[{'buffer':0,'byteLength':data.nbytes,'byteStride':32,'target':34962}],
             'accessors':[{'bufferView':0,'byteOffset':offset,'componentType':5126,'count':count,'type':kind} for offset,kind in [(0,'VEC3'),(12,'VEC3'),(24,'VEC2')]]}
        doc['accessors'][0].update(min=data[:,:3].min(0).tolist(),max=data[:,:3].max(0).tolist())
        meta=json.dumps(doc,separators=(',',':')).encode()
        meta+=b' '*(-len(meta)%4)
        raw=data.tobytes()
        (DEST/(name+'.glb')).write_bytes(struct.pack('<4sII',b'glTF',2,28+len(meta)+len(raw))+struct.pack('<I4s',len(meta),b'JSON')+meta+struct.pack('<I4s',len(raw),b'BIN\0')+raw)
        print(name,count//3,flush=True)


def handle(m,x,y,z,rx,ry,tile=BRONZE,plane='xy',thick=.025):
    path=[]
    for i in range(13):
        a=TAU*i/12
        path.append((x+rx*math.cos(a) if plane=='xy' else x,y+ry*math.sin(a),z if plane=='xy' else z+rx*math.cos(a)))
    m.tube(path,thick,tile,5)


def spear(m,x,z,height,base=0):
    neck=height-.29
    m.rod((x,base,z),(x,neck,z),.028,WOOD,8,.023)
    m.rod((x,neck-.09,z),(x,neck+.025,z),.039,HIDE,8)
    a,b,c,d=(x,neck,z),(x-.066,neck+.10,z),(x,height,z),(x+.066,neck+.10,z)
    for offset in [-.027,.027]:
        ridge=(x,neck+.13,z+offset)
        for v,w in [(a,b),(b,c),(c,d),(d,a)]:m.face([v,w,ridge],BRONZE)


def big_tent():
    m=Model()
    width,depth=1.65,1.69
    for z in (-depth,depth):
        m.rod((0,0,z),(0,2.52,z),.063,TIMBER)
        for x in (-width,width):
            m.rod((x,.02,z),(x,1.18,z),.05,TIMBER)
            peg=(x*1.29,.05,z*1.13)
            m.rod((x,1.18,z),peg,.014,HIDE,5)
            m.rod(peg,(peg[0]-.035,.2,peg[2]),.025,TIMBER,6)
    m.rod((0,2.44,-1.84),(0,2.44,1.84),.067,WOOD)
    for sign in (-1,1):
        def cloth(u,v):
            fold=.048*math.sin(v*PI*6+.45)*math.sin(u*PI)
            return (sign*(width*u+fold),2.46-1.25*u-.12*math.sin(PI*u)-.055*math.sin(v*PI),depth*(2*v-1))
        for i in range(8):
            for j in range(8):
                u,v=i/8,j/8
                coords=[(u,v),(u+.125,v),(u+.125,v+.125),(u,v+.125)]
                m.face([cloth(a,b) for a,b in coords],LINEN,coords)
        # Dyed tablet-woven hems cross the front gable and run down each long eave.
        for i in range(8):
            u=i/8
            coordinates=[(u,.904),(u+.125,.904),(u+.125,.998),(u,.998)]
            m.face([np.array(cloth(a,b))+[0,.009,0] for a,b in coordinates],KEY,
                   [(u,1),(u+.125,1),(u+.125,0),(u,0)])
        for j in range(8):
            v=j/8
            coordinates=[(.86,v),(.97,v),(.97,v+.125),(.86,v+.125)]
            m.face([np.array(cloth(a,b))+[0,.012,0] for a,b in coordinates],KEY,
                   [(j%4/4,0),(j%4/4,1),((j%4+1)/4,1),((j%4+1)/4,0)])
        for j in range(6):
            z1=depth*(2*j/6-1);z2=z1+depth/3
            def panel(z,h):return (sign*(width+.04*(1-h)),h,z)
            m.face([panel(z1,.13),panel(z2,.13),panel(z2,1.24),panel(z1,1.24)],LINEN)
            m.face([(sign*(width+.055),h,z) for z,h in [(z1,.18),(z2,.18),(z2,.39),(z1,.39)]],KEY)
        m.face([(0,2.45,-depth),(sign*width,1.22,-depth),(sign*width,.12,-depth),(0,.12,-depth)],LINEN)
        # Folded entrance wings: two rolled curtains reveal the timber ridge and the interior.
        pts=[(sign*.07,2.42,depth+.015),(sign*width,1.22,depth+.015),(sign*1.58,.12,depth+.04),
             (sign*1.12,.14,depth+.12),(sign*1.18,.95,depth+.19)]
        for i in range(1,len(pts)-1):m.face([pts[0],pts[i],pts[i+1]],LINEN)
        m.rod((sign*1.13,.98,depth+.19),(sign*1.34,1.03,depth+.13),.042,HIDE)
        for v in (.25,.5,.75):
            m.tube([cloth(t,v) for t in (0,.25,.5,.75,1)],.012,HIDE,5)
    return m


def small_tent():
    m=Model()
    for x in (-1.05,1.05):
        for direction in (-1,1):
            m.rod((x,0,.38+direction*.5),(x,1.55,.38-direction*.13),.032,WOOD)
            m.rod((x,1.53,.38-direction*.13),(x,1.68,.38-direction*.17),.048,BRONZE,6,0)
        m.rod((x,1.32,.38),(x,.58,-1.02),.032,TIMBER)
    m.rod((-1.18,1.35,.4),(1.18,1.35,.4),.039,WOOD)
    def panel(u,v):return ((u-.5)*2.6,.59+.82*v-.10*math.sin(v*PI)-.055*math.sin(u*PI),-1.08+1.61*v)
    for i in range(8):
        for j in range(5):
            uv=[(i/8,j/5),((i+1)/8,j/5),((i+1)/8,(j+1)/5),(i/8,(j+1)/5)]
            m.face([panel(u,v) for u,v in uv],LINEN,uv)
    m.face([(-1.26,.04,-1.07),(1.26,.04,-1.07),(1.28,.60,-1.06),(-1.28,.60,-1.06)],LINEN)
    for u in [-1.14,1.14]:
        m.rod((u,0,-1.07),(u,.62,-1.07),.027,TIMBER)
    m.box((0,.067,.23),(1.64,.13,.62),WOOL)
    for x in [-.58,-.51,.54,.61]:
        m.face([(x,.134,-.078),(x+.035,.134,-.078),(x+.035,.134,.539),(x,.134,.539)],RED)
    m.rod((-.81,.22,.02),(-.81,.22,.54),.15,RED,12)
    for x in (-1.27,1.27):
        m.rod((x,1.36,.53),(x*1.16,.05,.91),.014,HIDE,5)
        m.rod((x*1.16,0,.91),(x*1.16,.19,.94),.028,TIMBER)
    return m


def jar(water):
    m=Model()
    if water:
        profile=[(0,.19),(.05,.22),(.09,.17),(.18,.22),(.36,.36),(.54,.40),(.67,.31),(.72,.23),(.77,.15),(.84,.15),(.87,.20),(.91,.19),(.91,.135),(.80,.122),(.72,.085)]
        m.body(profile,CLAY,bands={1:GLAZE,5:FRIEZE,6:GLAZE,9:GLAZE,11:GLAZE,12:GLAZE,13:GLAZE})
        for sign in [-1,1]:
            m.tube([(sign*x,y,z) for x,y,z in [(.35,.45,.09),(.46,.5,.10),(.49,.58,.04),(.48,.59,-.07),(.37,.53,-.10)]],.035,GLAZE,7)
        m.tube([(0,.57,-.34),(0,.64,-.45),(0,.85,-.35),(0,.91,-.25),(0,.86,-.14)],.035,GLAZE,8)
    else:
        m.body([(.12,.025),(.2,.055),(.38,.14),(.56,.26),(.81,.31),(.98,.28),(1.06,.15),(1.11,.112),(1.30,.103),(1.32,.14),(1.36,.142),(1.36,.091),(1.24,.079)],CLAY,bands={8:RED,11:GLAZE})
        for sign in [-1,1]:
            path=[(sign*x,y,0) for x,y in [(.253,.93),(.326,.99),(.32,1.15),(.265,1.26),(.182,1.29),(.105,1.26)]]
            m.tube(path,.038,CLAY,8)
        for i in range(3):
            a=TAU*i/3
            m.rod((.29*math.cos(a),0,.29*math.sin(a)),(.21*math.cos(a),.55,.21*math.sin(a)),.031,TIMBER)
            b=a+TAU/3
            m.rod((.23*math.cos(a),.41,.23*math.sin(a)),(.23*math.cos(b),.41,.23*math.sin(b)),.034,WOOD)
    return m


def vessel(fire):
    m=Model()
    y=.38 if fire else .92
    r=.44 if fire else .40
    m.body([(y-.15,.05),(y-.12,.15),(y-.04,r*.78),(y+.08,r),(y+.12,r+.016),
            (y+.15,r),(y+.14,r-.028),(y+.04,r-.07),(y-.06,.08),(y-.06,0)],BRONZE)
    for i in range(3):
        a=TAU*i/3+.3
        def foot(distance,h):return (math.sin(a)*distance,h,math.cos(a)*distance)
        m.tube([foot(r*1.04,.025),foot(r*.91,.08),foot(r*.72,y*.7),foot(r*.83,y+.02)],.043,BRONZE,7)
        m.rod(foot(r*.9,.035),foot(r*1.10,.035),.047,BRONZE,6)
    for x in [-r,r]:
        handle(m,x,y+.12,0,.077,.095,BRONZE,'yz')
    if fire:
        for i in range(12):
            a=2.4*i;rad=.30*math.sqrt(i/12);h=y+.055+.07*(1-rad/.31)
            m.body([(h-.06,.033),(h,.072),(h+.04,.048),(h+.055,.013)],COAL if i%3 else GLAZE,(rad*math.cos(a),rad*math.sin(a)),7)
    return m


def altar():
    m=Model()
    for y,width,h in [(.07,.97,.14),(.18,.89,.10),(.37,.78,.30),(.56,.91,.09),(.635,1.00,.075)]:
        m.box((0,y,0),(width,h,width*.8),STONE)
    m.body([(.67,.13),(.70,.15),(.74,.219),(.8,.28),(.81,.265),(.75,.205),(.73,0)],STONE)
    m.body([(.75,0),(.76,.18),(.77,.15),(.77,0)],GLAZE,sides=18)
    for k in range(2):
        pts=[(-.15+.05*k,.775,-.035),(.02,.801,.013+k*.04),(.22,.84+k*.05,.062)]
        m.tube(pts,.009,TIMBER,5)
        for j in range(4):
            x=-.08+j*.072; h=.79+.015*j; z=.013+.04*k
            tip=(x+.052,h+.035,z+(.09 if j%2 else -.083))
            m.face([(x,h,z),(x+.015,h+.014,z+.03),tip,(x+.04,h+.009,z)],LEAF)
    return m


def rack():
    m=Model()
    for x in [-.82,.82]:
        m.rod((x,0,-.31),(x,1.29,.02),.064,TIMBER)
        m.rod((x,0,.32),(x,.78,-.06),.048,WOOD)
    for y in [.27,1.1]:
        m.rod((-.94,y,.02),(.94,y,.02),.052,WOOD)
        for x in [-.82,.82]:
            for off in [-.032,0,.032]:
                m.rod((x-.07,y+off,-.025),(x+.068,y+.055+off,.073),.021,HIDE,6)
    for i,h in enumerate([2.13,2.31,2.24,2.07]):spear(m,-.59+i*.39,.09+(i%2)*.035,h)
    return m


def shield():
    m=Model()
    tilt=-.19
    def vertex(x,y,z):
        return (x,.52+y*math.cos(tilt)-z*math.sin(tilt),y*math.sin(tilt)+z*math.cos(tilt))
    for j in range(5):
        for i in range(32):
            corners=[(j,i),(j+1,i),(j+1,i+1),(j,i+1)]
            pts=[];uv=[]
            for radius,angle in corners:
                r=.52*radius/5;a=TAU*angle/32
                x,y=r*math.cos(a),r*math.sin(a)
                pts.append(vertex(x,y,.136*(1-(r/.52)**2)))
                uv.append((.5+.476*x/.52,.5-.476*y/.52))
            m.face(pts,OWL,uv)
            m.face([tuple(np.array(v)-[0,0,.035]) for v in pts[::-1]],TIMBER,uv[::-1])
    rim=[vertex(.515*math.cos(TAU*j/32),.515*math.sin(TAU*j/32),0) for j in range(33)]
    m.tube(rim,.019,BRONZE,6)
    m.tube([vertex(x,y,z) for x,y,z in [(-.15,-.06,.07),(-.14,-.06,-.08),(.13,-.06,-.08),(.15,-.06,.07)]],.033,HIDE)
    return m


def pelt():
    m=Model()
    for x in [-.8,.8]:
        m.rod((x,0,.18),(x,1.89,0),.047,TIMBER)
        m.rod((x,0,-.37),(x,.93,.095),.034,WOOD)
    for y in [.21,1.75]:m.rod((-.89,y,.02),(.89,y,.02),.04,WOOD)
    # Width follows the spread forelegs, flank, haunch and hind legs. A separate tapered tail hangs below.
    widths=[(.27,.57),(.42,.50),(.62,.33),(.86,.31),(1.04,.38),(1.25,.43),(1.45,.66),(1.55,.58),(1.51,.31),(1.66,.18),(1.71,.11)]
    for (y,w),(ny,nw) in zip(widths,widths[1:]):
        for i in range(8):
            pts=[];uv=[]
            for h,width,j in [(y,w,i),(y,w,i+1),(ny,nw,i+1),(ny,nw,i)]:
                t=(j-4)/4
                pts.append((t*width,h+.16*(1-abs(t)) if h<.6 else h,.07+.11*(1-t*t)+.017*math.sin(t*6+h*5)))
                uv.append((.5+t*.48*width/.67,(1.74-h)/1.54))
            m.face(pts,FUR,uv)
    for y,w,ny,nw in [(.65,.105,.31,.086),(.31,.086,.105,.024)]:
        m.face([(-w,y,.198),(w,y,.198),(nw+.04,ny,.212),(-nw+.04,ny,.212)],FUR)
    for x,y,to_x,to_y in [(-.58,1.52,-.8,1.76),(.58,1.52,.8,1.76),(-.55,.29,-.78,.21),(.55,.29,.78,.21),(.11,1.7,.17,1.76),(-.11,1.7,-.17,1.76)]:
        m.rod((x,y,.085),(to_x,to_y,.025),.012,HIDE,5)
    return m


if __name__=='__main__':
    make_atlas()
    for name,model in [('ridge-tent',big_tent()),('lean-to',small_tent()),('amphora',jar(False)),('hydria',jar(True)),
                       ('tripod',vessel(False)),('altar',altar()),('spear-rack',rack()),('aspis',shield()),('wolf-hide',pelt()),('brazier',vessel(True))]:
        model.export(name,5000 if name in ('ridge-tent','lean-to') else 2000)

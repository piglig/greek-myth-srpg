"""Build metre-scale, vertex-painted scenery meshes for the orthographic battle camera."""
from pathlib import Path
from math import sin, cos, pi, sqrt
import json
import random
import struct

OUTPUT = Path(__file__).resolve().parents[2] / 'prototype/art/landmarks'
OUTPUT.mkdir(exist_ok=True)
rng = random.Random(381)
positions, normals, colors, grain_uv = [], [], [], []


def face(points, pigment, finish=None):
    a,b,c = points[:3]
    x,y,z = (b[i]-a[i] for i in range(3))
    u,v,w = (c[i]-a[i] for i in range(3))
    n = (y*w-z*v,z*u-x*w,x*v-y*u)
    length = sqrt(sum(i*i for i in n))
    if length < 1e-7:
        return
    rgb = [int(pigment[i:i+2],16)/255 for i in (0,2,4)]
    wash = rng.uniform(.90,1.05)
    # Keep grain in face space, aligned to the longest edge of each board.
    edge_length = sqrt(x*x+y*y+z*z)
    along = (x/edge_length,y/edge_length,z/edge_length)
    across = ((n[1]*along[2]-n[2]*along[1])/length,(n[2]*along[0]-n[0]*along[2])/length,(n[0]*along[1]-n[1]*along[0])/length)
    for k in range(1,len(points)-1):
        for p in (a,points[k],points[k+1]):
            positions.append(p)
            u,v = [sum((p[i]-a[i])*axis[i] for i in range(3)) for axis in (along,across)]
            if len(points)==4 and edge_length < sqrt(sum((points[-1][i]-a[i])**2 for i in range(3))):
                u,v = v,u
            kind = {None:0,'wood':1,'tile':2,'char':3,'leaf':4,'cloth':5,'falling_leaf':6}[finish]
            grain_uv.append((kind + .25 + u*.3, v))
            normals.append(tuple(i/length for i in n))
            colors.append(tuple(min(1,i**2.2*wash) for i in rgb))


def box(x,y,z,w,h,d,color,tilt=0,roll=0,finish=None):
    pts = []
    for a,b,c in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
                  (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]:
        a,b,c = a*w/2,b*h/2,c*d/2
        b,c = b*cos(tilt)-c*sin(tilt),b*sin(tilt)+c*cos(tilt)
        pts.append((x+a*cos(roll)-b*sin(roll),y+a*sin(roll)+b*cos(roll),z+c))
    for indices in [(3,2,1,0),(4,5,6,7),(0,4,7,3),(2,6,5,1),(7,6,2,3),(0,1,5,4)]:
        face([pts[i] for i in indices],color,finish)


def lump(x,y,z,w,h,d,color, sides=8):
    rings = []
    for level,radius in [(0,.70),(.29,1),(.73,.83),(1,.36)]:
        ring = []
        for i in range(sides):
            theta = 2*pi*(i+.14*level)/sides
            r = radius*rng.uniform(.88,1.10)
            ring.append((x+w*r*cos(theta),y+h*(level+rng.uniform(-.055,.055)),z+d*r*sin(theta)))
        rings.append(ring)
    for lower,upper in zip(rings,rings[1:]):
        for i in range(sides):
            j=(i+1)%sides
            face([lower[i],upper[i],lower[j]],color)
            face([lower[j],upper[i],upper[j]],color)
    face(rings[-1][::-1],color)
    face(rings[0],color)


def save(name):
    arrays = [positions,normals,colors,grain_uv]
    blob = bytearray()
    views,accessors = [],[]
    for arr in arrays:
        dims = len(arr[0])
        data = b''.join(struct.pack(f'<{dims}f',*p) for p in arr)
        views.append(dict(buffer=0,byteOffset=len(blob),byteLength=len(data),target=34962))
        accessors.append(dict(bufferView=len(views)-1,componentType=5126,count=len(arr),type=f'VEC{dims}',
                              min=list(map(min,zip(*arr))),max=list(map(max,zip(*arr)))))
        blob.extend(data)
    doc=dict(asset=dict(version='2.0'),scene=0,scenes=[dict(nodes=[0])],nodes=[dict(mesh=0,name=name)],
             meshes=[dict(primitives=[dict(attributes=dict(POSITION=0,NORMAL=1,COLOR_0=2,TEXCOORD_0=3),material=0)])],
             materials=[dict(pbrMetallicRoughness=dict(metallicFactor=0,roughnessFactor=1))],
             buffers=[dict(byteLength=len(blob))],bufferViews=views,accessors=accessors)
    header=json.dumps(doc,separators=(',',':')).encode()
    header+=b' '*(-len(header)%4)
    (OUTPUT/(name+'.glb')).write_bytes(struct.pack('<4sII',b'glTF',2,28+len(header)+len(blob))+
        struct.pack('<I4s',len(header),b'JSON')+header+struct.pack('<I4s',len(blob),b'BIN\x00')+blob)
    for arr in arrays:
        arr.clear()


stone=['998974','B5A384','827664','AA9375']
wood='594331'


def stone_course(start, end, wall, course, side_wall, ruin):
    # Draw full stones up to each jamb; stagger the bond and chip individual corners.
    base = course * .086
    cursor = start
    colors = ['A59984','B3A68F','B9A992','AFA28C','AA9E89']
    while cursor < end - .002:
        span = rng.uniform(.12,.23) if course else rng.uniform(.18,.27)
        if end-cursor < span+.07:
            span = end-cursor
        left,right = cursor+.0015,cursor+span-.0015
        top = base+rng.uniform(.082,.089)
        cut = rng.uniform(.007,.018)
        profile = [(left+cut,base),(right-cut,base),(right,base+cut),
                   (right,top-cut),(right-cut,top),(left+cut,top),(left,top-cut),(left,base+cut)]
        sign = 1 if wall>0 else -1
        outer = wall+sign*rng.uniform(.034,.046)
        def point(u,y,depth):
            return (depth,y,u) if side_wall else (u,y,depth)
        front = [point(u,y,outer) for u,y in profile]
        back = [point(u,y,wall-sign*.035) for u,y in profile]
        if (sign<0) != side_wall:
            front.reverse()
            back.reverse()
        color = rng.choice(colors if not ruin or course<3 else ['887A69','958677','9E907C'])
        face(front,color)
        face(back[::-1],color)
        for k in range(len(front)):
            j = (k+1)%len(front)
            face([front[j],front[k],back[k],back[j]],color)
        cursor += span


def roof_tile(x,z,side,ruin):
    # Wide pan and convex cover; the end profile remains visible at the eaves.
    pitch = .61
    width = .083
    depth = .099
    color = rng.choice(['9D5E42','AC6C4D','A46146','B27451'] if not ruin else ['694C40','845840','78564A'])
    lip = rng.uniform(.002,.006)
    def vertex(u,v,rise):
        return (x+u,.674-(z+v)*pitch+rise+lip,side*(z+v))
    edges = [-.51,-.40,-.27,.27,.40,.51]
    heights = [.014,.006,0,0,.006,.014]
    for j in range(5):
        u0,u1 = width*edges[j],width*edges[j+1]
        h0,h1 = heights[j:j+2]
        strip=[vertex(u0,0,h0),vertex(u0,depth,h0+.007),vertex(u1,depth,h1+.007),vertex(u1,0,h1)]
        face(strip[::side],color,'tile')
        end=[strip[1],(strip[1][0],strip[1][1]-.009,strip[1][2]),
             (strip[2][0],strip[2][1]-.009,strip[2][2]),strip[2]]
        face(end[::side],'794D38','tile')
    for j in range(4):
        a,b=j*pi/4,(j+1)*pi/4
        curve=[vertex(width*.5+.013*cos(t),v,.012+.015*sin(t)) for t,v in [(a,0),(b,0),(b,depth),(a,depth)]]
        face(curve[::side],color,'tile')


def vessel(x,y,z,r,h):
    profile=[(.0,.53),(.09,.66),(.32,.98),(.61,1),(.79,.77),(.89,.48),(.96,.48),(1,.57)]
    for j,((lo,r0),(hi,r1)) in enumerate(zip(profile,profile[1:])):
        for k in range(12):
            a,b=k*pi/6,(k+1)*pi/6
            quad=[(x+r*rad*cos(t),y+h*level,z+r*rad*sin(t))
                  for t,level,rad in [(a,lo,r0),(a,hi,r1),(b,hi,r1),(b,lo,r0)]]
            face(quad,'A3694F' if j!=5 else '62483D')
    face([(x+.51*r*cos(k*pi/6),y+h*.987,z+.51*r*sin(k*pi/6)) for k in reversed(range(12))],'453B32')


def wall_finish(ruin):
    # Broken lime render leaves the lower rubble courses and fractured margins exposed.
    for side in (-1,1):
        spans=[(-.48,-.235),(.095,.47)] if side==1 else ([(-.16,.27)] if ruin else [(-.48,.47)])
        for start,end in spans:
            if ruin:
                end=start+(end-start)*.66
            n=max(2,round((end-start)/.055))
            crest=.32 if ruin else .425
            bottoms=[.13+rng.uniform(-.036,.043)+(.04 if ruin else 0) for k in range(n+1)]
            for j in range(n):
                a,b=start+(end-start)*j/n,start+(end-start)*(j+1)/n
                quad=[(a,bottoms[j],side*.339),(b,bottoms[j+1],side*.339),
                      (b,crest,side*.339),(a,crest,side*.339)]
                face(quad[::side],'96836E' if ruin else 'CEBDA0')
    if not ruin:
        for side in (-1,1):
            for x in (-.35,.22):
                box(x,.291,side*.342,.15,.077,.009,'986C50')
                box(x,.285,side*.349,.113,.058,.010,'645546')
                for dx in (-.043,0,.043):
                    box(x+dx,.285,side*.357,.011,.059,.012,'937656',finish='wood')
        for x in (-.213,.079):
            box(x,.17,.319,.024,.34,.04,'6F5744',finish='wood')
        for j in range(6):
            box(-.174+.042*j,.145,.294,.039,.288,.025,'8A6D4E',finish='wood')
        for y in (.069,.235):
            box(-.07,y,.312,.252,.022,.017,'66533E',finish='wood')
        vessel(.282,0,.41,.080,.19)
        vessel(.413,0,.385,.044,.111)
        # The kiln sits inside the uphill gable; its flue rises above the ridge.
        for k in range(4):
            box(.316,.52+k*.08,-.105,.14-k*.009,.081,.14-k*.009,
                ['A0866B','A99174','AA9176','897663'][k])
        box(.316,.823,-.105,.135,.039,.135,'B39C80')
        box(.316,.844,-.105,.084,.006,.084,'473E35')
        for side in (-1,1):
            # Broad gable wash, hand-broken against a darker stone base.
            ys=[.15,.18,.135,.163,.122,.165]
            for j in range(5):
                z0=-.245+j*.098
                pts=[(side*.505,ys[j],z0),(side*.505,.419,z0),
                     (side*.505,.419,z0+.098),(side*.505,ys[j+1],z0+.098)]
                face(pts[::side],'C7B599')
            for z in (-.155,.167):
                box(side*.510,.302,z,.011,.099,.107,'927C61')
                box(side*.517,.305,z,.010,.076,.088,'52483B')
                for slat in range(3):
                    box(side*.524,.303,z+(slat-1)*.031,.013,.069,.018,'93785D',finish='wood')
        # A faded woven shade with scalloped, uneven fringes along its lower edge.
        for i in range(15):
            x=(i-7)*.055
            drop=.021+.007*cos(i*.8)
            tint='9C715A' if i in (2,3,11,12) else 'BEAB87'
            for j in range(3):
                z0=.309+.087*j
                def awning(z):
                    v=(z-.309)/.261
                    return .454-.072*v-.019*sin(v*pi)+.003*cos(i)
                pts=[(x-.0275,awning(z0),z0),(x-.0275,awning(z0+.088),z0+.088),
                     (x+.0275,awning(z0+.088),z0+.088),(x+.0275,awning(z0),z0)]
                face(pts,tint,"cloth")
                face(pts[::-1],tint,"cloth")
            face([(x-.0275,.382,.571),(x-.026,.382-drop,.575),
                  (x+.026,.382-drop*.85,.575),(x+.0275,.382,.571)],tint,"cloth")
        # A potter's drying shelf and a shallow bowl beneath the awning.
        box(.27,.158,.48,.27,.027,.12,'856647',finish='wood')
        for x in (.164,.373):
            box(x,.075,.48,.024,.15,.077,'735E45',finish='wood')
        vessel(.27,.172,.48,.048,.044)
    else:
        for x in (-.37,-.15,.26):
            box(x,.066,.07,.26,.053,.043,'4C4036',roll=x*.7,finish='char')
        for j in range(8):
            lump(.22+rng.uniform(-.12,.12),.006,rng.uniform(-.11,.18),.032,.023,.041,'895D48',5)


def house(ruin):
    for course in range(5):
        for side in (-1,1):
            spans = [(-.49,.49)]
            if side==1 and course<4:
                spans = [(-.49,-.21),(.07,.49)]
            if ruin and side==1 and course>=3:
                spans = [(-.49,-.21),(.07,.28)] if course==3 else [(-.49,-.04)]
            if ruin and side==-1 and course>=2:
                spans = [(-.49,-.36+.025*(4-course)),(-.17+.048*(course-2),.49-.09*(course-2))]
            for start,end in spans:
                stone_course(start,end,side*.292,course,False,ruin)
            if ruin and side==1 and course>=2:
                stone_course(-.26,.16-(course-2)*.13,side*.457,course,True,ruin)
            else:
                stone_course(-.26,.26,side*.457,course,True,ruin)
    for side in (-1,1):
        for i in range(8):
            x=(i-3.5)*.125
            if not ruin or i<6 or side==-1:
                length = .41 if not ruin or i<5 else .25+.04*(i%2)
                box(x,.526,side*.16,.035,.034,length,wood,side*.55,finish="char" if ruin else "wood")
        for i in range(12):
            for j in range(4):
                if ruin and (i>7+(j%2) or (i+2*j)%7==0):
                    continue
                roof_tile((i-5.5)*.083,j*.087,side,ruin)
    wall_finish(ruin)
    # Ridge caps catch the light and chipped eaves show the thickness of the roof.
    for i in range(8 if ruin else 11):
        box((i-5)*.094,.66,0,.092,.040,.067,'915B42' if not ruin else wood)
    for x in (-.34,.28):
        for k in range(3):
            lump(x+.027*k,-.006,.38+.026*k,.061,.049,.046,rng.choice(stone),6)
    if ruin:
        box(.32,.19,.27,.046,.47,.052,'49382F',roll=.49,finish='char')
        box(.24,.058,.36,.42,.074,.08,'544034',roll=.15,finish='char')
    else:
        for side in (-1,1):
            face([(side*.458,.422,-.28),(side*.458,.635,0),(side*.458,.422,.28)][::side],'AE9979')
    box(-.07,.346,.342,.32,.052,.09,wood,finish="wood")
    if not ruin:
        for x in (-.38,.38):
            box(x,.17,.53,.036,.34,.036,wood,finish="wood")
        box(0,.361,.532,.824,.023,.027,'725C47',finish='wood')
    save('ruin' if ruin else 'workshop')


house(True)
house(False)
# A stepped ashlar gate with a double timber lintel.
for side in (-1,1):
    for course in range(6):
        stone_course(-.13,.13,side*.40,course,True,False)
        box(side*.40,.044+course*.086,0,.16,.083,.26,'AF9F88')
    box(side*.40,.56,0,.23,.066,.31,'CAB798')
for z in (-.10,.10):
    box(0,.632,z,1.07,.092,.085,'77634B',finish='wood')
save('gate')
for x,y,z,w,h,d in [(-.08,-.10,0,.4,.7,.32),(.19,-.08,-.05,.24,.48,.26),(-.27,-.05,.14,.16,.29,.16)]:
    lump(x,y,z,w,h,d,'A49780',7)
save('boulder')
for side in (-1,1):
    for tier in range(3):
        lump(side*(.38-.047*tier),tier*.17-.08,-.04,.19,.28,.38-.038*tier,'988973',7)
lump(.02,.44,-.1,.38,.29,.30,'A99A83',7)
box(0,.23,-.29,.57,.56,.04,'42382E')
save('cave')
for i in range(6):
    box(.08*cos(i),.033+i*.018,.17*sin(i),.32+i*.023,.045,.065,'5B493B',roll=.19*sin(i),finish='char')
save('debris')
for i in range(5):
    box((i-2)*.084,.20,0,.081,.046,.51,'A38663',finish='wood')
for side in (-1,1):
    for rail in range(2):
        box(side*.21,.25+rail*.076,0,.025,.046,.56,'806647',finish='wood')
    for z in (-.21,.20):
        box(side*.21,.29,z,.037,.23,.031,'715C45',finish='wood')
    box(side*.17,.18,.45,.034,.04,.52,'8E7053',.13,finish='wood')
    for k in range(14):
        a=k*2*pi/14
        box(side*.265,.172+.15*cos(a),.15*sin(a),.044,.026,.076,'665744',a)
    for k in range(4):
        box(side*.265,.172,0,.028,.021,.3,'9B8160',k*pi/4)
save('cart')


def branch(start,end,r0,r1,color):
    dx,dy,dz = [b-a for a,b in zip(start,end)]
    length = sqrt(dx*dx+dy*dy+dz*dz)
    horizontal = sqrt(dx*dx+dz*dz)
    across = (dz/horizontal,0,-dx/horizontal) if horizontal else (1,0,0)
    normal = (dy*across[2]/length,(dz*across[0]-dx*across[2])/length,-dy*across[0]/length)
    rings = []
    for center,radius in [(start,r0),(end,r1)]:
        rings.append([tuple(center[k]+radius*(cos(a*pi/3)*across[k]+sin(a*pi/3)*normal[k])
                            for k in range(3)) for a in range(6)])
    for a in range(6):
        b = (a+1)%6
        face([rings[0][a],rings[0][b],rings[1][b],rings[1][a]],color,'wood')


def foliage(center,radii,palette,leaves=27):
    # Each spray is a layered fan of bent leaf clusters around a single twig.
    # A few of them break the outline of the rounded masses built by canopy().
    x,y,z = center
    w,h,d = radii
    twist = rng.uniform(0,2*pi)
    for i in range(leaves):
        phase = twist+i*2.4
        radius = sqrt((i+.5)/leaves)
        dx,dz = cos(phase),sin(phase)
        cx = x+w*radius*dx*.86
        cz = z+d*radius*dz*.86
        cy = y+h*(.65-.41*radius+rng.uniform(-.16,.18))
        tilt = phase+rng.uniform(-.72,.72)
        u,v = cos(tilt),sin(tilt)
        length = rng.uniform(.43,.72)
        breadth = rng.uniform(.19,.35)
        root = (cx-w*u*.24,cy-h*.24,cz-d*v*.24)
        tip = (cx+w*u*length,cy+h*rng.uniform(.14,.38),cz+d*v*length)
        ridge = (cx+w*u*.13,cy+h*.16,cz+d*v*.13)
        left = (cx-w*v*breadth,cy+h*.05,cz+d*u*breadth)
        right = (cx+w*v*breadth,cy+h*.04,cz-d*u*breadth)
        tone = palette[1] if i%5==0 else palette[0]
        for pts in ([root,left,ridge],[left,tip,ridge],[tip,right,ridge],[right,root,ridge]):
            face(pts,tone,"leaf")
            face(pts[::-1],palette[0],"leaf")


def canopy(center,radii,palette,sides=10,crown=None):
    # A rounded mass of leaves; the shader paints leaf strokes on it and frays its outline.
    # Normals lean toward the whole crown (centre, radii) so a tree is lit as one soft form
    # with its clumps showing inside it, instead of as a bunch of separate balls.
    x,y,z = center
    w,h,d = radii
    dark,light = [[(int(c[i:i+2],16)/255)**2.2 for i in (0,2,4)] for c in palette]
    lobes = [(rng.uniform(0,2*pi),rng.uniform(.06,.15)) for _ in range(3)]
    levels = [-1,-.72,-.32,.10,.50,.82,1]
    grid = []
    for level in levels:
        ring = []
        for i in range(sides):
            theta = 2*pi*(i+.5*(len(grid)%2))/sides
            girth = sqrt(max(0,1-level*level))
            swell = 1+sum(a*cos(theta*(k+2)+p+level*1.7) for k,(p,a) in enumerate(lobes))
            r = girth*swell*rng.uniform(.93,1.07)
            ring.append((x+w*r*cos(theta),y+h*level*rng.uniform(.95,1.05),z+d*r*sin(theta)))
        grid.append(ring)

    def emit(points):
        wash = rng.uniform(.93,1.06)
        for p in points:
            away = [(p[0]-x)/w,(p[1]-y)/h,(p[2]-z)/d]
            length = sqrt(sum(i*i for i in away)) or 1
            away = [i/length for i in away]
            if crown:
                (ox,oy,oz),(ow,oh,od) = crown
                whole = [(p[0]-ox)/ow,(p[1]-oy)/oh,(p[2]-oz)/od]
                span = sqrt(sum(i*i for i in whole)) or 1
                away = [.42*away[k]+.58*whole[k]/span for k in range(3)]
                length = sqrt(sum(i*i for i in away)) or 1
                away = [i/length for i in away]
            # Painted light: the underside stays in the dark pigment, the crown takes the light one.
            lift = min(1,max(0,.5+.62*away[1]))
            positions.append(p)
            normals.append(tuple(away))
            colors.append(tuple(min(1,(dark[k]*.78+(light[k]-dark[k]*.78)*lift*lift)*wash) for k in range(3)))
            grain_uv.append((7.25+.3*(.5+.5*away[0]),.5+.5*away[1]))

    for lower,upper in zip(grid,grid[1:]):
        for i in range(sides):
            j = (i+1)%sides
            emit([lower[i],upper[i],lower[j]])
            emit([lower[j],upper[i],upper[j]])


OLIVE_CROWN = ((0,.50,0),(.52,.34,.48))
fork = (-.045,.32,.01)
branch((0,-.025,0),fork,.072,.054,'675E4C')
for i in range(5):
    angle = i*2*pi/5+.2
    end = (.31*cos(angle),.46+.045*(i%3),.28*sin(angle))
    elbow = (end[0]*.62,.37+.034*(i%2),end[2]*.58)
    branch(fork,elbow,.046,.034,'706651')
    branch(elbow,end,.035,.018,'817760')
    tones = rng.choice([('46563C','8C9A68'),('4C5C42','96A272'),('425238','828F5E')])
    canopy((end[0]*1.06,end[1]+.075,end[2]*1.06),(.178,.118,.168),tones,crown=OLIVE_CROWN)
    a = angle+.9
    canopy((end[0]*.80+.09*cos(a),end[1]+.15+.02*(i%2),end[2]*.80+.09*sin(a)),(.132,.094,.126),tones,crown=OLIVE_CROWN)
    foliage((end[0]*1.34,end[1]+.02,end[2]*1.34),(.10,.12,.10),(tones[0],tones[1]),6)
canopy((-.03,.70,.03),(.215,.128,.20),('4C5C42','9CA878'),crown=OLIVE_CROWN)
# One folded, loose olive leaf. The shader carries it from this branch to the ground.
drifting = [(0.27,.57,.10),(.307,.588,.085),(.361,.578,.097),(.30,.567,.113)]
for tri in ([drifting[0],drifting[1],drifting[2]],[drifting[0],drifting[2],drifting[3]]):
    face(tri,'A99C69','falling_leaf')
    face(tri[::-1],'91885E','falling_leaf')
save('olive')
branch((0,-.02,0),(.012,.30,0),.051,.040,'695F49')
for i in range(6):
    t = i/5
    radius = .168*(1-t)**.72+.035
    lean = .016*sin(i*1.9)
    canopy((lean,.26+t*.60,.014*cos(i*2.3)),(radius,.135-.03*t,radius*.94),('2F3F30','5F7150'),9,crown=((0,.52,0),(.20,.52,.19)))
canopy((.012,.985,-.006),(.04,.085,.04),('354636','677957'),7)
foliage((.0,.24,.0),(.17,.10,.16),('43523D','6B7A58'),7)
save('cypress')

for i in range(5):
    a = i*2.4
    canopy((.15*cos(a),.085+.02*(i%2),.12*sin(a)),(.125,.082,.112),('454A34','737452'),8,crown=((0,.0,0),(.30,.19,.26)))
    foliage((.20*cos(a),.03,.16*sin(a)),(.10,.14,.09),('72714D','999362'),5)
save('scrub')

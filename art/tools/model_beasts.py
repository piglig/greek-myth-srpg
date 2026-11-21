"""Build the mountain wolf and boar from their chapter-one painted coats."""
from pathlib import Path
import math
import random
import numpy as np
from PIL import Image
import cv2
from skinned_glb import write_skin

ROOT=Path(__file__).resolve().parents[2]/"prototype/art/original"


def build(kind):
    wolf=kind=="wolf"
    rng=random.Random(93 if wolf else 117)
    coat="837766" if wolf else "805338"
    dark="514c48" if wolf else "503628"
    pale="b69d7e" if wolf else "94694b"
    nodes,origins,names=[],[],{}
    pos,nrm,colors,uv,joints,weights=[],[],[],[],[],[]
    original=Image.open(ROOT.parents[2]/"art/originals/beasts.png").convert("RGBA")
    size=original.width//3
    top=0 if wolf else 2*size
    frame=np.asarray(original.crop((0,top,size,top+size)))
    # Extend edge pigments so filtering across a UV island never samples transparency.
    outside=(frame[:,:,3]<128).astype(np.uint8)
    _,labels=cv2.distanceTransformWithLabels(outside,cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
    atlas=frame[:,:,:3].copy()
    atlas[outside==1]=atlas[outside==0][labels[outside==1]-1]
    if not wolf:
        # The tusks have their own geometry. Fill their painted silhouettes
        # with adjacent cheek fur to keep the hide continuous when the jaw opens.
        fur_mask=np.zeros(outside.shape,np.uint8)
        for polygon in [[(91,259),(101,250),(107,229),(114,235),(119,251),(115,265),(103,276),(89,274)],
                        [(29,234),(35,219),(45,214),(47,229),(46,241),(54,251),(50,264),(35,256)]]:
            cv2.fillPoly(fur_mask,[np.array(polygon,np.int32)],255)
        feather=cv2.GaussianBlur(cv2.dilate(fur_mask,np.ones((3,3),np.uint8)),(7,7),1.4)[:,:,None]/255.
        cheek=np.roll(atlas,(25,-30),axis=(0,1))
        atlas=np.uint8(atlas*(1-feather)+cheek*feather)
    Image.fromarray(atlas).save(ROOT/(kind+"_coat.png"))

    # Each section follows landmarks in the approved painting from rump to nose.
    # Columns are longitudinal position, midline pixel, side offset and vertical scale.
    torso_map=([(-.57,243,117,26,39),(-.32,215,124,38,52),(-.1,188,143,34,44),
                (.12,163,151,42,56),(.32,139,164,47,62),(.55,112,176,36,44)] if wolf else
               [(-.65,280,109,26,47),(-.38,249,115,55,59),(-.04,209,119,66,72),
                (.2,176,128,74,85),(.4,147,141,68,76),(.57,121,158,51,62)])
    face_map=([(.45,117,184,35,33),(.55,102,196,40,42),(.66,91,214,35,32),
               (.73,85,230,25,21),(.82,78,246,16,13),(.92,72,263,11,9)] if wolf else
              [(.41,132,169,49,42),(.54,109,183,54,52),(.66,93,205,48,41),
               (.78,79,230,36,29),(.88,69,252,25,18),(.98,63,271,17,12)])
    def sample(table,z):
        i=next((i for i in range(1,len(table)) if table[i][0]>=z),len(table)-1)
        a,b=table[i-1],table[i]
        f=max(0,min(1,(z-a[0])/(b[0]-a[0])))
        return [x+(y-x)*f for x,y in zip(a[1:],b[1:])]

    def pigment_uv(point,bone):
        x,y,z=point
        if bone.startswith(("Upper","Lower","Paw")):
            fore=bone[-2]=="F"
            hip,sole=((175,165),(164,328)) if wolf and fore else ((259,136),(275,252)) if wolf else (
                      ((210,165),(192,310)) if fore else ((289,140),(287,250)))
            f=min(1,max(0,(.76-y)/.74))
            px=hip[0]+(sole[0]-hip[0])*f-(z-(.306 if fore else -.36))*85
            py=hip[1]+(sole[1]-hip[1])*f
            # The shoulder and thigh emerge through the same pigment field as the ribcage.
            merge=min(1,max(0,(y-.42)/.21))
            if merge:
                tx,ty=pigment_uv(point,"Body")
                px+=merge*(tx*size-px)
                py+=merge*(ty*size-py)
        elif bone.startswith("Tail"):
            f=min(1,max(0,(-z-.49)/.48))
            px,py=(278+33*f,109+82*f) if wolf else (282+22*f,100+37*f)
        else:
            facial=bone in ("Head","Jaw")
            px,py,dx,dy=sample(face_map if facial else torso_map,z)
            cy,w,h=sample(head if facial else rows,z)
            # Mirrored cheeks share the visible, better lit side of the drawing.
            lateral=min(1.15,abs(x)/w)
            height=max(-1.18,min(1.18,(y-cy)/h))
            px+=dx*lateral-height*dx*.13
            py+=dy*(lateral*.30-height*.78)
        if wolf and bone.endswith(("FL","FR")) and y<.15:
            forward=z-.365
            side=x-math.copysign(.139,x)
            sole_x=167+side*180-forward*67
            sole_y=320+forward*119-(y-.04)*141
            f=max(0,min(1,(.15-y)/.08))
            px+=f*(sole_x-px)
            py+=f*(sole_y-py)
        return [px/size,py/size]

    def joint(name,parent,point):
        i=len(nodes)
        p=np.array(point,float)
        offset=p-origins[names[parent]] if parent else p
        nodes.append(dict(name=name,translation=offset.tolist()))
        if parent: nodes[names[parent]].setdefault("children",[]).append(i)
        names[name]=i
        origins.append(p)
        return name

    mapping=pigment_uv

    def triangle(vertices,skin,pigment,paint,shading=None):
        v=np.array(vertices)
        normal=np.cross(v[1]-v[0],v[2]-v[0])
        if np.linalg.norm(normal)<1e-7: return
        normal/=np.linalg.norm(normal)
        tint=rng.uniform(.985,1.015)
        for index,point in enumerate(v):
            first,second,w=skin(point) if callable(skin) else (skin,skin,0)
            pos.append(point); nrm.append(normal if shading is None else shading[index])
            joints.append([names[first],names[second],0,0]); weights.append([1-w,w,0,0])
            colors.append([*((int(pigment[i:i+2],16)/255)**2.2*tint for i in (0,2,4)),paint])
            uv.append(mapping(point,first))

    def surface(rings,skin,pigment,paint=.62):
        rings=np.asarray(rings)
        tangent=np.roll(rings,-1,axis=1)-np.roll(rings,1,axis=1)
        normals=np.cross(tangent,np.gradient(rings,axis=0))
        normals/=np.maximum(np.linalg.norm(normals,axis=2,keepdims=True),1e-9)
        for k,(a,b) in enumerate(zip(rings,rings[1:])):
            for i in range(len(a)):
                j=(i+1)%len(a)
                triangle([a[i],a[j],b[j]],skin,pigment,paint,[normals[k,i],normals[k,j],normals[k+1,j]])
                triangle([a[i],b[j],b[i]],skin,pigment,paint,[normals[k,i],normals[k+1,j],normals[k+1,i]])
        for ring in [rings[0][::-1],rings[-1]]:
            for i in range(1,len(ring)-1): triangle([ring[0],ring[i],ring[i+1]],skin,pigment,paint)

    def body(rows,skin,pigment,paint=.68,count=32):
        rings=[]
        # Interpolate the control sections with a cubic Hermite curve.
        control=np.array(rows)
        axis=control[:,0]
        slopes=np.gradient(control[:,1:],axis,axis=0)
        sections=[]
        for i,span in enumerate(np.diff(axis)):
            a,b=control[i,1:],control[i+1,1:]
            for t in (0,.25,.5,.75):
                shape=(2*t**3-3*t*t+1)*a+(t**3-2*t*t+t)*span*slopes[i]
                shape+=(-2*t**3+3*t*t)*b+(t**3-t*t)*span*slopes[i+1]
                sections.append((axis[i]+span*t,*shape))
        for z,y,w,h in [*sections,rows[-1]]:
            rings.append([(w*math.cos(t),y+h*math.sin(t),z) for t in angles(count)])
        surface(rings,skin,pigment,paint)

    def tube(points,radii,skin,pigment,paint=.48,count=16):
        pts=np.array(points);rings=[]
        for i,(w,h) in enumerate(radii):
            axis=pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]
            axis/=np.linalg.norm(axis)
            right=np.cross([0.,1.,0.] if abs(axis[0])>.85 else [1.,0.,0.],axis)
            right/=np.linalg.norm(right)
            across=np.cross(right,axis)
            rings.append([pts[i]+across*w*math.cos(t)+right*h*math.sin(t) for t in angles(count)])
        surface(rings,skin,pigment,paint)

    def pebble(center,rad,skin,pigment,paint=0.):
        x,y,z=center;w,h,d=rad
        rings=[[(x+w*r*math.cos(t),y+h*r*math.sin(t),z+d*k) for t in angles(10)]
               for k,r in [(-1,.08),(-.64,.78),(0,1),(.65,.76),(1,.08)]]
        surface(rings,skin,pigment,paint)

    joint("Body",None,(0,.65,0))
    joint("Chest","Body",(0,.70,.12))
    joint("Neck","Chest",(0,.77,.36))
    joint("Head","Neck",(0,.83,.54))
    joint("Jaw","Head",(0,.78,.60))
    joint("Tail","Body",(0,.74,-.49))
    joint("TailTip","Tail",(0,.55,-.75) if wolf else (.02,.70,-.70))
    def spine(p):
        z=p[2]
        if z>.32: return ("Chest","Neck",np.clip((z-.32)/.25,0,1))
        return ("Body","Chest",np.clip((z+.18)/.48,0,1))
    rows=[(-.57,.69,.105,.13),(-.48,.72,.177,.218),(-.32,.74,.205,.23),(-.10,.763,.157,.162),
          (.09,.74,.185,.222),(.28,.74,.212,.285),(.42,.77,.182,.240),(.55,.83,.132,.158)] if wolf else [
          (-.65,.64,.115,.20),(-.53,.67,.264,.30),(-.30,.70,.308,.359),(-.03,.735,.335,.40),
          (.19,.78,.326,.446),(.36,.74,.295,.37),(.50,.74,.21,.27),(.57,.76,.16,.195)]
    body(rows,spine,coat,.99)
    head=[(.45,.84,.111,.124),(.55,.88,.152,.163),(.66,.884,.148,.13),(.73,.853,.108,.093),
          (.82,.831,.077,.061),(.91,.823,.054,.042)] if wolf else [
          (.41,.755,.176,.175),(.54,.781,.214,.213),(.66,.75,.190,.174),
          (.78,.69,.134,.116),(.88,.655,.098,.082),(.97,.655,.082,.069)]
    if wolf:
        body(head,"Head",coat,.99)
        # Long cheek guard hairs overlap in the direction of the neck.
        for side in (-1,1):
            for j in range(5):
                z=.64-.030*j
                tube([(side*.114,.87,z),(side*(.145+.003*j),.839,z-.029),
                      (side*(.159+.004*j),.803-.006*j,z-.068)],
                     [(.030,.047),(.024,.037),(.002,.002)],"Head",pale,.98)

    nose_y=.823 if wolf else .66
    if wolf:
        pebble((0,nose_y,.92),(.052,.036,.037),"Head","302a28")
        jaw_y=nose_y-.052
        body([(.63,jaw_y,.084,.043),(.76,jaw_y-.005,.070,.031),(.89,jaw_y+.005,.040,.022)],"Jaw",pale,.25)
    else:
        # Widen the lower cheek into a jowl, narrowing again under the mobile snout.
        body([(.59,.664,.111,.083),(.68,.637,.143,.093),(.76,.613,.150,.085),
              (.835,.604,.136,.068),(.887,.603,.101,.049),(.944,.613,.068,.029),
              (.969,.618,.041,.015)],"Jaw",coat,.97)
        # One continuous set of rings from the poll to the nostrils. The
        # painted fur changes into bare skin across the bridge of the nose.
        def snout_uv(point,bone):
            x,y,z=point
            cheek=np.asarray(pigment_uv(point,bone))
            nose=np.array([63+x*178+(y-.654)*52,280+x*28-(y-.654)*121])/size
            t=np.clip((z-.855)/.143,0,1)
            return cheek+(nose-cheek)*t*t*(3-2*t)
        mapping=snout_uv
        profile=head[:5]+[(.918,.654,.093,.072),(.955,.654,.090,.065),
                          (.976,.654,.091,.061),(.991,.654,.089,.057),
                          (1.001,.654,.080,.050),(1.009,.654,.062,.039),
                          (1.014,.654,.040,.026),(1.017,.654,.020,.013),(1.018,.654,.001,.001)]
        muzzle=[]
        for i,(z,cy,w,h) in enumerate(profile):
            ring=[]
            for t in angles(48):
                x=w*math.cos(t)
                y=cy+h*math.sin(t)
                tip=np.clip((z-.95)/.05,0,1)
                dip=.014*math.exp(-((abs(x)-.046)/.019)**2-((y-.656)/.014)**2)
                ring.append((x,y,z+tip*(.10*(y-.654)-dip)))
            muzzle.append(ring)
        surface(muzzle,"Head",coat,.99)
        mapping=pigment_uv
    for sign in [-1,1]:
        # A cupped pinna tapers from a broad folded base to a rounded tip.
        base_y=.973 if wolf else .89
        base_z=.552 if wolf else .51
        height=.188 if wolf else .156
        outlines=[]
        for t,width in [(0,.052),(.18,.066),(.42,.058),(.70,.039),(.90,.018),(1,.003)]:
            ring=[]
            for angle in angles(24):
                u=width*math.cos(angle)
                x=sign*((.103 if wolf else .155)+(.055 if wolf else .104)*t+u)
                y=base_y+height*t
                z=base_z-.058*t+.031*math.sin(angle)*(1-.67*t)+.23*u
                ring.append((x,y,z))
            outlines.append(ring)
        def ear_uv(point,bone):
            x,y,z=point
            t=np.clip((y-base_y)/height,0,1)
            off=sign*x-(.103 if wolf else .155)-(.055 if wolf else .104)*t
            px=(121-2*t if wolf else 132+15*t)+off*(180 if wolf else 195)
            py=(196-36*t if wolf else 179-42*t)
            return [px/size,py/size]
        mapping=ear_uv
        surface(outlines,"Head",dark,.99)
        mapping=pigment_uv
        if not wolf:
            # The deep end of the canine sits inside the mandibular lip.
            # Tooth and socket move together while the upper muzzle lifts clear.
            def lip_uv(point,bone):
                x,y,z=point
                return [(137-(z-.748)*195+abs(x)*27)/size,
                        (233+(z-.748)*87-(y-.620)*124)/size]
            mapping=lip_uv
            tube([(sign*.111,.640,.748),(sign*.128,.620,.785),(sign*.137,.605,.815),
                  (sign*.135,.602,.838),(sign*.113,.605,.866),(sign*.079,.615,.903)],
                 [(.044,.060),(.048,.052),(.045,.046),(.040,.042),(.031,.031),(.014,.018)],
                 "Jaw","76513e",.92,24)
            mapping=pigment_uv
            ivory=[]
            for t in np.linspace(0,1,26):
                theta=t*1.94
                x=.111+.089*math.sin(theta)
                y=.597+.094*(1-math.cos(theta))
                z=.806+.045*math.sin(math.pi*t)-.018*t
                radius=.034*(1-t)**.78+.00065
                axis=np.array((sign*.089*1.94*math.cos(theta),.094*1.94*math.sin(theta),
                               .045*math.pi*math.cos(math.pi*t)-.018))
                axis/=np.linalg.norm(axis)
                u=np.cross([0.,0.,1.],axis)
                u/=np.linalg.norm(u)
                v=np.cross(axis,u)
                center=np.array((sign*x,y,z))
                ivory.append([center+radius*(.88*u*math.cos(a)+v*math.sin(a)) for a in angles(24)])
            surface(ivory,"Jaw","cbb78d",0)
    # The boar has a raised brush of coarse bristles along its shoulders.
    if not wolf:
        for i in range(125):
            z=rng.uniform(-.43,.42)
            y,w,h=sample(rows,z)
            x=rng.uniform(-.115,.115)
            crest=y+h*math.sqrt(1-(x/w)**2)
            length=.015+.032*math.exp(-((z-.19)/.22)**2)
            tube([(x,crest-.019,z),(x,crest+.009,z-.014),
                  (x*1.04,crest+length*rng.uniform(.55,1.12),z-.043)],
                 [(.010,.016),(.005,.011),(.001,.001)],spine,dark,.92,6)

    def tail_weights(p):
        if wolf:
            return "Tail","TailTip",float(np.clip((-.65-p[2])/.22,0,1))
        return "Tail","TailTip",float(np.clip((.76-p[1])/.12,0,1))
    if wolf:
        tube([(0,.75,-.49),(0,.68,-.64),(0,.52,-.78),(0,.425,-.89),(0,.40,-.98)],
             [(.081,.078),(.095,.094),(.087,.091),(.062,.064),(.009,.014)],tail_weights,dark,.98)
    else:
        tube([(0,.79,-.58),(.015,.78,-.69),(.024,.68,-.71),(.030,.61,-.70)],
             [(.025,.030),(.018,.017),(.013,.013),(.026,.031)],tail_weights,dark,.24)

    for fore in [True,False]:
        for left in [True,False]:
            key=("F" if fore else "H")+("L" if left else "R")
            x=(1 if left else -1)*(.139 if wolf else .195)
            z=(.306 if fore else -.36)
            base=np.array([x,.70,z])
            knee=np.array([x,.414,z+(-.072 if fore else .122)])
            ankle=np.array([x,.143,z+(.014 if fore else -.083)])
            foot=np.array([x,.048,ankle[2]+.042])
            if wolf and fore:
                knee[2]-=.048
                ankle[2]-=.012
                foot[2]=ankle[2]+.059
            upper=joint("Upper"+key,"Chest" if fore else "Body",base)
            lower=joint("Lower"+key,upper,knee)
            toe=joint("Paw"+key,lower,ankle)
            thick=1. if wolf else 1.23
            def blend(p):
                if p[1]>.46: return upper,lower,0.
                if p[1]>.33: return upper,lower,float(np.clip((.46-p[1])/.13,0,1))
                return lower,toe,float(np.clip((.175-p[1])/.065,0,1))
            if wolf and fore:
                tube([base+[-x*.42,.11,0],base+[-x*.14,0,0],.48*base+.52*knee,knee,
                      .77*knee+.23*ankle,.32*knee+.68*ankle,ankle+[0,.022,-.008],ankle,
                      .42*ankle+.58*foot,foot],
                     [(.070,.10),(.092,.14),(.080,.104),(.061,.079),(.055,.064),
                      (.040,.047),(.042,.050),(.045,.050),(.043,.046),(.047,.047)],blend,coat,.98)
            else:
                tube([base+[-x*.42,.111,0],base+[-x*.15,0,0],base*.5+knee*.5,knee,(knee+ankle)*.5+[0,0,-.012 if fore else -.059],ankle,foot],
                     [(w*thick,h*thick) for w,h in [( .071,.102),(.093,.142 if fore else .158),(.078,.097 if fore else .135),(.053,.058),
                       (.040,.043),(.031,.037),(.038,.043)]],blend,coat,.98)
            if wolf and fore:
                # A single metacarpal pad supports four toes, with the middle
                # digits reaching farther and the outside pair splaying gently.
                tube([foot+[0,.020,-.037],foot+[0,.012,-.010],foot+[0,.005,.021],
                      foot+[0,.002,.048],foot+[0,-.004,.075],foot+[0,-.005,.087]],
                     [(.040,.032),(.058,.041),(.067,.044),(.070,.041),(.060,.032),(.041,.021)],
                     toe,pale,.92,24)
                for j in (-1.5,-.5,.5,1.5):
                    edge=abs(j)-.5
                    tip=foot+[j*.032,-.014,.094-.020*edge]
                    tube([tip+[-j*.007,.013,-.045],tip+[0,.006,-.019],tip,
                          tip+[j*.002,-.005,.021],tip+[j*.002,-.009,.030]],
                         [(.015,.019),(.024,.026),(.023,.024),(.018,.019),(.009,.010)],
                         toe,pale,.88,16)
                    tube([tip+[j*.002,-.006,.022],tip+[j*.003,-.009,.031],
                          tip+[j*.004,-.015,.040]],[(.006,.007),(.005,.006),(.001,.001)],
                         toe,"64584a",.02,10)
            elif wolf:
                pebble(foot+[0,-.004,.031],(.054,.039,.075),toe,pale,.95)
                for j in (-1.5,-.5,.5,1.5):
                    tip=foot+[j*.021,-.019,.079-abs(j)*.009]
                    pebble(tip,(.017,.023,.04),toe,pale,.88)
                    pebble(tip+[0,-.005,.032],(.007,.009,.012),toe,dark,.03)
            else:
                for j in (-1,1):
                    tube([foot+[j*.021,.043,.001],foot+[j*.026,.008,.017],
                          foot+[j*.030,-.026,.030],foot+[j*.029,-.036,.037]],
                         [(.022,.032),(.028,.043),(.026,.048),(.023,.042)],toe,"46392e",.02)
    # Both animals carry their muzzle forward and down from the poll.
    for i,(first,_,_,_) in enumerate(joints):
        if first not in (names["Head"],names["Jaw"]): continue
        angle=.27 if wolf else .31
        cs,sn=math.cos(angle),math.sin(angle)
        rot=np.array([[1,0,0],[0,cs,-sn],[0,sn,cs]])
        pivot=origins[names["Head"]]
        pos[i]=pivot+rot@(pos[i]-pivot)
        nrm[i]=rot@nrm[i]
    write_skin(ROOT/(kind+".glb"),kind.title(),nodes,0,origins,pos,nrm,colors,uv,joints,weights)


def angles(n):
    return np.arange(n)*math.tau/n


if __name__=="__main__":
    for animal in ["wolf","boar"]: build(animal)

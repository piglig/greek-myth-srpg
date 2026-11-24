"""Apply the three divine paint schemes to the approved Alcas drawings without moving the figure.

Six traced material masks (160 x 128) are also the guides for the existing motion strips.
Pick the closest facing and transport its labels to each painted in-between with optical flow.
"""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "art/originals"
PIXEL = ROOT / "prototype/art/pixel"
KEYS = (0, 1, 13)
# Cloak, spear, shield ellipse, wrist cord and visible eye. Front row then back row.
TRACES = [
    ([(75,51),(81,47),(89,45),(99,51),(104,63),(101,80),(94,71),(84,62),(76,67),(72,65)],
     [(57,30),(68,45),(69,55),(74,66),(70,67),(61,47)],(92,73,8,14),(73,64),(80,43)),
    ([(68,52),(75,48),(84,46),(95,54),(105,66),(107,80),(92,74),(79,64),(69,70),(66,64)],
     [(53,35),(61,45),(62,53),(69,65),(66,68),(56,49)],(87,73,8,14),(68,66),(73,44)),
    ([(90,43),(97,42),(106,48),(117,56),(125,71),(117,73),(106,68),(101,54),(91,64),(84,66)],
     [(36,107),(44,98),(64,84),(74,76),(74,80),(49,99)],(102,74,8,14),(70,82),(83,49)),
    ([(69,49),(77,46),(86,53),(88,66),(92,80),(84,87),(60,95),(57,88),(61,68)],
     [(102,31),(100,44),(95,48),(90,65),(88,63),(94,44)],None,(90,61),None),
    ([(69,49),(77,47),(84,58),(87,68),(76,79),(54,99),(54,86),(60,71)],
     [(110,37),(109,44),(102,50),(95,75),(93,76),(100,48)],None,(93,71),None),
    ([(68,53),(79,50),(83,54),(78,68),(77,80),(68,87),(47,91),(48,80),(58,68)],
     [(119,39),(115,45),(103,50),(98,54),(94,53),(105,46)],None,(101,52),None),
]
cv2.setNumThreads(1)


def labels(index, scale=1, shield=True):
    cloak,spear,disk,cord,eye=TRACES[index]
    skirt=[
        [(76,69),(87,68),(90,82),(85,90),(74,87),(73,82)],
        [(71,69),(83,69),(88,80),(81,88),(67,87)],
        [(86,66),(102,66),(111,80),(105,88),(78,82)],
        [(76,76),(87,76),(90,84),(84,91),(72,92)],
        [(70,74),(84,67),(83,80),(73,89),(65,89)],
        [(64,74),(77,66),(86,77),(80,88),(66,93),(60,86)],
    ][index]
    mask=np.zeros((128*scale,160*scale),np.uint8)
    cv2.fillPoly(mask,[np.array(skirt,np.int32)*scale],6)
    for role,shape in enumerate((cloak,spear),1):
        cv2.fillPoly(mask,[np.array(shape,np.int32)*scale],role)
    if shield and disk:
        x,y,rx,ry=disk
        cv2.ellipse(mask,(x*scale,y*scale),(rx*scale,ry*scale),0,0,360,3,-1)
    cv2.circle(mask,tuple(v*scale for v in cord),scale+scale//2,4,-1)
    if eye:
        cv2.circle(mask,tuple(v*scale for v in eye),max(0,scale-1),5,-1)
    return mask


def paint(pic, mask, tier, scale=1):
    data=np.array(pic)
    rgb=data[:,:,:3].astype(np.float32)
    inside=data[:,:,3]>60
    lum=rgb @ np.array([.299,.587,.114],np.float32)
    cloth=(mask==1)&inside
    metal=(mask==2)&inside
    disk=(mask==3)&inside
    def erode(m,n):
        return cv2.erode(m.astype(np.uint8),np.ones((n,n),np.uint8)).astype(bool)
    hem=cloth & ~erode(cloth,3*scale) & (lum>45)
    # Break the upper seam in shadow; let the lower edge catch the light.
    above=np.roll(cloth,2*scale,axis=0)
    hem &= above | (lum>110)
    def glaze(selection,stops):
        for c in range(3):
            rgb[:,:,c][selection]=np.interp(lum[selection],[0,48,96,160,223,255],[v[c] for v in stops])
    blue=[(15,19,32),(22,39,59),(35,72,109),(54,112,158),(112,171,204),(186,219,231)]
    gold=[(37,28,27),(89,61,35),(155,107,49),(218,167,84),(252,221,152),(255,242,203)]
    if tier==1:
        glaze(hem,[(21,35,49),(37,79,108),(58,124,167),(104,180,217),(168,218,238),(218,242,250)])
    else:
        if tier==3:
            glaze(inside,[(21,23,34),(59,56,65),(112,112,127),(184,183,191),(236,235,231),(251,249,240)])
        glaze(cloth,blue)
        if tier==3: glaze(disk | ((mask==6)&inside),blue)
        rim=disk & ~erode(disk,4*scale+1)
        glaze(hem|metal|rim,gold)
        edge=inside & ~erode(inside,2*scale+1)
        lit=edge & ((lum>60) & (np.roll(inside,scale,axis=1)==False))
        rgb[lit]=rgb[lit]*.69+np.array([236,226,200])*.31
        if tier==3:
            # A flecked filament branches along the outer edge of the spearhead.
            y,x=np.indices(metal.shape)
            thread=metal & ~erode(metal,2*scale+1) & (((x+2*y)//(4*scale))%3!=0)
            rgb[thread]=[243,239,214]
            rgb[(mask==4)&inside]=[156,51,38]
    rgb[(mask==5)&inside]=[143,206,235] if tier<3 else [252,247,221]
    data[:,:,:3]=np.clip(rgb,0,255).astype(np.uint8)
    return Image.fromarray(data)


def gray(pic):
    a=np.asarray(pic)
    return (cv2.cvtColor(a[:,:,:3],cv2.COLOR_RGB2GRAY)* (a[:,:,3]>.5)).astype(np.uint8)


def main():
    original=Image.open(ROOT/"prototype/art/original/actors/hero.png").convert("RGBA")
    base=Image.open(PIXEL/"hero/actors.png").convert("RGBA")
    sheets=[Image.new("RGBA",(1536,1024)) for _ in range(3)]
    examples=[]
    for side in range(2):
        for col,key in enumerate(KEYS):
            i=side*3+col
            box=(key*320,side*256,(key+1)*320,(side+1)*256)
            src=original.crop(box)
            # The approved pixel bake composites the round shield over the old
            # spear drawing. Lift that same shield onto the matching source key.
            if TRACES[i][2]:
                native_box=tuple(v//2 for v in box)
                shield=base.crop(native_box)
                keep=(labels(i)==3).astype(np.uint8)*np.asarray(shield)[:,:,3]
                shield.putalpha(Image.fromarray(keep))
                src.alpha_composite(shield.resize(src.size,Image.Resampling.LANCZOS))
            for tier,sheet in enumerate(sheets,1):
                plate=ImageOps.mirror(paint(src,labels(i,2),tier,2))
                plate=plate.resize((544,435),Image.Resampling.LANCZOS)
                sheet.alpha_composite(plate,(col*512-16,side*512+37))
            g=gray(base.crop(tuple(v//2 for v in box)))
            for k,m in ((g,labels(i)),(np.fliplr(g),np.fliplr(labels(i)))):
                examples.append((np.ascontiguousarray(k),np.ascontiguousarray(m)))
    for tier,sheet in enumerate(sheets,1): sheet.save(ART/f"hero-tier{tier}.png")
    samples=np.asarray([cv2.resize(g,(40,32),interpolation=cv2.INTER_AREA) for g,_ in examples],np.float32)
    flow=cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_FAST)
    yy,xx=np.mgrid[:128,:160].astype(np.float32)
    for source in sorted((PIXEL/"hero").glob("*.png")):
        src=Image.open(source).convert("RGBA")
        results=[Image.new("RGBA",src.size) for _ in range(3)]
        for y in range(0,src.height,128):
            for x in range(0,src.width,160):
                cell=src.crop((x,y,x+160,y+128))
                if not cell.getchannel("A").getbbox():continue
                g=gray(cell)
                small=cv2.resize(g,(40,32),interpolation=cv2.INTER_AREA)
                nearest=int(np.argmin(((samples-small)**2).mean(axis=(1,2))))
                ref,mask=examples[nearest]
                delta=flow.calc(g,ref,None)
                transported=cv2.remap(mask,xx+delta[:,:,0],yy+delta[:,:,1],cv2.INTER_NEAREST)
                for tier,sheet in enumerate(results,1): sheet.paste(paint(cell,transported,tier),(x,y))
        for tier,sheet in enumerate(results,1):
            folder=PIXEL/f"hero-tier{tier}"
            folder.mkdir(exist_ok=True)
            sheet.save(folder/source.name,compress_level=4)
        print(source.name,flush=True)


if __name__=="__main__":
    main()

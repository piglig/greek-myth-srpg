"""Register approved, transparent character drawings on a common ground baseline."""
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'art/originals'
OUT = ROOT / 'prototype/art/original'
(OUT/'actors').mkdir(parents=True,exist_ok=True)


def split(sheet, count, axis):
    # Find the quietest gutter near each expected division; long spears cross cell centres.
    alpha = sheet.getchannel('A').point(lambda x: 255 if x>60 else 0)
    if axis == 'y':
        alpha = alpha.transpose(Image.Transpose.TRANSPOSE)
    density = list(alpha.resize((alpha.width,1),Image.Resampling.BOX).getdata())
    cuts = [0]
    for i in range(1,count):
        pos = alpha.width*i/count
        radius = alpha.width/count*.24
        cuts.append(min(range(round(pos-radius),round(pos+radius)),key=lambda x:(density[x],abs(x-pos))))
    cuts.append(alpha.width)
    if axis=='y':
        return [sheet.crop((0,a,sheet.width,b)) for a,b in zip(cuts,cuts[1:])]
    return [sheet.crop((a,0,b,sheet.height)) for a,b in zip(cuts,cuts[1:])]


def rows(name, count):
    return split(Image.open(SRC/(name+'.png')).convert('RGBA'),count,'y')


def register(name, directions, flip=False):
    frames = []
    for direction in directions:
        cut = []
        for pose in direction:
            pose = ImageOps.mirror(pose) if flip else pose.copy()
            alpha = pose.getchannel('A')
            pose.putalpha(alpha.point(lambda x: 0 if x<20 else x))
            cut.append(pose.crop(alpha.point(lambda x:255 if x>40 else 0).getbbox()))
        frames.append(cut)
    if len(frames[0]) == 5:
        # The supplemental key sheet was painted at a larger scale than the turnaround.
        # Register both keys together so the crouch-to-recovery change is preserved.
        for row in frames:
            factor = row[0].height*.86 / max(p.height for p in row[3:])
            row[3:] = [p.resize((round(p.width*factor),round(p.height*factor)),Image.Resampling.LANCZOS) for p in row[3:]]
    # Use one common scale so crouching and lunging retain their drawn proportions.
    scale = min(208/frames[0][0].height, min(311/p.width for row in frames for p in row),
                min(230/p.height for row in frames for p in row))
    if name == 'atalanta':
        # In the approved carry drawings she looks the opposite way to the
        # full draw. Keep grip and nose on the firing side at the handoff.
        for row in frames:
            row[:2] = [ImageOps.mirror(p) for p in row[:2]]
        for i,ratio in [(1,186/218), (2,186/200)]:
            p = frames[1][i]
            frames[1][i] = p.resize((round(p.width*ratio), round(p.height*ratio)),Image.Resampling.LANCZOS)
    if name == 'heracles':
        # The reverse source row includes fragments of the figure above it.
        import cv2
        import numpy as np
        for i in (1, 2):
            pose = frames[1][i]
            alpha = np.asarray(pose.getchannel('A'))
            _, labels, stats, _ = cv2.connectedComponentsWithStats((alpha > 0).astype('uint8'))
            body = labels == (1 + np.argmax(stats[1:, cv2.CC_STAT_AREA]))
            pose.putalpha(Image.fromarray(np.where(body, alpha, 0).astype('uint8')))
            frames[1][i] = pose.crop(pose.getbbox())
    if name in ('hero','heracles'):
        # Reverse walk and alternate strike came from a larger drawing sheet.
        # Match the walk-to-idle height ratio of the front view, then use the
        # same scale for BOTH drawings so their authored pose change survives.
        front, back = frames
        ratio = (front[1].height / front[0].height) * back[0].height / back[1].height
        back[1:3] = [p.resize((round(p.width*ratio),round(p.height*ratio)),
                              Image.Resampling.LANCZOS) for p in back[1:3]]
    if name in ('hero','wolf'):
        gait = Image.open(SRC/(name+'-gait.png')).convert('RGBA')
        # The spear sheet has a translucent neutral wash outside its painted silhouettes.
        if name == 'hero':
            gait.putalpha(gait.getchannel('A').point(lambda a: max(0,min(255,(a-138)*3))))
        for row,source in zip(frames,split(gait,2,'y')):
            steps = []
            for cell in split(source,6,'x'):
                mask = cell.getchannel('A').point(lambda a: 255 if a>75 else 0)
                steps.append(cell.crop(mask.getbbox()))
            factor = min(row[1].height / max(p.height for p in steps),
                         311/(scale*max(p.width for p in steps)))
            row.extend(p.resize((round(p.width*factor),round(p.height*factor)),Image.Resampling.LANCZOS) for p in steps)
        for row,source in zip(frames,rows(name+'-attack',2)):
            attack = []
            for cell in split(source,4,'x'):
                bounds = cell.getchannel('A').point(lambda a: 255 if a>65 else 0).getbbox()
                attack.append(cell.crop(bounds))
            factor = min(row[0].height/max(p.height for p in attack),
                         311/(scale*max(p.width for p in attack)))
            row.extend(p.resize((round(p.width*factor),round(p.height*factor)),Image.Resampling.LANCZOS) for p in attack)
    sheet = Image.new('RGBA',(320*len(frames[0]),512))
    for j,row in enumerate(frames):
        for i,p in enumerate(row):
            p=p.resize((max(1,round(p.width*scale)),max(1,round(p.height*scale))),Image.Resampling.LANCZOS)
            sheet.alpha_composite(p,(i*320+(320-p.width)//2,j*256+240-p.height))
    sheet.save(OUT/'actors'/(name+'.png'))


front,back,keys=rows('figures',4),rows('reverse',4),rows('strike-keys',4)
for i,name in enumerate(('hero','atalanta','heracles','lion')):
    poses=split(front[i],4,'x')
    directions=[poses[:3],[poses[3],*split(back[i],2,'x')]]
    if name in ('hero','lion'):
        start=0 if name=='hero' else 2
        for j in (0,1):
            directions[j].extend(split(keys[start+j],2,'x'))
    register(name,directions)
beasts=rows('beasts',4)
for i,name in enumerate(('wolf','boar')):
    register(name,[split(beasts[2*i+j],3,'x') for j in (0,1)])
for name in ('bandit','bandit_archer','bandit_chief'):
    register(name,[split(row,3,'x') for row in rows(name,2)],flip=True)
refugee = Image.open(SRC/'refugee.png').convert('RGBA')
cell_width, cell_height = refugee.width//3, refugee.height//2
register('refugee', [[refugee.crop((x*cell_width,y*cell_height,(x+1)*cell_width,(y+1)*cell_height))
                      for x in range(3)] for y in range(2)])
for src,dst in [('limestone','earth'),('cliff','cliff')]:
    im=Image.open(SRC/(src+'.png')).convert('RGB')
    im.thumbnail((1024,1024))
    im.save(OUT/(dst+'.webp'),quality=91)
fire=Image.open(SRC/'fire.png').convert('RGBA')
strip=Image.new('RGBA',(512,128))
for i,p in enumerate(split(fire,4,'x')):
    p=p.crop(p.getchannel('A').point(lambda x:255 if x>45 else 0).getbbox())
    p.thumbnail((120,118))
    strip.alpha_composite(p,(i*128+(128-p.width)//2,121-p.height))
strip.save(OUT/'fire.png')

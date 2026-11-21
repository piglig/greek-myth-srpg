"""Draw the continuous action phases for each battlefield action mark."""
from pathlib import Path
from math import sin,cos,pi
from PIL import Image,ImageDraw

out = Path(__file__).resolve().parents[2]/'prototype/art/original/fx'
out.mkdir(parents=True, exist_ok=True)
for kind in ('arrow','impact','dust','slash','roar'):
    frames = 1 if kind == 'arrow' else 32
    strip=Image.new('RGBA',(64*frames,64))
    for i in range(frames):
        frame=Image.new('RGBA',(64,64))
        pen=ImageDraw.Draw(frame)
        t=i/max(1,frames-1)
        ochre=(190,141,84,round(255*(1-.54*t)))
        chalk=(255,226,166,round(255*(1-.54*t)))
        if kind=='arrow':
            pen.line((8,32,51,32),fill='#886541',width=2)
            pen.polygon([(48,28),(58,32),(48,36)],fill='#C7B997')
            pen.polygon([(7,28),(18,32),(7,35),(11,32)],fill='#EBCEA7')
        elif kind=='slash':
            arc=(8-7*t,8,54+5*t,51)
            pen.arc(arc,185+90*t,282+75*t,fill=chalk,width=round(6-5*t))
        elif kind=='roar':
            for ring in (0,6):
                r=6+19*t-ring
                if r>0:
                    pen.arc((32-r,33-r*.65,32+r,33+r*.65),205,337,fill=ochre,width=2)
        else:
            for k in range(8):
                a=k*2*pi/8+.23*sin(k)
                r=3+22*t
                x,y=32+cos(a)*r,34+sin(a)*r*(.44 if kind=='dust' else 1)
                if kind=='dust':
                    pen.ellipse((x-3,y-2,x+2,y+1),fill=ochre)
                else:
                    pen.line((x,y,x-cos(a)*7,y-sin(a)*7),fill=chalk,width=2)
        strip.paste(frame,(i*64,0))
    strip.save(out/(kind+'.png'))

"""Pack the output of bake_hoplite.gd, preserving a common ground anchor."""
from pathlib import Path
import json
import sys
from PIL import Image

src = Path(sys.argv[1])
dest = Path(__file__).resolve().parents[2]/"prototype/art/original"/(sys.argv[2] if len(sys.argv)>2 else "hoplite")
dest.mkdir(parents=True, exist_ok=True)
records = {}
for direction in range(8):
    frames = []
    for path in sorted(src.glob("*.png")):
        name, index = path.stem.rsplit("-", 1)
        with Image.open(path) as row:
            tile = row.crop((direction*320, 0, (direction+1)*320, 320)).convert("RGBA")
        box = tile.getchannel("A").getbbox()
        if box is None or min(box[:2]) == 0 or max(box[2:]) == 320:
            raise ValueError(f"Empty or cropped silhouette: {direction}, {path}, {box}")
        frames.append((name,int(index),box,tile.crop(box)))
    x=y=line=0
    placed=[]
    for name,index,(left,top,right,bottom),patch in sorted(frames,key=lambda f:-f[3].height):
        if x+patch.width+4>2048:
            y+=line; x=line=0
        placed.append((x+2,y+2,patch))
        records.setdefault(name,{}).setdefault(str(direction),{})[index]=[
            x+2,y+2,patch.width,patch.height,left,top]
        x+=patch.width+4
        line=max(line,patch.height+4)
    atlas=Image.new("RGBA",(2048,y+line))
    for x,y,patch in placed:
        atlas.paste(patch,(x,y))
    atlas.save(dest/f"view_{direction}.webp",lossless=True,method=3)
manifest={clip:[[frames[i] for i in range(len(frames))] for frames in directions.values()]
          for clip,directions in records.items()}
(dest/"frames.json").write_text(json.dumps(manifest,separators=(",",":"))+"\n")

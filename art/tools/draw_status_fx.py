"""Draw the looping mark for the one ailment no effect kit has a fitting one for.

    python art/tools/draw_status_fx.py

It is a strip of square frames, drawn here pixel by pixel in the game's own pigments,
and written to prototype/art/original/fx/. `view/battle_controller.gd` plays it on the
body for as long as the status lasts (see its AURAS table).

    rooted    two turns of rope drawn tight round the ankles, the strands creeping
"""
from pathlib import Path
import math

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[2] / "prototype/art/original/fx"
INK = (38, 22, 14, 255)
ROPE = [(138, 98, 56, 255), (217, 183, 122, 255), (244, 222, 172, 255)]


def outlined(frame):
    """A one-pixel dark rim, so pale marks read on pale stone."""
    out = frame.copy()
    src, dst = frame.load(), out.load()
    for y in range(frame.height):
        for x in range(frame.width):
            if src[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < frame.width and 0 <= ny < frame.height and src[nx, ny][3]:
                    dst[x, y] = INK
                    break
    return out


def strip(frames):
    sheet = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height))
    for index, frame in enumerate(frames):
        sheet.paste(outlined(frame), (index * frame.width, 0))
    return sheet


def rooted(count=12, side=96):
    """The near half of two loops of rope. The far half would be behind the legs."""
    frames = []
    for index in range(count):
        turn = index / count
        frame = Image.new("RGBA", (side, side))
        px = frame.load()
        # The loops draw in and ease off once a round, as if pulled.
        pull = .5 - .5 * math.cos(turn * math.tau)
        for loop, height in enumerate((44, 52)):
            rx, ry = 21 - 2.5 * pull - loop, 7 - pull
            for step in range(0, 181):
                angle = math.radians(step)
                x, y = side / 2 + rx * math.cos(angle), height + ry * math.sin(angle)
                # Strands: bands of light and dark that creep along the rope.
                strand = int((step / 15 + turn * 4 + loop * .5) % 2)
                for thick in range(3):
                    px[round(x), round(y) + thick] = ROPE[2 if thick == 0 and strand else (1 if strand else 0)]
        # The knot, where the two loops are made fast.
        pen = ImageDraw.Draw(frame)
        pen.rectangle((side // 2 - 3, 50, side // 2 + 2, 58), fill=ROPE[1])
        pen.rectangle((side // 2 - 3, 50, side // 2 + 2, 51), fill=ROPE[2])
        pen.line((side // 2 - 1, 59, side // 2 - 3, 64 + round(pull)), fill=ROPE[0], width=2)
        pen.line((side // 2 + 1, 59, side // 2 + 4, 63 + round(pull)), fill=ROPE[0], width=2)
        frames.append(frame)
    return strip(frames)


OUT.mkdir(parents=True, exist_ok=True)
for name, sheet in (("rooted", rooted()),):
    sheet.save(OUT / f"{name}.png")
    print(name, sheet.size)

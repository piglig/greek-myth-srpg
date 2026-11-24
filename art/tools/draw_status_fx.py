"""Paint the cast net, ankle binding and laurel level-up at their shared 96px scale."""

from math import cos, sin, pi, tau
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SIZE = 96
SCALE = 3
INK = (67, 42, 33, 255)
HEMP = (177, 127, 73, 255)
FLAX = (241, 205, 143, 255)
LEAD = (91, 93, 93, 255)


class Frame:
    def __init__(self):
        self.image = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE))
        self.pen = ImageDraw.Draw(self.image)

    def line(self, points, color, width):
        pts = [(round(x * SCALE), round(y * SCALE)) for x, y in points]
        self.pen.line(pts, fill=color, width=max(1, round(width * SCALE)), joint="curve")

    def patch(self, points, color):
        self.pen.polygon([(round(x * SCALE), round(y * SCALE)) for x, y in points], fill=color)

    def rope(self, points, width):
        self.line(points, INK, width + 1.1)
        self.line(points, HEMP, width)
        self.line([(x - 0.25, y - 0.38) for x, y in points], FLAX, width * 0.38)

    def weight(self, x, y):
        self.patch(
            [
                (x - 2, y - 0.6),
                (x - 0.6, y - 2.2),
                (x + 1.7, y - 1.6),
                (x + 2.1, y + 1),
                (x, y + 2.4),
                (x - 2, y + 1.5),
            ],
            INK,
        )
        self.patch(
            [
                (x - 1.5, y - 0.3),
                (x, y - 1.5),
                (x + 1.2, y - 0.8),
                (x + 0.8, y + 1.3),
                (x - 1, y + 1),
            ],
            LEAD,
        )
        self.line([(x - 1.3, y - 0.1), (x, y - 1)], (211, 204, 178, 255), 0.85)

    def finish(self):
        return self.image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def ankle(phase=0, loose=0):
    f = Frame()
    pull = (1 - cos(tau * phase)) * 0.5
    rx = 18.8 - pull * 1.55 + loose * 7

    def front(a, j):
        return (
            48 + 0.65 * sin(tau * phase) + (rx - j) * cos(a),
            42 + 7 * j + (6 + loose * 2) * sin(a) + cos(a) * 2.2,
        )

    for j in (0, 1):
        # Only the turn of the rope in front of the shins catches direct light.
        arc = [front(pi * (k / 32 * 1.13 - 0.065), j) for k in range(33)]
        f.rope(arc, 2.3)
        for k in range(2, 32, 3):
            x, y = arc[k]
            f.line([(x - 0.6, y + 0.6), (x + 0.4, y - 0.6)], (123, 84, 51, 255), 0.8)
    for offset in (-1, 1):
        f.rope([(52 + offset, 49), (52 + offset * 3, 56), (52 + offset * 5, 59 + pull)], 1.4)
    f.rope([(49.5, 49.3), (53.5, 52.8), (55, 49.5), (51, 48.6)], 2.1)
    f.weight(47, 60 + pull)
    return f.finish()


def cast(index):
    if index == 7:
        return ankle()
    if index == 6:
        return ankle(loose=0.8)
    # The four corners keep their identity as the folded mesh opens, bellies and falls.
    width, height, flap, shear = [
        (8, 12, 4, -4),
        (15, 16, 7, -7),
        (28, 23, 9, -8),
        (39, 27, 7, -4),
        (42, 21, 4, 1),
        (29, 13, -12, 2),
    ][index]
    f = Frame()

    def knot(u, v):
        x = width * (u - v) / 2
        y = height * (u + v) / 2 + flap * (1 - u * u) * (1 - v * v)
        return (48 + x + shear * (u + v) / 2, 48 + y + sin(pi * u) * cos(pi * v) * flap * 0.18)

    divisions = 5
    for k in range(1, divisions):
        u = -1 + 2 * k / divisions
        for transpose in [False, True]:
            path = []
            for j in range(25):
                v = -1 + 2 * j / 24
                path.append(knot(v, u) if transpose else knot(u, v))
            f.rope(path, 1.25)
    corners = [knot(-1, -1), knot(1, -1), knot(1, 1), knot(-1, 1)]
    f.rope(corners + [corners[0]], 2.2)
    for x, y in corners:
        f.weight(x, y)
    return f.finish()


def laurel(index):
    f = Frame()
    t = index / 9
    y = 83 - 65 * min(t / 0.80, 1)
    rx = (18 + 16 * sin(min(t / 0.80, 1) * pi * 0.7)) * (1 - 0.35 * max(0, t - 0.72))
    opacity = [150, 211, 235, 241, 230, 220, 202, 181, 115, 42][index]
    for a, b in ((0.12, 1.26), (1.87, 3.0), (3.24, 4.52), (4.93, 6.12)):
        arc = [
            (48 + rx * cos(a + (b - a) * k / 16), y + 5 * sin(a + (b - a) * k / 16))
            for k in range(17)
        ]
        f.line(arc, (194, 132, 52, opacity // 3), 3.0)
        f.line(arc, (239, 184, 87, opacity), 1.45)
        f.line(arc[:8], (255, 233, 176, opacity), 0.7)
    for side in [-1, 1]:
        for k in range(3):
            age = t - 0.47 - 0.075 * k
            if age <= 0:
                continue
            x = 48 + side * (18 + age * (26 + 8 * k))
            h = y + 1 - k * 1.8 - age * 12
            length = 4.5 * sin(min(1, age / 0.52) * pi * 0.85)
            alpha = round(230 * min(1, age * 12) * min(1, (1.04 - t) * 5))
            f.patch(
                [
                    (x, h),
                    (x + side * length * 0.22, h - length),
                    (x + side * length, h - length * 1.5),
                    (x + side * length * 0.82, h - length * 0.30),
                ],
                (237, 193, 99, alpha),
            )
    return f.finish()


if __name__ == "__main__":
    for name, frames in [
        ("net", [cast(i) for i in range(8)]),
        ("rooted", [ankle(i / 6) for i in range(6)]),
        ("levelup", [laurel(i) for i in range(10)]),
    ]:
        strip = Image.new("RGBA", (SIZE * len(frames), SIZE))
        for i, frame in enumerate(frames):
            strip.paste(frame, (i * SIZE, 0))
        for folder in ["art/originals/fx", "prototype/art/original/fx"]:
            strip.save(ROOT / folder / (name + ".png"))

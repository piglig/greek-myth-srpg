"""Repaint a kind's registered drawings into another person, then bake them.

    python art/tools/repaint_looks.py <agent-sprite-forge checkout> [look ...]
    python art/tools/repaint_looks.py --preview <folder> [look ...]

People who have no drawings of their own borrow a kind's six registered poses
(prototype/art/original/actors/<kind>.png) and change the paint on them: cloth to another
dye, a crest or a blade taken away, hair gone grey. The poses stay where they are, so the
result goes through that kind's whole bake (see bake_look.py) and comes out as a full set
of sheets in prototype/art/pixel/<look>/.

Boxes are in the sheet's own pixels: six cells of 320x256, front row then rear row.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ACTORS = ROOT / "prototype/art/original/actors"


def hsv(rgb):
    """Hue in degrees, saturation and value in 0..1."""
    out = cv2.cvtColor(rgb.astype(np.float32) / 255, cv2.COLOR_RGB2HSV)
    return out[..., 0], out[..., 1], out[..., 2]


def rgb(h, s, v):
    return np.uint8(np.clip(cv2.cvtColor(np.dstack((h, s, v)).astype(np.float32), cv2.COLOR_HSV2RGB) * 255 + .5, 0, 255))


def hue_in(h, lo, hi):
    return (h >= lo) & (h <= hi) if lo <= hi else (h >= lo) | (h <= hi)


def boxed(shape, boxes):
    mask = np.zeros(shape, bool)
    for x0, y0, x1, y1 in boxes:
        mask[y0:y1, x0:x1] = True
    return mask


def dye(paint, window, hue, sat, gain=1.0, lift=0.0, where=None, mend=3):
    """Move cloth inside a hue window to another dye. `sat` None keeps the cloth's own."""
    h, s, v = hsv(paint[..., :3])
    pick = hue_in(h, window[0], window[1]) & (s >= window[2]) & (s <= window[3]) & (paint[..., 3] > 0)
    if where is not None:
        pick &= where
    # Stray dark flecks inside the cloth are cloth too, whatever their hue.
    closed = cv2.morphologyEx(pick.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((mend, mend), np.uint8)) > 0
    pick |= closed & (paint[..., 3] > 0) & (s < (.5 if mend == 3 else .8)) & (v < (.45 if mend == 3 else .6))
    new_s = s if sat is None else sat * (.6 + .8 * s)
    out = rgb(np.full_like(h, hue), np.clip(new_s, 0, 1), np.clip(v * gain + lift, 0, 1))
    paint[..., :3][pick] = out[pick]


def strip(paint, boxes, test):
    """Take away what `test(h, s, v)` picks inside the boxes, and the crumbs it leaves."""
    h, s, v = hsv(paint[..., :3])
    area = boxed(h.shape, boxes)
    paint[area & test(h, s, v)] = 0
    # Specks cut off from the figure by the removal go too.
    _, labels, stats, _ = cv2.connectedComponentsWithStats((paint[..., 3] > 40).astype(np.uint8), connectivity=8)
    small = np.isin(labels, np.flatnonzero(stats[:, cv2.CC_STAT_AREA] < 60))
    paint[area & small] = 0
    # And the hairlines of outline that used to run round it.
    solid = cv2.morphologyEx((paint[..., 3] > 40).astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    paint[area & (solid == 0)] = 0


def grey(paint, boxes, darkest=.25):
    """Turn dark hair inside the boxes grey."""
    h, s, v = hsv(paint[..., :3])
    pick = boxed(h.shape, boxes) & (v < darkest) & (paint[..., 3] > 0)
    out = rgb(np.full_like(h, 35), np.full_like(s, .08), np.clip(.38 + v * 1.5, 0, .8))
    paint[..., :3][pick] = out[pick]


def drillmaster(paint, plates=True):
    """达蒙, who trains the hired: the raider chief without crest or axe, an old soldier
    in undyed wool with a staff."""
    crest = [(146, 26, 196, 70), (452, 30, 503, 70), (754, 36, 808, 76),
             (128, 284, 178, 326), (462, 280, 511, 322), (797, 288, 848, 328)]
    strip(paint, crest, lambda h, s, v: hue_in(h, 345, 16) & (s > .45))
    blade = [(86, 92, 126, 146), (398, 92, 440, 144), (800, 22, 856, 76),
             (194, 340, 236, 390), (524, 330, 566, 382), (746, 274, 802, 314)]
    strip(paint, blade, lambda h, s, v: (s < .36) | (v > .62))
    dye(paint, (232, 350, .08, .46), 38, .27, gain=2.25, lift=.02)
    beard = [(150, 60, 186, 92), (455, 62, 492, 94), (755, 66, 795, 98),
             (135, 318, 172, 344), (470, 312, 506, 338), (808, 322, 842, 346)]
    grey(paint, beard)


def bands(top, bottom, columns=3):
    """The same band of rows in every cell: `top`..`bottom` within a cell, front and rear."""
    return [(c * 320, r * 256 + top, c * 320 + 320, r * 256 + bottom) for r in range(2) for c in range(columns)]


CREST = [(146, 26, 196, 70), (452, 30, 503, 70), (754, 36, 808, 76),
         (128, 284, 178, 326), (462, 280, 511, 322), (797, 288, 848, 328)]
MANTLE = (232, 350, .08, .46)


def plume(paint, sat, gain, lift=0.0, hue=40):
    h, s, v = hsv(paint[..., :3])
    dye(paint, (345, 16, .45, 1.0), hue, sat, gain, lift, where=boxed(h.shape, CREST))


def captain(paint, plates=True):
    """佣兵队长: the chief in sea-green, under a white crest."""
    plume(paint, .10, 1.5, .12)
    dye(paint, MANTLE, 186, .46, gain=1.35, lift=.03)


def idas(paint, plates=True):
    """伊达斯: the chief in saffron, under a black crest."""
    plume(paint, .15, .34)
    dye(paint, MANTLE, 33, .80, gain=2.0, lift=.02)


def swordsman(paint, plates=True):
    """佣兵剑士: the raider in undyed linen with a blue scarf."""
    h, s, v = hsv(paint[..., :3])
    dye(paint, (355, 22, .40, 1.0), 212, .50, where=boxed(h.shape, bands(36, 132)) & (v < .56), mend=5)
    dye(paint, (32, 85, .15, .9), 40, .17, gain=1.75, lift=.06, where=boxed(h.shape, bands(72, 222)), mend=5)


def hood(paint, hue, sat, gain=1.0):
    h, s, v = hsv(paint[..., :3])
    dye(paint, (0, 360, 0, .30), hue, sat, gain, where=boxed(h.shape, bands(20, 118)) & (v > .13) & (v < .72), mend=5)


def archer(paint, plates=True):
    """佣兵弓手: the raider archer in a pine-green hood."""
    hood(paint, 150, .40)


def guide(paint, plates=True):
    """带路人: the raider archer in a madder-red hood."""
    hood(paint, 4, .95, 1.05)


def trader(paint, plates=True):
    """阿齐尔, the trader: the villager in a purple cloak over a saffron tunic."""
    h, s, v = hsv(paint[..., :3])
    sack = boxed(h.shape, [(c * 320 + 160, 40, c * 320 + 215, 105) for c in range(3)]
                 + [(c * 320 + 105, 300, c * 320 + 158, 375) for c in range(3)])
    dye(paint, (20, 70, 0, .30), 42, .95, gain=.95, where=~sack & (v > .5))
    dye(paint, (140, 205, .10, 1.0), 300, .42, gain=1.1)


def horse(paint, plates, sash, coat):
    """A centaur with another sash and another coat."""
    h, s, v = hsv(paint[..., :3])
    dye(paint, (345, 12, .55, 1.0), sash[0], sash[1], where=v < .8)
    below = boxed(h.shape, bands(128, 256, 4)) if plates else np.ones(h.shape, bool)
    dye(paint, (340, 19, .10, .85), 28, coat[0], gain=coat[1], lift=coat[2], where=below & (v < .72), mend=5)


def lancer(paint, plates=True):
    """佣兵骑枪: a grey centaur with a blue sash."""
    horse(paint, plates, (212, .55), (.07, 1.5, .08))


def eurytion(paint, plates=True):
    """欧律提翁: a black centaur with a gold sash."""
    horse(paint, plates, (42, .85), (.10, .5, 0))


LOOKS = {
    "npc_drill": ("bandit_chief", drillmaster),
    "merc_captain": ("bandit_chief", captain),
    "idas": ("bandit_chief", idas),
    "merc_sword": ("bandit", swordsman),
    "merc_archer": ("bandit_archer", archer),
    "npc_guide": ("bandit_archer", guide),
    "npc_trader": ("refugee", trader),
    "merc_lancer": ("centaur", lancer),
    "eurytion": ("centaur", eurytion),
}
# Sheets the base kind bakes from other drawings than its six poses. They are repainted
# after the bake, without the boxes that belong to the poses.
AFTER = {"centaur": ["spear.png"]}

if __name__ == "__main__":
    forge = sys.argv[1]
    preview = Path(forge) if forge == "--preview" else None
    names = sys.argv[3:] if preview else sys.argv[2:]
    for look in names or LOOKS:
        base, repaint = LOOKS[look]
        paint = np.array(Image.open(ACTORS / (base + ".png")).convert("RGBA"))
        repaint(paint)
        if preview:
            # Only the repainted drawings, to look at before baking.
            Image.fromarray(paint).save(Path(sys.argv[2]) / (look + ".png"))
            continue
        with tempfile.TemporaryDirectory() as work:
            sheet = Path(work) / (look + ".png")
            Image.fromarray(paint).save(sheet)
            subprocess.run([sys.executable, str(Path(__file__).with_name("bake_look.py")), forge, look, base, str(sheet)], check=True)
        for name in AFTER.get(base, []):
            path = ROOT / "prototype/art/pixel" / look / name
            late = np.array(Image.open(path).convert("RGBA"))
            repaint(late, False)
            Image.fromarray(late).save(path)

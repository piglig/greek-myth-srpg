"""Edit CC0 recorded foley to Pandora's animation timings; see audio credits."""
from functools import lru_cache
from pathlib import Path
import subprocess
from tempfile import gettempdir
from urllib.request import urlopen

import imageio_ffmpeg
import numpy as np

RATE = 44100
IRON = "https://raw.githubusercontent.com/djeada/Standard-of-Iron/2d8deb59ee234869afe019bcd3bf444afe569331/assets/audio/sfx/"
STEPS = "https://raw.githubusercontent.com/Mcamento8/open-game-sfx-index/34bbe8b525b5ceff3804915ea745532af11f6055/audio/oga-footsteps/"
CACHE = Path(gettempdir()) / "pandora-cc0-field-edits-v1"


@lru_cache(maxsize=None)
def recording(name):
    CACHE.mkdir(exist_ok=True)
    path = CACHE / (name.replace("/", "-") + ".ogg")
    if not path.exists():
        url = STEPS + "mud02.ogg" if name == "mud" else IRON + name + ".ogg"
        with urlopen(url, timeout=25) as source:
            data = source.read()
        if not data.startswith(b"OggS"):
            raise ValueError(f"Invalid recording: {url}")
        path.write_bytes(data)
    pcm = subprocess.check_output([imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-i",
                                   str(path), "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"])
    x = np.frombuffer(pcm, "<f4").astype(float)
    # Keep the initial scrape or intake of breath but cut empty lead-in.
    onset = np.flatnonzero(np.abs(x) > np.max(np.abs(x)) * .025)[0]
    return x[max(0, onset - 120):] / np.max(np.abs(x))


# Source takes, relative gain and entrance after the animation callback (seconds).
def layer(names, gain=1., delay=0.):
    return names.split(), gain, delay


def guard_break_foley(export):
    # A taut creak, a dry snap, then the weight settling. Keep the rhythm
    # consistent for every unit; vary the recording underneath the snap.
    def cut(name, offset, seconds, speed, low, high, decay):
        pcm = recording("combat/" + name)
        at = RATE * offset + np.arange(round(RATE * seconds)) * speed
        clip = np.interp(at, np.arange(len(pcm)), pcm, right=0.)
        # Pad the edit so filtering cannot wrap the tail onto the attack.
        padded = 2 * len(clip)
        hz = np.fft.rfftfreq(padded, 1 / RATE)
        band = (1 - np.exp(-(hz / low)**2)) / (1 + (hz / high)**4)
        clip = np.fft.irfft(np.fft.rfft(clip, padded) * band, padded)[:len(clip)]
        clip *= np.exp(-np.arange(len(clip)) / (RATE * decay))
        edge = round(.002 * RATE)
        tail = round(.025 * RATE)
        clip[:edge] *= np.linspace(0, 1, edge)
        clip[-tail:] *= np.linspace(1, 0, tail)
        return clip / max(np.abs(clip).max(), 1e-6)

    for i, speed in enumerate((1., .97, 1.025)):
        mix = np.zeros(round(.49 * RATE))
        def add(clip, onset, gain):
            start = round(onset * RATE)
            mix[start:start + len(clip)] += gain * clip

        add(cut("bow_draw_creak", .07 + i*.025, .082, .94*speed, 360, 3700, .16), 0, .28)
        add(cut("guard_break", .0, .108, 1.13*speed, 590, 6400, .048), .058, .80)
        body = ("land_thud", "land_thud_v2", "land_thud")[i]
        add(cut(body, (.17, .12, .19)[i], .30, .79*speed, 58, 820, .115), .094 + i*.003, .65)
        add(cut("dodge_roll", .52 + i*.035, .22, .84*speed, 500, 2600, .09), .205, .12)
        export(("break_guard", "break_guard_2", "break_guard_3")[i], mix, .73)


def combat_foley(export):
    guard_break_foley(export)
    board = "combat/spear_impact_01 combat/spear_impact_02"
    body = "combat/land_thud combat/land_thud_v2"
    stone = "movement/footstep_stone_01 movement/footstep_stone_02 movement/footstep_stone_03"
    grass = "movement/footstep_grass_01 movement/footstep_grass_02 movement/footstep_grass_03"
    cues = {
        "bow_draw": (.25,.33,[layer("combat/bow_draw_creak combat/bow_hold_strain combat/bow_draw_creak")]),
        "arrow": (.23,.62,[layer("combat/bow_release_single"), layer(board,.16,.008)]),
        "arrow_hit": (.23,.70,[layer("combat/arrow_impact_01 combat/arrow_impact_02 combat/arrow_impact_03",.61), layer(body,.76,.007)]),
        "swing": (.19,.46,[layer("combat/javelin_throw_whoosh")]),
        "spear_hit": (.25,.75,[layer(body,.83),layer(board,.51,.009),layer("combat/guard_raise",.12,.018)]),
        "shield_hit": (.38,.79,[layer("combat/shield_bash combat/shield_bash_v2"),layer(board,.45,.004)]),
        "guard": (.35,.66,[layer("combat/shield_block combat/perfect_guard"),layer(board,.21)]),
        "bite": (.24,.67,[layer("wildlife/wolf_bite_snap"),layer(body,.25,.009)]),
        "wolf_breath": (.22,.44,[layer("wildlife/wolf_snarl_bark")]),
        "hit": (.27,.68,[layer(body),layer("combat/dodge_roll",.3,.008)]),
        "step": (.25,.48,[layer(stone),layer(grass,.22,.015)]),
        "splash": (.29,.46,[layer("mud"),layer(grass,.14,.012)]),
        "paw": (.19,.35,[layer(grass)]),
        "warning": (.70,.58,[layer("alerts/enemy_spotted_horn")]),
    }
    for name, (duration, peak, layers) in cues.items():
        for take, speed in enumerate([1., .959, 1.046][:1 if name == "warning" else 3]):
            mix = np.zeros(round(RATE * duration))
            for names, gain, delay in layers:
                raw = recording(names[take % len(names)])
                if name in {"arrow", "arrow_hit", "spear_hit", "hit", "shield_hit", "guard"}:
                    # Isolate one contact from a longer performance. Anchor the first
                    # strong transient to the animation and retain a little pre-attack.
                    window = np.abs(raw[:round(RATE * duration)])
                    attack = np.flatnonzero(window >= window.max() * .67)[0]
                    raw = raw[max(0, attack - round(.008 * RATE)):]
                start = round(delay * RATE)
                count = min(len(mix)-start, int(len(raw)/speed))
                part = np.interp(np.arange(count)*speed, np.arange(len(raw)), raw)
                # A short fade on each edit retains its original attack and natural tail.
                release = min(count // 3, round(RATE * .032))
                part[-release:] *= np.linspace(1, 0, release)
                mix[start:start+count] += part * gain
            mix[:44] *= np.linspace(0, 1, 44)
            export(name + ("" if take == 0 else "_" + str(take+1)), mix, peak)

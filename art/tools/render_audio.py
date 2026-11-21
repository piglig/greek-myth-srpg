"""Render Pandora's score and foley with numpy and FFmpeg (imageio-ffmpeg)."""
from pathlib import Path
import subprocess
from combat_foley import combat_foley
import numpy as np
import imageio_ffmpeg

DEST = Path(__file__).resolve().parents[2] / "prototype/audio"
DEST.mkdir(exist_ok=True)
SR = 44100
TAU = 2 * np.pi
rng = np.random.default_rng(418)


def timeline(seconds):
    return np.arange(round(seconds * SR)) / SR


def export(name, signal, peak, music=False):
    signal = np.asarray(signal, dtype=float)
    signal *= peak / max(1e-6, np.abs(signal).max())
    channels = 1 if signal.ndim == 1 else signal.shape[1]
    output = DEST / (name + (".ogg" if music else ".wav"))
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-loglevel", "error", "-y",
                    "-f", "f32le", "-ar", str(SR), "-ac", str(channels), "-i", "-",
                    *(["-c:a", "libvorbis", "-q:a", "5"] if music else ["-c:a", "pcm_s16le"]),
                    str(output)], input=signal.astype("<f4").tobytes(), check=True)


def noise(t, width):
    # Smoothed and differentiated layers supply skin, gut-string and grit transients.
    raw = rng.normal(size=len(t) + width - 1)
    return np.convolve(raw, np.ones(width) / np.sqrt(width), "valid")


def string(note, velocity=1.0):
    freq = 440 * 2 ** ((note - 69) / 12)
    t = timeline(2.7)
    sound = np.zeros(len(t))
    pick = rng.uniform(.15, .21)
    for harmonic in range(1, 15):
        phase = TAU * freq * harmonic * (1 + .000013 * harmonic ** 2) * t
        tone = np.sin(phase) + .28 * np.sin(phase * 1.0012)
        sound += (np.sin(np.pi * harmonic * pick) / harmonic ** 1.45
                  * np.exp(-t * (1.7 + .65 * harmonic)) * tone)
    sound += .045 * noise(t, 7) * np.exp(-t * 145)
    return velocity * sound * (1 - np.exp(-t * 650)) * np.minimum(1, (2.7 - t) * 15)


def drum(low=True):
    t = timeline(.58)
    base = 83 if low else 172
    skin = np.sin(TAU * (base * t + 1.2 * (1 - np.exp(-t * 29))))
    rim = .38 * np.sin(TAU * base * 1.58 * t) * np.exp(-t * 15)
    return (skin * np.exp(-t * 13) + rim + noise(t, 7) * .21 * np.exp(-t * 59)) * (1 - np.exp(-t * 700))


def place(mix, at, sample, pan):
    # Fold tails into the start of the next cycle for a continuous room return.
    first = round(at * SR) % len(mix)
    stereo = sample[:, None] * np.sqrt([(1 - pan) / 2, (1 + pan) / 2])
    count = min(len(sample), len(mix) - first)
    mix[first:first + count] += stereo[:count]
    mix[:len(sample) - count] += stereo[count:]


# Chinasaur's public-domain notation of the ancient melody:
# https://commons.wikimedia.org/wiki/File:Seikilos_score.png
MELODY = [
    [(69,1),(76,2),(76,3)], [(73,1),(74,1),(76,1),(74,3)],
    [(73,2),(74,1),(76,1),(74,1),(73,1)], [(71,1),(69,2),(71,1),(67,2)],
    [(69,1),(73,1),(76,1),(74,1),(73,1),(74,1)], [(73,1),(69,2),(71,1),(67,2)],
    [(69,1),(73,1),(71,1),(74,1),(76,1),(73,1)], [(69,1),(69,2),(69,1),(66,1),(64,1)]
]


def score(battle):
    tick = .294 if battle else .453
    bars = 24 if battle else 16
    mix = np.zeros((round(bars * 6 * tick * SR), 2))
    for bar in range(bars):
        start = 6 * bar * tick
        root = ([50,50,48,53,50,46,48,45] if battle else [45,50,45,43,50,43,45,45])[bar % 8]
        place(mix, start, string(root, .77), -.28)
        place(mix, start + tick * 3.05, string(root + 7, .44), .25)
        if battle:
            # Three eight-bar phrases: call, rising answer, then octave descent.
            pattern = ([0,7,12,10], [7,10,15,12], [12,7,5,3])[bar // 8]
            for index, beat in enumerate([0,2,3.5,5]):
                if index == 3 and bar % 4 == 3:
                    continue
                place(mix, start + beat*tick + .012, string(root + pattern[index], .68), .19)
            for beat, gain in [(0,.85),(3,.52),(4.5,.32)]:
                place(mix, start + beat*tick, drum(beat != 3)*gain, -.14)
            if bar % 4 == 3:
                place(mix, start + 5.5*tick, drum(False)*.42, .34)
        else:
            beat = 0
            for note, length in MELODY[bar % 8]:
                place(mix, start + tick * beat + rng.uniform(.012,.025),
                      string(note - (12 if bar < 8 else 0), rng.uniform(.81,1.04)), .08)
                beat += length
            if bar >= 8:
                place(mix, start + 4.55*tick, string(root + 12,.31), -.4)
    dry = mix.copy()
    for delay, gain in [(.041,.16),(.078,.105),(.124,.083),(.211,.053),(.346,.033)]:
        mix += np.roll(dry[:, ::-1], round(delay*SR), axis=0) * gain
    export("ridge" if battle else "jar", np.tanh(mix * .94), .82, True)


def foley():
    t = timeline(.9)
    def ring(freq, decay):
        return np.sin(TAU * freq * t) * np.exp(-t * decay)
    def save(name, sound, peak):
        export(name, sound * (1 - np.exp(-t*1200)) * np.minimum(1, (.9-t)*50), peak)
    clay = ring(732,29) + .56*ring(1211,39) + .19*ring(1933,48)
    save("focus", clay + .12*noise(t,8)*np.exp(-t*100), .23)
    save("confirm", .62*clay + np.roll(ring(958,19),round(SR*.049)), .40)
    for name, notes in [("victory",[57,64,69]),("defeat",[57,53,50])]:
        phrase = np.zeros((SR*4,2))
        for i,note in enumerate(notes):
            place(phrase,i*.32,string(note),i*.2-.2)
        export(name,phrase,.68)


if __name__ == "__main__":
    score(False)
    score(True)
    foley()
    combat_foley(export)

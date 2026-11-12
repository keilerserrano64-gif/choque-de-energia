"""Reproducible provisional Madara Edo ultimate audio; standard library only."""

import math
from pathlib import Path
import random
import time

import gen_intro_audio as intro
from gen_intro_audio import RATE, TAU, add_strings, add_taiko, envelope, smooth


OUTPUT = Path(__file__).resolve().parents[1] / "assets/ultimates/madara_edo/audio"
D_MINOR = (73.4162, 87.3071, 110.0)


class LowPass:
    def __init__(self, cutoff):
        self.alpha = 1.0 - math.exp(-TAU * cutoff / RATE)
        self.value = 0.0

    def step(self, value):
        self.value += self.alpha * (value - self.value)
        return self.value


class BandPass:
    """Constant-peak RBJ biquad, used as a simple vocal formant."""

    def __init__(self, frequency, q=4.0):
        omega = TAU * frequency / RATE
        alpha = math.sin(omega) / (2.0 * q)
        self.b0 = alpha / (1.0 + alpha)
        self.a1 = -2.0 * math.cos(omega) / (1.0 + alpha)
        self.a2 = (1.0 - alpha) / (1.0 + alpha)
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def step(self, value):
        result = self.b0 * (value - self.x2) - self.a1 * self.y1 - self.a2 * self.y2
        self.x2, self.x1 = self.x1, value
        self.y2, self.y1 = self.y1, result
        return result


def blank(duration):
    return [0.0] * round(duration * RATE)


def echo(samples, taps):
    """Feed-forward echoes; never propagate or extend past the requested length."""
    dry = samples[:]
    for delay, gain in taps:
        offset = round(delay * RATE)
        for i in range(offset, len(samples)):
            samples[i] += gain * dry[i - offset]


def save(name, samples, attack=0.01, release=0.06):
    intro.write_wav(name + ".wav", samples, attack, release)


def amenaza():
    samples = blank(2.0)
    noise = LowPass(110.0)
    phase = 0.0
    for i in range(len(samples)):
        t = i / RATE
        rise = t / 2.0
        phase += TAU * (40.0 + 15.0 * rise) / RATE
        drone = math.sin(phase) + 0.25 * math.sin(2.01 * phase)
        samples[i] = (0.6 * drone + 2.4 * noise.step(random.uniform(-1, 1))) * (
            0.25 + 0.75 * rise
        )
    save("amenaza", samples, 0.15, 0.18)


def susanoo():
    samples = blank(3.5)
    add_strings(samples, 0.0, 3.5, D_MINOR, 1.0, 2.7, 0.4)
    f1, f2 = BandPass(420, 2.0), BandPass(900, 3.0)
    phase = 0.0
    air = LowPass(1300)
    for i in range(len(samples)):
        t = i / RATE
        choir = 2.5 * f1.step(samples[i]) + 1.8 * f2.step(samples[i])
        phase += TAU * (52.0 + 24.0 * smooth(t / 3.5)) / RATE
        energy = 0.24 * math.sin(phase) + 0.11 * math.sin(3.02 * phase)
        energy += 0.45 * air.step(random.uniform(-1, 1))
        samples[i] = 0.5 * samples[i] + choir + energy * smooth(t / 2.8)
    echo(samples, ((0.13, 0.25), (0.29, 0.16), (0.43, 0.08)))
    save("susanoo", samples, 0.16, 0.5)


def espada_alza():
    samples = blank(1.5)
    phase = 0.0
    air = LowPass(2400)
    for i in range(len(samples)):
        t = i / RATE
        rise = t / 1.5
        phase += TAU * (85.0 + 510.0 * rise ** 1.7) / RATE
        buzz = math.sin(phase) + 0.35 * math.sin(2.01 * phase)
        buzz += 0.2 * math.sin(4.0 * phase) + 0.8 * air.step(random.uniform(-1, 1))
        samples[i] = buzz * (0.15 + 0.85 * rise)
    save("espada_alza", samples, 0.09, 0.12)


def espada_tajo():
    samples = blank(1.0)
    noise = 0.0
    phase = 0.0
    for i in range(len(samples)):
        t = i / RATE
        cutoff = 180.0 + 11500.0 * math.exp(-38.0 * t)
        alpha = 1.0 - math.exp(-TAU * cutoff / RATE)
        noise += alpha * (random.uniform(-1, 1) - noise)
        sweep = 2.2 * noise * math.exp(-28.0 * t) * smooth(t / 0.002)
        u = max(0.0, t - 0.055)
        phase += TAU * (35.0 + 95.0 * math.exp(-28.0 * u)) / RATE
        impact = math.sin(phase) * math.exp(-6.5 * u) * smooth(u / 0.005)
        samples[i] = sweep + 1.6 * impact
    echo(samples, ((0.073, 0.32), (0.149, 0.22), (0.241, 0.14), (0.367, 0.08)))
    save("espada_tajo", samples, 0.002, 0.2)


def risa():
    samples = blank(3.0)
    # Six progressively closer, shorter "ha" syllables, with pitch falling per ha.
    syllables = ((0.08, 0.38), (0.62, 0.34), (1.10, 0.30),
                 (1.52, 0.27), (1.88, 0.24), (2.18, 0.22))
    f1, f2 = BandPass(700, 3.8), BandPass(1200, 4.5)
    breath = LowPass(3500)
    phase = 0.0
    for i in range(len(samples)):
        t = i / RATE
        gain = pitch = 0.0
        for start, duration in syllables:
            u = t - start
            if 0 <= u < duration:
                gain = envelope(u, duration, 0.028, 0.12)
                gain *= 0.95 - 0.35 * u / duration
                pitch = 109.0 - 13.0 * u / duration
                break
        phase = (phase + (pitch or 98.0) / RATE) % 1.0
        # Asymmetric glottal pulse: rich harmonics excite both vowel resonances.
        glottal = 2.0 * phase - 1.0
        glottal += 0.5 * math.sin(TAU * phase)
        air = breath.step(random.uniform(-1, 1))
        source = gain * (glottal + 0.32 * air)
        vowel = 3.2 * f1.step(source) + 2.4 * f2.step(source)
        chest = 0.22 * gain * math.sin(TAU * phase)
        samples[i] = vowel + chest + 0.09 * gain * air
    echo(samples, ((0.095, 0.27), (0.19, 0.12), (0.285, 0.06)))
    save("risa", samples, 0.02, 0.25)


def cielo():
    samples = blank(3.0)
    noise = LowPass(95)
    phase = 0.0
    for i in range(len(samples)):
        t = i / RATE
        phase += TAU * (32.0 + 6.0 * math.sin(TAU * 0.23 * t)) / RATE
        rumble = (0.65 + 0.35 * math.sin(TAU * 0.72 * t)) * math.sin(phase)
        samples[i] = (3.0 * noise.step(random.uniform(-1, 1)) + 0.55 * rumble) * (
            0.2 + 0.8 * smooth(t / 2.5)
        )
    save("cielo", samples, 0.65, 0.5)


def meteoro_cae():
    samples = blank(2.5)
    phase = noise = 0.0
    whistle = BandPass(1600, 1.5)
    for i in range(len(samples)):
        t = i / RATE
        rise = t / 2.5
        phase += TAU * (95.0 + 850.0 * rise ** 2) / RATE
        alpha = 1.0 - math.exp(-TAU * (180 + 5200 * rise ** 2) / RATE)
        raw = random.uniform(-1, 1)
        noise += alpha * (raw - noise)
        howl = math.sin(phase) + 0.22 * math.sin(2.03 * phase)
        samples[i] = (0.45 * howl + 1.8 * noise + 0.5 * whistle.step(raw)) * (
            0.04 + 0.96 * rise ** 1.8
        )
    save("meteoro_cae", samples, 0.15, 0.065)


def explosion(name, duration, huge=False):
    samples = blank(duration)
    noise, debris = LowPass(2600), LowPass(850)
    phase = second = 0.0
    for i in range(len(samples)):
        t = i / RATE
        phase += TAU * (34 + 105 * math.exp(-23 * t)) / RATE
        hit = 1.6 * math.sin(phase) * math.exp(-(2.1 if huge else 3.8) * t)
        wash = noise.step(random.uniform(-1, 1)) * 2.2 * math.exp(-2.7 * t)
        rubble = debris.step(random.uniform(-1, 1))
        rubble *= (0.5 + 0.5 * math.sin(TAU * 17.3 * t)) ** 6
        rubble *= 1.8 * math.exp(-1.8 * t) * smooth(t / 0.12)
        if huge:
            u = max(0.0, t - 0.13)
            second += TAU * (42 + 75 * math.exp(-20 * u)) / RATE
            hit += 1.2 * math.sin(second) * math.exp(-2.0 * u) * smooth(u / 0.006)
            hit += 0.85 * math.sin(TAU * 30 * t) * math.exp(-1.25 * t)
        samples[i] = (hit + wash + rubble) * smooth(t / 0.004)
    echo(samples, ((0.117, 0.23), (0.263, 0.16), (0.419, 0.09)))
    save(name, samples, 0.004, 0.5 if huge else 0.35)


def music():
    samples = blank(25.0)
    for i in range(len(samples)):
        t = i / RATE
        gain = 0.035
        if 2 <= t < 10:
            gain = 0.05 + 0.06 * smooth((t - 2) / 7)
        elif 10 <= t < 13:
            gain = 0.009
        elif 13 <= t < 19:
            gain = 0.03 + 0.07 * smooth((t - 13) / 6)
        elif t >= 19.6:
            gain = 0.13
        drone = math.sin(TAU * D_MINOR[0] * t)
        drone += 0.55 * math.sin(TAU * 36.7081 * t)
        samples[i] = gain * drone

    add_strings(samples, 2, 4, D_MINOR, 0.65, 3.3, 0.4)
    add_strings(samples, 6, 4, (116.5409, 146.8324, 174.6141), 0.85, 1.5, 0.5)
    add_strings(samples, 9, 1, D_MINOR, 1.1, 0.025, 0.85)
    for start in (6.0, 7.0, 8.0, 8.5, 9.0):
        add_taiko(samples, start, 0.55 if start < 9 else 1.8, 0.95)

    add_strings(samples, 13, 6, D_MINOR, 0.75, 5.0, 0.18)
    for index, start in enumerate((13.0, 14.5, 16.0, 17.5, 18.25)):
        add_taiko(samples, start, 0.3 + 0.17 * index, min(0.75, 19.0 - start))

    add_strings(samples, 19.6, 5.4, (146.8324, 174.6141, 220.0), 1.4, 0.13, 1.0)
    add_strings(samples, 21, 4, D_MINOR, 0.9, 0.05, 0.9)
    for start, strength in ((19.6, 1.25), (20.3, 0.8), (21, 2.0),
                            (21.7, 0.85), (22.4, 1.0), (23, 2.4)):
        add_taiko(samples, start, strength, min(1.8, 25.0 - start))
    for start in (9.0, 21.0, 23.0):
        first = round(start * RATE)
        count = min(round(1.0 * RATE), len(samples) - first)
        noise = LowPass(900)
        for i in range(count):
            t = i / RATE
            raw = random.uniform(-1, 1)
            cymbal = raw - noise.step(raw)
            samples[first + i] += 0.3 * cymbal * math.exp(-4 * t) * envelope(
                t, count / RATE, 0.005, 0.3
            )

    # Fade every layer before the two scene cuts, then enforce digital silence.
    for i in range(len(samples)):
        t = i / RATE
        if 9.85 <= t < 10:
            samples[i] *= smooth((10 - t) / 0.15)
        elif 10 <= t < 10.08:
            samples[i] *= smooth((t - 10) / 0.08)
        if 18.85 <= t < 19:
            samples[i] *= smooth((19 - t) / 0.15)
        elif 19 <= t < 19.6:
            samples[i] = 0.0
        elif 19.6 <= t < 19.63:
            samples[i] *= smooth((t - 19.6) / 0.03)
    save("musica_definitivo", samples, 0.5, 1.0)


def main():
    random.seed(170047)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    intro.OUTPUT = OUTPUT
    started = time.perf_counter()
    for generate in (amenaza, susanoo, espada_alza, espada_tajo, risa, cielo, meteoro_cae):
        generate()
    explosion("explosion1", 2.0)
    explosion("explosion2", 3.0, huge=True)
    music()
    print(f"Total: {time.perf_counter() - started:.2f} s", flush=True)


if __name__ == "__main__":
    main()

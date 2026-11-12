"""Reproducible provisional Madara Edo intro audio; Python standard library only."""

import math
from pathlib import Path
import random
import struct
import time
import wave


RATE = 44100
TAU = 2.0 * math.pi
PEAK = 10.0 ** (-1.0 / 20.0)
OUTPUT = Path(__file__).resolve().parents[1] / "assets/intros/madara_edo/audio"


def smooth(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def envelope(t, duration, attack=0.01, release=0.02):
    return smooth(t / attack) * smooth((duration - t) / release)


def write_wav(name, samples, attack=0.01, release=0.02):
    """Fade first, then peak-normalize without clipping or limiting."""
    duration = len(samples) / RATE
    last = len(samples) - 1
    for i in range(len(samples)):
        samples[i] *= smooth(i / (RATE * attack)) * smooth(
            (last - i) / (RATE * release)
        )
    peak = max(abs(value) for value in samples)
    scale = PEAK * 32767.0 / peak if peak else 0.0
    pcm = bytearray(2 * len(samples))
    for i, value in enumerate(samples):
        struct.pack_into("<h", pcm, 2 * i, round(value * scale))
    with wave.open(str(OUTPUT / name), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm)
    print(f"{name}: {duration:.1f} s", flush=True)


def wind():
    samples = []
    low = 0.0
    for i in range(4 * RATE):
        t = i / RATE
        cutoff = 420.0 + 240.0 * math.sin(TAU * 0.31 * t)
        alpha = 1.0 - math.exp(-TAU * cutoff / RATE)
        low += alpha * (random.uniform(-1.0, 1.0) - low)
        gust = 0.58 + 0.25 * math.sin(TAU * 0.61 * t - 0.9)
        gust += 0.12 * math.sin(TAU * 1.13 * t)
        samples.append(low * gust)
    write_wav("viento.wav", samples, 0.8, 0.6)


def smoke():
    samples = []
    low = phase = 0.0
    alpha = 1.0 - math.exp(-TAU * 1700.0 / RATE)
    for i in range(round(1.6 * RATE)):
        t = i / RATE
        low += alpha * (random.uniform(-1.0, 1.0) - low)
        breath = math.sin(math.pi * t / 1.6) ** 1.8
        phase += TAU * (40.0 + 15.0 * math.exp(-9.0 * t)) / RATE
        thump = math.sin(phase) * math.exp(-8.0 * t) * smooth(t / 0.008)
        samples.append(0.85 * low * breath + 0.65 * thump)
    write_wav("humo.wav", samples)


def sharingan():
    samples = []
    partials = ((1870.0, 1.0, 3.2), (2630.0, 0.65, 4.6),
                (3510.0, 0.42, 5.8), (4870.0, 0.28, 7.5))
    for i in range(round(1.3 * RATE)):
        t = i / RATE
        metal = sum(amp * math.sin(TAU * freq * t) * math.exp(-decay * t)
                    for freq, amp, decay in partials)
        metal *= smooth(t / 0.018)
        dun = math.sin(TAU * 70.0 * t) * math.exp(-15.0 * t)
        samples.append(0.25 * metal + 0.8 * dun * smooth(t / 0.006))
    write_wav("sharingan.wav", samples)


def chakra():
    samples = []
    phase = low = burst_low = 0.0
    for i in range(3 * RATE):
        t = i / RATE
        rise = min(t / 2.7, 1.0)
        phase = (phase + (60.0 + 60.0 * rise) / RATE) % 1.0
        alpha = 1.0 - math.exp(-TAU * (160.0 + 3200.0 * rise ** 2) / RATE)
        raw = 0.45 * (2.0 * phase - 1.0) + 0.55 * random.uniform(-1.0, 1.0)
        low += alpha * (raw - low)
        tremolo = 0.72 + 0.28 * math.sin(TAU * (2.0 * t + 2.6 * t * t))
        body = low * tremolo * (0.12 + 0.88 * rise ** 1.5)
        body *= smooth(t / 0.15) * (1.0 - smooth((t - 2.7) / 0.25))
        burst_low += 0.42 * (random.uniform(-1.0, 1.0) - burst_low)
        if t >= 2.7:
            u = t - 2.7
            burst = (1.6 * burst_low + 0.7 * math.sin(TAU * 48.0 * u))
            body += burst * math.exp(-12.0 * u) * smooth(u / 0.006)
        samples.append(body)
    write_wav("chakra.wav", samples)


def shockwave():
    samples = []
    low = phase = 0.0
    for i in range(round(0.9 * RATE)):
        t = i / RATE
        phase += TAU * (38.0 + 55.0 * math.exp(-16.0 * t)) / RATE
        low += 0.22 * (random.uniform(-1.0, 1.0) - low)
        samples.append((math.sin(phase) * math.exp(-7.0 * t)
                        + 1.3 * low * math.exp(-12.0 * t)) * smooth(t / 0.006))
    write_wav("onda.wav", samples)


def add_taiko(samples, start, strength=1.0, duration=0.75):
    phase = 0.0
    first = round(start * RATE)
    count = min(round(duration * RATE), len(samples) - first)
    for i in range(count):
        t = i / RATE
        phase += TAU * (43.0 + 105.0 * math.exp(-20.0 * t)) / RATE
        tone = math.sin(phase) + 0.19 * math.sin(2.37 * phase) * math.exp(-9.0 * t)
        click = random.uniform(-1.0, 1.0) * 0.4 * math.exp(-65.0 * t)
        samples[first + i] += strength * (tone * math.exp(-6.0 * t) + click) * envelope(
            t, duration, 0.006, 0.04
        )


def add_strings(samples, start, duration, notes, level, attack, release):
    """Pairs of detuned saws with independent phases, softened by a one-pole LPF."""
    frequencies = [note * detune for note in notes for detune in (0.997, 1.003)]
    phases = [random.random() for _ in frequencies]
    low = 0.0
    first = round(start * RATE)
    count = min(round(duration * RATE), len(samples) - first)
    for i in range(count):
        t = i / RATE
        raw = 0.0
        for j, freq in enumerate(frequencies):
            phases[j] = (phases[j] + freq / RATE) % 1.0
            raw += 2.0 * phases[j] - 1.0
        cutoff = 650.0 + 1300.0 * smooth(t / max(attack, 0.01))
        alpha = 1.0 - math.exp(-TAU * cutoff / RATE)
        low += alpha * (raw / len(frequencies) - low)
        samples[first + i] += level * low * envelope(t, duration, attack, release)


def music():
    samples = []
    for i in range(12 * RATE):
        t = i / RATE
        # D2 + A2: barely audible initially, growing beneath the percussion.
        gain = 0.012 + 0.075 * smooth((t - 1.8) / 6.5)
        drone = math.sin(TAU * 73.4162 * t) + 0.65 * math.sin(TAU * 110.0 * t)
        samples.append(gain * drone * envelope(t, 12.0, 1.1, 2.8))

    beat = 60.0 / 70.0
    hit = 2.0
    while hit < 6.0:
        add_taiko(samples, hit, 0.25 + 0.055 * (hit - 2.0))
        hit += beat

    # Continuous phase acceleration: quarter notes at 6 s to sixteenths at 9 s.
    # Integral of event rate is r * (u + u*u/2), with r = 70/60.
    event = 0
    while True:
        u = -1.0 + math.sqrt(1.0 + 2.0 * event / (70.0 / 60.0))
        if u >= 3.0:
            break
        accent = 1.0 if event % 4 == 0 else 0.62
        add_taiko(samples, 6.0 + u, accent * (0.36 + 0.14 * u), 0.55)
        event += 1

    add_strings(samples, 6.0, 1.85, (146.8324, 174.6141, 220.0), 0.5, 1.5, 0.3)
    add_strings(samples, 7.5, 1.9, (116.5409, 146.8324, 174.6141), 0.8, 1.3, 0.4)
    add_strings(samples, 9.0, 3.0, (146.8324, 174.6141, 220.0), 0.9, 0.09, 2.7)
    add_taiko(samples, 9.0, 1.55, 2.5)

    # Broad, bright noise cymbal on the final impact, fading to exact silence.
    low = 0.0
    for i in range(3 * RATE):
        t = i / RATE
        noise = random.uniform(-1.0, 1.0)
        low += 0.12 * (noise - low)
        cymbal = noise - low
        samples[9 * RATE + i] += 0.55 * cymbal * math.exp(-2.1 * t) * envelope(
            t, 3.0, 0.008, 1.5
        )
    write_wav("musica_intro.wav", samples)


def main():
    random.seed(140047)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    for generate in (wind, smoke, sharingan, chakra, shockwave, music):
        generate()
    print(f"Total: {time.perf_counter() - started:.2f} s", flush=True)


if __name__ == "__main__":
    main()

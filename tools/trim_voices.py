"""Recorta el silencio de las voces generadas, las normaliza y les pone un fundido corto.

Uso (desde la carpeta del proyecto): python tools/trim_voices.py
Solo usa la biblioteca estándar de Python.
"""
import array
import pathlib
import wave

ROOT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "voices"
THRESHOLD = 600  # amplitud (de 32767) por debajo de la cual se considera silencio
PAD = 0.015  # segundos de margen que se dejan antes y después
FADE = 0.012  # segundos de fundido de entrada y salida
PEAK = 0.92  # pico tras normalizar


def process(path: pathlib.Path) -> None:
    with wave.open(str(path), "rb") as src:
        params = src.getparams()
        frames = src.readframes(params.nframes)
    if params.sampwidth != 2:
        print("Omitido (no es PCM de 16 bits):", path)
        return
    samples = array.array("h", frames)
    channels = params.nchannels
    rate = params.framerate
    count = len(samples) // channels
    loud = [i for i in range(count) if max(abs(samples[i * channels + c]) for c in range(channels)) > THRESHOLD]
    if not loud:
        return
    pad = int(PAD * rate)
    start = max(0, loud[0] - pad)
    end = min(count, loud[-1] + pad)
    trimmed = samples[start * channels:end * channels]
    peak = max(1, max(abs(s) for s in trimmed))
    gain = min(4.0, PEAK * 32767 / peak)
    fade = max(1, int(FADE * rate))
    total = len(trimmed) // channels
    out = array.array("h", [0]) * len(trimmed)
    for i in range(total):
        env = 1.0
        if i < fade:
            env = i / fade
        elif i > total - fade:
            env = max(0.0, (total - i) / fade)
        for c in range(channels):
            value = int(trimmed[i * channels + c] * gain * env)
            out[i * channels + c] = max(-32768, min(32767, value))
    with wave.open(str(path), "wb") as dst:
        dst.setnchannels(channels)
        dst.setsampwidth(2)
        dst.setframerate(rate)
        dst.writeframes(out.tobytes())


def main() -> None:
    files = sorted(ROOT.glob("*/*.wav"))
    for path in files:
        process(path)
    print("Recortadas", len(files), "voces")


if __name__ == "__main__":
    main()

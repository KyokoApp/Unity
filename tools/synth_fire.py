#!/usr/bin/env python3
"""Sintesis SFX api prosedural, 22050 Hz mono 16-bit, tanpa numpy.

Menghasilkan fire_loop.wav (loop 6 detik, tetap deterministik/identik),
fire_shoot.wav (0,5 detik), dan fire_explode.wav (1,8 detik). Setiap suara
memakai PRNG terpisah agar penambahan suara tak pernah mengubah fire_loop.wav.
"""
import math
import random
import struct
import wave
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "project/packs/audio_sfx"
SR, L, XF = 22050, 6.0, 0.5


def write_wav(path: Path, samples: list[float], peak: float = 0.85) -> None:
    gain = peak / max(1e-9, max(abs(v) for v in samples))
    pcm = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, value * gain)) * 32767))
        for value in samples
    )
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SR)
        wav.writeframes(pcm)
    print(f"ok -> {path} ({len(samples)} sampel)")


def synth_loop() -> list[float]:
    # Seed dan urutan panggilan PRNG sengaja sama dengan versi Ronde-37.
    rng = random.Random(7)
    n_all = int((L + XF) * SR)
    out = [0.0] * n_all
    brown = low = 0.0
    for i in range(n_all):
        brown = brown * 0.995 + rng.uniform(-1, 1) * 0.06
        low += (brown - low) * 0.05
        out[i] += low * 1.4
    white_prev = high = low2 = 0.0
    for i in range(n_all):
        white = rng.uniform(-1, 1)
        high = 0.97 * (high + white - white_prev)
        white_prev = white
        low2 += (high - low2) * 0.35
        t = i / SR
        mod = 0.55 + 0.25 * math.sin(t * 2 * math.pi * 0.37) + 0.2 * math.sin(t * 2 * math.pi * 1.13 + 1.0)
        out[i] += low2 * 0.10 * mod
    t = 0.0
    while t < L + XF:
        t += rng.expovariate(16.0)
        start = int(t * SR)
        big = rng.random() < 0.08
        amp = rng.uniform(0.15, 0.45) * (2.2 if big else 1.0)
        dur = int(SR * rng.uniform(0.002, 0.009) * (3 if big else 1))
        tau = dur / 3.0
        for k in range(dur * 3):
            j = start + k
            if j >= n_all:
                break
            out[j] += rng.uniform(-1, 1) * amp * math.exp(-k / tau)
    n, crossfade = int(L * SR), int(XF * SR)
    result = out[:n]
    for k in range(crossfade):
        alpha = k / crossfade
        result[k] = result[k] * alpha + out[n + k] * (1 - alpha)
    return result


def synth_shoot() -> list[float]:
    rng = random.Random(3801)
    duration = 0.5
    n = int(duration * SR)
    out = [0.0] * n
    low = high = previous = 0.0
    phase = 0.0
    for i in range(n):
        t = i / SR
        x = t / duration
        envelope = math.exp(-7.0 * t) * min(1.0, t / 0.006)
        # cutoff menyapu cepat naik, lalu turun panjang.
        sweep = x / 0.18 if x < 0.18 else max(0.0, 1.0 - (x - 0.18) / 0.82)
        cutoff = 250.0 + 6400.0 * sweep
        alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / SR)
        white = rng.uniform(-1.0, 1.0)
        low += (white - low) * alpha
        high = 0.94 * (high + low - previous)
        previous = low
        freq = 140.0 + (55.0 - 140.0) * x
        phase += 2.0 * math.pi * freq / SR
        boom = math.sin(phase) * math.exp(-10.0 * t)
        pop = rng.uniform(-1, 1) * math.exp(-150.0 * abs(t - 0.025))
        out[i] = high * envelope * 0.72 + boom * 0.58 + pop * 0.22
    return out


def synth_explode() -> list[float]:
    rng = random.Random(3802)
    duration = 1.8
    n = int(duration * SR)
    out = [0.0] * n
    brown = low = 0.0
    phase = 0.0
    crack_times = [0.012, 0.031, 0.067, 0.12, 0.21, 0.34, 0.51, 0.73, 0.96, 1.22]
    crack_amps = [rng.uniform(0.15, 0.5) for _ in crack_times]
    for i in range(n):
        t = i / SR
        x = t / duration
        fade = min(1.0, (duration - t) / 0.22)
        freq = 75.0 + (32.0 - 75.0) * math.sqrt(x)
        phase += 2.0 * math.pi * freq / SR
        sub = math.sin(phase) * math.exp(-2.5 * t) * 0.92
        brown = max(-1.6, min(1.6, brown * 0.993 + rng.uniform(-1, 1) * 0.055))
        low += (brown - low) * 0.075
        rumble = low * math.exp(-1.45 * t) * 0.78
        initial = rng.uniform(-1, 1) * math.exp(-65.0 * t) * 1.1
        crackle = 0.0
        for when, amp in zip(crack_times, crack_amps):
            dt = t - when
            if 0.0 <= dt < 0.035:
                crackle += rng.uniform(-1, 1) * amp * math.exp(-95.0 * dt) * math.exp(-1.4 * when)
        out[i] = (sub + rumble + initial + crackle) * fade
    return out


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_wav(OUT_DIR / "fire_loop.wav", synth_loop())
    write_wav(OUT_DIR / "fire_shoot.wav", synth_shoot(), 0.9)
    write_wav(OUT_DIR / "fire_explode.wav", synth_explode(), 0.92)


if __name__ == "__main__":
    main()

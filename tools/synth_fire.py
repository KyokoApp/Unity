#!/usr/bin/env python3
"""Sintesis suara api berderak (loop mulus 6 dtk) -> project/packs/audio_sfx/fire_loop.wav

Murni pustaka standar (tanpa numpy). Tiga lapis:
  1. gemuruh  : brown noise + low-pass
  2. desis    : white noise band-pass, amplitudo berombak pelan
  3. letupan  : burst noise pendek meluruh eksponensial (Poisson ~16/dtk,
                8% letupan besar)
Ekor 0,5 dtk di-crossfade ke kepala -> loop tanpa klik.
Jalankan:  python3 tools/synth_fire.py
"""
import math
import random
import struct
import wave
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "project/packs/audio_sfx/fire_loop.wav"
SR, L, XF = 22050, 6.0, 0.5


def main() -> None:
    random.seed(7)
    n_all = int((L + XF) * SR)
    out = [0.0] * n_all
    b = lp = 0.0
    for i in range(n_all):
        b = b * 0.995 + random.uniform(-1, 1) * 0.06
        lp += (b - lp) * 0.05
        out[i] += lp * 1.4
    hp_prev = hp = lp2 = 0.0
    for i in range(n_all):
        w = random.uniform(-1, 1)
        hp = 0.97 * (hp + w - hp_prev)
        hp_prev = w
        lp2 += (hp - lp2) * 0.35
        t = i / SR
        mod = 0.55 + 0.25 * math.sin(t * 2 * math.pi * 0.37) + 0.2 * math.sin(t * 2 * math.pi * 1.13 + 1.0)
        out[i] += lp2 * 0.10 * mod
    t = 0.0
    while t < L + XF:
        t += random.expovariate(16.0)
        start = int(t * SR)
        big = random.random() < 0.08
        amp = random.uniform(0.15, 0.45) * (2.2 if big else 1.0)
        dur = int(SR * random.uniform(0.002, 0.009) * (3 if big else 1))
        tau = dur / 3.0
        for k in range(dur * 3):
            j = start + k
            if j >= n_all:
                break
            out[j] += random.uniform(-1, 1) * amp * math.exp(-k / tau)
    n, x = int(L * SR), int(XF * SR)
    res = out[:n]
    for k in range(x):
        a = k / x
        res[k] = res[k] * a + out[n + k] * (1 - a)
    g = 0.85 / max(abs(v) for v in res)
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * g)) * 32767)) for v in res))
    print(f"ok -> {OUT} ({n} sampel)")


if __name__ == "__main__":
    main()

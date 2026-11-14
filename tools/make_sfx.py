#!/usr/bin/env python3
# Makes the pickup chimes with a small synth (the bell voice from Keeper of the Hollow's make_audio.py).
# Output: audio/pickup.wav and audio/letter.wav. Needs numpy.
import numpy as np, os, wave
SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
def hz(n): return 440.0 * 2 ** ((n - 69) / 12.0)
def bell(f, dur):
    t = np.arange(int(SR * dur)) / SR
    s = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 5) + 0.2 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 9)
    return s * np.exp(-t * 2.2) * np.minimum(1, t * 600)
def seq(notes, step, dur, g):
    buf = np.zeros(int(SR * (step * len(notes) + dur)))
    for i, n in enumerate(notes):
        s = bell(hz(n), dur); a = int(i * step * SR); buf[a:a + len(s)] += s * g
    return buf
def write(name, buf):
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(buf, -1, 1) * 32000).astype("<i2").tobytes())
write("pickup", seq([72, 76, 79, 84], 0.07, 0.6, 0.4))
write("letter", seq([60, 64, 67, 72, 76, 79, 84], 0.09, 0.9, 0.35))

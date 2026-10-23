#!/usr/bin/env python3
"""Genera la música original de la intro (estilo «phonk» de gimnasio): 808 distorsionado,
cencerro con melodía en menor, bombo, palmas y charles. Todo sintetizado: sin muestras ni
canciones de nadie, así que no hay derechos de autor de terceros.

Uso: python3 tools/make_intro_music.py salida.wav   (luego ffmpeg la pasa a .m4a)
"""
import sys
import wave

import numpy as np

SR = 44100
BPM = 132
BEAT = 60 / BPM
STEP = BEAT / 4          # semicorchea
BARS = 8
LENGTH = BARS * 4 * BEAT + 1.5  # + cola
rng = np.random.default_rng(7)

out = np.zeros(int(LENGTH * SR) + SR)


def add(signal, start):
    i = int(start * SR)
    end = min(len(out), i + len(signal))
    out[i:end] += signal[: end - i]


def t(seconds):
    return np.arange(int(seconds * SR)) / SR


def env(length, attack=0.002, decay=0.2):
    x = t(length)
    a = np.clip(x / attack, 0, 1)
    return a * np.exp(-x / decay)


def lowpass(x, cutoff):
    alpha = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def note(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def kick():
    x = t(0.45)
    freq = 45 + 110 * np.exp(-x / 0.04)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * env(0.45, 0.001, 0.16) * 0.9


def clap():
    n = rng.standard_normal(int(0.25 * SR))
    body = highpass(lowpass(n, 2500), 900)
    e = env(0.25, 0.001, 0.07)
    # tres golpecitos muy juntos, como una palmada real
    for d in (0.0, 0.012, 0.024):
        i = int(d * SR)
        x = np.arange(len(e) - i) / SR
        e[i:] += 0.5 * np.exp(-x / 0.01)
    return body * e * 0.55


def hat(open_=False):
    n = rng.standard_normal(int(0.2 * SR))
    return highpass(n, 7000) * env(0.2, 0.001, 0.09 if open_ else 0.025) * 0.12


def bass808(midi, length):
    x = t(length)
    f = note(midi)
    glide = f * (1 + 0.6 * np.exp(-x / 0.03))
    phase = 2 * np.pi * np.cumsum(glide) / SR
    raw = np.sin(phase) * env(length, 0.003, 0.9)
    return np.tanh(raw * 3.2) * 0.42   # saturación: el 808 «sucio» del phonk


def cowbell(midi, length=0.32):
    f = note(midi)
    x = t(length)
    tone = np.sign(np.sin(2 * np.pi * f * x)) + 0.8 * np.sign(np.sin(2 * np.pi * f * 1.48 * x))
    return lowpass(tone, 4500) * env(length, 0.001, 0.09) * 0.11


def impact():
    x = t(2.2)
    boom = np.sin(2 * np.pi * np.cumsum(32 + 60 * np.exp(-x / 0.25)) / SR) * env(2.2, 0.002, 0.7)
    noise = lowpass(rng.standard_normal(len(x)), 900) * env(2.2, 0.002, 0.35) * 0.5
    return np.tanh((boom + noise) * 1.6) * 0.75


def riser(length):
    x = t(length)
    n = rng.standard_normal(len(x))
    return highpass(n, 2000) * (x / length) ** 2 * 0.25


# Melodía de cencerro en La menor frigio (La, Si bemol, Do, Re, Mi): oscura y tensa.
A, Bb, C, D, E, F, G = 69, 70, 72, 74, 76, 77, 79
melody = [A, A, C, A, Bb, A, G, A, A, A, C, D, E, D, C, Bb]
bass_line = [45, 45, 46, 43]  # La, La, Si bemol, Sol (graves)

# Intro: golpe + subida
add(impact(), 0.0)
add(riser(BEAT * 4), 0.0)

start = BEAT * 4  # el ritmo entra en el compás 2
for bar in range(BARS - 1):
    t0 = start + bar * 4 * BEAT
    for beat in range(4):
        tb = t0 + beat * BEAT
        if beat in (0, 2) or (beat == 3 and bar % 2 == 1):
            add(kick(), tb)
        if beat in (1, 3):
            add(clap(), tb)
    for s in range(16):
        ts = t0 + s * STEP
        # charles en semicorcheas, con redobles (tresillos) al final de cada 2 compases
        if bar % 2 == 1 and s >= 12:
            for k in range(3):
                add(hat(), ts + k * STEP / 3)
        else:
            add(hat(open_=(s % 8 == 6)), ts)
        if s % 2 == 0:
            add(cowbell(melody[(s // 2 + bar * 8) % len(melody)]), ts)
    add(bass808(bass_line[bar % 4], 4 * BEAT * 0.95), t0)

# Final: último golpe para cerrar
add(impact() * 0.8, start + (BARS - 1) * 4 * BEAT)

mix = out[: int(LENGTH * SR)]
mix = np.tanh(mix * 1.0)
mix /= np.max(np.abs(mix)) + 1e-9
mix *= 0.89
fade = int(0.8 * SR)
mix[-fade:] *= np.linspace(1, 0, fade)

pcm = (mix * 32767).astype(np.int16)
with wave.open(sys.argv[1] if len(sys.argv) > 1 else "intro.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print(f"{LENGTH:.1f} s")

#!/usr/bin/env python3
"""Sintetizza la musica (calypso morbido con steel drum) e gli effetti sonori di Manila.

Tutto è generato qui, senza campioni esterni: nessun problema di licenza.
Uso: python3 tools/sintetizza_audio.py   (serve ffmpeg con libvorbis per la musica)
Scrive assets/audio/musica.ogg e assets/audio/*.wav
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(1821)


def note_hz(n):
    """n = numero MIDI."""
    return 440.0 * 2 ** ((n - 69) / 12)


def env_exp(n, attack, tau):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / tau)


def steelpan(freq, dur, vel=1.0):
    """Steel drum: parziali quasi armoniche con decadimento rapido e un leggero battimento."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    parts = [(1.0, 1.0, 0.9), (2.0, 0.55, 0.45), (3.01, 0.28, 0.3), (4.02, 0.12, 0.2), (5.05, 0.05, 0.12)]
    s = np.zeros(n)
    for mult, amp, tau in parts:
        f = freq * mult
        if f > SR / 2.2:
            continue
        s += amp * np.sin(2 * np.pi * f * t + rng.random() * 0.3) * np.exp(-t / tau)
    s += 0.25 * np.sin(2 * np.pi * freq * 1.004 * t) * np.exp(-t / 0.8)   # battimento
    a = np.clip(t / 0.004, 0, 1)
    return s * a * vel


def pluck_bass(freq, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(4 * np.pi * freq * t) + 0.1 * np.sin(6 * np.pi * freq * t)
    return s * env_exp(n, 0.006, 0.35) * vel


def shaker(dur, vel=1.0):
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    # passa alto grezzo: differenza
    noise = np.diff(np.concatenate([[0], noise]))
    return noise * env_exp(n, 0.002, 0.03) * vel


def conga(freq, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq * (1 + 0.6 * np.exp(-t / 0.02))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env_exp(n, 0.002, 0.12) * vel


def add(buf, sig, start):
    i = int(start * SR)
    j = min(len(buf), i + len(sig))
    if i < len(buf):
        buf[i:j] += sig[: j - i]


def reverb(x, mix=0.22):
    out = x.copy()
    for d, g in [(0.029, 0.5), (0.037, 0.45), (0.047, 0.4), (0.061, 0.35), (0.083, 0.3), (0.11, 0.22)]:
        k = int(d * SR)
        y = np.zeros_like(x)
        y[k:] = x[:-k]
        for _ in range(3):
            y2 = np.zeros_like(y)
            y2[k:] = y[:-k] * g
            y = y + y2
        out += y * mix * g
    return out


def music():
    bpm = 96
    beat = 60 / bpm
    bar = 4 * beat
    # progressione (radici MIDI): sezione A e sezione B, 8 battute ciascuna, ripetute
    C, F, G, Am, Dm = 48, 53, 55, 57, 50
    chords = {C: [0, 4, 7], F: [0, 4, 7], G: [0, 4, 7, 10], Am: [0, 3, 7], Dm: [0, 3, 7]}
    A = [C, F, G, C, C, F, G, C]
    B = [F, C, Dm, G, Am, F, G, C]
    prog = A + B + A + B
    total = len(prog) * bar
    L = np.zeros(int((total + 3) * SR))
    R = np.zeros_like(L)
    mel_rhythms = [
        [(0, 1.5), (1.5, 0.5), (2, 1), (3, 1)],
        [(0, 0.5), (0.5, 1), (1.5, 0.5), (2, 1.5), (3.5, 0.5)],
        [(0.5, 0.5), (1, 1), (2, 0.5), (2.5, 1.5)],
        [(0, 1), (1, 0.5), (1.5, 1.5), (3, 1)],
    ]
    scale = [0, 2, 4, 5, 7, 9, 11]
    prev = 72
    for bi, root in enumerate(prog):
        t0 = bi * bar
        tones = [root + iv for iv in chords[root]]
        # basso calypso: 1, 2e, 3, 4e
        for pos, off, v in [(0, 0, 0.9), (1.5, 7, 0.6), (2, 0, 0.8), (3.5, 4 if root not in (Am, Dm) else 3, 0.6)]:
            sig = pluck_bass(note_hz(root - 12 + off), beat * 0.9, v * 0.55)
            add(L, sig, t0 + pos * beat)
            add(R, sig, t0 + pos * beat)
        # accordi in levare (steel drum di accompagnamento)
        for pos in (0.5, 1.5, 2.5, 3.5):
            for k, tn in enumerate(tones[:3]):
                sig = steelpan(note_hz(tn + 12), beat * 0.9, 0.11)
                add(L if k % 2 == 0 else R, sig, t0 + pos * beat + k * 0.006)
                add(R if k % 2 == 0 else L, sig * 0.6, t0 + pos * beat + k * 0.006)
        # percussioni
        for s16 in range(16):
            acc = 0.5 if s16 % 4 == 2 else 0.28
            sig = shaker(0.06, acc * 0.09)
            add(L, sig * 0.7, t0 + s16 * beat / 4)
            add(R, sig, t0 + s16 * beat / 4)
        for pos, f in [(1.5, 210), (2.75, 260), (3.5, 210)]:
            sig = conga(f, 0.3, 0.24)
            add(R, sig, t0 + pos * beat)
            add(L, sig * 0.6, t0 + pos * beat)
        # melodia (si tace nelle prime 2 battute e ogni tanto respira)
        if bi < 2 or bi % 8 == 7:
            continue
        rh = mel_rhythms[(bi * 7 + bi // 8) % len(mel_rhythms)]
        for k, (pos, dur) in enumerate(rh):
            on_beat = pos in (0, 2)
            if on_beat:
                cands = [tn + 24 for tn in tones] + [tn + 12 for tn in tones]
            else:
                cands = []
                for o in (60, 72, 84):
                    cands += [o + s for s in scale]
            cands = [c for c in cands if 67 <= c <= 88]
            cands.sort(key=lambda c: abs(c - prev) + rng.random() * 2.5)
            nt = cands[0] if rng.random() < 0.7 else cands[min(1, len(cands) - 1)]
            prev = nt
            sig = steelpan(note_hz(nt), dur * beat + 0.6, 0.42)
            add(L, sig, t0 + pos * beat)
            add(R, sig * 0.85, t0 + pos * beat + 0.012)
            if dur >= 1.5:   # rullata del suonatore sulle note lunghe
                for r in range(1, int(dur * 4)):
                    add(L, steelpan(note_hz(nt), 0.4, 0.12), t0 + (pos + r * 0.25) * beat)
    # coda che rientra all'inizio per un loop senza salti
    n = int(total * SR)
    for ch in (L, R):
        tail = ch[n:].copy()
        ch[: len(tail)] += tail
    L, R = L[:n], R[:n]
    L, R = reverb(L), reverb(R)
    st = np.stack([L, R], 1)
    st /= np.max(np.abs(st)) / 0.8
    st = np.tanh(st * 1.1) * 0.85
    wav = os.path.join(OUT, "_musica.wav")
    write_wav(wav, st, 2)
    ogg = os.path.join(OUT, "musica.ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", ogg], check=True)
    os.remove(wav)
    print("musica", round(total, 1), "s")


def write_wav(path, data, ch=1, sr=SR):
    d = np.clip(data, -1, 1)
    pcm = (d * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def norm(x, peak=0.8):
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def sfx():
    out = {}
    # clic di legno (pulsanti)
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    out["click"] = norm(np.sin(2 * np.pi * 1800 * t) * np.exp(-t / 0.008) + 0.3 * rng.standard_normal(n) * np.exp(-t / 0.004), 0.5)
    # pedone di legno sul tabellone
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    f = 520 * (1 + 0.5 * np.exp(-t / 0.01))
    tock = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.045)
    tock += 0.4 * np.sin(2 * np.pi * 1300 * t) * np.exp(-t / 0.015)
    out["pawn"] = norm(tock, 0.7)
    # dadi che rotolano
    dur = 0.9
    x = np.zeros(int(dur * SR))
    tt = 0.0
    gap = 0.03
    while tt < dur - 0.05:
        c = int(0.012 * SR)
        tc = np.arange(c) / SR
        click = (np.sin(2 * np.pi * rng.uniform(1800, 3200) * tc) + 0.6 * rng.standard_normal(c)) * np.exp(-tc / 0.004)
        add(x, click * (1 - tt / dur) ** 0.5, tt)
        tt += gap * rng.uniform(0.6, 1.4)
        gap *= 1.12
    out["dice"] = norm(x, 0.7)
    # monete
    x = np.zeros(int(0.7 * SR))
    for k, st in enumerate([0.0, 0.09, 0.16]):
        n = int(0.5 * SR)
        t = np.arange(n) / SR
        base = rng.uniform(2300, 2700)
        s = sum(a * np.sin(2 * np.pi * base * m * t) * np.exp(-t / tau) for m, a, tau in [(1, 1, 0.18), (1.51, 0.6, 0.12), (2.37, 0.4, 0.08), (3.1, 0.2, 0.05)])
        add(x, s * (0.9 - k * 0.2), st)
    out["coin"] = norm(x, 0.55)
    # onda (barcone che naviga)
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    k = 60
    noise = np.convolve(noise, np.ones(k) / k, mode="same")     # passa basso
    e = np.sin(np.pi * np.clip(t / 0.9, 0, 1)) ** 1.5
    out["splash"] = norm(noise * e * (1 + 0.4 * np.sin(2 * np.pi * 7 * t)), 0.5)
    # campana del molo
    n = int(1.8 * SR)
    t = np.arange(n) / SR
    bell = sum(a * np.sin(2 * np.pi * 740 * m * t) * np.exp(-t / tau) for m, a, tau in [(1, 1, 0.9), (2.0, 0.5, 0.6), (2.76, 0.35, 0.4), (5.4, 0.15, 0.2), (0.5, 0.3, 1.2)])
    out["bell"] = norm(bell * np.clip(t / 0.003, 0, 1), 0.6)
    # cannone dei pirati
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    boom = np.sin(2 * np.pi * np.cumsum(55 * (1 + 2 * np.exp(-t / 0.05))) / SR) * np.exp(-t / 0.35)
    nz = np.convolve(rng.standard_normal(n), np.ones(30) / 30, mode="same") * np.exp(-t / 0.25)
    out["cannon"] = norm(boom + 1.5 * nz, 0.8)
    # steel drum: arpeggi
    def arp(notes, step, dur_each=0.9, vel=0.6):
        x = np.zeros(int((step * len(notes) + dur_each) * SR))
        for i, nt in enumerate(notes):
            add(x, steelpan(note_hz(nt), dur_each, vel), i * step)
        return norm(reverb(x, 0.15), 0.6)
    out["market"] = arp([72, 76, 79], 0.09, 0.7)
    out["turn"] = arp([79, 84], 0.1, 0.8, 0.5)
    out["voyage"] = arp([72, 76, 79, 84, 79, 84], 0.12, 1.0)
    out["win"] = arp([60, 64, 67, 72, 76, 79, 84, 88, 84, 88], 0.11, 1.4)
    for name, data in out.items():
        write_wav(os.path.join(OUT, name + ".wav"), data, 1)
    print("effetti:", ", ".join(out))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sfx()
    music()

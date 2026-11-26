"""Measure a bounced WAV: level, clipping, dynamics, tonal balance and mono compatibility.

    python tools/analyze_wav.py song.wav [other.wav ...]
"""
import sys

import numpy as np
import soundfile as sf


def band_pass(x, rate, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / rate)
    spec[(f < lo) | (f >= hi)] = 0
    return np.fft.irfft(spec, len(x))


def analyze(path: str) -> None:
    data, rate = sf.read(path, dtype="float64", always_2d=True)
    mono = data.mean(axis=1)
    peak = np.abs(data).max()
    rms = np.sqrt((data ** 2).mean())
    clipped = int((np.abs(data) >= 0.999).sum())
    # short-term loudness (400 ms windows): how much the level moves (pumping shows up here)
    win = int(0.4 * rate)
    levels = [20 * np.log10(np.sqrt((mono[i:i + win] ** 2).mean()) + 1e-9)
              for i in range(0, len(mono) - win, win // 2)]
    levels = [lv for lv in levels if lv > -60]
    # tonal balance
    spec = np.abs(np.fft.rfft(mono * np.hanning(len(mono)))) ** 2
    freqs = np.fft.rfftfreq(len(mono), 1.0 / rate)
    total = spec.sum() + 1e-12
    bands = [(20, 150, "bass"), (150, 600, "low-mid"), (600, 2500, "mid"), (2500, 6000, "presence"), (6000, 16000, "air")]
    centroid = (freqs * spec).sum() / total
    print(f"{path}: {rate} Hz, {data.shape[1]} ch, {len(data) / rate:.1f} s")
    print(f"  peak {20 * np.log10(peak + 1e-9):.1f} dBFS, rms {20 * np.log10(rms + 1e-9):.1f} dBFS, crest {20 * np.log10(peak / (rms + 1e-9)):.1f} dB, clipped samples {clipped}")
    print(f"  loudness range (400 ms): {min(levels):.1f} .. {max(levels):.1f} dB (spread {max(levels) - min(levels):.1f} dB)")
    print("  bands: " + ", ".join(f"{n} {100 * spec[(freqs >= lo) & (freqs < hi)].sum() / total:.1f}%" for lo, hi, n in bands))
    print(f"  spectral centroid {centroid:.0f} Hz")
    if data.shape[1] == 2:
        left, right = data[:, 0], data[:, 1]
        rl, rr, rm = (np.sqrt((x ** 2).mean()) for x in (left, right, mono))
        print(f"  stereo: L/R correlation {np.corrcoef(left, right)[0, 1]:.2f}, "
              f"mono-sum loss {20 * np.log10(rm / ((rl + rr) / 2)):.1f} dB (0 = fully mono-safe, about -3 = uncorrelated)")
        print("  per-band L/R correlation (negative = cancels on a mono speaker): " + ", ".join(
            f"{lo}-{hi} Hz {np.corrcoef(band_pass(left, rate, lo, hi), band_pass(right, rate, lo, hi))[0, 1]:.2f}"
            for lo, hi in [(20, 150), (150, 600), (600, 2500), (2500, 8000)]))


for p in sys.argv[1:]:
    analyze(p)

"""Decode the Salamander Grand Piano takes and merge the instrument into sampled.json.

Source: https://github.com/sfzinstruments/SalamanderGrandPiano  (CC-BY 3.0, Alexander Holm)

Step 1 (PowerShell): tools/fetch_salamander.ps1 downloads the FLAC takes for velocity layers
v2, v6, v10, v14 (-> our layers 0..3) into assets/samples/salamander_grand/.
Step 2 (this script): each FLAC is decoded to 16-bit WAV, trimmed to TRIM_SECONDS with a short
fade-out, and the FLAC is removed. Then the 'salamander_grand' instrument is merged into
data/instruments/sampled.json (written as UTF-8 without a BOM).

Usage (from the project folder):
    python tools/fetch_salamander.py
"""
import glob
import json
import os
import re
import sys

import numpy as np
import soundfile as sf

LAYERS = {2: 0, 6: 1, 10: 2, 14: 3}  # Salamander velocity layer -> our layer index
TRIM_SECONDS = 6.0
FADE_SECONDS = 0.4
ID = "salamander_grand"
CREDIT = ("Salamander Grand Piano by Alexander Holm, CC-BY 3.0 "
          "(https://github.com/sfzinstruments/SalamanderGrandPiano)")

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "assets", "samples", ID)
JSON_PATH = os.path.join(ROOT, "data", "instruments", "sampled.json")
NOTE_INDEX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
NAME_RE = re.compile(r"^([A-Ga-g])([#s]?)(-?\d+)v(\d+)\.(flac|wav)$", re.IGNORECASE)  # D#1v2.flac or Ds1v2.flac


def midi_of(letter: str, sharp: str, octave: str) -> int:
    # Scientific pitch: A0 = 21 (same convention as the VSCO files)
    return 12 * (int(octave) + 1) + NOTE_INDEX[letter.upper()] + (1 if sharp else 0)


def decode(flac: str) -> str:
    wav = os.path.splitext(flac)[0].replace("#", "s") + ".wav"
    if not os.path.exists(wav):
        data, rate = sf.read(flac, dtype="float32", always_2d=True)
        n = min(data.shape[0], int(TRIM_SECONDS * rate))
        data = data[:n].copy()
        fade = min(int(FADE_SECONDS * rate), n)
        if fade > 0:
            data[n - fade:] *= np.linspace(1.0, 0.0, fade, dtype=np.float32)[:, None]
        sf.write(wav, data, rate, subtype="PCM_16")
    os.remove(flac)
    return wav


def main() -> int:
    if not os.path.isdir(OUT_DIR):
        print(f"Missing {OUT_DIR}: run tools/fetch_salamander.ps1 first.")
        return 1
    for flac in sorted(glob.glob(os.path.join(OUT_DIR, "*.flac"))):
        print("decoding", os.path.basename(flac))
        decode(flac)

    samples = []
    for wav in sorted(glob.glob(os.path.join(OUT_DIR, "*.wav"))):
        name = os.path.basename(wav)
        m = NAME_RE.match(name)
        if not m or int(m.group(4)) not in LAYERS:
            continue
        midi = midi_of(m.group(1), m.group(2), m.group(3))
        samples.append({"midi": midi, "vel": LAYERS[int(m.group(4))],
                        "file": f"res://assets/samples/{ID}/{name}"})
    if not samples:
        print("No Salamander WAV takes found.")
        return 1
    samples.sort(key=lambda s: (s["vel"], s["midi"]))
    print(f"{len(samples)} takes, {len({s['midi'] for s in samples})} pitches, "
          f"{len({s['vel'] for s in samples})} velocity layers")

    mids = sorted({s["midi"] for s in samples})
    entry = {
        "id": ID,
        "name": "Concert Grand (Salamander)",
        "category": "Keys",
        "family": "Piano",
        "synth": "sampler",
        "color": "#E9E4D8",
        "start_midi": 60,
        "range": [mids[0] - 4, mids[-1] + 6],
        "description": "Recorded Yamaha C5 concert grand with four velocity layers. " + CREDIT + ".",
        "params": {"samples": samples, "loop": False, "release": 0.6},
    }

    if os.path.exists(JSON_PATH):
        with open(JSON_PATH, encoding="utf-8-sig") as f:  # tolerate a BOM written by PowerShell
            doc = json.load(f)
    else:
        doc = {"version": 1, "license_note": "", "instruments": []}
    doc["instruments"] = [i for i in doc.get("instruments", []) if i.get("id") != ID]
    doc["instruments"].append(entry)
    notes = [n for n in [doc.get("license_note", "").strip(), CREDIT + "."] if n]
    doc["license_note"] = " ".join(dict.fromkeys(notes))
    with open(JSON_PATH, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
    print(f"Merged {ID} into {os.path.relpath(JSON_PATH, ROOT)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

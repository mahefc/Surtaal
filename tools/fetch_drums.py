#!/usr/bin/env python3
"""Fetch / convert Virtuosity Drums (CC0) into Surtaal's drum-loop kit.

Source: Versilian Studios / Karoryfer — Virtuosity Drums, CC0 1.0
Trimmed mid-mic (kickmic for kick) bank packaged by ferrosintesis-samples-drumkit.

  python tools/fetch_drums.py

Expects crates already under build/drumkit_fetch/ (or downloads them).
Writes assets/samples/<id>/*.wav and data/instruments/drums.json.
"""
from __future__ import annotations

import json
import tarfile
import urllib.request
from pathlib import Path

import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "drumkit_fetch"
OUT_JSON = ROOT / "data" / "instruments" / "drums.json"

# articulation stem -> Surtaal instrument
KIT = [
    # id, name, color, family, stem, crate_dir, midi
    ("kick", "Kick", "#FF6B6B", "Drum kit", "kick", "ferrosintesis-samples-drumkit-0.2.1", 36),
    ("snare", "Snare", "#FFD93D", "Drum kit", "snare", "ferrosintesis-samples-drumkit-0.2.1", 38),
    ("hat", "Hi-hat", "#6BCB77", "Drum kit", "hhc", "ferrosintesis-samples-drumkit-0.2.1", 42),
    ("hat_open", "Open Hi-hat", "#95D5A0", "Drum kit", "hho", "ferrosintesis-samples-drumkit-0.2.1", 46),
    ("tom_hi", "High Tom", "#4ECDC4", "Drum kit", "tomhi", "ferrosintesis-samples-drumkit-0.2.1", 50),
    ("tom_lo", "Floor Tom", "#3AAFA9", "Drum kit", "tomlo", "ferrosintesis-samples-drumkit-0.2.1", 45),
    ("rim", "Rimshot", "#F4A261", "Drum kit", "sidestick", "ferrosintesis-samples-drumkit-0.2.1", 37),
    ("ride", "Ride", "#A8DADC", "Drum kit", "ride", "ferrosintesis-samples-drumkit-0.2.1", 51),
    ("crash", "Crash", "#BFC9D4", "Drum kit", "crash", "ferrosintesis-samples-drumkit2-0.2.1", 49),
]

CRATES = {
    "ferrosintesis-samples-drumkit": "0.2.1",
    "ferrosintesis-samples-drumkit2": "0.2.1",
}


def ensure_crates() -> None:
    BUILD.mkdir(parents=True, exist_ok=True)
    for name, ver in CRATES.items():
        dest = BUILD / f"{name}.crate"
        folder = BUILD / f"{name}-{ver}"
        if folder.is_dir():
            continue
        if not dest.is_file():
            url = f"https://crates.io/api/v1/crates/{name}/{ver}/download"
            print(f"Downloading {url}")
            urllib.request.urlretrieve(url, dest)
        print(f"Extracting {dest.name}")
        with tarfile.open(dest, "r:gz") as tar:
            tar.extractall(BUILD)


def convert_one(stem: str, crate_dir: str, out_dir: Path, midi: int) -> list[dict]:
    src = BUILD / crate_dir / "samples"
    out_dir.mkdir(parents=True, exist_ok=True)
    # Keep rr1 only; map velocity layers to Surtaal's 0..n-1 soft->loud.
    files = sorted(src.glob(f"{stem}_vl*_rr1.flac"))
    if not files:
        raise SystemExit(f"No samples for {stem} in {src}")
    zones: list[dict] = []
    for i, flac in enumerate(files):
        data, rate = sf.read(str(flac), always_2d=False)
        wav_name = f"{stem}_v{i + 1}.wav"
        wav_path = out_dir / wav_name
        sf.write(str(wav_path), data, rate, subtype="PCM_16")
        zones.append(
            {
                "midi": midi,
                "vel": i,
                "file": f"res://assets/samples/{out_dir.name}/{wav_name}",
            }
        )
        print(f"  {out_dir.name}: {wav_name} ({rate} Hz)")
    return zones


def main() -> None:
    ensure_crates()
    instruments = []
    for iid, name, color, family, stem, crate_dir, midi in KIT:
        zones = convert_one(stem, crate_dir, ROOT / "assets" / "samples" / iid, midi)
        instruments.append(
            {
                "id": iid,
                "name": name,
                "category": "Drums",
                "family": family,
                "synth": "sampler",
                "color": color,
                "start_midi": midi,
                "range": [midi - 6, midi + 6],
                "description": (
                    "Virtuosity Drums studio recording (Versilian / Karoryfer, CC0). "
                    "Velocity layers for expressive drum loops."
                ),
                "params": {"samples": zones, "loop": False, "fixed": True, "release": 0.15},
            }
        )
    payload = {
        "version": 1,
        "license_note": (
            "Virtuosity Drums by Versilian Studios / Karoryfer Samples, CC0 1.0. "
            "https://github.com/sfzinstruments/virtuosity_drums"
        ),
        "instruments": instruments,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUT_JSON} with {len(instruments)} drum instruments.")


if __name__ == "__main__":
    main()

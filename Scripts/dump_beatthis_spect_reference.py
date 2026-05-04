#!/usr/bin/env python3
"""dump_beatthis_spect_reference.py — produce the log-mel spectrogram reference JSON for S2 tests.

Loads love_rehab.m4a via ffmpeg, runs Beat This!'s LogMelSpect, and writes the first 10
frames (10 × 128 floats) as JSON to:

    PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/beat_this_reference/
        love_rehab_spect_reference.json

Parameters match Beat This! defaults exactly:
    sr=22050, n_fft=1024, hop=441, n_mels=128, f_min=30, f_max=11000,
    mel_scale="slaney", normalized="frame_length", power=1, log_multiplier=1000

Usage (from project root):
    /tmp/beat_this_venv/bin/python Scripts/dump_beatthis_spect_reference.py

Source: github.com/CPJKU/beat_this @ 9d787b9797eaa325856a20897187734175467074
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).parent.parent / "vendor" / "beat_this_repo"))

from beat_this.preprocessing import LogMelSpect

AUDIO_PATH = Path("PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a")
OUT_PATH = Path(
    "PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/"
    "beat_this_reference/love_rehab_spect_reference.json"
)

N_FRAMES = 10


def load_audio_ffmpeg(path: str, target_sr: int = 22050) -> np.ndarray:
    cmd = [
        "ffmpeg", "-i", str(path),
        "-ac", "1", "-ar", str(target_sr),
        "-f", "f32le", "-", "-loglevel", "error",
    ]
    raw = subprocess.check_output(cmd)
    return np.frombuffer(raw, dtype="<f4").astype(np.float32)


def main() -> int:
    if not AUDIO_PATH.exists():
        print(f"MISSING: {AUDIO_PATH} — run Scripts/fetch_tempo_fixtures.sh first",
              file=sys.stderr)
        return 1

    print(f"Loading {AUDIO_PATH} ...")
    signal = load_audio_ffmpeg(str(AUDIO_PATH), target_sr=22050)
    signal_tensor = torch.tensor(signal, dtype=torch.float32)
    print(f"  signal: {len(signal)} samples, {len(signal)/22050:.2f}s")

    spect_fn = LogMelSpect(device="cpu")
    with torch.no_grad():
        spect = spect_fn(signal_tensor)  # shape: (T, 128)

    total_frames = spect.shape[0]
    print(f"  spectrogram: {tuple(spect.shape)} (T={total_frames}, bins=128)")

    frames = spect[:N_FRAMES].tolist()  # list[list[float]], 10 × 128

    result = {
        "n_fft": 1024,
        "hop_length": 441,
        "sample_rate": 22050,
        "n_mels": 128,
        "f_min": 30,
        "f_max": 11000,
        "mel_scale": "slaney",
        "normalized": "frame_length",
        "power": 1,
        "log_multiplier": 1000,
        "total_frames": total_frames,
        "fixture": "love_rehab",
        "audio_file": "love_rehab.m4a",
        "n_reference_frames": N_FRAMES,
        "frames_10x128": frames,
    }

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_PATH, "w") as f:
        json.dump(result, f, indent=2)

    print(f"  → {OUT_PATH} ({OUT_PATH.stat().st_size:,} bytes)")
    print(f"  frame[0][0..3] = {frames[0][:4]}")
    print(f"  frame[0][63..67] = {frames[0][63:67]}")
    print(f"  frame[0][124..127] = {frames[0][124:128]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

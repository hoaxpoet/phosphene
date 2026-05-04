#!/usr/bin/env python3
"""dump_beatthis_reference.py — produce per-fixture Beat This! reference JSON files.

Runs Beat This! inference on each of the six DSP.2 fixtures and writes one JSON
file per fixture under:

    PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/beat_this_reference/

Each JSON contains:
  - model_variant, fixture metadata
  - beat_logits_first1500 / downbeat_logits_first1500: dense per-frame raw
    logit streams (first 1500 frames ≈ 30 s) for golden tests in Sessions 2 / 4 / 5
  - beats_seconds / downbeats_seconds: postprocessed beat positions (minimal
    postprocessor, no DBN, same as default inference)
  - bpm_trimmed_mean: BPM from trimmed-mean IOI (D-075 method; avoids histogram bias)
  - beats_per_bar_estimate: rough meter estimate from downbeat spacing

Usage (from project root):
    /tmp/beat_this_venv/bin/python Scripts/dump_beatthis_reference.py [--variant small0|final0]

Venv setup:
    python3 -m venv /tmp/beat_this_venv
    /tmp/beat_this_venv/bin/pip install torch torchaudio einops soxr rotary-embedding-torch soundfile
    cd /tmp/beat_this_repo && /tmp/beat_this_venv/bin/pip install -e .

Audio loading uses ffmpeg (which must be on PATH) to decode .m4a previews to
mono float32 at 22050 Hz — the same target sample rate that Beat This! uses.
torchaudio's loader is not used because it requires torchcodec for .m4a on
newer torchaudio versions and that dependency is not part of the minimal venv.

Source: github.com/CPJKU/beat_this @ 9d787b9797eaa325856a20897187734175467074
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import torch

# Allow running from project root without installing beat_this to system Python
sys.path.insert(0, str(Path(__file__).parent.parent / "vendor" / "beat_this_repo"))

from beat_this.inference import load_model, split_predict_aggregate
from beat_this.model.postprocessor import Postprocessor
from beat_this.preprocessing import LogMelSpect


FIXTURE_DIR = Path("PhospheneEngine/Tests/Fixtures/tempo")
OUT_DIR = Path("PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/beat_this_reference")

FIXTURES = [
    ("love_rehab",          "love_rehab.m4a",          "Chaim",        "electronic ~125 BPM, 4/4"),
    ("so_what",             "so_what.m4a",              "Miles Davis",  "jazz ~136 BPM, swing"),
    ("there_there",         "there_there.m4a",          "Radiohead",    "syncopated rock ~86 BPM underlying meter"),
    ("pyramid_song",        "pyramid_song.m4a",         "Radiohead",    "16/8 grouped 3+3+4+3+3 irregular meter"),
    ("money",               "money.m4a",                "Pink Floyd",   "7/4 at ~123 BPM"),
    ("if_i_were_with_her_now", "if_i_were_with_her_now.m4a", "Spiritualized",
     "syncopation + mid-track meter changes (temporal-instability gate)"),
]


def load_audio_ffmpeg(path: str, target_sr: int = 22050) -> tuple[np.ndarray, int]:
    """Decode audio to mono float32 at target_sr using ffmpeg.

    Mirrors what Beat This!'s Audio2Frames.signal2spect does after soxr resampling:
    decode to float32 PCM at 22050 Hz mono. The soxr step is folded into the ffmpeg
    -ar flag since both produce a high-quality sinc resampler output.
    """
    cmd = ["ffmpeg", "-i", str(path), "-ac", "1", "-ar", str(target_sr),
           "-f", "f32le", "-", "-loglevel", "error"]
    raw = subprocess.check_output(cmd)
    arr = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    return arr, target_sr


def bpm_from_beats(beats: np.ndarray) -> float:
    """Trimmed-mean IOI BPM — D-075 method; avoids histogram-mode bias."""
    if len(beats) < 2:
        return 0.0
    iois = np.diff(beats)
    med = np.median(iois)
    inliers = iois[(iois >= 0.5 * med) & (iois <= 2.0 * med)]
    mean_ioi = inliers.mean() if len(inliers) > 0 else np.mean(iois)
    return 60.0 / mean_ioi


def beats_per_bar_from_downbeats(downbeats: np.ndarray, bpm: float) -> int:
    """Rough meter estimate from downbeat inter-onset intervals."""
    if len(downbeats) < 2 or bpm <= 0:
        return 0
    db_iois = np.diff(downbeats)
    med_db = np.median(db_iois)
    return int(round(med_db / (60.0 / bpm)))


def run(variant: str = "small0") -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Loading {variant} model...")
    model = load_model(variant, device="cpu")
    model.eval()

    spect_fn = LogMelSpect(device="cpu")
    postprocessor = Postprocessor(type="minimal", fps=50)

    for label, filename, artist, description in FIXTURES:
        audio_path = FIXTURE_DIR / filename
        if not audio_path.exists():
            print(f"MISSING: {audio_path}  — run Scripts/fetch_tempo_fixtures.sh first")
            continue

        print(f"\n--- {label} ---")
        signal, sr = load_audio_ffmpeg(str(audio_path), target_sr=22050)
        signal_tensor = torch.tensor(signal, dtype=torch.float32)
        spect = spect_fn(signal_tensor)  # (T, 128)
        duration_s = spect.shape[0] / 50.0
        print(f"  spect: {tuple(spect.shape)}, {duration_s:.1f}s @ 50fps")

        t1 = time.perf_counter()
        with torch.inference_mode():
            pred = split_predict_aggregate(
                spect=spect,
                chunk_size=1500,
                border_size=6,
                overlap_mode="keep_first",
                model=model,
            )
        beat_logits = pred["beat"].float()
        downbeat_logits = pred["downbeat"].float()
        inference_ms = (time.perf_counter() - t1) * 1000
        projected_30s_ms = inference_ms / duration_s * 30.0

        beats, downbeats = postprocessor(beat_logits, downbeat_logits)
        bpm = bpm_from_beats(beats)
        bpb = beats_per_bar_from_downbeats(downbeats, bpm)
        print(f"  inference: {inference_ms:.0f}ms, BPM: {bpm:.1f}, beats/bar~: {bpb}")

        T = min(1500, len(beat_logits))
        result = {
            "model_variant": variant,
            "fixture": label,
            "artist": artist,
            "description": description,
            "audio_file": filename,
            "sample_rate": 22050,
            "hop_length": 441,
            "frame_rate_hz": 50,
            "n_frames": int(len(beat_logits)),
            "beat_logits_first1500": beat_logits[:T].tolist(),
            "downbeat_logits_first1500": downbeat_logits[:T].tolist(),
            "beats_seconds": beats.tolist(),
            "downbeats_seconds": downbeats.tolist(),
            "bpm_trimmed_mean": round(float(bpm), 2),
            "beats_per_bar_estimate": int(bpb),
            "inference_ms_measured": round(inference_ms, 1),
            "inference_projected_30s_ms": round(projected_30s_ms, 1),
        }

        out_path = OUT_DIR / f"{label}_reference.json"
        with open(out_path, "w") as f:
            json.dump(result, f, indent=2)
        print(f"  → {out_path} ({out_path.stat().st_size:,} bytes)")

    print(f"\nAll fixtures written to {OUT_DIR}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    parser.add_argument(
        "--variant", default="small0",
        help="Beat This! checkpoint variant (default: small0)"
    )
    args = parser.parse_args(argv)
    run(args.variant)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

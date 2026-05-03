#!/usr/bin/env python3
"""convert_beatnet_weights.py — DSP.2 weight converter.

One-shot converter that ingests a BeatNet PyTorch checkpoint (state_dict
saved via torch.save, format .pt or .pth) and emits Phosphene's vendored
.bin weight format under PhospheneEngine/Sources/ML/Weights/beatnet/.

Output format mirrors PhospheneEngine/Sources/ML/Weights/ (Open-Unmix HQ):

  * one .bin file per tensor: contiguous float32 little-endian, C order
  * manifest.json describing tensors with shape + byte count

The output is consumed at runtime by BeatTrackerModel+Weights.swift
(Session 5), which mirrors StemModel+Weights.swift exactly.

Usage:
    python3 Scripts/convert_beatnet_weights.py \
        --checkpoint <path-to-model_N_weights.pt> \
        --variant <gtzan|ballroom|rock_corpus> \
        [--out PhospheneEngine/Sources/ML/Weights/beatnet]

Reproducibility: a fresh clone of github.com/mjhydri/BeatNet @ main with
src/BeatNet/models/model_1_weights.pt as input produces byte-identical
output. The script does not download anything; the caller supplies the
checkpoint path. See docs/diagnostics/DSP.2-architecture.md for the
provenance trail.

Dependencies: torch >= 1.6, numpy. Both required only at conversion time;
runtime inference uses MPSGraph + Accelerate (no Python, no torch).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from collections import OrderedDict
from pathlib import Path

import numpy as np
import torch


# Expected state_dict keys + shapes for the BeatNet BDA model
# (constructor BDA(dim_in=272, num_cells=150, num_layers=2)).
# Source: src/BeatNet/model.py (commit @main 2026-04-13).
EXPECTED_TENSORS: "OrderedDict[str, tuple[int, ...]]" = OrderedDict([
    ("conv1.weight",       (2, 1, 10)),
    ("conv1.bias",         (2,)),
    ("linear0.weight",     (150, 262)),
    ("linear0.bias",       (150,)),
    ("lstm.weight_ih_l0",  (600, 150)),
    ("lstm.weight_hh_l0",  (600, 150)),
    ("lstm.bias_ih_l0",    (600,)),
    ("lstm.bias_hh_l0",    (600,)),
    ("lstm.weight_ih_l1",  (600, 150)),
    ("lstm.weight_hh_l1",  (600, 150)),
    ("lstm.bias_ih_l1",    (600,)),
    ("lstm.bias_hh_l1",    (600,)),
    ("linear.weight",      (3, 150)),
    ("linear.bias",        (3,)),
])


def torch_key_to_filename(torch_key: str) -> str:
    """Map state_dict key to flat .bin filename.

    Mirrors PhospheneEngine/Sources/ML/Weights/ convention for Open-Unmix
    (e.g. ``vocals.lstm.weight_ih_l0`` -> ``vocals_lstm_weight_ih_l0.bin``).
    BeatNet has no per-stem prefix so output names are bare layer.param.
    """
    return torch_key.replace(".", "_") + ".bin"


def convert(checkpoint_path: Path, variant: str, out_dir: Path) -> dict:
    """Load checkpoint, validate, write .bin files + manifest. Return manifest."""
    state_dict = torch.load(str(checkpoint_path), map_location="cpu", weights_only=True)

    missing = [k for k in EXPECTED_TENSORS if k not in state_dict]
    extra = [k for k in state_dict if k not in EXPECTED_TENSORS]
    if missing:
        raise SystemExit(f"checkpoint missing expected tensors: {missing}")
    if extra:
        raise SystemExit(f"checkpoint has unexpected tensors: {extra}")

    out_dir.mkdir(parents=True, exist_ok=True)

    tensors_meta: "OrderedDict[str, dict]" = OrderedDict()
    total_bytes = 0
    for key, expected_shape in EXPECTED_TENSORS.items():
        tensor = state_dict[key]
        if tuple(tensor.shape) != expected_shape:
            raise SystemExit(
                f"shape mismatch for {key}: expected {expected_shape}, "
                f"got {tuple(tensor.shape)}"
            )
        if tensor.dtype != torch.float32:
            raise SystemExit(f"dtype mismatch for {key}: expected float32, got {tensor.dtype}")

        arr = tensor.detach().cpu().contiguous().numpy().astype("<f4", copy=False)
        filename = torch_key_to_filename(key)
        out_path = out_dir / filename
        with open(out_path, "wb") as fh:
            fh.write(arr.tobytes(order="C"))

        nbytes = arr.nbytes
        sha = hashlib.sha256(arr.tobytes(order="C")).hexdigest()
        tensors_meta[key] = {
            "file": filename,
            "shape": list(expected_shape),
            "dtype": "float32",
            "bytes": nbytes,
            "sha256": sha,
        }
        total_bytes += nbytes

    manifest = OrderedDict([
        ("format_version", 1),
        ("model", "beatnet"),
        ("variant", variant),
        ("description",
         "BeatNet BDA (beat-downbeat-activation) CRNN weights for MPSGraph "
         "inference. Source: github.com/mjhydri/BeatNet @ main, "
         "src/BeatNet/model.py BDA(dim_in=272, num_cells=150, num_layers=2). "
         "License: CC-BY-4.0 (see docs/CREDITS.md)."),
        ("source_checkpoint", checkpoint_path.name),
        ("dtype", "float32"),
        ("byte_order", "little-endian"),
        ("total_bytes", total_bytes),
        ("total_params", total_bytes // 4),
        ("architecture", OrderedDict([
            ("input_dim", 272),
            ("conv_channels_out", 2),
            ("conv_kernel", 10),
            ("post_pool_dim", 262),
            ("projection_dim", 150),
            ("lstm_hidden", 150),
            ("lstm_num_layers", 2),
            ("lstm_bidirectional", False),
            ("output_classes", 3),
            ("output_class_meanings", ["beat", "downbeat", "no_beat"]),
            ("frame_rate_hz", 50),
            ("hop_samples", 441),
            ("win_samples", 1411),
            ("internal_sample_rate_hz", 22050),
        ])),
        ("tensors", tensors_meta),
    ])

    manifest_path = out_dir / "manifest.json"
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")

    return manifest


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    parser.add_argument(
        "--checkpoint",
        type=Path,
        required=True,
        help="path to BeatNet state_dict .pt (e.g. model_1_weights.pt)",
    )
    parser.add_argument(
        "--variant",
        choices=("gtzan", "ballroom", "rock_corpus"),
        required=True,
        help="training corpus identifier (model 1=gtzan, 2=ballroom, 3=rock_corpus)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("PhospheneEngine/Sources/ML/Weights/beatnet"),
        help="output directory (default: PhospheneEngine/Sources/ML/Weights/beatnet)",
    )
    args = parser.parse_args(argv)

    if not args.checkpoint.is_file():
        parser.error(f"checkpoint not found: {args.checkpoint}")

    manifest = convert(args.checkpoint, args.variant, args.out)
    print(
        f"wrote {len(manifest['tensors'])} tensors "
        f"({manifest['total_bytes']:,} bytes, {manifest['total_params']:,} params) "
        f"to {args.out}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""convert_beatthis_weights.py — DSP.2 weight converter for Beat This!

One-shot converter that ingests a Beat This! PyTorch Lightning checkpoint and
emits Phosphene's vendored .bin weight format under
PhospheneEngine/Sources/ML/Weights/beat_this/.

Output format mirrors PhospheneEngine/Sources/ML/Weights/ (Open-Unmix HQ):

  * one .bin file per float32 tensor: contiguous float32 little-endian, C order
  * manifest.json describing every tensor with shape, dtype, byte count, sha256

The 5 int64 ``num_batches_tracked`` BatchNorm buffers are skipped — they are
used only during training and are not consumed during inference.

Usage:
    python3 Scripts/convert_beatthis_weights.py \\
        --checkpoint ~/.cache/torch/hub/checkpoints/beat_this-small0.ckpt \\
        --variant small0 \\
        [--out PhospheneEngine/Sources/ML/Weights/beat_this]

    python3 Scripts/convert_beatthis_weights.py \\
        --checkpoint ~/.cache/torch/hub/checkpoints/beat_this-final0.ckpt \\
        --variant final0

Reproducibility: a fresh clone of github.com/CPJKU/beat_this @ commit
9d787b9797eaa325856a20897187734175467074, with the checkpoint downloaded via
``torch.hub`` (URL: https://cloud.cp.jku.at/public.php/dav/files/7ik4RrBKTS273gp),
and a fresh run of this script produces byte-identical output. The script does
not download anything; the caller supplies the checkpoint path.

Venv setup (Python 3.12+):
    python3 -m venv /tmp/beat_this_venv
    /tmp/beat_this_venv/bin/pip install torch torchaudio einops soxr rotary-embedding-torch
    cd /tmp/beat_this_repo && /tmp/beat_this_venv/bin/pip install -e .

Or simply:
    pip install beat-this torch

Dependencies: torch >= 2.0, numpy. Required only at conversion time; runtime
inference uses MPSGraph + Accelerate (no Python, no torch).

Source: github.com/CPJKU/beat_this, commit 9d787b9797eaa325856a20897187734175467074.
License: MIT (see docs/CREDITS.md).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import OrderedDict
from pathlib import Path

import numpy as np
import torch


# Keys to skip — int64 BatchNorm training-only buffers (not needed at inference)
SKIP_KEYS = {
    "frontend.stem.bn1d.num_batches_tracked",
    "frontend.stem.bn2d.num_batches_tracked",
    "frontend.blocks.0.norm.num_batches_tracked",
    "frontend.blocks.1.norm.num_batches_tracked",
    "frontend.blocks.2.norm.num_batches_tracked",
}

# Expected hyperparameter sets per variant (from checkpoint["hyper_parameters"])
# Source: beat_this/model/pl_module.py PLBeatThis.__init__
EXPECTED_HPARAMS: dict[str, dict] = {
    "small0": {
        "spect_dim": 128, "transformer_dim": 128, "ff_mult": 4,
        "n_layers": 6, "head_dim": 32, "stem_dim": 32,
        "sum_head": True, "partial_transformers": True,
    },
    "small1": {
        "spect_dim": 128, "transformer_dim": 128, "ff_mult": 4,
        "n_layers": 6, "head_dim": 32, "stem_dim": 32,
        "sum_head": True, "partial_transformers": True,
    },
    "small2": {
        "spect_dim": 128, "transformer_dim": 128, "ff_mult": 4,
        "n_layers": 6, "head_dim": 32, "stem_dim": 32,
        "sum_head": True, "partial_transformers": True,
    },
    "final0": {
        "spect_dim": 128, "transformer_dim": 512, "ff_mult": 4,
        "n_layers": 6, "head_dim": 32, "stem_dim": 32,
        "sum_head": True, "partial_transformers": True,
    },
    "final1": {
        "spect_dim": 128, "transformer_dim": 512, "ff_mult": 4,
        "n_layers": 6, "head_dim": 32, "stem_dim": 32,
        "sum_head": True, "partial_transformers": True,
    },
    "final2": {
        "spect_dim": 128, "transformer_dim": 512, "ff_mult": 4,
        "n_layers": 6, "head_dim": 32, "stem_dim": 32,
        "sum_head": True, "partial_transformers": True,
    },
}


def torch_key_to_filename(key: str) -> str:
    """Map state_dict key to flat .bin filename.

    Convention mirrors Open-Unmix: dots become underscores, .bin suffix added.
    Example: ``frontend.stem.bn1d.weight`` → ``frontend_stem_bn1d_weight.bin``
    """
    return key.replace(".", "_") + ".bin"


def validate_hparams(checkpoint: dict, variant: str) -> dict:
    """Extract and validate hyperparameters from a Lightning checkpoint."""
    hparams = checkpoint.get("hyper_parameters", {})
    if variant in EXPECTED_HPARAMS:
        expected = EXPECTED_HPARAMS[variant]
        mismatches = []
        for k, v in expected.items():
            if k in hparams and hparams[k] != v:
                mismatches.append(f"{k}: expected {v}, got {hparams[k]}")
        if mismatches:
            print(f"WARNING: hyperparameter mismatches for variant '{variant}':")
            for m in mismatches:
                print(f"  {m}")
            print("  Proceeding — the actual checkpoint hparams take precedence.")
    return hparams


def convert(checkpoint_path: Path, variant: str, out_dir: Path) -> dict:
    """Load checkpoint, validate, write .bin files + manifest. Return manifest."""
    checkpoint = torch.load(str(checkpoint_path), map_location="cpu", weights_only=True)

    hparams = validate_hparams(checkpoint, variant)
    transformer_dim = hparams.get("transformer_dim", 512)
    n_layers = hparams.get("n_layers", 6)
    head_dim = hparams.get("head_dim", 32)
    stem_dim = hparams.get("stem_dim", 32)
    ff_mult = hparams.get("ff_mult", 4)
    spect_dim = hparams.get("spect_dim", 128)

    # Strip "model." prefix added by PyTorch Lightning's PLBeatThis wrapper
    raw_sd = checkpoint["state_dict"]
    state_dict = OrderedDict()
    for k, v in raw_sd.items():
        clean_key = k[6:] if k.startswith("model.") else k
        # Also strip "_orig_mod." for compiled models (matches BeatThis._load_from_state_dict)
        clean_key = clean_key.replace("_orig_mod.", "")
        state_dict[clean_key] = v

    out_dir.mkdir(parents=True, exist_ok=True)

    tensors_meta: OrderedDict[str, dict] = OrderedDict()
    total_bytes = 0
    total_params = 0

    for key, tensor in state_dict.items():
        if key in SKIP_KEYS:
            continue  # int64 training-only buffers; not needed at inference

        if tensor.dtype != torch.float32:
            raise SystemExit(
                f"Unexpected dtype for {key}: {tensor.dtype}. "
                "All inference tensors should be float32. "
                "If this is a new checkpoint format, inspect and update SKIP_KEYS."
            )

        arr = tensor.detach().cpu().contiguous().numpy().astype("<f4", copy=False)
        filename = torch_key_to_filename(key)
        out_path = out_dir / filename
        with open(out_path, "wb") as fh:
            fh.write(arr.tobytes(order="C"))

        nbytes = arr.nbytes
        sha = hashlib.sha256(arr.tobytes(order="C")).hexdigest()
        tensors_meta[key] = {
            "file": filename,
            "shape": list(tensor.shape),
            "dtype": "float32",
            "bytes": nbytes,
            "sha256": sha,
        }
        total_bytes += nbytes
        total_params += tensor.numel()

    manifest = OrderedDict([
        ("format_version", 1),
        ("model", "beat_this"),
        ("variant", variant),
        ("description",
         "Beat This! (Foscarin et al., ISMIR 2024) transformer beat/downbeat tracker weights. "
         "Source: github.com/CPJKU/beat_this @ commit 9d787b9797eaa325856a20897187734175467074. "
         "Checkpoint downloaded from https://cloud.cp.jku.at/public.php/dav/files/7ik4RrBKTS273gp. "
         "License: MIT (see docs/CREDITS.md)."),
        ("source_checkpoint", checkpoint_path.name),
        ("source_commit", "9d787b9797eaa325856a20897187734175467074"),
        ("dtype", "float32"),
        ("byte_order", "little-endian"),
        ("total_bytes", total_bytes),
        ("total_params", total_params),
        ("architecture", OrderedDict([
            ("model_class", "BeatThis"),
            ("spect_dim", spect_dim),
            ("transformer_dim", transformer_dim),
            ("n_layers", n_layers),
            ("head_dim", head_dim),
            ("n_heads", transformer_dim // head_dim),
            ("stem_dim", stem_dim),
            ("ff_mult", ff_mult),
            ("ffn_dim", transformer_dim * ff_mult),
            ("sum_head", hparams.get("sum_head", True)),
            ("partial_transformers", hparams.get("partial_transformers", True)),
            ("n_frontend_blocks", 3),
            ("output_heads", ["beat", "downbeat"]),
            ("output_activation", "none (raw logits; sigmoid in postprocessor)"),
            ("frame_rate_hz", 50),
            ("hop_samples", 441),
            ("sample_rate_hz", 22050),
            ("n_mels", 128),
            ("n_fft", 1024),
            ("f_min_hz", 30),
            ("f_max_hz", 11000),
            ("mel_scale", "slaney"),
            ("mel_norm", "frame_length"),
            ("mel_power", 1),
            ("log_multiplier", 1000),
            ("inference_chunk_size_frames", 1500),
            ("inference_border_size_frames", 6),
            ("inference_overlap_mode", "keep_first"),
            ("resampler", "soxr (inference.py:Audio2Frames.signal2spect)"),
            ("positional_encoding", "RoPE (rotary_embedding_torch, head_dim=32)"),
            ("attention_norm", "RMSNorm (pre-attention)"),
            ("ffn_norm", "RMSNorm (pre-FFN)"),
            ("ffn_activation", "GELU"),
            ("attention_gating", True),
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
        help="path to Beat This! Lightning .ckpt file",
    )
    parser.add_argument(
        "--variant",
        default="small0",
        help="checkpoint name/variant (e.g. small0, final0). Default: small0",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("PhospheneEngine/Sources/ML/Weights/beat_this"),
        help="output directory (default: PhospheneEngine/Sources/ML/Weights/beat_this)",
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

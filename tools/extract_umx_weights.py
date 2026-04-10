#!/usr/bin/env python3
"""
Extract Open-Unmix HQ weight tensors into raw float32 .bin files for MPSGraph.

Loads the umxhq PyTorch checkpoint via openunmix, iterates all named
parameters and buffers across 4 stems, and saves each tensor as a raw
.bin file (float32, C-contiguous). Produces a manifest.json mapping
tensor names to shapes, dtypes, filenames, and byte sizes.

The output directory is intended to be bundled into PhospheneEngine as
a Swift Package Manager resource (.copy("Weights")).

Usage:
    python tools/extract_umx_weights.py [--output DIR]

Requires: torch, openunmix (see tools/requirements-ml.txt)

Per-stem expected tensors:
  - input_mean[1487], input_scale[1487]
  - fc1.weight[512, 2974], fc1.bias[512]
  - bn1.weight[512], bn1.bias[512], bn1.running_mean[512], bn1.running_var[512]
  - lstm.weight_ih_l{0,1,2}[2048, 512], lstm.weight_hh_l{0,1,2}[2048, 512]
  - lstm.weight_ih_l{0,1,2}_reverse[2048, 512], lstm.weight_hh_l{0,1,2}_reverse[2048, 512]
  - lstm.bias_ih_l{0,1,2}[2048], lstm.bias_hh_l{0,1,2}[2048]
  - lstm.bias_ih_l{0,1,2}_reverse[2048], lstm.bias_hh_l{0,1,2}_reverse[2048]
  - fc2.weight[512, 1024], fc2.bias[512]
  - bn2.weight[512], bn2.bias[512], bn2.running_mean[512], bn2.running_var[512]
  - fc3.weight[2049, 512], fc3.bias[512]
  - bn3.weight[2049], bn3.bias[2049], bn3.running_mean[2049], bn3.running_var[2049]
  - output_mean[2049], output_scale[2049]

Open-Unmix architecture per stem:
  input_mean/input_scale: bandwidth-limited normalization (1487 bins = 2 ch × 743 + 1)
  fc1: Linear(2974, 512) — 2974 = 2 channels × 1487 bins
  bn1: BatchNorm1d(512)
  lstm: LSTM(512, 256, num_layers=3, bidirectional=True) — output 512
  fc2: Linear(1024, 512) — 1024 = skip connection (512 LSTM out + 512 fc1 out)
  bn2: BatchNorm1d(512)
  fc3: Linear(512, 2049) — full-bandwidth output
  bn3: BatchNorm1d(2049)
  output_mean/output_scale: output denormalization
"""

import argparse
import json
import os
import sys
import time

import numpy as np
import torch


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

STEM_NAMES = ["vocals", "drums", "bass", "other"]

DEFAULT_OUTPUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "PhospheneEngine", "Sources", "ML", "Weights",
)


# ---------------------------------------------------------------------------
# Model loading
# ---------------------------------------------------------------------------

def load_openunmix():
    """Load pre-trained Open-Unmix HQ separator."""
    print("[1/3] Loading Open-Unmix HQ model via openunmix...")
    import openunmix
    separator = openunmix.umxhq(device="cpu")
    separator.eval()
    print(f"       Stems: {STEM_NAMES}")
    print(f"       Target models: {list(separator.target_models.keys())}")
    return separator


# ---------------------------------------------------------------------------
# Weight extraction
# ---------------------------------------------------------------------------

def extract_stem_tensors(stem_model, stem_name):
    """Extract all named parameters and buffers from a single stem model.

    Returns a list of (name, tensor) tuples with stem-prefixed names.
    Parameters are .weight/.bias from nn.Linear/nn.BatchNorm/nn.LSTM.
    Buffers are input_mean, input_scale, output_mean, output_scale,
    and bn running_mean/running_var.
    """
    tensors = []

    # Named parameters: fc1.weight, fc1.bias, bn1.weight, bn1.bias,
    # lstm.weight_ih_l0, ..., fc2.*, bn2.*, fc3.*, bn3.*
    for name, param in stem_model.named_parameters():
        tensors.append((f"{stem_name}.{name}", param.detach()))

    # Named buffers: input_mean, input_scale, output_mean, output_scale,
    # bn1.running_mean, bn1.running_var, bn1.num_batches_tracked, etc.
    for name, buf in stem_model.named_buffers():
        # Skip num_batches_tracked — it's an int64 counter, not a weight
        if "num_batches_tracked" in name:
            continue
        tensors.append((f"{stem_name}.{name}", buf.detach()))

    return tensors


def extract_all_weights(separator):
    """Extract weight tensors from all 4 stem models.

    Returns a list of (name, numpy_array) tuples.
    """
    print("[2/3] Extracting weight tensors...")
    all_tensors = []

    for stem_name in STEM_NAMES:
        stem_model = separator.target_models[stem_name]
        tensors = extract_stem_tensors(stem_model, stem_name)
        all_tensors.extend(tensors)
        param_count = sum(t.numel() for _, t in tensors)
        print(f"       {stem_name}: {len(tensors)} tensors, "
              f"{param_count:,} elements")

    total_elements = sum(t.numel() for _, t in all_tensors)
    total_bytes = total_elements * 4  # float32
    print(f"       Total: {len(all_tensors)} tensors, "
          f"{total_elements:,} elements, "
          f"{total_bytes / 1024 / 1024:.1f} MB")

    return [(name, t.numpy().astype(np.float32)) for name, t in all_tensors]


# ---------------------------------------------------------------------------
# Save to disk
# ---------------------------------------------------------------------------

def save_weights(tensors, output_dir):
    """Save each tensor as a raw .bin file and write manifest.json.

    Each .bin file contains C-contiguous float32 data (no header).
    The manifest maps tensor names to their metadata.
    """
    print(f"[3/3] Saving to {output_dir}/")
    os.makedirs(output_dir, exist_ok=True)

    manifest = {
        "format_version": 1,
        "model": "umxhq",
        "description": "Open-Unmix HQ weight tensors for MPSGraph inference",
        "stems": STEM_NAMES,
        "dtype": "float32",
        "byte_order": "little-endian",
        "tensors": {},
    }

    for name, array in tensors:
        # Ensure C-contiguous
        array = np.ascontiguousarray(array)

        # Filename: replace dots with underscores for filesystem safety
        filename = name.replace(".", "_") + ".bin"
        filepath = os.path.join(output_dir, filename)

        array.tofile(filepath)

        manifest["tensors"][name] = {
            "file": filename,
            "shape": list(array.shape),
            "dtype": "float32",
            "bytes": array.nbytes,
        }

    # Write manifest
    manifest_path = os.path.join(output_dir, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    total_bytes = sum(t["bytes"] for t in manifest["tensors"].values())
    print(f"       {len(manifest['tensors'])} files + manifest.json")
    print(f"       Total: {total_bytes / 1024 / 1024:.1f} MB")

    return manifest


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Extract Open-Unmix HQ weights to raw float32 .bin files"
    )
    parser.add_argument(
        "--output", "-o",
        default=DEFAULT_OUTPUT_DIR,
        help=f"Output directory (default: {DEFAULT_OUTPUT_DIR})",
    )
    args = parser.parse_args()

    start = time.time()

    separator = load_openunmix()
    tensors = extract_all_weights(separator)
    manifest = save_weights(tensors, args.output)

    elapsed = time.time() - start
    print(f"\nDone in {elapsed:.1f}s. "
          f"Manifest: {os.path.join(args.output, 'manifest.json')}")

    # Summary table
    print("\n--- Per-stem tensor summary ---")
    for stem in STEM_NAMES:
        stem_tensors = {
            k: v for k, v in manifest["tensors"].items()
            if k.startswith(f"{stem}.")
        }
        n_tensors = len(stem_tensors)
        n_bytes = sum(v["bytes"] for v in stem_tensors.values())
        print(f"  {stem:8s}: {n_tensors:3d} tensors, "
              f"{n_bytes / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()

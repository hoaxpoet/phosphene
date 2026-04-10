#!/usr/bin/env python3
"""
Validate extracted Open-Unmix HQ weight tensors against architecture constants.

Loads manifest.json from the Weights directory and verifies:
  1. All expected tensors are present (4 stems × 43 tensors = 172 total)
  2. Tensor shapes match Open-Unmix HQ architecture constants
  3. All files exist on disk and have correct byte sizes
  4. Data is valid float32 (no NaN/Inf)
  5. Weight statistics are reasonable (not all zeros, bounded values)
  6. Manifest metadata is well-formed

Usage:
    python tools/test_umx_weights.py [--weights-dir DIR]

Requires: numpy (no torch dependency — validates purely from .bin files)
"""

import argparse
import json
import os
import sys

import numpy as np


# ---------------------------------------------------------------------------
# Architecture constants (must match StemSeparator.swift / convert_stem_model.py)
# ---------------------------------------------------------------------------

STEM_NAMES = ["vocals", "drums", "bass", "other"]
NB_BINS = 2049           # N_FFT/2 + 1 = 4096/2 + 1
NB_OUTPUT_BINS = 4098    # 2 channels × 2049 (fc3/bn3 output both channels)
UMX_NB_BINS = 1487       # Bandwidth-limited input bins
HIDDEN_SIZE = 512
LSTM_LAYERS = 3
LSTM_HIDDEN = 256        # Bidirectional → 512 output
FC1_IN = 2 * UMX_NB_BINS  # 2974 (2 channels × 1487 bins)
FC2_IN = 2 * HIDDEN_SIZE  # 1024 (skip connection: 512 + 512)

# Expected tensor shapes per stem.
# Open-Unmix uses bias=False on all Linear layers (bias folded into BatchNorm).
EXPECTED_TENSORS = {
    # Input normalization
    "input_mean": [UMX_NB_BINS],         # [1487]
    "input_scale": [UMX_NB_BINS],        # [1487]

    # FC1: Linear(2974, 512, bias=False)
    "fc1.weight": [HIDDEN_SIZE, FC1_IN],  # [512, 2974]

    # BN1: BatchNorm1d(512)
    "bn1.weight": [HIDDEN_SIZE],
    "bn1.bias": [HIDDEN_SIZE],
    "bn1.running_mean": [HIDDEN_SIZE],
    "bn1.running_var": [HIDDEN_SIZE],

    # FC2: Linear(1024, 512, bias=False)
    "fc2.weight": [HIDDEN_SIZE, FC2_IN],  # [512, 1024]

    # BN2: BatchNorm1d(512)
    "bn2.weight": [HIDDEN_SIZE],
    "bn2.bias": [HIDDEN_SIZE],
    "bn2.running_mean": [HIDDEN_SIZE],
    "bn2.running_var": [HIDDEN_SIZE],

    # FC3: Linear(512, 4098, bias=False) — outputs 2 channels × 2049 bins
    "fc3.weight": [NB_OUTPUT_BINS, HIDDEN_SIZE],  # [4098, 512]

    # BN3: BatchNorm1d(4098)
    "bn3.weight": [NB_OUTPUT_BINS],
    "bn3.bias": [NB_OUTPUT_BINS],
    "bn3.running_mean": [NB_OUTPUT_BINS],
    "bn3.running_var": [NB_OUTPUT_BINS],

    # Output normalization (per-channel, applied after reshape)
    "output_mean": [NB_BINS],    # [2049]
    "output_scale": [NB_BINS],   # [2049]
}

# LSTM: 3 layers, bidirectional, input_size=512, hidden_size=256
# LSTM gate size = 4 * hidden_size = 1024
# weight_ih: [gate_size, input_size] = [1024, 512]
# weight_hh: [gate_size, hidden_size] = [1024, 256]
# bias: [gate_size] = [1024]
LSTM_GATE_SIZE = 4 * LSTM_HIDDEN  # 1024

for layer in range(LSTM_LAYERS):
    # Forward direction
    EXPECTED_TENSORS[f"lstm.weight_ih_l{layer}"] = [LSTM_GATE_SIZE, HIDDEN_SIZE]
    EXPECTED_TENSORS[f"lstm.weight_hh_l{layer}"] = [LSTM_GATE_SIZE, LSTM_HIDDEN]
    EXPECTED_TENSORS[f"lstm.bias_ih_l{layer}"] = [LSTM_GATE_SIZE]
    EXPECTED_TENSORS[f"lstm.bias_hh_l{layer}"] = [LSTM_GATE_SIZE]
    # Reverse direction
    EXPECTED_TENSORS[f"lstm.weight_ih_l{layer}_reverse"] = [LSTM_GATE_SIZE, HIDDEN_SIZE]
    EXPECTED_TENSORS[f"lstm.weight_hh_l{layer}_reverse"] = [LSTM_GATE_SIZE, LSTM_HIDDEN]
    EXPECTED_TENSORS[f"lstm.bias_ih_l{layer}_reverse"] = [LSTM_GATE_SIZE]
    EXPECTED_TENSORS[f"lstm.bias_hh_l{layer}_reverse"] = [LSTM_GATE_SIZE]


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def validate_manifest(manifest, weights_dir):
    """Validate manifest structure and metadata."""
    errors = []

    if manifest.get("format_version") != 1:
        errors.append(f"Unexpected format_version: {manifest.get('format_version')}")

    if manifest.get("model") != "umxhq":
        errors.append(f"Unexpected model: {manifest.get('model')}")

    if manifest.get("dtype") != "float32":
        errors.append(f"Unexpected dtype: {manifest.get('dtype')}")

    if manifest.get("stems") != STEM_NAMES:
        errors.append(f"Unexpected stems: {manifest.get('stems')}")

    if "tensors" not in manifest:
        errors.append("Missing 'tensors' key")

    return errors


def validate_tensor_presence(manifest):
    """Check that all expected tensors are present for all stems."""
    errors = []
    tensors = manifest.get("tensors", {})

    for stem in STEM_NAMES:
        for tensor_name in EXPECTED_TENSORS:
            full_name = f"{stem}.{tensor_name}"
            if full_name not in tensors:
                errors.append(f"Missing tensor: {full_name}")

    # Check for unexpected tensors
    expected_names = set()
    for stem in STEM_NAMES:
        for tensor_name in EXPECTED_TENSORS:
            expected_names.add(f"{stem}.{tensor_name}")

    for name in tensors:
        if name not in expected_names:
            errors.append(f"Unexpected tensor: {name}")

    return errors


def validate_shapes(manifest):
    """Check that all tensor shapes match architecture constants."""
    errors = []
    tensors = manifest.get("tensors", {})

    for stem in STEM_NAMES:
        for tensor_name, expected_shape in EXPECTED_TENSORS.items():
            full_name = f"{stem}.{tensor_name}"
            if full_name not in tensors:
                continue  # Already caught by presence check

            actual_shape = tensors[full_name]["shape"]
            if actual_shape != expected_shape:
                errors.append(
                    f"{full_name}: expected shape {expected_shape}, "
                    f"got {actual_shape}"
                )

    return errors


def validate_files(manifest, weights_dir):
    """Check that all .bin files exist and have correct byte sizes."""
    errors = []
    tensors = manifest.get("tensors", {})

    for name, info in tensors.items():
        filepath = os.path.join(weights_dir, info["file"])

        if not os.path.exists(filepath):
            errors.append(f"{name}: file not found: {info['file']}")
            continue

        actual_size = os.path.getsize(filepath)
        expected_size = info["bytes"]
        if actual_size != expected_size:
            errors.append(
                f"{name}: expected {expected_size} bytes, "
                f"got {actual_size} in {info['file']}"
            )

        # Verify byte count matches shape × 4 (float32)
        n_elements = 1
        for dim in info["shape"]:
            n_elements *= dim
        expected_from_shape = n_elements * 4
        if expected_size != expected_from_shape:
            errors.append(
                f"{name}: manifest bytes ({expected_size}) doesn't match "
                f"shape {info['shape']} × 4 = {expected_from_shape}"
            )

    return errors


def validate_data(manifest, weights_dir):
    """Check all tensor data for NaN/Inf and reasonable statistics."""
    errors = []
    tensors = manifest.get("tensors", {})

    checked = 0
    for name, info in tensors.items():
        filepath = os.path.join(weights_dir, info["file"])
        if not os.path.exists(filepath):
            continue

        data = np.fromfile(filepath, dtype=np.float32)

        if np.any(np.isnan(data)):
            errors.append(f"{name}: contains NaN values")

        if np.any(np.isinf(data)):
            errors.append(f"{name}: contains Inf values")

        if np.all(data == 0):
            # running_mean can be all zeros legitimately, but weights shouldn't
            if "running_mean" not in name:
                errors.append(f"{name}: all zeros (suspicious)")

        # Sanity: weights should be bounded. BatchNorm running_var can
        # legitimately be large (unbiased variance from training), so use
        # a higher threshold for those.
        max_abs = np.max(np.abs(data))
        threshold = 10000 if "running_var" in name else 1000
        if max_abs > threshold:
            errors.append(
                f"{name}: max |value| = {max_abs:.1f} (exceeds {threshold})"
            )

        checked += 1

    if checked == 0:
        errors.append("No tensor files could be validated")

    return errors


def validate_total_count(manifest):
    """Check expected total tensor count: 4 stems × 43 tensors = 172."""
    errors = []
    expected_per_stem = len(EXPECTED_TENSORS)
    expected_total = len(STEM_NAMES) * expected_per_stem
    actual_total = len(manifest.get("tensors", {}))

    if actual_total != expected_total:
        errors.append(
            f"Expected {expected_total} tensors "
            f"({len(STEM_NAMES)} stems × {expected_per_stem} per stem), "
            f"got {actual_total}"
        )

    return errors


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Validate extracted Open-Unmix HQ weight tensors"
    )
    parser.add_argument(
        "--weights-dir", "-w",
        default=os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "PhospheneEngine", "Sources", "ML", "Weights",
        ),
        help="Directory containing .bin files and manifest.json",
    )
    args = parser.parse_args()

    weights_dir = args.weights_dir
    manifest_path = os.path.join(weights_dir, "manifest.json")

    print(f"Validating weights in: {weights_dir}")
    print()

    if not os.path.exists(manifest_path):
        print(f"FAIL: manifest.json not found at {manifest_path}")
        sys.exit(1)

    with open(manifest_path) as f:
        manifest = json.load(f)

    # Run all validations
    checks = [
        ("Manifest metadata", validate_manifest, (manifest, weights_dir)),
        ("Total tensor count", validate_total_count, (manifest,)),
        ("Tensor presence", validate_tensor_presence, (manifest,)),
        ("Tensor shapes", validate_shapes, (manifest,)),
        ("File existence and sizes", validate_files, (manifest, weights_dir)),
        ("Data validity (NaN/Inf/zeros)", validate_data, (manifest, weights_dir)),
    ]

    total_errors = 0
    for check_name, check_fn, check_args in checks:
        errors = check_fn(*check_args)
        status = "PASS" if not errors else "FAIL"
        print(f"  [{status}] {check_name}")
        for err in errors:
            print(f"         {err}")
            total_errors += 1

    print()
    if total_errors == 0:
        n_tensors = len(manifest.get("tensors", {}))
        total_bytes = sum(
            t["bytes"] for t in manifest["tensors"].values()
        )
        print(f"All checks passed. {n_tensors} tensors, "
              f"{total_bytes / 1024 / 1024:.1f} MB total.")
        sys.exit(0)
    else:
        print(f"FAILED: {total_errors} error(s)")
        sys.exit(1)


if __name__ == "__main__":
    main()

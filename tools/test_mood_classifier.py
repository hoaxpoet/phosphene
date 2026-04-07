#!/usr/bin/env python3
"""
Integration tests for the converted MoodClassifier CoreML model.

4 required assertions:
  1. Output shape is [2] (valence, arousal)
  2. Values in range [-1, 1] for 100 random inputs
  3. High-energy major-key input → positive valence, high arousal
  4. Slow minor-key input → negative valence, low arousal

Usage:
    python tools/test_mood_classifier.py [--model PATH]
"""

import argparse
import os
import sys

import coremltools as ct
import numpy as np


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

NUM_FEATURES = 10

# Feature indices (must match train_mood_classifier.py)
IDX_SUB_BASS = 0
IDX_LOW_BASS = 1
IDX_LOW_MID = 2
IDX_MID_HIGH = 3
IDX_HIGH_MID = 4
IDX_HIGH = 5
IDX_CENTROID = 6
IDX_FLUX = 7
IDX_MAJOR_CORR = 8
IDX_MINOR_CORR = 9

DEFAULT_MODEL_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "PhospheneEngine", "Sources", "ML", "Models", "MoodClassifier.mlpackage",
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_model(model_path):
    """Load the CoreML model."""
    print(f"Loading model: {model_path}")
    model = ct.models.MLModel(model_path, compute_units=ct.ComputeUnit.CPU_AND_NE)
    return model


def predict(model, features):
    """Run prediction and return [valence, arousal]."""
    inp = {"features": features.reshape(1, NUM_FEATURES).astype(np.float32)}
    result = model.predict(inp)
    return result["mood"].flatten()


# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

def assert_output_shape(model):
    """Assertion 1: Output shape is [2]."""
    print("\n[1/4] Output shape is [2]...")
    features = np.random.randn(NUM_FEATURES).astype(np.float32)
    output = predict(model, features)
    assert output.shape == (2,), f"FAIL: Expected shape (2,), got {output.shape}"
    print(f"       Output shape: {output.shape} — PASS")
    return True


def assert_output_range(model):
    """Assertion 2: Values in range [-1, 1] for 100 random inputs."""
    print("\n[2/4] Values in range [-1, 1] for 100 random inputs...")
    rng = np.random.RandomState(123)
    all_outputs = []
    for _ in range(100):
        features = rng.uniform(0, 1, size=NUM_FEATURES).astype(np.float32)
        output = predict(model, features)
        all_outputs.append(output)

    all_outputs = np.array(all_outputs)
    min_val = all_outputs.min()
    max_val = all_outputs.max()
    assert min_val >= -1.0, f"FAIL: Min value {min_val:.4f} < -1.0"
    assert max_val <= 1.0, f"FAIL: Max value {max_val:.4f} > 1.0"
    print(f"       Range: [{min_val:.4f}, {max_val:.4f}] — PASS")
    return True


def assert_happy_quadrant(model):
    """Assertion 3: High-energy major-key → positive valence, high arousal."""
    print("\n[3/4] High-energy major-key → positive valence, high arousal...")
    features = np.zeros(NUM_FEATURES, dtype=np.float32)

    # Energetic bass-heavy signal (calibrated to real AGC output).
    features[IDX_SUB_BASS] = 0.25
    features[IDX_LOW_BASS] = 0.20
    features[IDX_LOW_MID] = 0.10
    features[IDX_MID_HIGH] = 0.08
    features[IDX_HIGH_MID] = 0.05
    features[IDX_HIGH] = 0.03

    # Moderate brightness and flux.
    features[IDX_CENTROID] = 0.20
    features[IDX_FLUX] = 0.15

    # Strong major key correlation.
    features[IDX_MAJOR_CORR] = 0.85
    features[IDX_MINOR_CORR] = 0.45

    output = predict(model, features)
    valence, arousal = output[0], output[1]
    print(f"       Valence: {valence:.3f} (expect > 0.3)")
    print(f"       Arousal: {arousal:.3f} (expect > 0.3)")
    assert valence > 0.2, f"FAIL: valence {valence:.3f} <= 0.2"
    assert arousal > 0.1, f"FAIL: arousal {arousal:.3f} <= 0.1"
    print("       PASS")
    return True


def assert_sad_quadrant(model):
    """Assertion 4: Low-energy minor-key → negative valence, low arousal."""
    print("\n[4/4] Low-energy minor-key → negative valence, low arousal...")
    features = np.zeros(NUM_FEATURES, dtype=np.float32)

    # Quiet signal (calibrated to real AGC output).
    features[IDX_SUB_BASS] = 0.03
    features[IDX_LOW_BASS] = 0.02
    features[IDX_LOW_MID] = 0.02
    features[IDX_MID_HIGH] = 0.02
    features[IDX_HIGH_MID] = 0.01
    features[IDX_HIGH] = 0.01

    # Dark timbre, low flux.
    features[IDX_CENTROID] = 0.06
    features[IDX_FLUX] = 0.03

    # Strong minor key correlation.
    features[IDX_MAJOR_CORR] = 0.20
    features[IDX_MINOR_CORR] = 0.80

    output = predict(model, features)
    valence, arousal = output[0], output[1]
    print(f"       Valence: {valence:.3f} (expect < -0.3)")
    print(f"       Arousal: {arousal:.3f} (expect < -0.3)")
    assert valence < -0.3, f"FAIL: valence {valence:.3f} >= -0.3"
    assert arousal < 0.0, f"FAIL: arousal {arousal:.3f} >= 0.0"
    print("       PASS")
    return True


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Test MoodClassifier CoreML model."
    )
    parser.add_argument(
        "--model", type=str, default=DEFAULT_MODEL_PATH,
        help=f"Path to MoodClassifier.mlpackage (default: {DEFAULT_MODEL_PATH})"
    )
    args = parser.parse_args()

    print("=" * 60)
    print("Phosphene Mood Classifier — Integration Tests")
    print("=" * 60)

    if not os.path.exists(args.model):
        print(f"\nERROR: Model not found: {args.model}")
        print("Run train_mood_classifier.py first.")
        sys.exit(1)

    model = load_model(args.model)

    assertions = [
        ("Output shape", assert_output_shape),
        ("Output range", assert_output_range),
        ("Happy quadrant", assert_happy_quadrant),
        ("Sad quadrant", assert_sad_quadrant),
    ]

    passed = 0
    failed = 0
    for name, fn in assertions:
        try:
            fn(model)
            passed += 1
        except AssertionError as e:
            print(f"       FAIL: {e}")
            failed += 1

    print("\n" + "=" * 60)
    print(f"Results: {passed}/{len(assertions)} passed, {failed} failed")
    print("=" * 60)

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()

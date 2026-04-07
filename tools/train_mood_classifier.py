#!/usr/bin/env python3
"""
Train a lightweight MLP mood classifier and export to CoreML .mlpackage for ANE.

The model maps 10 audio features (computed by MIRPipeline in Swift) to continuous
valence/arousal values in [-1, 1], following Russell's circumplex model of affect.

Input features (10 floats):
  [0-5]:  6-band energy (subBass, lowBass, lowMid, midHigh, highMid, high)
  [6]:    spectralCentroid (normalized 0-1 by Nyquist)
  [7]:    spectralFlux (normalized 0-1 via running max)
  [8]:    majorKeyCorrelation (best Pearson r with any major key profile, 0-1)
  [9]:    minorKeyCorrelation (best Pearson r with any minor key profile, 0-1)

Output (2 floats):
  [0]: valence  — -1 (sad/tense) to +1 (happy/calm)
  [1]: arousal  — -1 (calm/relaxed) to +1 (energetic/excited)

Training data is rule-based (no external labeled dataset). The rules encode
music-theory-informed relationships between spectral features and emotional
perception. The MLP learns smooth interpolation over these rules, which is
more suitable for ANE inference than raw heuristics in Swift.

Usage:
    python tools/train_mood_classifier.py [--output PATH] [--samples N] [--epochs N]
"""

import argparse
import os
import time

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

NUM_FEATURES = 10
NUM_OUTPUTS = 2  # valence, arousal

# Feature indices
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

DEFAULT_OUTPUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "PhospheneEngine", "Sources", "ML", "Models",
)


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------

class MoodClassifier(nn.Module):
    """Lightweight MLP: 10 -> 32 (ReLU) -> 16 (ReLU) -> 2 (tanh)."""

    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(NUM_FEATURES, 32),
            nn.ReLU(),
            nn.Linear(32, 16),
            nn.ReLU(),
            nn.Linear(16, NUM_OUTPUTS),
            nn.Tanh(),
        )

    def forward(self, x):
        return self.net(x)


# ---------------------------------------------------------------------------
# Training data generation (rule-based)
# ---------------------------------------------------------------------------

def compute_valence(features):
    """Rule-based valence from audio features.

    Major key correlation → positive valence, minor → negative.
    Confidence-weighted so ambiguous keys produce near-zero valence.
    Higher spectral centroid (brightness) adds slight positive bias.
    """
    major_corr = features[IDX_MAJOR_CORR]
    minor_corr = features[IDX_MINOR_CORR]
    centroid = features[IDX_CENTROID]

    # Key mode is the primary valence driver.
    # When major > minor → positive; when minor > major → negative.
    # Scale by the winning correlation's strength (confidence).
    mode_diff = major_corr - minor_corr
    confidence = max(major_corr, minor_corr)
    key_valence = np.sign(mode_diff) * confidence * 1.2

    # Brightness adds slight positive bias.
    brightness_bias = (centroid - 0.3) * 0.4

    valence = np.clip(key_valence + brightness_bias, -1.0, 1.0)
    return float(valence)


def compute_arousal(features):
    """Rule-based arousal from audio features.

    Total energy → primary arousal driver.
    Spectral flux (timbral change) → secondary arousal driver.
    Low-frequency dominance → slight arousal boost (kick-heavy = energetic).
    """
    energy = features[IDX_SUB_BASS:IDX_HIGH + 1]
    flux = features[IDX_FLUX]

    # Total energy is the primary arousal driver.
    # 6-band AGC output: per-band mean ~0.08 for average music.
    # Energetic: ~0.12, quiet: ~0.04. Use bass weight since it varies most.
    total_energy = energy.mean()
    bass_weight = (energy[0] + energy[1]) * 0.5  # sub_bass + low_bass avg
    weighted_energy = total_energy * 0.4 + bass_weight * 0.6
    energy_arousal = (weighted_energy - 0.08) * 8.0

    # Spectral flux adds arousal (rapid timbral change = exciting).
    flux_arousal = (flux - 0.08) * 1.5

    arousal = np.clip(energy_arousal + flux_arousal, -1.0, 1.0)
    return float(arousal)


def generate_training_data(num_samples, seed=42):
    """Generate synthetic training data with rule-based valence/arousal targets.

    Features are sampled from realistic distributions matching MIRPipeline output.
    """
    rng = np.random.RandomState(seed)

    features = np.zeros((num_samples, NUM_FEATURES), dtype=np.float32)
    targets = np.zeros((num_samples, NUM_OUTPUTS), dtype=np.float32)

    for i in range(num_samples):
        # 6-band energy after AGC: total ~0.5 spread across 6 bands.
        # Per-band typical range: 0.01–0.30. Bass-heavy music: bass ~0.25, high ~0.02.
        # Calibrated from live Core Audio tap diagnostics.
        energy = rng.beta(1.5, 5, size=6).astype(np.float32) * 0.35 + 0.01
        features[i, IDX_SUB_BASS:IDX_HIGH + 1] = energy

        # Spectral centroid: typically 0.05–0.40 from real diagnostics.
        features[i, IDX_CENTROID] = rng.beta(2, 6) * 0.4 + 0.03

        # Spectral flux: typically 0.02–0.30, occasional spikes to 1.0.
        features[i, IDX_FLUX] = rng.beta(1.5, 8) * 0.4 + 0.01

        # Major/minor key correlations (pre-computed from chroma by ChromaExtractor).
        # Realistic ranges: 0–1, with one typically dominating.
        if rng.random() < 0.3:
            # Ambiguous/atonal: both low.
            features[i, IDX_MAJOR_CORR] = rng.uniform(0.0, 0.3)
            features[i, IDX_MINOR_CORR] = rng.uniform(0.0, 0.3)
        elif rng.random() < 0.5:
            # Clear major key.
            features[i, IDX_MAJOR_CORR] = rng.uniform(0.5, 1.0)
            features[i, IDX_MINOR_CORR] = rng.uniform(0.1, features[i, IDX_MAJOR_CORR] - 0.1)
        else:
            # Clear minor key.
            features[i, IDX_MINOR_CORR] = rng.uniform(0.5, 1.0)
            features[i, IDX_MAJOR_CORR] = rng.uniform(0.1, features[i, IDX_MINOR_CORR] - 0.1)

        # Compute targets from rules.
        targets[i, 0] = compute_valence(features[i])
        targets[i, 1] = compute_arousal(features[i])

    # Add small noise to targets for regularization.
    noise = rng.normal(0, 0.02, size=targets.shape).astype(np.float32)
    targets = np.clip(targets + noise, -1.0, 1.0)

    return features, targets


# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------

def train_model(num_samples=50000, epochs=300, lr=1e-3, seed=42):
    """Train the MLP on synthetic rule-based data."""
    print(f"[1/4] Generating {num_samples} training samples...")
    features, targets = generate_training_data(num_samples, seed=seed)

    # Split 90/10 train/val.
    split = int(num_samples * 0.9)
    train_x = torch.from_numpy(features[:split])
    train_y = torch.from_numpy(targets[:split])
    val_x = torch.from_numpy(features[split:])
    val_y = torch.from_numpy(targets[split:])

    model = MoodClassifier()
    optimizer = optim.Adam(model.parameters(), lr=lr)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    loss_fn = nn.MSELoss()

    print(f"[2/4] Training for {epochs} epochs...")
    print(f"       Model: {sum(p.numel() for p in model.parameters())} parameters")
    t0 = time.time()

    best_val_loss = float("inf")
    best_state = None

    for epoch in range(epochs):
        model.train()
        pred = model(train_x)
        loss = loss_fn(pred, train_y)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
        scheduler.step()

        if (epoch + 1) % 50 == 0 or epoch == 0:
            model.eval()
            with torch.no_grad():
                val_pred = model(val_x)
                val_loss = loss_fn(val_pred, val_y).item()
            if val_loss < best_val_loss:
                best_val_loss = val_loss
                best_state = {k: v.clone() for k, v in model.state_dict().items()}
            print(f"       Epoch {epoch + 1:4d}: train_loss={loss.item():.6f}  "
                  f"val_loss={val_loss:.6f}")

    elapsed = time.time() - t0
    print(f"       Training complete in {elapsed:.1f}s, best val_loss={best_val_loss:.6f}")

    # Restore best model.
    if best_state is not None:
        model.load_state_dict(best_state)
    model.eval()
    return model


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def validate_model(model):
    """Quick sanity checks before CoreML conversion."""
    print("[3/4] Validating model...")

    # Check output range.
    rng = np.random.RandomState(99)
    test_input = torch.from_numpy(
        rng.uniform(0, 1, size=(100, NUM_FEATURES)).astype(np.float32)
    )
    with torch.no_grad():
        output = model(test_input).numpy()

    assert output.shape == (100, 2), f"Unexpected output shape: {output.shape}"
    assert np.all(output >= -1.0) and np.all(output <= 1.0), \
        f"Output out of range: min={output.min():.3f}, max={output.max():.3f}"

    # Check major-key high-energy → positive valence, high arousal.
    # Values calibrated to real Core Audio tap AGC output.
    major_input = np.zeros((1, NUM_FEATURES), dtype=np.float32)
    major_input[0, IDX_SUB_BASS] = 0.25   # energetic bass
    major_input[0, IDX_LOW_BASS] = 0.20
    major_input[0, IDX_LOW_MID] = 0.10
    major_input[0, IDX_MID_HIGH] = 0.08
    major_input[0, IDX_HIGH_MID] = 0.05
    major_input[0, IDX_HIGH] = 0.03
    major_input[0, IDX_CENTROID] = 0.20  # moderate brightness
    major_input[0, IDX_FLUX] = 0.15  # moderate flux
    major_input[0, IDX_MAJOR_CORR] = 0.85  # strong major key
    major_input[0, IDX_MINOR_CORR] = 0.45  # weaker minor

    with torch.no_grad():
        major_out = model(torch.from_numpy(major_input)).numpy()[0]
    print(f"       Major-key high-energy: valence={major_out[0]:.3f}, arousal={major_out[1]:.3f}")
    assert major_out[0] > 0.2, f"Expected valence > 0.2, got {major_out[0]:.3f}"
    assert major_out[1] > 0.1, f"Expected arousal > 0.1, got {major_out[1]:.3f}"

    # Check minor-key low-energy → negative valence, low arousal.
    minor_input = np.zeros((1, NUM_FEATURES), dtype=np.float32)
    minor_input[0, IDX_SUB_BASS] = 0.03   # quiet
    minor_input[0, IDX_LOW_BASS] = 0.02
    minor_input[0, IDX_LOW_MID] = 0.02
    minor_input[0, IDX_MID_HIGH] = 0.02
    minor_input[0, IDX_HIGH_MID] = 0.01
    minor_input[0, IDX_HIGH] = 0.01
    minor_input[0, IDX_CENTROID] = 0.06  # dark
    minor_input[0, IDX_FLUX] = 0.03  # low flux
    minor_input[0, IDX_MAJOR_CORR] = 0.20  # weak major
    minor_input[0, IDX_MINOR_CORR] = 0.80  # strong minor key

    with torch.no_grad():
        minor_out = model(torch.from_numpy(minor_input)).numpy()[0]
    print(f"       Minor-key low-energy:  valence={minor_out[0]:.3f}, arousal={minor_out[1]:.3f}")
    assert minor_out[0] < -0.3, f"Expected valence < -0.3, got {minor_out[0]:.3f}"
    assert minor_out[1] < 0.0, f"Expected arousal < 0, got {minor_out[1]:.3f}"

    print("       All validation checks passed.")


# ---------------------------------------------------------------------------
# CoreML conversion
# ---------------------------------------------------------------------------

def convert_to_coreml(model, output_dir):
    """Convert trained PyTorch model to CoreML .mlpackage."""
    print("[4/4] Converting to CoreML...")
    output_path = os.path.join(output_dir, "MoodClassifier.mlpackage")

    # Trace the model.
    example_input = torch.randn(1, NUM_FEATURES)
    traced = torch.jit.trace(model, example_input)

    # Convert to CoreML.
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="features", shape=(1, NUM_FEATURES))],
        outputs=[ct.TensorType(name="mood")],
        compute_units=ct.ComputeUnit.CPU_AND_NE,
        minimum_deployment_target=ct.target.macOS14,
    )

    # Add metadata.
    mlmodel.author = "Phosphene (auto-generated)"
    mlmodel.short_description = (
        "Lightweight valence/arousal mood classifier for music visualization. "
        "Input: 10 audio features (6-band energy, spectral centroid, flux, "
        "major/minor key correlations). "
        "Output: [valence, arousal] each in [-1, 1]."
    )
    mlmodel.input_description["features"] = (
        "10 audio features: [subBass, lowBass, lowMid, midHigh, highMid, high, "
        "centroid, flux, majorKeyCorrelation, minorKeyCorrelation]"
    )
    mlmodel.output_description["mood"] = (
        "2 values: [valence (-1=sad to +1=happy), arousal (-1=calm to +1=energetic)]"
    )

    # Save.
    os.makedirs(output_dir, exist_ok=True)
    mlmodel.save(output_path)

    # Verify round-trip.
    loaded = ct.models.MLModel(output_path, compute_units=ct.ComputeUnit.CPU_AND_NE)
    test_in = {"features": np.random.randn(1, NUM_FEATURES).astype(np.float32)}
    result = loaded.predict(test_in)
    mood = result["mood"]
    assert mood.shape == (1, 2), f"Unexpected CoreML output shape: {mood.shape}"

    size_mb = sum(
        os.path.getsize(os.path.join(dp, f))
        for dp, _, filenames in os.walk(output_path)
        for f in filenames
    ) / (1024 * 1024)

    print(f"       Saved: {output_path}")
    print(f"       Size: {size_mb:.2f} MB")
    print(f"       CoreML round-trip verified.")
    return output_path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Train mood classifier and export to CoreML."
    )
    parser.add_argument(
        "--output", type=str, default=DEFAULT_OUTPUT_DIR,
        help=f"Output directory for .mlpackage (default: {DEFAULT_OUTPUT_DIR})"
    )
    parser.add_argument(
        "--samples", type=int, default=50000,
        help="Number of training samples (default: 50000)"
    )
    parser.add_argument(
        "--epochs", type=int, default=300,
        help="Training epochs (default: 300)"
    )
    parser.add_argument(
        "--seed", type=int, default=42,
        help="Random seed (default: 42)"
    )
    args = parser.parse_args()

    print("=" * 60)
    print("Phosphene Mood Classifier — Training Pipeline")
    print("=" * 60)
    print(f"Architecture: {NUM_FEATURES} -> 32 (ReLU) -> 16 (ReLU) -> {NUM_OUTPUTS} (tanh)")
    print(f"Samples: {args.samples}, Epochs: {args.epochs}, Seed: {args.seed}")
    print()

    model = train_model(
        num_samples=args.samples,
        epochs=args.epochs,
        seed=args.seed,
    )
    validate_model(model)
    output_path = convert_to_coreml(model, args.output)

    print()
    print("=" * 60)
    print(f"Done. Model saved to: {output_path}")
    print("=" * 60)


if __name__ == "__main__":
    main()

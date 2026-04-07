#!/usr/bin/env python3
"""
Train mood classifier on live-pipeline annotated features.

Input: CSV with columns [timestamp, track, artist, 10 features..., stableKey,
       stableBPM, valence, arousal] — exported from Phosphene recording mode
       with manual V/A annotations propagated to all rows.

The model trains on EXACTLY the same feature distribution it sees at inference.
No librosa. No DEAM. No distribution mismatch.

Usage:
    python tools/train_mood_from_live.py [--input PATH] [--epochs N] [--output PATH]
"""

import argparse
import json
import os
import sys

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim


# Feature columns in the CSV (indices 3-12, 0-indexed)
FEATURE_COLS = [
    "subBass", "lowBass", "lowMid", "midHigh", "highMid", "high",
    "centroid", "flux", "majorCorr", "minorCorr",
]
NUM_FEATURES = 10
NUM_OUTPUTS = 2

DEFAULT_INPUT = os.path.expanduser("~/phosphene_features_annotated.csv")
DEFAULT_OUTPUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "PhospheneEngine", "Sources", "ML", "Models",
)
DEFAULT_SCALER = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "data", "mood_scaler.json"
)


class MoodClassifier(nn.Module):
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(NUM_FEATURES, 64),
            nn.ReLU(),
            nn.Linear(64, 32),
            nn.ReLU(),
            nn.Linear(32, 16),
            nn.ReLU(),
            nn.Linear(16, NUM_OUTPUTS),
            nn.Tanh(),
        )

    def forward(self, x):
        return self.net(x)


def load_data(csv_path):
    """Load annotated CSV. Returns features (N, 10) and targets (N, 2)."""
    import csv

    features = []
    targets = []
    tracks = []

    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            v = row.get("valence", "").strip()
            a = row.get("arousal", "").strip()
            if not v or not a:
                continue
            try:
                feat = [float(row[col]) for col in FEATURE_COLS]
                valence = float(v)
                arousal = float(a)
            except (ValueError, KeyError) as exc:
                print(f"  Skipping row: {exc}", file=sys.stderr)
                continue
            features.append(feat)
            targets.append([valence, arousal])
            tracks.append(row.get("track", ""))

    return (
        np.array(features, dtype=np.float32),
        np.array(targets, dtype=np.float32),
        tracks,
    )


def main():
    parser = argparse.ArgumentParser(
        description="Train mood classifier on live-pipeline features."
    )
    parser.add_argument("--input", default=DEFAULT_INPUT, help="Annotated CSV")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="Output dir")
    parser.add_argument("--scaler-output", default=DEFAULT_SCALER, help="Scaler JSON")
    parser.add_argument("--epochs", type=int, default=500)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    print("=" * 60)
    print("Phosphene Mood Classifier — Live Feature Training")
    print("=" * 60)

    # Load data
    print(f"\n[1/4] Loading {args.input}...")
    features, targets, tracks = load_data(args.input)
    print(f"  Loaded {len(features)} annotated rows")

    unique_tracks = sorted(set(tracks))
    print(f"  Tracks: {len(unique_tracks)}")
    for track in unique_tracks:
        count = tracks.count(track)
        idx = tracks.index(track)
        print(f"    {track:50s} {count:4d} rows  V={targets[idx, 0]:+.1f} A={targets[idx, 1]:+.1f}")

    # Z-score normalize features
    print("\n[2/4] Normalizing features...")
    means = features.mean(axis=0)
    stds = features.std(axis=0)
    stds[stds < 1e-10] = 1.0

    print(f"  {'Feature':>12s}  {'mean':>10s}  {'std':>10s}")
    for i, name in enumerate(FEATURE_COLS):
        print(f"  {name:>12s}  {means[i]:10.6f}  {stds[i]:10.6f}")

    normalized = (features - means) / stds

    # Save scaler
    os.makedirs(os.path.dirname(args.scaler_output), exist_ok=True)
    scaler = {
        "feature_names": FEATURE_COLS,
        "means": means.tolist(),
        "stds": stds.tolist(),
    }
    with open(args.scaler_output, "w") as f:
        json.dump(scaler, f, indent=2)
    print(f"  Saved scaler to {args.scaler_output}")

    # Train/val split (80/20, shuffled)
    rng = np.random.RandomState(args.seed)
    indices = rng.permutation(len(features))
    split = int(len(features) * 0.8)

    train_x = torch.from_numpy(normalized[indices[:split]])
    train_y = torch.from_numpy(targets[indices[:split]])
    val_x = torch.from_numpy(normalized[indices[split:]])
    val_y = torch.from_numpy(targets[indices[split:]])

    # Train
    print(f"\n[3/4] Training for {args.epochs} epochs...")
    model = MoodClassifier()
    print(f"  Model: {sum(p.numel() for p in model.parameters())} parameters")
    print(f"  Train: {len(train_x)}, Val: {len(val_x)}")

    optimizer = optim.Adam(model.parameters(), lr=0.001)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    loss_fn = nn.MSELoss()

    best_val_loss = float("inf")
    best_state = None

    for epoch in range(args.epochs):
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
                rmse_v = float(torch.sqrt(torch.mean((val_pred[:, 0] - val_y[:, 0]) ** 2)))
                rmse_a = float(torch.sqrt(torch.mean((val_pred[:, 1] - val_y[:, 1]) ** 2)))
            if val_loss < best_val_loss:
                best_val_loss = val_loss
                best_state = {k: v.clone() for k, v in model.state_dict().items()}
            print(f"  Epoch {epoch + 1:4d}: loss={loss.item():.6f}  "
                  f"val={val_loss:.6f}  rmse_v={rmse_v:.3f}  rmse_a={rmse_a:.3f}")

    if best_state:
        model.load_state_dict(best_state)
    model.eval()

    # Evaluate
    print("\n  Final evaluation (best model):")
    with torch.no_grad():
        val_pred = model(val_x)
        rmse_v = float(torch.sqrt(torch.mean((val_pred[:, 0] - val_y[:, 0]) ** 2)))
        rmse_a = float(torch.sqrt(torch.mean((val_pred[:, 1] - val_y[:, 1]) ** 2)))
    print(f"    Valence RMSE: {rmse_v:.3f}")
    print(f"    Arousal RMSE: {rmse_a:.3f}")

    # Per-track predictions
    print("\n  Per-track predictions:")
    with torch.no_grad():
        all_pred = model(torch.from_numpy(normalized)).numpy()
    for track in unique_tracks:
        idxs = [i for i, t in enumerate(tracks) if t == track]
        mean_pred_v = np.mean(all_pred[idxs, 0])
        mean_pred_a = np.mean(all_pred[idxs, 1])
        true_v = targets[idxs[0], 0]
        true_a = targets[idxs[0], 1]
        print(f"    {track:50s} true=({true_v:+.1f},{true_a:+.1f})  "
              f"pred=({mean_pred_v:+.2f},{mean_pred_a:+.2f})")

    # Export to CoreML
    print(f"\n[4/4] Converting to CoreML...")
    traced = torch.jit.trace(model, torch.randn(1, NUM_FEATURES))
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="features", shape=(1, NUM_FEATURES))],
        outputs=[ct.TensorType(name="mood")],
        compute_units=ct.ComputeUnit.CPU_AND_NE,
        minimum_deployment_target=ct.target.macOS14,
    )
    mlmodel.author = "Phosphene (live-pipeline trained)"
    mlmodel.short_description = (
        "Valence/arousal classifier trained on live Phosphene features "
        f"from {len(unique_tracks)} annotated tracks."
    )

    output_path = os.path.join(args.output, "MoodClassifier.mlpackage")
    os.makedirs(args.output, exist_ok=True)
    mlmodel.save(output_path)
    print(f"  Saved: {output_path}")

    print(f"\n{'=' * 60}")
    print("Done. Update MoodClassifier.swift scaler params from:")
    print(f"  {args.scaler_output}")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    main()

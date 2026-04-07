#!/usr/bin/env python3
"""
Train a mood classifier on the DEAM dataset and export to CoreML .mlpackage for ANE.

The model maps 10 audio features (matching Phosphene's MIRPipeline) to continuous
valence/arousal values in [-1, 1], following Russell's circumplex model of affect.

Input features (10 floats, z-score normalized):
  [0-5]:  6-band energy (subBass, lowBass, lowMid, midHigh, highMid, high)
  [6]:    spectralCentroid (normalized 0-1 by Nyquist)
  [7]:    spectralFlux (half-wave rectified frame-to-frame magnitude diff)
  [8]:    majorKeyCorrelation (best Pearson r with any major key profile, 0-1)
  [9]:    minorKeyCorrelation (best Pearson r with any minor key profile, 0-1)

Output (2 floats):
  [0]: valence  -- -1 (sad/tense) to +1 (happy/calm)
  [1]: arousal  -- -1 (calm/relaxed) to +1 (energetic/excited)

Training data: DEAM dataset (MediaEval Database for Emotional Analysis in Music)
with real valence/arousal annotations averaged per song.

Usage:
    python tools/train_mood_classifier.py [--audio-dir PATH] [--annotations-dir PATH]
                                          [--output PATH] [--epochs N]
                                          [--cache-features PATH]
"""

import argparse
import json
import math
import os
import sys
import time
import warnings

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim

# Suppress librosa warnings about PySoundFile
warnings.filterwarnings("ignore", category=FutureWarning)
warnings.filterwarnings("ignore", category=UserWarning, module="librosa")


# ---------------------------------------------------------------------------
# Constants -- must match Swift pipeline exactly
# ---------------------------------------------------------------------------

NUM_FEATURES = 10
NUM_OUTPUTS = 2  # valence, arousal

SAMPLE_RATE = 48000
FFT_SIZE = 1024
BIN_COUNT = FFT_SIZE // 2  # 512
BIN_RESOLUTION = SAMPLE_RATE / FFT_SIZE  # 46.875 Hz
NYQUIST = SAMPLE_RATE / 2  # 24000 Hz
MIN_CHROMA_FREQ = 500.0  # match ChromaExtractor.swift minFrequency

# 6-band boundaries (Hz) -- from BandEnergyProcessor.swift bands6
BANDS_6 = [
    ("subBass", 20, 80),
    ("lowBass", 80, 250),
    ("lowMid", 250, 1000),
    ("midHigh", 1000, 4000),
    ("highMid", 4000, 8000),
    ("high", 8000, 24000),
]

# Krumhansl-Schmuckler key profiles -- from ChromaExtractor.swift
MAJOR_PROFILE = np.array(
    [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88],
    dtype=np.float64,
)
MINOR_PROFILE = np.array(
    [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17],
    dtype=np.float64,
)

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

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)

DEFAULT_AUDIO_DIR = os.path.join(SCRIPT_DIR, "data", "DEAM", "DEAM_audio", "MEMD_audio")
DEFAULT_ANNOTATIONS_DIR = os.path.join(
    SCRIPT_DIR, "data", "DEAM", "annotations", "annotations",
    "annotations averaged per song", "song_level",
)
DEFAULT_OUTPUT_DIR = os.path.join(PROJECT_ROOT, "PhospheneEngine", "Sources", "ML", "Models")
DEFAULT_CACHE_PATH = os.path.join(SCRIPT_DIR, "data", "deam_features_cache.npz")


# ---------------------------------------------------------------------------
# Band bin ranges -- matching Swift: floor(low / binRes) to ceil(high / binRes)
# ---------------------------------------------------------------------------

def compute_band_ranges():
    """Compute 6-band bin ranges matching BandEnergyProcessor.swift."""
    ranges = []
    for _name, low, high in BANDS_6:
        start = max(0, int(math.floor(low / BIN_RESOLUTION)))
        end = min(BIN_COUNT, int(math.ceil(high / BIN_RESOLUTION)))
        ranges.append((start, end))
    return ranges


BAND_RANGES = compute_band_ranges()


# ---------------------------------------------------------------------------
# Chroma bin-to-pitch-class mapping -- matching ChromaExtractor.swift
# ---------------------------------------------------------------------------

def build_bin_pitch_classes():
    """Precompute pitch class for each FFT bin, matching ChromaExtractor.swift."""
    pitch_classes = []
    for i in range(BIN_COUNT):
        freq = i * BIN_RESOLUTION
        if freq < MIN_CHROMA_FREQ:
            pitch_classes.append(-1)
            continue
        # MIDI note: 69 = A4 = 440 Hz
        midi_note = 69.0 + 12.0 * math.log2(freq / 440.0)
        pc = int(round(midi_note)) % 12
        if pc < 0:
            pc += 12
        pitch_classes.append(pc)
    return pitch_classes


BIN_PITCH_CLASSES = build_bin_pitch_classes()


# ---------------------------------------------------------------------------
# Key profile rotation and correlation
# ---------------------------------------------------------------------------

def rotate_profile(profile, shift):
    """Rotate a 12-element profile by `shift` positions (matching Swift rotateProfile)."""
    return np.roll(profile, -shift)


def build_all_key_profiles():
    """Build 24 key profiles: [0..11] = major rotations, [12..23] = minor rotations."""
    profiles = []
    for root in range(12):
        profiles.append(rotate_profile(MAJOR_PROFILE, root))
    for root in range(12):
        profiles.append(rotate_profile(MINOR_PROFILE, root))
    return profiles


KEY_PROFILES = build_all_key_profiles()


def pearson_correlation(x, y):
    """Pearson correlation matching ChromaExtractor.swift implementation."""
    n = len(x)
    mean_x = np.mean(x)
    mean_y = np.mean(y)
    dx = x - mean_x
    dy = y - mean_y
    cov = np.sum(dx * dy)
    denom = math.sqrt(np.sum(dx * dx) * np.sum(dy * dy))
    if denom < 1e-10:
        return 0.0
    return cov / denom


def compute_key_correlations(chroma):
    """Compute best major and minor key correlations from a 12-bin chroma vector.

    Matches ChromaExtractor.estimateKey: Pearson correlation with all 24 profiles,
    take best major and best minor, clamp to 0-1.
    """
    best_major = -2.0
    best_minor = -2.0

    for i in range(24):
        corr = pearson_correlation(chroma, KEY_PROFILES[i])
        if i < 12:
            best_major = max(best_major, corr)
        else:
            best_minor = max(best_minor, corr)

    # Clamp to 0-1 matching Swift
    best_major = min(max(best_major, 0.0), 1.0)
    best_minor = min(max(best_minor, 0.0), 1.0)
    return best_major, best_minor


# ---------------------------------------------------------------------------
# Feature extraction for a single track
# ---------------------------------------------------------------------------

def extract_features_from_audio(audio_path):
    """Extract 10 features from an audio file, matching Phosphene's MIRPipeline.

    Returns a 10-element numpy array (track-level means), or None on failure.
    """
    import librosa

    try:
        # Load audio: mono, 48kHz to match Core Audio tap
        y, sr = librosa.load(audio_path, sr=SAMPLE_RATE, mono=True)
    except Exception as exc:
        print(f"  WARNING: Failed to load {audio_path}: {exc}", file=sys.stderr)
        return None

    if len(y) < FFT_SIZE:
        print(f"  WARNING: Audio too short ({len(y)} samples): {audio_path}", file=sys.stderr)
        return None

    # Compute STFT: 1024-point, hop=512 (default for 1024 n_fft)
    # Use hop_length=512 to match typical frame rate
    stft = np.abs(librosa.stft(y, n_fft=FFT_SIZE, hop_length=FFT_SIZE // 2))
    # stft shape: (513, num_frames) -- we use bins 0..511 (BIN_COUNT)
    # Apply same normalization as Swift FFTProcessor: magnitudes *= 2.0 / fftSize
    magnitudes = stft[:BIN_COUNT, :] * (2.0 / FFT_SIZE)  # (512, num_frames)
    num_frames = magnitudes.shape[1]

    if num_frames < 2:
        return None

    # Per-frame feature accumulators
    band_energies = np.zeros((num_frames, 6), dtype=np.float64)
    centroids = np.zeros(num_frames, dtype=np.float64)
    fluxes = np.zeros(num_frames, dtype=np.float64)
    chromas = np.zeros((num_frames, 12), dtype=np.float64)

    prev_mags = None

    for frame_idx in range(num_frames):
        mags = magnitudes[:, frame_idx].astype(np.float64)

        # --- 6-band RMS energy ---
        for band_idx, (start, end) in enumerate(BAND_RANGES):
            if end > start:
                band_mags = mags[start:end]
                band_energies[frame_idx, band_idx] = np.sqrt(np.mean(band_mags ** 2))

        # --- Spectral centroid: sum(freq_i * mag_i) / sum(mag_i), normalized by Nyquist ---
        freqs = np.arange(BIN_COUNT) * BIN_RESOLUTION
        mag_sum = np.sum(mags)
        if mag_sum > 1e-10:
            centroid = np.sum(freqs * mags) / mag_sum
            centroids[frame_idx] = centroid / NYQUIST  # normalize to 0-1
        else:
            centroids[frame_idx] = 0.0

        # --- Spectral flux: half-wave rectified frame-to-frame magnitude difference ---
        if prev_mags is not None:
            diff = mags - prev_mags
            fluxes[frame_idx] = np.sum(np.maximum(diff, 0.0))
        else:
            fluxes[frame_idx] = 0.0
        prev_mags = mags.copy()

        # --- 12-bin chroma: map bins >= 500 Hz to pitch class ---
        chroma = np.zeros(12, dtype=np.float64)
        for i in range(BIN_COUNT):
            pc = BIN_PITCH_CLASSES[i]
            if pc < 0:
                continue
            chroma[pc] += mags[i]

        # Normalize chroma: divide by max so loudest pitch class = 1.0
        max_val = np.max(chroma)
        if max_val > 1e-10:
            chroma = chroma / max_val

        chromas[frame_idx] = chroma

    # --- Per-track means ---
    mean_band_energy = np.mean(band_energies, axis=0)  # shape (6,)
    mean_centroid = np.mean(centroids)
    mean_flux = np.mean(fluxes)
    mean_chroma = np.mean(chromas, axis=0)  # shape (12,)

    # --- AGC-like normalization for 6-band energy ---
    # Match Swift AGC: divide each band by total energy sum, scale by 0.5
    total_energy = np.sum(mean_band_energy)
    if total_energy > 1e-10:
        mean_band_energy = mean_band_energy / total_energy * 0.5
    else:
        mean_band_energy = np.zeros(6, dtype=np.float64)

    # --- Major/minor key correlations from mean chroma ---
    major_corr, minor_corr = compute_key_correlations(mean_chroma)

    # Assemble 10-feature vector
    features = np.zeros(NUM_FEATURES, dtype=np.float32)
    features[IDX_SUB_BASS:IDX_HIGH + 1] = mean_band_energy.astype(np.float32)
    features[IDX_CENTROID] = np.float32(mean_centroid)
    features[IDX_FLUX] = np.float32(mean_flux)
    features[IDX_MAJOR_CORR] = np.float32(major_corr)
    features[IDX_MINOR_CORR] = np.float32(minor_corr)

    return features


# ---------------------------------------------------------------------------
# Annotation loading
# ---------------------------------------------------------------------------

def load_annotations(annotations_dir):
    """Load DEAM annotations from both CSV files.

    Returns dict: song_id (int) -> (valence_mean, arousal_mean) in 1-9 scale.
    """
    annotations = {}

    file1 = os.path.join(annotations_dir, "static_annotations_averaged_songs_1_2000.csv")
    file2 = os.path.join(annotations_dir, "static_annotations_averaged_songs_2000_2058.csv")

    for filepath in [file1, file2]:
        if not os.path.exists(filepath):
            print(f"  WARNING: Annotation file not found: {filepath}", file=sys.stderr)
            continue

        with open(filepath, "r") as f:
            header = f.readline()  # skip header
            for line in f:
                parts = line.strip().split(",")
                if len(parts) < 5:
                    continue
                try:
                    song_id = int(parts[0].strip())
                    valence_mean = float(parts[1].strip())
                    arousal_mean = float(parts[3].strip())
                    annotations[song_id] = (valence_mean, arousal_mean)
                except (ValueError, IndexError):
                    continue

    return annotations


def normalize_deam_va(valence_raw, arousal_raw):
    """Normalize DEAM 1-9 scale to -1 to +1."""
    valence = (valence_raw - 5.0) / 4.0
    arousal = (arousal_raw - 5.0) / 4.0
    return np.clip(valence, -1.0, 1.0), np.clip(arousal, -1.0, 1.0)


# ---------------------------------------------------------------------------
# Dataset construction
# ---------------------------------------------------------------------------

def find_audio_file(audio_dir, song_id):
    """Find the audio file for a given song_id, checking common naming patterns."""
    candidates = [
        os.path.join(audio_dir, f"{song_id}.mp3"),
        os.path.join(audio_dir, f"{song_id}.wav"),
    ]
    # Also check one level up and MEMD_audio subdirectory
    parent = os.path.dirname(audio_dir)
    candidates.append(os.path.join(parent, f"{song_id}.mp3"))
    memd_sub = os.path.join(audio_dir, "MEMD_audio")
    if os.path.isdir(memd_sub):
        candidates.append(os.path.join(memd_sub, f"{song_id}.mp3"))

    for path in candidates:
        if os.path.exists(path):
            return path
    return None


def build_dataset(audio_dir, annotations_dir, cache_path=None):
    """Extract features for all annotated tracks.

    Returns: features (N, 10), targets (N, 2), song_ids (N,)
    """
    # Try loading from cache
    if cache_path and os.path.exists(cache_path):
        print(f"Loading cached features from {cache_path}")
        data = np.load(cache_path)
        return data["features"], data["targets"], data["song_ids"]

    # Load annotations
    annotations = load_annotations(annotations_dir)
    print(f"Loaded {len(annotations)} annotations")

    if len(annotations) == 0:
        print("ERROR: No annotations found. Check --annotations-dir path.", file=sys.stderr)
        sys.exit(1)

    # Check audio directory
    if not os.path.isdir(audio_dir):
        # Try common alternative paths
        alt_paths = [
            os.path.join(os.path.dirname(audio_dir), "MEMD_audio"),
            os.path.join(os.path.dirname(os.path.dirname(audio_dir)), "MEMD_audio"),
        ]
        found = False
        for alt in alt_paths:
            if os.path.isdir(alt):
                print(f"Audio dir not found at {audio_dir}, using {alt}")
                audio_dir = alt
                found = True
                break
        if not found:
            print(f"ERROR: Audio directory not found: {audio_dir}", file=sys.stderr)
            print("  You may need to extract DEAM_audio.zip first.", file=sys.stderr)
            sys.exit(1)

    features_list = []
    targets_list = []
    song_ids_list = []
    skipped = 0
    total = len(annotations)

    t0 = time.time()
    for idx, (song_id, (val_raw, aro_raw)) in enumerate(sorted(annotations.items())):
        if (idx + 1) % 50 == 0 or idx == 0:
            elapsed = time.time() - t0
            rate = (idx + 1) / max(elapsed, 0.01)
            remaining = (total - idx - 1) / max(rate, 0.01)
            print(f"  [{idx + 1}/{total}] Extracting features... "
                  f"({elapsed:.0f}s elapsed, ~{remaining:.0f}s remaining)")

        audio_path = find_audio_file(audio_dir, song_id)
        if audio_path is None:
            skipped += 1
            continue

        feats = extract_features_from_audio(audio_path)
        if feats is None:
            skipped += 1
            continue

        valence, arousal = normalize_deam_va(val_raw, aro_raw)
        features_list.append(feats)
        targets_list.append(np.array([valence, arousal], dtype=np.float32))
        song_ids_list.append(song_id)

    elapsed = time.time() - t0
    print(f"  Feature extraction complete: {len(features_list)} tracks in {elapsed:.1f}s "
          f"({skipped} skipped)")

    if len(features_list) == 0:
        print("ERROR: No features extracted. Check audio files.", file=sys.stderr)
        sys.exit(1)

    features = np.array(features_list, dtype=np.float32)
    targets = np.array(targets_list, dtype=np.float32)
    song_ids = np.array(song_ids_list, dtype=np.int32)

    # Save cache
    if cache_path:
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        np.savez(cache_path, features=features, targets=targets, song_ids=song_ids)
        print(f"  Cached features to {cache_path}")

    return features, targets, song_ids


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------

class MoodClassifier(nn.Module):
    """MLP: 10 -> 64 (ReLU) -> 32 (ReLU) -> 16 (ReLU) -> 2 (tanh)."""

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


# ---------------------------------------------------------------------------
# Feature normalization
# ---------------------------------------------------------------------------

def compute_scaler(features):
    """Compute per-feature mean and std for z-score normalization."""
    means = np.mean(features, axis=0).astype(np.float32)
    stds = np.std(features, axis=0).astype(np.float32)
    # Prevent division by zero
    stds = np.where(stds < 1e-8, 1.0, stds)
    return means, stds


def apply_scaler(features, means, stds):
    """Apply z-score normalization."""
    return ((features - means) / stds).astype(np.float32)


def save_scaler(means, stds, path):
    """Save scaler parameters to JSON."""
    scaler = {
        "feature_names": [
            "subBass", "lowBass", "lowMid", "midHigh", "highMid", "high",
            "centroid", "flux", "majorCorr", "minorCorr",
        ],
        "means": means.tolist(),
        "stds": stds.tolist(),
    }
    with open(path, "w") as f:
        json.dump(scaler, f, indent=2)
    print(f"  Saved scaler parameters to {path}")


# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------

def train_model(features, targets, epochs=500, lr=1e-3, batch_size=32, seed=42):
    """Train the MLP on DEAM features/targets.

    Uses 80/20 train/val split.
    """
    torch.manual_seed(seed)
    np.random.seed(seed)

    n = len(features)
    indices = np.random.permutation(n)
    split = int(n * 0.8)

    train_idx = indices[:split]
    val_idx = indices[split:]

    train_x = torch.from_numpy(features[train_idx])
    train_y = torch.from_numpy(targets[train_idx])
    val_x = torch.from_numpy(features[val_idx])
    val_y = torch.from_numpy(targets[val_idx])

    model = MoodClassifier()
    optimizer = optim.Adam(model.parameters(), lr=lr)
    loss_fn = nn.MSELoss()

    num_params = sum(p.numel() for p in model.parameters())
    print(f"  Model: {num_params} parameters")
    print(f"  Train: {len(train_idx)} samples, Val: {len(val_idx)} samples")
    print(f"  Batch size: {batch_size}, Epochs: {epochs}, LR: {lr}")

    t0 = time.time()
    best_val_loss = float("inf")
    best_state = None

    for epoch in range(epochs):
        model.train()

        # Mini-batch training
        perm = torch.randperm(len(train_idx))
        epoch_loss = 0.0
        num_batches = 0

        for start in range(0, len(train_idx), batch_size):
            end = min(start + batch_size, len(train_idx))
            batch_idx = perm[start:end]
            batch_x = train_x[batch_idx]
            batch_y = train_y[batch_idx]

            pred = model(batch_x)
            loss = loss_fn(pred, batch_y)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()

            epoch_loss += loss.item()
            num_batches += 1

        avg_train_loss = epoch_loss / max(num_batches, 1)

        # Validation every 50 epochs or at start/end
        if (epoch + 1) % 50 == 0 or epoch == 0 or epoch == epochs - 1:
            model.eval()
            with torch.no_grad():
                val_pred = model(val_x)
                val_loss = loss_fn(val_pred, val_y).item()

                # Per-dimension RMSE
                val_diff = val_pred - val_y
                rmse_valence = torch.sqrt(torch.mean(val_diff[:, 0] ** 2)).item()
                rmse_arousal = torch.sqrt(torch.mean(val_diff[:, 1] ** 2)).item()

            if val_loss < best_val_loss:
                best_val_loss = val_loss
                best_state = {k: v.clone() for k, v in model.state_dict().items()}

            print(f"    Epoch {epoch + 1:4d}: train_loss={avg_train_loss:.6f}  "
                  f"val_loss={val_loss:.6f}  "
                  f"val_rmse_v={rmse_valence:.4f}  val_rmse_a={rmse_arousal:.4f}")

    elapsed = time.time() - t0
    print(f"  Training complete in {elapsed:.1f}s, best val_loss={best_val_loss:.6f}")

    # Restore best model
    if best_state is not None:
        model.load_state_dict(best_state)
    model.eval()

    return model, val_x, val_y, val_idx


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------

def evaluate_model(model, val_x, val_y, val_idx, song_ids):
    """Compute detailed evaluation metrics."""
    model.eval()
    with torch.no_grad():
        val_pred = model(val_x).numpy()
    val_true = val_y.numpy()

    # Per-dimension RMSE
    rmse_valence = np.sqrt(np.mean((val_pred[:, 0] - val_true[:, 0]) ** 2))
    rmse_arousal = np.sqrt(np.mean((val_pred[:, 1] - val_true[:, 1]) ** 2))

    print(f"\n  Validation RMSE:")
    print(f"    Valence: {rmse_valence:.4f}")
    print(f"    Arousal: {rmse_arousal:.4f}")
    print(f"    Combined: {np.sqrt((rmse_valence**2 + rmse_arousal**2) / 2):.4f}")

    # Quadrant accuracy
    def get_quadrant(v, a):
        if v >= 0 and a >= 0:
            return "happy"     # Q1: +V +A
        elif v < 0 and a >= 0:
            return "tense"     # Q2: -V +A
        elif v < 0 and a < 0:
            return "sad"       # Q3: -V -A
        else:
            return "calm"      # Q4: +V -A

    true_quads = [get_quadrant(v, a) for v, a in val_true]
    pred_quads = [get_quadrant(v, a) for v, a in val_pred]

    correct = sum(1 for t, p in zip(true_quads, pred_quads) if t == p)
    total = len(true_quads)
    print(f"\n  Quadrant accuracy: {correct}/{total} ({100 * correct / total:.1f}%)")

    # Per-quadrant breakdown
    quad_names = ["happy", "tense", "sad", "calm"]
    for q in quad_names:
        q_mask = [i for i, t in enumerate(true_quads) if t == q]
        if len(q_mask) == 0:
            print(f"    {q:6s}: no samples")
            continue
        q_correct = sum(1 for i in q_mask if pred_quads[i] == q)
        print(f"    {q:6s}: {q_correct}/{len(q_mask)} ({100 * q_correct / len(q_mask):.1f}%)")

    # 5 worst predictions
    errors = np.sqrt(np.sum((val_pred - val_true) ** 2, axis=1))
    worst_idx = np.argsort(errors)[-5:][::-1]
    print(f"\n  5 worst predictions:")
    print(f"    {'song_id':>8s}  {'true_V':>7s} {'true_A':>7s}  "
          f"{'pred_V':>7s} {'pred_A':>7s}  {'error':>6s}")
    for i in worst_idx:
        sid = song_ids[val_idx[i]]
        tv, ta = val_true[i]
        pv, pa = val_pred[i]
        err = errors[i]
        print(f"    {sid:>8d}  {tv:>7.3f} {ta:>7.3f}  {pv:>7.3f} {pa:>7.3f}  {err:>6.3f}")

    return rmse_valence, rmse_arousal


# ---------------------------------------------------------------------------
# CoreML conversion
# ---------------------------------------------------------------------------

def convert_to_coreml(model, output_dir, scaler_means, scaler_stds):
    """Convert trained PyTorch model to CoreML .mlpackage."""
    output_path = os.path.join(output_dir, "MoodClassifier.mlpackage")

    # Trace the model
    example_input = torch.randn(1, NUM_FEATURES)
    traced = torch.jit.trace(model, example_input)

    # Convert to CoreML
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="features", shape=(1, NUM_FEATURES))],
        outputs=[ct.TensorType(name="mood")],
        compute_units=ct.ComputeUnit.CPU_AND_NE,
        minimum_deployment_target=ct.target.macOS14,
    )

    # Add metadata
    mlmodel.author = "Phosphene (DEAM-trained)"
    mlmodel.short_description = (
        "Valence/arousal mood classifier trained on DEAM dataset. "
        "Input: 10 z-score-normalized audio features (6-band energy, spectral centroid, "
        "flux, major/minor key correlations). "
        "Output: [valence, arousal] each in [-1, 1]. "
        "Apply z-score normalization using mood_scaler.json before inference."
    )
    mlmodel.input_description["features"] = (
        "10 z-score-normalized features: [subBass, lowBass, lowMid, midHigh, highMid, high, "
        "centroid, flux, majorKeyCorrelation, minorKeyCorrelation]. "
        "Normalize with scaler params before passing."
    )
    mlmodel.output_description["mood"] = (
        "2 values: [valence (-1=sad to +1=happy), arousal (-1=calm to +1=energetic)]"
    )

    # Save
    os.makedirs(output_dir, exist_ok=True)
    mlmodel.save(output_path)

    # Verify round-trip
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

    print(f"  Saved: {output_path}")
    print(f"  Size: {size_mb:.2f} MB")
    print(f"  CoreML round-trip verified.")
    return output_path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Train mood classifier on DEAM dataset and export to CoreML."
    )
    parser.add_argument(
        "--audio-dir", type=str, default=DEFAULT_AUDIO_DIR,
        help=f"Path to DEAM audio directory (default: {DEFAULT_AUDIO_DIR})"
    )
    parser.add_argument(
        "--annotations-dir", type=str, default=DEFAULT_ANNOTATIONS_DIR,
        help=f"Path to DEAM annotations directory (default: {DEFAULT_ANNOTATIONS_DIR})"
    )
    parser.add_argument(
        "--output", type=str, default=DEFAULT_OUTPUT_DIR,
        help=f"Output directory for .mlpackage (default: {DEFAULT_OUTPUT_DIR})"
    )
    parser.add_argument(
        "--epochs", type=int, default=500,
        help="Training epochs (default: 500)"
    )
    parser.add_argument(
        "--cache-features", type=str, default=DEFAULT_CACHE_PATH,
        help=f"Path to cache extracted features as .npz (default: {DEFAULT_CACHE_PATH})"
    )
    parser.add_argument(
        "--no-cache", action="store_true",
        help="Disable feature caching (re-extract every run)"
    )
    parser.add_argument(
        "--seed", type=int, default=42,
        help="Random seed (default: 42)"
    )
    args = parser.parse_args()

    cache_path = None if args.no_cache else args.cache_features

    print("=" * 64)
    print("Phosphene Mood Classifier -- DEAM Training Pipeline")
    print("=" * 64)
    print(f"Architecture: {NUM_FEATURES} -> 64 (ReLU) -> 32 (ReLU) -> 16 (ReLU) -> {NUM_OUTPUTS} (tanh)")
    print(f"Audio dir:       {args.audio_dir}")
    print(f"Annotations dir: {args.annotations_dir}")
    print(f"Output dir:      {args.output}")
    print(f"Epochs: {args.epochs}, Seed: {args.seed}")
    print(f"Feature cache:   {cache_path or 'disabled'}")
    print()

    # --- Step 1: Build dataset ---
    print("[1/4] Building dataset from DEAM...")
    features, targets, song_ids = build_dataset(
        args.audio_dir, args.annotations_dir, cache_path
    )
    print(f"  Total tracks processed: {len(features)}")
    print(f"  Feature shape: {features.shape}")
    print(f"  Target range: valence [{targets[:, 0].min():.3f}, {targets[:, 0].max():.3f}], "
          f"arousal [{targets[:, 1].min():.3f}, {targets[:, 1].max():.3f}]")
    print()

    # --- Step 2: Normalize features ---
    print("[2/4] Normalizing features (z-score)...")
    scaler_means, scaler_stds = compute_scaler(features)

    # Print feature stats
    feature_names = [
        "subBass", "lowBass", "lowMid", "midHigh", "highMid", "high",
        "centroid", "flux", "majorCorr", "minorCorr",
    ]
    print(f"  {'Feature':>12s}  {'mean':>10s}  {'std':>10s}")
    for i, name in enumerate(feature_names):
        print(f"  {name:>12s}  {scaler_means[i]:>10.6f}  {scaler_stds[i]:>10.6f}")

    # Save scaler
    scaler_path = os.path.join(SCRIPT_DIR, "data", "mood_scaler.json")
    os.makedirs(os.path.dirname(scaler_path), exist_ok=True)
    save_scaler(scaler_means, scaler_stds, scaler_path)

    features_norm = apply_scaler(features, scaler_means, scaler_stds)
    print()

    # --- Step 3: Train ---
    print(f"[3/4] Training for {args.epochs} epochs...")
    model, val_x, val_y, val_idx = train_model(
        features_norm, targets,
        epochs=args.epochs,
        batch_size=32,
        lr=1e-3,
        seed=args.seed,
    )
    print()

    # --- Step 4: Evaluate ---
    print("[4/5] Evaluating model...")
    rmse_v, rmse_a = evaluate_model(model, val_x, val_y, val_idx, song_ids)
    print()

    # --- Step 5: Export ---
    print("[5/5] Converting to CoreML...")
    output_path = convert_to_coreml(model, args.output, scaler_means, scaler_stds)

    print()
    print("=" * 64)
    print(f"Done. Model saved to: {output_path}")
    print(f"Scaler saved to: {scaler_path}")
    print(f"NOTE: Swift MoodClassifier must apply z-score normalization using")
    print(f"  the means and stds from {scaler_path} before inference.")
    print("=" * 64)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Convert Open-Unmix (UMX-HQ) stem separation model to CoreML .mlpackage for ANE.

Architecture split:
  - STFT / iSTFT: handled in Swift via Accelerate/vDSP (not in CoreML model)
  - Neural network (mask estimation): converted to CoreML .mlpackage

The CoreML model takes STFT magnitude spectrograms [1, 2, 2049, T] and outputs
4 filtered spectrograms [4, 2, 2049, T] (one per stem: vocals, drums, bass, other).

The full separation pipeline in Swift will be:
  1. STFT(audio) → magnitude spectrogram + phase
  2. CoreML predict(magnitude) → 4 filtered spectrograms
  3. iSTFT(filtered_spec, original_phase) → 4 stem waveforms

Usage:
    python tools/convert_stem_model.py [--output PATH] [--duration SECONDS]

Open-Unmix stem ordering (model output): vocals=0, drums=1, bass=2, other=3
This matches Phosphene's StemData ordering directly.
"""

import argparse
import math
import os
import time

import coremltools as ct
import numpy as np
import torch
import torch.nn.functional as F


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SAMPLE_RATE = 44100
N_FFT = 4096
HOP_LENGTH = 1024
NB_BINS = N_FFT // 2 + 1  # 2049
NB_CHANNELS = 2

# Open-Unmix internal constants (from umxhq weights)
UMX_NB_BINS = 1487       # bandwidth-limited input bins
UMX_NB_OUTPUT_BINS = 2049 # full output bins
UMX_HIDDEN_SIZE = 512

# Stem ordering: matches Phosphene's StemData (vocals, drums, bass, other)
STEM_NAMES = ["vocals", "drums", "bass", "other"]

DEFAULT_DURATION_S = 10
DEFAULT_OUTPUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "PhospheneEngine", "Sources", "ML", "Models",
)


# ---------------------------------------------------------------------------
# Model loading
# ---------------------------------------------------------------------------

def load_openunmix():
    """Load pre-trained Open-Unmix HQ separator."""
    print("[1/5] Loading Open-Unmix HQ model...")
    import openunmix
    separator = openunmix.umxhq(device="cpu")
    separator.eval()
    print(f"       Model: umxhq (Open-Unmix High Quality)")
    print(f"       STFT: n_fft={N_FFT}, hop={HOP_LENGTH}")
    print(f"       Stems: {STEM_NAMES}")
    return separator


# ---------------------------------------------------------------------------
# CoreML-compatible wrapper
# ---------------------------------------------------------------------------

class StemSeparatorFixed(torch.nn.Module):
    """Combined 4-stem mask estimator with all shapes hardcoded for CoreML tracing.

    Takes STFT magnitude spectrogram [1, 2, 2049, nb_frames] and outputs
    4 filtered spectrograms stacked as [4, 2, 2049, nb_frames].

    All dynamic shape calculations are replaced with compile-time constants
    to avoid the coremltools `int` op conversion bug.
    """

    def __init__(self, separator, nb_frames):
        super().__init__()
        self.nb_frames = nb_frames

        # Copy weights from all 4 stem models
        for stem_name in STEM_NAMES:
            src = separator.target_models[stem_name]
            prefix = stem_name
            # Register submodules
            setattr(self, f"{prefix}_fc1", src.fc1)
            setattr(self, f"{prefix}_bn1", src.bn1)
            setattr(self, f"{prefix}_lstm", src.lstm)
            setattr(self, f"{prefix}_fc2", src.fc2)
            setattr(self, f"{prefix}_bn2", src.bn2)
            setattr(self, f"{prefix}_fc3", src.fc3)
            setattr(self, f"{prefix}_bn3", src.bn3)
            # Register buffers for mean/scale (non-trainable parameters)
            self.register_buffer(f"{prefix}_input_mean", src.input_mean.data.clone())
            self.register_buffer(f"{prefix}_input_scale", src.input_scale.data.clone())
            self.register_buffer(f"{prefix}_output_mean", src.output_mean.data.clone())
            self.register_buffer(f"{prefix}_output_scale", src.output_scale.data.clone())

    def _run_stem(self, x, fc1, bn1, lstm, fc2, bn2, fc3, bn3,
                  input_mean, input_scale, output_mean, output_scale):
        """Run one stem's mask estimation network.

        Args:
            x: [1, 2, 2049, nb_frames] STFT magnitude spectrogram.

        Returns:
            [1, 2, 2049, nb_frames] filtered spectrogram for this stem.
        """
        nf = self.nb_frames

        # Permute to [frames, batch, channels, freq_bins]
        x = x.permute(3, 0, 1, 2)
        mix = x.detach().clone()

        # Bandwidth limit and normalize
        x = x[..., :UMX_NB_BINS]
        x = x + input_mean
        x = x * input_scale

        # FC1: [frames, channels * nb_bins] → [frames, hidden]
        x = x.reshape(nf, NB_CHANNELS * UMX_NB_BINS)
        x = fc1(x)
        x = bn1(x)
        x = x.reshape(nf, 1, UMX_HIDDEN_SIZE)
        x = torch.tanh(x)

        # LSTM
        lstm_out, _ = lstm(x)
        x = torch.cat([x, lstm_out], -1)

        # FC2 + FC3
        x = x.reshape(nf, UMX_HIDDEN_SIZE * 2)
        x = fc2(x)
        x = bn2(x)
        x = F.relu(x)
        x = fc3(x)
        x = bn3(x)

        # Reshape and apply output scaling
        x = x.reshape(nf, 1, NB_CHANNELS, UMX_NB_OUTPUT_BINS)
        x = x * output_scale + output_mean

        # Apply mask (ReLU ensures non-negative) and multiply with input
        x = F.relu(x) * mix

        # Back to [batch, channels, freq_bins, frames]
        return x.permute(1, 2, 3, 0)

    def forward(self, spectrogram):
        """Run all 4 stem models on the input spectrogram.

        Args:
            spectrogram: [1, 2, 2049, nb_frames] STFT magnitude.

        Returns:
            [4, 2, 2049, nb_frames] — stacked filtered spectrograms
            in order: vocals, drums, bass, other.
        """
        stems = []
        for name in STEM_NAMES:
            stem_out = self._run_stem(
                spectrogram,
                getattr(self, f"{name}_fc1"),
                getattr(self, f"{name}_bn1"),
                getattr(self, f"{name}_lstm"),
                getattr(self, f"{name}_fc2"),
                getattr(self, f"{name}_bn2"),
                getattr(self, f"{name}_fc3"),
                getattr(self, f"{name}_bn3"),
                getattr(self, f"{name}_input_mean"),
                getattr(self, f"{name}_input_scale"),
                getattr(self, f"{name}_output_mean"),
                getattr(self, f"{name}_output_scale"),
            )
            stems.append(stem_out)

        # Stack: [4, 1, 2, 2049, nb_frames] → squeeze batch → [4, 2, 2049, nb_frames]
        return torch.cat(stems, dim=0)


# ---------------------------------------------------------------------------
# CoreML conversion
# ---------------------------------------------------------------------------

def compute_nb_frames(duration_s, sample_rate=SAMPLE_RATE):
    """Compute number of STFT frames for a given duration.

    Matches torch.stft with center=True (default): the input is padded by
    n_fft//2 on each side, giving padded_length = num_samples + n_fft.
    Frames = (padded_length - n_fft) // hop_length + 1 = num_samples // hop_length + 1.
    """
    num_samples = sample_rate * duration_s
    return num_samples // HOP_LENGTH + 1


def convert_to_coreml(separator, duration_s, output_path, max_abs_error):
    """Build combined model, trace, and convert to CoreML.

    Returns:
        Tuple of (coreml_model, pytorch_model, separator, example_spectrogram).
    """
    nb_frames = compute_nb_frames(duration_s)
    print(f"[2/5] Building combined 4-stem model (nb_frames={nb_frames})...")

    combined = StemSeparatorFixed(separator, nb_frames)
    combined.eval()

    # Verify against original models
    example_spec = torch.randn(1, NB_CHANNELS, NB_BINS, nb_frames)
    with torch.no_grad():
        combined_out = combined(example_spec)
    assert combined_out.shape == (4, NB_CHANNELS, NB_BINS, nb_frames), (
        f"Unexpected shape: {combined_out.shape}"
    )
    print(f"       Combined output shape: {list(combined_out.shape)} ✓")

    # Verify each stem matches the original
    for i, name in enumerate(STEM_NAMES):
        orig_model = separator.target_models[name]
        orig_model.eval()
        with torch.no_grad():
            orig_out = orig_model(example_spec)
        diff = (combined_out[i:i+1] - orig_out).abs().max().item()
        assert diff < 1e-5, f"Stem '{name}' mismatch: max diff = {diff}"
    print("       All stems match original models ✓")

    # Trace
    print(f"[3/5] Tracing with input [1, 2, {NB_BINS}, {nb_frames}]...")
    with torch.no_grad():
        traced = torch.jit.trace(combined, example_spec)
        trace_out = traced(example_spec)

    trace_diff = (trace_out - combined_out).abs().max().item()
    assert trace_diff < 1e-5, f"Trace diverged: max diff = {trace_diff}"
    print("       Trace output matches ✓")

    # Convert to CoreML
    print("[4/5] Converting to CoreML .mlpackage...")
    coreml_model = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                name="spectrogram",
                shape=(1, NB_CHANNELS, NB_BINS, nb_frames),
            )
        ],
        outputs=[
            ct.TensorType(name="stems"),
        ],
        compute_units=ct.ComputeUnit.CPU_AND_NE,
        minimum_deployment_target=ct.target.macOS14,
    )

    # Metadata
    coreml_model.author = "Phosphene (converted from Open-Unmix HQ)"
    coreml_model.short_description = (
        f"Open-Unmix HQ 4-stem mask estimator. "
        f"Input: STFT magnitude [1, 2, {NB_BINS}, {nb_frames}]. "
        f"Output: [4, 2, {NB_BINS}, {nb_frames}] filtered spectrograms "
        f"(vocals, drums, bass, other). "
        f"STFT/iSTFT handled externally."
    )
    coreml_model.version = "1.0"
    coreml_model.user_defined_metadata.update({
        "model_type": "stem_separator",
        "source_model": "open-unmix-hq (umxhq)",
        "sample_rate": str(SAMPLE_RATE),
        "n_fft": str(N_FFT),
        "hop_length": str(HOP_LENGTH),
        "nb_frames": str(nb_frames),
        "duration_seconds": str(duration_s),
        "stem_order": ",".join(STEM_NAMES),
        "requires_stft": "true",
        "note": "Input is STFT magnitude spectrogram, not raw audio. "
                "Caller must perform STFT before and iSTFT after inference.",
    })

    # Save
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    coreml_model.save(output_path)
    size_mb = sum(
        os.path.getsize(os.path.join(dp, f))
        for dp, _, filenames in os.walk(output_path)
        for f in filenames
    ) / (1024 * 1024)
    print(f"       Saved: {output_path} ({size_mb:.1f} MB)")

    return coreml_model, combined, separator, example_spec


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def validate_shapes(coreml_model, nb_frames):
    """Assert CoreML model input/output shapes."""
    print("[5/5] Validating shapes and accuracy...")

    spec = coreml_model.get_spec()
    input_desc = spec.description.input[0]
    input_shape = list(input_desc.type.multiArrayType.shape)
    expected_input = [1, NB_CHANNELS, NB_BINS, nb_frames]
    assert input_shape == expected_input, (
        f"Input shape {input_shape} != expected {expected_input}"
    )
    print(f"       Input shape:  {input_shape} ✓")


def compare_outputs(coreml_model, pytorch_model, example_spec, max_abs_error):
    """Run same input through PyTorch and CoreML, assert outputs match."""
    with torch.no_grad():
        pytorch_out = pytorch_model(example_spec).numpy()

    coreml_pred = coreml_model.predict({"spectrogram": example_spec.numpy()})
    coreml_out = coreml_pred["stems"]

    assert pytorch_out.shape == coreml_out.shape, (
        f"Shape mismatch: PyTorch {pytorch_out.shape} vs CoreML {coreml_out.shape}"
    )

    abs_diff = np.abs(pytorch_out - coreml_out)
    max_diff = float(abs_diff.max())
    mean_diff = float(abs_diff.mean())
    print(f"       Max absolute error:  {max_diff:.6f} (threshold: {max_abs_error})")
    print(f"       Mean absolute error: {mean_diff:.6f}")

    assert max_diff < max_abs_error, (
        f"Max absolute error {max_diff:.6f} exceeds threshold {max_abs_error}"
    )
    print("       PyTorch ↔ CoreML comparison: PASS ✓")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Convert Open-Unmix HQ to CoreML .mlpackage for Phosphene"
    )
    parser.add_argument(
        "--output", "-o",
        default=os.path.join(DEFAULT_OUTPUT_DIR, "StemSeparator.mlpackage"),
        help="Output .mlpackage path",
    )
    parser.add_argument(
        "--duration", "-d",
        type=int,
        default=DEFAULT_DURATION_S,
        help=f"Fixed input duration in seconds (default: {DEFAULT_DURATION_S})",
    )
    parser.add_argument(
        "--max-error",
        type=float,
        default=0.05,
        help="Max absolute error threshold for PyTorch/CoreML comparison (default: 0.05)",
    )
    args = parser.parse_args()

    nb_frames = compute_nb_frames(args.duration)

    print("=" * 60)
    print("Phosphene — Open-Unmix HQ → CoreML Conversion")
    print("=" * 60)
    print(f"Output:      {args.output}")
    print(f"Duration:    {args.duration}s @ {SAMPLE_RATE} Hz")
    print(f"STFT:        n_fft={N_FFT}, hop={HOP_LENGTH}")
    print(f"Frames:      {nb_frames}")
    print(f"Input shape: [1, {NB_CHANNELS}, {NB_BINS}, {nb_frames}]")
    print(f"Output shape: [4, {NB_CHANNELS}, {NB_BINS}, {nb_frames}]")
    print()

    t0 = time.time()

    separator = load_openunmix()
    coreml_model, pytorch_model, _, example_spec = convert_to_coreml(
        separator, args.duration, args.output, args.max_error
    )
    validate_shapes(coreml_model, nb_frames)
    compare_outputs(coreml_model, pytorch_model, example_spec, args.max_error)

    elapsed = time.time() - t0
    print()
    print(f"Done in {elapsed:.1f}s.")
    print(f"Model: {args.output}")
    print(f"Stems: {STEM_NAMES}")
    print()
    print("NOTE: This model operates on STFT magnitude spectrograms.")
    print("In Swift (Increment 2.3), perform STFT before and iSTFT after CoreML inference.")


if __name__ == "__main__":
    main()

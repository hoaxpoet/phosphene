#!/usr/bin/env python3
"""convert_panns_weights.py — IFC.2 weight converter for PANNs MobileNetV1.

Ingests the PANNs MobileNetV1 checkpoint (Kong et al., 2020) and emits
Phosphene's vendored .bin format under
PhospheneEngine/Sources/ML/Weights/panns_mobilenetv1/, mirroring the Beat This!
and Open-Unmix converters:

  * one .bin per float32 tensor (contiguous float32 little-endian, C order)
  * manifest.json with shape / dtype / bytes / sha256 per tensor

The front-end is exported as data, not reimplemented: the checkpoint's
torchlibrosa STFT conv basis (conv_real / conv_imag, the Hann-windowed DFT
matrices) and the librosa mel filterbank (logmel_extractor.melW) ship as .bin
tensors, so the Swift front-end is exact matmuls against these matrices — no
FFT-normalization or librosa-filterbank reproduction risk. BatchNorm is exported
raw (weight/bias/running_mean/running_var) and fused at load time in Swift, as
for Beat This!.

int64 ``num_batches_tracked`` BN buffers are skipped (training-only).

Usage:
    tools/.venv/bin/python tools/convert_panns_weights.py \
        --checkpoint ~/panns_data/MobileNetV1_mAP=0.389.pth

Weights: CC-BY-4.0 (Kong et al., Zenodo record 3987831). Reference code (model
definition): MIT (github.com/qiuqiangkong/audioset_tagging_cnn) — reimplemented
in MPSGraph, not vendored. Ship-time attribution is handled in IFC.4.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import OrderedDict
from pathlib import Path

import torch


def torch_key_to_filename(key: str) -> str:
    """dots → underscores, .bin suffix (Open-Unmix / Beat This! convention)."""
    return key.replace(".", "_") + ".bin"


def convert(checkpoint_path: Path, out_dir: Path) -> dict:
    ck = torch.load(str(checkpoint_path), map_location="cpu", weights_only=False)
    state_dict = ck["model"] if "model" in ck else ck
    out_dir.mkdir(parents=True, exist_ok=True)

    tensors_meta: OrderedDict[str, dict] = OrderedDict()
    total_bytes = 0
    total_params = 0

    for key, tensor in state_dict.items():
        if key.endswith("num_batches_tracked"):
            continue  # int64 training-only buffer
        if tensor.dtype != torch.float32:
            raise SystemExit(f"Unexpected dtype for {key}: {tensor.dtype}")
        arr = tensor.detach().cpu().contiguous().numpy().astype("<f4", copy=False)
        filename = torch_key_to_filename(key)
        raw = arr.tobytes(order="C")
        (out_dir / filename).write_bytes(raw)
        tensors_meta[key] = {
            "file": filename,
            "shape": list(tensor.shape),
            "dtype": "float32",
            "bytes": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest(),
        }
        total_bytes += len(raw)
        total_params += tensor.numel()

    manifest = OrderedDict([
        ("format_version", 1),
        ("model", "panns_mobilenetv1"),
        ("variant", "mAP=0.389"),
        ("description",
         "PANNs MobileNetV1 audio tagger (Kong et al., 2020), AudioSet 527-class. "
         "Used for instrument-family activity (D-177 / IFC). "
         "Source code (model def): github.com/qiuqiangkong/audioset_tagging_cnn (MIT), "
         "reimplemented in MPSGraph. Weights: CC-BY-4.0, Zenodo record 3987831 "
         "(MobileNetV1_mAP=0.389.pth). Attribution shipped per IFC.4."),
        ("source_checkpoint", checkpoint_path.name),
        ("source_zenodo", "3987831"),
        ("weights_license", "CC-BY-4.0"),
        ("dtype", "float32"),
        ("byte_order", "little-endian"),
        ("total_bytes", total_bytes),
        ("total_params", total_params),
        ("architecture", OrderedDict([
            ("model_class", "MobileNetV1"),
            ("classes_num", 527),
            ("sample_rate_hz", 32000),
            ("window_size", 1024),
            ("hop_size", 320),
            ("mel_bins", 64),
            ("f_min_hz", 50),
            ("f_max_hz", 14000),
            ("center", True),
            ("pad_mode", "reflect"),
            ("stft_power", 2),
            ("logmel", "10*log10(clamp(mel, amin=1e-10)); ref=1.0; top_db=none"),
            ("bn_eps", 1e-5),
            ("front_end_matrices", [
                "spectrogram_extractor.stft.conv_real.weight",
                "spectrogram_extractor.stft.conv_imag.weight",
                "logmel_extractor.melW",
            ]),
            ("output_activation", "sigmoid (clipwise_output)"),
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
    parser.add_argument("--checkpoint", type=Path,
                        default=Path.home() / "panns_data" / "MobileNetV1_mAP=0.389.pth")
    parser.add_argument("--out", type=Path,
                        default=Path("PhospheneEngine/Sources/ML/Weights/panns_mobilenetv1"))
    args = parser.parse_args(argv)
    if not args.checkpoint.is_file():
        parser.error(f"checkpoint not found: {args.checkpoint}")
    manifest = convert(args.checkpoint, args.out)
    print(f"wrote {len(manifest['tensors'])} tensors "
          f"({manifest['total_bytes']:,} bytes, {manifest['total_params']:,} params) to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

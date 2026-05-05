#!/usr/bin/env python3
"""dump_beatthis_activations.py — dump intermediate Beat This! activations.

Used to localise the DSP.2 S8 bug: Swift BeatThisModel.predict produces
sub-threshold output (max sigmoid ≈ 0.29) on real audio while the Python
reference produces max ≈ 1.0 on the same input.

Strategy: register forward-hooks on each major sub-module, run inference
on love_rehab.m4a, dump per-stage tensor stats (shape, min, max, mean, std)
plus the first 32 values flattened. Mirror the same dumps in Swift via a
new BeatThisModel diagnostic surface; the first stage where the stats
diverge is where the bug lives.

Usage:
    /tmp/beat_this_venv/bin/python Scripts/dump_beatthis_activations.py \\
      --audio PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a \\
      --out   docs/diagnostics/DSP.2-S8-python-activations.json
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import torch

# Allow running from project root without installing beat_this to system Python
sys.path.insert(0, str(Path(__file__).parent.parent / "vendor" / "beat_this_repo"))

from beat_this.inference import load_model
from beat_this.preprocessing import LogMelSpect


def decode_audio(path: Path, sample_rate: int = 22050) -> np.ndarray:
    """Decode any audio file to mono Float32 at sample_rate via ffmpeg."""
    proc = subprocess.run(
        ["ffmpeg", "-loglevel", "error",
         "-i", str(path), "-ac", "1", "-ar", str(sample_rate),
         "-f", "f32le", "-"],
        capture_output=True, check=True
    )
    return np.frombuffer(proc.stdout, dtype=np.float32).copy()


def tensor_summary(name: str, tensor: torch.Tensor) -> dict:
    """Stats + first 32 values for a tensor."""
    flat = tensor.detach().cpu().numpy().reshape(-1).astype(np.float64)
    return {
        "name": name,
        "shape": list(tensor.shape),
        "dtype": str(tensor.dtype),
        "min": float(flat.min()),
        "max": float(flat.max()),
        "mean": float(flat.mean()),
        "std": float(flat.std()),
        "first32": flat[:32].tolist(),
        "last32": flat[-32:].tolist(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audio", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--variant", default="small0")
    parser.add_argument(
        "--raw-dir", type=Path, default=None,
        help="If set, also dump each stage's full Float32 tensor as raw .bin"
    )
    args = parser.parse_args()

    print(f"[py-dump] decoding {args.audio.name} …")
    samples = decode_audio(args.audio)
    print(f"[py-dump] audio: {len(samples)} samples / {len(samples)/22050:.1f}s, "
          f"peak={np.max(np.abs(samples)):.3f}")

    print(f"[py-dump] computing log-mel spectrogram …")
    spect_op = LogMelSpect(sample_rate=22050)
    spect = spect_op(torch.from_numpy(samples))
    print(f"[py-dump] spect shape: {spect.shape}, peak={spect.max():.3f}")

    print(f"[py-dump] loading model variant {args.variant} …")
    model = load_model(args.variant, device="cpu")
    model.eval()

    # Capture frontend sub-module outputs via forward hooks.
    captures: list[dict] = []
    captures.append(tensor_summary("input.spect", spect.unsqueeze(0)))

    handles = []

    raw_tensors: dict[str, np.ndarray] = {}

    def hook(name):
        def _hook(_module, _inputs, output):
            if isinstance(output, torch.Tensor):
                captures.append(tensor_summary(name, output))
                raw_tensors[name] = output.detach().cpu().numpy().astype(np.float32)
            else:
                print(f"[py-dump] WARN: {name} produced non-Tensor output: {type(output)}")
        return _hook

    # Frontend stem sub-stages.
    stem = model.frontend.stem
    handles.append(stem.bn1d.register_forward_hook(hook("stem.bn1d")))
    handles.append(stem.conv2d.register_forward_hook(hook("stem.conv2d")))
    handles.append(stem.bn2d.register_forward_hook(hook("stem.bn2d")))
    handles.append(stem.activation.register_forward_hook(hook("stem.activation")))

    # Frontend blocks (3 of them).
    for i, block in enumerate(model.frontend.blocks):
        handles.append(block.partial.register_forward_hook(hook(f"frontend.blocks.{i}.partial")))
        handles.append(block.conv2d.register_forward_hook(hook(f"frontend.blocks.{i}.conv2d")))
        handles.append(block.norm.register_forward_hook(hook(f"frontend.blocks.{i}.norm")))
        handles.append(block.activation.register_forward_hook(hook(f"frontend.blocks.{i}.activation")))

    # Frontend concat + linear (last frontend stage).
    handles.append(model.frontend.linear.register_forward_hook(hook("frontend.linear")))

    # Transformer blocks (6 of them) — each layer is a ModuleList[Attn, FF],
    # not a single module. Hook each component, plus the post-norm.
    for i, layer in enumerate(model.transformer_blocks.layers):
        attn, ffn = layer[0], layer[1]
        handles.append(attn.register_forward_hook(hook(f"transformer.{i}.attn")))
        handles.append(ffn.register_forward_hook(hook(f"transformer.{i}.ffn")))
    handles.append(
        model.transformer_blocks.norm.register_forward_hook(hook("transformer.norm"))
    )

    # Final task heads — SumHead returns dict {beat, downbeat}, hook its
    # internal Linear so we get the pre-sigmoid logits as a tensor.
    handles.append(
        model.task_heads.beat_downbeat_lin.register_forward_hook(hook("head.linear"))
    )

    print(f"[py-dump] running model with {len(handles)} hooks …")
    with torch.no_grad():
        out = model(spect.unsqueeze(0))
    print(f"[py-dump] beat output shape: {out['beat'].shape}, "
          f"max sigmoid: {torch.sigmoid(out['beat']).max():.4f}")

    # Add the final sigmoid stats explicitly.
    sig_beat = torch.sigmoid(out["beat"])
    captures.append(tensor_summary("output.beat_sigmoid", sig_beat))
    captures.append(tensor_summary("output.beat_logits", out["beat"]))

    for h in handles:
        h.remove()

    if args.raw_dir is not None:
        args.raw_dir.mkdir(parents=True, exist_ok=True)
        for name, arr in raw_tensors.items():
            arr.tofile(str(args.raw_dir / f"{name}.bin"))
        print(f"[py-dump] wrote {len(raw_tensors)} raw tensors → {args.raw_dir}")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "source": str(args.audio),
        "variant": args.variant,
        "n_stages": len(captures),
        "stages": captures,
    }
    with args.out.open("w") as f:
        json.dump(payload, f, indent=2)
    print(f"[py-dump] wrote {len(captures)} stages → {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

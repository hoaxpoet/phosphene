#!/usr/bin/env python3
"""PANNs MobileNetV1 reference — ground truth for the MPSGraph port (IFC.2).

Loads the MobileNetV1 PANN (Kong et al., weights CC-BY-4.0, Zenodo 3987831) and:
  1. Prints clipwise top-tags + a 2 s/1 s per-family activity sweep on the two
     spike clips (the human-meaningful evidence — mirrors the D-177 spike).
  2. Dumps numerical fixtures (waveform window, internal log-mel, pre-sigmoid
     logits, clipwise probs) so the Swift MPSGraph port can be validated to
     numerical parity, plus the full per-family series for the closeout match.

Dev-only. Weights + clips are NOT committed. Run from the repo root with the
tools venv:  tools/.venv/bin/python tools/panns_reference.py

The model class is the canonical PANNs MobileNetV1 (qiuqiangkong/audioset_tagging_cnn,
MIT), inlined so this script has no dependency beyond torch/torchlibrosa/librosa.
"""
import json
import os
from pathlib import Path

import librosa
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torchlibrosa.augmentation import SpecAugmentation
from torchlibrosa.stft import LogmelFilterBank, Spectrogram

HOME = Path.home()
CKPT = HOME / "panns_data" / "MobileNetV1_mAP=0.389.pth"
LABELS = HOME / "panns_data" / "class_labels_indices.csv"
SR = 32000
CLIPS = {
    "sym5": "/tmp/sym5_i.mp3",          # Beethoven Sym 5 i. — string-dominant
    "octet": "/tmp/octet_op103.mp3",     # Beethoven Wind Octet Op.103 — winds/horns
}
OUT_DIR = Path(__file__).resolve().parent / "data" / "panns_reference"


# --- canonical PANNs MobileNetV1 (inlined, eval-only) -----------------------
def init_layer(layer):
    nn.init.xavier_uniform_(layer.weight)
    if hasattr(layer, "bias") and layer.bias is not None:
        layer.bias.data.fill_(0.0)


def init_bn(bn):
    bn.bias.data.fill_(0.0)
    bn.weight.data.fill_(1.0)


class MobileNetV1(nn.Module):
    def __init__(self, sample_rate, window_size, hop_size, mel_bins, fmin, fmax, classes_num):
        super().__init__()
        window, center, pad_mode = "hann", True, "reflect"
        ref, amin, top_db = 1.0, 1e-10, None
        self.spectrogram_extractor = Spectrogram(
            n_fft=window_size, hop_length=hop_size, win_length=window_size,
            window=window, center=center, pad_mode=pad_mode, freeze_parameters=True)
        self.logmel_extractor = LogmelFilterBank(
            sr=sample_rate, n_fft=window_size, n_mels=mel_bins, fmin=fmin, fmax=fmax,
            ref=ref, amin=amin, top_db=top_db, freeze_parameters=True)
        self.spec_augmenter = SpecAugmentation(
            time_drop_width=64, time_stripes_num=2, freq_drop_width=8, freq_stripes_num=2)
        self.bn0 = nn.BatchNorm2d(64)

        def conv_bn(inp, oup, stride):
            return nn.Sequential(
                nn.Conv2d(inp, oup, 3, 1, 1, bias=False), nn.AvgPool2d(stride),
                nn.BatchNorm2d(oup), nn.ReLU(inplace=True))

        def conv_dw(inp, oup, stride):
            return nn.Sequential(
                nn.Conv2d(inp, inp, 3, 1, 1, groups=inp, bias=False), nn.AvgPool2d(stride),
                nn.BatchNorm2d(inp), nn.ReLU(inplace=True),
                nn.Conv2d(inp, oup, 1, 1, 0, bias=False), nn.BatchNorm2d(oup),
                nn.ReLU(inplace=True))

        self.features = nn.Sequential(
            conv_bn(1, 32, 2), conv_dw(32, 64, 1), conv_dw(64, 128, 2), conv_dw(128, 128, 1),
            conv_dw(128, 256, 2), conv_dw(256, 256, 1), conv_dw(256, 512, 2), conv_dw(512, 512, 1),
            conv_dw(512, 512, 1), conv_dw(512, 512, 1), conv_dw(512, 512, 1), conv_dw(512, 512, 1),
            conv_dw(512, 1024, 2), conv_dw(1024, 1024, 1))
        self.fc1 = nn.Linear(1024, 1024, bias=True)
        self.fc_audioset = nn.Linear(1024, classes_num, bias=True)

    def forward(self, x, return_intermediates=False):
        taps = {}
        x = self.spectrogram_extractor(x)        # (B,1,T,513) power
        logmel = self.logmel_extractor(x)        # (B,1,T,64)
        x = logmel.transpose(1, 3)
        x = self.bn0(x)
        x = x.transpose(1, 3)
        taps["bn0"] = x.squeeze(1).clone()       # (B,T,64)
        x = self.features[0](x)
        taps["features0"] = x.clone()            # (B,32,T',32)
        for i in range(1, len(self.features)):
            x = self.features[i](x)
        taps["features"] = x.clone()             # (B,1024,T'',2)
        x = torch.mean(x, dim=3)
        (x1, _) = torch.max(x, dim=2)
        x2 = torch.mean(x, dim=2)
        x = x1 + x2
        taps["pre_fc"] = x.clone()               # (B,1024)
        x = F.relu_(self.fc1(x))
        logits = self.fc_audioset(x)
        clipwise = torch.sigmoid(logits)
        if return_intermediates:
            taps["logmel"] = logmel.squeeze(1)
            taps["logits"] = logits
            taps["probs"] = clipwise
            return clipwise, logits, logmel.squeeze(1), taps
        return clipwise


def load_labels():
    import csv
    with open(LABELS) as f:
        rows = list(csv.reader(f))
    return [r[2] for r in rows[1:]]


# IFC.3 orchestral instrument-family taxonomy (AudioSet labels → 4 families).
# Single source of truth — the Swift InstrumentFamily.audioSetClasses mirror is
# cross-checked against the resolved indices in the fixtures (windows.json).
# woodwinds includes the "Wind instrument, woodwind instrument" catch-all (oboe/
# bassoon have no dedicated AudioSet class); percussion is the orchestral set
# anchored on Timpani; vehicle/air/train/foghorns are excluded from brass.
FAMILIES = {
    "strings":    ["Bowed string instrument", "String section", "Violin, fiddle",
                   "Pizzicato", "Cello", "Double bass", "Harp"],
    "brass":      ["Brass instrument", "French horn", "Trumpet", "Trombone"],
    "woodwinds":  ["Wind instrument, woodwind instrument", "Flute", "Saxophone", "Clarinet"],
    "percussion": ["Percussion", "Drum", "Bass drum", "Timpani", "Cymbal",
                   "Mallet percussion", "Marimba, xylophone", "Glockenspiel", "Vibraphone"],
}


def main():
    torch.manual_seed(0)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    model = MobileNetV1(SR, 1024, 320, 64, 50, 14000, 527)
    ck = torch.load(CKPT, map_location="cpu", weights_only=False)
    model.load_state_dict(ck["model"])
    model.eval()
    labels = load_labels()
    fam_idx = {f: [labels.index(n) for n in ns if n in labels] for f, ns in FAMILIES.items()}

    def infer(seg, intermediates=False):
        with torch.no_grad():
            t = torch.tensor(seg[None, :], dtype=torch.float32)
            return model(t, return_intermediates=intermediates)

    summary = {}
    for tag, path in CLIPS.items():
        y, _ = librosa.load(path, sr=SR, mono=True, duration=40.0)
        clip = infer(y).numpy()[0]
        top = sorted(range(len(clip)), key=lambda i: -clip[i])[:15]
        print(f"\n=== {tag}: TOP-15 CLIPWISE (40s) ===")
        for i in top:
            print(f"  {clip[i]:5.3f}  {labels[i]}")

        win, hop = int(2.0 * SR), int(1.0 * SR)
        times, series = [], {f: [] for f in FAMILIES}
        for start in range(0, len(y) - win + 1, hop):
            cw = infer(y[start:start + win]).numpy()[0]
            times.append(start / SR)
            for f, ii in fam_idx.items():
                series[f].append(float(max((cw[i] for i in ii), default=0.0)))
        print(f"\n=== {tag}: PER-FAMILY (2s win / 1s hop) ===")
        print("  t(s) " + " ".join(f"{f[:6]:>7}" for f in FAMILIES))
        for k, t in enumerate(times):
            print(f"  {t:4.0f} " + " ".join(f"{series[f][k]:7.3f}" for f in FAMILIES))
        for f in FAMILIES:
            s = np.array(series[f])
            print(f"  {f:10s} mean {s.mean():.3f} peak {s.max():.3f} range {s.max()-s.min():.3f}")
        summary[tag] = {"top_tags": [[labels[i], float(clip[i])] for i in top],
                        "times": times, "series": series}

    # --- numerical fixtures: two 2 s windows fed identically to the Swift port -
    # sym5@0s carries deep intermediate taps for layer-by-layer parity
    # localization; octet@6s is a second end-to-end cross-check.
    def flat(t):
        a = t.numpy()[0]
        return {"shape": list(a.shape), "data": a.astype(np.float32).ravel().tolist()}

    fixtures = {}
    for tag, start_s, deep in [("sym5", 0.0, True), ("octet", 6.0, False)]:
        y, _ = librosa.load(CLIPS[tag], sr=SR, mono=True, offset=start_s, duration=2.0)
        y = y[:int(2.0 * SR)]
        clipwise, logits, logmel, taps = infer(y, intermediates=True)
        entry = {
            "waveform": y.astype(np.float32).tolist(),
            "logmel": logmel.numpy()[0].astype(np.float32).ravel().tolist(),  # (T*64,) row-major
            "logits": logits.numpy()[0].astype(np.float32).tolist(),    # (527,)
            "probs": clipwise.numpy()[0].astype(np.float32).tolist(),
        }
        if deep:
            entry["taps"] = {k: flat(taps[k]) for k in ("bn0", "pre_fc")}
        fixtures[f"{tag}@{start_s:.0f}s"] = entry
        print(f"\nfixture {tag}@{start_s:.0f}s: logmel {logmel.shape[1:]}  "
              f"top prob {clipwise.max().item():.3f} ({labels[int(clipwise.argmax())]})")

    # Musically-meaningful windows for the per-family-match closeout: strings-
    # dominant (sym5) + the brass↔woodwind trades (octet). Each carries its 2 s
    # waveform + probs + per-family values, so the Swift port can reproduce the
    # discrimination and be compared row-for-row against this reference.
    # Front-end parity is proven on the two end-to-end fixtures above; these
    # windows carry the (smaller) log-mel + probs so the Swift network is fed
    # the identical reference log-mel and compared family-for-family.
    windows = []
    for tag, t in [("sym5", 9.0), ("sym5", 30.0), ("octet", 3.0),
                   ("octet", 8.0), ("octet", 14.0), ("octet", 17.0)]:
        y, _ = librosa.load(CLIPS[tag], sr=SR, mono=True, offset=t, duration=2.0)
        y = y[:int(2.0 * SR)]
        cw, _, lm, _ = infer(y, intermediates=True)
        cw = cw.numpy()[0]
        fam = {f: float(max((cw[i] for i in ii), default=0.0)) for f, ii in fam_idx.items()}
        top = sorted(range(len(cw)), key=lambda i: -cw[i])[:3]
        windows.append({"tag": tag, "t": t,
                        "logmel": lm.numpy()[0].astype(np.float32).ravel().tolist(),
                        "probs": cw.astype(np.float32).tolist(),
                        "family": fam, "top3": [[labels[i], float(cw[i])] for i in top]})
        print(f"window {tag}@{t:.0f}s: " + " ".join(f"{f}={fam[f]:.3f}" for f in FAMILIES))

    windows_doc = {"family_indices": fam_idx, "windows": windows}
    (OUT_DIR / "per_family.json").write_text(json.dumps(summary))
    (OUT_DIR / "fixtures.json").write_text(json.dumps(fixtures))
    (OUT_DIR / "windows.json").write_text(json.dumps(windows_doc))
    print(f"\nwrote {OUT_DIR}/per_family.json + fixtures.json + windows.json")


if __name__ == "__main__":
    main()

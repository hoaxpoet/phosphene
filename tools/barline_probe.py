#!/usr/bin/env python3
"""barline_probe.py — is bar-line phase recoverable WITHOUT the downbeat activation stream?

The beat-sync program has established, four independent ways, that bar position cannot be
read out of Beat This!'s downbeat activations (D-208 + its FT.1 amendment). But beats
themselves are good — suite-1 F 0.97 — so on a local file we hold ~400-1000 reliable beat
times and the only open question is *which of them are bar lines*.

That is a periodicity-and-phase search over a tiny integer space, and it need not use the
downbeat stream at all. This probe tests whether beat-synchronous accent features carry the
bar: low-band energy (kick lands on 1), broadband RMS, spectral flux (change lands on bars),
and harmonic change (chords change on bar lines).

METHOD. For each meter B and phase p, the score is a standardised contrast
    d(B,p) = (mean feature at bar-line beats - mean elsewhere) / sd(all beats)
whose expectation is 0 under the null for ANY B — deliberately, because DBN.2 was derailed
by a statistic whose bias scaled with B.

That is not sufficient on its own: larger B maximises over more phases with fewer samples
per phase, so its max-over-phase is more inflated by chance. So every score is reported
against a PERMUTATION NULL — the same max-over-phase statistic computed on shuffled
features — and what counts is the margin over that null, not the raw d.

Usage:
    ~/phosphene-ml-env/bin/python tools/barline_probe.py \\
        --beats-dir /tmp/barprobe \\
        --fixtures ~/phosphene_beatbench_fixtures
"""

from __future__ import annotations
import argparse, glob, json, os, subprocess, sys
import numpy as np

SR = 22050
# D-207 fixed the system's hypothesis set at {3,4,5,7}. 2 and 6 are excluded for the
# same reason 6/9/12 were: they are sub- or super-multiples of a real bar length, not
# candidate bars. Including 2 in a first pass let kick-on-alternate-beats — a genuine
# periodicity that is NOT the bar — win the argmax on three tracks.
METERS = (3, 4, 5, 7)
N_PERM = 200
RNG = np.random.default_rng(20260731)


def decode(path: str) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(SR),
         "-f", "f32le", "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def beat_features(audio: np.ndarray, beats: list[float]) -> dict[str, np.ndarray]:
    """One value per beat, from the window running from that beat to the next."""
    n_fft = 2048
    freqs = np.fft.rfftfreq(n_fft, 1.0 / SR)
    low = freqs < 200.0
    # Chroma: map each bin to a pitch class (ignore sub-audible / very high bins).
    with np.errstate(divide="ignore"):
        midi = 69 + 12 * np.log2(np.maximum(freqs, 1e-6) / 440.0)
    pc = np.mod(np.round(midi).astype(int), 12)
    usable = (freqs > 55) & (freqs < 4000)

    spec, low_e, rms = [], [], []
    for i, t in enumerate(beats):
        start = int(t * SR)
        end = int(beats[i + 1] * SR) if i + 1 < len(beats) else start + n_fft
        seg = audio[start:max(end, start + n_fft)][:n_fft]
        if len(seg) < n_fft:
            seg = np.pad(seg, (0, n_fft - len(seg)))
        rms.append(float(np.sqrt(np.mean(seg ** 2)) + 1e-12))
        mag = np.abs(np.fft.rfft(seg * np.hanning(n_fft)))
        spec.append(mag)
        low_e.append(float(mag[low].sum()))
    spec = np.array(spec)

    # Spectral flux: positive change from the previous beat's spectrum.
    flux = np.zeros(len(beats))
    flux[1:] = np.maximum(spec[1:] - spec[:-1], 0).sum(axis=1)

    # Chroma change: 1 - cosine similarity between adjacent beats' pitch-class profiles.
    chroma = np.zeros((len(beats), 12))
    for k in range(12):
        sel = usable & (pc == k)
        chroma[:, k] = spec[:, sel].sum(axis=1)
    chroma /= (np.linalg.norm(chroma, axis=1, keepdims=True) + 1e-12)
    hchange = np.zeros(len(beats))
    hchange[1:] = 1.0 - np.sum(chroma[1:] * chroma[:-1], axis=1)

    return {"low_energy": np.array(low_e), "rms": np.array(rms),
            "flux": flux, "harmonic_change": hchange}


def contrast(feat: np.ndarray, meter: int, phase: int) -> float:
    """Standardised mean difference; expectation 0 under the null for any meter."""
    idx = np.arange(len(feat))
    on = (idx % meter) == phase
    if on.sum() < 2 or (~on).sum() < 2:
        return 0.0
    sd = feat.std()
    if sd < 1e-12:
        return 0.0
    return float((feat[on].mean() - feat[~on].mean()) / sd)


def best_phase(feat: np.ndarray, meter: int) -> tuple[int, float]:
    scores = [contrast(feat, meter, p) for p in range(meter)]
    p = int(np.argmax(scores))
    return p, float(scores[p])


def null_max(feat: np.ndarray, meter: int) -> float:
    """Mean max-over-phase contrast on shuffled features — the chance baseline."""
    vals = []
    shuffled = feat.copy()
    for _ in range(N_PERM):
        RNG.shuffle(shuffled)
        vals.append(max(contrast(shuffled, meter, p) for p in range(meter)))
    return float(np.mean(vals))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--beats-dir", required=True)
    ap.add_argument("--fixtures", required=True)
    args = ap.parse_args()
    fixtures = os.path.expanduser(args.fixtures)

    print("\n============ bar-line probe — can accent features carry the bar? ============")
    print("d = standardised contrast at the best phase; null = same statistic on shuffled")
    print("features (chance level for that meter). margin = d - null. Only margin counts.\n")

    hits = misses = 0
    for path in sorted(glob.glob(os.path.join(args.beats_dir, "*.beats.json"))):
        doc = json.load(open(path))
        name, truth, beats = doc["track"], doc.get("truth_meter"), doc["beats"]
        audio = None
        for ext in ("wav", "mp3", "m4a", "flac"):
            cand = os.path.join(fixtures, f"{name}.{ext}")
            if os.path.exists(cand):
                audio = decode(cand)
                break
        if audio is None:
            print(f"  {name}: fixture missing"); continue

        feats = beat_features(audio, beats)
        print(f"  {name}  (truth {truth}, {len(beats)} beats)")
        best_overall = (None, None, -9.9)
        for fname, feat in feats.items():
            row, margins = [], {}
            for meter in METERS:
                p, d = best_phase(feat, meter)
                margin = d - null_max(feat, meter)
                margins[meter] = (margin, p)
                row.append(f"{meter}:{margin:+.3f}")
            pick = max(margins, key=lambda m: margins[m][0])
            flag = "" if truth is None else (" ✓" if pick == truth else " ✗")
            print(f"      {fname:16s} {'  '.join(row)}   → {pick}{flag}")
            if margins[pick][0] > best_overall[2]:
                best_overall = (fname, pick, margins[pick][0])
        fname, pick, margin = best_overall
        verdict = "" if truth is None else (" ✓" if pick == truth else " ✗")
        print(f"      {'BEST':16s} {fname} → meter {pick} (margin {margin:+.3f}){verdict}\n")
        if truth is not None:
            hits += int(pick == truth); misses += int(pick != truth)

    print(f"  ground-truthed tracks: {hits} correct / {hits + misses}")
    print("""
  Read: a margin near 0 means the feature carries no bar information beyond chance,
  and no amount of search over (meter, phase) will recover one. A clearly positive
  margin on the true meter means the bar IS in the audio, just not in the downbeat
  activation stream — which would be the changed premise D-208 asks for.
============================================================================\n""")
    return 0


if __name__ == "__main__":
    sys.exit(main())

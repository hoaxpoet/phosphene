#!/usr/bin/env python3
"""metrical_level_probe.py — FT.3.1: is the beat grid at the notated level, blind?

WHY. FT.3 found the bar's METER on 6/6 truthed tracks but its PHASE on only 3/6, and the
two clean phase failures (money, bleed) are exactly the two tracks with a large AMLt-CMLt
gap — a grid running at double or half the beat a listener would tap. AMLt-CMLt already
NAMES a wrong level, but only against ground truth. The open question is whether it can be
named blind, and D-210 says a wrong-level track should DECLINE the bar rather than have it
corrected — so a detector that declines correctly is a win even if it never corrects.

THE PHYSICS, which is what makes this different from a fifth swing at the activation stream:

  * A HALF-TIME grid marks every OTHER notated beat, so real musical events sit BETWEEN
    grid beats. Evidence: accent at the midpoints is as strong as accent at the beats.
  * A DOUBLE-TIME grid marks notated beats AND their midpoints, so alternate grid beats are
    weak. Evidence: strong period-2 alternation ACROSS grid beats.

Both are read from FT.3's own accent features. The second one is not a new idea — it is the
reason `barline_probe.py` had to exclude meter 2 from the hypothesis set ("kick-on-alternate-
beats is a genuine periodicity that is NOT the bar"). That excluded signal IS the
double-time detector; this script points it at the question it actually answers.

  A_double(track) = sum over features of [ max_p contrast(beat series, 2, p) - null ]
  A_half(track)   = sum over features of   contrast(interleaved beat+midpoint series, 2, 0)

`A_half` needs no null: it is a single fixed phase, so there is no max-over-phase inflation
to subtract (the failure that derailed DBN.2 twice and that FT.3 task 3 caught in the
probe's own rule).

Usage:
    ~/phosphene-ml-env/bin/python tools/metrical_level_probe.py \\
        --beats-dir /tmp/barprobe --fixtures ~/phosphene_beatbench_fixtures --synthetic
"""

from __future__ import annotations
import argparse, glob, json, os, sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from barline_probe import beat_features, decode  # noqa: E402
from barline_parity import contrasts, null_max  # noqa: E402

FEATURES = ("low_energy", "rms", "flux", "harmonic_change")
NULL_SEED = 20_260_819


# MARK: - Re-gridding (task 2's synthetic control)

def regrid(beats: list[float], factor: float) -> list[float]:
    """Put a KNOWN-GOOD grid deliberately at the wrong metrical level.

    Re-gridding, not resampling: the audio is untouched and only the grid moves, which is
    exactly the real failure (Phosphene's grid at the wrong level over correct audio).
    Resampling would change the spectral content too and confound the measurement.

      factor 2.0 -> DOUBLE-time grid (insert midpoints)
      factor 0.5 -> HALF-time grid (drop every other beat)
      factor 1.0 -> unchanged negative control
    """
    if factor == 1.0:
        return list(beats)
    if factor == 0.5:
        return list(beats[::2])
    if factor == 2.0:
        out = []
        for i in range(len(beats) - 1):
            out.append(beats[i])
            out.append((beats[i] + beats[i + 1]) / 2.0)
        out.append(beats[-1])
        return out
    raise ValueError(f"unsupported factor {factor}")


def midpoint_interleaved(beats: list[float]) -> list[float]:
    """beat, midpoint, beat, midpoint, ... — the series `A_half` is measured on."""
    out = []
    for i in range(len(beats) - 1):
        out.append(beats[i])
        out.append((beats[i] + beats[i + 1]) / 2.0)
    out.append(beats[-1])
    return out


# MARK: - The two statistics

def level_scores(audio: np.ndarray, beats: list[float]) -> dict:
    """(A_double, A_half) for one grid over one track."""
    at_beats = beat_features(audio, beats)
    at_both = beat_features(audio, midpoint_interleaved(beats))

    a_double = 0.0
    a_half = 0.0
    for index, name in enumerate(FEATURES):
        series = [float(v) for v in at_beats[name]]
        observed = contrasts(series, 2)
        a_double += max(observed) - null_max(series, 2, NULL_SEED + index)

        interleaved = [float(v) for v in at_both[name]]
        # Phase 0 = the grid beats; phase 1 = the midpoints between them.
        a_half += contrasts(interleaved, 2)[0]
    return {"a_double": a_double, "a_half": a_half, "beats": len(beats)}


# MARK: - Labels (task 1)

# Level label = grid BPM / truth BPM snapped to {0.5, 1, 2}, cross-checked against the
# committed BeatBench baseline's AMLt-CMLt gap. Tracks whose ratio is not an octave of the
# truth are EXCLUDED: their grid is not at a wrong LEVEL, it is on no stable pulse, which is
# a different failure and would poison the label set.
REAL_LABELS = {
    #  track              level  why (from BEATBENCH_BASELINE_2026-07-30.md)
    "billie_jean":        (1.0, "ratio 0.995, CMLt 0.97 = AMLt 0.97, gap 0.00"),
    "take_five":          (1.0, "ratio 1.013, CMLt 1.00 = AMLt 1.00, gap 0.00"),
    "solsbury_hill":      (1.0, "ratio 1.002, CMLt 1.00 = AMLt 1.00, gap 0.00"),
    "pyramid_song":       (1.0, "ratio 0.977, gap 0.00; CMLt 0.75 is grouped-16/8 "
                                "ambiguity, NOT a level error — weak negative"),
    "money":              (2.0, "ratio 1.906, CMLt 0.00 vs AMLt 0.88, gap 0.88"),
    "bleed":              (0.5, "ratio 0.507, CMLt 0.03 vs AMLt 0.84, gap 0.81"),
}
EXCLUDED = {
    "yyz": "ratio 0.858 — not an octave; gap 0.00 (0.21/0.21) = grid on no real pulse",
    "bohemian_rhapsody": "ratio 1.100 — not an octave; gap 0.00 (0.48/0.48); tempo changes",
    "clair_de_lune": "ratio 2.577 — not an octave; AMLt 0.02 = no pulse at all (true rubato)",
}


# Committed BeatBench baseline (BEATBENCH_BASELINE_2026-07-30.md), reproduced at the top of
# this session. Used only for task 6's agreement table — never as a label.
BASELINE = {
    "billie_jean": (0.97, 0.97), "money": (0.00, 0.88), "pyramid_song": (0.75, 0.75),
    "solsbury_hill": (1.00, 1.00), "take_five": (1.00, 1.00), "yyz": (0.21, 0.21),
    "bohemian_rhapsody": (0.48, 0.48), "bleed": (0.03, 0.84), "clair_de_lune": (0.00, 0.02),
}


def run_benchmark_agreement(beats_dir: str, fixtures: str, truth_dir: str) -> None:
    """Task 6 — does the detector's verdict agree with each track's AMLt-CMLt gap, across the
    whole benchmark? The `status` column is the one that turned out to matter."""
    print("\n  --- task 6: detector verdict vs AMLt-CMLt gap, all 9 ground-truthed tracks ---")
    print("  gap = AMLt - CMLt: large means the grid found the pulse but disagrees with the")
    print("  reference about the LEVEL. It does NOT say which side is wrong — that is the")
    print("  finding. 'backends' is what librosa/madmom said about the TAPS at GT.2.\n")
    print(f"  {'track':22s} {'gap':>5s} {'detect':>6s} {'margin':>7s} {'status':18s} backends")
    for name in sorted(BASELINE):
        path = os.path.join(beats_dir, f"{name}.beats.json")
        audio = load_audio(name, fixtures)
        if not os.path.exists(path) or audio is None:
            continue
        cmlt, amlt = BASELINE[name]
        out = detect(audio, json.load(open(path))["beats"])
        gt_path = os.path.join(truth_dir, f"{name}.groundtruth.json")
        status, verdicts = "—", "—"
        if os.path.exists(gt_path):
            gt = json.load(open(gt_path))
            status = str(gt.get("status"))
            backends = gt.get("backends") or {}
            verdicts = "/".join(sorted({v.get("verdict", "?") for v in backends.values()}))
        print(f"  {name:22s} {amlt - cmlt:>5.2f} {(out['factor'] or 0):>6.1f} "
              f"{out['margin']:>7.3f} {status:18s} {verdicts}")


# MARK: - Main

def load_audio(name: str, fixtures: str) -> np.ndarray | None:
    for ext in ("wav", "mp3", "m4a", "flac"):
        candidate = os.path.join(fixtures, f"{name}.{ext}")
        if os.path.exists(candidate):
            return decode(candidate)
    return None


def print_labels() -> None:
    print("\n  --- task 1: the label set, and how small it is ---")
    print("  Level = grid BPM / truth BPM snapped to an octave, cross-checked against the")
    print("  committed BeatBench baseline's AMLt-CMLt gap. A detector can be fitted to two")
    print("  positives, which is the exact failure this increment exists because of.\n")
    print(f"  {'track':22s} {'level':>6s}  justification")
    for name, (level, why) in REAL_LABELS.items():
        print(f"  {name:22s} {level:>6.1f}  {why}")
    for name, why in EXCLUDED.items():
        print(f"  {name:22s} {'EXCL':>6s}  {why}")
    positives = sum(1 for lv, _ in REAL_LABELS.values() if lv != 1.0)
    negatives = sum(1 for lv, _ in REAL_LABELS.values() if lv == 1.0)
    print(f"\n  {positives} positives (one 2x, one 1/2x) and {negatives} negatives "
          f"(one weak). This is why task 2's synthetic set exists.")


def run_real(beats_dir: str, fixtures: str) -> list[dict]:
    print("\n  --- real tracks ---")
    print(f"  {'track':22s} {'level':>6s} {'A_double':>9s} {'A_half':>8s} {'beats':>6s}")
    rows = []
    for name, (level, _) in REAL_LABELS.items():
        path = os.path.join(beats_dir, f"{name}.beats.json")
        audio = load_audio(name, fixtures)
        if not os.path.exists(path) or audio is None:
            print(f"  {name:22s} beats dump or fixture missing")
            continue
        beats = json.load(open(path))["beats"]
        scores = level_scores(audio, beats)
        rows.append({"track": name, "level": level, **scores})
        print(f"  {name:22s} {level:>6.1f} {scores['a_double']:>9.3f} "
              f"{scores['a_half']:>8.3f} {scores['beats']:>6d}")
    return rows


def run_synthetic(beats_dir: str, fixtures: str, bases: list[str]) -> list[dict]:
    """Task 2. Every case's true level is known BY CONSTRUCTION, so the detector is measured
    on material it was not fitted to. Verified bases (a right-level label from ground truth)
    support an ABSOLUTE accuracy claim; unverified bases support only the weaker claim that
    the detector ORDERS 1/2x < 1x < 2x within a track, which holds whatever the base's true
    level is."""
    print("\n  --- task 2: synthetic control (re-gridded; audio untouched) ---")
    print("  'verified' bases carry a ground-truth right-level label; the rest are assumed")
    print("  right-level and are scored only on within-track ORDERING, which survives that")
    print("  assumption being wrong.\n")
    print(f"  {'base':22s} {'ver':>3s} {'factor':>6s} {'A_double':>9s} {'A_half':>8s}")
    rows = []
    for name in bases:
        path = os.path.join(beats_dir, f"{name}.beats.json")
        audio = load_audio(name, fixtures)
        if not os.path.exists(path) or audio is None:
            continue
        beats = json.load(open(path))["beats"]
        verified = REAL_LABELS.get(name, (None, ""))[0] == 1.0
        for factor in (0.5, 1.0, 2.0):
            grid = regrid(beats, factor)
            if len(grid) < 40:
                continue
            scores = level_scores(audio, grid)
            rows.append({"base": name, "verified": verified, "factor": factor, **scores})
            print(f"  {name:22s} {'y' if verified else '.':>3s} {factor:>6.1f} "
                  f"{scores['a_double']:>9.3f} {scores['a_half']:>8.3f}")
        print()
    return rows


def levelness(scores: dict) -> float:
    """How much a grid looks like it IS the notated beat.

    High when accent sits on the grid beats rather than between them (`a_half` high) AND
    there is no strong alternation across grid beats (`a_double` low). The two are the two
    ways a grid can be at the wrong level, so the difference is the natural single score."""
    return scores["a_half"] - scores["a_double"]


def detect(audio: np.ndarray, beats: list[float]) -> dict:
    """WITHIN-TRACK detection. The absolute distributions of `a_double` and `a_half` overlap
    badly across tracks (see `report_separation`), so no global threshold can work. But the
    signals order correctly WITHIN a track — so instead of thresholding, re-grid the track's
    own beats to 1/2x and 2x and ask which of the three candidate levels looks most like the
    notated beat. That is a comparison against the track's own baseline, which is the axis the
    data actually supports.

    Returns the correction factor to APPLY to the given grid: 1.0 = already right, 0.5 = the
    grid is running double-time, 2.0 = half-time."""
    candidates = {}
    for factor in (0.5, 1.0, 2.0):
        grid = regrid(beats, factor)
        if len(grid) < 40:
            continue
        candidates[factor] = levelness(level_scores(audio, grid))
    if not candidates:
        return {"factor": None, "margin": 0.0, "scores": {}}
    best = max(candidates, key=candidates.__getitem__)
    runner_up = max((v for k, v in candidates.items() if k != best), default=candidates[best])
    return {"factor": best, "margin": candidates[best] - runner_up, "scores": candidates}


def report_separation(rows: list[dict]) -> None:
    """Does anything separate the synthetic 2x and 1/2x cases? Task 3's hard stop."""
    print("\n  --- task 3: does either signal separate the synthetic levels? ---")
    for key, expect in (("a_double", "HIGH on 2.0"), ("a_half", "LOW on 0.5")):
        print(f"\n  {key} ({expect}):")
        for factor in (0.5, 1.0, 2.0):
            values = sorted(r[key] for r in rows if r["factor"] == factor)
            if not values:
                continue
            print(f"    factor {factor:>3.1f}: n={len(values):2d}  "
                  f"min {values[0]:+7.3f}  median {values[len(values) // 2]:+7.3f}  "
                  f"max {values[-1]:+7.3f}")
        for a, b in ((2.0, 1.0), (0.5, 1.0)):
            hi = [r[key] for r in rows if r["factor"] == a]
            lo = [r[key] for r in rows if r["factor"] == b]
            if hi and lo:
                overlap = "OVERLAP" if (min(hi) <= max(lo) and min(lo) <= max(hi)) else "SEPARATED"
                print(f"    {a} vs {b}: {overlap}")

    ordered = 0
    total = 0
    for base in sorted({r["base"] for r in rows}):
        per = {r["factor"]: r for r in rows if r["base"] == base}
        if len(per) < 3:
            continue
        total += 1
        if per[0.5]["a_half"] < per[1.0]["a_half"] and per[2.0]["a_double"] > per[1.0]["a_double"]:
            ordered += 1
    print(f"\n  within-track ordering correct on {ordered}/{total} bases "
          f"(A_half rises 0.5 -> 1.0 AND A_double rises 1.0 -> 2.0)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--beats-dir", required=True)
    ap.add_argument("--fixtures", required=True)
    ap.add_argument("--synthetic", action="store_true")
    ap.add_argument("--groundtruth",
                    default="PhospheneEngine/Tests/Fixtures/beatbench/groundtruth")
    args = ap.parse_args()
    fixtures = os.path.expanduser(args.fixtures)

    print("\n========= FT.3.1 — is the grid at the notated metrical level, blind? =========")
    print_labels()
    real = run_real(args.beats_dir, fixtures)

    if args.synthetic:
        bases = sorted(os.path.basename(p).replace(".beats.json", "")
                       for p in glob.glob(os.path.join(args.beats_dir, "*.beats.json")))
        bases = [b for b in bases if REAL_LABELS.get(b, (1.0, ""))[0] == 1.0
                 or b not in REAL_LABELS]
        bases = [b for b in bases if b not in EXCLUDED]
        synthetic = run_synthetic(args.beats_dir, fixtures, bases)
        report_separation(synthetic)
        run_detection(args.beats_dir, fixtures)
        run_benchmark_agreement(args.beats_dir, fixtures, args.groundtruth)
        json.dump({"real": real, "synthetic": synthetic},
                  open(os.path.join(args.beats_dir, "level_probe.json"), "w"), indent=2)
        print(f"\n  wrote {os.path.join(args.beats_dir, 'level_probe.json')}")
    print("=" * 79 + "\n")
    return 0




# MARK: - Task 3/5: within-track detection, scored

def run_detection(beats_dir: str, fixtures: str) -> None:
    """Score the within-track detector on the real labels AND on the synthetic set."""
    print("\n  --- task 3/5: WITHIN-TRACK detection ---")
    print("  'want' is the correction the label implies: a grid at level 2.0 (double-time)")
    print("  needs 0.5 applied to it. 'got' is the detector's pick; 'margin' is its lead over")
    print("  the runner-up candidate.\n")

    print(f"  REAL\n  {'track':22s} {'level':>5s} {'want':>5s} {'got':>5s} {'margin':>7s}  ok")
    real_ok = real_n = 0
    real_rows = []
    for name, (level, _) in REAL_LABELS.items():
        path = os.path.join(beats_dir, f"{name}.beats.json")
        audio = load_audio(name, fixtures)
        if not os.path.exists(path) or audio is None:
            continue
        want = 1.0 / level
        out = detect(audio, json.load(open(path))["beats"])
        ok = out["factor"] == want
        real_ok += int(ok)
        real_n += 1
        real_rows.append({"track": name, "want": want, **out})
        print(f"  {name:22s} {level:>5.1f} {want:>5.1f} "
              f"{(out['factor'] or 0):>5.1f} {out['margin']:>7.3f}  {'OK' if ok else 'X'}")
    print(f"  real: {real_ok}/{real_n}")

    print(f"\n  SYNTHETIC (true level known by construction)\n"
          f"  {'base':22s} {'ver':>3s} {'made':>5s} {'want':>5s} {'got':>5s} {'margin':>7s}  ok")
    bases = sorted(os.path.basename(p).replace(".beats.json", "")
                   for p in glob.glob(os.path.join(beats_dir, "*.beats.json")))
    bases = [b for b in bases if b not in EXCLUDED and REAL_LABELS.get(b, (1.0, ""))[0] == 1.0]
    syn_ok = syn_n = ver_ok = ver_n = 0
    syn_rows = []
    for name in bases:
        audio = load_audio(name, fixtures)
        path = os.path.join(beats_dir, f"{name}.beats.json")
        if audio is None or not os.path.exists(path):
            continue
        beats = json.load(open(path))["beats"]
        verified = name in REAL_LABELS
        for made in (0.5, 1.0, 2.0):
            grid = regrid(beats, made)
            if len(grid) < 40:
                continue
            want = 1.0 / made
            out = detect(audio, grid)
            ok = out["factor"] == want
            syn_ok += int(ok)
            syn_n += 1
            if verified:
                ver_ok += int(ok)
                ver_n += 1
            syn_rows.append({"base": name, "verified": verified, "made": made,
                             "want": want, **out})
            print(f"  {name:22s} {'y' if verified else '.':>3s} {made:>5.1f} {want:>5.1f} "
                  f"{(out['factor'] or 0):>5.1f} {out['margin']:>7.3f}  {'OK' if ok else 'X'}")
    print(f"\n  synthetic, ALL bases      : {syn_ok}/{syn_n}")
    print(f"  synthetic, VERIFIED bases : {ver_ok}/{ver_n}  "
          f"(the only ones supporting an absolute claim)")
    confusion(syn_rows, real_rows)
    json.dump({"real": real_rows, "synthetic": syn_rows},
              open(os.path.join(beats_dir, "level_detect.json"), "w"), indent=2)


def confusion(syn_rows: list[dict], real_rows: list[dict]) -> None:
    """Task 5 — the confusion matrix and the confident-correct / confident-wrong overlap."""
    print("\n  --- task 5: confusion matrix (synthetic, all bases) ---")
    print(f"  {'want\\got':>10s} " + "  ".join(f"{f:>5.1f}" for f in (0.5, 1.0, 2.0)))
    for want in (0.5, 1.0, 2.0):
        counts = [sum(1 for r in syn_rows if r["want"] == want and r["factor"] == got)
                  for got in (0.5, 1.0, 2.0)]
        print(f"  {want:>10.1f} " + "  ".join(f"{c:>5d}" for c in counts))

    right = sorted(r["margin"] for r in syn_rows + real_rows if r["factor"] == r["want"])
    wrong = sorted(r["margin"] for r in syn_rows + real_rows if r["factor"] != r["want"])
    print("\n  --- task 5: margin overlap (synthetic + real together) ---")
    print(f"  correct   (n={len(right):2d}): min {right[0]:+.3f}  median "
          f"{right[len(right) // 2]:+.3f}  max {right[-1]:+.3f}" if right else "  correct: none")
    print(f"  incorrect (n={len(wrong):2d}): min {wrong[0]:+.3f}  median "
          f"{wrong[len(wrong) // 2]:+.3f}  max {wrong[-1]:+.3f}" if wrong else "  incorrect: none")
    if right and wrong:
        if max(wrong) >= min(right):
            print(f"  OVERLAP: incorrect reaches {max(wrong):+.3f}, correct starts at "
                  f"{min(right):+.3f} — no margin threshold cleanly separates them.")
        else:
            print(f"  SEPARATED: incorrect tops out at {max(wrong):+.3f}, correct starts at "
                  f"{min(right):+.3f}.")
        print("\n  undetermined-rate vs confident-wrong-rate, by decline threshold:")
        print(f"  {'thresh':>7s} {'answered':>8s} {'correct':>7s} {'CONF-WRONG':>10s}")
        for threshold in (0.0, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0):
            kept = [r for r in syn_rows + real_rows if r["margin"] >= threshold]
            ok = sum(1 for r in kept if r["factor"] == r["want"])
            print(f"  {threshold:>7.2f} {len(kept):>8d} {ok:>7d} {len(kept) - ok:>10d}")


if __name__ == "__main__":
    sys.exit(main())

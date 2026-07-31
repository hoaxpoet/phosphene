#!/usr/bin/env python3
"""barline_combine.py — FT.3 tasks 1-3: unseen tracks, PHASE, and the combination rule.

`tools/barline_probe.py` established 6/6 on meter over the ground-truthed six, with three
caveats it stated about itself: the meter set was narrowed after seeing results, no single
feature works alone, and **phase was never measured**. This script answers those three.

  Task 1  Re-score on eight tracks that have no ground truth and so played no part in
          designing the method. Their meters here are PUBLISHED / by-ear, not tapped truth,
          and are labelled as such.
  Task 2  Score PHASE — which beat is the bar line — against `downbeats_s` in the
          ground-truth JSON. A right meter on the wrong phase is visually wrong.
  Task 3  State a combination rule over the four features and show, on a feature set with
          NO bar information, that it scores every meter equally. That control is the whole
          point: DBN.2 died twice to a statistic whose bias scaled with the meter.

Usage:
    ~/phosphene-ml-env/bin/python tools/barline_combine.py \\
        --beats-dir /tmp/barprobe --fixtures ~/phosphene_beatbench_fixtures \\
        --groundtruth PhospheneEngine/Tests/Fixtures/beatbench/groundtruth
"""

from __future__ import annotations
import argparse, glob, json, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from barline_probe import METERS, N_PERM, beat_features, decode  # noqa: E402

RNG = np.random.default_rng(20260731)
FEATURES = ("low_energy", "rms", "flux", "harmonic_change")

# Task 1's unseen set. NOT ground truth — published notation / by ear, recorded here so a
# disagreement can be read as "the method is wrong" OR "this label is wrong", not silently
# scored as a hit. Every one of them is in 4, which is itself a limitation (see the report).
PUBLISHED = {
    "so_what": 4, "around_the_world": 4, "stayin_alive": 4, "superstition": 4,
    "there_there": 4, "girl_from_ipanema": 4, "giorgio_by_moroder": 4,
    "dance_yrself_clean": 4,
}


# MARK: - Vectorised contrast (identical statistic to barline_probe.contrast)

def phase_onehot(length: int, meter: int) -> np.ndarray:
    """(length, meter) indicator of which phase each beat index belongs to."""
    onehot = np.zeros((length, meter))
    onehot[np.arange(length), np.arange(length) % meter] = 1.0
    return onehot


def contrasts(feat: np.ndarray, meter: int) -> np.ndarray:
    """d(meter, p) for every phase p at once — same formula as the probe, vectorised."""
    return contrasts_batch(feat[None, :], meter)[0]


def contrasts_batch(feats: np.ndarray, meter: int) -> np.ndarray:
    """(n, meter) contrasts for a stack of n feature vectors sharing one length."""
    n, length = feats.shape
    onehot = phase_onehot(length, meter)
    counts = onehot.sum(axis=0)                       # (meter,)
    sums = feats @ onehot                             # (n, meter)
    total = feats.sum(axis=1, keepdims=True)          # (n, 1)
    sd = feats.std(axis=1, keepdims=True)             # (n, 1)
    mean_on = sums / counts
    mean_off = (total - sums) / (length - counts)
    return np.where(sd < 1e-12, 0.0, (mean_on - mean_off) / np.maximum(sd, 1e-12))


def permuted(feat: np.ndarray, draws: int) -> np.ndarray:
    """(draws, len) — the feature shuffled `draws` ways. Preserves its marginal exactly."""
    return feat[np.argsort(RNG.random((draws, len(feat))), axis=1)]


# MARK: - The three candidate combination rules

def rule_max_feature(feats: dict[str, np.ndarray]) -> dict:
    """(a) INCUMBENT, what the probe did: per-feature null-corrected margin, take the max.

    Each feature picks its own meter AND its own phase; the winner is whichever feature is
    most confident. Max over four features is itself chance-inflated, and nothing corrects
    for that."""
    best = (-9.9, None, None, None)
    per_meter = {}
    for meter in METERS:
        top = -9.9
        for name in FEATURES:
            feat = feats[name]
            d = contrasts(feat, meter)
            margin = float(d.max() - contrasts_batch(permuted(feat, N_PERM), meter).max(axis=1).mean())
            top = max(top, margin)
            if margin > best[0]:
                best = (margin, meter, int(d.argmax()), name)
        per_meter[meter] = top
    return {"meter": best[1], "phase": best[2], "margin": best[0],
            "source": best[3], "per_meter": per_meter}


def rule_sum_margin(feats: dict[str, np.ndarray]) -> dict:
    """(b) Sum the four per-feature margins per meter. Features vote by strength, but each
    still votes at its own phase, so a meter can win with the features disagreeing on which
    beat is the bar line — and then phase has to be resolved separately."""
    per_meter, phases = {}, {}
    for meter in METERS:
        total = 0.0
        votes = np.zeros(meter)
        for name in FEATURES:
            feat = feats[name]
            d = contrasts(feat, meter)
            total += float(d.max() - contrasts_batch(permuted(feat, N_PERM), meter).max(axis=1).mean())
            votes += d
        per_meter[meter] = total
        phases[meter] = int(votes.argmax())
    meter = max(per_meter, key=per_meter.__getitem__)
    return {"meter": meter, "phase": phases[meter], "margin": per_meter[meter],
            "gap": per_meter[meter] - max(per_meter[m] for m in METERS if m != meter),
            "source": "sum", "per_meter": per_meter}


def rule_common_phase(feats: dict[str, np.ndarray]) -> dict:
    """(c) CHOSEN. One statistic, one null, and phase falls out of it.

        S(B,p) = sum over features of d(feature, B, p)      -- all features at the SAME p
        margin(B) = max_p S(B,p) - E_null[max_p S(B,p)]

    The features are summed at a COMMON phase because that is the physical claim: the bar
    line is the same beat for the kick, the flux and the chord change. A feature that finds
    a strong period at a phase the others reject contributes nothing, which is the desired
    behaviour and is what (a) and (b) both fail to do.

    The null is drawn on the COMBINED statistic, with each feature shuffled independently,
    so the max-over-phase inflation AND the max-over-features inflation are both subtracted
    rather than only the first. That is the specific defect that let DBN.2's score scale
    with B; `--control` is the test that it is gone."""
    per_meter, phases = {}, {}
    for meter in METERS:
        observed = sum(contrasts(feats[n], meter) for n in FEATURES)
        null = sum(contrasts_batch(permuted(feats[n], N_PERM), meter) for n in FEATURES)
        per_meter[meter] = float(observed.max() - null.max(axis=1).mean())
        phases[meter] = int(observed.argmax())
    meter = max(per_meter, key=per_meter.__getitem__)
    return {"meter": meter, "phase": phases[meter], "margin": per_meter[meter],
            "gap": per_meter[meter] - max(per_meter[m] for m in METERS if m != meter),
            "source": "combined", "per_meter": per_meter}


RULES = {"max_feature": rule_max_feature, "sum_margin": rule_sum_margin,
         "common_phase": rule_common_phase}


# MARK: - Task 2: phase scoring

def tap_phases(beats: list[float], meter: int,
               downbeats: list[float]) -> np.ndarray | None:
    """Histogram over phases of where the ground-truth downbeat taps actually land.

    The taps are sparse hand taps, so each is snapped to its nearest beat and counted under
    that beat's index mod `meter`. Taps further than half a beat period from any beat are
    dropped as untrustworthy rather than scored. Returning the whole histogram — not just a
    hit rate — is deliberate: it separates "our phase is wrong" from "the taps never agreed
    on a phase in the first place", and only the first is our defect."""
    if not downbeats or len(beats) < 2:
        return None
    grid = np.asarray(beats)
    tol = float(np.median(np.diff(grid))) * 0.5
    hist = np.zeros(meter, dtype=int)
    for t in downbeats:
        i = int(np.abs(grid - t).argmin())
        if abs(grid[i] - t) <= tol:
            hist[i % meter] += 1
    return hist if hist.sum() else None


# MARK: - Task 3: the no-bar-information control

def control(rule_name: str, trials: int, length: int, real: dict | None) -> None:
    rule = RULES[rule_name]
    print(f"\n  --- control [{rule_name}]: {trials} feature sets with NO bar information ---")
    for label, maker in (
        ("gaussian noise", lambda: {n: RNG.standard_normal(length) for n in FEATURES}),
        ("shuffled REAL features (keeps the heavy tails)",
         (lambda: {n: RNG.permutation(real[n]) for n in FEATURES}) if real else None),
    ):
        if maker is None:
            continue
        picks, margins = [], {m: [] for m in METERS}
        for _ in range(trials):
            out = rule(maker())
            picks.append(out["meter"])
            for m in METERS:
                margins[m].append(out["per_meter"][m])
        counts = {m: picks.count(m) for m in METERS}
        share = {m: counts[m] / trials for m in METERS}
        worst = max(abs(s - 1 / len(METERS)) for s in share.values())
        print(f"    {label}")
        print("      picked meter : " + "  ".join(f"{m}:{counts[m]:3d} ({share[m]:.0%})" for m in METERS))
        print("      mean margin  : " + "  ".join(f"{m}:{np.mean(margins[m]):+.4f}" for m in METERS))
        trend = np.polyfit(METERS, [np.mean(margins[m]) for m in METERS], 1)[0]
        verdict = "PASS" if worst <= 0.10 and abs(trend) < 0.01 else "FAIL"
        print(f"      max deviation from uniform {worst:.0%}; margin-vs-meter slope "
              f"{trend:+.5f}/meter  → {verdict}\n")


# MARK: - Main

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--beats-dir", required=True)
    ap.add_argument("--fixtures", required=True)
    ap.add_argument("--groundtruth",
                    default="PhospheneEngine/Tests/Fixtures/beatbench/groundtruth")
    ap.add_argument("--control", type=int, default=200,
                    help="synthetic trials for the task-3 control (0 to skip)")
    args = ap.parse_args()
    fixtures = os.path.expanduser(args.fixtures)

    print("\n=========== FT.3 tasks 1-3 — unseen tracks, phase, combination rule ===========")
    print("meter columns show each rule's pick; ✓/✗ is against tapped truth, ~/! against a")
    print("PUBLISHED (not tapped) meter. phase = share of ground-truth downbeats landing on")
    print("the predicted bar-line beat; 'mode' is the phase the taps actually agree on.\n")

    header = (f"  {'track':22s} {'truth':>6s}  " +
              "  ".join(f"{r:>14s}" for r in RULES) + "   phase(common)")
    print(header)
    print("  " + "-" * (len(header) + 4))

    tally = {r: [0, 0] for r in RULES}          # [hits, scored] on tapped truth
    unseen_tally = {r: [0, 0] for r in RULES}   # [agrees, scored] on published meter
    phase_rows, real_for_control = [], None

    for path in sorted(glob.glob(os.path.join(args.beats_dir, "*.beats.json"))):
        doc = json.load(open(path))
        name, truth, beats = doc["track"], doc.get("truth_meter"), doc["beats"]
        published = PUBLISHED.get(name)
        audio = None
        for ext in ("wav", "mp3", "m4a", "flac"):
            cand = os.path.join(fixtures, f"{name}.{ext}")
            if os.path.exists(cand):
                audio = decode(cand)
                break
        if audio is None:
            print(f"  {name:22s} fixture missing")
            continue

        feats = beat_features(audio, beats)
        if real_for_control is None:
            real_for_control = feats

        cells, outs = [], {}
        for rname, rule in RULES.items():
            out = rule(feats)
            outs[rname] = out
            if truth is not None:
                mark = "✓" if out["meter"] == truth else "✗"
                tally[rname][0] += int(out["meter"] == truth)
                tally[rname][1] += 1
            elif published is not None:
                mark = "~" if out["meter"] == published else "!"
                unseen_tally[rname][0] += int(out["meter"] == published)
                unseen_tally[rname][1] += 1
            else:
                mark = " "
            cells.append(f"{out['meter']}{mark}p{out['phase']} {out['margin']:+.3f}")

        # Task 2 — phase, scored for EVERY rule against the tapped downbeats.
        gt_path = os.path.join(args.groundtruth, f"{name}.groundtruth.json")
        phase_cell = "no truth"
        if os.path.exists(gt_path):
            gt = json.load(open(gt_path))
            downbeats = gt.get("downbeats_s") or []
            scores = {}
            for rname, out in outs.items():
                hist = tap_phases(beats, out["meter"], downbeats)
                if hist is None:
                    continue
                total = int(hist.sum())
                scores[rname] = (float(hist[out["phase"]]) / total,
                                 int(hist.argmax()), float(hist.max()) / total, total)
            if scores:
                phase_cell = "  ".join(f"{r[:3]}:{scores[r][0]:.0%}" for r in RULES
                                       if r in scores)
                phase_rows.append((name, truth, outs, scores))
            else:
                phase_cell = "no downbeats"

        label = f"{truth}" if truth is not None else (f"[{published}]" if published else "—")
        print(f"  {name:22s} {label:>6s}  " + "  ".join(f"{c:>14s}" for c in cells) +
              f"   {phase_cell}")

    print("\n  tapped-truth accuracy   : " +
          "  ".join(f"{r} {tally[r][0]}/{tally[r][1]}" for r in RULES))
    print("  published-meter agreement: " +
          "  ".join(f"{r} {unseen_tally[r][0]}/{unseen_tally[r][1]}" for r in RULES))

    if phase_rows:
        print("\n  --- task 2: meter right / phase right, per rule ---")
        print("  'agree' = share of downbeat taps on the predicted bar-line beat.")
        print("  'ceiling' = share on the taps' OWN modal phase — the best any method could")
        print("  score here. A low ceiling means the taps disagree and the track is not")
        print("  evidence either way; a high ceiling with low agree is our error.\n")
        print(f"  {'track':22s} {'rule':>12s} {'truth':>5s} {'meter':>5s} {'p':>3s} "
              f"{'tap p':>5s} {'agree':>6s} {'ceiling':>7s} {'n':>4s}  verdict")
        phase_tally = {r: [0, 0] for r in RULES}
        for name, truth, outs, scores in phase_rows:
            for rname in RULES:
                if rname not in scores:
                    continue
                frac, mode, ceiling, total = scores[rname]
                meter_ok = truth is not None and outs[rname]["meter"] == truth
                phase_ok = frac >= 0.5
                if truth is None:
                    verdict = f"(no meter truth) phase {'ok' if phase_ok else 'off'}"
                else:
                    verdict = ("meter+phase" if meter_ok and phase_ok else
                               "METER RIGHT, PHASE WRONG" if meter_ok else
                               "phase ok, meter wrong" if phase_ok else "both wrong")
                    if meter_ok:
                        phase_tally[rname][1] += 1
                        phase_tally[rname][0] += int(phase_ok)
                print(f"  {name:22s} {rname:>12s} {str(truth):>5s} "
                      f"{outs[rname]['meter']:>5d} {outs[rname]['phase']:>3d} {mode:>5d} "
                      f"{frac:>6.0%} {ceiling:>7.0%} {total:>4d}  {verdict}")
            print()
        print("  phase correct WHERE METER IS CORRECT: " +
              "  ".join(f"{r} {phase_tally[r][0]}/{phase_tally[r][1]}" for r in RULES))

    for rname in (RULES if args.control else ()):
        control(rname, args.control, 600, real_for_control)

    print("=" * 79 + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

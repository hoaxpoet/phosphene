#!/usr/bin/env python3
"""barline_parity.py — the FT.3 task-4 parity reference for `BarLineEstimator` (Swift).

WHY THIS EXISTS, AND WHY IT IS NOT JUST `barline_combine.py --rule sum_margin`.

FT.3's task-4 gate is that the Swift port reproduces the Python margins "to within 1e-3".
That gate is unachievable against `barline_probe.py` / `barline_combine.py` as written,
for a reason that has nothing to do with the port: their permutation null is a 200-draw
MONTE-CARLO estimate consumed from a single numpy PCG64 stream, in whatever order the
tracks and features happen to be visited. Two runs of the *same Python* with different
seeds disagree by far more than 1e-3 (measured — see `--seed-jitter`). Reproducing that
number in Swift would mean reimplementing PCG64 and numpy's `Generator.shuffle`, and the
result would still be a Monte-Carlo sample rather than a value.

So the null is made DETERMINISTIC on both sides instead: a 15-line SplitMix64 plus
Fisher-Yates, specified here and reimplemented identically in `BarLineEstimator.swift`.
Both languages then compute the *same* null rather than two samples of it, the 1e-3 gate
becomes a real test of the port, and the estimator gains run-to-run determinism, which an
engine component wants anyway.

Everything else — the features, the contrast statistic, the `sum_margin` combination rule
chosen in FT.3 task 3 — is unchanged from `barline_combine.py`.

Usage:
    ~/phosphene-ml-env/bin/python tools/barline_parity.py \\
        --beats-dir /tmp/barprobe --fixtures ~/phosphene_beatbench_fixtures \\
        --out /tmp/barprobe/parity.json
"""

from __future__ import annotations
import argparse, glob, json, os, sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from barline_probe import METERS, N_PERM, beat_features, decode  # noqa: E402

# Fixed order — the null's seed is derived from the feature index, so this is contract.
FEATURES = ("low_energy", "rms", "flux", "harmonic_change")
NULL_SEED = 20_260_731
MASK64 = (1 << 64) - 1


# MARK: - SplitMix64, reimplemented identically in BarLineEstimator.swift

class SplitMix64:
    def __init__(self, seed: int) -> None:
        self.state = seed & MASK64

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        return (z ^ (z >> 31)) & MASK64

    def shuffle(self, values: list[float]) -> None:
        """In-place Fisher-Yates, descending, matching SplitMix64.shuffle in Swift."""
        for i in range(len(values) - 1, 0, -1):
            j = self.next() % (i + 1)
            values[i], values[j] = values[j], values[i]


# MARK: - The statistic (same formula as barline_probe.contrast, all phases at once)

def contrasts(feature: list[float], meter: int) -> list[float]:
    n = len(feature)
    if n <= meter:
        return [0.0] * meter
    sums = [0.0] * meter
    counts = [0.0] * meter
    for index, value in enumerate(feature):
        sums[index % meter] += value
        counts[index % meter] += 1.0
    total = sum(sums)
    mean = total / n
    sd = (sum((v - mean) ** 2 for v in feature) / n) ** 0.5
    if sd < 1e-12:
        return [0.0] * meter
    out = []
    for phase in range(meter):
        on = counts[phase]
        off = n - on
        out.append(0.0 if on < 2 or off < 2
                   else (sums[phase] / on - (total - sums[phase]) / off) / sd)
    return out


def null_max(feature: list[float], meter: int, seed: int, draws: int = N_PERM) -> float:
    rng = SplitMix64(seed)
    shuffled = list(feature)
    accumulated = 0.0
    for _ in range(draws):
        rng.shuffle(shuffled)
        accumulated += max(contrasts(shuffled, meter))
    return accumulated / draws


# MARK: - sum_margin (FT.3 task 3's chosen rule), deterministic null

def estimate(feats: dict[str, np.ndarray]) -> dict:
    margins, phases = {}, {}
    for meter in METERS:
        total = 0.0
        votes = [0.0] * meter
        for index, name in enumerate(FEATURES):
            feature = [float(v) for v in feats[name]]
            observed = contrasts(feature, meter)
            seed = NULL_SEED + index * 1000 + meter
            total += max(observed) - null_max(feature, meter, seed)
            for phase in range(meter):
                votes[phase] += observed[phase]
        margins[meter] = total
        phases[meter] = int(np.argmax(votes))
    winner = max(METERS, key=lambda m: margins[m])
    runner_up = max(margins[m] for m in METERS if m != winner)
    return {"meter": winner, "phase": phases[winner], "margin": margins[winner],
            "gap": margins[winner] - runner_up,
            "margins": {str(m): margins[m] for m in METERS}}


# MARK: - Task 6: the local-path A/B against the incumbent resolver

# `BarLineEstimator.declineThreshold` — keep the two in step.
#
# Derived, not chosen by taste (D-207: "a threshold set from the margin's measured
# distribution"). Labelling a track correct only when BOTH meter and phase are right, the
# objective (correct kept - incorrect admitted) has two equal maxima on the nine
# ground-truthed tracks: (0.106, 0.136] and (0.226, 2.254]. D-207's product call — decline
# when unsure, because a wrong bar-1 fires the accent on an arbitrary beat of every bar —
# breaks the tie toward the interval that admits ZERO confident-wrong answers. 1.24 is that
# interval's midpoint, so it is maximally far from both observed edges.
DECLINE_THRESHOLD = 1.24


def f_measure(reference: list[float], estimate: list[float], tol: float = 0.070) -> float:
    """Greedy one-to-one F-measure at +/-70 ms.

    Ported from `Metrics.fMeasure` in `PhospheneEngine/Sources/BeatBench/Metrics.swift`
    (that target is an executable, so the test bundle cannot import it). One-to-one
    matters: without it a downbeat stream firing twice per reference bar would score full
    recall on both."""
    if not reference or not estimate:
        return 0.0
    used, matched = set(), 0
    for ref in reference:
        best, best_delta = None, tol
        for index, est in enumerate(estimate):
            if index in used:
                continue
            delta = abs(est - ref)
            if delta <= best_delta:
                best, best_delta = index, delta
        if best is not None:
            used.add(best)
            matched += 1
    precision = matched / len(estimate)
    recall = matched / len(reference)
    return 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)


def phase_agreement(beats: list[float], meter: int, phase: int,
                    downbeats: list[float]) -> tuple[float, float, int]:
    """(agree, ceiling, n) — the share of ground-truth downbeat taps landing on the
    predicted bar-line beat, the best share any single global phase could reach, and the
    number of taps scored. Same snapping as `barline_combine.tap_phases`: each tap goes to
    its nearest grid beat, taps further than half a beat period away are dropped.

    The ceiling separates "our phase is wrong" from "no single phase describes this track",
    and only the first is a defect of this method."""
    if not downbeats or len(beats) < 2 or meter < 1:
        return (0.0, 0.0, 0)
    periods = sorted(beats[i + 1] - beats[i] for i in range(len(beats) - 1))
    tol = periods[len(periods) // 2] * 0.5
    hist = [0] * meter
    for tap in downbeats:
        index = min(range(len(beats)), key=lambda i: abs(beats[i] - tap))
        if abs(beats[index] - tap) <= tol:
            hist[index % meter] += 1
    total = sum(hist)
    if total == 0:
        return (0.0, 0.0, 0)
    return (hist[phase] / total, max(hist) / total, total)


def ab_row(name: str, doc: dict, out: dict, truth_dir: str) -> dict | None:
    """One A/B row: incumbent resolver vs BarLineEstimator, on the SAME full-track grid."""
    gt_path = os.path.join(truth_dir, f"{name}.groundtruth.json")
    if not os.path.exists(gt_path):
        return None
    gt = json.load(open(gt_path))
    truth_meter = gt.get("meter_from_taps")
    truth_downbeats = gt.get("downbeats_s") or []
    beats = doc["beats"]

    confident = out["margin"] >= DECLINE_THRESHOLD
    ours_downbeats = ([beats[i] for i in range(len(beats)) if i % out["meter"] == out["phase"]]
                      if confident else [])

    # SPAN TRIM, both sides. `BeatBench.swift` trims only the REFERENCE to the grid's span,
    # which is right when the grid is a 30 s preview and the taps cover more. Here the grid
    # is the whole track and the taps cover PART of it (billie_jean: 34 downbeats over
    # 1.6-69.1 s of a ~294 s track), so an untrimmed estimate is penalised on precision for
    # every bar outside the tapped region — billie_jean scores 0.37 that way with a perfect
    # bar line. Trimming both sides to the tapped span is the symmetric fix; it is the only
    # deviation from the reference metric and it applies identically to both arms.
    if truth_downbeats:
        lo, hi = truth_downbeats[0] - 1.0, truth_downbeats[-1] + 1.0
        in_span = lambda xs: [t for t in xs if lo <= t <= hi]  # noqa: E731
    else:
        in_span = lambda xs: xs  # noqa: E731

    raw_downbeats = [beats[i] for i in range(len(beats)) if i % out["meter"] == out["phase"]]
    incumbent_downbeats = in_span(doc.get("resolver_downbeats") or [])
    agree, ceiling, scored = phase_agreement(beats, out["meter"], out["phase"], truth_downbeats)
    meter_ok = truth_meter is not None and out["meter"] == truth_meter
    return {
        "ours_db_f_raw": f_measure(truth_downbeats, in_span(raw_downbeats)),
        "phase_agree": agree,
        "phase_ceiling": ceiling,
        "phase_n": scored,
        "meter_ok": meter_ok,
        "bar_ok": meter_ok and agree >= 0.5,
        "track": name,
        "truth_meter": truth_meter,
        "incumbent_meter": doc.get("resolver_beats_per_bar"),
        "incumbent_db_f": f_measure(truth_downbeats, incumbent_downbeats),
        "ours_meter": out["meter"] if confident else None,
        "ours_margin": out["margin"],
        "ours_declined": not confident,
        "ours_db_f": f_measure(truth_downbeats, in_span(ours_downbeats)),
        "truth_downbeats": len(truth_downbeats),
    }


def print_sweep(rows: list[dict]) -> None:
    """Threshold sweep over the observed margins. The point is that the operating point is
    visible rather than asserted, including what declining costs: `kept dbF` counts only
    undeclined tracks, `all dbF` charges every decline a 0.00 the way the product would."""
    truthed = [r for r in rows if r["truth_meter"] is not None]
    if not truthed:
        return
    print("\n  --- task 5: decline-threshold sweep (ground-truthed tracks only) ---")
    print("  bar OK = meter AND phase both right. conf-wrong = undeclined but bar wrong —")
    print("  the number D-207 exists to keep at zero.\n")
    print(f"  {'threshold':>9s} {'kept':>5s} {'bar OK':>6s} {'conf-wrong':>10s} "
          f"{'kept dbF':>8s} {'all dbF':>8s}")
    candidates = sorted({0.0} | {round(r["ours_margin"] + 1e-4, 4) for r in truthed}
                        | {DECLINE_THRESHOLD})
    for threshold in candidates:
        kept = [r for r in truthed if r["ours_margin"] >= threshold]
        bar_ok = sum(1 for r in kept if r["bar_ok"])
        wrong = len(kept) - bar_ok
        kept_f = sum(r["ours_db_f_raw"] for r in kept) / len(kept) if kept else 0.0
        all_f = sum(r["ours_db_f_raw"] for r in kept) / len(truthed)
        mark = "  <- operating point" if abs(threshold - DECLINE_THRESHOLD) < 1e-9 else ""
        print(f"  {threshold:>9.3f} {len(kept):>5d} {bar_ok:>6d} {wrong:>10d} "
              f"{kept_f:>8.2f} {all_f:>8.2f}{mark}")


def print_ab(rows: list[dict]) -> None:
    print("\n  --- task 6: local-path A/B, incumbent resolver vs BarLineEstimator ---")
    print("  Both arms read the SAME full-track grid (FT.1 tiler), so this isolates the")
    print("  method change from FT.1's window change. downbeat F is +/-70 ms one-to-one.")
    print("  A declined row contributes downbeat F 0.00 BY CONSTRUCTION (D-207: no bar")
    print("  position is emitted at all) — that is the cost of declining, stated.\n")
    print(f"  {'track':22s} {'truth':>5s} {'inc m':>5s} {'inc dbF':>7s} "
          f"{'our m':>6s} {'margin':>7s} {'our dbF':>7s} {'phase':>6s} {'ceil':>5s}")
    inc_meter = ours_meter = scored = 0
    inc_f = ours_f = 0.0
    declines = 0
    for row in rows:
        our_m = "decl" if row["ours_declined"] else str(row["ours_meter"])
        print(f"  {row['track']:22s} {str(row['truth_meter']):>5s} "
              f"{str(row['incumbent_meter']):>5s} {row['incumbent_db_f']:>7.2f} "
              f"{our_m:>6s} {row['ours_margin']:>7.3f} {row['ours_db_f']:>7.2f} "
              f"{row['phase_agree']:>6.0%} {row['phase_ceiling']:>5.0%}")
        declines += int(row["ours_declined"])
        if row["truth_meter"] is None:
            continue
        scored += 1
        inc_meter += int(row["incumbent_meter"] == row["truth_meter"])
        ours_meter += int(row["ours_meter"] == row["truth_meter"])
        inc_f += row["incumbent_db_f"]
        ours_f += row["ours_db_f"]
    if scored:
        bars = sum(1 for r in rows if r["truth_meter"] is not None and r["bar_ok"]
                   and not r["ours_declined"])
        print(f"\n  meter correct   : incumbent {inc_meter}/{scored}   BarLineEstimator {ours_meter}/{scored}")
        print(f"  BAR correct (meter AND phase, undeclined): BarLineEstimator {bars}/{scored}")
        print(f"  mean downbeat F : incumbent {inc_f / scored:.3f}   BarLineEstimator {ours_f / scored:.3f}")
        answered = [r for r in rows if r["truth_meter"] is not None and not r["ours_declined"]]
        if answered:
            ours_ans = sum(r["ours_db_f"] for r in answered) / len(answered)
            inc_ans = sum(r["incumbent_db_f"] for r in answered) / len(answered)
            print(f"  ... on the {len(answered)} tracks BarLineEstimator ANSWERS: "
                  f"incumbent {inc_ans:.3f}   BarLineEstimator {ours_ans:.3f}")
    print(f"  decline rate    : {declines}/{len(rows)} rows at threshold {DECLINE_THRESHOLD}")


def print_margin_distribution(rows: list[dict]) -> None:
    """Task 5 — the margin distribution and whether correct and incorrect overlap."""
    truthed = [r for r in rows if r["truth_meter"] is not None]
    print("\n  --- task 5: margin distribution and the correct/incorrect overlap ---")
    for label, key in (("METER only", "meter_ok"), ("BAR (meter AND phase)", "bar_ok")):
        correct = sorted(r["ours_margin"] for r in truthed if r[key])
        wrong = sorted(r["ours_margin"] for r in truthed if not r[key])
        print(f"\n  labelling by {label}:")
        print(f"    correct   ({len(correct)}): " + (", ".join(f"{v:+.3f}" for v in correct) or "none"))
        print(f"    incorrect ({len(wrong)}): " + (", ".join(f"{v:+.3f}" for v in wrong) or "none"))
        overlap_report(correct, wrong)
    correct = sorted(r["ours_margin"] for r in truthed if r["bar_ok"])
    wrong = sorted(r["ours_margin"] for r in truthed if not r["bar_ok"])
    print(f"\n  operating point {DECLINE_THRESHOLD} (labelled by BAR): keeps "
          f"{sum(1 for v in correct if v >= DECLINE_THRESHOLD)}/{len(correct)} correct, "
          f"admits {sum(1 for v in wrong if v >= DECLINE_THRESHOLD)}/{len(wrong)} incorrect")


def overlap_report(correct: list[float], wrong: list[float]) -> None:
    if not (correct and wrong):
        return
    if max(wrong) >= min(correct):
        print(f"    OVERLAP: incorrect reaches {max(wrong):+.3f}, correct starts at "
              f"{min(correct):+.3f} — no threshold separates them cleanly.")
    else:
        print(f"    SEPARATED: incorrect tops out at {max(wrong):+.3f}, correct starts at "
              f"{min(correct):+.3f}; any threshold in between works.")


# MARK: - Main

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--beats-dir", required=True)
    ap.add_argument("--fixtures", required=True)
    ap.add_argument("--out", default=None, help="write the per-track margins as JSON")
    ap.add_argument("--ab", action="store_true",
                    help="task 5 + task 6: margin distribution and the A/B vs the incumbent")
    ap.add_argument("--groundtruth",
                    default="PhospheneEngine/Tests/Fixtures/beatbench/groundtruth")
    ap.add_argument("--seed-jitter", type=int, default=0,
                    help="also run the ORIGINAL stochastic null this many times per track, "
                         "to show why a deterministic null was needed for the 1e-3 gate")
    args = ap.parse_args()
    fixtures = os.path.expanduser(args.fixtures)

    print("\n===== FT.3 task 4 — deterministic-null reference for the Swift port =====")
    print("margins are sum_margin (task 3's chosen rule) with a SplitMix64 permutation")
    print("null, byte-identical to BarLineEstimator.swift.\n")
    print(f"  {'track':22s} {'truth':>5s} {'meter':>5s} {'p':>3s} {'margin':>9s} {'gap':>8s}"
          f"   {'m3':>8s} {'m4':>8s} {'m5':>8s} {'m7':>8s}")

    results, ab_rows = {}, []
    for path in sorted(glob.glob(os.path.join(args.beats_dir, "*.beats.json"))):
        doc = json.load(open(path))
        name, truth, beats = doc["track"], doc.get("truth_meter"), doc["beats"]
        audio = None
        for ext in ("wav", "mp3", "m4a", "flac"):
            candidate = os.path.join(fixtures, f"{name}.{ext}")
            if os.path.exists(candidate):
                audio = decode(candidate)
                break
        if audio is None:
            print(f"  {name:22s} fixture missing")
            continue

        feats = beat_features(audio, beats)
        out = estimate(feats)
        out["truth_meter"] = truth
        out["beats"] = len(beats)
        results[name] = out
        marks = "  ".join(f"{out['margins'][str(m)]:8.4f}" for m in METERS)
        flag = "" if truth is None else (" OK" if out["meter"] == truth else " X")
        print(f"  {name:22s} {str(truth):>5s} {out['meter']:>5d} {out['phase']:>3d} "
              f"{out['margin']:9.4f} {out['gap']:8.4f}   {marks}{flag}")

        if args.ab:
            row = ab_row(name, doc, out, args.groundtruth)
            if row:
                row["ours_meter_raw"] = out["meter"]
                ab_rows.append(row)

        if args.seed_jitter:
            jitter(name, feats, args.seed_jitter)

    if ab_rows:
        print_margin_distribution(ab_rows)
        print_sweep(ab_rows)
        print_ab(ab_rows)

    if args.out:
        with open(args.out, "w") as handle:
            json.dump(results, handle, indent=2, sort_keys=True)
        print(f"\n  wrote {args.out}")
    print("=" * 79 + "\n")
    return 0


def jitter(name: str, feats: dict[str, np.ndarray], runs: int) -> None:
    """Run the ORIGINAL Monte-Carlo null `runs` times and report the spread of the winning
    margin. This is the evidence that the 1e-3 parity gate could not have been met against
    a stochastic null, whatever the port did."""
    from barline_probe import contrast  # noqa: PLC0415

    spreads = {}
    for meter in METERS:
        values = []
        for run in range(runs):
            rng = np.random.default_rng(1000 + run)
            total = 0.0
            for name_f in FEATURES:
                feature = np.asarray(feats[name_f], dtype=float)
                observed = max(contrast(feature, meter, p) for p in range(meter))
                shuffled = feature.copy()
                draws = []
                for _ in range(N_PERM):
                    rng.shuffle(shuffled)
                    draws.append(max(contrast(shuffled, meter, p) for p in range(meter)))
                total += observed - float(np.mean(draws))
            values.append(total)
        spreads[meter] = (float(np.mean(values)), float(np.std(values)),
                          float(max(values) - min(values)))
    worst = max(spreads[m][2] for m in METERS)
    detail = "  ".join(f"{m}:sd {spreads[m][1]:.4f} range {spreads[m][2]:.4f}" for m in METERS)
    print(f"     stochastic-null spread over {runs} seeds — {detail}")
    print(f"     worst range {worst:.4f} vs the 1e-3 parity gate "
          f"({worst / 1e-3:.0f}x)\n")


if __name__ == "__main__":
    sys.exit(main())

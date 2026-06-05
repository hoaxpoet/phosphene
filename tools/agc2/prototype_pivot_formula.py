#!/usr/bin/env python3
"""AGC2.3 formula prototype — additive vs scale-free per-band EMA pivot (BUG-027 / D-146).

Replays the logged per-frame band values (`bass`/`mid`/`treble`) from a recorded
session through a per-band EMA (decay = stemEMADecay = 0.9989, seed-from-first-nonzero,
reset per track — mirroring StemAnalyzer) and compares two derivations of the
"above this band's own average" deviation:

  additive    rel = (x - ema) * 2          (literal mirror of the stem path)
  scalefree   rel = x / max(ema, floor) - 1 (relative, uniform range across bands)

For each it reports the firing rate (% active frames with dev > eps) and the
amplitude of the punches (p90 of the positive dev) — the question is which gives
mid/treble a *usable* signal, not just a non-zero one. EXPLORATORY (not production).
"""
import csv
import sys
import os

DECAY = 0.9989
EPS = 1e-4
FLOOR = 0.01  # denominator floor for the scale-free form
BANDS = ["bass", "mid", "treble"]


def fget(r, k):
    try:
        return float(r[k])
    except (KeyError, ValueError, TypeError):
        return None


def p(xs, q):
    if not xs:
        return float("nan")
    s = sorted(xs)
    return s[min(len(s) - 1, int(q * len(s)))]


def run(path, label):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    # Per-track EMA state; reset when track_elapsed_s goes backwards.
    ema = {b: 0.0 for b in BANDS}
    prev_te = None
    last_triple = None
    # accumulators: band -> list of (additive_dev, scalefree_dev, active?)
    acc = {b: {"add": [], "sf": [], "add_fire": 0, "sf_fire": 0, "n": 0} for b in BANDS}
    for r in rows:
        te = fget(r, "track_elapsed_s")
        if te is None:
            continue
        if prev_te is not None and te < prev_te - 0.5:
            ema = {b: 0.0 for b in BANDS}  # track reset
            last_triple = None
        prev_te = te
        vals = {b: fget(r, b) for b in BANDS}
        if any(v is None for v in vals.values()):
            continue
        triple = (vals["bass"], vals["mid"], vals["treble"])
        is_new_analysis = triple != last_triple  # dedup render-rate repeats
        last_triple = triple
        active = te >= 2.0 and (vals["bass"] + vals["mid"] + vals["treble"]) > 0.10
        for b in BANDS:
            x = vals[b]
            if is_new_analysis:  # advance EMA only on a fresh analysis update
                if ema[b] == 0.0 and x > 0:
                    ema[b] = x
                ema[b] = ema[b] * DECAY + x * (1 - DECAY)
            if not active:
                continue
            add_rel = (x - ema[b]) * 2.0
            sf_rel = x / max(ema[b], FLOOR) - 1.0
            add_dev = max(0.0, add_rel)
            sf_dev = max(0.0, sf_rel)
            acc[b]["n"] += 1
            if add_dev > EPS:
                acc[b]["add_fire"] += 1
                acc[b]["add"].append(add_dev)
            if sf_dev > EPS:
                acc[b]["sf_fire"] += 1
                acc[b]["sf"].append(sf_dev)
    print(f"\n=== {label}  ({os.path.basename(path)}) ===")
    print(f"  {'band':7} {'n':>6} | additive: fire  dev_p50  dev_p90 | scalefree: fire  dev_p50  dev_p90")
    for b in BANDS:
        a = acc[b]
        n = max(1, a["n"])
        print(f"  {b:7} {a['n']:>6} | "
              f"{100*a['add_fire']/n:>9.1f}% {p(a['add'],0.5):>7.3f} {p(a['add'],0.9):>7.3f} | "
              f"{100*a['sf_fire']/n:>10.1f}% {p(a['sf'],0.5):>7.3f} {p(a['sf'],0.9):>7.3f}")


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        d, _, lab = arg.partition("=")
        run(os.path.join(d, "features.csv"), lab or os.path.basename(d))

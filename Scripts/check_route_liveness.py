#!/usr/bin/env python3
"""check_route_liveness.py — are a preset's declared audio routes actually carrying
information in a real capture?

    Scripts/check_route_liveness.py <Preset> <capture> [...]
    Scripts/check_route_liveness.py AuroraVeil ~/Documents/phosphene_sessions/<dir>

Why this exists (2026-08-12). BUG-086's `dsp.stem` manual gate was aimed at Aurora
Veil on the strength of a stale note calling `other_energy_dev` its anchor. Git says
that route was dropped at AV.2.h and AV.7 reauthored the preset onto mood envelopes
(D-185), so **Aurora Veil declares no stem route at all** — the M7 could not have
revealed a stem-latency change, and Matt spent a review sitting on it. Worse, of the
five routes it does declare, `pulseAmp01` is pinned at 1.000 with zero range and the
vocals-pitch pair is 0.1 % nonzero, which is most of why the preset reads as
uncoupled.

**Run this before asking anyone to review a preset.** A route with no dynamic range
cannot be seen, so an M7 aimed at it spends a human's attention on a measurement that
was already available from a CSV.

Route liveness is a property of the **audio pipeline**, not of the preset, so any
capture answers it — the preset that was running during the capture does not matter.

Verdicts
--------
  DEAD      range below `DEAD_RANGE` — carries no information at all
  SPARSE    nonzero on under `SPARSE_PCT` % of frames — garnish, not a driver
  NARROW    alive but range under `NARROW_RANGE` — visible only with high gain
  ALIVE     usable dynamic range
  ABSENT    the primitive is not a recorded column (may be CPU-derived; QG.1.1)
"""
import argparse
import csv
import glob
import json
import os
import sys

DEAD_RANGE = 1e-6
NARROW_RANGE = 0.05
SPARSE_PCT = 5.0

# Sidecar primitive name -> recorded CSV column, where they differ.
ALIASES = {
    "barPhase01": "barPhase01_permille",
    "pulseAmp01": "pulse_amp01",
    "pulsePhase01": "pulse_phase01",
    "sectionIndex": "section_index",
    "beatPhase01": "beatPhase01",
}


def load(path):
    with open(path, newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        return header, list(reader)


def series(header, rows, name):
    if name not in header:
        return None
    i = header.index(name)
    out = []
    for row in rows:
        try:
            out.append(float(row[i]))
        except (ValueError, IndexError):
            pass
    return out or None


def sidecar(preset):
    hits = glob.glob(f"PhospheneEngine/Sources/Presets/Shaders/{preset}.json")
    if not hits:
        hits = [p for p in glob.glob("PhospheneEngine/Sources/Presets/Shaders/*.json")
                if os.path.basename(p)[:-5].lower() == preset.lower()]
    if not hits:
        sys.exit(f"no sidecar for '{preset}'")
    return json.load(open(hits[0]))


def pct(values, q):
    s = sorted(values)
    return s[min(len(s) - 1, max(0, int(q * len(s))))]


def classify(v):
    if v is None:
        return "ABSENT", ""
    lo, hi = pct(v, 0.05), pct(v, 0.95)
    rng = hi - lo
    nonzero = 100.0 * sum(1 for x in v if abs(x) > 1e-6) / len(v)
    detail = f"p5 {lo:+8.3f}  p95 {hi:+8.3f}  range {rng:7.3f}  nonzero {nonzero:5.1f}%"
    # DEAD is judged on the p5-p95 range, NOT max-min: `pulseAmp01` sits pinned at
    # 1.000 on 99.9 % of frames with one excursion, and a max-min test let that single
    # frame rescue it from DEAD — mislabelling the exact case this tool exists to catch.
    if rng <= DEAD_RANGE:
        return "DEAD", detail
    if nonzero < SPARSE_PCT:
        return "SPARSE", detail
    if rng < NARROW_RANGE:
        return "NARROW", detail
    return "ALIVE", detail


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("preset")
    ap.add_argument("captures", nargs="+")
    args = ap.parse_args()

    routes = sidecar(args.preset).get("audio_routes") or []
    if isinstance(routes, dict):
        routes = [routes]
    if not routes:
        print(f"{args.preset} declares NO audio_routes.")
        return 2

    worst = 0
    for capture in args.captures:
        fh, fr = load(os.path.join(capture, "features.csv"))
        sh, sr = load(os.path.join(capture, "stems.csv"))
        print(f"\n=== {args.preset} routes in {os.path.basename(os.path.normpath(capture))}")
        print(f"{'route':22s} {'primitive':24s} {'kind':11s} {'verdict':8s} detail")
        seen = set()
        for r in routes:
            prim = str(r.get("primitive"))
            key = (r.get("route"), prim)
            if key in seen:
                continue
            seen.add(key)
            col = ALIASES.get(prim, prim)
            v = series(sh, sr, col) or series(fh, fr, col)
            verdict, detail = classify(v)
            worst = max(worst, {"ALIVE": 0, "ABSENT": 1, "NARROW": 2,
                                "SPARSE": 3, "DEAD": 4}[verdict])
            print(f"{str(r.get('route'))[:22]:22s} {prim[:24]:24s} "
                  f"{str(r.get('kind'))[:11]:11s} {verdict:8s} {detail}")
        print("\n  DEAD/SPARSE routes cannot be seen — do not aim a manual review at them.")
    return 1 if worst >= 3 else 0


if __name__ == "__main__":
    sys.exit(main())

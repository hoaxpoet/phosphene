#!/usr/bin/env python3
"""FBS Stage 0 (companion) — grid-vs-onset alignment from features.csv alone.

PCM-free coverage for EVERY track in a session (raw_tap.wav only covers the
first one). Measures whether the engine's own raw onset novelty (`spectralFlux`,
computed from the FFT — independent of the grid) is concentrated at a consistent
point of the grid's own beat-phase clock (`beatPhase01`):

  - phase = beatPhase01 (where in the beat the grid thinks we are, 0..1)
  - weight = spectralFlux (how much of an onset is happening)
  - R = |circular mean| in [0,1]: high => onsets land at a CONSISTENT grid
        phase (grid is phase-coherent with the music); low => onsets are spread
        across the whole beat cycle (grid phase wrong or wandering).
  - offset = where in the beat the onsets pile up (ms). ~0 => the grid's beat
        lands on the music's beat; nonzero => off by a constant.

Because beatPhase01 is the grid's OWN warped clock, this has no long-window
tempo-slip problem (unlike a fixed-period fold). Reported over an EARLY window
(drift~0, ~= the cached grid as installed) and the FULL track (the live,
drift-corrected phase the preset actually sees).

Pure stdlib. Diagnostic artifact for the FBS work.

Usage: python3 grid_phase_csv.py <session_dir> [--early-hi 11]
"""
import argparse
import csv
import math
import os


def fget(r, k):
    try:
        return float(r[k])
    except (KeyError, ValueError, TypeError):
        return None


def segments(rows):
    segs, cur, prev = [], [], None
    for r in rows:
        te = fget(r, "track_elapsed_s")
        if te is None:
            cur.append(r)
            continue
        if prev is not None and te < prev - 0.5:
            if cur:
                segs.append(cur)
            cur = []
        cur.append(r)
        prev = te
    if cur:
        segs.append(cur)
    return segs


def phase_lock_csv(seg, lo, hi):
    """Circular lock of spectralFlux weight against beatPhase01 over [lo,hi] s."""
    C = S = W = 0.0
    bpm = None
    twopi = 2.0 * math.pi
    for r in seg:
        te = fget(r, "track_elapsed_s")
        if te is None or te < lo or te > hi:
            continue
        ph = fget(r, "beatPhase01")
        w = fget(r, "spectralFlux")
        if ph is None or w is None or w <= 0:
            continue
        if bpm is None:
            bpm = fget(r, "grid_bpm")
        ang = twopi * ph
        C += w * math.cos(ang)
        S += w * math.sin(ang)
        W += w
    if W <= 0:
        return 0.0, float("nan"), bpm, 0
    R = math.hypot(C, S) / W
    off_turn = math.atan2(S, C) / twopi
    if off_turn > 0.5:
        off_turn -= 1.0
    period_ms = (60.0 / bpm * 1000.0) if bpm else float("nan")
    off_ms = off_turn * period_ms
    n = sum(1 for r in seg if (fget(r, "track_elapsed_s") or -1) >= lo
            and (fget(r, "track_elapsed_s") or 1e9) <= hi)
    return R, off_ms, bpm, n


def drift_at(seg, ts):
    cand = [fget(r, "drift_ms") for r in seg
            if fget(r, "track_elapsed_s") is not None
            and abs(fget(r, "track_elapsed_s") - ts) < 1.0
            and fget(r, "drift_ms") is not None]
    return cand[len(cand) // 2] if cand else None


def lock_word(r):
    return "STRONG" if r >= 0.35 else ("moderate" if r >= 0.22 else ("weak" if r >= 0.14 else "none"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session_dir")
    ap.add_argument("--early-hi", type=float, default=11.0, help="early window = [1, early-hi] s")
    a = ap.parse_args()
    rows = list(csv.DictReader(open(os.path.join(a.session_dir, "features.csv"), newline="")))
    segs = segments(rows)
    print(f"\nfeatures-proxy grid alignment  ({os.path.basename(os.path.normpath(a.session_dir))}, "
          f"{len(segs)} tracks)  — spectralFlux vs beatPhase01")
    print(f"  early window = [1,{a.early_hi:.0f}]s (≈ cached grid as installed); full = whole track")
    print(f"  {'#':>2} {'bpm':>6} {'len_s':>6} {'meanFlux':>8} | "
          f"{'EARLY R':>7} {'off_ms':>7} {'lock':>8} | {'FULL R':>6} {'off_ms':>7} {'lock':>8} | "
          f"{'drift0→10→end':>16}")
    for i, seg in enumerate(segs):
        te = [fget(r, "track_elapsed_s") for r in seg if fget(r, "track_elapsed_s") is not None]
        length = (te[-1] - te[0]) if te else 0.0
        flux = [fget(r, "spectralFlux") or 0 for r in seg]
        meanflux = sum(flux) / len(flux) if flux else 0.0
        eR, eoff, bpm, _en = phase_lock_csv(seg, 1.0, a.early_hi)
        fR, foff, _b, _fn = phase_lock_csv(seg, 1.0, te[-1] if te else 0.0)
        d0, d10, dend = drift_at(seg, 0.5), drift_at(seg, 10.0), (drift_at(seg, te[-1] - 1) if te else None)

        def fmt(x, s="%+.0f"):
            return (s % x) if x is not None and x == x else "  n/a"
        print(f"  {i:>2} {(bpm or 0):>6.1f} {length:>6.1f} {meanflux:>8.3f} | "
              f"{eR:>7.2f} {fmt(eoff):>7} {lock_word(eR):>8} | {fR:>6.2f} {fmt(foff):>7} {lock_word(fR):>8} | "
              f"{fmt(d0):>5}{fmt(d10):>6}{fmt(dend):>6}")
    print("  (lock thresholds: STRONG≥0.35 moderate≥0.22 weak≥0.14 — real music rarely exceeds ~0.35;")
    print("   a phase-coherent grid shows a clear nonzero R with a STABLE offset early-vs-full.)")


if __name__ == "__main__":
    main()

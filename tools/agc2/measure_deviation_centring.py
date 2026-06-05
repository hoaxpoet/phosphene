#!/usr/bin/env python3
"""AGC2.1 — Measure deviation-primitive centring across recorded sessions (BUG-027).

Reads a session's `features.csv` + `stems.csv` (the values production actually
shipped that frame — no re-derivation from FFT) and reports, per capture path:

  Manifestation A (FeatureVector bands, MIRPipeline.swift:334-339 fixed-0.5 pivot):
    - per-band AGC centre (p50/mean) for bass/mid/treble and the 6 bands
    - `*Dev` firing rate  = % active frames where (x-0.5)*2 > eps  (i.e. x > 0.5)
    - signed `*Rel` stddev = stddev of (x-0.5)*2

  Manifestation B (StemFeatures, StemAnalyzer.swift:221-247):
    - raw `{stem}Energy` centre (p50/mean)  -- the value consumers read directly
    - `{stem}EnergyDev` firing rate (logged) -- per-stem-EMA path, may self-centre
    - `{stem}EnergyRel` mean + stddev (logged) -- to confirm the EMA self-centres ~0

Frame selection: per track (segmented by `track_elapsed_s` reset), drop the first
`--skip-s` seconds (the BUG-025 cold-start AGC transient), then keep only "active"
frames where bass+mid+treble exceeds `--active-floor` (excludes silence/prep, which
would otherwise deflate firing rates artificially). Both the active-only and
all-post-coldstart figures are reported so the filtering is transparent.

Pure Python stdlib (no numpy/pandas). Permanent diagnostic artifact for BUG-027.

Usage:
    python3 measure_deviation_centring.py <session_dir> [--label LF|Spotify]
            [--skip-s 2.0] [--active-floor 0.10] [--eps 1e-4] [--per-track]
"""
import argparse
import csv
import math
import os
import sys

BANDS3 = ["bass", "mid", "treble"]
BANDS6 = ["subBass", "lowBass", "lowMid", "midHigh", "highMid", "high"]
STEMS = ["vocals", "drums", "bass", "other"]


def fget(row, key):
    try:
        return float(row[key])
    except (KeyError, ValueError, TypeError):
        return None


def median(xs):
    if not xs:
        return float("nan")
    s = sorted(xs)
    n = len(s)
    m = n // 2
    return s[m] if n % 2 else 0.5 * (s[m - 1] + s[m])


def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def stdev(xs):
    if len(xs) < 2:
        return float("nan")
    mu = mean(xs)
    return math.sqrt(sum((x - mu) ** 2 for x in xs) / (len(xs) - 1))


def load_csv(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def segment_tracks(rows):
    """Split feature rows into per-track segments on a track_elapsed_s reset."""
    segs, cur, prev = [], [], None
    for r in rows:
        te = fget(r, "track_elapsed_s")
        if te is None:
            cur.append(r)
            continue
        if prev is not None and te < prev - 0.5:  # elapsed went backwards => new track
            if cur:
                segs.append(cur)
            cur = []
        cur.append(r)
        prev = te
    if cur:
        segs.append(cur)
    return segs


def active_frames(feat_rows, skip_s, active_floor):
    """Frames past the cold-start window AND with audible energy. Returns the rows
    plus the set of `frame` indices (to filter stems.csv by alignment)."""
    kept, frame_ids, post_cs = [], set(), 0
    for seg in segment_tracks(feat_rows):
        for r in seg:
            te = fget(r, "track_elapsed_s")
            if te is None or te < skip_s:
                continue
            post_cs += 1
            b, m, t = fget(r, "bass"), fget(r, "mid"), fget(r, "treble")
            if None in (b, m, t):
                continue
            if (b + m + t) <= active_floor:
                continue
            kept.append(r)
            fid = r.get("frame")
            if fid is not None:
                frame_ids.add(fid)
    return kept, frame_ids, post_cs


def band_row(rows, band, eps):
    vals = [v for v in (fget(r, band) for r in rows) if v is not None]
    if not vals:
        return None
    rel = [(v - 0.5) * 2.0 for v in vals]
    dev_fire = sum(1 for x in rel if x > eps) / len(vals)
    return {
        "n": len(vals),
        "p50": median(vals),
        "mean": mean(vals),
        "rel_mean": mean(rel),
        "rel_std": stdev(rel),
        "dev_fire": dev_fire,
    }


def stem_row(stem_rows, stem, eps):
    e = [v for v in (fget(r, stem + "Energy") for r in stem_rows) if v is not None]
    rel = [v for v in (fget(r, stem + "EnergyRel") for r in stem_rows) if v is not None]
    dev = [v for v in (fget(r, stem + "EnergyDev") for r in stem_rows) if v is not None]
    if not e:
        return None
    return {
        "n": len(e),
        "energy_p50": median(e),
        "energy_mean": mean(e),
        "rel_mean": mean(rel) if rel else float("nan"),
        "rel_std": stdev(rel) if rel else float("nan"),
        "dev_fire": (sum(1 for x in dev if x > eps) / len(dev)) if dev else float("nan"),
    }


def report(session_dir, label, skip_s, active_floor, eps, per_track):
    feat = load_csv(os.path.join(session_dir, "features.csv"))
    stems = load_csv(os.path.join(session_dir, "stems.csv"))
    name = os.path.basename(os.path.normpath(session_dir))
    print(f"\n{'='*78}\nSESSION {name}   path={label}   "
          f"skip={skip_s}s  active_floor={active_floor}  eps={eps}")
    if not feat:
        print("  (no features.csv)")
        return
    segs = segment_tracks(feat)
    print(f"  features frames={len(feat)}  tracks={len(segs)}  stems frames={len(stems)}")

    kept, frame_ids, post_cs = active_frames(feat, skip_s, active_floor)
    print(f"  post-cold-start frames={post_cs}  active frames={len(kept)} "
          f"({100*len(kept)/max(1,post_cs):.0f}% of post-CS)")

    print("\n  --- Manifestation A: FeatureVector bands (fixed-0.5 pivot) ---")
    print(f"  {'band':8} {'n':>6} {'p50':>7} {'mean':>7} "
          f"{'relMean':>8} {'relStd':>7} {'Dev fires':>10}")
    for band in BANDS3 + BANDS6:
        s = band_row(kept, band, eps)
        if s:
            print(f"  {band:8} {s['n']:>6} {s['p50']:>7.3f} {s['mean']:>7.3f} "
                  f"{s['rel_mean']:>8.3f} {s['rel_std']:>7.3f} {100*s['dev_fire']:>9.1f}%")

    if stems:
        # Filter stems by the active feature frames (align on `frame` index).
        stem_kept = [r for r in stems if r.get("frame") in frame_ids] if frame_ids else []
        if not stem_kept:  # fall back: no frame alignment -> use all stems
            stem_kept = stems
            print("\n  (note: stems not frame-aligned to active mask; using all stem frames)")
        print("\n  --- Manifestation B: StemFeatures (raw energy + per-stem-EMA dev) ---")
        print(f"  {'stem':8} {'n':>6} {'E p50':>7} {'E mean':>7} "
              f"{'relMean':>8} {'relStd':>7} {'Dev fires':>10}")
        for stem in STEMS:
            s = stem_row(stem_kept, stem, eps)
            if s:
                print(f"  {stem:8} {s['n']:>6} {s['energy_p50']:>7.3f} {s['energy_mean']:>7.3f} "
                      f"{s['rel_mean']:>8.3f} {s['rel_std']:>7.3f} {100*s['dev_fire']:>9.1f}%")

    if per_track and len(segs) > 1:
        print("\n  --- Per-track (active frames; bass/mid/treble Dev fire %) ---")
        for i, seg in enumerate(segs):
            sk, _, _ = active_frames(seg, skip_s, active_floor)
            if not sk:
                continue
            te_max = max((fget(r, "track_elapsed_s") or 0) for r in seg)
            cells = []
            for band in BANDS3:
                s = band_row(sk, band, eps)
                cells.append(f"{band}={s['p50']:.2f}/{100*s['dev_fire']:.0f}%" if s else f"{band}=-")
            print(f"  track {i+1:2} (~{te_max:5.0f}s, n={len(sk):5}): " + "  ".join(cells))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session_dir")
    ap.add_argument("--label", default="?")
    ap.add_argument("--skip-s", type=float, default=2.0)
    ap.add_argument("--active-floor", type=float, default=0.10)
    ap.add_argument("--eps", type=float, default=1e-4)
    ap.add_argument("--per-track", action="store_true")
    a = ap.parse_args()
    report(a.session_dir, a.label, a.skip_s, a.active_floor, a.eps, a.per_track)


if __name__ == "__main__":
    main()

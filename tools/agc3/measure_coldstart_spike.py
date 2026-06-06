#!/usr/bin/env python3
"""AGC3.1 — Measure the AGC `f.bass` cold-start band-value spike (BUG-029).

Reads a session's `features.csv` (the AGC-normalised band values production
actually shipped each frame — no re-derivation from FFT) and characterises, per
track onset, the cold-start spike in the FeatureVector bands.

Mechanism under test (`BandEnergyProcessor.process`):
  - `agcScale = 0.5 / agcRunningAvg`, applied to every band.
  - `agcRunningAvg` is an EMA of total 6-band energy; it is NOT reset per track
    (MIRPipeline.reset() is never called per track). During an inter-track
    silence `totalRawEnergy ~ 0`, so the running average DECAYS toward 0; the
    first audible frame of the next track is then divided by a too-small
    denominator -> the bands explode for a frame or two until the EMA catches up.
  - At session start (frame 0) the seed `max(totalRawEnergy, 1e-6)` off leading
    silence is the worst case (seed ~ 1e-6 -> enormous scale).

What it reports, per track segment (segmented on a `track_elapsed_s` reset):
  - silent pre-roll length (leading frames below `--silence-floor`)
  - onset `track_elapsed_s` (first audible frame)
  - PEAK `f.bass` (+ the 6 bands) inside `--onset-window` s of the onset
  - STEADY `f.bass` (median of active frames in [`--steady-lo`, `--steady-hi`] s)
  - spike RATIO (peak / steady)
  - spike DURATION (consecutive frames from onset with bass > ratio_mult x steady)
  - downstream `fo_spike_strength = 1.0 + 0.8*clamp(f.bass,0,1)` at peak vs steady
    (Ferrofluid Ocean's `f.bass` consumer; the small `cached_bass_proportion`
     baseline term, <= +0.25 and ~constant, is omitted to match the filed evidence)

It also (a) classifies each onset as session-start (frame-0 seed) vs later
(inter-track-silence decay), (b) correlates spike magnitude with pre-roll length
to confirm/refute the "every track onset" claim, and (c) optionally checks the
per-stem path (`stems.csv` `bassEnergy`), which uses BandEnergyProcessor too but
IS reset per track (StemAnalyzer.reset) so should not spike.

Pure Python stdlib. Permanent diagnostic artifact for BUG-029 / AGC3.

Usage:
    python3 measure_coldstart_spike.py <session_dir> [--label LF|Spotify]
        [--silence-floor 0.02] [--onset-window 3.0] [--steady-lo 10] [--steady-hi 40]
        [--ratio-mult 1.5] [--active-floor 0.10] [--stems]
"""
import argparse
import csv
import os

BANDS6 = ["subBass", "lowBass", "lowMid", "midHigh", "highMid", "high"]


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


def load_csv(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def segment_tracks(rows):
    """Split feature rows into per-track segments on a `track_elapsed_s` reset.

    Returns a list of (start_index, segment_rows). Mirrors the AGC2 harness.
    """
    segs, cur, prev, start = [], [], None, 0
    for i, r in enumerate(rows):
        te = fget(r, "track_elapsed_s")
        if te is None:
            cur.append(r)
            continue
        if prev is not None and te < prev - 0.5:  # elapsed went backwards => new track
            if cur:
                segs.append((start, cur))
            cur, start = [], i
        cur.append(r)
        prev = te
    if cur:
        segs.append((start, cur))
    return segs


def fo_spike_strength(bass):
    """Ferrofluid Ocean's `f.bass` term: 1.0 + 0.8*clamp(f.bass,0,1)."""
    return 1.0 + 0.8 * min(max(bass, 0.0), 1.0)


def analyse_track(seg, args):
    """Characterise the cold-start spike for one track segment."""
    floor = args.silence_floor

    def energy(r):
        b, m, t = fget(r, "bass"), fget(r, "mid"), fget(r, "treble")
        return (b or 0) + (m or 0) + (t or 0)

    # Silent pre-roll: leading frames below the silence floor.
    pre = 0
    for r in seg:
        if energy(r) < floor:
            pre += 1
        else:
            break
    if pre >= len(seg):
        return None  # silent track segment
    onset = seg[pre]
    onset_te = fget(onset, "track_elapsed_s")
    # Pre-roll wall-clock span (use `time` deltas, robust to variable analysis fps).
    t0 = fget(seg[0], "time")
    tons = fget(onset, "time")
    preroll_s = (tons - t0) if (t0 is not None and tons is not None) else float("nan")

    # Peak f.bass within the onset window.
    win = [r for r in seg if (fget(r, "track_elapsed_s") or 0) < (onset_te + args.onset_window)]
    pk = max(win, key=lambda r: fget(r, "bass") or 0)
    peak_bass = fget(pk, "bass")
    peak_te = fget(pk, "track_elapsed_s")
    peak_bands = {b: fget(pk, b) for b in BANDS6}

    # Steady f.bass: median of active frames in the steady window.
    steady_vals = [
        fget(r, "bass") for r in seg
        if args.steady_lo < (fget(r, "track_elapsed_s") or 0) < args.steady_hi
        and energy(r) > args.active_floor
    ]
    steady = median([v for v in steady_vals if v is not None])
    ratio = (peak_bass / steady) if (steady and steady == steady) else float("nan")

    # Spike duration: consecutive frames *from the onset frame* with bass above
    # ratio_mult x steady. (Start at the onset, not seg[0] — the leading pre-roll
    # frames are silent and would break the run immediately.)
    thresh = args.ratio_mult * steady if steady == steady else float("inf")
    from_onset = [r for r in seg
                  if onset_te <= (fget(r, "track_elapsed_s") or -1) < onset_te + args.onset_window]
    dur_frames, dur_end_te = 0, onset_te
    for r in from_onset:
        b = fget(r, "bass") or 0
        if b > thresh:
            dur_frames += 1
            dur_end_te = fget(r, "track_elapsed_s")
        else:
            break
    spike_s = (dur_end_te - onset_te) if dur_frames else 0.0

    return {
        "pre_frames": pre,
        "preroll_s": preroll_s,
        "onset_te": onset_te,
        "peak_bass": peak_bass,
        "peak_te": peak_te,
        "peak_bands": peak_bands,
        "steady": steady,
        "ratio": ratio,
        "spike_frames": dur_frames,
        "spike_s": spike_s,
        "fo_peak": fo_spike_strength(peak_bass),
        "fo_steady": fo_spike_strength(steady),
    }


def stem_onset(seg, stem_by_frame, args):
    """Peak vs steady per-stem `bassEnergy` for one feature segment (frame-aligned)."""
    def be(r):
        s = stem_by_frame.get(r.get("frame"))
        return fget(s, "bassEnergy") if s else None

    onset_te = None
    for r in seg:
        b, m, t = fget(r, "bass"), fget(r, "mid"), fget(r, "treble")
        if (b or 0) + (m or 0) + (t or 0) >= args.silence_floor:
            onset_te = fget(r, "track_elapsed_s")
            break
    if onset_te is None:
        return None
    win = [r for r in seg if (fget(r, "track_elapsed_s") or 0) < (onset_te + args.onset_window)]
    peaks = [be(r) for r in win if be(r) is not None]
    steady = [
        be(r) for r in seg
        if args.steady_lo < (fget(r, "track_elapsed_s") or 0) < args.steady_hi and be(r) is not None
    ]
    if not peaks or not steady:
        return None
    pk, st = max(peaks), median(steady)
    return {"peak": pk, "steady": st, "ratio": pk / st if st else float("nan")}


def report(session_dir, args):
    feat = load_csv(os.path.join(session_dir, "features.csv"))
    name = os.path.basename(os.path.normpath(session_dir))
    print(f"\n{'='*92}\nSESSION {name}   path={args.label}")
    if not feat:
        print("  (no features.csv)")
        return
    segs = segment_tracks(feat)
    print(f"  features frames={len(feat)}   track segments={len(segs)}   "
          f"silence_floor={args.silence_floor}  onset_window={args.onset_window}s  "
          f"steady=[{args.steady_lo},{args.steady_hi}]s")

    print("\n  --- FeatureVector `f.bass` cold-start spike, per track onset ---")
    print(f"  {'trk':>3} {'mode':>13} {'preRoll_s':>9} {'onsetTE':>7} "
          f"{'peakBass':>8} {'steady':>7} {'ratio':>6} {'spike_s':>7} "
          f"{'fo_peak':>7} {'fo_steady':>9}")
    rows_for_corr = []
    for i, (_, seg) in enumerate(segs):
        a = analyse_track(seg, args)
        if a is None:
            print(f"  {i+1:>3}  (silent / no onset)")
            continue
        mode = "session-start" if i == 0 else "inter-track"
        print(f"  {i+1:>3} {mode:>13} {a['preroll_s']:>9.2f} {a['onset_te']:>7.2f} "
              f"{a['peak_bass']:>8.3f} {a['steady']:>7.3f} {a['ratio']:>6.1f} {a['spike_s']:>7.2f} "
              f"{a['fo_peak']:>7.3f} {a['fo_steady']:>9.3f}")
        rows_for_corr.append((i + 1, mode, a))

    # Per-band breakdown at the peak frame (shows the spike is a global scale, all bands together).
    print("\n  --- 6-band values at the spike-peak frame (global AGC scale inflates all bands) ---")
    print(f"  {'trk':>3} " + " ".join(f"{b:>8}" for b in BANDS6))
    for tno, _, a in rows_for_corr:
        print(f"  {tno:>3} " + " ".join(f"{(a['peak_bands'][b] or 0):>8.3f}" for b in BANDS6))

    # Correlation: spike ratio vs pre-roll length (the "every track onset" question).
    print("\n  --- Spike magnitude vs silent pre-roll length ---")
    for tno, mode, a in rows_for_corr:
        verdict = "SPIKE" if a["ratio"] >= 3.0 else ("mild" if a["ratio"] >= 1.8 else "none")
        print(f"  track {tno} ({mode:>13}): pre-roll {a['preroll_s']:>5.2f}s  "
              f"-> ratio {a['ratio']:>5.1f}x  [{verdict}]")

    # Stem path (uses BandEnergyProcessor too, but IS reset per track).
    if args.stems:
        stems = load_csv(os.path.join(session_dir, "stems.csv"))
        if stems:
            sby = {r.get("frame"): r for r in stems}
            print("\n  --- Per-stem `bassEnergy` at onset (reset per track => expect NO spike) ---")
            print(f"  {'trk':>3} {'peak':>7} {'steady':>7} {'ratio':>6}")
            for i, (_, seg) in enumerate(segs):
                s = stem_onset(seg, sby, args)
                if s:
                    print(f"  {i+1:>3} {s['peak']:>7.3f} {s['steady']:>7.3f} {s['ratio']:>6.1f}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("session_dir")
    ap.add_argument("--label", default="?")
    ap.add_argument("--silence-floor", type=float, default=0.02,
                    help="bass+mid+treble below this counts as silence (pre-roll detection)")
    ap.add_argument("--onset-window", type=float, default=3.0, help="seconds after onset to search for the peak")
    ap.add_argument("--steady-lo", type=float, default=10.0, help="steady-window start (track_elapsed_s)")
    ap.add_argument("--steady-hi", type=float, default=40.0, help="steady-window end (track_elapsed_s)")
    ap.add_argument("--ratio-mult", type=float, default=1.5, help="spike-duration threshold = this x steady")
    ap.add_argument("--active-floor", type=float, default=0.10, help="bass+mid+treble floor for steady-window frames")
    ap.add_argument("--stems", action="store_true", help="also check the per-stem bassEnergy path")
    a = ap.parse_args()
    report(a.session_dir, a)


if __name__ == "__main__":
    main()

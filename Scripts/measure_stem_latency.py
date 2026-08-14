#!/usr/bin/env python3
"""measure_stem_latency.py — BUG-086 validation: how far behind the audio are
the per-stem features, measured on a real session capture?

    Scripts/measure_stem_latency.py ~/Documents/phosphene_sessions/<capture>

BUG-086 (2026-08-11): per-stem features reached presets ≈5.4 s late while the
real-time band features beside them were correct to ≈0.3 s. BUG086.1 dropped the
separation period 5 s → 2 s and derived the read offset from it, taking nominal
latency to 2.5 s. `StemSeparationCadenceRegressionTests` gates the arithmetic
that produces that number; **this script measures what the pipeline actually
delivered**, which is a different claim and the one that matters.

Why a script and not a unit test — correcting the plan
------------------------------------------------------
BUG-086's verification criteria called for "an automated gate" on measured lag.
Building it showed that form to be wrong: the lag is a *live-pipeline* property
of the ML timer's cadence, wallclock advance and `MLDispatchScheduler` deferral
(D-059). No unit test can synthesize it — and a synthetic one would be exactly
the "green test measuring the wrong thing" trap the constants test already risks
on its own. So the honest artifact is a measurement over a real capture, and the
capture is the input a human has to supply.

Method
------
Cross-correlates each stem's `energyRel` (from `stems.csv`) against a
time-aligned reference built from `features.csv`'s `bass + mid` bands, both
recorded at ~60 Hz, and reports the lag maximising correlation.

Deliberately CSV-only — no WAV. The tap file is optional, is truncated to 30 s
on most captures, and carries a per-capture sample rate (44.1 kHz on some,
48 kHz on others; assuming the wrong one scales the time axis by 8.8 % and
manufactures a plausible fake lag, which is a mistake this measurement made once
before being corrected).

What is and is not controlled for
---------------------------------
This measures the **relative** lag between two columns written on the same frame
clock, so any global offset between the capture and the outside world cancels and
does not need controlling for. There is deliberately no "alignment control": a
first version compared `treble` against `bass+mid` as one, which is not a control
at all but a *musical* comparison — the two registers genuinely decorrelate (that
is a measured property, r ≈ 0), so its peak lag is noise, and it raised false
"capture is suspect" alarms on 7 of 15 good segments. A check that fires on
healthy data is worse than no check.

What IS guarded is estimate strength: a lag read off a weak correlation is not a
measurement, so segments whose best r falls below `MIN_R` are reported
inconclusive rather than given a number.

Capture scale — this tool needs a LONG capture
----------------------------------------------
`MIN_R` was 0.40 and that was too permissive. Measured across the corpus, the
correlation this method achieves is a property of the *capture*, not of the fix:

    beat-match-test-session   88 min, 16 tracks   r 0.70-0.94   sharp unimodal peak
    single-track captures     1-4 min             r 0.19-0.48   flat, no peak

Both regimes appear in PRE-fix captures, so the weakness is not caused by anything
BUG086.1 changed. At 0.40 a 76 s capture returned "PASS 2.9 s" off r 0.42/0.48 —
a number with no peak behind it, reported as validation. That was a false pass and
the floor is 0.60 now.

**A trustworthy before/after needs a BeatBench-scale capture on the fixed build** —
ideally the same 16-track corpus that produced the pre-fix 5.4 s, so the comparison
is like-for-like on identical material. Short captures are below the resolution of
this measurement; the tool now says so instead of guessing.

Why 3.5 and not 3.0
-------------------
The ceiling was 3.0 s, set from BUG086.1's "2.5 s nominal" plus slack. That nominal
was wrong, and the streaming capture `2026-08-12T19-06-54Z` proved it:

    latency = (chunkSeconds - stemReadStartSeconds) + inference

`latestSeparationTimestamp` is stamped AFTER separation returns, so the chunk's newest
sample is already one inference old when the read window starts walking it. Predicted
2.50 + 0.531 = 3.03 s; measured 3.0 s. Inference was assumed to be a duty cost only and
is also a latency cost.

So ~3.0 s is the architectural floor at a 2 s period, not a number to tune toward, and a
3.0 s ceiling sits exactly on it — it fails a working pipeline. 3.5 s accommodates measured
p90 inference (868 ms → 3.37 s) while still failing the pre-fix 5.4 s decisively, which is
the regression this gate exists to catch. **This is not floor-tuning (QG.1 / D-179): the
gate was mis-set against a wrong model, and the model is what changed.**
"""
import argparse
import csv
import math
import os
import re
import sys

FPS = 59.9
STEMS = ["drums", "bass", "vocals", "other"]
MAX_LAG_S = 15.0
LAG_STEP_FRAMES = 6
WIN_MIN_FRAMES = 3600          # ≥60 s of track; shorter segments are too noisy
EMA_S = 8.0
TARGET_S = 3.5                 # see "Why 3.5 and not 3.0" below
MIN_R = 0.60                   # see "Capture scale" below — 0.40 handed out a false PASS
MIN_TRACK_S = 240.0            # single short tracks are below this tool's resolution


def load(path):
    with open(path, newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        return {name: i for i, name in enumerate(header)}, list(reader)


def column(index, rows, name, lo, hi):
    if name not in index:
        return None
    i = index[name]
    out = []
    for row in rows[lo:hi]:
        try:
            out.append(float(row[i]))
        except (ValueError, IndexError):
            out.append(0.0)
    return out


def centre(values, tau_s=EMA_S):
    """Subtract a rolling EMA — the deviation move D-026 makes for stems, applied
    to the AGC-normalised bands so the statistic measures music and not the AGC's
    own denominator (FA #31)."""
    alpha = 1.0 - math.exp(-1.0 / (tau_s * FPS))
    mean = values[0] if values else 0.0
    out = []
    for value in values:
        mean += alpha * (value - mean)
        out.append(value - mean)
    return out


def pearson(a, b):
    n = min(len(a), len(b))
    if n < 120:
        return float("nan")
    mean_a, mean_b = sum(a[:n]) / n, sum(b[:n]) / n
    var_a = sum((x - mean_a) ** 2 for x in a[:n])
    var_b = sum((x - mean_b) ** 2 for x in b[:n])
    if var_a <= 1e-12 or var_b <= 1e-12:
        return float("nan")
    cov = sum((a[i] - mean_a) * (b[i] - mean_b) for i in range(n))
    return cov / math.sqrt(var_a * var_b)


def best_lag(reference, signal, max_lag_frames):
    """Peak-correlation lag in frames. Positive = `signal` trails `reference`."""
    usable = len(reference) - max_lag_frames
    if usable < WIN_MIN_FRAMES // 2:
        return None
    best = (-2.0, 0)
    for lag in range(0, max_lag_frames, LAG_STEP_FRAMES):
        r = pearson(reference[:usable], signal[lag:usable + lag])
        if r == r and r > best[0]:
            best = (r, lag)
    return best


def track_segments(elapsed):
    bounds = [0]
    for i in range(1, len(elapsed)):
        if elapsed[i] < elapsed[i - 1] - 1.0:
            bounds.append(i)
    bounds.append(len(elapsed))
    return [(bounds[k], bounds[k + 1]) for k in range(len(bounds) - 1)]


def track_names(capture):
    """Playback order from the log.

    The pattern is greedy and anchored on ` duration=`, NOT `[^']*`. A title
    containing an apostrophe — `Stayin' Alive - From "Saturday Night Fever"
    Soundtrack` — makes `[^']*` stop mid-title, the whole match fail, and the track
    vanish from this list. Because the list is index-aligned to segments, one
    dropped name **shifts every label after it**: on capture
    `2026-08-12T19-06-54Z` that silently reported Stayin' Alive's numbers under the
    name "Superstition". Labels being wrong is worse than labels being missing.
    """
    path = os.path.join(capture, "session.log")
    if not os.path.exists(path):
        return []
    pattern = re.compile(r"loadForPlayback track='(.*)' artist='(.*)' duration=")
    names = []
    with open(path, errors="replace") as handle:
        for line in handle:
            match = pattern.search(line)
            if match:
                names.append(match.group(1))
    return names


def reported_cadence(capture):
    """The STEM_SEPARATION line BUG086.1 added. Absent → the capture predates the
    fix, which is the single most likely reason a run shows ~5.4 s."""
    path = os.path.join(capture, "session.log")
    if not os.path.exists(path):
        return None
    pattern = re.compile(
        r"STEM_SEPARATION: inference=([\d.]+)ms period=([\d.]+)s duty=([\d.]+)%"
        r" nominal_latency=([\d.]+)s")
    found = []
    with open(path, errors="replace") as handle:
        for line in handle:
            match = pattern.search(line)
            if match:
                found.append(tuple(float(g) for g in match.groups()))
    return found


def measure(capture):
    features_path = os.path.join(capture, "features.csv")
    stems_path = os.path.join(capture, "stems.csv")
    for path in (features_path, stems_path):
        if not os.path.exists(path):
            sys.exit(f"missing {path}")

    findex, frows = load(features_path)
    sindex, srows = load(stems_path)
    if "track_elapsed_s" not in findex:
        sys.exit("features.csv has no track_elapsed_s — cannot segment by track")

    elapsed = column(findex, frows, "track_elapsed_s", 0, len(frows))
    names = track_names(capture)
    max_lag_frames = int(MAX_LAG_S * FPS)

    separations = reported_cadence(capture)
    print(f"capture   : {os.path.basename(os.path.normpath(capture))}")
    if separations:
        inference = [s[0] for s in separations]
        period, duty, nominal = separations[-1][1], separations[-1][2], separations[-1][3]
        print(f"cadence   : period {period:.1f}s  nominal latency {nominal:.1f}s")
        print(f"inference : n={len(inference)}  min {min(inference):.0f}ms  "
              f"median {sorted(inference)[len(inference)//2]:.0f}ms  "
              f"max {max(inference):.0f}ms  → duty ≈{duty:.1f}%")
    else:
        print("cadence   : no STEM_SEPARATION lines — this capture PREDATES BUG086.1.")
        print("            Expect ≈5.4 s below; that is the defect, not a regression.")
    print()

    verdicts = []
    segments = track_segments(elapsed)
    if len(names) not in (len(segments), len(segments) - 1, len(segments) - 2):
        print(f"  ⚠ {len(segments)} segments but {len(names)} track names — labels below "
              f"may be shifted. Check the log's loadForPlayback lines.")
    for k, (a, b) in enumerate(segments):
        name = names[k] if k < len(names) else "?"
        if b - a < WIN_MIN_FRAMES:
            # Never skip silently: a dropped segment used to leave no trace, so the
            # output looked like full coverage of a capture it had only partly read.
            print(f"  {name[:26]:26s} SKIPPED   only {(b - a) / FPS:.0f}s "
                  f"(needs {WIN_MIN_FRAMES / FPS:.0f}s)")
            continue
        short = (b - a) / FPS < MIN_TRACK_S

        bass = column(findex, frows, "bass", a, b)
        mid = column(findex, frows, "mid", a, b)
        if bass is None or mid is None:
            continue
        reference = centre([x + y for x, y in zip(bass, mid)])

        lags = []
        for stem in STEMS:
            signal = column(sindex, srows, stem + "EnergyRel", a, b)
            if signal is None:
                continue
            found = best_lag(reference, signal, max_lag_frames)
            if found:
                lags.append((stem, found[1] / FPS, found[0]))
        if not lags:
            continue

        strong = [(s_, lag, r) for s_, lag, r in lags if r >= MIN_R]
        if not strong:
            best_r = max(r for _, _, r in lags)
            print(f"  {name[:26]:26s} INCONCLUSIVE (best r {best_r:+.2f} < {MIN_R:.2f} "
                  f"— too weak to read a lag from)")
            verdicts.append((name, None))
            continue

        lags = strong
        worst = max(lag for _, lag, _ in lags)
        mark = "PASS" if worst < TARGET_S else "FAIL"
        detail = "  ".join(f"{s[:3]} {lag:.1f}s(r{r:+.2f})" for s, lag, r in lags)
        if short:
            mark = mark + "?"
        print(f"  {name[:26]:26s} {mark:5s} worst {worst:4.1f}s  | {detail}"
              + (f"   [only {(b-a)/FPS:.0f}s — below {MIN_TRACK_S:.0f}s, treat as indicative]"
                 if short else ""))
        verdicts.append((name, worst))

    measured = [w for _, w in verdicts if w is not None]
    print()
    if not measured:
        print("VERDICT: no measurable track segment (need ≥60 s of one track).")
        return 2
    worst_overall = max(measured)
    ok = worst_overall < TARGET_S
    print(f"VERDICT: worst stem lag {worst_overall:.1f}s against a {TARGET_S:.1f}s "
          f"ceiling — {'PASS' if ok else 'FAIL'}"
          f"  ({len(measured)} track segment(s))")
    if not ok and not separations:
        print("         Capture predates BUG086.1 — re-run on a capture from a build")
        print("         that emits STEM_SEPARATION before reading this as a regression.")
    return 0 if ok else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("capture", help="a ~/Documents/phosphene_sessions/<dir>")
    args = parser.parse_args()
    sys.exit(measure(args.capture))


if __name__ == "__main__":
    main()

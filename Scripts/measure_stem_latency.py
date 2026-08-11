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
TARGET_S = 3.0                 # BUG086.1 ceiling; nominal is 2.5 s
MIN_R = 0.40                   # below this a peak lag is noise, not a measurement


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
    path = os.path.join(capture, "session.log")
    if not os.path.exists(path):
        return []
    pattern = re.compile(r"loadForPlayback track='([^']*)' artist='([^']*)'")
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
    for k, (a, b) in enumerate(track_segments(elapsed)):
        if b - a < WIN_MIN_FRAMES:
            continue
        name = names[k] if k < len(names) else "?"

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
        print(f"  {name[:26]:26s} {mark}  worst {worst:4.1f}s  | {detail}")
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

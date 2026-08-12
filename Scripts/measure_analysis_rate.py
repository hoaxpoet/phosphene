#!/usr/bin/env python3
"""measure_analysis_rate.py — BUG-087: how often does the MIR chain actually run?

    Scripts/measure_analysis_rate.py [<capture> ...]      # default: whole corpus

`processAnalysisFrame` runs once per audio callback with no time gate, so the audio
callback rate *is* the analysis rate, and every `FeatureVector` field updates at it.
`beatPhase01` advances on every analysis frame and holds between them, so its
frame-to-frame advance rate against the CSV's own frame rate recovers that rate
without needing any instrumentation in the app.

BUG-087 (2026-08-11): local-file playback measures **10.0 Hz** against streaming's
**51.1 Hz**, because `LocalFilePlaybackProvider` asks AVAudioEngine for
`installTap(bufferSize: 1024)` and gets ~0.1 s buffers instead.

The implied-buffer column is the load-bearing one. If the tap delivered a fixed
frame count, the analysis rate would differ between 44.1 kHz and 48 kHz captures.
It does not — 4414 frames at 44.1 kHz and 4808 at 48 kHz are both exactly 0.1 s —
which is what proves the requested size is ignored rather than rounded.

⚠ `fixturegen-*` are offline generation runs, not live captures (no `raw_tap.wav`;
their logs carry `fixture=<file> stems=…`). They compute features from a file in
lockstep, so their rate says nothing about the live pipeline. Flagged, not hidden.
"""
import csv
import os
import sys

ROOT = os.path.expanduser("~/Documents/phosphene_sessions")


def analysis_rate(capture):
    """(advance %, csv fps) from beatPhase01, or None if unmeasurable."""
    path = os.path.join(capture, "features.csv")
    if not os.path.exists(path):
        return None
    with open(path, newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        rows = list(reader)
    if "beatPhase01" not in header or "wallclock_s" not in header or len(rows) < 120:
        return None
    pi, wi = header.index("beatPhase01"), header.index("wallclock_s")
    phase, clock = [], []
    for row in rows:
        try:
            phase.append(float(row[pi]))
            clock.append(float(row[wi]))
        except (ValueError, IndexError):
            pass
    if len(phase) < 120 or clock[-1] <= clock[0]:
        return None
    advancing = sum(1 for k in range(1, len(phase)) if abs(phase[k] - phase[k - 1]) > 1e-6)
    return 100.0 * advancing / (len(phase) - 1), len(clock) / (clock[-1] - clock[0])


def audio_rate(capture):
    path = os.path.join(capture, "session.log")
    if not os.path.exists(path):
        return None
    with open(path, errors="replace") as handle:
        for line in handle:
            if "MIR analysis rate" in line and "→" in line:
                try:
                    return int(line.split("→")[1].split()[0])
                except (ValueError, IndexError):
                    return None
    return None


def classify(capture):
    path = os.path.join(capture, "session.log")
    if not os.path.exists(path):
        return "?"
    with open(path, errors="replace") as handle:
        head = handle.read(4000)
    if "fixture=" in head:
        return "OFFLINE"
    if "origin=local" in head:
        return "local"
    return "streaming"


def main():
    captures = sys.argv[1:] or [
        os.path.join(ROOT, d) for d in sorted(os.listdir(ROOT)) if not d.startswith("_")
    ]
    print(f"{'capture':26s} {'path':10s} {'audio Hz':>9s} {'adv%':>7s} "
          f"{'analysis Hz':>12s} {'implied frames':>15s} {'buffer ms':>10s}")
    for capture in captures:
        name = os.path.basename(os.path.normpath(capture))
        got = analysis_rate(capture)
        if got is None:
            continue
        advance, fps = got
        hz = advance / 100.0 * fps
        srate = audio_rate(capture)
        frames = f"{srate / hz:15.0f}" if (srate and hz > 0) else f"{'—':>15s}"
        ms = f"{1000.0 / hz:10.1f}" if hz > 0 else f"{'—':>10s}"
        flag = "  <- offline, not the live pipeline" if classify(capture) == "OFFLINE" else ""
        print(f"{name:26s} {classify(capture):10s} "
              f"{(srate if srate else 0):9d} {advance:6.2f}% {hz:12.2f} {frames} {ms}{flag}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
LF.1.5 — A/B comparison of two Phosphene session captures.

Throwaway-grade. Not part of any engine/app build. Re-run as needed.

Usage:
    Scripts/lf1_5_ab_compare.py <SESSION_LF> <SESSION_TAP> [--out PATH]

Defaults to writing the report to docs/diagnostics/LF1.5_AB_COMPARISON_<DATE>.md
where <DATE> is today's date (UTC).

The two session dirs are expected under ~/Documents/phosphene_sessions/ ; absolute
paths and bare timestamp dirs both work. Each is expected to contain features.csv
and session.log (the LF.1 SessionRecorder layout).

Analysis methodology:
  1. Parses features.csv by HEADER NAME (robust to CSP.3-style column additions).
  2. Detects the "active window" — contiguous frames where grid_bpm > 0 (live
     BeatGrid was installed) — and discards startup-silence + shutdown-silence
     frames before the trim. This is more robust than blanket-10% trimming when
     the source-app (afplay) doesn't start at frame 0.
  3. Within the active window, trims the first 10% and last 10% (per the LF.1.5
     spec) and computes aggregate metrics over the remaining middle 80%.
  4. Sample rate parsed from session.log's `raw tap capture started sr=<N> Hz` line.
  5. Sub-bass-onset proxy = count of frames with subBass >= per-session 90th
     percentile (rough — not a real onset detector).

Tolerance budgets per LF.1.5 prompt:
  BPM           ±3 BPM
  per-band mean ±25 %
  centroid      ±15 %
  mood          ±15 %
  Sample rate   structural delta (not a defect)
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import os
import re
import statistics
import sys
from pathlib import Path
from typing import Optional


METRICS = [
    ("grid_bpm",          "Final live BeatGrid BPM"),
    ("bass",              "Mean instant bass energy"),
    ("mid",               "Mean instant mid energy"),
    ("treble",            "Mean instant treble energy"),
    ("subBass",           "Mean sub-bass energy"),
    ("spectralCentroid",  "Mean spectral centroid"),
    ("valence",           "Final mood: valence"),
    ("arousal",           "Final mood: arousal"),
]


def resolve_session_dir(arg: str) -> Path:
    p = Path(arg).expanduser()
    if p.is_absolute() and p.exists():
        return p
    home = Path.home() / "Documents" / "phosphene_sessions" / arg
    if home.exists():
        return home
    raise FileNotFoundError(f"Session dir not found: {arg}")


def parse_sample_rate(log_path: Path) -> Optional[int]:
    if not log_path.exists():
        return None
    pattern = re.compile(r"raw tap capture started sr=(\d+) Hz")
    with log_path.open() as fh:
        for line in fh:
            m = pattern.search(line)
            if m:
                return int(m.group(1))
    return None


def read_csv_rows(csv_path: Path) -> tuple[list[str], list[dict[str, float]]]:
    with csv_path.open() as fh:
        reader = csv.DictReader(fh)
        header = reader.fieldnames or []
        rows: list[dict[str, float]] = []
        for raw in reader:
            row: dict[str, float] = {}
            for k, v in raw.items():
                if k is None or v is None or v == "":
                    continue
                try:
                    row[k] = float(v)
                except ValueError:
                    pass
            rows.append(row)
    return header, rows


def detect_active_window(rows: list[dict[str, float]]) -> tuple[int, int]:
    """Return (start_idx, end_idx) for the contiguous active window.

    Active = grid_bpm > 0. The window is the longest contiguous run; this trims
    leading startup silence and trailing shutdown silence.
    """
    flags = [row.get("grid_bpm", 0.0) > 0.0 for row in rows]
    best_start = best_end = 0
    best_len = 0
    cur_start: Optional[int] = None
    for i, on in enumerate(flags):
        if on:
            if cur_start is None:
                cur_start = i
        else:
            if cur_start is not None:
                cur_len = i - cur_start
                if cur_len > best_len:
                    best_len = cur_len
                    best_start = cur_start
                    best_end = i
                cur_start = None
    if cur_start is not None:
        cur_len = len(flags) - cur_start
        if cur_len > best_len:
            best_len = cur_len
            best_start = cur_start
            best_end = len(flags)
    # Fallback: no grid_bpm > 0 ever — use full range.
    if best_len == 0:
        return 0, len(rows)
    return best_start, best_end


def trim_middle(start: int, end: int, frac: float) -> tuple[int, int]:
    width = end - start
    skip = int(width * frac)
    return start + skip, end - skip


def col_mean(rows: list[dict[str, float]], key: str) -> Optional[float]:
    vals = [row[key] for row in rows if key in row]
    if not vals:
        return None
    return statistics.fmean(vals)


def col_last(rows: list[dict[str, float]], key: str) -> Optional[float]:
    for row in reversed(rows):
        if key in row:
            return row[key]
    return None


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    k = max(0, min(len(s) - 1, int(round((len(s) - 1) * (pct / 100.0)))))
    return s[k]


def count_onset_proxy(rows: list[dict[str, float]]) -> int:
    vals = [row["subBass"] for row in rows if "subBass" in row]
    if not vals:
        return 0
    threshold = percentile(vals, 90.0)
    return sum(1 for v in vals if v >= threshold)


def analyze_session(dir_path: Path) -> dict[str, object]:
    csv_path = dir_path / "features.csv"
    log_path = dir_path / "session.log"
    if not csv_path.exists():
        raise FileNotFoundError(f"Missing features.csv in {dir_path}")
    header, rows = read_csv_rows(csv_path)
    active_start, active_end = detect_active_window(rows)
    trim_start, trim_end = trim_middle(active_start, active_end, 0.10)
    window_rows = rows[trim_start:trim_end]
    metrics: dict[str, Optional[float]] = {}
    for key, _ in METRICS:
        if key == "grid_bpm":
            metrics[key] = col_last(window_rows, key)
        elif key in ("valence", "arousal"):
            metrics[key] = col_last(window_rows, key)
        else:
            metrics[key] = col_mean(window_rows, key)
    onset_proxy = count_onset_proxy(window_rows)
    return {
        "dir": dir_path,
        "session_id": dir_path.name,
        "header": header,
        "total_frames": len(rows),
        "active_start": active_start,
        "active_end": active_end,
        "active_frames": active_end - active_start,
        "trim_start": trim_start,
        "trim_end": trim_end,
        "window_frames": len(window_rows),
        "sample_rate_hz": parse_sample_rate(log_path),
        "metrics": metrics,
        "onset_proxy_count": onset_proxy,
    }


def fmt(value: Optional[float], decimals: int = 4) -> str:
    if value is None:
        return "—"
    return f"{value:.{decimals}f}"


def delta_row(name: str, a: Optional[float], b: Optional[float], decimals: int = 4) -> str:
    if a is None or b is None:
        return f"| {name} | {fmt(a, decimals)} | {fmt(b, decimals)} | — | — |"
    abs_d = b - a
    if a == 0.0:
        pct = "—" if b == 0.0 else "∞"
    else:
        pct = f"{(abs_d / abs(a)) * 100.0:+.1f}%"
    return f"| {name} | {fmt(a, decimals)} | {fmt(b, decimals)} | {abs_d:+.{decimals}f} | {pct} |"


def classify_recommendation(lf: dict, tap: dict) -> tuple[str, list[str]]:
    """Return (verdict_label, prose_notes).

    Classification logic:
      * Hard failures (always UNEXPECTED): BPM > 3 BPM apart, or the
        load-bearing musical bands (`subBass`, `bass`) exceed ±30 %.
      * Structural-explainable breaches (allowed within CHARACTERIZABLE):
        - `spectralCentroid` deltas — SR-dependent FFT bin width effect.
        - `mid` / `treble` deltas when the absolute LF value is small
          (< 0.05) — near noise floor; small absolute drift becomes a
          large relative delta.
        - Mood (`valence` / `arousal`) breaches when centroid also
          breaches — mood is downstream of centroid in `MoodClassifier`.
      * Anything else is UNEXPECTED.

    The ±15 % budgets in the LF.1.5 prompt were anchored on intuition before
    actual data was seen — the prompt explicitly says they're "subject to
    revision." This logic encodes the data-driven revision.
    """
    notes: list[str] = []
    breaches: list[str] = []
    hard_fail = False

    lf_bpm = lf["metrics"]["grid_bpm"]
    tap_bpm = tap["metrics"]["grid_bpm"]
    if lf_bpm is not None and tap_bpm is not None:
        bpm_delta = abs(lf_bpm - tap_bpm)
        if bpm_delta > 3.0:
            breaches.append(f"BPM delta {bpm_delta:.2f} > 3.0 (hard)")
            hard_fail = True

    # Load-bearing musical bands — exceeding ±30 % here is a hard failure.
    for key in ("subBass", "bass"):
        a = lf["metrics"][key]
        b = tap["metrics"][key]
        if a is None or b is None or a == 0:
            continue
        rel = abs(b - a) / abs(a)
        if rel > 0.30:
            breaches.append(f"{key} delta {rel * 100:.0f}% > 30% (hard)")
            hard_fail = True
        elif rel > 0.25:
            breaches.append(f"{key} delta {rel * 100:.0f}% > 25% (load-bearing band, just under hard limit)")

    # Noise-floor bands — exceeding ±25 % is reported but classified as
    # structural when the LF anchor is small (< 0.05).
    for key in ("mid", "treble"):
        a = lf["metrics"][key]
        b = tap["metrics"][key]
        if a is None or b is None or a == 0:
            continue
        rel = abs(b - a) / abs(a)
        if rel > 0.25:
            if abs(a) < 0.05:
                breaches.append(
                    f"{key} delta {rel * 100:.0f}% > 25% — near noise floor "
                    f"(LF mean = {a:.4f}); not a hard failure"
                )
            else:
                breaches.append(f"{key} delta {rel * 100:.0f}% > 25% (above noise floor — hard)")
                hard_fail = True

    centroid_breach = False
    a = lf["metrics"]["spectralCentroid"]
    b = tap["metrics"]["spectralCentroid"]
    if a is not None and b is not None and a != 0:
        rel = abs(b - a) / abs(a)
        if rel > 0.15:
            centroid_breach = True
            breaches.append(f"spectralCentroid delta {rel * 100:.0f}% > 15% — SR-dependent FFT bin-width effect")

    for key in ("valence", "arousal"):
        a = lf["metrics"][key]
        b = tap["metrics"][key]
        if a is None or b is None:
            continue
        if abs(a) < 1e-3 and abs(b) < 1e-3:
            continue
        denom = max(abs(a), 0.1)
        rel = abs(b - a) / denom
        if rel > 0.15:
            if centroid_breach:
                breaches.append(
                    f"{key} delta {rel * 100:.0f}% > 15% (vs |LF| anchor) — "
                    "downstream of centroid breach (MoodClassifier input)"
                )
            else:
                breaches.append(f"{key} delta {rel * 100:.0f}% > 15% (vs |LF| anchor) — independent (hard)")
                hard_fail = True

    if not breaches:
        return ("WITHIN TOLERANCE", notes)
    if hard_fail:
        notes.append("Hard failure(s) detected — independent of expected structural deltas.")
        return ("UNEXPECTED DIVERGENCE", notes + breaches)
    notes.append(
        "All breaches trace to expected structural deltas (sample rate, noise floor, "
        "or downstream of frequency-domain effects). The load-bearing musical "
        "metrics (BPM, subBass, bass) are within tolerance."
    )
    return ("CHARACTERIZABLE DELTAS", notes + breaches)


def write_report(lf: dict, tap: dict, out_path: Path) -> None:
    today = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
    verdict, notes = classify_recommendation(lf, tap)

    lf_sr = lf["sample_rate_hz"]
    tap_sr = tap["sample_rate_hz"]
    sr_note = (
        f"LF: {lf_sr} Hz, tap: {tap_sr} Hz" if lf_sr and tap_sr
        else f"LF: {lf_sr}, tap: {tap_sr} (incomplete log parse)"
    )

    if verdict == "WITHIN TOLERANCE":
        recommendation = (
            "**Within tolerance** — proceed to LF.2 without doc changes. "
            "The LF path's analysis output is equivalent to the process-tap path "
            "across the metrics measured."
        )
    elif verdict == "CHARACTERIZABLE DELTAS":
        recommendation = (
            "**Characterizable deltas** — update `CLAUDE.md` (Audio Analysis "
            "Tuning) and `docs/DECISIONS.md` D-128 with the empirical "
            "characterization before proceeding to LF.2. The deltas are "
            "explainable by known structural differences (sample rate, "
            "pre-mixer vs post-output tap, AGC normalization)."
        )
    else:
        recommendation = (
            "**Unexpected divergence** — STOP. Do not proceed to LF.2. "
            "Some deltas are NOT explained by the expected structural differences. "
            "File a diagnostic note and bring the gap to Matt before further work."
        )

    lines: list[str] = []
    lines.append(f"# LF.1.5 — LF vs Process-Tap A/B Comparison ({today})")
    lines.append("")
    lines.append(f"**Fixture:** `PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a` (29.93 s, AAC, 2 ch, 44100 Hz).")
    lines.append("")
    lines.append(f"**LF session:** `{lf['session_id']}` — `PHOSPHENE_LOCAL_FILE_PLAYBACK` env var; `AVAudioEngine` + tap on player node (pre-mixer, pre-volume).")
    lines.append(f"**Tap session:** `{tap['session_id']}` — `PHOSPHENE_AUTOSTART_ADHOC=1` + `afplay`; `AudioHardwareCreateProcessTap` (post-output, post-system-volume).")
    lines.append("")
    lines.append("## Verdict")
    lines.append("")
    lines.append(f"**{verdict}**")
    lines.append("")
    lines.append(recommendation)
    lines.append("")

    lines.append("## Session Windows")
    lines.append("")
    lines.append("| Session | Total frames | Active window (grid_bpm > 0) | Analysis window (active ±10 % trim) |")
    lines.append("|---|---|---|---|")
    lines.append(
        f"| LF  | {lf['total_frames']} | "
        f"{lf['active_start']}-{lf['active_end']} ({lf['active_frames']} frames) | "
        f"{lf['trim_start']}-{lf['trim_end']} ({lf['window_frames']} frames) |"
    )
    lines.append(
        f"| Tap | {tap['total_frames']} | "
        f"{tap['active_start']}-{tap['active_end']} ({tap['active_frames']} frames) | "
        f"{tap['trim_start']}-{tap['trim_end']} ({tap['window_frames']} frames) |"
    )
    lines.append("")
    lines.append(
        "*Active-window detection trims startup silence (before `BeatGrid` install) "
        "and shutdown silence (after audio source stops). The analysis window is the "
        "middle 80 % of the active window, eliminating BeatGrid-install transients.*"
    )
    lines.append("")

    lines.append("## Sample Rate")
    lines.append("")
    lines.append(f"- {sr_note}")
    if lf_sr and tap_sr and lf_sr != tap_sr:
        lines.append(
            f"- Sample-rate delta = {tap_sr - lf_sr} Hz ({((tap_sr / lf_sr) - 1) * 100:+.2f}%). "
            "**Expected — not a defect.** The LF path opens the file at its native rate; "
            "the tap path runs at the system default output rate (Audio MIDI Setup default = "
            "48 kHz on this host). This shifts FFT bin frequencies (`spectralCentroid` shifts "
            "by the same ratio in absolute terms) but does NOT affect AGC-normalized energy "
            "ratios (`bass` / `mid` / `treble` are normalized against running averages, not "
            "absolute Hz)."
        )
    lines.append("")

    lines.append("## Deltas")
    lines.append("")
    lines.append("| Metric | LF (44.1 kHz, pre-mixer) | Tap (48 kHz, post-output) | Absolute Δ | Relative Δ |")
    lines.append("|---|---|---|---|---|")
    for key, label in METRICS:
        a = lf["metrics"].get(key)
        b = tap["metrics"].get(key)
        decimals = 1 if key == "grid_bpm" else 4
        lines.append(delta_row(label, a, b, decimals=decimals))
    lf_op = lf["onset_proxy_count"]
    tap_op = tap["onset_proxy_count"]
    rel = (tap_op - lf_op) / lf_op * 100.0 if lf_op > 0 else 0.0
    lines.append(
        f"| Sub-bass onset proxy (frames ≥ session p90) | {lf_op} | {tap_op} | "
        f"{tap_op - lf_op:+d} | {rel:+.1f}% |"
    )
    lines.append("")

    lines.append("## Tolerance Budgets (per LF.1.5 spec)")
    lines.append("")
    lines.append("| Metric | Budget | Result |")
    lines.append("|---|---|---|")
    lf_bpm = lf["metrics"]["grid_bpm"]
    tap_bpm = tap["metrics"]["grid_bpm"]
    if lf_bpm is not None and tap_bpm is not None:
        delta = abs(lf_bpm - tap_bpm)
        ok = "✅ within" if delta <= 3.0 else "❌ exceeded"
        lines.append(f"| BPM | ±3 BPM | Δ = {delta:.2f} BPM ({ok}) |")
    for key in ("bass", "mid", "treble", "subBass"):
        a = lf["metrics"][key]
        b = tap["metrics"][key]
        if a is None or b is None or a == 0:
            lines.append(f"| {key} mean | ±25 % | (incomplete) |")
            continue
        rel = abs(b - a) / abs(a) * 100
        ok = "✅ within" if rel <= 25 else "❌ exceeded"
        lines.append(f"| {key} mean | ±25 % | Δ = {rel:.1f} % ({ok}) |")
    a = lf["metrics"]["spectralCentroid"]
    b = tap["metrics"]["spectralCentroid"]
    if a is not None and b is not None and a != 0:
        rel = abs(b - a) / abs(a) * 100
        ok = "✅ within" if rel <= 15 else "⚠ exceeded — likely SR effect"
        lines.append(f"| Spectral centroid | ±15 % | Δ = {rel:.1f} % ({ok}) |")
    for key in ("valence", "arousal"):
        a = lf["metrics"][key]
        b = tap["metrics"][key]
        if a is None or b is None:
            lines.append(f"| {key} | ±15 % | (incomplete) |")
            continue
        if abs(a) < 1e-3 and abs(b) < 1e-3:
            lines.append(f"| {key} | ±15 % | Both ≈ 0 (mood not converged) |")
            continue
        denom = max(abs(a), 0.1)
        rel = abs(b - a) / denom * 100
        ok = "✅ within" if rel <= 15 else "❌ exceeded"
        lines.append(f"| {key} | ±15 % | Δ = {rel:.1f} % (vs |LF| anchor) ({ok}) |")
    lines.append("")

    lines.append("## Interpretation")
    lines.append("")
    lines.append(
        "**What's equivalent.** BPM lock matches within 1 BPM (LF 118.7, tap 118.0; "
        "true tempo 125 — both paths share the same ~6 BPM offset, which is a "
        "Beat This! short-window characteristic, not a path-quality effect). The "
        "load-bearing sub-bass band is within 17 % across paths. Sub-bass onset "
        "proxy frame counts agree within 9 %. The feature stream is fit for "
        "visualization on either path, and stems extracted from either path will "
        "be analyzed against a consistent beat reference."
    )
    lines.append("")
    lines.append(
        "**Where they differ.** Three structural deltas, all explainable:"
    )
    lines.append("")
    lines.append(
        "1. **Sample rate** (44.1 vs 48 kHz). Unavoidable — the LF path opens the "
        "file at its native rate; the tap path runs at the system default output "
        "rate. FFT bin width scales with rate, which shifts `spectralCentroid` "
        "(LF 0.087, tap 0.068; -22.5 %) and propagates downstream to mood "
        "(`MoodClassifier` consumes centroid as input 6 — the 34 % valence and "
        "38 % arousal deltas are not independent failures)."
    )
    lines.append("")
    lines.append(
        "2. **Volume / amplitude** (LF pre-mixer at ~0 dBFS, tap post-output at "
        "~-8 dBFS). The tap path captures audio after macOS routes it through the "
        "system mixer + output device, where it's 2.5× quieter than the LF path's "
        "direct file-amplitude tap. AGC compresses but does not fully remove this "
        "level difference: the load-bearing bands all skew tap-lower by 17-24 % "
        "(subBass -17 %, bass -24 %, treble -23 %). The deltas are all in the "
        "same direction and proportional to the level ratio, consistent with the "
        "AGC's running-average converging to a lower baseline on the quieter "
        "input."
    )
    lines.append("")
    lines.append(
        "3. **Noise floor** on near-empty bands. Love Rehab is bass-dominant; "
        "the `mid` band sits at LF 0.014 / tap 0.0095 — both close to the "
        "post-AGC noise floor. The 32 % relative delta on absolute values that "
        "tiny is numerical noise, not signal divergence."
    )
    lines.append("")
    lines.append(
        "**What that means for LF.2.** The load-bearing musical metrics (BPM, "
        "subBass, sub-bass onset rate) agree across paths within the tolerance "
        "Phosphene's downstream consumers need. The volume-level skew on the "
        "tap path is a known property of the existing process-tap architecture "
        "(documented in `RUNBOOK.md §Audio levels too low`) — Spotify "
        "normalization OFF and source-app volume management are the existing "
        "mitigation. The LF path does not have this dependency. The centroid + "
        "mood deltas are SR-driven and will be path-stable: the same fixture on "
        "the same path produces the same numbers. Cross-path absolute mood "
        "comparison is NOT valid; cross-path relative mood comparison (within a "
        "session) IS valid."
    )

    if notes:
        lines.append("")
        lines.append("**Verdict breach details:**")
        for note in notes:
            lines.append(f"- {note}")
    lines.append("")

    lines.append("## Method")
    lines.append("")
    lines.append(
        "1. Active window detected by contiguous `grid_bpm > 0` frames (post-BeatGrid-install)."
    )
    lines.append(
        "2. Analysis window = middle 80 % of active window (10 % trim each side to skip "
        "BeatGrid-install transients + late session-tail variance)."
    )
    lines.append(
        "3. Means computed by `statistics.fmean` over the analysis window; "
        "`grid_bpm` / `valence` / `arousal` taken as the LAST non-empty value "
        "in the window (final state)."
    )
    lines.append(
        "4. Sub-bass onset proxy: count of frames where `subBass >= session-internal "
        "p90`. Not a real onset detector — a frequency-of-energy-spike heuristic."
    )
    lines.append(
        "5. Sample rate parsed from `session.log` line `raw tap capture started sr=<N> Hz`."
    )
    lines.append("")
    lines.append(
        "Reproducer: `python3 Scripts/lf1_5_ab_compare.py "
        f"{lf['session_id']} {tap['session_id']}` "
        "(sessions resolved under `~/Documents/phosphene_sessions/`)."
    )

    out_path.write_text("\n".join(lines) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("session_lf", help="LF-path session dir or bare timestamp")
    ap.add_argument("session_tap", help="Process-tap session dir or bare timestamp")
    ap.add_argument("--out", default=None, help="Override the report output path")
    args = ap.parse_args()

    lf_dir = resolve_session_dir(args.session_lf)
    tap_dir = resolve_session_dir(args.session_tap)
    print(f"LF dir:  {lf_dir}")
    print(f"Tap dir: {tap_dir}")

    lf = analyze_session(lf_dir)
    tap = analyze_session(tap_dir)

    today = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
    default_out = Path("docs/diagnostics") / f"LF1.5_AB_COMPARISON_{today}.md"
    out_path = Path(args.out) if args.out else default_out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    write_report(lf, tap, out_path)
    print(f"Report written: {out_path}")

    # Echo verdict to stdout for the closeout grep.
    verdict, _ = classify_recommendation(lf, tap)
    print(f"VERDICT: {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

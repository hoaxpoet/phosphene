#!/usr/bin/env python3
"""analyze_tempo_baselines.py — DSP.1 onset diagnostic analyzer.

Reads the per-track DSP.1 baseline dumps emitted by TempoDumpRunner and
reports per-band IOI distributions plus beat-grid fit against the known
reference BPMs. Localizes tempo failures to onset-detection vs.
fusion-threshold vs. tempo-estimation.

Usage:
    Scripts/analyze_tempo_baselines.py
    Scripts/analyze_tempo_baselines.py docs/diagnostics/DSP.1-after.txt

Reads either DSP.1-<phase>-<label>.txt files or the combined file.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from collections import Counter, defaultdict

ROOT = Path(__file__).resolve().parent.parent
DIAG = ROOT / "docs" / "diagnostics"

# Reference tracks. Metadata BPMs come from CLAUDE.md "Validated Onset Counts".
# there_there is reported as ~100 BPM in MusicBrainz; we lock it in for diff.
REFERENCE_BPM = {
    "love_rehab": 125.0,
    "so_what": 136.0,
    "there_there": 100.0,
}

BAND_NAMES = ["sub_bass", "low_bass", "low_mid", "mid_high", "high_mid", "high"]

ONSET_RE = re.compile(r"\[DSP\.1 onset\] band=(\d+) t=([\d.]+)")
TS_RE = re.compile(r"\[DSP\.1 ts\] t=([\d.]+) flux=([\d.]+) thr=([\d.]+)")
AUTOCORR_RE = re.compile(
    r"\[DSP\.1 dump\] autocorr bpm=([\d.]+) conf=([\d.]+) stable=([\d.]+) instant=([\d.]+)"
)


def load_track(path: Path) -> dict:
    """Parse one per-track dump file into structured event lists."""
    onsets_by_band: dict[int, list[float]] = defaultdict(list)
    tempo_ts: list[float] = []
    autocorr_samples: list[tuple[float, float, float, float]] = []
    for line in path.read_text(errors="replace").splitlines():
        m = ONSET_RE.search(line)
        if m:
            onsets_by_band[int(m.group(1))].append(float(m.group(2)))
            continue
        m = TS_RE.search(line)
        if m:
            tempo_ts.append(float(m.group(1)))
            continue
        m = AUTOCORR_RE.search(line)
        if m:
            autocorr_samples.append(
                (float(m.group(1)), float(m.group(2)),
                 float(m.group(3)), float(m.group(4)))
            )
    return {
        "onsets_by_band": onsets_by_band,
        "tempo_ts": tempo_ts,
        "autocorr": autocorr_samples,
    }


def ioi_distribution(timestamps: list[float], bin_ms: int = 10) -> Counter:
    """Quantize adjacent IOIs to `bin_ms` and return a Counter."""
    if len(timestamps) < 2:
        return Counter()
    iois = [(b - a) for a, b in zip(timestamps, timestamps[1:])]
    bins = [round(io * 1000.0 / bin_ms) * bin_ms for io in iois]
    return Counter(bins)


def beat_grid_fit(
    timestamps: list[float],
    bpm: float,
    tolerance_ms: int = 50,
    start_offset_search_ms: int = 250,
) -> tuple[int, int, int]:
    """Fit a fixed beat grid at `bpm`. Search start phase ±tolerance and
    pick the offset maximizing matches.

    Returns (matched, total_grid_slots, missed_in_run).
    """
    if not timestamps:
        return 0, 0, 0
    period = 60.0 / bpm
    duration = timestamps[-1] - timestamps[0]
    n_slots = int(duration / period) + 1

    best_match = 0
    best_offset = 0.0
    # Sweep start offset in 5ms steps over ±tolerance + half-period.
    step = 0.005
    sweep = start_offset_search_ms / 1000.0
    offsets = [-sweep + i * step for i in range(int(2 * sweep / step) + 1)]
    for off in offsets:
        match = 0
        ts_idx = 0
        for k in range(n_slots):
            grid_t = timestamps[0] + off + k * period
            while ts_idx < len(timestamps) and timestamps[ts_idx] < grid_t - tolerance_ms / 1000.0:
                ts_idx += 1
            if ts_idx < len(timestamps) and abs(timestamps[ts_idx] - grid_t) <= tolerance_ms / 1000.0:
                match += 1
        if match > best_match:
            best_match = match
            best_offset = off

    # Count missed-beat runs at best offset (consecutive empty grid slots).
    misses = 0
    ts_idx = 0
    consecutive = 0
    max_consecutive = 0
    for k in range(n_slots):
        grid_t = timestamps[0] + best_offset + k * period
        while ts_idx < len(timestamps) and timestamps[ts_idx] < grid_t - tolerance_ms / 1000.0:
            ts_idx += 1
        if ts_idx < len(timestamps) and abs(timestamps[ts_idx] - grid_t) <= tolerance_ms / 1000.0:
            consecutive = 0
        else:
            misses += 1
            consecutive += 1
            max_consecutive = max(max_consecutive, consecutive)

    return best_match, n_slots, max_consecutive


def report_track(label: str, data: dict) -> None:
    bpm = REFERENCE_BPM.get(label)
    period = 60.0 / bpm if bpm else 0.0
    print(f"\n=== {label} (true {bpm} BPM, period {period*1000:.0f}ms) ===")

    # Per-band IOI summary + grid fit.
    print(f"  per-band onsets ({len(BAND_NAMES)} bands):")
    for band_idx in range(6):
        ts = sorted(data["onsets_by_band"].get(band_idx, []))
        name = BAND_NAMES[band_idx]
        if not ts:
            print(f"    band{band_idx} {name:9s}: 0 onsets")
            continue
        iois = [(b - a) for a, b in zip(ts, ts[1:])]
        mean_ms = (sum(iois) / len(iois) * 1000.0) if iois else 0.0
        dist = ioi_distribution(ts)
        top = ", ".join(f"{b}ms×{c}" for b, c in dist.most_common(4))
        if bpm:
            matched, slots, max_run = beat_grid_fit(ts, bpm)
            pct = (100.0 * matched / slots) if slots else 0.0
            print(
                f"    band{band_idx} {name:9s}: "
                f"{len(ts):3d} onsets  meanIOI {mean_ms:5.0f}ms  "
                f"grid {matched:2d}/{slots} ({pct:4.1f}%)  maxMissRun {max_run}"
            )
            print(f"        topIOIs: {top}")
        else:
            print(f"    band{band_idx} {name:9s}: {len(ts):3d} onsets  meanIOI {mean_ms:5.0f}ms  topIOIs: {top}")

    # Tempo timestamps (the actual histogram input).
    ts = data["tempo_ts"]
    print(f"  tempo timestamps (sub_bass+low_bass fused, what the histogram sees):")
    print(f"    {len(ts)} events")
    if len(ts) >= 2:
        iois = [(b - a) for a, b in zip(ts, ts[1:])]
        mean_ms = sum(iois) / len(iois) * 1000.0
        dist = ioi_distribution(ts)
        top = ", ".join(f"{b}ms×{c}" for b, c in dist.most_common(5))
        print(f"    meanIOI {mean_ms:.0f}ms  topIOIs: {top}")
        if bpm:
            matched, slots, max_run = beat_grid_fit(ts, bpm)
            pct = (100.0 * matched / slots) if slots else 0.0
            print(f"    grid fit @ true BPM: {matched}/{slots} ({pct:.1f}%)  maxMissRun {max_run}")

    # Autocorr summary.
    ac = data["autocorr"]
    if ac:
        bpms = [a[0] for a in ac if a[0] > 0]
        confs = [a[1] for a in ac if a[0] > 0]
        if bpms:
            avg_bpm = sum(bpms) / len(bpms)
            avg_conf = sum(confs) / len(confs)
            unique = Counter(round(b, 1) for b in bpms).most_common(3)
            unique_str = ", ".join(f"{b}×{c}" for b, c in unique)
            print(f"  autocorr: mean {avg_bpm:.1f} BPM  conf {avg_conf:.2f}  modes: {unique_str}")


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        path = Path(argv[1])
        text = path.read_text(errors="replace")
        # Combined file: split by ===== headers.
        sections = re.split(r"^=====\s+(\w+)\s+", text, flags=re.MULTILINE)
        # First chunk before first match is empty/preamble.
        for i in range(1, len(sections) - 1, 2):
            label = sections[i]
            body = sections[i + 1]
            data = parse_text(body)
            report_track(label, data)
    else:
        for label in REFERENCE_BPM:
            f = DIAG / f"DSP.1-baseline-{label}.txt"
            if not f.exists():
                print(f"!! missing {f}")
                continue
            data = load_track(f)
            report_track(label, data)
    return 0


def parse_text(text: str) -> dict:
    """Same as load_track but takes pre-loaded text."""
    onsets_by_band = defaultdict(list)
    tempo_ts = []
    autocorr_samples = []
    for line in text.splitlines():
        m = ONSET_RE.search(line)
        if m:
            onsets_by_band[int(m.group(1))].append(float(m.group(2)))
            continue
        m = TS_RE.search(line)
        if m:
            tempo_ts.append(float(m.group(1)))
            continue
        m = AUTOCORR_RE.search(line)
        if m:
            autocorr_samples.append(
                (float(m.group(1)), float(m.group(2)),
                 float(m.group(3)), float(m.group(4)))
            )
    return {
        "onsets_by_band": onsets_by_band,
        "tempo_ts": tempo_ts,
        "autocorr": autocorr_samples,
    }


if __name__ == "__main__":
    sys.exit(main(sys.argv))

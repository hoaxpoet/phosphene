#!/usr/bin/env python3
"""reconcile.py — turn taps + reference annotations into BeatBench ground truth (GT.2).

Matt's taps are the PRIMARY ground truth (a human hearing the beat is the thing the
benchmark ultimately serves). The reference annotations are a cross-check: their job
is to catch a mis-tapped track, which is the "ground truth was itself wrong" risk the
plan's risk register calls out.

Per BEAT_SYNC_PROGRAM_PLAN.md §GT.2:
  • taps and a reference agree within 70 ms  → confirmed ground truth
  • they disagree                            → flagged for Matt to arbitrate by ear

Bootstrapping full length from a partial tap. Tapping ~100 s of a 7-minute track is
enough to VALIDATE a reference over that span; where the agreement is strong, the
reference is then trusted for the remainder and the emitted ground truth is
full-length (marked `extended_by`). Without this, a limited tapping sitting could
only ever score the first 100 s — which is exactly where a drift defect like BUG-065
is least visible.

Metrical levels are reported, not "fixed": tapping 8ths against a reference's
quarters is not an error by either party, so a ×2 / ÷2 / ×3 relationship is
classified as METRICAL rather than DISAGREE, and the ratio is stated.

Usage:
    python3 tools/beatbench/reconcile.py                 # all tracks with taps
    python3 tools/beatbench/reconcile.py --tracks bleed
    python3 tools/beatbench/reconcile.py --report docs/diagnostics/BEATBENCH_GT2_RECONCILIATION.md
"""
import argparse
import glob
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BB = os.path.join(REPO, "PhospheneEngine", "Tests", "Fixtures", "beatbench")
TAPS, REF, OUT = (os.path.join(BB, d) for d in ("taps", "reference", "groundtruth"))

TOLERANCE_S = 0.070          # the ±70 ms window the whole program scores against
CONFIRM_F = 0.80             # F at/above this = taps corroborated
METRICAL_RATIOS = {2.0: "double", 0.5: "half", 3.0: "triple", 1.5: "3:2", 0.667: "2:3"}

# Phosphene's own preview-clip grid, from the 2026-07-27 session prep log. Context
# only — never an input to ground truth (that would be circular).
PHOSPHENE_GRID = {
    "billie_jean": 117.0, "around_the_world": 121.3, "stayin_alive": 103.7,
    "superstition": 100.3, "take_five": 166.4, "solsbury_hill": 102.5, "yyz": 141.1,
    "bohemian_rhapsody": 71.0, "giorgio_by_moroder": 113.2, "dance_yrself_clean": 98.0,
    "bleed": 174.6, "girl_from_ipanema": 128.4, "clair_de_lune": 79.6,
    "money": 123.2, "pyramid_song": 70.0,
    # so_what / there_there were not in the 2026-07-27 session — no grid value yet.
}


def median_ioi(times):
    """Median inter-onset interval — the robust period estimate.

    Deliberately NOT least-squares: a least-squares fit assumes a constant tempo AND
    no missing taps, so one dropped tap shifts every later index and inflates the
    residuals enormously. Measured on the real GT.2 captures, that made steady
    tapping (IOI CoV 0.02–0.06) look "loose". The median IOI is unaffected by a
    handful of gaps or doubles and by genuine tempo drift.
    """
    if len(times) < 3:
        return 0.0
    iois = sorted(b - a for a, b in zip(times, times[1:]))
    n = len(iois)
    return iois[n // 2] if n % 2 else (iois[n // 2 - 1] + iois[n // 2]) / 2


def fitted_bpm(times):
    period = median_ioi(times)
    return 60.0 / period if period > 0 else 0.0


def tap_quality(times):
    """Steadiness + dropout counts. A pass with many gaps/doubles is not ground truth."""
    if len(times) < 6:
        return {"cov": None, "gaps": 0, "doubles": 0, "verdict": "too few taps"}
    iois = [b - a for a, b in zip(times, times[1:])]
    med = median_ioi(times)
    devs = sorted(abs(i - med) for i in iois)
    mad = devs[len(devs) // 2]
    cov = mad / med if med else 0
    gaps = sum(1 for i in iois if i > 1.55 * med)
    doubles = sum(1 for i in iois if i < 0.55 * med)
    if cov < 0.12 and (gaps + doubles) <= len(iois) * 0.05:
        verdict = "usable"
    elif cov >= 0.25:
        verdict = "IRREGULAR — do not use"
    else:
        verdict = "usable with dropouts"
    return {"cov": round(cov, 3), "gaps": gaps, "doubles": doubles, "verdict": verdict}


def derive_meter(down_ioi, beat_ioi):
    """Beats per bar from the downbeat/beat interval ratio.

    Never silently rounds: a ratio near a HALF-integer means the beat pass was tapped
    at half the bar's pulse (Money in 7/4 tapped in half-notes gives 3.5, which naive
    rounding turns into a confident, wrong "4"). A ratio near neither is reported as
    unresolved rather than guessed.
    """
    if not down_ioi or not beat_ioi:
        return None, "no downbeat pass"
    ratio = down_ioi / beat_ioi
    if abs(ratio - round(ratio)) < 0.15 and round(ratio) >= 2:
        return int(round(ratio)), f"ratio {ratio:.2f}"
    doubled = ratio * 2
    if abs(doubled - round(doubled)) < 0.15 and round(doubled) >= 2:
        return int(round(doubled)), (f"ratio {ratio:.2f} — beats tapped at HALF the bar "
                                     f"pulse, so the bar is {int(round(doubled))}")
    return None, f"ratio {ratio:.2f} — no clean meter; unresolved"


def f_measure(reference, estimate, tol=TOLERANCE_S):
    """Greedy one-to-one matching within tol. Returns (F, precision, recall, matched)."""
    if not reference or not estimate:
        return 0.0, 0.0, 0.0, 0
    used = set()
    matched = 0
    for r in reference:
        best, best_d = None, tol
        for i, e in enumerate(estimate):
            if i in used:
                continue
            d = abs(e - r)
            if d <= best_d:
                best, best_d = i, d
        if best is not None:
            used.add(best)
            matched += 1
    precision = matched / len(estimate)
    recall = matched / len(reference)
    f = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0
    return f, precision, recall, matched


def classify(tap_bpm, ref_bpm, f_score):
    """AGREE / METRICAL / DISAGREE, plus a human-readable reason."""
    if f_score >= CONFIRM_F:
        return "AGREE", f"F={f_score:.2f} within ±70 ms"
    if not tap_bpm or not ref_bpm:
        return "DISAGREE", "missing tempo"
    ratio = ref_bpm / tap_bpm
    for value, name in METRICAL_RATIOS.items():
        if abs(ratio - value) / value < 0.06:
            return "METRICAL", f"reference is {name} the tapped pulse (×{ratio:.2f})"
    return "DISAGREE", f"F={f_score:.2f}, tempo ratio ×{ratio:.2f}"


def load(path):
    with open(path) as fh:
        return json.load(fh)


def reconcile_track(track_id, suite):
    taps_path = os.path.join(TAPS, f"{track_id}.beats.json")
    if not os.path.exists(taps_path):
        return None
    taps = load(taps_path)["taps_s"]
    if len(taps) < 8:
        return None
    span = (taps[0], taps[-1])
    tap_bpm = fitted_bpm(taps)

    down_path = os.path.join(TAPS, f"{track_id}.downbeats.json")
    tap_downs = load(down_path)["taps_s"] if os.path.exists(down_path) else []
    down_ioi = median_ioi(tap_downs)
    beat_ioi = median_ioi(taps)
    meter, meter_note = derive_meter(down_ioi, beat_ioi)
    beats_quality = tap_quality(taps)
    downs_quality = tap_quality(tap_downs)
    if downs_quality["verdict"].startswith("IRREGULAR"):
        meter, meter_note = None, "downbeat pass too irregular to derive a meter"

    backends = {}
    for ref_path in sorted(glob.glob(os.path.join(REF, f"{track_id}.*.json"))):
        ref = load(ref_path)
        name = ref["backend"]
        # Compare only where Matt actually tapped.
        windowed = [b for b in ref["beats_s"] if span[0] - TOLERANCE_S <= b <= span[1] + TOLERANCE_S]
        f, precision, recall, matched = f_measure(taps, windowed)
        verdict, why = classify(tap_bpm, fitted_bpm(windowed), f)
        backends[name] = {
            "verdict": verdict, "why": why,
            "f_measure": round(f, 3), "precision": round(precision, 3),
            "recall": round(recall, 3), "matched": matched,
            "ref_bpm_in_span": round(fitted_bpm(windowed), 2),
            "ref_beats_full_track": len(ref["beats_s"]),
            "ref_downbeats_full_track": len(ref["downbeats_s"]),
        }

    confirming = [n for n, b in backends.items() if b["verdict"] == "AGREE"]
    if confirming:
        status = "confirmed"
    elif any(b["verdict"] == "METRICAL" for b in backends.values()):
        status = "metrical_review"
    else:
        status = "needs_arbitration"

    # Full-length extension: only from a backend that agreed on the tapped span.
    extended_by, beats_out, downbeats_out = None, taps, tap_downs
    if confirming:
        best = max(confirming, key=lambda n: backends[n]["f_measure"])
        ref = load(os.path.join(REF, f"{track_id}.{best}.json"))
        if len(ref["beats_s"]) > len(taps):
            extended_by, beats_out = best, ref["beats_s"]
            if ref["downbeats_s"]:
                downbeats_out = ref["downbeats_s"]

    return {
        "track_id": track_id, "suite": suite,
        "status": status,
        "tapped_span_s": [round(span[0], 2), round(span[1], 2)],
        "tap_count": len(taps), "tap_bpm": round(tap_bpm, 2),
        "tap_downbeat_count": len(tap_downs),
        "meter_from_taps": meter,
        "meter_note": meter_note,
        "beats_quality": beats_quality,
        "downbeats_quality": downs_quality,
        "phosphene_grid_bpm": PHOSPHENE_GRID.get(track_id),
        "backends": backends,
        "extended_by": extended_by,
        "beats_s": beats_out, "downbeats_s": downbeats_out,
        "source": "taps" if not extended_by else f"taps validated, extended by {extended_by}",
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tracks", default="")
    ap.add_argument("--report", default="")
    args = ap.parse_args()

    manifest = load(os.path.join(BB, "manifest.json"))
    wanted = {t.strip() for t in args.tracks.split(",") if t.strip()}
    os.makedirs(OUT, exist_ok=True)

    rows = []
    for entry in manifest["tracks"]:
        if wanted and entry["id"] not in wanted:
            continue
        result = reconcile_track(entry["id"], entry["suite"])
        if not result:
            continue
        rows.append(result)
        with open(os.path.join(OUT, f"{entry['id']}.groundtruth.json"), "w") as fh:
            json.dump(result, fh, indent=2, sort_keys=True)
            fh.write("\n")

    if not rows:
        print("no tapped tracks found", file=sys.stderr)
        return 1

    lines = []
    add = lines.append
    add(f"{'track':<20}{'suite':>5}{'tapped':>9}{'grid':>8}{'meter':>6}  {'status':<18}backends")
    add("-" * 108)
    for r in rows:
        backends = "  ".join(
            f"{n}:{b['verdict']}(F={b['f_measure']:.2f})" for n, b in sorted(r["backends"].items())
        )
        add(f"{r['track_id']:<20}{r['suite']:>5}{r['tap_bpm']:>9.2f}"
            f"{(r['phosphene_grid_bpm'] or 0):>8.1f}{str(r['meter_from_taps'] or '-'):>6}  "
            f"{r['status']:<18}{backends}")
    add("")
    for r in rows:
        if r["status"] == "confirmed":
            continue
        add(f"[{r['track_id']}] {r['status']}")
        for name, b in sorted(r["backends"].items()):
            add(f"    {name:<8} {b['verdict']:<9} {b['why']}  (ref {b['ref_bpm_in_span']} BPM in span)")
    report = "\n".join(lines)
    print(report)

    if args.report:
        os.makedirs(os.path.dirname(args.report), exist_ok=True)
        with open(args.report, "w") as fh:
            fh.write("# BeatBench GT.2 reconciliation — taps vs reference annotations\n\n")
            fh.write("Generated by `tools/beatbench/reconcile.py`. Taps are primary ground "
                     "truth; references cross-check them. See BEAT_SYNC_PROGRAM_PLAN.md §GT.2.\n\n")
            fh.write("```\n" + report + "\n```\n")
        print(f"\n→ {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

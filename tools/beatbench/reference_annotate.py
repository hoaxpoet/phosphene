#!/usr/bin/env python3
"""reference_annotate.py — independent reference beat/downbeat annotations (GT.2).

Produces a second opinion to reconcile against Matt's taps. Where taps and a
reference agree within 70 ms the result becomes BeatBench ground truth;
disagreements go to Matt to arbitrate by ear (BEAT_SYNC_PROGRAM_PLAN.md §GT.2).

WHY BEAT THIS! IS NOT A BACKEND HERE
------------------------------------
Beat This! is Phosphene's OWN grid model (`BeatGridAnalyzer` = BeatThisPreprocessor
+ BeatThisModel + BeatGridResolver, D-077). Scoring Phosphene's grid against a
Beat This! annotation would be circular — it measures "did we port the model
correctly" (already covered by the DSP.2 S8 layer-match tests), not "is the beat
right". Ground truth must come from outside that loop: human taps plus a
different algorithm family.

LICENSE (see the `reference-port` skill §1)
------------------------------------------
madmom and librosa run here as OFFLINE ANNOTATION TOOLS only. No madmom code and
no CC-NC madmom model weights ship in the product. Nothing this script touches is
linked into PhospheneEngine or PhospheneApp.

Backends, in order of authority:
  madmom  — RNN + DBN beat/downbeat tracking. A genuinely different algorithm
            family from Beat This!; handles odd meters via beats_per_bar.
  librosa — onset-envelope dynamic-programming beat tracking. Weaker (no downbeats,
            assumes near-constant tempo) but installs anywhere, so there is always
            at least one reference opinion.

Usage:
    tools/beatbench/.venv/bin/python tools/beatbench/reference_annotate.py
    ... --tracks bleed,take_five --backend madmom
    ... --list-backends
"""
import argparse
import json
import os
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEATBENCH = os.path.join(REPO, "PhospheneEngine", "Tests", "Fixtures", "beatbench")
MANIFEST = os.path.join(BEATBENCH, "manifest.json")
OUT_DIR = os.path.join(BEATBENCH, "reference")

# The plan's meter hypothesis set (BEAT_SYNC_PROGRAM_PLAN.md §DBN.1): {3,4,5,6,7,9,12}.
# Feeding the real candidate set is what lets the DBN find odd meters instead of
# forcing everything to 4 — and a candidate NOT in this list cannot be reported, so an
# under-specified list manufactures false confidence (an earlier [3,4,5,7] run made
# Pyramid Song read as a firm 7 simply because 8/12 were not offered).
BEATS_PER_BAR = [3, 4, 5, 6, 7, 9, 12]


# MARK: - backends

def madmom_available():
    # A broken madmom (numpy-ABI mismatch — see README) dumps a long numpy notice to
    # stderr on import. Probing availability should be quiet, so swallow it.
    import contextlib
    import io as _io
    try:
        with contextlib.redirect_stderr(_io.StringIO()):
            import madmom  # noqa: F401
        return True
    except Exception:
        return False


def madmom_annotate(path):
    """RNN activations → DBN tracking. Returns (beats, downbeats, meta)."""
    from madmom.features.beats import RNNBeatProcessor, DBNBeatTrackingProcessor
    from madmom.features.downbeats import (
        RNNDownBeatProcessor,
        DBNDownBeatTrackingProcessor,
    )
    beat_act = RNNBeatProcessor()(path)
    beats = DBNBeatTrackingProcessor(fps=100)(beat_act)

    down_act = RNNDownBeatProcessor()(path)
    tracked = DBNDownBeatTrackingProcessor(beats_per_bar=BEATS_PER_BAR, fps=100)(down_act)
    # tracked rows are [time, position_in_bar]; position 1 is the downbeat.
    downbeats = [float(t) for t, pos in tracked if int(pos) == 1]
    bar_positions = [int(pos) for _, pos in tracked]
    meter = max(bar_positions) if bar_positions else 0
    return (
        [float(b) for b in beats],
        downbeats,
        {"meter_estimate": meter, "beats_per_bar_candidates": BEATS_PER_BAR},
    )


def librosa_available():
    try:
        import librosa  # noqa: F401
        return True
    except Exception:
        return False


def librosa_annotate(path):
    """Onset-envelope DP beat tracking. No downbeats — returns [] for them."""
    import librosa
    y, sr = librosa.load(path, sr=None, mono=True)
    tempo, frames = librosa.beat.beat_track(y=y, sr=sr, units="frames")
    beats = librosa.frames_to_time(frames, sr=sr)
    tempo_value = float(tempo) if not hasattr(tempo, "__len__") else float(tempo[0])
    return (
        [float(b) for b in beats],
        [],
        {"tempo_estimate": tempo_value, "downbeats_supported": False},
    )


BACKENDS = {
    "madmom": {
        "available": madmom_available,
        "annotate": madmom_annotate,
        "independent": True,
        "note": "RNN + DBN; different algorithm family from Beat This!",
    },
    "librosa": {
        "available": librosa_available,
        "annotate": librosa_annotate,
        "independent": True,
        "note": "onset-envelope DP; no downbeats, assumes near-constant tempo",
    },
}


# MARK: - driver

def load_manifest():
    with open(MANIFEST) as fh:
        return json.load(fh)


def fixtures_dir():
    raw = os.environ.get("BEATBENCH_FIXTURES_DIR", "~/phosphene_beatbench_fixtures")
    return os.path.expanduser(raw)


def annotate_track(entry, backend_name, backend, base):
    filename = entry.get("filename")
    if not filename:
        return None, f"{entry['id']}: no filename in manifest"
    path = os.path.join(base, filename)
    if not os.path.isfile(path):
        return None, f"{entry['id']}: fixture missing at {path}"

    started = time.time()
    beats, downbeats, meta = backend["annotate"](path)
    payload = {
        "track_id": entry["id"],
        "suite": entry["suite"],
        "audio_file": filename,
        "backend": backend_name,
        "independent_of_phosphene": backend["independent"],
        "backend_note": backend["note"],
        "beat_count": len(beats),
        "downbeat_count": len(downbeats),
        "beats_s": beats,
        "downbeats_s": downbeats,
        "meta": meta,
        "elapsed_s": round(time.time() - started, 1),
    }
    out = os.path.join(OUT_DIR, f"{entry['id']}.{backend_name}.json")
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(out, "w") as fh:
        json.dump(payload, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return out, None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--backend", default="all", help="madmom | librosa | all")
    ap.add_argument("--tracks", default="", help="comma-separated track ids (default: all)")
    ap.add_argument("--list-backends", action="store_true")
    ap.add_argument("--force", action="store_true", help="re-annotate existing outputs")
    args = ap.parse_args()

    usable = {n: b for n, b in BACKENDS.items() if b["available"]()}
    if args.list_backends:
        for name, backend in BACKENDS.items():
            state = "available" if name in usable else "NOT INSTALLED"
            print(f"  {name:<8} {state:<14} {backend['note']}")
        return 0
    if not usable:
        print("no reference backend installed — see tools/beatbench/README.md", file=sys.stderr)
        return 1

    selected = usable if args.backend == "all" else {
        k: v for k, v in usable.items() if k == args.backend
    }
    if not selected:
        print(f"backend '{args.backend}' not available; have: {', '.join(usable)}", file=sys.stderr)
        return 1

    manifest = load_manifest()
    wanted = {t.strip() for t in args.tracks.split(",") if t.strip()}
    entries = [e for e in manifest["tracks"] if not wanted or e["id"] in wanted]
    base = fixtures_dir()

    failures = 0
    for backend_name, backend in selected.items():
        print(f"\n=== {backend_name} ({len(entries)} tracks) ===")
        for entry in entries:
            out = os.path.join(OUT_DIR, f"{entry['id']}.{backend_name}.json")
            if os.path.exists(out) and not args.force:
                print(f"  skip {entry['id']} (exists; --force to redo)")
                continue
            try:
                written, error = annotate_track(entry, backend_name, backend, base)
            except Exception as exc:  # a backend blowing up on one track must not stop the run
                written, error = None, f"{entry['id']}: {type(exc).__name__}: {exc}"
            if error:
                print(f"  FAIL {error}", file=sys.stderr)
                failures += 1
            else:
                payload = json.load(open(written))
                print(f"  ok   {entry['id']:<20} {payload['beat_count']:>5} beats  "
                      f"{payload['downbeat_count']:>4} downbeats  ({payload['elapsed_s']}s)")
    if failures:
        print(f"\n{failures} failure(s)", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

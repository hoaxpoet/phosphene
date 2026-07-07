#!/usr/bin/env python3
"""corpus_manifest.py — build, tag, and stratify the Phosphene corpus manifest.

CENSUS.1 tooling (see docs/ENGINEERING_PLAN.md §Phase CENSUS). Walks Matt's
music archive, filters corpus hygiene hazards (AppleDouble `._` resource
forks, FairPlay `.m4p`, incomplete `.part` downloads), and emits:

  scan   — manifest CSV: relpath, ext, size_bytes, artist, album
  tag    — enrich manifest rows with mutagen-read audio metadata
           (duration, bitrate, sample rate, genre, year, FLAC bit depth).
           Checkpointed + resumable: safe to re-run until `remaining=0`.
  pilot  — deterministic stratified pilot sample (default n=1000, seed=42)
           for the CENSUS.3 pilot census run.

Usage (macOS; paths shown for the default mount):
  python3 tools/corpus_manifest.py scan  --root "/Volumes/Extreme SSD" --manifest /tmp/corpus_manifest.csv
  python3 tools/corpus_manifest.py tag   --root "/Volumes/Extreme SSD" --manifest /tmp/corpus_manifest.csv
  python3 tools/corpus_manifest.py pilot --manifest /tmp/corpus_manifest.csv --out tools/data/corpus_pilot_1000.csv

Requires: mutagen (`pip install mutagen`). Stdlib otherwise.
"""

import argparse
import collections
import csv
import os
import random
import re
import sys
import time
import unicodedata
from concurrent.futures import ProcessPoolExecutor

AUDIO_EXTS = {".mp3", ".m4a", ".flac"}
EXCLUDED_DIR_PARTS = {".TemporaryItems", ".Trashes", "System Volume Information"}

FIELDS = [
    "relpath", "ext", "size_bytes", "artist", "album",
    "duration_s", "bitrate_kbps", "sample_rate_hz", "bit_depth",
    "genre_raw", "genre_bucket", "year", "decade", "tag_status",
]

# Free-text genre → census bucket. First match wins; order matters.
GENRE_RULES = [
    ("classical", ["classical", "baroque", "romantic era", "opera", "symph", "chamber", "piano sonata"]),
    ("jazz", ["jazz", "bebop", "swing", "big band", "bossa"]),
    ("hiphop", ["hip-hop", "hip hop", "rap", "grime"]),
    ("electronic", ["electronic", "electronica", "techno", "house", "idm", "ambient", "dance", "trip-hop",
                    "trip hop", "dubstep", "drum & bass", "dnb", "downtempo", "electro"]),
    ("folk_country", ["folk", "country", "bluegrass", "americana", "singer-songwriter", "singer/songwriter"]),
    ("soul_rnb", ["soul", "r&b", "rnb", "funk", "motown", "blues"]),
    ("pop", ["pop"]),
    ("rock_alt_indie", ["rock", "alternative", "punk", "indie", "shoegaze", "grunge", "metal", "psychedelic",
                        "post-", "emo", "new wave", "hardcore"]),
    ("world_latin", ["world", "latin", "reggae", "afro", "brazil"]),
    ("soundtrack", ["soundtrack", "score", "musical"]),
]


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c))


def genre_bucket(raw: str) -> str:
    if not raw:
        return "unknown"
    g = norm(raw)
    for bucket, keys in GENRE_RULES:
        if any(k in g for k in keys):
            return bucket
    return "other"


# MARK: - scan

def cmd_scan(args: argparse.Namespace) -> None:
    root = os.path.abspath(args.root)
    rows = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIR_PARTS]
        for name in filenames:
            if name.startswith("._"):
                continue  # AppleDouble resource fork — parses as corrupt audio
            ext = os.path.splitext(name)[1].lower()
            if ext not in AUDIO_EXTS:
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root)
            parts = rel.split(os.sep)
            artist = parts[1] if len(parts) >= 3 else ""
            album = parts[2] if len(parts) >= 4 else ""
            try:
                size = os.path.getsize(full)
            except OSError:
                continue
            rows.append({
                "relpath": rel, "ext": ext.lstrip("."), "size_bytes": size,
                "artist": artist, "album": album, "tag_status": "pending",
            })
    rows.sort(key=lambda r: r["relpath"])
    with open(args.manifest, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print(f"scan: {len(rows)} tracks -> {args.manifest}")


# MARK: - tag

def _read_tags(job):
    """Worker: (relpath, fullpath) -> dict of tag fields."""
    relpath, full = job
    out = {"relpath": relpath, "tag_status": "ok"}
    try:
        import mutagen
        f = mutagen.File(full, easy=True)
        if f is None:
            out["tag_status"] = "unreadable"
            return out
        info = f.info
        out["duration_s"] = f"{getattr(info, 'length', 0.0):.2f}"
        br = getattr(info, "bitrate", 0) or 0
        out["bitrate_kbps"] = str(br // 1000)
        out["sample_rate_hz"] = str(getattr(info, "sample_rate", 0) or 0)
        out["bit_depth"] = str(getattr(info, "bits_per_sample", "") or "")
        tags = f.tags or {}
        g = tags.get("genre")
        raw = (g[0] if g else "").strip()
        out["genre_raw"] = raw[:60]
        out["genre_bucket"] = genre_bucket(raw)
        y = tags.get("date") or tags.get("year")
        year = ""
        if y:
            m = re.match(r"(\d{4})", str(y[0]))
            if m:
                year = m.group(1)
        out["year"] = year
        out["decade"] = str((int(year) // 10) * 10) if year else ""
    except Exception:
        out["tag_status"] = "error"
    return out


def cmd_tag(args: argparse.Namespace) -> None:
    root = os.path.abspath(args.root)
    with open(args.manifest, newline="") as f:
        rows = list(csv.DictReader(f))
    by_rel = {r["relpath"]: r for r in rows}
    pending = [r["relpath"] for r in rows if r["tag_status"] == "pending"]
    if not pending:
        print("tag: remaining=0 (complete)")
        return
    deadline = time.monotonic() + args.time_budget
    jobs = [(rel, os.path.join(root, rel)) for rel in pending]
    done = 0
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        for res in pool.map(_read_tags, jobs, chunksize=32):
            by_rel[res["relpath"]].update(res)
            done += 1
            if time.monotonic() > deadline:
                break
    with open(args.manifest, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        for r in rows:
            w.writerow(r)
    remaining = sum(1 for r in rows if r["tag_status"] == "pending")
    print(f"tag: processed {done} this pass, remaining={remaining}")


# MARK: - pilot

def cmd_pilot(args: argparse.Namespace) -> None:
    with open(args.manifest, newline="") as f:
        rows = [r for r in csv.DictReader(f) if r["tag_status"] == "ok"]
    rng = random.Random(args.seed)

    def dur(r):
        try:
            return float(r["duration_s"])
        except ValueError:
            return 0.0

    picked: dict[str, dict] = {}

    def take(pool, n, label):
        pool = [r for r in pool if r["relpath"] not in picked]
        for r in rng.sample(pool, min(n, len(pool))):
            r = dict(r)
            r["stratum"] = label
            picked[r["relpath"]] = r

    # Targeted strata first (the census's stated blind spots), then
    # proportional fill by genre_bucket × decade.
    take([r for r in rows if r["genre_bucket"] == "jazz"], 80, "jazz_swing")
    take([r for r in rows if r["genre_bucket"] == "classical"], 40, "classical_rubato")
    take([r for r in rows if dur(r) > 480], 60, "long_form")
    take([r for r in rows if r["sample_rate_hz"] not in ("44100", "0")], 40, "nonstandard_rate")
    take([r for r in rows if r["ext"] == "flac"], 60, "flac")

    remaining = args.n - len(picked)
    cells = collections.defaultdict(list)
    for r in rows:
        if r["relpath"] not in picked:
            cells[(r["genre_bucket"], r["decade"])].append(r)
    total = sum(len(v) for v in cells.values())
    # Largest-remainder proportional allocation with a floor of 1.
    alloc = {}
    for key, pool in sorted(cells.items()):
        alloc[key] = max(1, round(remaining * len(pool) / total)) if pool else 0
    for key in sorted(alloc, key=lambda k: -alloc[k]):
        if sum(min(alloc[k], len(cells[k])) for k in alloc) <= remaining:
            break
        alloc[key] = max(1, alloc[key] - 1)
    for key, pool in sorted(cells.items()):
        take(pool, alloc[key], f"prop_{key[0]}_{key[1] or 'nodate'}")

    out_rows = sorted(picked.values(), key=lambda r: r["relpath"])[: args.n]
    with open(args.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS + ["stratum"])
        w.writeheader()
        for r in out_rows:
            w.writerow(r)
    counts = collections.Counter(r["stratum"].split("_")[0] for r in out_rows)
    print(f"pilot: {len(out_rows)} tracks -> {args.out}; strata heads: {dict(counts)}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    ps = sub.add_parser("scan"); ps.add_argument("--root", required=True); ps.add_argument("--manifest", required=True); ps.set_defaults(fn=cmd_scan)
    pt = sub.add_parser("tag"); pt.add_argument("--root", required=True); pt.add_argument("--manifest", required=True)
    pt.add_argument("--workers", type=int, default=8); pt.add_argument("--time-budget", type=float, default=38.0); pt.set_defaults(fn=cmd_tag)
    pp = sub.add_parser("pilot"); pp.add_argument("--manifest", required=True); pp.add_argument("--out", required=True)
    pp.add_argument("--n", type=int, default=1000); pp.add_argument("--seed", type=int, default=42); pp.set_defaults(fn=cmd_pilot)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()

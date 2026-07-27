#!/usr/bin/env python3
"""beatbench_find_fixtures.py — locate the BeatBench suite tracks in the corpus.

The beat-sync program (D-202) needs 12 new full-length tracks as BeatBench
fixtures (BEAT_SYNC_PROGRAM_PLAN.md §1). Most are expected to already live in
the 27,639-track corpus. This searches the committed corpus manifest
(tools/data/corpus_manifest.csv.gz) for each target by title-in-path + artist
and prints candidate relpaths (under the corpus root, e.g. /Volumes/Extreme SSD)
so they can be copied into BEATBENCH_FIXTURES_DIR (~/phosphene_beatbench_fixtures/).

ponytail: substring matcher over the committed manifest, no deps beyond stdlib.
Ceiling: title/artist collisions over-match; the human picks the right row.

Usage: python3 tools/beatbench_find_fixtures.py
"""
import csv
import gzip
import os
import sys

MANIFEST = os.path.join(os.path.dirname(__file__), "data", "corpus_manifest.csv.gz")

# (id, title-keyword, artist-keyword, suite) — keywords are lowercased substrings.
TARGETS = [
    ("billie_jean",       "billie jean",     "michael jackson", 1),
    ("around_the_world",  "around the world", "daft punk",       1),
    ("stayin_alive",      "stayin",          "bee gees",        1),
    ("superstition",      "superstition",    "stevie wonder",   1),
    ("take_five",         "take five",       "brubeck",         2),
    ("solsbury_hill",     "solsbury",        "peter gabriel",   2),
    ("bohemian_rhapsody", "bohemian",        "queen",           3),
    ("giorgio_by_moroder","giorgio",         "daft punk",       3),
    ("dance_yrself_clean","dance yrself",    "lcd soundsystem", 3),
    ("bleed",             "bleed",           "meshuggah",       4),
    ("girl_from_ipanema", "ipanema",         "getz",            5),
    ("clair_de_lune",     "clair de lune",   "debussy",         5),
]


def load_rows(path):
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
        return list(csv.DictReader(fh))


def find(rows, title_kw, artist_kw):
    hits = []
    for r in rows:
        relpath = (r.get("relpath") or "").lower()
        artist = (r.get("artist") or "").lower()
        if title_kw in relpath and (artist_kw in artist or artist_kw in relpath):
            hits.append(r)
    return hits


def main():
    if not os.path.exists(MANIFEST):
        sys.exit(f"corpus manifest not found: {MANIFEST}")
    rows = load_rows(MANIFEST)
    found, missing = 0, []
    for tid, title_kw, artist_kw, suite in TARGETS:
        hits = find(rows, title_kw, artist_kw)
        print(f"\n[{tid}] suite {suite} — \"{title_kw}\" / {artist_kw}")
        if not hits:
            print("    NO MATCH — source manually")
            missing.append(tid)
            continue
        found += 1
        for r in hits[:6]:
            print(f"    {r['duration_s']:>7}s  {r['ext']:<4}  {r['relpath']}")
        if len(hits) > 6:
            print(f"    … +{len(hits) - 6} more")
    print(f"\n{found}/{len(TARGETS)} targets have at least one candidate; "
          f"missing: {', '.join(missing) if missing else 'none'}")


if __name__ == "__main__":
    main()

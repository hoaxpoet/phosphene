#!/usr/bin/env python3
"""beatbench_manifest.py — (re)generate the committed BeatBench fixture manifest.

The BeatBench suite tracks (BEAT_SYNC_PROGRAM_PLAN.md §1) are full-length,
copyrighted, and live OUTSIDE the repo at BEATBENCH_FIXTURES_DIR
(~/phosphene_beatbench_fixtures by default). What ships in the repo is this
manifest — per-track sha256 + duration — so a presence gate can verify a
fixture dir has the exact expected audio (a re-encode changes the hash).

Local-source tracks present in the dir get their sha256 + duration_s filled;
tap-backfill tracks (not yet acquired from a recorded session) stay pending.
Deterministic: same files in → same manifest out.

ponytail: sha256 via hashlib, duration via macOS `afinfo` (no third-party dep).

Usage: python3 tools/beatbench_manifest.py [fixtures_dir]
  fixtures_dir default: $BEATBENCH_FIXTURES_DIR or ~/phosphene_beatbench_fixtures
Writes: PhospheneEngine/Tests/Fixtures/beatbench/manifest.json
"""
import hashlib
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "PhospheneEngine", "Tests", "Fixtures", "beatbench", "manifest.json")

# tap-derived fixtures were segmented from this recorded session's raw_tap.wav.
SOURCE_SESSION = "2026-07-27T12-58-56Z"

# id, title, artist, suite, source(local=corpus rip | tap=segmented from session), filename
TRACKS = [
    ("billie_jean",        "Billie Jean",          "Michael Jackson",         1, "local", "billie_jean.mp3"),
    ("around_the_world",   "Around the World",     "Daft Punk (Alive 2007)",  1, "local", "around_the_world.mp3"),
    ("stayin_alive",       "Stayin' Alive",        "Bee Gees",                1, "local", "stayin_alive.mp3"),
    ("superstition",       "Superstition",         "Stevie Wonder",           1, "local", "superstition.flac"),
    ("take_five",          "Take Five",            "The Dave Brubeck Quartet",2, "local", "take_five.mp3"),
    ("solsbury_hill",      "Solsbury Hill",        "Peter Gabriel",           2, "tap",   "solsbury_hill.wav"),
    ("yyz",                "YYZ",                  "Rush",                    2, "tap",   "yyz.wav"),
    ("bohemian_rhapsody",  "Bohemian Rhapsody",    "Queen",                   3, "tap",   "bohemian_rhapsody.wav"),
    ("giorgio_by_moroder", "Giorgio by Moroder",   "Daft Punk",               3, "local", "giorgio_by_moroder.mp3"),
    ("dance_yrself_clean", "Dance Yrself Clean",   "LCD Soundsystem",         3, "local", "dance_yrself_clean.mp3"),
    ("bleed",              "Bleed",                "Meshuggah",               4, "tap",   "bleed.wav"),
    ("girl_from_ipanema",  "The Girl from Ipanema","Getz/Gilberto",           5, "local", "girl_from_ipanema.mp3"),
    ("clair_de_lune",      "Clair de Lune",        "Debussy (Weissenberg)",   5, "local", "clair_de_lune.mp3"),
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def duration_s(path):
    out = subprocess.run(["afinfo", path], capture_output=True, text=True).stdout
    m = re.search(r"estimated duration:\s*([0-9.]+)\s*sec", out)
    return round(float(m.group(1)), 2) if m else None


def main():
    fixtures = (sys.argv[1] if len(sys.argv) > 1
                else os.environ.get("BEATBENCH_FIXTURES_DIR")
                or os.path.expanduser("~/phosphene_beatbench_fixtures"))
    entries, present, missing = [], 0, 0
    for tid, title, artist, suite, source, filename in TRACKS:
        e = {"id": tid, "title": title, "artist": artist, "suite": suite,
             "source": source, "filename": filename}
        if source == "tap":
            e["source_session"] = SOURCE_SESSION
        path = os.path.join(fixtures, filename)
        if os.path.isfile(path):
            e["sha256"] = sha256(path)
            e["duration_s"] = duration_s(path)
            present += 1
        else:
            e["sha256"] = None
            e["duration_s"] = None
            missing += 1
            print(f"  fixture absent: {filename}", file=sys.stderr)
        entries.append(e)

    manifest = {
        "_doc": "BeatBench fixture manifest (GT.1). Audio lives at BEATBENCH_FIXTURES_DIR, "
                "not in the repo. Regenerate with tools/beatbench_manifest.py. "
                "sha256 pins exact bytes; a re-encode changes it.",
        "fixtures_env": "BEATBENCH_FIXTURES_DIR",
        "tracks": entries,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        json.dump(manifest, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print(f"wrote {OUT}: {present} hashed, {missing} missing, {len(entries)} total")


if __name__ == "__main__":
    main()

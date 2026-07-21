#!/usr/bin/env python3
"""Build a capability-spanning test playlist from the census results.

Selects a small, diverse set of local tracks that exercises Phosphene's
audio-reactive dimensions (mood quadrant, tempo, beat-lock vs rubato/swing,
tonal clarity) AND the local-file decode edge cases that surface defects
(non-44.1 kHz, long-form, short, low-bitrate rips, high-bit-depth/FLAC).

Input is the already-computed census (no re-analysis): full_results.csv joined
to the corpus manifest on relpath. Output is an .m3u (absolute paths) plus a
coverage sheet naming what each pick exercises — the defect-detection checklist.

ponytail: stdlib only, deterministic stratified pick. Not farthest-point
sampling — buckets + must-cover edge cases is enough for a test asset; upgrade
to diversity sampling only if a bucket picks feel too samey.
"""
import argparse, csv, os, random, sys
from collections import defaultdict


def _f(row, key):
    v = row.get(key, "")
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def load(census_path, manifest_path):
    man = {}
    with open(manifest_path, newline="") as fh:
        for r in csv.DictReader(fh):
            man[r["relpath"]] = r
    rows = []
    with open(census_path, newline="") as fh:
        for r in csv.DictReader(fh):
            if r.get("error"):  # unreadable/failed row
                continue
            r["_man"] = man.get(r["relpath"], {})
            rows.append(r)
    return rows


def mood_quadrant(row):
    v, a = _f(row, "valence"), _f(row, "arousal")
    if v is None or a is None:
        return None
    return ("hi-val" if v >= 0 else "lo-val") + "/" + ("hi-aro" if a >= 0 else "lo-aro")


def tempo_bin(row):
    bpm = _f(row, "grid_bpm") or _f(row, "mir_bpm")
    if not bpm:
        return None
    return "slow" if bpm < 90 else "mid" if bpm < 130 else "fast"


def key_conf(row):
    mr, nr = _f(row, "key_major_r"), _f(row, "key_minor_r")
    vals = [x for x in (mr, nr) if x is not None]
    return max(vals) if vals else None


# Capability tags: a track can carry several. Selection covers every tag.
def capability_tags(row):
    tags = []
    q = mood_quadrant(row)
    if q:
        tags.append("mood:" + q)
    t = tempo_bin(row)
    if t:
        tags.append("tempo:" + t)
    if (row.get("beat_irregular") or "").strip() in ("1", "True", "true"):
        tags.append("beat:irregular")
    else:
        fd = _f(row, "folded_disagreement")
        if fd is not None:
            tags.append("beat:regular")
    kc = key_conf(row)
    if kc is not None:
        tags.append("tonal:strong-key" if kc >= 0.6 else "tonal:ambiguous")
    g = (row["_man"].get("genre_bucket") or "").strip()
    if g:
        tags.append("genre:" + g)
    return tags


# Decode edge cases that stress the local-file path (defect surface).
def edge_tags(row):
    man = row["_man"]
    tags = []
    dur = _f(row, "duration_s")
    if dur is not None and dur > 480:
        tags.append("edge:long-form")
    if dur is not None and dur < 90:
        tags.append("edge:short")
    rate = _f(row, "native_rate") or _f(man, "sample_rate_hz")
    if rate and abs(rate - 44100) > 1:
        tags.append("edge:non-44k")
    br = _f(man, "bitrate_kbps")
    if br is not None and br < 128:
        tags.append("edge:low-bitrate")
    bd = _f(man, "bit_depth")
    if (man.get("ext") or "").lower() == "flac" or (bd is not None and bd >= 24):
        tags.append("edge:hi-res")
    return tags


def select(rows, size, seed):
    rnd = random.Random(seed)
    rnd.shuffle(rows)
    picked, picked_paths, artists = [], set(), set()
    covered = defaultdict(int)

    def take(row, why):
        if row["relpath"] in picked_paths:
            return False
        art = (row["_man"].get("artist") or "").strip().lower()
        if art and art in artists and len(picked) < size - 5:
            return False  # spread artists until we're nearly full
        picked.append((row, why))
        picked_paths.add(row["relpath"])
        if art:
            artists.add(art)
        for tag in why:
            covered[tag] += 1
        return True

    # Pass 1: guarantee at least one track per edge case (defect surface first).
    all_edges = sorted({t for r in rows for t in edge_tags(r)})
    for edge in all_edges:
        for r in rows:
            if edge in edge_tags(r) and take(r, capability_tags(r) + edge_tags(r)):
                break

    # Pass 2: cover every capability tag twice, reactive axes first so a small
    # budget is spent on mood/tempo/beat/tonal before genre breadth.
    prio = {"mood": 0, "tempo": 1, "beat": 2, "tonal": 3, "genre": 4}
    all_caps = sorted({t for r in rows for t in capability_tags(r)},
                      key=lambda t: (prio.get(t.split(":")[0], 9), t))
    for cap in all_caps:
        while covered[cap] < 2 and len(picked) < size:
            for r in rows:
                if cap in capability_tags(r) and take(r, capability_tags(r) + edge_tags(r)):
                    break
            else:
                break

    # Pass 3: fill to size with the rarest-covered tags (widen the spread).
    for r in rows:
        if len(picked) >= size:
            break
        why = capability_tags(r) + edge_tags(r)
        if why and any(covered[t] < 3 for t in why):
            take(r, why)

    return picked, covered


def write_outputs(picked, root, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    m3u = os.path.join(out_dir, "test_playlist.m3u")
    sheet = os.path.join(out_dir, "test_playlist_coverage.csv")
    with open(m3u, "w") as fh:
        fh.write("#EXTM3U\n")
        for row, _why in picked:
            man = row["_man"]
            dur = int(_f(row, "duration_s") or 0)
            label = f"{man.get('artist','?')} - {os.path.basename(row['relpath'])}"
            fh.write(f"#EXTINF:{dur},{label}\n{os.path.join(root, row['relpath'])}\n")
    with open(sheet, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["relpath", "artist", "genre", "bpm", "valence", "arousal",
                    "key", "exercises"])
        for row, why in picked:
            man = row["_man"]
            w.writerow([row["relpath"], man.get("artist", ""),
                        man.get("genre_bucket", ""),
                        row.get("grid_bpm", ""), row.get("valence", ""),
                        row.get("arousal", ""), row.get("key_class", ""),
                        " ".join(sorted(why))])
    return m3u, sheet


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--census", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--root", required=True, help="absolute prefix for relpaths")
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", type=int, default=50)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()

    rows = load(a.census, a.manifest)
    picked, covered = select(rows, a.size, a.seed)

    # ponytail self-check: the point of the playlist is coverage — assert it.
    quads = {t for _, why in picked for t in why if t.startswith("mood:")}
    assert len(quads) >= 4, f"missing mood quadrants: only {quads}"
    edges = {t for _, why in picked for t in why if t.startswith("edge:")}
    assert len(edges) >= 3, f"too few decode edge cases: {edges}"

    m3u, sheet = write_outputs(picked, a.root, a.out)
    print(f"selected {len(picked)} / {len(rows)} readable tracks")
    print(f"playlist: {m3u}\ncoverage: {sheet}\n")
    print("coverage (tag: count):")
    for tag in sorted(covered):
        print(f"  {tag}: {covered[tag]}")


if __name__ == "__main__":
    main()

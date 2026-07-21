#!/usr/bin/env python3
"""Analyze the Tunes Club catalog + bridge it to the census.

Three products, cheapest first:
  1. Structural profiles — per-curator and per-instance stats from the sheet
     alone (no audio): sets, tracks, set lengths, participation timeline.
  2. Archive match rate — how much of the catalog was already analyzed in the
     census (the sourcing inventory + the §9.5b 72%/24% stat, refined).
  3. Set arcs + human-vs-shuffle test — for sets whose tracks matched the
     census, the valence/arousal/tempo trajectory, and whether the human
     ordering is smoother than random shuffles of the same tracks (§9.5a).

Match is a lazy normalized artist + title-in-filename join, not a fingerprint.
ponytail: string match with a reported yield; upgrade to fpcalc only if the
yield is too low to trust the arcs.
"""
import argparse, csv, itertools, os, random, re, sys
from collections import defaultdict

csv.field_size_limit(1 << 20)


def norm(s):
    s = (s or "").lower()
    s = re.sub(r"\(.*?\)|\[.*?\]", " ", s)          # drop parentheticals
    s = re.sub(r"\bfeat\.?\b.*|\bft\.?\b.*", " ", s)  # drop featured-artist tail
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    s = re.sub(r"^the ", "", s)
    return re.sub(r"\s+", " ", s).strip()


def primary_artist(a):
    # collaborations: take the first credited artist
    return norm(re.split(r",|&|/| x | vs\.? |\+", a or "")[0])


def secs(length):
    m = re.match(r"\s*(\d+):(\d+)", length or "")
    return int(m.group(1)) * 60 + int(m.group(2)) if m else None


def load_catalog(path):
    with open(path, newline="") as fh:
        return [r for r in csv.DictReader(fh) if (r.get("Track Artist") or "").strip()]


def load_census(census_path, manifest_path):
    census = {}
    with open(census_path, newline="") as fh:
        for r in csv.DictReader(fh):
            if not r.get("error"):
                census[r["relpath"]] = r
    by_artist = defaultdict(list)   # norm primary artist -> [(relpath, norm filename)]
    with open(manifest_path, newline="") as fh:
        for r in csv.DictReader(fh):
            rp = r["relpath"]
            fn = norm(os.path.splitext(os.path.basename(rp))[0])
            by_artist[primary_artist(r.get("artist"))].append((rp, fn))
            # filename often carries the real artist too; index by that as backup
    return census, by_artist


def match_track(row, census, by_artist):
    art = primary_artist(row["Track Artist"])
    if not art or art not in by_artist:
        return None, False  # artist not in archive at all
    title_tokens = [t for t in norm(row["Track Name"]).split() if len(t) > 2]
    best = None
    for rp, fn in by_artist[art]:
        if title_tokens and all(t in fn for t in title_tokens):
            best = rp
            break
    if best is None:
        return None, True   # artist present, track not found (version/sourcing gap)
    return census.get(best), True


def bpm(feat):
    for k in ("grid_bpm", "mir_bpm"):
        try:
            v = float(feat.get(k, ""))
            if v > 0:
                return v
        except (TypeError, ValueError):
            pass
    return None


def fval(feat, key):
    try:
        return float(feat.get(key, ""))
    except (TypeError, ValueError):
        return None


def path_cost(series):
    """Total absolute step size along a sequence — lower = smoother arc."""
    return sum(abs(series[i] - series[i - 1]) for i in range(1, len(series)))


def shuffle_ratio(series, seed, trials=300):
    """Human path cost / mean random-permutation cost. <1 => human is smoother."""
    human = path_cost(series)
    rnd = random.Random(seed)
    if len(series) <= 2:
        return None
    if len(series) <= 7:  # exhaustive when cheap
        perms = list(itertools.permutations(series))
        costs = [path_cost(p) for p in perms]
    else:
        costs = []
        for _ in range(trials):
            p = series[:]
            rnd.shuffle(p)
            costs.append(path_cost(p))
    mean = sum(costs) / len(costs)
    return human / mean if mean else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--census", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()

    rows = load_catalog(a.catalog)
    census, by_artist = load_census(a.census, a.manifest)

    # --- 1. Structural profiles -------------------------------------------
    curators = defaultdict(lambda: {"tracks": 0, "sets": set(), "instances": set(),
                                    "dur": 0, "durn": 0})
    sets = defaultdict(list)  # (instance, set#, creator) -> rows (ordered)
    for r in rows:
        c = r["Set Creator"].strip()
        cur = curators[c]
        cur["tracks"] += 1
        cur["sets"].add((r["Instance"], r["Set #"]))
        cur["instances"].add(r["Instance"])
        d = secs(r["Track Length"])
        if d:
            cur["dur"] += d
            cur["durn"] += 1
        sets[(r["Instance"], r["Set #"], c)].append(r)

    print(f"# Tunes Club catalog analysis\n\n{len(rows)} tracks · "
          f"{len({r['Instance'] for r in rows})} instances · "
          f"{len(sets)} sets · {len(curators)} curators\n")
    print("## Curator profiles\n")
    print(f"{'curator':18} {'instances':>9} {'sets':>5} {'tracks':>7} "
          f"{'avg/set':>8} {'avg trk':>8}")
    for c, d in sorted(curators.items(), key=lambda kv: -kv[1]["tracks"]):
        avg_set = d["tracks"] / len(d["sets"]) if d["sets"] else 0
        avg_trk = d["dur"] / d["durn"] if d["durn"] else 0
        print(f"{c[:18]:18} {len(d['instances']):>9} {len(d['sets']):>5} "
              f"{d['tracks']:>7} {avg_set:>8.1f} {avg_trk/60:>7.1f}m")

    # --- 2. Archive match rate --------------------------------------------
    per_cur = defaultdict(lambda: [0, 0, 0])  # curator -> [tracks, artist_in, track_matched]
    matched_feats = {}  # (instance,set,creator,track#) -> feat row
    for r in rows:
        feat, artist_in = match_track(r, census, by_artist)
        pc = per_cur[r["Set Creator"].strip()]
        pc[0] += 1
        pc[1] += 1 if artist_in else 0
        if feat is not None:
            pc[2] += 1
            matched_feats[(r["Instance"], r["Set #"], r["Set Creator"], r["Set Track #"])] = feat
    tot = [sum(x) for x in zip(*per_cur.values())]
    print("\n## Archive coverage (already-censused)\n")
    print(f"{'curator':18} {'artist-in %':>11} {'track-matched %':>15}")
    for c, (n, ai, tm) in sorted(per_cur.items(), key=lambda kv: -kv[1][0]):
        print(f"{c[:18]:18} {100*ai/n:>10.0f}% {100*tm/n:>14.0f}%")
    print(f"{'TOTAL':18} {100*tot[1]/tot[0]:>10.0f}% {100*tot[2]/tot[0]:>14.0f}%")

    # --- 3. Set arcs + human-vs-shuffle -----------------------------------
    print("\n## Set arcs (human ordering vs shuffle; ratio <1.0 = human smoother)\n")
    print(f"{'set':38} {'matched':>7} {'aro ratio':>9} {'tempo ratio':>11}")
    ratios = defaultdict(list)
    for key, srows in sorted(sets.items()):
        srows = sorted(srows, key=lambda r: int(r["Set Track #"] or 0))
        aro, tempo = [], []
        for r in srows:
            f = matched_feats.get((r["Instance"], r["Set #"], r["Set Creator"],
                                   r["Set Track #"]))
            if f:
                av = fval(f, "arousal")
                bp = bpm(f)
                if av is not None:
                    aro.append(av)
                if bp is not None:
                    tempo.append(bp)
        n = len(srows)
        if len(aro) < 4:  # too few matched to judge an arc
            continue
        ar = shuffle_ratio(aro, a.seed)
        tr = shuffle_ratio(tempo, a.seed + 1) if len(tempo) >= 4 else None
        label = f"{key[0]} s{key[1]} {key[2]}"[:38]
        print(f"{label:38} {len(aro):>3}/{n:<3} "
              f"{ar if ar else float('nan'):>9.2f} "
              f"{(tr if tr else float('nan')):>11.2f}")
        if ar:
            ratios["arousal"].append(ar)
        if tr:
            ratios["tempo"].append(tr)

    print("\n## Human-vs-shuffle summary\n")
    for dim, rs in ratios.items():
        if rs:
            below = sum(1 for x in rs if x < 1.0)
            print(f"  {dim}: {len(rs)} sets judged · mean ratio {sum(rs)/len(rs):.2f} "
                  f"· {below}/{len(rs)} smoother-than-random ({100*below/len(rs):.0f}%)")

    # ponytail self-check: the join has to actually fire, else the arcs are empty
    assert tot[1] > 0, "no artist matched the archive — normalization is broken"
    assert matched_feats, "no track-level census matches — arc section is vacuous"


if __name__ == "__main__":
    main()

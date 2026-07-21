#!/usr/bin/env python3
"""Resolve the Tunes Club Spotify playlists to canonical track lists.

Spotify's API previews are deprecated and PKCE gives us no app token, but the
public embed page (open.spotify.com/embed/playlist/<id>) server-renders a
__NEXT_DATA__ JSON blob with the full ordered trackList (title, artist,
duration, track URI). We parse that — no auth, no audio, just the canonical
listing.

Then reconcile three sources:
  - this Spotify resolution (the audio-available, ordered show)
  - tunes_club.csv (the definitive full catalog, incl. non-Spotify tracks)
  - the census (which tracks already have Phosphene features, from the old lib)

Output: spotify_tracklists.csv + a coverage summary. ponytail: stdlib only,
recursive JSON walk to find trackList so we don't hard-code Spotify's shape.
"""
import csv, json, os, re, sys, time, urllib.request
from collections import defaultdict

PLAYLISTS = [
    ("TC 1", "5iUVb4iWmPD4Em3CzSVHFS"), ("TC 2", "41WwG8gjmQhyJrWXFsuX2a"),
    ("TC 3", "76ApZg8pcsj5plXLQK6w1Y"), ("TC 4", "09cPBJkH2JcaQdyMe45qE6"),
    ("TC 5", "7kl09N8y5JkjGmQlKrBc2v"), ("TC 6", "3crnyi1dBYqmXPlPZCVGBj"),
    ("TC 7", "0qhDwVpmCZB1UgvWQVdTqt"), ("TC 8", "3Kb80Xg2Ikq0DlP06zpdaM"),
    ("TC 9", "1DRK1qoRDinQZ8uUzvwibJ"), ("TC 10", "51EU6A4zXULN9AbIwj81Vg"),
    ("TC 11", "6MrbmCGVpNsapuEZyNVjxt"), ("TC 12", "3H1PI6qvyUH4koJReGqcJ9"),
    ("TC 13", "5zZYMOfke8zrmzeuxJ1JGp"), ("TC 14", "4Sn4hjG65vZ7t3mmr1iNCQ"),
    ("TC 15", "3Q4use7HFM0TVhEvCW13Gd"), ("TC 16", "4i7sGOqArdZuJcAAEJ9kAE"),
    ("TC 17", "615AY8MFp4tiDE5Rz4ZU7K"), ("TC 18", "6kMvV1oTB7WjLdSXT2EOPY"),
    ("TC 19", "2uC3o1kxyB0SDtoWu4acWX"), ("TC 20", "7GRAM1rw1GRQUmRZ7XHP8D"),
    ("TC 21", "4IWsU8dBYCVgL0xlnwshDv"), ("TC 22", "4kkxyamZyihxKN9njHSStd"),
    ("TC 23", "5Pyk5qkqrse6Q3OAlrkiLd"), ("TC 24", "2bzq72HqhpkHkXZsh1a8AS"),
    ("TC 25", "1Or6IwzIvloJoVvdry9GJV"), ("TC 26", "4JLMNYqToApsIsV1LoBtAh"),
    ("TC 27", "1JB52XioezmFYyWJcKxQVk"), ("TC 28", "4iY7mt65bJL61H3x9tKTFG"),
    ("TC 29", "4O0LIYH5LV34EDOvHnd0Sy"),
]
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
NEXT = re.compile(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', re.S)


def find_tracklist(node):
    """Recursively locate the first list of track dicts (have uri + title)."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "trackList" and isinstance(v, list) and v:
                return v
            hit = find_tracklist(v)
            if hit:
                return hit
    elif isinstance(node, list):
        for v in node:
            hit = find_tracklist(v)
            if hit:
                return hit
    return None


def resolve(pid):
    url = f"https://open.spotify.com/embed/playlist/{pid}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        html = r.read().decode("utf-8", "replace")
    m = NEXT.search(html)
    if not m:
        return []
    tl = find_tracklist(json.loads(m.group(1))) or []
    out = []
    for t in tl:
        uri = t.get("uri", "")
        tid = uri.split(":")[-1] if uri else ""
        artists = t.get("subtitle", "")
        if isinstance(artists, list):
            artists = ", ".join(a.get("name", "") for a in artists)
        dur = t.get("duration", 0)
        out.append({"id": tid, "artist": artists, "title": t.get("title", ""),
                    "duration_s": round(dur / 1000) if dur else ""})
    return out


# --- census match (reused shape from tunes_club_analyze) --------------------
def norm(s):
    s = re.sub(r"\(.*?\)|\[.*?\]", " ", (s or "").lower())
    s = re.sub(r"[^a-z0-9 ]", " ", re.sub(r"\bfeat\.?\b.*|\bft\.?\b.*", " ", s))
    return re.sub(r"\s+", " ", re.sub(r"^the ", "", s)).strip()


def load_archive(census_path, manifest_path):
    census = {}
    if os.path.exists(census_path):
        with open(census_path, newline="") as fh:
            for r in csv.DictReader(fh):
                if not r.get("error"):
                    census[r["relpath"]] = r
    by_artist = defaultdict(list)
    if os.path.exists(manifest_path):
        with open(manifest_path, newline="") as fh:
            for r in csv.DictReader(fh):
                a = norm(re.split(r",|&|/| x |\+", r.get("artist", ""))[0])
                fn = norm(os.path.splitext(os.path.basename(r["relpath"]))[0])
                by_artist[a].append(fn)
    return census, by_artist


def in_archive(track, by_artist):
    a = norm(re.split(r",|&|/| x |\+", track["artist"])[0])
    if a not in by_artist:
        return False
    toks = [t for t in norm(track["title"]).split() if len(t) > 2]
    return any(toks and all(t in fn for t in toks) for fn in by_artist[a])


def main():
    census_path = sys.argv[1] if len(sys.argv) > 1 else ""
    manifest_path = sys.argv[2] if len(sys.argv) > 2 else ""
    out = sys.argv[3] if len(sys.argv) > 3 else "spotify_tracklists.csv"
    _, by_artist = load_archive(census_path, manifest_path)

    # catalog counts per instance (definitive doc)
    cat = defaultdict(int)
    if os.path.exists("tunes_club.csv"):
        with open("tunes_club.csv", newline="") as fh:
            for r in csv.DictReader(fh):
                if (r.get("Track Artist") or "").strip():
                    cat[r["Instance"].split(" (")[0].strip()] += 1

    rows, per_inst = [], {}
    for inst, pid in PLAYLISTS:
        try:
            tracks = resolve(pid)
        except Exception as e:  # network / parse — report, don't die
            print(f"  {inst}: FAILED ({e})", file=sys.stderr)
            tracks = []
        matched = sum(1 for t in tracks if by_artist and in_archive(t, by_artist))
        per_inst[inst] = (len(tracks), matched)
        for pos, t in enumerate(tracks, 1):
            rows.append([inst, pos, t["id"], t["artist"], t["title"], t["duration_s"]])
        time.sleep(0.3)

    with open(out, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["instance", "position", "spotify_id", "artist", "title", "duration_s"])
        w.writerows(rows)

    tot_sp = sum(n for n, _ in per_inst.values())
    tot_m = sum(m for _, m in per_inst.values())
    print(f"resolved {tot_sp} Spotify tracks across {len(PLAYLISTS)} playlists → {out}\n")
    print(f"{'instance':9} {'spotify':>7} {'catalog':>7} {'censused':>8}")
    for inst, pid in PLAYLISTS:
        n, m = per_inst[inst]
        print(f"{inst:9} {n:>7} {cat.get(inst, '-'):>7} {m:>8}")
    print(f"{'TOTAL':9} {tot_sp:>7} {sum(cat.values()):>7} {tot_m:>8}")
    if by_artist:
        print(f"\n{tot_m}/{tot_sp} Spotify tracks ({100*tot_m/tot_sp:.0f}%) already "
              f"have census features; the rest need live capture through the app.")


if __name__ == "__main__":
    main()

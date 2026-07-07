#!/usr/bin/env python3
"""census_report.py — distribution review of a CorpusCensusRunner results CSV.

CENSUS.3 tooling (see docs/ENGINEERING_PLAN.md §Phase CENSUS). Reads the census
output CSV + the pilot manifest (for genre_bucket / stratum / decade), and emits a
Markdown report: octave-folded BPM-disagreement histogram vs the D-154 10 %
threshold, MoodClassifier feature means/stds vs mood_scaler.json, K-S key-confidence
distribution, per-genre 3-way BPM error census, and dual-rate (44.1↔48 kHz) feature
deltas. Reports only; proposes no retune (every threshold change is its own increment).

Usage:
  python3 tools/census_report.py \
    --results "/Volumes/Extreme SSD/phosphene_census/pilot_results.csv" \
    --manifest tools/data/corpus_pilot_1000.csv \
    --scaler tools/data/mood_scaler.json \
    --out docs/diagnostics/CENSUS_PILOT_REPORT.md \
    [--failures "/Volumes/Extreme SSD/phosphene_census/census_failures.log"]

Stdlib only.
"""

import argparse
import csv
import json
import math
import re
import statistics as st

# A dual-rate row's relpath ends with the rate suffix; match that exactly rather
# than "contains #" — real filenames carry '#' (e.g. "Piano Sonata #8").
DUAL_SUFFIX = re.compile(r"#(44100|48000)$")

FEATS = ["subBass", "lowBass", "lowMid", "midHigh", "highMid", "high",
         "centroid", "flux", "majorCorr", "minorCorr"]
D154_THRESHOLD = 0.10


def fnum(s):
    if s is None or s == "":
        return None
    try:
        v = float(s)
        return v if math.isfinite(v) else None
    except ValueError:
        return None


def load_results(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    native = [r for r in rows if not DUAL_SUFFIX.search(r["relpath"])]
    dual = [r for r in rows if DUAL_SUFFIX.search(r["relpath"])]
    return native, dual


def load_manifest(path):
    with open(path, newline="") as f:
        return {r["relpath"]: r for r in csv.DictReader(f)}


def histogram(values, edges):
    counts = [0] * (len(edges) - 1)
    for v in values:
        for i in range(len(edges) - 1):
            if edges[i] <= v < edges[i + 1] or (i == len(edges) - 2 and v == edges[-1]):
                counts[i] += 1
                break
    return counts


def bar(n, total, width=40):
    if total == 0:
        return ""
    return "█" * max(0, round(width * n / total))


def section_coverage(native, dual, failures):
    ok = [r for r in native if r["error"] == ""]
    errored = [r for r in native if r["error"] != ""]
    with_grid = [r for r in ok if fnum(r["grid_bpm"]) is not None]
    beatless = [r for r in ok if fnum(r["grid_bpm"]) is None]
    lines = ["## 1. Coverage", "",
             f"- Native track rows: **{len(native)}** ({len(ok)} ok, {len(errored)} row-level error)",
             f"- Dual-rate rows: **{len(dual)}** (≈{len(dual)//2} tracks × 2 rates)",
             f"- Full-mix grid resolved: **{len(with_grid)}** · beatless / empty-grid (left blank, not fabricated): **{len(beatless)}**",
             f"- Decode failures (census_failures.log): **{failures}**", ""]
    return lines, ok, with_grid


def section_disagreement(ok):
    both = [r for r in ok
            if fnum(r["folded_disagreement"]) is not None
            and fnum(r["grid_bpm"]) is not None and fnum(r["drums_bpm"]) is not None]
    fd = sorted(fnum(r["folded_disagreement"]) for r in both)
    lines = ["## 2. Octave-folded BPM disagreement vs the D-154 10 % threshold", "",
             f"Full-mix vs drums-stem grid, octave-folded (D-154 calibrated this on 38 tracks; "
             f"threshold = {D154_THRESHOLD}). n = **{len(fd)}** tracks with both grids.", ""]
    if not fd:
        lines.append("_No tracks with both grids._")
        return lines, both
    edges = [0, 0.02, 0.04, 0.06, 0.08, 0.10, 0.15, 0.20, 0.30, 0.50, 1.01]
    counts = histogram(fd, edges)
    lines.append("```")
    lines.append(f"{'bucket':>12}  {'n':>4}  {'%':>5}")
    for i, c in enumerate(counts):
        lbl = f"{edges[i]:.2f}-{edges[i+1]:.2f}"
        mark = "  <- 10% gate" if abs(edges[i] - 0.10) < 1e-9 else ""
        lines.append(f"{lbl:>12}  {c:>4}  {100*c/len(fd):>4.1f}%  {bar(c, len(fd))}{mark}")
    lines.append("```")
    above = sum(1 for v in fd if v > D154_THRESHOLD)
    p50 = st.median(fd)
    p90 = fd[int(0.90 * (len(fd) - 1))]
    p99 = fd[int(0.99 * (len(fd) - 1))]
    irregular = sum(1 for r in both if r["beat_irregular"] == "true")
    lines += ["",
              f"- Above the {D154_THRESHOLD} threshold: **{above}/{len(fd)} ({100*above/len(fd):.1f}%)**.",
              f"- Percentiles: p50 **{p50:.4f}** · p90 **{p90:.4f}** · p99 **{p99:.4f}**.",
              f"- `beat_irregular == true` (folded > 0.10 OR bar_confidence < 0.2): **{irregular}/{len(both)} ({100*irregular/len(both):.1f}%)**.",
              ""]
    # Is 0.10 a natural valley? Look at the density right around it.
    near = sum(1 for v in fd if 0.08 <= v <= 0.12)
    lines.append(f"- Density in the 0.08–0.12 band around the gate: **{near}** tracks "
                 f"({100*near/len(fd):.1f}%) — {'thin (gate sits in a gap)' if near/len(fd) < 0.05 else 'not obviously a valley'}.")
    # Bar-confidence covariance.
    bc = [(fnum(r['bar_confidence']), fnum(r['folded_disagreement'])) for r in both
          if fnum(r['bar_confidence']) is not None]
    if len(bc) > 2:
        xs = [b for b, _ in bc]
        ys = [d for _, d in bc]
        mx, my = st.mean(xs), st.mean(ys)
        cov = sum((x - mx) * (y - my) for x, y in bc) / len(bc)
        sx, sy = st.pstdev(xs), st.pstdev(ys)
        r = cov / (sx * sy) if sx > 0 and sy > 0 else float("nan")
        lines.append(f"- bar_confidence vs folded-disagreement correlation: **r = {r:.3f}** "
                     f"(bar_confidence mean {mx:.3f}).")
    lines.append("")
    return lines, both


def section_mood(ok, scaler):
    rows = [r for r in ok if fnum(r["feat0"]) is not None]
    lines = ["## 3. Mood feature means/stds vs `mood_scaler.json` (DEAM reference)", "",
             f"Per-frame means of the 10 MoodClassifier inputs, aggregated across n = **{len(rows)}** tracks, "
             f"vs the DEAM-derived z-scaler. A large mean shift or std ratio ≠ 1 says the classifier operates "
             f"off-centre on this library (the §5 Tier-1 re-centre candidate). _Reports only; no retune here._", "",
             "```",
             f"{'feature':>10}  {'deploy_mean':>11}  {'DEAM_mean':>9}  {'Δmean(σ)':>8}  {'deploy_std':>10}  {'DEAM_std':>8}  {'std_ratio':>9}"]
    for i, name in enumerate(FEATS):
        vals = [fnum(r[f"feat{i}"]) for r in rows if fnum(r[f"feat{i}"]) is not None]
        if not vals:
            continue
        dm, ds = st.mean(vals), (st.pstdev(vals) if len(vals) > 1 else 0.0)
        rm, rs = scaler["means"][i], scaler["stds"][i]
        zshift = (dm - rm) / rs if rs > 0 else float("nan")
        ratio = ds / rs if rs > 0 else float("nan")
        lines.append(f"{name:>10}  {dm:>11.5f}  {rm:>9.5f}  {zshift:>+8.2f}  {ds:>10.5f}  {rs:>8.5f}  {ratio:>9.2f}")
    lines += ["```", "",
              "`Δmean(σ)` = (deploy_mean − DEAM_mean) / DEAM_std — how far the deployment centre sits from "
              "the scaler's zero, in DEAM sigmas. |Δ| ≳ 1 on a feature ⇒ that input is systematically "
              "off-centre for this library.", ""]
    return lines


def section_key(ok):
    rows = [r for r in ok if fnum(r["key_major_r"]) is not None or fnum(r["key_minor_r"]) is not None]
    conf = []
    for r in rows:
        mj, mn = fnum(r["key_major_r"]), fnum(r["key_minor_r"])
        vals = [v for v in (mj, mn) if v is not None]
        if vals:
            conf.append(max(vals))
    lines = ["## 4. K-S key-confidence distribution", "",
             f"`ChromaExtractor` Krumhansl-Schmuckler correlation (code comment flags it \"unreliable\"). "
             f"max(major_r, minor_r) as a confidence proxy, n = **{len(conf)}**. "
             f"This is a *self-consistency* distribution — accuracy needs external ground truth (§8.5 enrichment).", ""]
    if conf:
        conf.sort()
        edges = [0, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 1.01]
        counts = histogram(conf, edges)
        lines.append("```")
        for i, c in enumerate(counts):
            lines.append(f"{edges[i]:.2f}-{edges[i+1]:.2f}  {c:>4}  {100*c/len(conf):>4.1f}%  {bar(c, len(conf))}")
        lines.append("```")
        lines.append(f"- median key-confidence **{st.median(conf):.3f}** · "
                     f"< 0.5 (weak): **{sum(1 for v in conf if v < 0.5)}** "
                     f"({100*sum(1 for v in conf if v < 0.5)/len(conf):.1f}%).")
    # key class histogram
    classes = {}
    for r in rows:
        k = r["key_class"] or "(none)"
        classes[k] = classes.get(k, 0) + 1
    top = sorted(classes.items(), key=lambda kv: -kv[1])[:8]
    lines.append("- Top key classes: " + ", ".join(f"{k} ({n})" for k, n in top))
    lines.append("")
    return lines


def section_per_genre(both, manifest):
    by_genre = {}
    for r in both:
        m = manifest.get(r["relpath"])
        g = (m["genre_bucket"] if m else "") or "unknown"
        by_genre.setdefault(g, []).append(r)
    lines = ["## 5. Per-genre 3-way BPM error census", "",
             "Median octave-folded grid-vs-drums disagreement + median |mir−grid|/max relative delta, "
             "by genre_bucket (joined from the pilot manifest). The swing/rubato shelves (jazz, classical) "
             "are D-154's named blind spot.", "",
             "```",
             f"{'genre':>16}  {'n':>4}  {'med_folded':>10}  {'p90_folded':>10}  {'irreg%':>6}  {'med|mir-grid|':>13}"]
    for g, rs in sorted(by_genre.items(), key=lambda kv: -len(kv[1])):
        fd = sorted(fnum(r["folded_disagreement"]) for r in rs if fnum(r["folded_disagreement"]) is not None)
        if not fd:
            continue
        med = st.median(fd)
        p90 = fd[int(0.90 * (len(fd) - 1))]
        irr = 100 * sum(1 for r in rs if r["beat_irregular"] == "true") / len(rs)
        deltas = []
        for r in rs:
            gb, mb = fnum(r["grid_bpm"]), fnum(r["mir_bpm"])
            if gb and mb and max(gb, mb) > 0:
                deltas.append(abs(gb - mb) / max(gb, mb))
        md = st.median(deltas) if deltas else float("nan")
        lines.append(f"{g:>16}  {len(fd):>4}  {med:>10.4f}  {p90:>10.4f}  {irr:>5.1f}%  {md:>13.4f}")
    lines += ["```", ""]
    return lines


def section_dual_rate(dual, native):
    # Pair #44100 and #48000 rows per base relpath; also compare to the native row.
    base = {}
    for r in dual:
        rel, _, rate = r["relpath"].rpartition("#")
        base.setdefault(rel, {})[rate] = r
    nat = {r["relpath"]: r for r in native}
    lines = ["## 6. Dual-rate (44.1 ↔ 48 kHz) feature deltas", "",
             "Same 30 s window decoded at both rates through the MIR/mood path — the cross-path skew the "
             "DECISIONS sample-rate delta describes (spectralCentroid ~22 % → valence +34 % / arousal −38 %). "
             "Positive Δ = 48 kHz minus 44.1 kHz.", ""]
    cd, vd, ad = [], [], []
    for rel, byrate in base.items():
        if "44100" not in byrate or "48000" not in byrate:
            continue
        a, b = byrate["44100"], byrate["48000"]
        c44, c48 = fnum(a["feat6"]), fnum(b["feat6"])
        if c44 and c48 and c44 != 0:
            cd.append((c48 - c44) / abs(c44))
        v44, v48 = fnum(a["valence"]), fnum(b["valence"])
        if v44 is not None and v48 is not None:
            vd.append(v48 - v44)
        r44, r48 = fnum(a["arousal"]), fnum(b["arousal"])
        if r44 is not None and r48 is not None:
            ad.append(r48 - r44)
    n = len(cd)
    lines.append(f"Paired tracks (both rates present): **{n}**.")
    if n:
        lines += ["", "```",
                  f"centroid  median Δrel {st.median(cd):+.3%}   mean {st.mean(cd):+.3%}",
                  f"valence   median Δabs {st.median(vd):+.4f}   mean {st.mean(vd):+.4f}   (n={len(vd)})",
                  f"arousal   median Δabs {st.median(ad):+.4f}   mean {st.mean(ad):+.4f}   (n={len(ad)})",
                  "```", "",
                  "_Note: valence/arousal here are the census's single-shot EMA-attenuated outputs "
                  "(≈ ×emaAlpha from neutral); read the deltas as directional, not absolute magnitudes._"]
    lines.append("")
    return lines


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--results", required=True)
    p.add_argument("--manifest", required=True)
    p.add_argument("--scaler", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--failures", default=None)
    p.add_argument("--date", default="", help="Report date (passed in; script has no clock).")
    args = p.parse_args()

    native, dual = load_results(args.results)
    manifest = load_manifest(args.manifest)
    scaler = json.load(open(args.scaler))
    failures = 0
    if args.failures:
        try:
            failures = sum(1 for _ in open(args.failures))
        except OSError:
            failures = 0

    out = [f"# CENSUS.3 — Pilot census distribution report",
           "",
           f"**Date:** {args.date or 'TBD'} · **Source:** `{args.results}` · "
           f"**Manifest:** `{args.manifest}` · generated by `tools/census_report.py`.",
           "",
           "The census MEASURES; every retune proposal below is a candidate only and lands as its own "
           "D-numbered increment (EP §Phase CENSUS scope guard).", ""]
    cov, ok, with_grid = section_coverage(native, dual, failures)
    out += cov
    dis, both = section_disagreement(ok)
    out += dis
    out += section_mood(ok, scaler)
    out += section_key(ok)
    out += section_per_genre(both, manifest)
    out += section_dual_rate(dual, native)

    with open(args.out, "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"report: {len([r for r in native if r['error']==''])} tracks -> {args.out}")


if __name__ == "__main__":
    main()

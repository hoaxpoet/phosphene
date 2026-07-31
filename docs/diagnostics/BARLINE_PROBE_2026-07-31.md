# Bar-line probe — the bar is in the audio, just not in the downbeat stream

**Date:** 2026-07-31 · **Status:** probe, not an implementation · **Feeds:** FT.3
**Script:** `tools/barline_probe.py` · **Beat times:** `FullTrackMeterTests` with `PHOSPHENE_BEATS_DUMP`

---

## Why

Four independent levers have failed to get bar position out of Beat This!'s downbeat
activations (D-208 + its FT.1 amendment): a different onset source (TRK.2), an unbiased
decoder (DBN.2), a 10× larger model (MDL.1), and 13–25× more context (FT.1). D-208
concluded the evidence is thin.

Matt's question — *"is there more that can be done for local tracks specifically?"* —
reframes it. Three premises change on a local file: the whole track exists before playback,
prep time is nearly free, and LF.2 gives same-bytes-analysed-and-played. And crucially
**beats are already good** (suite-1 F 0.97), so on a local file we hold 400–1000 reliable
beat times and the only open question is *which of them are bar lines*.

That is a periodicity-and-phase search over a tiny integer space — and **it need not use
the downbeat stream at all.**

## Method

Beat-synchronous features, one value per beat, from the window running from each beat to
the next: **low-band energy** (<200 Hz — kick lands on 1), **broadband RMS**, **spectral
flux** (change lands on bars), **harmonic change** (1 − cosine similarity of adjacent
beats' pitch-class profiles — chords change on bar lines).

For each meter `B` and phase `p`:

```
d(B,p) = (mean feature at bar-line beats − mean elsewhere) / sd(all beats)
```

Expectation 0 under the null for **any** `B`, chosen deliberately: DBN.2 was derailed by a
statistic whose bias scaled with `B`. That alone is not enough — larger `B` maximises over
more phases with fewer samples each, so its max-over-phase is more chance-inflated — so
every score is reported against a **permutation null** (the same statistic on shuffled
features, 200 draws). **Only the margin over that null counts.**

Beat times come from the engine's own full-track grid via FT.1's tiler, not from ground
truth: the taps are sparse, and on money/solsbury_hill they are half-time.

## Result — 6 / 6

| track | truth | probe | best feature | margin |
|---|---|---|---|---|
| billie_jean | 4 | **4 ✓** | low_energy | **+1.045** |
| bleed | 4 | **4 ✓** | flux | +0.138 |
| bohemian_rhapsody | 4 | **4 ✓** | low_energy | +0.133 |
| **money** | **7** | **7 ✓** | flux | +0.212 |
| **solsbury_hill** | **7** | **7 ✓** | flux | +0.052 |
| **take_five** | **5** | **5 ✓** | low_energy | **+1.167** |

Baseline for the same tracks: **2/6** for the incumbent resolver, **2/6** for the DBN.2
decoder. All three odd meters — the ones four prior levers failed on — are recovered.

Untruthed tracks, for the record: pyramid_song → 4 (+0.032, noise), yyz → 4 (+0.901 on
low_energy, plausible — much of YYZ is in 4), clair_de_lune → 3 (+0.118, and it has no
stable meter, so any confident answer here is a false positive).

## Three caveats, stated before this is treated as a win

**1. The meter set was changed between runs, and it moved the headline from 2/6 to 6/6.**
The first pass used {2,3,4,5,6,7} and scored 2/6, with meter **2** winning spuriously on
three tracks. The justification for restricting to {3,4,5,7} is that D-207 already fixed the
system's hypothesis set to exactly that, and 2 is a sub-multiple of a real bar length rather
than a candidate bar — kick-on-alternate-beats is a genuine periodicity that is not the bar.
That reasoning is sound, but **the change was made after seeing the first table**, and the
result is sensitive to it. FT.3 must re-establish this on tracks not used to tune it.

**2. The margins are wildly uneven.** Take Five (+1.167) and Billie Jean (+1.045) are
unambiguous — all four features agree independently. Solsbury Hill (+0.052) and Bohemian
(+0.133) are thin, and on solsbury only `flux` finds it while `low_energy` picks 4. A decline
threshold set from this distribution would refuse several of the correct answers.

**3. No single feature works alone.** `low_energy` gets 4/6 and `flux` gets 4/6 — but
*different* fours. money and solsbury_hill need flux; bohemian needs low_energy. Any
implementation needs a combination rule, and combination rules are exactly where DBN.2's
bias problems came from.

**Not measured at all: phase.** The probe scores which *meter*, never which *beat* is the
bar line. A correct meter with the wrong phase puts the accent on the wrong beat of every
bar — visually identical to being wrong. FT.3 must score phase against ground-truth
downbeats.

## Scope limit — the same one that sank D-170

**This is structurally local-file-only.** It needs the whole track; streaming exposes a 30 s
preview before playback. That is precisely the property that got section detection removed:

> D-170: *"Structurally local-file-only… the feature could only ever serve local-file
> playback, and no detector, supervised or not, changes that."*

The difference is the second half of D-170's reasoning — it was also *below the perceptual
bar* on local files (F@3 ≈ 0.29–0.41). This is 6/6 on meter. But the scope limit is
identical, and whether a local-file-only improvement is worth building is a product call,
not an engineering one.

## Reproduce

```bash
mkdir -p /tmp/barprobe
PHOSPHENE_FT1_FULLTRACK=1 PHOSPHENE_BEATS_DUMP=/tmp/barprobe \
  swift test --package-path PhospheneEngine --filter FullTrackMeter

~/phosphene-ml-env/bin/python tools/barline_probe.py \
  --beats-dir /tmp/barprobe --fixtures ~/phosphene_beatbench_fixtures
```

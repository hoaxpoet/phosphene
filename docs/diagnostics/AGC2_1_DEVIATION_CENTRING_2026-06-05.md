# AGC2.1 — Deviation-primitive centring measured across real sessions (BUG-027)

**Increment:** AGC2.1 (Instrument & measure).
**Date:** 2026-06-05.
**Status:** Measurement complete. **No production code changed.** Input to the AGC2.2 decision gate — the (a)/(b)/(c)/split call is Matt's, made on this evidence.
**Harness:** [`tools/agc2/measure_deviation_centring.py`](../../tools/agc2/measure_deviation_centring.py) (pure stdlib; reads the values production *shipped* each frame from `features.csv` / `stems.csv` — no re-derivation from FFT).
**Source of truth:** [`docs/QUALITY/KNOWN_ISSUES.md` § BUG-027](../QUALITY/KNOWN_ISSUES.md). This doc expands that entry's evidence; it does not override it.

---

## 1. Purpose

[BUG-027](../QUALITY/KNOWN_ISSUES.md) claims the positive deviation primitives
(`bassDev`/`midDev`/`trebDev` on `FeatureVector`; the raw `{stem}Energy` values on
`StemFeatures`) are mis-calibrated against a 0.5 centre that the total-energy AGC does not
produce per band. AGC2.1 reproduces that claim on real recorded sessions across both capture
paths and a spectrally varied track set, and produces the permanent evidence table that grounds
the AGC2.2 fix-scope decision.

## 2. Methodology

- **Direct read of shipped values.** The harness reads the CSV columns the app logged that
  frame (`bass`, `mid`, `treble`, the 6 bands, `bassRel`, `bassDev`; and every
  `{stem}Energy` / `{stem}EnergyRel` / `{stem}EnergyDev`). `midDev`/`trebDev` are not logged,
  so they are derived from the logged `mid`/`treble` via the production formula
  `xDev = max(0, (x − 0.5) × 2)` exactly. No FFT re-derivation, so the harness cannot disagree
  with production.
- **Frame selection.** Segment by track (`track_elapsed_s` reset → new track). Drop each track's
  first 2 s (the BUG-025 cold-start AGC transient — a one-time, per-`reset()` warmup). Then keep
  only **active** frames where `bass + mid + treble > 0.10` (excludes silence / prep, which would
  otherwise deflate the firing rate artificially by adding never-fire frames). Active-frame counts
  are reported so the filtering is transparent (typically 86–100 % of post-cold-start frames).
- **Metrics.** Per band: AGC centre (p50/mean); `*Dev` firing rate (% active frames with the
  positive deviation > ε = 1e-4, i.e. the band value > 0.5); signed `*Rel` stddev. Per stem: raw
  `{stem}Energy` centre; logged `{stem}EnergyDev` firing rate; logged `{stem}EnergyRel` mean +
  stddev. Stems are aligned to the active feature frames by `frame` index.

## 3. Sessions measured

> The two sessions named in the BUG-027 entry (`2026-06-01T22-37-01Z` LF, `2026-06-02T01-12-51Z`
> Spotify) **no longer exist on disk.** Matt recorded a purpose-built replacement; the four below
> cover both capture paths and four spectral classes, exceeding the AGC2.1 bar.

| Session | Path | Content | Spectral character |
|---|---|---|---|
| `2026-06-05T14-35-14Z` | Local File | Atlas — Battles (1 track) | bass-dominant |
| `2026-06-05T21-34-58Z` | Local File | Wilhelms Scream (James Blake), Cherub Rock (Smashing Pumpkins), Alameda (Elliott Smith), Better Git It In Your Soul (Charles Mingus) | **4 classes: bass-dominant / dense-rock / mid-rich acoustic / treble-rich jazz** |
| `2026-06-05T18-26-37Z` | Spotify (process tap) | Billie Jean, Around the World, Seven Nation Army, Get Lucky, … (9 tracks) | mixed (funk/rock/electronic) |
| `2026-06-05T21-10-41Z` | Spotify (process tap) | Love Shack, Sad Song, In Undertow (3 tracks) | mixed |

## 4. Manifestation A — FeatureVector band deviation (fixed-0.5 pivot)

`MIRPipeline.swift:334-339`. Headline column is the `*Dev` firing rate (D-026's "primary
above-average motion driver").

| Session | Path | `bass` p50 | **`bassDev`** | **`midDev`** | **`trebDev`** | `bassRel` σ (signed) |
|---|---|---|---|---|---|---|
| `14-35-14Z` | LF | 0.271 | 6.8 % | **0.0 %** | **0.0 %** | 0.235 |
| `21-34-58Z` | LF | 0.205 | 7.9 % | **0.0 %** | **0.0 %** | 0.450 |
| `18-26-37Z` | Spotify | 0.211 | 2.1 % | **0.0 %** | **0.0 %** | 0.352 |
| `21-10-41Z` | Spotify | 0.124 | 4.5 % | 0.9 % | **0.0 %** | 0.945 |

`bassDev` fires **2–8 %** of active frames; `midDev`/`trebDev` fire **~0 %** on every session,
both paths. The signed `bassRel` carries real information (σ 0.23–0.95); the positive-only `*Dev`
clamp discards most of it. (BUG-027 originally measured `bassDev` 2.9 % LF / 1.5 % Spotify on the
now-deleted sessions — reproduced here within the same band.)

### 4a. The decisive test — per spectral class (LF `21-34-58Z`)

Does a genuinely mid- or treble-dominant track lift `midDev`/`trebDev` off zero?

| Track | Spectral class | `bass` p50 / Dev | `mid` p50 / Dev | `treble` p50 / Dev |
|---|---|---|---|---|
| Wilhelms Scream (James Blake) | bass-dominant | 0.14 / 9 % | 0.03 / **0 %** | 0.00 / **0 %** |
| Cherub Rock (Smashing Pumpkins) | dense rock | 0.25 / 10 % | 0.04 / **0 %** | 0.01 / **0 %** |
| Alameda (Elliott Smith) | **mid-rich** acoustic | 0.22 / 6 % | 0.07 / **0 %** | 0.01 / **0 %** |
| Better Git It In Your Soul (Mingus) | **treble-rich** jazz | 0.18 / 6 % | 0.10 / **0 %** | 0.01 / **0 %** |

**No.** The mid band's centre rises monotonically with the music's spectral focus
(0.03 → 0.04 → 0.07 → 0.10) but never approaches 0.5, so `midDev` stays at 0 % even on the
vocal-forward acoustic and the cymbal/horn jazz track. Treble centre never exceeds 0.01. The
deadness is **structural, not genre-correlated**: low-frequency bins carry the majority of the
RMS-summed 6-band total on essentially all music, so the total-energy AGC pins mid/treble bands
far below the 0.5 pivot regardless of perceptual focus.

## 5. Manifestation B — StemFeatures (raw energy vs per-stem-EMA deviation)

`StemAnalyzer.swift:221-247`. Raw `{stem}Energy` is a 3-band sum of an AGC-normalised stem; the
`{stem}EnergyDev` goes through a **per-stem EMA pivot** (`:277-298`), not the fixed 0.5.

| Session | Path | raw `{stem}Energy` p50 (voc/drm/bas/oth) | `{stem}EnergyDev` fires |
|---|---|---|---|
| `14-35-14Z` | LF | 0.45 / 0.37 / 0.37 / 0.40 | 74–77 % |
| `21-34-58Z` | LF | 0.31 / 0.24 / 0.26 / 0.27 | 64–71 % |
| `18-26-37Z` | Spotify | 0.30 / 0.25 / 0.27 / 0.26 | 56–57 % |

Raw `{stem}Energy` centres **~0.25–0.45, not 0.5** (matches the Nimbus NB.10 r1.6 p50 figures of
0.24 / 0.27 / 0.41) → any consumer that assumes a 0.5 centre and reads the raw value under-drives
(Nimbus's `bloom`). **But `{stem}EnergyDev` is alive (56–77 %)** because its per-stem EMA pivot
self-centres — the exact mechanism the band path lacks.

## 6. Findings

1. **Manifestation A is real and broader than the bass-only headline.** `bassDev` fires 2–8 %;
   **`midDev`/`trebDev` fire ~0 % on all music, both paths, including genuinely mid-rich and
   treble-rich tracks.** This is the Dragon Bloom bite (`mid_att_rel ≈ 0 → frozen feathers`)
   generalised: the *entire* positive mid/treble deviation channel is dead catalog-wide.
2. **Manifestation B splits cleanly.** The raw `{stem}Energy` value is miscalibrated (~0.30, not
   0.5) and bites consumers that read it directly. The stem *deviation* path is **already healthy**
   — it needs no engine change.
3. **The working pattern already exists in-codebase.** The stem deviation path (per-element EMA
   pivot — alive, 56–77 %) and the band deviation path (fixed-0.5 pivot — dead, 0–8 %) sit side by
   side. Fixing manifestation A is, mechanically, bringing the band path in line with the stem path
   the project already ships.

## 7. Implication for the AGC2.2 decision (evidence input — not the decision)

The decision is Matt's. What the evidence constrains:

- **(a) Per-band AGC** (each band its own running-average denominator → band *value* centres at
  0.5): also changes the **raw band values** every preset reads (`f.mid` centre 0.05 → 0.5,
  `f.treble` 0.005 → 0.5) and **erases the cross-band relative-energy information** the 6-band
  total-energy AGC deliberately preserves (`BandEnergyProcessor.swift:40,122`). Largest blast
  radius; touches non-deviation consumers too.
- **(b) Per-band EMA pivot at the derivation layer** (mirror `StemAnalyzer`'s stem path onto the
  bands; keep the total-energy AGC untouched): same liveness win, **raw band values and cross-band
  info preserved**, blast radius bounded to the `*Rel`/`*Dev` consumers. Breaks the
  `RelDevTests` formula pin `bassRel == (bass−0.5)×2` (a deliberate, signed-off update). Finding 3
  shows this is the smallest correct change. **Evidence leans here.**
- **(c) Document + steer to signed `*Rel`** (no engine change): zero risk, but mid/treble "punch"
  stays unavailable to *everyone* — even the signed `midRel` centres at −0.87 (σ 0.09), so the
  signed form is also weak for mid/treble, not just the clamped `*Dev`.
- **Split — (b) for the FeatureVector band path + (c)/doc for stems:** Finding 2 shows the stem
  *deviation* path is already correct; only the raw-`{stem}Energy`-0.5 assumption needs handling
  (document the ~0.30 centre + recalibrate the few raw-energy consumers — Nimbus already did).

**Behaviour-change caveat (any of a/b):** the positive deviation cue moves from "fires rarely on a
strong transient (~3 %)" to "fires when above the band's own recent average (~50 %)." That is the
*intended* D-026 behaviour, but it changes the feel of any preset that was implicitly relying on
the rare-firing — hence the mandatory catalog M7 and golden-hash re-bank in AGC2.4.

## 8. Reproduce

```
python3 tools/agc2/measure_deviation_centring.py <session_dir> --label <LF|Spotify> [--per-track]
```

Sessions live under `~/Documents/phosphene_sessions/`. The four above were the AGC2.1 set.

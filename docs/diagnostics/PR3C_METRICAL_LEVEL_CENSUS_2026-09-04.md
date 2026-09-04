# PR.3c — the metrical level is not the problem; the meter is

**Directive:** Matt, 2026-09-04, "go at the metrical level" — after PR.3a/b failed to make the
bar-line estimator answer on bleed, bohemian_rhapsody, clair_de_lune and girl_from_ipanema, and
D-210 was cited as the reason (grid at double or half the tapped pulse ⇒ bar phase unrecoverable).

**Finding: the metrical level is correct on 7 of 9 ground-truthed fixtures, and D-210's blocking
argument rests on two reference values that have both since been withdrawn.** No level corrector
should be built. The defect the evidence actually shows is the **meter**.

## 1. D-210's premise no longer holds

D-210 (2026-07-31) declined to correct the level on the grounds that its two exhibits pulled in
opposite directions — *"money wants halving at 116 BPM and bleed wants doubling at 115 — same
tempo, opposite corrections — so no global BPM threshold separates them."* Its table:

| track | grid BPM | truth BPM **as D-210 had it** | truth BPM **now** | source of the revision |
|---|---:|---:|---:|---|
| money | 116.19 | **60.97** | **121.06** (`arbitrated_taps`) | BUG-102.2 re-annotation, 2026-08-27 |
| bleed | 115.00 | **226.72** | **115.38** (`confirmed`, taps + madmom) | BUG-102.1 re-tap, 2026-08-27 |

Against the current references neither is an octave error: money is a ~4 % tempo error (which is
what BUG-107 root-caused it as — *"the old 60.97 reference made 116.19 look like a clean ×1.91
octave… against the true level it is a plain tempo error"*), and bleed is simply **right**.
**Both legs of D-210's argument are gone.** That does not mean level correction is now warranted —
it means the case against it evaporated, and the census below asks the question fresh.

## 2. Census — production analyzer vs current ground truth

`MetricalLevelCensus`, env-gated `UZUME_LEVEL_CENSUS=1`. Grid from `DefaultBeatGridAnalyzer` at
44.1 kHz with no env flags (so: the model's downbeat head, the shipping default). BPM is the
median inter-beat interval on each side. "Level" classifies grid/truth against 1×, 2×, ½×, 3×, ⅓×
within 6 %.

| track | truth BPM | status | grid BPM | level | tapped meter | grid meter |
|---|---:|---|---:|---|---:|---:|
| billie_jean | 117.45 | confirmed | 115.38 | **correct** | 4 | 4 ✓ |
| bleed | 115.38 | confirmed | 115.38 | **correct** | 4 | **2** ✗ |
| bohemian_rhapsody | 71.09 | metrical_review | 71.43 | **correct** | 4 | 4 ✓ |
| money | 121.06 | arbitrated_taps | 120.00 | **correct** | 7 | **1** ✗ |
| solsbury_hill | 101.69 | confirmed | 103.45 | **correct** | 7 | **1** ✗ |
| take_five | 171.43 | confirmed | 166.67 | **correct** | 5 | **4** ✗ |
| pyramid_song | 66.58 | metrical_review | 68.18 | **correct** | — | 1 |
| clair_de_lune | 49.89 | needs_arbitration | 136.36 | other 2.733× | — | 3 |
| yyz | 272.21 | metrical_review | 214.29 | other 0.787× | — | 1 |

**Seven of nine correct. Zero clean doubles or halves.** The two misses are not octave errors
either — 2.733× and 0.787× are not 2 or ½ — and both sit on ground truth that is itself unsettled
(`needs_arbitration`, `metrical_review`), so neither can be called a grid defect yet.

## 3. What the census does show

**The meter is wrong on four of the five fixtures that have a tapped meter**, and the wrong values
are the degenerate ones BUG-028 and BUG-107 describe: bleed 4→**2**, money 7→**1**,
solsbury_hill 7→**1**, take_five 5→**4**. `computeMeter` reads the model's downbeat head, which
over-fires (a downbeat on 69–90 % of beats on odd-meter material) and collapses
`round(median_IOI / beat_period)` toward 1.

This is the same defect Matt saw on *Low*: `beatsPerBar = 2` on What In The World, Art Decade and
Weeping Wall (PR.1 §2). It is a **bar** defect, not a **level** defect.

## 4. Consequence

- **Do not build a metrical-level corrector.** The level is right where the reference is settled,
  and where it is not settled the reference has to be arbitrated before any grid claim is possible.
  Building a corrector here would be tuning toward an unvalidated target.
- **D-210 should be revisited** — not to reverse its product call (decline the bar when unsure is
  still right) but because its stated rationale cites two withdrawn numbers, and a future session
  reading it will draw the wrong conclusion, exactly as this one initially did.
- **The meter is the live defect, and `BarLineEstimator` is the instrument for it** — measured at
  meter 6-correct / 0-incorrect ("trivially separable", FT.3 task 5) and zero confident-wrong at
  the shipping threshold. That is FT.4.1's still-unadopted `UZUME_BARLINE`, which take_five's
  5/2 → 5/5 and downbeat F 0.26 → 0.97 already demonstrates.
- **PR.1's *Low* tempo readings (Weeping Wall 142.3, Warszawa 54.0) are not reclassifiable as level
  errors.** *Low* has no ground truth, and this census shows the analyzer's level is generally
  right on material that does. They stay open as unexplained tempo readings on near-beatless
  ambient audio.

## 5. Honest bounds

Nine fixtures, four with a tapped meter usable as a meter reference. Three of the nine carry
`metrical_review` / `needs_arbitration` status, so a chunk of the catalogue cannot arbitrate its own
level. The census measures the **offline prep grid**, not the live grid — PR.1's drift measurement
is the live half and is a separate axis.

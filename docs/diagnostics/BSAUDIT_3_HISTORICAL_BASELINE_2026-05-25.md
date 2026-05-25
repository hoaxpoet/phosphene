# BSAudit.3.validate.2 — Historical Accent-Window Baseline Against Pre-Impl Captures

**Date:** 2026-05-25
**Scope:** read-only run of the new `ColdStartVerifier --accent-window-pass-rate`
mode (shipped in BSAudit.3.validate.1) against the pre-BSAudit.3.impl reference
captures. These captures predate the fix, so this report tells us **how the OLD
architecture performed under the new metric** — useful as a before-snapshot for
interpreting the validate.3 fresh-capture results.
**Authority:** see [`docs/prompts/BSAUDIT_3_VALIDATE_KICKOFF.md`](../prompts/BSAUDIT_3_VALIDATE_KICKOFF.md) §Sub-commit 2.
**No production code changes; no closeout claims about BUG-017.**

## Capture inventory

| Tag | Path | Architecture state | Available? |
|---|---|---|---|
| cap1 | `~/Documents/phosphene_sessions/2026-05-22T16-57-36Z/` | CS.1 baseline (no runtime correction) | **Absent on disk** (deleted between kickoff authoring and validate.2 run) |
| cap2 | `~/Documents/phosphene_sessions/2026-05-22T19-03-59Z/` | CS.1.y.2 onset-fix attempt (since reverted) | ✅ |
| cap3 | `~/Documents/phosphene_sessions/2026-05-23T02-39-54Z/` | CS.1.y.2-redo round 2 (since reverted) | ✅ |
| cap4 | `~/Documents/phosphene_sessions/2026-05-24T15-07-31Z/` | M7 capture (CS.1.y.2-redo, since reverted) | ✅ |

**cap1 absence note.** The CS.1 baseline capture was not on disk when validate.2
ran (`find ~/Documents -name '*16-57-36*'` returns no hits). Without it, the
"original cold-start, no runtime correction" arm of the comparison is missing
from this report. The remaining three captures all contain a runtime correction
attempt — cap2 the sub-bass-onset snap (visual = liveOnset; CLAUDE.md Failed
Approach #68), cap3 + cap4 the Beat This!@15s snap (CS.1.y.2-redo). All three
were `Open`/`Reverted` at the time the validate kickoff was authored.

## Verifier configuration

All runs used the BSAudit.3.validate.1 defaults:

| Knob | Value |
|---|---|
| `--first-window-s` | 10.0 s |
| `--window-start-s` | 0 (measure from track start) |
| `--accept-ms` | 60 ms (design §6.5 acceptance window) |
| `--accent-threshold` | 0.30 (rising edge on `beatComposite`) |
| `--per-track-pass-rate` | 0.80 (PASS-firing gate) |
| `--degraded-conf-threshold` | 0.30 (PASS-degraded ceiling for max conf) |
| Aggregate gate (design §4 + §12) | ≥ 90 % PASS-firing OR PASS-degraded |
| Audible-beat reference | Beat This! on a 25 s `raw_tap.wav` slice |
| `accent_confidence` policy | column absent on these captures → treated as 1.0 (no gating in effect; the raw `beatComposite` is what the runtime wrote) |

## Per-capture results

Per-track verdict — `PASS-firing` requires ≥ 80 % of audible beats hit;
`PASS-degraded` requires max `accent_confidence` < 0.30 AND no row above the
composite threshold (graceful degradation); `FAIL` is the system claimed sync
but missed.

### cap2 — `2026-05-22T19-03-59Z` (CS.1.y.2 onset-fix attempt, reverted)

Verifier verdict: **PASS** — 10 / 10 tracks PASS-firing|degraded (100 %).

| # | Track | Verdict | hits / audible | max conf | max composite |
|---|---|---|---|---|---|
| 1 | Billie Jean | `pass-firing` | 18 / 19 (95 %) | 1.00 | 1.00 |
| 2 | Around the World | `pass-firing` | 20 / 20 (100 %) | 1.00 | 1.00 |
| 3 | Seven Nation Army | `pass-firing` | 20 / 20 (100 %) | 1.00 | 1.00 |
| 4 | Get Lucky | `pass-firing` | 19 / 19 (100 %) | 1.00 | 1.00 |
| 5 | Superstition | `pass-firing` | 17 / 17 (100 %) | 1.00 | 1.00 |
| 6 | Everlong | `pass-firing` | 26 / 26 (100 %) | 1.00 | 1.00 |
| 7 | Royals | `pass-firing` | 14 / 14 (100 %) | 1.00 | 1.00 |
| 8 | HUMBLE. | `pass-firing` | 12 / 12 (100 %) | 1.00 | 1.00 |
| 9 | B.O.B. — Bombs Over Baghdad | `pass-firing` | 25 / 25 (100 %) | 1.00 | 1.00 |
| 10 | Money | `pass-firing` | 4 / 4 (100 %) | 1.00 | 1.00 |

Full report: [`<cap2>/cold_start_accent_window.md`](../../../../Documents/phosphene_sessions/2026-05-22T19-03-59Z/cold_start_accent_window.md).

### cap3 — `2026-05-23T02-39-54Z` (CS.1.y.2-redo round 2, reverted)

Verifier verdict: **PASS** — 10 / 10 tracks PASS-firing|degraded (100 %).

| # | Track | Verdict | hits / audible | max conf | max composite |
|---|---|---|---|---|---|
| 1 | Billie Jean | `pass-firing` | 19 / 19 (100 %) | 1.00 | 1.00 |
| 2 | Around the World | `pass-firing` | 21 / 21 (100 %) | 1.00 | 1.00 |
| 3 | Seven Nation Army | `pass-firing` | 19 / 19 (100 %) | 1.00 | 1.00 |
| 4 | Get Lucky | `pass-firing` | 20 / 20 (100 %) | 1.00 | 1.00 |
| 5 | Superstition | `pass-firing` | 16 / 16 (100 %) | 1.00 | 1.00 |
| 6 | Everlong | `pass-firing` | 26 / 26 (100 %) | 1.00 | 1.00 |
| 7 | Royals | `pass-firing` | 14 / 14 (100 %) | 1.00 | 1.00 |
| 8 | HUMBLE. | `pass-firing` | 12 / 12 (100 %) | 1.00 | 1.00 |
| 9 | B.O.B. — Bombs Over Baghdad | `pass-firing` | 26 / 26 (100 %) | 1.00 | 1.00 |
| 10 | Money | `pass-firing` | 13 / 13 (100 %) | 1.00 | 1.00 |

Full report: [`<cap3>/cold_start_accent_window.md`](../../../../Documents/phosphene_sessions/2026-05-23T02-39-54Z/cold_start_accent_window.md).

### cap4 — `2026-05-24T15-07-31Z` (M7 capture, CS.1.y.2-redo, reverted)

Verifier verdict: **PASS** — 10 / 10 tracks PASS-firing|degraded (100 %).

| # | Track | Verdict | hits / audible | max conf | max composite |
|---|---|---|---|---|---|
| 1 | Billie Jean | `pass-firing` | 19 / 19 (100 %) | 1.00 | 1.00 |
| 2 | Around the World | `pass-firing` | 20 / 21 (95 %) | 1.00 | 1.00 |
| 3 | Seven Nation Army | `pass-firing` | 21 / 21 (100 %) | 1.00 | 1.00 |
| 4 | Get Lucky | `pass-firing` | 19 / 19 (100 %) | 1.00 | 1.00 |
| 5 | Superstition | `pass-firing` | 17 / 17 (100 %) | 1.00 | 1.00 |
| 6 | Everlong | `pass-firing` | 26 / 26 (100 %) | 1.00 | 1.00 |
| 7 | Royals | `pass-firing` | 15 / 15 (100 %) | 1.00 | 1.00 |
| 8 | HUMBLE. | `pass-firing` | 13 / 13 (100 %) | 1.00 | 1.00 |
| 9 | B.O.B. — Bombs Over Baghdad | `pass-firing` | 25 / 25 (100 %) | 1.00 | 1.00 |
| 10 | Money | `pass-firing` | 13 / 13 (100 %) | 1.00 | 1.00 |

Full report: [`<cap4>/cold_start_accent_window.md`](../../../../Documents/phosphene_sessions/2026-05-24T15-07-31Z/cold_start_accent_window.md).

## Aggregate observation

Across all 30 pre-impl track samples (3 captures × 10 tracks), the verifier
reports **30 / 30 PASS-firing, 0 / 30 PASS-degraded, 0 / 30 FAIL**. Only two
tracks fall below 100 % per-track hit rate (cap2 Billie Jean 95 %, cap4 Around
the World 95 %) — both still well above the 80 % PASS-firing gate.

The aggregate pass rate is identical (100 %) across all three captures despite
the captures' substantially different underlying cold-start behaviour
(cap2 = `visual = liveOnset` snap; cap3/cap4 = Beat This!@15s snap). All three
were perceptually broken per Matt's M7 reviews — yet all three pass this
metric.

## Why the OLD architecture scores so high — design §6.5 confirmed

The new metric measures whether a **`beatComposite` rising-edge fires within
±60 ms of each audible beat**. On the pre-impl captures, `beatComposite` is the
**raw** beat-detector pulse (no `accentConfidence` gating yet), so the question
reduces to: did the BeatDetector's per-band onset stream fire near the audible
beats?

For the 10-track reference playlist, the answer is overwhelmingly yes — the
per-band onsets (notably sub-bass on the kick band) fire on kicks, and on
pop/rock catalog the kicks sit on beats. The metric is doing what it should:
scoring whether the accent pulse aligns with the audible beat. The pre-impl
captures had a working accent pulse layer; what was broken was the **visual
phase ramp** (`beatPhase01` sawtooth wrapping at the wrong moment), which is
what `cold_start_report.md`'s ±50 ms / 90 % verdict measured and consistently
flagged the same captures as FAIL (cap1 3/10, subsequent fix attempts 0–1 / 10
under that older metric).

In other words: the pre-impl baseline is high under the new metric because the
metric scores **accent-vs-audible-beat alignment** under a soft-ramp gating
contract that the pre-impl architecture **trivially satisfied with no gating
at all**. The new architecture (BSAudit.3.impl) preserves accent alignment
during steady-state and adds the soft-ramp gating during cold-start; it should
score similarly or marginally lower depending on how many beats fall inside
the acquisition window.

## Implications for validate.3 interpretation

These three results frame the expected behaviour of post-impl captures:

1. **Verifier PASS at sub-commit 3 is NECESSARY but NOT SUFFICIENT.** The high
   pre-impl baseline confirms the kickoff's verifier-circularity caveat
   (BSAudit §5b): "the verifier's reference is Beat This! on the same raw tap
   that produced features.csv, so it cannot detect a class of failures M7
   catches." A post-impl capture passing this metric does not prove perceptual
   sync — M7 is load-bearing.

2. **What a `pass-firing` post-impl result means.** The accent pulse fires
   near the audible beat, possibly with a few early-beat misses absorbed by
   the gating ramp (design §6.5 soft-ramp warmup). This is the intended
   behaviour. Distinguishing "soft-ramp working as designed" from "metric
   blind to a real failure" requires M7.

3. **What a `pass-degraded` post-impl result means.** On a track the
   `LiveBeatDriftTracker` cannot phase-lock (sparse onsets, polyrhythmic
   accents, half-time mis-detection), the gating keeps accents below the
   threshold for the full window. The system never claimed sync and never
   accent-pulsed at the wrong moment — graceful degradation per design §6.6.
   The kickoff's design intent: HUMBLE-class hard tracks land here.

4. **What a `fail` post-impl result means.** The system claimed sync
   (accent_confidence rose, gating let composite through) but the accents
   missed the audible beats. This is the failure mode the metric IS designed
   to catch — a false-positive lock claim.

5. **The stop-and-report criterion from the kickoff is partially activated.**
   The kickoff names it explicitly: *"Sub-commit 2's historical baseline shows
   the metric is insensitive to the BSAudit.3.impl change — i.e., old captures
   and new captures score identically. That means the metric isn't catching
   what it should."* The pre-impl side of that comparison is now established
   at 100 %. **Once Matt produces a fresh post-impl capture in validate.3, if
   it also lands at 100 % PASS-firing across the catalog, the metric is
   insensitive to the impl change** and the close has to rely entirely on M7
   (which it does anyway per design §12, but the verifier loses its informative
   floor). The PASS-degraded path is the metric's main differentiating
   signal — a post-impl capture in which HUMBLE / Money / other sparse tracks
   land at PASS-degraded while clean tracks remain PASS-firing is the
   strongest verifier evidence the new architecture works.

## Caveats

- **cap1 absent** as noted above — the comparison is missing the "no runtime
  correction" arm. If cap1 can be recreated by Matt (rebuild of HEAD with
  `PHOSPHENE_FULL_RAW_TAP=1` on the original 10-track reference playlist) the
  4th data point will land here.
- **Per-track sample sizes are small** (4 – 26 audible beats per track,
  median ~19). A handful of missed beats moves the per-track pass rate by
  5–10 %. The aggregate gate (≥ 90 % of catalog PASS-firing OR degraded) is
  insensitive to single-track jitter.
- **The verifier scores within-capture only** (Path A finding, BSAudit.2):
  Beat This! on raw_tap is per-capture-stable but cross-capture-unstable. Do
  not compare cap2/3/4 numbers against each other to draw architectural
  conclusions; compare each against its own baseline expectations.

## What this report does NOT say

This report does **not** assert anything about whether BSAudit.3.impl works.
That close criterion is M7 + a fresh post-impl capture, both to be produced in
validate.3.

— Claude (2026-05-25, BSAudit.3.validate.2)

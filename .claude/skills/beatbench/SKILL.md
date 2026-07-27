---
name: beatbench
description: Invoke when running, extending, or interpreting the BeatBench beat-sync benchmark — baseline captures, A/B comparisons, category-win claims, ground-truth or fixture changes. The measurement skill for the beat-sync program (D-202).
---

# BeatBench — the beat-sync measurement skill

BeatBench scores a beat grid (offline JSON, a recorded session's `features.csv`, or a live capture) against tapped ground truth and emits standard + Phosphene-specific metrics. Kept separate from `beat-sync-session` so preset/UX increments that merely *cite* sync numbers load only this one. The harness itself does not exist until GT.3 — the invocation block below is a placeholder; the metric and claim contract is authoritative now.

## Metrics (exact windows)

The GT.3 harness config file fixes the concrete tolerance parameters and is the authority; the standard windows below are the definitions the config instantiates.

- **Beat F-measure @ ±70 ms** — precision/recall of detected vs ground-truth beats within a ±70 ms tolerance window. The headline offline number.
- **Cemgil accuracy** — Gaussian error weighting of each beat's timing deviation (standard Cemgil et al. σ = 40 ms window). Rewards tightness, not just presence-in-window.
- **CMLt / AMLt** — continuity-based: longest correctly-tracked segment as a fraction of the track. CMLt requires correct metrical level; AMLt allows octave/offbeat relationships. Standard 17.5 % tempo + phase continuity tolerance.
- **Downbeat F-measure** — F-measure @ ±70 ms over downbeats only; the meter/bar-position check (category 2's lever).
- **Phase-error-vs-time percentiles** — signed phase error (detected − ground-truth, ms) bucketed by time-in-track, reported as p50/p90/p99 per window. This is the BUG-065 curve — the metric that exposes bounded-but-not-tightening drift.
- **Time-to-lock** — seconds from track start until phase error first stays under the perceptual window for a sustained span.
- **Lock %** — fraction of the track with phase error inside the perceptual window (`lock_state` proxy on the live path).
- **Confident-wrong rate** — fraction of frames that are **high-confidence AND phase error > 70 ms**. The category-5 metric: it must be ≈ 0 on true rubato (Clair de Lune) — a confident beat that is wrong is worse than declining to beat.

## The five suites and targets

Copied verbatim from `docs/BEAT_SYNC_PROGRAM_PLAN.md` §1. **Targets provisional until D-B (GT.3 baseline)** — GT.3 ratifies or revises them against the measured baseline.

| # | Category | Suite tracks (new + existing catalog) | Target (proposed — finalized against GT.3 baseline, DECISION D-B) |
|---|---|---|---|
| 1 | Baseline 4/4, strong pulse | Billie Jean, Around the World, Stayin' Alive, Superstition (+ love_rehab, Cherub Rock, Get Lucky, Everlong) | Beat F-measure ≥ 0.95 offline; live phase error p90 < 30 ms held across the full track (closes BUG-065's 50–70 ms mid-track wander); downbeat correct |
| 2 | Odd meters | Take Five (5/4), Money (7/4), Solsbury Hill (7/4), Pyramid Song (grouped 16/8) (+ So What) | Meter decoded correctly on ≥ 3/4; beat F-measure ≥ 0.85; Money no longer REACTIVE on the live path (closes BUG-001 ceiling, BUG-013 workaround-by-decoding) |
| 3 | Mid-song tempo changes | Bohemian Rhapsody, Giorgio by Moroder, Dance Yrself Clean | Grid re-locks within ≤ 20 s of a tempo change (≤ 2 analysis windows); phase error back under 50 ms after re-lock; no confident wrong-tempo pulse during the transition |
| 4 | Dense transients / polyrhythm | Bleed (Meshuggah) (+ There There as the syncopation case) | Quarter-note grid tracked (not the herta subdivisions): beat F ≥ 0.80; There There reads ~86 BPM meter, not the ~140 kick rate |
| 5 | Ambiguous / rubato | Girl from Ipanema (weak-transient steady), Clair de Lune (true rubato) (+ Pyramid Song crossover) | Split target. Ipanema: tracked softly, F ≥ 0.80. Clair de Lune: confident-wrong rate ≈ 0 — beatConfidence stays below the accent threshold ≥ 90% of duration, visuals driven by energy/harmony layers. Success = declining honestly, not faking a beat |

Category 5's second half is the inversion that keeps the program honest: for true rubato the deliverable is a trustworthy confidence signal, not a beat.

## Claim rules

- **The closeout table covers all five suites**, not just the target suite. A dsp.beat behavioral change without a five-suite before/after table (or an explicit "no behavioral change") is an incomplete closeout (`closeout` skill).
- **Report regressions on any suite even when the target suite improves.** Chasing odd meters while regressing baseline 4/4 is the named risk (plan §7); suite-1 no-regression is a hard gate in DBN.3.
- **No window cherry-picking.** Report the full percentile curve and every suite's number; do not quote the one window where the change looks best.
- **No category is claimed won without a benchmark number.** The verifier-passing → M7-failing pattern (six cold-start iterations) is the cost of claiming a win without measurement.

## Ground-truth maintenance

Detailed protocol: plan §GT.2. Summary:

- **Tap protocol.** Ground truth is Matt's tapped beat timestamps captured by the TapCapture CLI (playback-clock timestamps), two passes per track — beats, then downbeats — cross-checked against independent reference tools (madmom DBNBeatTracker + the vendored Beat This! reference, offline annotation tools only, nothing ships; see `reference-port`).
- **Latency calibration.** Each capture session begins with a calibration round (tap to a generated metronome); the median tap→click offset is subtracted from all subsequent taps. The offset is documented alongside the ground truth.
- **Reconciliation.** Where taps and tools agree within 70 ms → ground truth. Disagreements are listed for Matt to resolve by ear (expected concentration: Bleed, Pyramid Song, Clair de Lune — for Clair de Lune "no stable grid" may legitimately be the annotation).
- **Adding a track.** Acquire the fixture into `BEATBENCH_FIXTURES_DIR` (never commit bulky audio; add its content hash + expected duration to the committed manifest), tap it (both passes + calibration), run the reference-tool pass, reconcile, then commit the resulting `<track>.groundtruth.json`.
- **Never hand-edit a groundtruth JSON.** Ground truth changes only through the tap + reconciliation pipeline, so provenance stays intact. Editing the JSON by hand silently corrupts the benchmark's reference.

## CLI invocations

> TO FILL (GT.3): BeatBench CLI invocations for offline-grid / session-replay / live-capture modes

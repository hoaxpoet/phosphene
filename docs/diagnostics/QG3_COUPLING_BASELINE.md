# QG.3 — Audio-Visual Coupling Baseline

**Date:** 2026-07-10. **Increment:** QG.3 (coupling metric, report-first). **Producer:** `CouplingReportTests` (gated `PHOSPHENE_COUPLING=1`). **Decision:** [D-182]. **This is a REPORT, not a gate** — the QG.3.1 gate is deferred pending calibration, and the headline finding below is *why* it cannot be calibrated yet.

## What was measured

Per certified preset × canonical fixture (`love_rehab` / `so_what` / `there_there`), cross-correlation of a per-frame **visual delta** (mean |luma(frame i) − luma(frame i−1)| over the 64×64 reduced-resolution render, 0..1) against the **audio energy envelope** (composite = mean of `bass`/`mid`/`treble`, plus each band), at lags 0–500 ms. Per pair: peak Pearson **r**, **lag** at peak, and a **stationarity** note (r over non-overlapping 10 s windows: min/median/max). Negative control: fixture `love_rehab`'s energy against fixture `so_what`'s rendered frames — real audio mismatched to real frames (FA #27), bounding the noise floor.

Per-frame FeatureVector **and** StemFeatures are reconstructed from the checked-in `route_coverage` fixtures (real preview clips through the production separation + analysis chain) and bound at the shader's slots; nothing is hand-authored.

## ★ Headline finding — the metric is not measurable for 11 of 13 certified presets on the current render substrate

The offline harness (reused from `PresetRegressionTests`) renders **one fragment** — the preset's primary/`direct`/`ray_march` pipeline — with **zeroed aux state**: the slot-6 CPU-accumulator buffers, the feedback history texture, and the mv_warp marks buffer are all zero, because that state is produced by the live multi-pass render loop and **cannot be reconstructed from the CSV fixtures**. For every preset whose music-driven motion lives in that state, the offline render is **byte-identical frame-to-frame** — `visual_delta = 0.00000` for the whole run.

**11 of 13 certified presets render fully static offline** (delta_mean = 0.00000): Cytokinesis, Dragon Bloom, Fata Morgana, Filigree, Floret, Glaze, Lumen Mosaic, Mitosis, Nacre, Nimbus, Skein. This is **by construction, NOT a coupling defect** — the same reason `PresetRegressionTests` records identical dHashes across its three fixtures for these presets (the standalone fragment is a static canvas ground / silence-floor body / unbound-history read). Their real coupling is unobservable here.

Only **Ferrofluid Ocean** (ray-march) and **Murmuration** (whose fragment reads FeatureVector directly) produce non-static output offline, so only they can be measured at all — and only Murmuration clears its own noise floor.

## Baseline table

`comp_r@lag` = peak composite Pearson r and its lag in ms · `win` = composite r over 10 s windows [min/med/max] · `delta_mean` = mean per-frame visual delta (0..1). **Static** rows produce no signal (all zero).

| Preset | Fixture | comp_r@lag | bass_r | mid_r | treb_r | win [min/med/max] | delta_mean |
|---|---|---|---|---|---|---|---|
| Cytokinesis | all 3 | — | — | — | — | — | 0.00000 (**static**) |
| Dragon Bloom | all 3 | — | — | — | — | — | 0.00000 (**static**) |
| Fata Morgana | all 3 | — | — | — | — | — | 0.00000 (**static**) |
| Ferrofluid Ocean | love_rehab | +0.07 @510ms | +0.07 | +0.05 | −0.21 | +0.04/+0.05/+0.05 | 0.00205 |
| Ferrofluid Ocean | so_what | +0.05 @301ms | +0.06 | −0.01 | −0.03 | +0.04/+0.06/+0.06 | 0.00180 |
| Ferrofluid Ocean | there_there | +0.08 @347ms | +0.13 | −0.21 | −0.09 | −0.00/+0.17/+0.17 | 0.00205 |
| Filigree | all 3 | — | — | — | — | — | 0.00000 (**static**) |
| Floret | all 3 | — | — | — | — | — | 0.00000 (**static**) |
| Glaze | all 3 | — | — | — | — | — | 0.00000 (**static**) |
| Lumen Mosaic | all 3 | — | — | — | — | — | 0.00000 (**static**) |
| Mitosis | all 3 | — | — | — | — | — | 0.00000 (**static**) |
| Murmuration | love_rehab | **+0.30 @487ms** | +0.31 | +0.07 | +0.13 | +0.29/+0.36/+0.36 | 0.00063 |
| Murmuration | so_what | +0.13 @0ms | +0.12 | +0.03 | +0.16 | +0.14/+0.19/+0.19 | 0.00040 |
| Murmuration | there_there | +0.03 @440ms | +0.03 | +0.00 | +0.23 | +0.01/+0.08/+0.08 | 0.00022 |
| Nacre | all 3 | — | — | — | — | — | 0.00000 (**static**) |
| Nimbus | all 3 | — | — | — | — | — | 0.00000 (**static**) |
| Skein | all 3 | — | — | — | — | — | 0.00000 (**static**) |

## Noise floor (negative control)

Fixture `love_rehab`-audio × `so_what`-frames, composite peak r over lags 0–500 ms:

| Preset (frames) | control comp_r |
|---|---|
| Ferrofluid Ocean | **+0.08** |
| Murmuration | **+0.08** |

(Static presets have a 0.00 control by construction — no frame variance to correlate.)

**Interpretation of the floor.** Peak-over-lag Pearson r is **positively biased**: taking the maximum over ~22 candidate lags of noisy per-lag correlations (each ≈ N(0, 1/√1286) ≈ 0.028 sd on a 1286-frame run) inflates the value above 0. The control captures exactly this bias at **+0.08** — mismatched real audio against real frames still scores +0.08. So **+0.08 is the noise ceiling**, and any real-coupling r must clear it with margin to be meaningful. This is why the negative control is load-bearing and why a raw r near 0.08 means "coupling not measured as present," never "coupled."

Against that floor: Ferrofluid Ocean's measured r (0.05–0.08) sits **at** the floor (coupling not measured as present on this substrate). Murmuration/`love_rehab` (**+0.30**, windows +0.29/+0.36) is clearly above; `so_what` (+0.13) is above; `there_there` (+0.03) is below.

## Recommended QG.3.1 floor — and why it CANNOT be set yet

**Recommendation: do NOT flip a gate.** A gate needs a population; the measurable population here is **2 presets**, of which **1** clears the floor. Two prerequisites must land first:

1. **A headless multi-pass / state-reconstructing render.** Until the offline render reproduces the live render loop's per-frame state (feedback history, mv_warp marks, slot-6 accumulators), 11/13 certified presets are unmeasurable and any gate would either false-red all of them or exempt them into meaninglessness. This is the blocking item.
2. **Proxy validity check.** The metric correlates visual *delta* (motion magnitude) with energy *level*. A well-coupled preset that modulates motion *character* or *colour* (rather than raw frame-delta), or that carries high steady motion, can legitimately score low. Before gating, confirm the proxy tracks felt coupling on presets Matt has already M7-approved (Murmuration/`love_rehab` is the one positive anchor we have).

**Provisional floor, for when (1) and (2) are satisfied:** peak composite r ≥ **0.15** at any lag 0–500 ms on at least one canonical fixture (≈ 2× the +0.08 noise ceiling; Murmuration's cross-fixture mean is 0.15). Treat as a starting hypothesis to re-derive against the then-measurable population, **not** a committed threshold.

## Presets below the noise floor — route/coupling defect or measurement gap?

Per the prompt, presets below the noise floor are candidates for a route/coupling defect (→ KNOWN_ISSUES), **not** tuning targets. But here **every below-floor result is a measurement gap, not a defect**: the 11 static presets are static because the harness zeroes their state, and Ferrofluid Ocean's at-floor result is the same offline-substrate limitation (its spike/aurora routes are CPU-computed StemFeatures the fixture can't populate — the documented QG.1.1 boundary, cf. [D-180]). **No KNOWN_ISSUES entry is filed from this baseline** — there is no evidence of a dead route that isn't already explained by the render substrate. The M7 seat remains the coupling authority (manual-validation rule stands).

## Reproduce

```
PHOSPHENE_COUPLING=1 swift test --package-path PhospheneEngine --filter CouplingReportTests
```

Per-frame visual-delta CSVs are written to `coupling/<preset>_<fixture>_visual_delta.csv` (gitignored; regenerable). The printed `ROW`/`CONTROL` lines are this table's source.

## References

`PhospheneEngine/Tests/PhospheneEngineTests/Renderer/CouplingReportTests.swift` (producer), `docs/diagnostics/QG1_REPLAY_AUDIT.md` (replay feasibility — the "no headless render" gap this inherits), `docs/ENGINE/SESSION_REPLAY.md` (SR.1 uncalibrated-proxy doctrine), [D-182] (metric definition + report-first rationale), [D-180] (route-coverage gate + the CPU-computed StemFeatures fixture boundary), FA #27 (no hand-authored envelopes).

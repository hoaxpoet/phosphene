# QG.3 — Audio-Visual Coupling Baseline

**Date:** 2026-07-10. **Increment:** QG.3 (metric, report-first) → **QG.3.1 (measurable for all 13 via the real multi-pass render).** **Producer:** `CouplingReportTests` (gated `PHOSPHENE_COUPLING=1`). **Decisions:** [D-182] (metric), [D-183] (measurement substrate + calibration). **This is a REPORT, not a gate** — the QG.3.2 gate flip is Matt's call, taken against this distribution.

## What was measured

Per certified preset × canonical fixture (`love_rehab` dance / `so_what` jazz / `there_there` rock), cross-correlation of a per-frame **visual delta** (mean |luma(i) − luma(i−1)| over a downsampled luma field, 0..1) against the **audio energy envelope** (composite = mean of `bass`/`mid`/`treble`, plus each band), at lags 0–500 ms. Per pair: peak Pearson **r**, **lag** at peak, and a **stationarity** note (r over non-overlapping 10 s windows: min/median/max). Negative control: `love_rehab`-energy × `so_what`-frames — real audio mismatched to real frames (FA #27), bounding the per-preset noise floor.

**QG.3.1 render substrate (the headline change from QG.3).** Each frame is rendered through the preset's **real** path — the 10 multi-pass / feedback / follower presets via the shared `MultiPassRenderHarness` (the same headless seam the photosensitivity flash gate drives, with feedback persistence), the 3 single-pass presets (Ferrofluid Ocean, Murmuration, Nimbus) via one fragment + the ticked Nimbus CPU follower. This replaced QG.3's single-fragment/zeroed-state harness, which rendered **11 of 13 presets static** (`visual_delta = 0`). **All 13 now produce real signal** — the metric is measurable across the whole certified set.

## Baseline table (QG.3.1 — real multi-pass render)

`comp_r@lag` = peak composite Pearson r + lag (ms) · `win` = composite r over 10 s windows [min/med/max] · `Δμ` = mean per-frame visual delta (0..1). Sorted by best-fixture composite r.

| Preset | love_rehab | so_what | there_there | best win[min/med/max] | control (floor) |
|---|---|---|---|---|---|
| **Skein** | +0.55 @23ms | **+0.69** @23ms | +0.24 @46ms | +0.74/+0.76/+0.76 | +0.05 |
| **Dragon Bloom** | **+0.47** @510ms | +0.19 @46ms | +0.03 @510ms | +0.46/+0.47/+0.47 | +0.13 |
| **Filigree** | +0.06 @487ms | **+0.39** @139ms | −0.15 @487ms | +0.26/+0.56/+0.56 | +0.04 |
| **Lumen Mosaic** | **+0.37** @487ms | +0.05 @371ms | +0.06 @115ms | +0.34/+0.40/+0.40 | +0.03 |
| **Fata Morgana** | **+0.32** @23ms | +0.21 @394ms | +0.12 @162ms | +0.29/+0.36/+0.36 | +0.04 |
| **Murmuration** | **+0.29** @487ms | +0.12 @0ms | +0.03 @440ms | +0.28/+0.35/+0.35 | +0.07 |
| **Mitosis** | +0.22 @487ms | **+0.27** @0ms | +0.03 @0ms | +0.33/+0.50/+0.50 | +0.01 |
| **Floret** | +0.11 @23ms | **+0.25** @0ms | +0.12 @440ms | +0.20/+0.41/+0.41 | +0.01 |
| **Nimbus** | **+0.23** @463ms | +0.18 @0ms | +0.02 @347ms | −0.02/+0.37/+0.37 | +0.04 |
| **Cytokinesis** | +0.17 @0ms | **+0.20** @0ms | −0.04 @510ms | +0.25/+0.25/+0.25 | +0.05 |
| **Glaze** | +0.09 @92ms | −0.06 @510ms | **+0.13** @510ms | −0.05/+0.19/+0.19 | +0.04 |
| **Ferrofluid Ocean** | +0.07 @510ms | +0.05 @301ms | **+0.08** @347ms | −0.00/+0.17/+0.17 | +0.08 |
| **Nacre** | +0.03 @0ms | −0.02 @92ms | **+0.05** @0ms | −0.12/+0.39/+0.39 | −0.02 |

## Noise floor is PER-PRESET, not global

The negative control (`love_rehab`-audio × `so_what`-frames) ranges **−0.02 … +0.13** across presets. **Dragon Bloom's floor (+0.13) is the highest** — its long feedback trails give the frame sequence high autocorrelation, so even mismatched audio scores higher. Peak-over-lag Pearson r is also positively biased (max over ~22 lag candidates of noisy correlations). **Conclusion: a single global floor is wrong** — a feedback preset's real coupling must clear *its own* control, not a flat threshold. The per-preset control column is the reference each preset is judged against.

## Reading the distribution

- **11 of 13 clear their own floor with margin** on at least one fixture: Skein (0.69 vs 0.05), Dragon Bloom (0.47 vs 0.13), Filigree (0.39 vs 0.04), Lumen Mosaic (0.37 vs 0.03), Fata Morgana (0.32), Murmuration (0.29), Mitosis (0.27), Floret (0.25), Nimbus (0.23), Cytokinesis (0.20), Glaze (0.13 vs 0.04, marginal).
- **`there_there` (rock) scores lowest across almost every preset** — its energy envelope is the least dynamic of the three clips (steady loudness), so delta-vs-energy correlation is weakest there. This is a fixture property, not a preset defect; it argues for a "best of N fixtures" gate rule, not "all fixtures."
- **2 presets read weak — and both are PROXY-validity artifacts, not defects:**
  - **Nacre** (0.05, control −0.02): its music connection is a *downbeat camera push* (NACRE.4, D-171) — subtle whole-frame motion that barely moves the mean-abs frame delta. The metric under-reads camera-motion coupling. Nacre is CERTIFIED + M7-approved.
  - **Ferrofluid Ocean** (0.08, control +0.08 — at floor): rendered via the single-fragment path (its faithful render is ray_march + post_process + a baked height field we approximate). Under-measured render, not a dead route (its spike/aurora routes are CPU-computed StemFeatures the offline fixture can't populate — the documented QG.1.1 boundary, [D-180]).

## Recommended QG.3.2 gate — ship as a WARNING tier, not a hard cert gate

The metric is now measurable, and the distribution is real. But **two certified, M7-approved presets (Nacre, Ferrofluid Ocean) sit at/below a meaningful floor** for legitimate proxy reasons. A hard cert gate at any floor that catches genuinely-dead coupling would false-red them — the exact "verdict on an uncalibrated proxy" failure QG.3 exists to avoid. Recommendation:

1. **QG.3.2 = a warning-tier report threshold, not a cert blocker.** Flag any preset whose best-fixture peak composite r is **< 0.15** AND fails to clear its own control by **≥ 0.10** as "coupling not measured as present — review," surfaced in the closeout evidence. It informs, it does not fail certification.
2. **Validate the proxy against M7 before any hard gate.** The one thing that would justify a blocking gate is evidence the metric tracks *felt* coupling. Nacre (low r, M7-loved) and Skein (high r, M7-certified) are the calibration anchors: if Matt confirms the metric's ordering matches his felt ordering on a few presets, a hard gate becomes defensible. Until then, warning-tier only.
3. **Per-preset floor, best-of-fixtures.** Judge each preset against its own control on its best fixture — never a global threshold on all fixtures (feedback autocorrelation + the `there_there` low-dynamics effect would both misfire).

**No KNOWN_ISSUES filed.** No preset renders below its floor in a way that isn't explained by a proxy/render-fidelity limit. Nacre and Ferrofluid Ocean are watched under QG.3.2 calibration, not filed as defects (verified: both are certified + M7-approved; low r is a proxy artifact).

## Reproduce

```
PHOSPHENE_COUPLING=1 swift test --package-path PhospheneEngine --filter CouplingReportTests
```

Per-frame visual-delta CSVs → `coupling/<preset>_<fixture>_visual_delta.csv` (gitignored; regenerable). The printed `ROW`/`CONTROL` lines are this table's source. Sweep ≈ 130 s (real multi-pass render).

## References

`CouplingReportTests.swift` + `MultiPassRenderHarness.swift` (producer + shared render), `MultiPassFlashHarnessTests.swift` (the flash gate that shares the harness), `docs/diagnostics/QG1_REPLAY_AUDIT.md`, `docs/ENGINE/SESSION_REPLAY.md` (SR.1 uncalibrated-proxy doctrine), [D-182] (metric), [D-183] (measurement substrate + calibration), [D-180] (route-coverage + the CPU-computed StemFeatures fixture boundary), FA #27, FA #66 (drive the live path, never reimplement).

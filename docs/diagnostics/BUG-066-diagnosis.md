# BUG-066 — MoodClassifier flux input ran 16× hot on the offline path (diagnosis + fix)

**Severity:** P2 · **Domain:** ml.mood / dsp.mir · **Class:** regression / pipeline-wiring (not calibration — see the correction below)
**Filed:** 2026-07-08 (MOOD-FLUX.1) · **Fixed:** 2026-07-08 (MOOD-FLUX.2) — code-complete, **pending Matt's live M7 (before/after preset picks)**.
**Surfaced by:** CENSUS.3 pilot (`docs/diagnostics/CENSUS_PILOT_REPORT.md` §3).

## Expected behavior

The MoodClassifier z-scores its 10 inputs against the scaler baked into `MoodClassifier.swift` (`scalerMeans`/`scalerStds`, mirrored in `tools/data/mood_scaler.json`). Those stats were fit on the **live** MIR pipeline's feature distribution (the model was retrained on live-pipeline annotated features, commit `d586e57`, Apr 2026). `spectralFlux` (input [7]) has scaler mean **0.25**, std **0.20**; a track's flux should z-score to a few sigma.

## Actual behavior

Across the 1,000-track pilot the **offline** session-prep flux input mean is **8.06** (z ≈ **+38**) — saturated far past range on every track. Band energies and centroid match the scaler within ~20 %. Only flux is off, by a uniform **16×**.

## Reproduction

`.build/release/CorpusCensusRunner --manifest tools/data/corpus_pilot_1000.csv …` then compare column `feat7` mean against `mood_scaler.json.means[7]`. The census mirrors the production `SessionPreparer.analyzeMIR` offline path exactly.

## Session artifacts

- `CENSUS_PILOT_REPORT.md` §3 (feature means/stds vs scaler).
- `~/phosphene_features_annotated.csv` (the live training set) — flux mean **0.2516**, identical to the scaler; proves the model is correctly calibrated to the **live** pipeline.
- The two feature-extraction code paths, below.

## Root cause (corrected — this is NOT a DEAM/train-vs-inference mismatch)

The initial framing (DEAM-training-vs-runtime) was **wrong**: the shipped model was retrained on live features (`d586e57`), and the live training CSV's flux mean (0.2516) matches the scaler feature-for-feature. The model is correct.

The real cause is a **live-vs-offline feature-path divergence**. The offline session-prep path (`SessionPreparer.analyzeMIR.computeFFTMagnitudes`) **reimplemented** the FFT magnitude formula differently from the live `Audio/FFTProcessor`:

| | Live `FFTProcessor.runFFTCore` | Offline `analyzeMIR.computeFFTMagnitudes` (pre-fix) |
|---|---|---|
| Magnitude | `vDSP_zvabs` → **\|FFT\|** | `vDSP_zvmags` → **power** |
| Scale | `× 2 / fftSize` → \|FFT\|/512 | `/ fftSize` then `sqrt` → \|FFT\|/32 |
| Net | \|FFT\|/512 | **\|FFT\|/32 → 16× larger** |
| Hop | 1024 non-overlapping (`AudioInputRouter` chunk) | 1024 non-overlapping — **same** |

Both paths feed the **same** `MIRPipeline`/`SpectralAnalyzer`. Spectral flux is fed **raw** into the classifier's z-score (`MIRPipeline.swift:66` — "not normalized, for mood classifier z-score input"), so it is the only feature exposed to the 16× magnitude difference. Band energies are AGC-normalized and centroid/chroma are ratios → scale-invariant → they matched despite the divergence. That is the discriminator. (Confirmed empirically: the pre/post flux ratio is exactly **16.000** on every track, σ=0.)

`analyzeMIR` sets `TrackProfile.mood`, which the planner scores presets on before playback. So the **offline (pre-playback) mood was saturated; the live mood was always fine**. Mood is 30 % of `DefaultPresetScorer`, so preset selection ran on 9 effective features. No crash / plausible values from the other 9 → P2.

## Fix (MOOD-FLUX.2)

One-line-of-intent change in `SessionPreparer+Analysis.swift` (and its census mirror `CensusAnalysis.swift`): make the offline magnitude formula **byte-identical to the live `FFTProcessor`** — `vDSP_zvabs` + `× 2/fftSize` instead of `sqrt(power/fftSize)`. Only the raw-flux-fed feature moves; ratio/AGC features are invariant.

## Verification

1. **Automated:** flux z-score **+38 → +1.43** (un-saturated); the 16× correction is **uniform** across tracks (σ=0), so it generalizes corpus-wide without a re-run. Full mood/MIR/session-prep/spectral suites green (103 tests), incl. `MoodClassifierGolden` (unchanged — the fix is feature-extraction, not the classifier).
2. **Blast radius** (measured, 40-track pre/post): `mir_bpm` **0/40 changed**; `key_class` shifted 6/40 and only empty→resolved (harmless; key is unused, BUG-054); centroid ~unchanged (ratio). The change aligns the *entire* offline MIR feature scale to live — a broader correctness improvement — but with benign collateral.
3. **Manual (required, outstanding):** Matt reviews before/after **preset picks** on known tracks. Mood is taste-bearing; a green parity test is necessary, not sufficient. **This gate is open** — MOOD-FLUX.2 is code-complete, not resolved, until Matt confirms live.

## Related

- `CENSUS_PILOT_REPORT.md` §3 is the pre-fix measurement (the finding); the fix landed after.
- BUG-054 (dsp.key) — separate weak-key issue.
- The live path was never affected; no live regression.

# BUG-066 — MoodClassifier flux input is ~32× the scaler's trained scale (diagnosis)

**Severity:** P2 · **Domain:** ml.mood / calibration · **Class:** calibration / api-contract
**Filed:** 2026-07-08 (MOOD-FLUX.1, instrument→diagnose — no fix code) · **Surfaced by:** CENSUS.3 pilot (`docs/diagnostics/CENSUS_PILOT_REPORT.md` §3)
**Status:** diagnosed; fix scoped as MOOD-FLUX.2 (awaiting Matt's option pick).

## Expected behavior

The MoodClassifier z-scores its 10 inputs against `tools/data/mood_scaler.json` (means/stds fit during DEAM training), so each input should land within a few sigma of the scaler's mean and the MLP should see all 10 features in their trained range. `spectralFlux` (input [7]) has scaler mean **0.25**, std **0.20** — a typical track's flux should z-score to roughly `[-1, +3]`.

## Actual behavior

Across the 1,000-track pilot the per-track mean of the runtime flux input is **8.06** (std 6.66) — the flux z-score is `(8.06 − 0.25) / 0.20 ≈ +38`. The flux channel is **saturated far past the trained range on essentially every track**. The other nine inputs are fine: band energies (feat0–5) sit within ~20 % of the scaler, centroid within ~26 %. Only flux is off, and it is off by **~32×**, not a distribution difference.

Measured means/stds (pilot, n=993), from `CENSUS_PILOT_REPORT.md §3`:

```
feature      deploy_mean  DEAM_mean  Δmean(σ)  std_ratio
flux            8.05583     0.25158    +38.17     32.59
centroid        0.09889     0.11827     -0.26      0.57
subBass         0.12909     0.12720     +0.02      0.54
lowBass         0.24552     0.20594     +0.30      0.49
```

## Reproduction

Deterministic; not track-specific (fires on every track). Minimum reproducer:
`.build/release/CorpusCensusRunner --root <corpus> --manifest tools/data/corpus_pilot_1000.csv --out <csv>` then compare column `feat7` mean against `mood_scaler.json.means[7]`. The same feature path runs in production `SessionPreparer.analyzeMIR`.

## Session artifacts

- `CENSUS_PILOT_REPORT.md` §3 (feature means/stds vs scaler) — the primary artifact.
- Code paths compared below.

## Root cause

The DEAM training feature extractor and the runtime mood feature path compute **spectral flux with different STFT parameters**, and flux — an unnormalized frame-to-frame difference sum — is fed **raw** into the classifier's z-score, so it is the only feature exposed to the mismatch.

| Parameter | Training (`tools/train_mood_classifier.py`) | Runtime (`SessionPreparer.analyzeMIR` + census `CensusAnalysis.runMIR`) |
|---|---|---|
| STFT hop | `librosa.stft(hop_length=512)` — 50 % overlap | `offset += fftSize` — **hop 1024, non-overlapping** |
| Magnitude norm | `stft * (2.0 / fftSize)` = ÷512 | `sqrt(power / fftSize)` = ÷√1024 = ÷32 → **16× larger** |
| Sample rate | fixed 48 000 | file-native (44 100 typical) |
| Flux formula | `sum(max(mag[t]−mag[t−1], 0))`, track-**mean** | `SpectralAnalyzer.computeFlux` (same form), EMA(α=0.25), census track-mean |

Two multiplicative effects both inflate runtime flux: the **16× magnitude-normalization** difference (flux is linear in magnitude), and the **hop/overlap** difference (non-overlapping frames are 1024 samples apart, so adjacent spectra differ more → larger rectified diff, ~2×). 16 × ~2 ≈ **32×**, matching the observed gap.

**Why only flux is affected** (`PhospheneEngine/Sources/DSP/MIRPipeline.swift`):
- **flux** — line 66 comment: *"Raw smoothed spectral flux (not normalized). For mood classifier z-score input."* Fed **raw** → fully exposed to magnitude scale + hop.
- **band energies** — `bandEnergyProcessor` applies total-energy AGC → scale-invariant → immune.
- **centroid** — a magnitude-weighted frequency **ratio**, then ÷Nyquist → invariant to magnitude scale and (nearly) to hop.

So band/centroid match the scaler regardless of the STFT-parameter divergence; flux does not. This is the discriminator that confirms the cause.

## Impact

`TrackProfile.mood` (valence/arousal) is produced by this offline path and is **30 % of `DefaultPresetScorer`'s weight** — the largest single factor in which visualizer each track receives. With the flux z-score pinned at ~+38 on every track, the MLP's flux input is effectively a saturated constant: **mood — and therefore preset selection — has been running on 9 effective features on every session** since the scaler and the runtime feature path diverged. Not a crash and not silent-fail (mood still produces plausible values from the other 9), which is why it went unnoticed — hence P2, not P1.

## Suspected failure class

`calibration` (the scaler is fit against a feature scale the runtime does not produce) compounded by `api-contract` (the training extractor's comment claims to "match Phosphene's MIRPipeline" but uses a different hop and magnitude normalization).

## Verification criteria (written before the fix)

A fix is accepted only when **both** hold:

1. **Automated:** re-running the census (or a `MoodFeatureParityTests` unit) shows the flux input's deployment mean within a small multiple (≤ ~2×) of the scaler mean, i.e. the flux z-score is no longer saturated (|z| for a typical track < ~4); the MoodClassifier golden-fixture test is regenerated and green; band/centroid features are unchanged.
2. **Manual (required — musical feel):** Matt reviews before/after **preset picks** on a set of known tracks. Mood is a taste-bearing output; a green parity test proves the pipeline is consistent, not that the resulting mood (and the presets it selects) reads right. No automated metric substitutes.

## Fix options (→ MOOD-FLUX.2, Matt's call)

1. **(Recommended) Regenerate the mood model against the real runtime features, on the corpus.** Fix the extractor to use the runtime STFT params (hop 1024, `÷√fftSize`, native-rate handling), re-extract features, re-fit `mood_scaler.json`, and retrain the MLP — on the 28k in-domain corpus (§5 Tier-2) rather than the 1,802 DEAM excerpts, since a retrain is required regardless. Correct + durable + upgrades the weakest shipped model. Needs the manual before/after M7 pass.
2. **Scale-correct flux at the runtime boundary (stopgap).** Divide `rawSmoothedFlux` by ~32 before the classifier. Cheap, un-pins the channel this week, but a magic constant over a real divergence (the hop factor is not a clean constant). Fragile; only as a bridge.
3. **Re-fit the scaler alone on corpus stats — rejected.** The MLP weights were trained on DEAM-scaled flux; re-scaling only the scaler misaligns weights ↔ inputs. Collapses into (1) once the retrain is acknowledged.

## Related

- BUG-054 (dsp.key) — separate weak-signal issue (key), not this.
- `docs/research/CORPUS_ML_OPPORTUNITIES.md` §5 — the mood-model calibration/retrain opportunity this fix realizes.

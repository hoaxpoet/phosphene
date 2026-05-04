# DSP.2 S8 — Layer-Diff Handoff Prompt

Use this as the agent prompt for the next session. Self-contained: assumes no memory of prior context.

---

## The bug

`BeatThisModel.predict` in `PhospheneEngine/Sources/ML/` produces structurally degraded
output on real audio. On `PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a` (29.9 s
of 4/4 electronic music, ~125 BPM):

| | Swift `BeatThisModel` | Python ref `beat_this.load_model('small0')` |
|---|---|---|
| `max(sigmoid(beat_logits))` | **0.295** | **0.9999** |
| `mean(sigmoid)` | 0.21 | 0.090 |
| frames > 0.5 (peak-pick threshold in `BeatGridResolver`) | **0** | **124** |

The Swift output is **flat** — no peaks at beat positions, slightly elevated
baseline. `BeatGridResolver.resolve` therefore returns an empty `BeatGrid` for every
track. Production effect: every Spotify-prepared session installs `.empty` in
`StemCache`; `MIRPipeline.liveDriftTracker.hasGrid == false`; `MIRPipeline.buildFeatureVector`
falls through to the legacy `BeatPredictor` IIR estimator every frame. **DSP.2 S7's
drift tracker is wired correctly but dormant in production.** Lifting `withKnownIssue`
on `Tests/.../ML/BeatThisModelTests.test_loveRehab_endToEnd_producesBeats` (asserts
`max>0.9` and `≥50 frames>0.5`) is the pass/fail signal for "S7 actually engaged."

Lowering the resolver threshold experimentally to 0.15 produced 173 false-positive
"beats" at 366 BPM on the 125 BPM track, confirming the bug is **structural** (no
useful signal at any threshold), not calibration. So fixing this is a model-internals
problem, not a postprocessing tweak.

## What's already done (committed at HEAD = `f18acce3` on `origin/main`)

1. **Python venv set up** at `/tmp/beat_this_venv` (regeneratable from the recipe in
   `.gitignore`). `torch`, `torchaudio`, `einops`, `soxr`, `rotary-embedding-torch`,
   `soundfile`, plus the Beat This! repo cloned at the pinned commit
   `9d787b9797eaa325856a20897187734175467074` under `vendor/beat_this_repo/`. Both
   regeneratable; neither committed.
2. **Python activation-dump script** at `Scripts/dump_beatthis_activations.py`. Runs
   the canonical `load_model('small0')` on any audio file, registers forward hooks at
   every major sub-module, dumps per-stage tensor stats (shape, min, max, mean, std)
   plus first 32 and last 32 flattened values. Output is JSON matching the schema
   below.
3. **Reference output** at `docs/diagnostics/DSP.2-S8-python-activations.json`: 34
   stages from the Python forward pass on `love_rehab.m4a`. This is the ground-truth
   oracle for the diff. Stage list:
   ```
   input.spect
   stem.{bn1d, conv2d, bn2d, activation}
   frontend.blocks.{0,1,2}.{partial, conv2d, norm, activation}
   frontend.linear
   transformer.{0..5}.{attn, ffn}
   transformer.norm
   head.linear
   output.{beat_sigmoid, beat_logits}
   ```
4. **Failing-as-expected golden test** at
   `Tests/.../ML/BeatThisModelTests.swift::test_loveRehab_endToEnd_producesBeats`.
   Wrapped in `withKnownIssue("BeatThisModel produces sub-threshold output …")`;
   suite stays green and the failure is recorded. Removing the wrapper is the milestone.
5. **CLAUDE.md updated**: S7 status flipped to "code complete but production-dormant",
   DSP.2 S8 added as the new top-priority "next ordered increment".

## What you need to build in this session

### Step 1: Swift activation-dump infrastructure

Goal: produce the same 34-stage JSON dump from the Swift `BeatThisModel` so the two
can be diffed numerically.

**Files to read first**:
- `PhospheneEngine/Sources/ML/BeatThisModel.swift` — entry point, `predict`,
  `predictCore`, `predictIncludingFrontendOutput`. The `CorePrediction` struct already
  carries `frontendShape`; extend it to carry actual values for many stages.
- `PhospheneEngine/Sources/ML/BeatThisModel+Graph.swift` — `buildGraph` is the top-level
  graph builder. Stage names already implicitly present via `name:` parameters
  (`"fe"`, `"blk0"…"blk5"`, `"pn"`, `"head"`, `"beat_sum"`, `"beat_sig"`).
- `PhospheneEngine/Sources/ML/BeatThisModel+Frontend.swift` — `buildFrontend`,
  `buildStemConv`, frontend block construction.
- `PhospheneEngine/Sources/ML/BeatThisModel+Weights.swift` — weight load + BN fusion.

**Plan**:

1. Extend `BeatThisGraphBundle` (defined in `BeatThisModel.swift`) with an optional
   `[String: MPSGraphTensor]` of intermediate tensors keyed by the same names as
   the Python dump (`"stem.bn1d"`, `"stem.conv2d"`, `"frontend.blocks.0.partial"`,
   etc.). Don't break the existing four-field struct; add the dict as a new property.
2. Modify `buildFrontend` and `buildTransformerBlock` to RETURN the intermediate
   tensors they produce internally, in addition to the final tensor they already
   return. Easiest pattern: change the return type from `MPSGraphTensor` to a small
   tuple/struct containing the final tensor plus a labelled list of intermediates.
   Then `buildGraph` aggregates everything into the new dict.
3. Add a `predictWithDiagnostics(spectrogram:frameCount:) throws -> [String: [Float]]`
   method on `BeatThisModel`. Mirrors `predictCore` but adds every intermediate
   tensor to `targetTensors` of the `graph.run` call, reads each result back, and
   returns a dict keyed by stage name.
4. Be careful with shapes — Python's hooks return tensors in CHW + time order
   (e.g. `[1, 32, 32, 1497]` for `stem.conv2d`). MPSGraph's intermediate tensors may
   use a different layout (NHWC vs NCHW) per how the conv ops are configured. The
   diff script needs to know which axes to compare; see the `last32` field in the
   Python JSON — those values come from a flat row-major view, so getting the same
   ordering on the Swift side requires either matching layout or doing an explicit
   reshape before flattening.
5. **Ship a Swift CLI `BeatThisActivationDumper`** under
   `PhospheneEngine/Sources/BeatThisActivationDumper/`, mirroring the
   `TempoDumpRunner` / `QualityReelAnalyzer` pattern (`@main` struct, `ParsableCommand`,
   ffmpeg subprocess for audio decode). Args: `--audio`, `--out`. Produces JSON at
   `docs/diagnostics/DSP.2-S8-swift-activations.json` matching the Python schema.

   **Don't name the file `main.swift`** — that triggers Swift's script-mode parsing
   and breaks `@main`. Name it `BeatThisActivationDumper.swift` and put any helpers
   (e.g. `Report.swift`-style file) alongside. (`QualityReelAnalyzer` had this same
   issue and the fix is documented in commit `36cbded8`.)

### Step 2: Diff script

Write a Python script `Scripts/diff_beatthis_activations.py` that loads both JSONs,
walks them stage-by-stage, and prints a comparison table:

```
Stage                           Py max     Sw max     Δ max     Py mean    Sw mean    Δ mean    Verdict
input.spect                     +9.126     +9.126    +0.000    +3.551     +3.551    +0.000     ✓ match
stem.bn1d                       +3.351     +3.351    +0.000    +0.154     +0.154    +0.000     ✓ match
stem.conv2d                     +1.632     +0.213    -1.419    +0.003     +0.001    -0.002     ✗ FIRST DIVERGENCE
…
```

Where "FIRST DIVERGENCE" is the topmost stage with relative |Δ| > 1e-3 in either
max or mean (or first 32 values bin-by-bin). That stage's implementation is where the
bug lives. Print a clear "FIRST DIVERGENCE: <stage>" banner above the table.

### Step 3: Fix

Inspect the implementation of the first-divergence stage. Most likely culprits per
project history:

- **Weight reshape order in `BeatThisModel+Weights.swift`.** Python conv weights
  are OIHW = [out_channels, in_channels, kH, kW]. MPSGraph 2D convs typically expect
  HWIO. Existing comment in CLAUDE.md notes "conv weights rearranged OIHW→HWIO at
  load time" — verify the rearrange is actually correct. The first conv (`stem.conv2d`)
  is `1→32 channels, 4×3 kernel, stride 4×1, no bias`. If the rearrange is wrong,
  the conv output shape is right but the values are scrambled.
- **BN fusion direction in `fuseBeatThisBN`** (BeatThisModel+Weights.swift line ~176).
  PyTorch BN uses `(x - mean) / sqrt(var + eps) * gamma + beta`. Fusing this into the
  preceding conv requires multiplying conv weights by `gamma / sqrt(var + eps)` and
  adjusting bias. Easy to get the sign or the order wrong.
- **RoPE table indexing across the 6 transformer blocks.** Single shared table at
  `BeatThisModel+Graph.swift:103-131`. Each block applies it inside its attention.
  Python's `RotaryEmbedding(head_dim=32)` produces a per-head freqs vector; verify
  the Swift table matches dimension-by-dimension.
- **PartialFTTransformer block construction order in `BeatThisModel+Frontend.swift`**.
  The PyTorch PartialFTTransformer applies F-direction attention then T-direction
  attention with batched-and-rearrange logic. If the order is swapped or the
  rearrange axes are wrong, the output shape would still be right but values would be
  garbage.

Once the first-divergence stage is identified, the fix is usually a 1-5 line change.
Then re-run the dumps and confirm subsequent stages converge.

### Step 4: Lock the regression

- Remove the `withKnownIssue { … }` wrapper in
  `Tests/.../ML/BeatThisModelTests.swift::test_loveRehab_endToEnd_producesBeats`.
  Test should now pass cleanly.
- Run the full DSP suite (`swift test --package-path PhospheneEngine --filter "DSP|ML"`)
  to verify no regressions in other tests.
- Re-run `QualityReelAnalyzer` against
  `~/Documents/phosphene_sessions/2026-05-04T22-44-35Z/raw_tap.wav` (or a fresh session
  if you re-record). Should now produce a non-empty BeatGrid with sensible BPM and
  beat count.
- Update `CLAUDE.md` and `docs/ENGINEERING_PLAN.md`: flip DSP.2 S8 to ✅, flip S7 to
  "fully ✅ pending Matt's reel sign-off", update test counts.

### Step 5: Hand-off back to Matt for visual sign-off

The actual reel re-record + Pyramid Song / Money / so_what watch is gated on the model
fix landing. After Step 4, post the green-light: "BeatThisModel fixed at commit
`<hash>`. Drift tracker is live in production. Re-record reel via the existing
workflow (`PHOSPHENE_FULL_RAW_TAP=1` env var, Spotify-connected playlist with
Pyramid Song + Money appended)." Then it's Matt's call to actually watch.

## Done when

- [ ] `Swift QualityReelAnalyzer` produces non-empty BeatGrid on
      `~/Documents/phosphene_sessions/<session>/raw_tap.wav`.
- [ ] `Tests/.../ML/BeatThisModelTests.test_loveRehab_endToEnd_producesBeats` passes
      without `withKnownIssue`.
- [ ] `Scripts/diff_beatthis_activations.py` shows `✓ match` (relative |Δ| < 1e-3) on
      every stage on `love_rehab.m4a`.
- [ ] Full DSP test suite green; no SwiftLint regressions on touched files.
- [ ] CLAUDE.md status flipped, ENGINEERING_PLAN.md updated, all changes pushed.

## What NOT to do

- Don't lower the `BeatGridResolver.probThreshold` to "fix" the symptoms. Already
  tried; produces false-positive beats at wrong tempos (173 beats at 366 BPM on a
  125 BPM track). The bug is structural, not calibration.
- Don't skip Step 1 and try to spot the bug by reading the 1565 lines of model code.
  The layer-diff is the only way to localise without burning hours.
- Don't commit `vendor/beat_this_repo` or `/tmp/beat_this_venv`. Both regeneratable
  per `.gitignore`.
- Don't remove or modify the `withKnownIssue` golden test until the fix is in place
  and the diff shows match — that test is the regression sentinel.

## Reference: Python schema

The JSON the Swift dumper must produce, matching `docs/diagnostics/DSP.2-S8-python-activations.json`:

```json
{
  "source": "PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a",
  "variant": "small0",
  "n_stages": 34,
  "stages": [
    {
      "name": "input.spect",
      "shape": [1, 1497, 128],
      "dtype": "torch.float32",
      "min": 0.252,
      "max": 9.126,
      "mean": 3.551,
      "std": 1.234,
      "first32": [...],
      "last32": [...]
    },
    ...
  ]
}
```

`shape` and `dtype` are nice-to-have for the Swift side; the diff script should be
robust to formatting differences. What matters is that `min`, `max`, `mean`, `std`,
`first32`, `last32` are present at each named stage.

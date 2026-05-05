# DSP.2 S7/S8 Regression Hardening — Handoff Prompt

Use this as the agent prompt for a session focused on locking in DSP.2's
correctness against future regressions. Self-contained: assumes no memory
of prior context.

---

## Why this matters

DSP.2 S7 (`LiveBeatDriftTracker`) and S8 (BeatThisModel four-bug fix)
landed at HEAD `c9e2626e` on `origin/main`. The model now produces output
numerically equivalent to the PyTorch reference on `love_rehab.m4a`:
max sigmoid 0.9999 vs ref 0.9999, 126 frames > 0.5 vs ref 124, 59 beats
detected vs 59 in ground-truth fixture.

The existing golden test (`test_loveRehab_endToEnd_producesBeats` in
`Tests/.../ML/BeatThisModelTests.swift`) asserts only `max sigmoid > 0.9`
and `≥ 50 frames > 0.5` — those bounds were chosen when we were tracking a
known bad output and didn't know the right answer. They're loose by design;
the model could regress quietly back to a 0.92 max with 51 frames > 0.5
and the test would still pass while the visualizer's beat-tracking
behaviour silently degraded.

Now that we know the actual numerical answer, we want a tight,
numerical-match suite that fails on any regression to any of the four
bugs we just fixed. The S5 `BeatGridResolverGoldenTests` already
established the pattern (golden JSON fixtures + ≤95 % within tolerance);
this work extends it to the model end-to-end.

Plus: the SC overhaul (`docs/diagnostics/SC-Overhaul-handoff.md`) will
consume three new public APIs on `LiveBeatDriftTracker`
(`currentBPM`, `currentLockState`, `relativeBeatTimes(...)`) that
shipped without unit tests. We want those covered before the SC overhaul
lands so any logic bug surfaces in the cheap unit suite, not in the
expensive visual review.

## What's already in place (HEAD `c9e2626e`)

- `BeatThisModel.predictDiagnostic(spectrogram:frameCount:) throws ->
  [String: (shape: [Int], values: [Float])]` returns intermediate-stage
  activations keyed by name (`stem.bn1d`, `stem.conv2d`, …,
  `frontend.linear`, `transformer.0..5`, `transformer.norm`,
  `head.linear`, `output.beat_logits`, `output.beat_sigmoid`). 27 named
  stages.
- `BeatThisActivationDumper` CLI executable mirrors
  `Scripts/dump_beatthis_activations.py` so the two outputs can be diffed
  numerically. Both ship as supported tooling.
- `Scripts/dump_beatthis_activations.py` ships at HEAD with sub-module
  hooks inside the partial-FT block (attnF, ffF, attnT, ffT) — useful if
  any partial-block regression surfaces.
- Python venv setup recipe in `.gitignore`:
  ```
  python3 -m venv /tmp/beat_this_venv
  /tmp/beat_this_venv/bin/pip install torch torchaudio einops soxr \
      rotary-embedding-torch soundfile numpy
  /tmp/beat_this_venv/bin/pip install -e vendor/beat_this_repo
  git clone --depth 1 https://github.com/CPJKU/beat_this vendor/beat_this_repo
  cd vendor/beat_this_repo && git checkout 9d787b9797eaa325856a20897187734175467074
  ```
  Both regeneratable, neither committed.
- `LiveBeatDriftTracker` gained public APIs (`currentBPM`,
  `currentLockState`, `relativeBeatTimes(playbackTime:count:window:)`) in
  preparation for the SC overhaul. These are uncovered by tests today.
- `MIRPipeline.elapsedSeconds` is now `public private(set)` (was
  internal); its track-relative-since-`mir.reset()` semantics are the
  contract the SC overhaul depends on.

## What to build

### Step 1: Tighten the existing golden test

`Tests/.../ML/BeatThisModelTests.swift::test_loveRehab_endToEnd_producesBeats`
currently asserts `maxProb > 0.9` and `aboveHalf >= 50`. Change to:

```swift
#expect(maxProb > 0.99,
        "Python reference produces max sigmoid 0.9999 on love_rehab; got \(maxProb)")
#expect(aboveHalf >= 100,
        "expected ~120 frames above 0.5 (Python ref: 124); got \(aboveHalf)")
```

Rationale: actual Swift output is 0.9999 with 126 frames > 0.5. A 1 %
margin on max (0.99) and a 20 % margin on count (100) catches a real
regression without noisy flapping on float32 jitter.

### Step 2: Add per-stage numerical-match golden test

This is the load-bearing piece. Add a new test file
`Tests/.../ML/BeatThisLayerMatchTests.swift` that loads the Python
reference activations from
`docs/diagnostics/DSP.2-S8-python-activations.json` (already committed at
`f18acce3`, 34 stages of stats), runs `BeatThisModel.predictDiagnostic`
on `love_rehab.m4a`, and asserts each stage's stats (min, max, mean, std)
match Python within float32 noise tolerance.

Tolerance per stage: `relative error ≤ 1e-3` on max and mean. Looser at
the time-axis edges (last 1–3 frames diverge due to padding propagation
through softmax — that's documented behaviour, not a regression). Easiest:
slice the time axis to `[..., :frameCount-3]` before computing stats, then
compare to Python's full-range stats.

Or better: write the comparison against the **per-stage `min/max/mean`**
that Python produces when the same time-slicing is applied. Compute
slice-aware Python stats once and store in a fresh JSON fixture
`docs/diagnostics/DSP.2-S8-python-activations-tslice.json` (or extend the
existing one with sliced fields).

Match this loosely to how `BeatGridResolverGoldenTests` works:

```swift
@Test(arguments: stageNames)
func test_swift_layer_matches_python(stageName: String) throws {
    let py = try loadPythonStage(stageName)        // load JSON fixture
    let sw = try loadSwiftStage(stageName)         // run predictDiagnostic
    let py_max  = py.max
    let sw_max  = sliced(sw).max
    let relErr = abs(sw_max - py_max) / max(abs(py_max), 1e-9)
    #expect(relErr < 1e-3,
            "\(stageName) max regression: py=\(py_max) sw=\(sw_max) rel=\(relErr)")
    // … same for mean, min …
}
```

For `stageNames` start with the seven most-load-bearing:
`stem.bn1d`, `stem.conv2d`, `stem.bn2d`, `frontend.linear`,
`transformer.0`, `transformer.norm`, `output.beat_logits`. If those pass,
add the rest.

The test is gated behind a `BEATTHIS_LAYER_MATCH=1` env var like
`BEATGRID_PROB_THRESHOLD` once was — runs in the regular suite, but only
asserts when the env var is set. **Default: skip with a message**, so we
don't break existing CI on machines without the audio fixture or where
inference timing is unreliable.

Alternative (simpler, more robust): make the test load the audio fixture
directly via `ffmpeg` (mirror what `test_loveRehab_endToEnd_producesBeats`
already does) and run unconditionally. That's the path the existing test
took and works on local + CI alike.

Run the existing test infrastructure to compare:

```bash
swift test --package-path PhospheneEngine --filter BeatThisLayerMatchTests
```

### Step 3: Lock in the four bug fixes as targeted regression tests

Each of the four S8 bugs deserves a 1-test-per-bug surface so a
hypothetical regression localizes immediately. Add to a new file
`Tests/.../ML/BeatThisBugRegressionTests.swift`:

#### Bug 1: Frontend block order (norm after conv with correct out_dim shape)

```swift
@Test func test_frontendBlock_normShape_matchesOutDim() throws {
    // Reading BeatThisFrontendBlockWeights.norm.scale.count for block 0
    // should be 64 (the conv output channels), not 32 (the input channels).
    let weights = try BeatThisModel.loadWeights()
    #expect(weights.frontendBlocks[0].norm.scale.count == 64,
            "block 0 norm should be on out_dim=64, not in_dim=32")
    #expect(weights.frontendBlocks[1].norm.scale.count == 128,
            "block 1 norm should be on out_dim=128, not in_dim=64")
    #expect(weights.frontendBlocks[2].norm.scale.count == 256,
            "block 2 norm should be on out_dim=256, not in_dim=128")
}
```

Note: `loadWeights` is currently `internal`; you'll need to expose it
`@testable import` style. That's already the test target's pattern.

#### Bug 2: Stem reshape transposes [T, F] → [F, T] before NHWC

Hard to test without dumping the conv input directly. The
`predictDiagnostic` path already exposes `stem.bn1d` (which matches
Python within 1e-4) — that proves the transpose+reshape is correct.
Cover it via the layer-match test in Step 2 with explicit attention on
`stem.bn1d`. Add a comment in `Tests/.../ML/BeatThisBugRegressionTests.swift`
pointing to the layer-match test for this bug rather than duplicating.

#### Bug 3: BN1d-aware padding zeros out padded region

```swift
@Test func test_bn1dAwarePadding_padsToZeroPostBN() throws {
    // Feed a spectrogram of exactly frameCount * inputMels values (no
    // padding needed inside the model) and confirm the dump's stem.bn1d
    // last frame matches the second-to-last (no synthetic edge).
    // … then feed a shorter spectrogram and confirm the post-BN value at
    // a padded frame is < 1e-3 in absolute value.
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let model = try BeatThisModel(device: device)
    // 1497 mel frames of constant 0 input — model pads to 1500.
    let n = 1497 * BeatThisModel.inputMels
    let zeros = [Float](repeating: 0, count: n)
    let captures = try model.predictDiagnostic(spectrogram: zeros, frameCount: 1497)
    guard let bn1d = captures["stem.bn1d"] else {
        Issue.record("stem.bn1d not in predictDiagnostic output"); return
    }
    // bn1d shape: [1500, 128]. Padded frames are [1497..<1500].
    // Each value at padded frames should be ≈ 0 post-BN (= float32 noise).
    let stride = 128
    for paddedFrame in 1497..<1500 {
        for mel in 0..<128 {
            let val = bn1d.values[paddedFrame * stride + mel]
            #expect(abs(val) < 1e-3,
                    "padded frame \(paddedFrame) mel \(mel): expected ≈0, got \(val)")
        }
    }
}
```

#### Bug 4: Paired-adjacent RoPE (4D + 3D)

```swift
@Test func test_RoPE_pairsAdjacentNotHalves() throws {
    // Construct a tiny [B=1, H=1, S=2, D=4] input where positions s=0 and
    // s=1 differ. Apply the 4D RoPE helper. Verify the output at s=1 is
    // the position-1 rotated version of the input — not the half-and-half
    // rotated one.
    // …
    // Implementation: build a tiny MPSGraph-only test, similar to the
    // MPSConvTest pattern that briefly existed but was removed. Or, test
    // by running predictDiagnostic on a known fixture and confirming
    // post-RoPE attention output differs from the half-and-half version.
}
```

Note: this test is harder to set up cleanly because RoPE is private to
`BeatThisModel+Frontend.swift` and `+Graph.swift`. Two options:

1. Make `applyRoPE4D` and `applyRoPE` `internal` (was private) so the
   test target can `@testable` import and call them directly with
   crafted inputs.
2. Cover this via the layer-match test (Step 2) with `stage =
   "transformer.0"` — if RoPE regresses to half-and-half, the transformer
   output would diverge from Python by `> 1e-3`, failing that test.

I'd lean (2) — the layer-match test is the canonical regression surface,
and exposing private APIs solely for testing introduces coupling. Add a
comment to `BeatThisBugRegressionTests.swift` explaining that bug 4 is
covered by the layer-match test on `transformer.0` rather than a
dedicated test.

#### Reactive-mode regression: no grid → BeatPredictor fallback

```swift
@Test func test_reactiveMode_fallsBackToBeatPredictor() throws {
    // With setBeatGrid(nil), MIRPipeline should use BeatPredictor for
    // beat_phase01. Confirm by feeding a synthetic onset stream and
    // checking that beat_phase01 advances 0→1 between onsets.
    let mir = MIRPipeline()
    mir.setBeatGrid(nil)  // reactive mode
    // … synthesize FFT input with a 120 BPM kick pattern, run process()
    // for 4 beats, confirm beat_phase01 in the FeatureVector advances
    // monotonically between beats.
}
```

This is the "regression that breaks Phosphene for ad-hoc playback users"
test — important because S7/S8 only fixed the planned-mode path; the
reactive-mode fallback must keep working.

### Step 4: Unit-test the new LiveBeatDriftTracker public APIs

The SC overhaul will consume three APIs that shipped with no test
coverage at HEAD `c9e2626e`. Cover them:

```swift
@Test func test_currentBPM_returnsGridBPM() throws {
    let tracker = LiveBeatDriftTracker()
    #expect(tracker.currentBPM == 0, "no grid → BPM 0")
    let grid = BeatGrid(/* … 125 BPM … */)
    tracker.setGrid(grid)
    #expect(abs(tracker.currentBPM - 125.0) < 0.01)
}

@Test func test_currentLockState_progression() throws {
    // Already covered by lockStateProgression in
    // LiveBeatDriftTrackerTests; just add a thin test that the public
    // accessor returns the same value as the result struct does.
}

@Test func test_relativeBeatTimes_emptyGrid_returnsEmpty() throws { … }
@Test func test_relativeBeatTimes_withinWindow_returnsExpectedCount() throws { … }
@Test func test_relativeBeatTimes_respectsCount() throws { … }
@Test func test_relativeBeatTimes_includesPastBeats() throws {
    // Verify negative values are returned for beats already passed.
}
@Test func test_relativeBeatTimes_appliesDrift() throws {
    // Set drift to a known value (via an internal setter or by feeding
    // shifted onsets), then confirm relativeBeatTimes shifts accordingly.
}
```

These all live in
`Tests/.../DSP/LiveBeatDriftTrackerTests.swift` (existing file,
`@Suite("LiveBeatDriftTracker")`).

## Files to touch

- `Tests/.../ML/BeatThisModelTests.swift` — tighten thresholds in
  `test_loveRehab_endToEnd_producesBeats`.
- `Tests/.../ML/BeatThisLayerMatchTests.swift` (new) — Step 2.
- `Tests/.../ML/BeatThisBugRegressionTests.swift` (new) — Step 3.
- `Tests/.../DSP/LiveBeatDriftTrackerTests.swift` — extend with Step 4.
- `docs/diagnostics/DSP.2-S8-python-activations-tslice.json` (new,
  optional) — slice-aware Python reference stats. Generate via:
  ```
  /tmp/beat_this_venv/bin/python Scripts/dump_beatthis_activations.py \
    --audio PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a \
    --out docs/diagnostics/DSP.2-S8-python-activations.json \
    --raw-dir /tmp/qra_py_raw
  ```
  Then post-process to slice last 3 frames off each stage's time axis and
  recompute stats. Or skip if Step 2's tolerance is loose enough to
  absorb the edge effects.
- `PhospheneEngine/Sources/ML/BeatThisModel+Weights.swift` — make
  `loadWeights` accessible to tests (`internal` is fine; they
  `@testable import ML`).

## Done-when

- [ ] `test_loveRehab_endToEnd_producesBeats` asserts `> 0.99` and
      `>= 100`, passes cleanly.
- [ ] `BeatThisLayerMatchTests` runs unconditionally, covers at least
      seven stages, all pass within `relErr < 1e-3` on max + mean.
- [ ] `BeatThisBugRegressionTests` covers Bug 1 (frontend norm shape),
      Bug 3 (BN1d-aware padding), reactive-mode fallback. Bug 2 / Bug 4
      annotated as covered by layer-match test.
- [ ] `LiveBeatDriftTrackerTests` covers `currentBPM`,
      `currentLockState`, and `relativeBeatTimes` (≥ 5 new tests).
- [ ] Full DSP + ML test suite green (`swift test --package-path
      PhospheneEngine --filter "DSP|ML"`).
- [ ] `swiftlint --strict` clean on touched files.
- [ ] CLAUDE.md updated: bump test count baseline (currently ~964 tests
      per the 2026-05-04 entry; this work adds ~12). Note in the
      "Recent landed work" entry that the four S8 bugs are now
      individually regression-locked.

## What NOT to do

- Don't lower the `BeatGridResolver.probThreshold` (0.5) to make tests
  pass on flaky machines. The model is producing sharp-peaks output now;
  any regression below 0.5 max is a real regression.
- Don't add MPSGraph numerical-tolerance shims (e.g. `if rel < 0.01:
  pass`). The tolerance band must catch a real regression, which by
  observation is on the order of 80 % relative error in the bad path.
  `1e-3` is loose enough for float32 noise, tight enough for real bugs.
- Don't expose `applyRoPE4D` / `applyRoPE` for testing. Bug 4 is covered
  by the transformer-output layer-match test; keep the implementation
  encapsulated.
- Don't depend on Python being installed at test time. The Python
  reference output is committed as static JSON at
  `docs/diagnostics/DSP.2-S8-python-activations.json`; that's the
  ground truth. Only Step 2's optional time-slice fixture-regen step
  needs Python.
- Don't remove the `BeatThisActivationDumper` CLI. It's the lasting
  diagnostic surface for any future regression that the layer-match
  test catches but doesn't localise.

## Reference: structure

```
PhospheneEngine/Sources/
  ML/BeatThisModel.swift                     // predict, predictDiagnostic
  ML/BeatThisModel+Weights.swift             // loadWeights() — make internal
  ML/BeatThisModel+Frontend.swift            // applyRoPE4D — keep private
  ML/BeatThisModel+Graph.swift               // applyRoPE — keep private
  ML/BeatThisModel+Ops.swift                 // shared graph helpers
  DSP/LiveBeatDriftTracker.swift             // currentBPM, currentLockState,
                                             // relativeBeatTimes(...)
  DSP/MIRPipeline.swift                      // public elapsedSeconds; setBeatGrid(_:)
  BeatThisActivationDumper/Dumper.swift      // CLI mirror of dump_beatthis_activations.py

PhospheneEngine/Tests/PhospheneEngineTests/
  ML/BeatThisModelTests.swift                // test_loveRehab_endToEnd_producesBeats
  ML/BeatThisLayerMatchTests.swift           // (new — Step 2)
  ML/BeatThisBugRegressionTests.swift        // (new — Step 3)
  DSP/LiveBeatDriftTrackerTests.swift        // existing, extend (Step 4)

docs/diagnostics/
  DSP.2-S8-python-activations.json           // ground truth, 34 stages
  DSP.2-S8-python-activations-tslice.json    // (optional, new — Step 2)
  DSP.2-S8-handoff.md                        // historical (S8 itself, now done)
  SC-Overhaul-handoff.md                     // separate parallel work
  DSP.2-Regression-Hardening-handoff.md      // this file

Scripts/
  dump_beatthis_activations.py               // ref implementation, sub-module hooks
```

## Estimated scope

Three test files, ~250 lines added (mostly Step 2's parametrized layer
match). Plus ~10-line tightening in the existing test, plus ~15 lines of
CLAUDE.md updates. Total: ~275 lines, ~1.5 hours.

## Commit shape

Three commits in order so `git bisect` has traction:

1. `[DSP.2 hardening] Tighten test_loveRehab_endToEnd thresholds`
2. `[DSP.2 hardening] BeatThisLayerMatchTests: Swift vs Python per-stage stats`
3. `[DSP.2 hardening] BeatThisBugRegressionTests + LiveBeatDriftTracker public API tests`

## After it lands

- Future BeatThisModel regressions are catchable in the cheap unit suite,
  not via reel-recording detective work.
- The SC overhaul (`docs/diagnostics/SC-Overhaul-handoff.md`) can rely on
  `currentBPM` / `currentLockState` / `relativeBeatTimes(...)` having
  unit-tested behaviour.
- CLAUDE.md status moves to: "DSP.2 S7+S8 fully ✅ with regression-locked
  numerical-match suite."

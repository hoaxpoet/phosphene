Increment LM.1.2 — Lumen Mosaic post-LM.1 review remediations.
Pure cleanup + targeted regression-test addition. NOT a visual rework
and NOT a feature increment. Six findings packaged from the LM.1
self-review (commit `d1c9c7ba`). Land BEFORE LM.2 so the matID == 1
emission path has a focused regression-lock and the redundant work
identified in LM.1 doesn't entrench.

Authoritative review notes are in this prompt; the commit-trail
context is `git log --oneline d1c9c7ba 93521485`.

────────────────────────────────────────
SCOPE — six findings, in priority order
────────────────────────────────────────

1. (P1, load-bearing) **Add a focused unit test for the matID == 1
   lighting-fragment dispatch.** This is the only review finding that
   would actually catch a regression. Currently the matID == 1 branch
   in `raymarch_lighting_fragment` is exercised only through
   `PresetRegressionTests`'s 64×64 dHash, which doesn't validate the
   actual output expression. A focused test that constructs a
   synthetic G-buffer with matID = 1 and asserts the lit RGB equals
   `albedo × kLumenEmissionGain + irradiance × kLumenIBLFloor × ao`
   gates a future regression where the matID branch silently breaks.

2. (P2, perf) **`sceneSDF` evaluates Voronoi + fbm8 on every march
   sample.** At 1080p with ~50% panel coverage that's ~7M voronoi
   calls + ~7M fbm8 calls per frame (1 march sample × ~128 steps + 6
   central-differences-normal samples per hit). Most march samples
   are far from the panel surface where the relief contribution is
   noise-floor anyway. Gate the relief/frost computation on
   `box_dist < threshold` so only near-surface samples pay the cost.

3. (P2, cleanliness) **Drop the redundant `voronoi_f1f2` call in
   `sceneMaterial`.** Currently sceneMaterial computes `v0` and
   `cell_seed = v0.pos`, then passes `cell_seed` to
   `lm_backlight_static` which `(void)`-ignores it. The voronoi
   evaluation is wasted work in LM.1 and is only there for "call-site
   stability when LM.2 adds per-cell sampling". Per CLAUDE.md "Don't
   add features, refactor, or introduce abstractions beyond what the
   task requires" + the V.7.5 / D-072 lesson about preemptive
   scaffolding, defer the voronoi sample until LM.2 actually needs
   it. The diff is a few-line revert.

4. (P3, doc) **Document the matID encoding range.** The G-buffer's
   `gbuf0.g` is `.rg16Float`; matID values 0/1 round-trip exactly
   through fp16, but values above 2048 (fp16's exact integer limit)
   would silently truncate. Add a one-line note above
   `kLumenEmissionGain` in `RayMarch.metal` AND in the
   `rayMarchGBufferPreamble` G-buffer-output docstring stating "matID
   values must fit in fp16's exact integer range [0, 2048]".

5. (P3, doc) **Cross-reference the sky early-return in the matID
   block.** The matID dispatch at `RayMarch.metal:300` happens after
   the depth-≥-0.999 sky early-return. The dispatch block doesn't
   restate that ordering, and a future maintainer adding a new matID
   value could miss it. Add a one-line "Sky path returns before
   this — gbuf0.r ≥ 0.999 short-circuits at line 257" comment above
   `int matID = int(g0.g + 0.5);`.

6. (P3, future-cleanup) **Drop the unused input `int matID`
   parameter from `sceneMaterial`.** The G-buffer fragment hardcodes
   `0` as the input, all 4 ray-march presets `(void)matID` it. The
   parameter is a vestige of an earlier API that never matched the
   deferred pipeline. Removing it tightens the contract — but the
   change touches 5 files (preamble + 4 preset .metal files +
   2 inline test shader strings) and is a lower-priority polish.
   **Mark this as deferred to LM.6 / LM.9 cleanup pass; do NOT land
   in LM.1.2 unless the removal is trivial after items 1–5.**

────────────────────────────────────────
NON-GOALS — do NOT do these
────────────────────────────────────────

- **Do NOT add a panel-edge invariant test that runs the full
  deferred pipeline.** That's a LM.2+ harness extension item — the
  harness now correctly renders LumenMosaic via
  `renderDeferredRayMarchFrame` (commit `93521485`), but a
  programmatic "every pixel is matID == 1" assertion needs the
  G-buffer to be readable by the test, not just the post-composite
  output. Land that with LM.6's perf measurement work.
- **Do NOT touch the matID dispatch logic itself.** The
  `albedo × 4.0 + irradiance × 0.05 × ao` expression is correct;
  this prompt only adds a test for it.
- **Do NOT widen the G-buffer to include matID values > 1.** Phase
  LM ships matID = 0 and matID = 1 only; matID = 2+ is open
  territory for later presets and the half-float ceiling note in
  finding #4 is the only documentation update needed.
- **Do NOT add IBL-bound rendering to the visual harness.**
  Glass Brutalist + Kinetic Sculpture review-via-harness needs
  IBLManager construction; deferred per LM.1.1's commit message.
- **Do NOT regenerate `PresetRegressionTests` golden hashes.** None
  of the LM.1.2 changes should drift the visual output. If a hash
  drifts, halt and surface the diff before continuing.

────────────────────────────────────────
FILES TO TOUCH
────────────────────────────────────────

Modify:

- `PhospheneEngine/Sources/Presets/Shaders/LumenMosaic.metal`
  - `sceneSDF`: add `if (box_dist > kReliefBandRadius) { return box_dist; }`
    early-out (or equivalent) before the relief/frost evaluation.
    `kReliefBandRadius` ≈ `kReliefAmplitude + kFrostAmplitude` × 4 (small
    safety margin) = roughly 0.02 world units, since the displacement
    can never push the surface farther than `kReliefAmplitude +
    kFrostAmplitude`. Document the threshold rationale in a comment
    cross-referencing the Lipschitz-safety analysis already in the
    constants.
  - `sceneMaterial`: drop the `voronoi_f1f2(panel_uv, kCellDensity)`
    call and the `cell_seed` derivation. Update the call site to
    `lm_backlight_static(.zero, f)` (or remove the unused param —
    see helper change below). Add a one-line comment that LM.2 will
    reintroduce per-cell sampling at this site.
  - `lm_backlight_static`: drop the unused `cell_seed` parameter.
    Update the doc-comment to note LM.2 will reintroduce it.

- `PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal`
  - Above `kLumenEmissionGain`: add a one-line note about matID's
    fp16 ceiling.
  - Inside the `if (matID == 1)` block: add the sky-early-return
    cross-reference comment.

- `PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift`
  - In the `gbuf0.G` documentation block at the top of
    `rayMarchGBufferPreamble`, add the same fp16-ceiling note.
  - Watch the file_length lint gate (currently 399 lines, ceiling
    400). Compact existing doc-comments by 1 line if needed to stay
    under.

Create:

- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/MatIDDispatchTests.swift`
  - Single new file, single `@Suite("MatIDDispatch")` struct.
  - **Test 1**: `test_matID0_runsCookTorrancePath`. Build a
    synthetic G-buffer programmatically:
      - gbuffer0: depth = 0.5, matID = 0 at every pixel
      - gbuffer1: normal = (0, 0, -1), AO = 1.0 at every pixel
      - gbuffer2: albedo = (0.5, 0.5, 0.5), packed roughness = 0.5,
        metallic = 0.0
    Bind, run `raymarch_lighting_fragment` directly via a one-off
    pipeline state, read back the lit RGB. Assert the result is the
    Cook-Torrance + IBL-fallback expression
    (`albedo × 0.04 × ao` minimum) — bounded but non-zero.
  - **Test 2**: `test_matID1_emissionPath_albedoTimes4`. Same
    synthetic G-buffer except matID = 1. Assert the lit RGB equals
    `albedo × kLumenEmissionGain + irradiance × kLumenIBLFloor × ao`
    within 1e-3 tolerance. With `iblManager: nil` and the lighting
    fragment's documented "unbound textures return zero" behaviour,
    `irradiance = 0` and the expected result is exactly
    `albedo × 4.0 = (2.0, 2.0, 2.0)`. Tone-map is downstream
    (`PostProcessChain` / `composite`), NOT in
    `raymarch_lighting_fragment` — so the lit-texture output IS the
    HDR value, before ACES.
  - **Test 3**: `test_matID1_skyShortCircuit`. Same synthetic
    G-buffer, except depth = 1.0 at every pixel. Assert the lit
    RGB equals the sky-procedural output (NOT
    `albedo × 4.0`). This regression-locks the documented
    "Sky path returns before this" invariant for matID == 1.
  - All three tests must construct a real `MetalContext` +
    `RayMarchPipeline`, call `pipeline.runLightingPass(...)`
    directly (it's `internal` in the Renderer module), and read
    back the litTexture pixels. Keep the test small (32×32 is
    enough; central-pixel sampling is fine) — this is a unit-level
    gate, not a perf benchmark.
  - Note: `RayMarchPipeline.runLightingPass` is currently
    package-internal. If the test target can't reach it from
    `@testable import Renderer`, surface that as a discovery and
    halt; the fix is either widening the visibility (preferred —
    consistent with `runGBufferPass` access) or routing the test
    through `pipeline.render(...)` with a stub G-buffer pipeline.

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

1. `swift build --package-path PhospheneEngine` — green.
2. `swift test --package-path PhospheneEngine --filter MatIDDispatch` —
   3 new tests green.
3. `swift test --package-path PhospheneEngine --filter
   PresetRegressionTests` — golden hashes UNCHANGED for all 16
   presets (no visual drift expected). If LumenMosaic drifts
   because of the threshold-gated `sceneSDF`, the new value should
   still be within the 8-bit hamming threshold of
   `0xF0F0C8CCCCC8F0F0`. If drift exceeds threshold, halt and
   surface; the threshold-gated SDF branch may be miscalibrated.
4. `swift test --package-path PhospheneEngine --filter
   PresetAcceptanceTests` — green (4 invariants × 16 presets).
5. `swift test --package-path PhospheneEngine --filter
   presetLoaderBuiltInPresetsHaveValidPipelines` — green.
6. `RENDER_VISUAL=1 swift test --package-path PhospheneEngine
   --filter renderPresetVisualReview` — Lumen Mosaic PNGs match the
   pre-LM.1.2 baseline (uniform pale cream); the visual change
   from item #2 (sceneSDF threshold gate) is invisible in the
   final composite for the static-backlight LM.1 case (the relief
   contributes only via the unbound IBL ambient).
7. `swiftlint lint --strict` on touched files — 0 violations.
8. `xcodebuild -scheme PhospheneApp -destination 'platform=macOS'
   build` — green.

────────────────────────────────────────
ESTIMATED SESSION COST
────────────────────────────────────────

1 session. Items 1, 4, 5 are trivial; items 2, 3 are small refactors
with regression-hash verification; item 6 is explicitly deferred.
The new test file is ~150 lines and follows the existing
`RayMarchPipelineTests` / `SSGITests` test-infrastructure pattern.

────────────────────────────────────────
COMMIT MESSAGE TEMPLATE
────────────────────────────────────────

`[LM.1.2] LumenMosaic: post-LM.1 review remediations`

Body should explicitly cite each finding number (1–5), what changed
for each, and the regression-hash verification result.

────────────────────────────────────────
CARRY-FORWARD
────────────────────────────────────────

- Finding #6 (drop the unused input `int matID` parameter) deferred
  to LM.6 / LM.9 cleanup pass per CLAUDE.md "don't refactor beyond
  what the task requires".
- Panel-edge invariant programmatic test deferred to LM.6 (needs
  G-buffer readback, separate harness work).
- IBL-bound matID == 0 visual review (Glass Brutalist, Kinetic
  Sculpture) deferred per the LM.1.1 commit's carry-forward.
- LM.2 will populate slot 8 (`LumenPatternState`) for the harness
  via the existing `presetFragmentBuffer3:` parameter on
  `pipeline.render(...)` — no further harness work needed there.

Execute Increment QR.5 (CLEAN.1) — Mechanical cleanup pass.

Authoritative spec: `docs/ENGINEERING_PLAN.md §Phase QR §Increment QR.5 (CLEAN.1) — Mechanical cleanup pass` (~line 2807). Read it in full before starting; the 17-item catalog and implementation order below mirror that section, with session-scoped sequencing added.

────────────────────────────────────────
WHAT THIS INCREMENT IS
────────────────────────────────────────

Pure deletion of dead code, dead binaries, and stale doc comments accumulated through DSP.1 / DSP.2 / D-076 abandonment / V.1+V.2 utility introduction. **~600 LOC and ~1.6 MB removed.** No behavior change is the load-bearing invariant; if a test fails or a preset golden hash drifts, the cleanup was not literal-equivalent and the change must be backed out and investigated.

Three estimated sessions:
- Session A — Pure deletions + stale comments (items #1, #2, #6, #7, #8, #9, #10, #11). Small commits, no behavior risk.
- Session B — Preset migration + utility dedup (items #5 then #4). Sequencing matters; golden hashes must stay byte-identical across the rename.
- Session C — EMA centralization + `BeatPredictor` retirement + test cleanups + allocation fixes (items #12, #13, #14, #15, #16, #17). Touches DSP hot paths; full suite + soak test required.

This prompt covers all three. Run sequentially or break across multiple Claude Code sessions per the session header below.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. QR.1 → QR.4 must have landed. Verify with `git log --oneline | grep -E '^\w+ \[QR\.[1-4]'` — expect at least four commits with `[QR.1]` through `[QR.4]` prefixes. If any are missing, stop and report.

2. Confirm the doc-refactor (DOC.0 → DOC.4) has landed (this prompt assumes the slimmed CLAUDE.md and the pruning rule are in force). Verify with `grep -q "Pruning pass — every tenth increment" CLAUDE.md` (expect exit 0).

3. Working tree must be clean of unrelated changes for the increment scope. `git status --short` — anything outside the catalog items below should be stashed or surfaced to Matt before starting.

4. Read these context anchors before touching code:
   - `CLAUDE.md` §Increment Completion Protocol (closeout + commit cadence + pruning step).
   - `CLAUDE.md` §Failed Approaches: #27 (no synthetic audio for diagnostics), #31 (deviation-form rule — relevant if any preset migration in #5 touches audio-driven thresholds).
   - `docs/DECISIONS.md` D-075 (the IOI-trimmed-mean tempo path that retires the histogram).
   - `docs/DECISIONS.md` D-077 (the Beat This! pivot that abandoned BeatNet weights — establishes why item #1 is safe to delete).
   - `docs/DECISIONS.md` D-045 (V.1 utility naming convention — the destination for item #5's renames).
   - `docs/DECISIONS.md` D-055 / D-062 (V.2 / V.3 utility load order — relevant for item #4 dedup).

────────────────────────────────────────
SESSION A — PURE DELETIONS + STALE COMMENTS
────────────────────────────────────────

Commits land in this order. Each is its own commit; full test suite must pass after each.

**Item #1 — Delete `Sources/ML/Weights/beatnet/` (D-076 abandoned)**
- Path: `PhospheneEngine/Sources/ML/Weights/beatnet/`
- ~1.6 MB binaries + 14 .bin + manifest.
- Verify: `find PhospheneEngine -path '*beatnet*' -type f` returns empty after the delete.
- Verify: `grep -rE "beatnet|BeatNet" PhospheneEngine/Sources/` returns no hits (other than Failed Approach #17 amendment in CLAUDE.md, which is a historical reference and stays).
- Commit message: `[QR.5] ML: delete abandoned BeatNet weights (D-076 reserved-but-abandoned)`.

**Item #2 — Delete `Scripts/convert_beatnet_weights.py`**
- ~80 LOC.
- Verify the file is the only BeatNet artifact in `Scripts/`: `ls Scripts/ | grep -i beatnet`.
- Commit message: `[QR.5] scripts: delete convert_beatnet_weights.py (D-076 abandoned)`.

**Item #6 — Delete placeholder `Sources/Orchestrator/Orchestrator.swift`**
- 5 LOC, empty namespace placeholder.
- Verify it has no imports/consumers: `grep -rE "import.*Orchestrator/Orchestrator|Orchestrator\\.\\b" PhospheneEngine/Sources/ PhospheneApp/`. Expect zero non-placeholder hits.
- Commit message: `[QR.5] Orchestrator: delete empty placeholder Orchestrator.swift`.

**Item #7 — Delete placeholder `Sources/Session/Session.swift`**
- 5 LOC, empty namespace placeholder.
- Same verification pattern as #6.
- Commit message: `[QR.5] Session: delete empty placeholder Session.swift`.

**Item #8 — Delete `Sources/Orchestrator/PresetSignaling.swift`**
- 39 LOC.
- IMPORTANT precondition check: `grep -rE "PresetSignaling|presetCompletionEvent" PhospheneEngine/Sources/ PhospheneApp/`. If `ArachneState: PresetSignaling` conformance still exists (per CLAUDE.md D-095), this file is **still consumed** — do not delete. Instead, surface to Matt as a discrepancy between the QR.5 catalog ("no preset emits") and current code state.
- If conformance is gone: commit `[QR.5] Orchestrator: delete unused PresetSignaling protocol`.

**Item #9 — Inline `Views/Ready/ReadyBackgroundPresetView.swift` into `ReadyView.swift`**
- 34 LOC moved.
- Verify Xcode project file (`PhospheneApp.xcodeproj/project.pbxproj`) is updated across all four sections (`PBXBuildFile`, `PBXFileReference`, `PBXGroup`, `PBXSourcesBuildPhase`) — Failed Approach: app-layer source files not registered in pbxproj cause `cannot find type` errors. See CLAUDE.md §Code Style "New app-layer source files must be registered in Xcode project.pbxproj across all four sections."
- Commit message: `[QR.5] Views/Ready: inline ReadyBackgroundPresetView into ReadyView`.

**Item #10 — Delete or wire `Services/PresetPreviewController.swift`**
- 52 LOC stub, no caller (per QR.5 catalog).
- Verify no consumers: `grep -rE "PresetPreviewController" PhospheneApp/ PhospheneEngine/`. If zero hits → delete. If hits exist → surface as scope deviation.
- If deleted: also remove the four pbxproj entries.
- Commit message: `[QR.5] Services: delete PresetPreviewController stub (no caller)` or `[QR.5] Services: wire PresetPreviewController (was stubbed)` if Matt directs wiring.

**Item #11 — Stale CoreML doc comments**
- Doc-only edit across 7+ files. Each comment block claims a CoreML dependency that doesn't exist (D-009 — no CoreML; MPSGraph + Accelerate only).
- Sites:
  - `Sources/Audio/Protocols.swift` lines ~101, ~166, ~188, ~190, ~192
  - `Sources/Shared/AudioFeatures+Frame.swift` line ~71
  - `Sources/Shared/StemSampleBuffer.swift` line ~46
  - `PhospheneApp/VisualizerEngine.swift` line ~173
  - `PhospheneApp/VisualizerEngine+Stems.swift` lines ~62, ~142
- For each: replace any "CoreML" reference with "MPSGraph" (or delete the comment if it has no remaining substance). Grep `grep -rn "CoreML\|Core ML" PhospheneEngine/Sources/ PhospheneApp/ | grep -v "// Failed Approach\|HISTORICAL_DEAD_ENDS"` to find any remaining hits.
- Commit message: `[QR.5] docs: replace stale CoreML doc comments with MPSGraph (D-009)`.

**Session A done-when:**
- 8 commits landed (one per item, except #6+#7 which are functionally identical can land together if you prefer).
- `swift test --package-path PhospheneEngine` passes (~1185 tests; same pre-existing flakes as the baseline).
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` clean.
- `swiftlint lint --strict --config .swiftlint.yml` — zero new violations (project baseline preserved).

────────────────────────────────────────
SESSION B — PRESET MIGRATION + UTILITY DEDUP
────────────────────────────────────────

**Order matters: #5 must precede #4.** Migrating presets first ensures dedup doesn't break their compile.

**Item #5 — Migrate production presets calling legacy `fbm3D` / `perlin2D` / `sdPlane` / `sdBox` to V.1+V.2 names**

Production presets to grep + migrate:
- `Sources/Presets/Shaders/VolumetricLithograph.metal`
- `Sources/Presets/Shaders/GlassBrutalist.metal`
- Any others identified by `grep -lE "fbm3D|perlin2D|sdPlane|sdBox" PhospheneEngine/Sources/Presets/Shaders/*.metal`

Rename table (legacy camelCase → V.1+V.2 snake_case per D-045):
- `fbm3D(...)` → `fbm8(...)` (or `fbm4` depending on octave count at the call site; check existing semantics)
- `perlin2D(...)` → `perlin2d(...)`
- `sdPlane(...)` → check `Sources/Presets/Shaders/Utilities/Geometry/SDFPrimitives.metal` for current name (likely `sd_plane`)
- `sdBox(...)` → `sd_box(...)`

For each rename, verify the function exists in the V.1+V.2 tree with the same signature. If the V.1+V.2 form differs (different arg order, different return type), the rename is not literal-equivalent and the call site needs adjustment.

Verify after each preset migration: `PresetRegressionTests` golden hash unchanged for that preset (these renames are name-only; if a hash drifts, investigate).

Commit message per preset: `[QR.5] preset <name>: migrate legacy utility names to V.1+V.2 (D-045)`.

**Item #4 — Dedup `ShaderUtilities.metal` legacy bodies vs V.1+V.2 trees**

13 functions, ~400 LOC. The legacy bodies in `ShaderUtilities.metal` duplicate functionality now provided by `Sources/Presets/Shaders/Utilities/Noise/`, `.../Geometry/`, and others.

Process:
1. Grep production presets to confirm no remaining consumers of the legacy names: `grep -rE "\b(fbm3D|perlin2D|sdPlane|sdBox|legacy_fn_N)\b" PhospheneEngine/Sources/Presets/Shaders/ | grep -v "Shaders/Utilities/"`. Expect zero hits after #5.
2. For each duplicated function, delete its body from `ShaderUtilities.metal`.
3. Compile + run `PresetRegressionTests` — hashes must stay byte-identical (if anything drifts, the deletion was not literal-equivalent).

`ShaderUtilities.metal` keeps the functions that are NOT duplicated by V.1+V.2 trees (~55 → ~42 functions after dedup).

Commit message: `[QR.5] Shaders/ShaderUtilities: dedup 13 legacy bodies vs V.1+V.2 trees (D-045)`.

**Session B done-when:**
- All preset migrations landed.
- ShaderUtilities.metal dedup landed.
- `PresetRegressionTests` shows zero hash drift across all 15 production presets × 3 fixtures.
- `PresetLoaderCompileFailureTest` passes (`expectedProductionPresetCount = 15`).
- Engine + app builds clean.

────────────────────────────────────────
SESSION C — EMA CENTRALIZATION + BEAT-PREDICTOR RETIREMENT + TEST CLEANUPS + ALLOCATION FIXES
────────────────────────────────────────

**Item #3 — Delete IOI histogram + `dumpHistogram` consumers (dead post-D-075)**
- Path: `Sources/DSP/BeatDetector+Tempo.swift` ~lines 144–177.
- ~50 LOC. The histogram-mode picker was retired in D-075 in favour of trimmed-mean IOI; the histogram itself is still built for diagnostic dumps but it can either stay (cheap) or go (if confirmed unused). Per the catalog: delete the histogram + consumers; keep `computeRobustBPM` (the load-bearing tempo path).
- Cross-check: any test that consumes `dumpHistogram` (`BeatDetector+TempoDiagnostics.swift`) — if so, delete the test along with the consumer.
- Verify: `BeatDetectorTests` still pass post-deletion (the test surface should be `computeRobustBPM` validation only).
- Commit message: `[QR.5] BeatDetector: delete IOI histogram + dumpHistogram (D-075 trimmed-mean wins)`.

**Item #12 — Centralize EMA in `Shared/Smoother`**
- New file: `PhospheneEngine/Sources/Shared/Smoother.swift`. Implement a single value type wrapping the `pow(rate, 30/fps)` FPS-independent EMA pattern.
- Replace the 5 copy-pasted impls in:
  - `Sources/DSP/BeatDetector.swift` (decay envelope)
  - `Sources/DSP/LiveBeatDriftTracker.swift` (drift α=0.4 per matched onset — verify the abstraction fits both per-frame and per-event)
  - `Sources/DSP/BandEnergyProcessor.swift` (band energy smoothing)
  - `Sources/DSP/MIRPipeline.swift` (any EMA call sites)
  - `Sources/DSP/StemAnalyzer.swift` (per-stem EMAs in `computeRichFeatures`)
- IMPORTANT: the decay constants must be byte-identical post-centralization. `MIRPipelineUnitTests` + `BeatDetectorTests` will catch divergence.
- Commit message: `[QR.5] Shared: centralize EMA pattern in Smoother value type`.

**Item #13 — Delete `BeatPredictor.swift` (subordinate to `LiveBeatDriftTracker`)**
- ~150 LOC + tests.
- Files: `Sources/DSP/BeatPredictor.swift`, `Tests/PhospheneEngineTests/DSP/BeatPredictorTests.swift`.
- Precondition check: `BeatPredictor` is doc-deprecated post-DSP.2 S7 as reactive-mode-only fallback. Per the Architect simplification #3 cited in the catalog, the live Beat This! retry path (DSP.3.5) makes it dispensable. **Verify before deletion:** `grep -rE "BeatPredictor" PhospheneEngine/Sources/ PhospheneApp/`. If `MIRPipeline.swift` still has a `BeatPredictor` field with non-trivial usage, the deletion is not safe — surface to Matt as a scope deviation.
- After deletion: `MIRPipeline` must still produce `beatPhase01` / `beatsUntilNext` in `FeatureVector` for tracks where no `BeatGrid` is installed. Confirm via `MIRPipelineDriftIntegrationTests` (drift tracker drives FV when grid present) and add a test for the no-grid fallback if one isn't there (`beatPhase01 = 0`, `beatsUntilNext = 0`).
- Commit message: `[QR.5] DSP: retire BeatPredictor (subordinate to LiveBeatDriftTracker post-DSP.2 S7)`.

**Item #14 — Audit `Tests/TestDoubles/` for stale doubles; standardize naming**
- Files: `Tests/PhospheneEngineTests/TestDoubles/`.
- Audit each double: is it consumed by any test? `grep -rE "<TypeName>" Tests/`. Stale ones get deleted.
- Standardize naming: Mock = full record-and-replay; Stub = canned return values; Fake = working in-memory impl.
- Commit message: `[QR.5] TestDoubles: audit + standardize naming (Mock vs Stub vs Fake)`.

**Item #15 — Consolidate `Tests/.../Orchestrator/SessionPlanner*Tests.swift` (4 files → 2)**
- Target structure: `SessionPlannerTests.swift` (unit) + `SessionPlannerGoldenTests.swift` (golden fixtures).
- Pure file reorganisation; test bodies move verbatim.
- Commit message: `[QR.5] Tests/Orchestrator: consolidate SessionPlanner test files (4 → 2)`.

**Item #16 — Pre-allocate buffer in `AudioInputRouter.swift` file-playback path**
- Lines ~252–263.
- 46 buffers/sec of fresh allocation in the current code; pre-allocating saves churn on file-playback sessions.
- ~10 LOC.
- Verify after: full suite passes; soak test (10-minute minimum) shows no `MemoryReporter` regression in `residentBytes` slope.
- Commit message: `[QR.5] AudioInputRouter: pre-allocate file-playback buffer`.

**Item #17 — Add `AudioBuffer.latestSamples` `unsafeReadInto(_ ptr:count:)` overload**
- ~30 LOC.
- Goal: eliminate per-FFT-frame allocation. Current `latestSamples` allocates a Swift array each call; the unsafe overload writes into caller-provided memory.
- Update FFT call site (`FFTProcessor`) to use the new overload.
- Verify after: `FFTProcessorTests` + `AudioToFFTPipelineTests` pass; soak test shows reduced allocation count.
- Commit message: `[QR.5] AudioBuffer: add unsafeReadInto overload to eliminate per-FFT-frame allocation`.

**Session C done-when:**
- All 9 Session C items landed (items #3, #12, #13, #14, #15, #16, #17 from the catalog — items #5 and #4 already landed in Session B; reorder above puts #3 first because it pairs with #13's BeatPredictor work conceptually).
- Full engine suite passes after each commit.
- `bash Scripts/run_soak_test.sh --duration 600` (10-minute soak) shows no `residentBytes` regression vs the pre-#16/#17 baseline.

────────────────────────────────────────
DONE-WHEN (Increment-level)
────────────────────────────────────────

- [ ] All 17 catalog items landed in separate commits with `[QR.5] <component>: <description>` messages.
- [ ] Full engine suite + full app build green after each commit (`git bisect` retains value).
- [ ] All `PresetRegressionTests` golden hashes unchanged.
- [ ] `PresetLoaderCompileFailureTest` passes (15 production presets).
- [ ] 2-hour soak test (`bash Scripts/run_soak_test.sh --duration 7200` with `caffeinate -i`) passes without memory regression.
- [ ] CLAUDE.md unchanged (or minimal edit — only Failed Approach numbers if any new lesson surfaces; see Failed Approach #50 / #51 pattern for in-place rule additions).
- [ ] `docs/ARCHITECTURE.md §Module Map` updated for any deleted/added files (e.g. delete `BeatPredictor` row; add `Smoother` row).
- [ ] `docs/ENGINEERING_PLAN.md §Phase QR §Increment QR.5` marked ✅ with date.
- [ ] DECISIONS.md not touched (this increment is mechanical, no design decisions).

────────────────────────────────────────
STOP AND REPORT INSTEAD OF FORGING AHEAD
────────────────────────────────────────

Per CLAUDE.md §Increment Completion Protocol "Stop and report" rules, halt and surface to Matt if any of the following fire:

- Any test fails or any golden hash drifts during a "literal-equivalent" rename or dedup.
- `BeatPredictor` deletion (item #13) breaks `MIRPipeline` because the live Beat This! retry path is not the only consumer in current code.
- `PresetSignaling.swift` deletion (item #8) is blocked because `ArachneState: PresetSignaling` conformance still exists and is load-bearing.
- A preset migration in item #5 needs more than a name change (different arg order, different return type) — that's a non-mechanical change and warrants a scope discussion.
- EMA centralization (item #12) cannot preserve byte-identical decay constants across all 5 call sites because they use subtly different forms.
- Soak test shows a memory regression after #16 or #17.

────────────────────────────────────────
COMMIT CADENCE
────────────────────────────────────────

One commit per catalog item. Push at the end of each session, not after every commit. Use the standard format: `[QR.5] <component>: <description>` + Co-Authored-By footer.

Do NOT push to remote without Matt's explicit "yes, push" approval per CLAUDE.md §Increment Completion Protocol "Do not push to the remote without Matt's explicit approval."

────────────────────────────────────────
CLOSEOUT REPORT
────────────────────────────────────────

After Session C completes, produce a closeout report covering:

1. **Files changed** — grouped per session, citing each catalog item number.
2. **Tests run** — engine suite + app suite + soak test pass counts; any pre-existing flakes called out.
3. **Visual verification** — `PresetRegressionTests` confirms hashes unchanged across 45 fixtures (15 presets × 3); explicitly state "no visual change expected; if observed, it's a bug." A `RENDER_VISUAL=1` contact sheet is NOT required for this increment (no behavioral change).
4. **Documentation updates** — ARCHITECTURE.md Module Map edits, ENGINEERING_PLAN.md status flip, CLAUDE.md untouched.
5. **Capability registry** — `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` likely untouched (mechanical cleanup doesn't change capabilities) — confirm or update.
6. **Known risks and follow-ups** — any items deferred from the catalog (e.g. if #8 was blocked by `PresetSignaling` still being used), what's the recommended next move.
7. **Git status** — branch state, commit hash list (~17 commits), `git status` clean post-increment.

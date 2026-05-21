# Phase CA Kickoff — Capability Audit — Increment CA.7 (Renderer)

Hand this to a new Claude Code session verbatim. Do not summarise.

## What this phase is

Phase CA — Capability Audit is a multi-increment archaeology of Phosphene's codebase. Each increment audits one subsystem: reads the actual source, traces consumers and producers, cross-references against `CLAUDE.md` / `docs/ARCHITECTURE.md` / `docs/QUALITY/KNOWN_ISSUES.md` / `docs/DECISIONS.md`, and assigns a health verdict to every capability the subsystem exposes.

**Prior increments:**

- **CA.1 (DSP / MIR)** closed 2026-05-20 at [../CAPABILITY_REGISTRY/DSP_MIR.md](../CAPABILITY_REGISTRY/DSP_MIR.md). 22 files. Surfaced one runtime production-orphan cluster (per-frame StructuralAnalyzer chain — later superseded by BUG-015 fix routing runtime predictions through it).
- **CA.2 (ML)** closed 2026-05-20 at [../CAPABILITY_REGISTRY/ML.md](../CAPABILITY_REGISTRY/ML.md). 16 files / 4,507 LoC. Methodology refinement: pre-grep visibility verification.
- **CA.3 (Session)** closed 2026-05-20 at [../CAPABILITY_REGISTRY/SESSION.md](../CAPABILITY_REGISTRY/SESSION.md). 22 files / ~3,425 LoC. Methodology refinement: cross-check kickoff prompt against KNOWN_ISSUES.md as Pass 0.
- **CA.4 (Orchestrator)** closed 2026-05-20 at [../CAPABILITY_REGISTRY/ORCHESTRATOR.md](../CAPABILITY_REGISTRY/ORCHESTRATOR.md). 14 files / ~2,950 LoC. **Surfaced the load-bearing broken-but-claimed BUG-015** — `applyLiveUpdate(...)` had zero production call sites; the entire Phase 4.5/4.6 live-adaptation pipeline was dead in production. BUG-015 fixed 2026-05-21.
- **CA.5 (App-layer engine-adapter slice)** closed 2026-05-21 at [../CAPABILITY_REGISTRY/APP.md](../CAPABILITY_REGISTRY/APP.md). 49 files / 7,975 LoC. Verified BUG-015 wire shape clean (10 byte-level confirmations); BUG-012-i1 instrumentation intact. Surfaced 1 field-level production-orphan (landed 2026-05-21), 1 file-naming drift (landed 2026-05-21), 1 docstring product call (CA.5-FU-2 closed 2026-05-21 same day as CA.6 — Matt picked "stay invisible"; engine-driven adaptations do NOT toast).
- **CA.6 (App-layer Views + ViewModels presentation slice)** closed 2026-05-21 at [../CAPABILITY_REGISTRY/APP_VIEWS.md](../CAPABILITY_REGISTRY/APP_VIEWS.md). 59 files / 8,285 LoC. Verified PlaybackChromeViewModel BUG-015 / D-091 consumer chain clean (no lowercased title+artist string match — Failed Approach #56 eliminated); D-091 single-SettingsStore enforcement clean across View tree; DASH.7 surface clean against D-088 / D-089 (16 line-anchored confirmations); U.10 / U.11 timing-margin compliance clean across 9 widened test files. Three small follow-ups (two file-header docstring drifts in Dashboard family + one architectural-consistency wrapper extraction for AppleMusicConnectionView) all closed same-day 2026-05-21.

**The App layer is now fully closed.** Three engine subsystems remain unaudited: CA-Renderer, CA-Audio, CA-Presets (per-preset state classes).

This kickoff is for **Increment CA.7: the Renderer subsystem** (`PhospheneEngine/Sources/Renderer/`). It is the seventh audit pass and the first into the engine-Metal stack.

## Why Renderer next

Six reasons, in priority order:

1. **Largest unaudited subsystem in the codebase.** 38 files / ~13,067 LoC. After CA.7 lands, the remaining unaudited engine modules are CA-Audio (smaller — `Sources/Audio/`) and CA-Presets (per-preset state classes under `Sources/Presets/`). The renderer is the load-bearing engine module — every preset, every frame, every audio-reactive moment flows through `RenderPipeline.render(...)`.

2. **CA.5 + CA.6 noted Renderer as the load-bearing App ↔ Renderer boundary.** CA.5's §Boundary-noted App ↔ Renderer entry catalogued the producer side: `RenderPipeline` constructed at `VisualizerEngine.swift:600`; `FrameBudgetManager` + `MLDispatchScheduler` at `:667/:668` reading `QualityCeiling` from UserDefaults; `RayMarchPipeline` constructed per-preset in `applyPreset`; per-preset state classes binding slots 6/7/8 via `setDirectPresetFragmentBuffer` / `setDirectPresetFragmentBuffer2` / `setDirectPresetFragmentBuffer3`. CA.7 audits the consumer side end-to-end.

3. **CLAUDE.md "GPU Contract Details" is load-bearing for every preset shader.** Texture binding layout slots 0-11 (G-buffer + IBL + post-process textures + per-preset reserved); buffer binding layout slots 0-8 (FeatureVector, FeedbackParams, StemFeatures, SceneUniforms, accumulated-audio-time, etc.). The contract pointer in CLAUDE.md §GPU Contract delegates to [docs/ARCHITECTURE.md §GPU Contract Details](../ARCHITECTURE.md#gpu-contract-details). Every preset author cited this contract when binding new state classes (D-LM-buffer-slot-8 / D-092 / D-093 / D-094). The contract is implemented inside `RenderPipeline` + `RayMarchPipeline` + `RenderPipeline+PresetSwitching`; CA.7 verifies the implementation matches the documented contract line-by-line.

4. **`MLDispatchScheduler` D-059 dispatch algorithm is BUG-012-i1 instrumented.** Per CA.5: `MLDispatchScheduler.swift:190` carries `BUG012Probe.log(...)` calls beyond the originally-documented 8 instrumented files. CA.5 treated it as instrumented (read-only). CA.7 reads the algorithm itself and verifies: (a) the per-frame `decide(now:budget:)` algorithm matches the D-059 spec — 5 ordered checks (`.ultra` → immediate; pending ≥ `maxDeferralMs` → force-dispatch; `recentFramesObserved < requireCleanFramesCount` → defer (warmup); `recentMaxFrameMs > currentTierBudgetMs` → defer 100 ms; else dispatch); (b) Tier 1 (`maxDeferralMs=2000, requireCleanFramesCount=30`) vs Tier 2 (`maxDeferralMs=1500, requireCleanFramesCount=20`) per `ARCHITECTURE.md §Dispatch Scheduling`; (c) the `FrameTimingProviding` testability seam at the `MLDispatchScheduler` ↔ `FrameBudgetManager` boundary per D-059e (single source of truth — no parallel timing buffer). **The instrumentation files remain read-only** per the BUG-012-i1 Hard Rule carried forward from CA.2.

5. **`FrameBudgetManager` is the budget governor for the entire engine.** 30-frame rolling window (`recentMaxFrameMs`), 180-frame upshift hysteresis (`currentLevel`), per-tier budget thresholds. Consumes the `onFrameTimingObserved` closure that `VisualizerEngine` wires to both the soak-test harness AND the scheduler (D-060c). The governor's quality-downshift behaviour is the user-visible safety net under load; if the algorithm has silently drifted from the documented spec, downshifts may fire at the wrong threshold.

6. **`mv_warp` accumulator architecture (D-027 / MV-2) lives in `RenderPipeline+MVWarp.swift` (397 LoC).** This is the per-vertex feedback architecture that Milkdrop-style ray-march presets depend on (Failed Approach #32 — "Driving ray-march preset visuals from instantaneous audio alone"). Every preset declaring `mv_warp` in its passes list (Arachne, Gossamer, Aurora Veil, VolumetricLithograph, plus future presets) consumes this surface. The implementation is also the load-bearing surface for the **CLAUDE.md "Test in the production-grade rendering pipeline" rule** (promoted 2026-05-18 after AV.1/AV.2/AV.2.1 cascade): tests must exercise the same dispatch path the live app uses. CA.7 audits whether the mv_warp dispatch path is reachable from tests (vs the AV cascade's anti-pattern of bypassing to `preset.pipelineState` directly).

7. **Failed Approach #66 (G-buffer test/prod parity) lives at the `RenderPipeline.render` mesh-vs-SDF branch.** The Ferrofluid Ocean rounds 50-57 cost six tuning rounds because the fixture helper took the SDF branch while live took the mesh branch. The pipeline's branch logic is in `RayMarchPipeline.render(...)` (`runMeshGBufferPass` vs `runGBufferPass`). CA.7 audits whether the dispatch-path selection is correctly documented and whether the test harness can be configured to match the live branch by construction.

8. **`RenderPipeline+ICB.swift` (338 LoC) carries the ICB architecture** that ARCHITECTURE.md §GPU Contract Details references but the audit has never read end-to-end. ICB (Indirect Command Buffer) is load-bearing for the Murmuration particle preset (D-097) and any future particle-family preset.

## Read these first, before doing anything else

1. **CLAUDE.md** — the entire file. Especially: §GPU Contract Details, §Audio Data Hierarchy (the Renderer's audio-consumption interface), Failed Approach #32 (driving ray-march from instantaneous audio alone — motivated MV-2 / D-027), Failed Approach #66 (G-buffer test/prod parity), Failed Approach #67 (one audio primitive per visual layer — applies inside the renderer's per-pass dispatch), the §"Test in the production-grade rendering pipeline" rule (promoted 2026-05-18), and the §"Diagnostic infrastructure precedes fidelity claims" rule (SR.1 / PresetSessionReplay).

2. **docs/CAPABILITY_REGISTRY/APP.md** — CA.5 audit. Read §Boundary-noted "App ↔ Renderer" entry, §Per-file-capability-index for `VisualizerEngine.swift` (the consumer of every Renderer capability), §Verification-of-BUG-015-wire-shape (the BUG-015 wire feeds RenderPipeline indirectly via mood + plan; the renderer side is the consumer).

3. **docs/CAPABILITY_REGISTRY/APP_VIEWS.md** — CA.6 audit. Read §Verification-of-DASH.7-dashboard-surface — DASH.7 has a Renderer-side counterpart (the `BeatCardBuilder` / `StemsCardBuilder` / `PerfCardBuilder` + `DashboardCardLayout` + `DashboardSnapshot` + `DashboardFontLoader` + `StemEnergyHistory` types live in `Sources/Renderer/Dashboard/`). CA.7 closes the producer side of DASH.7.

4. **docs/CAPABILITY_REGISTRY/ML.md** — CA.2 audit. Read §Cross-references for the `MLDispatchScheduler` ↔ ML boundary. The scheduler decides when stem-separation MPSGraph dispatch can fire vs when frame-budget pressure forces deferral.

5. **docs/CAPABILITY_REGISTRY/DSP_MIR.md** — CA.1 audit. Read §Cross-references for the per-frame consumer chain into RenderPipeline. `FeatureVector` / `FeedbackParams` / `SceneUniforms` are passed every frame; `setFeatures` / `setMood` / `updateFeedbackBeatValue` are the App-side write points; the Renderer reads them via the GPU buffer-binding contract.

6. **docs/QUALITY/KNOWN_ISSUES.md** — every Open entry. Especially:
   - **BUG-011** (Closed but ongoing — Arachne over Tier 2 frame budget on M2 Pro; closure rationale section). The FrameBudgetManager governor behaviour is what made the closure decision land — CA.7 verifies the governor algorithm matches the documented spec.
   - **BUG-012** (instrumentation in place — CA.7 MUST NOT edit the 8 instrumented files; `MLDispatchScheduler.swift:190` is among them per CA.5's broader count).
   - **BUG-016** (Lumen Mosaic — Open; the apply path goes through `RenderPipeline` slot-8 binding; CA.5 audited the App-layer apply path, CA.7 audits the renderer-side consumer if it exists).
   - **BUG-001** (Money 7/4 stays REACTIVE — DSP-layer, but the rendered output goes through `DynamicTextOverlay` for the SpectralCartograph mode label; CA.7 may surface adjacent observations).
   - Pre-existing Flakes section — particularly `MetadataPreFetcher.fetch_networkTimeout` (Audio-scope), `SoakTestHarness` (Diagnostics; consumes `FrameBudgetManager` via `RenderPipeline.onFrameTimingObserved`), `MemoryReporter` (env-dependent).

7. **docs/ARCHITECTURE.md** — sections §Renderer (lines 134-184), §Support Tiers (lines 243-247), §Dispatch Scheduling (Increment 6.3; lines 257-273), §Session Recording (§Render-loop integration paragraph — the `RenderPipeline.onFrameRendered` closure that `SessionRecorder` consumes), §Soak Test Infrastructure (§Frame Timing Fan-out D-060c — `RenderPipeline.onFrameTimingObserved`), §Long-Session Resilience (§DisplayChangeCoordinator — `FrameBudgetManager.resetRecentFrameBuffer()`), and the §Module Map Renderer/ block. **Particular attention:** the §Module Map Renderer/ block is the most likely to have drifted given the renderer's complexity (CA.1 found 6 of 20 DSP files missing; CA.2 found 9 of 16 ML files; CA.3 found 13 of 22 Session files; CA.4 found 9 of 14 Orchestrator files; CA.5 found 34 of 49 App engine-adapter files; CA.6 found 27 of 47 Views files + 8 of 12 ViewModels files; expect proportional drift in the 38-file Renderer module).

8. **docs/DECISIONS.md** — grep for D-027 (mv_warp per-vertex feedback architecture), D-059 (MLDispatchScheduler algorithm + Tier 1/2 deferral caps), D-060 (Soak test infrastructure + D-060c frame-timing fan-out), D-061 (long-session resilience — DisplayChangeCoordinator's reset of FrameBudgetManager rolling buffer), D-085 (RayMarchPipeline staged-composition contract), D-087 (DASH.7 dashboard producer types), D-088 (DASH.7.1 brand-alignment — affects the Renderer/Dashboard/ builders), D-089 (DASH.7.2 dark-surface legibility — Renderer-side rendering of card layouts is in Sources/Renderer/Dashboard/), D-092 (slot 6/7 reservations for per-preset world state), D-093 (Arachne worldTex sample at texture 13 — staged composition), D-094 (ArachneSpiderGPU ≤ 80 bytes — slot 7 buffer allocation), D-LM-buffer-slot-8 (Lumen slot 8 fragment buffer).

9. **docs/ENGINEERING_PLAN.md** — search for "Increment 6.3" (MLDispatchScheduler), "Increment 7.1" (Soak harness — `FrameBudgetManager` + `FrameTimingReporter` boundary), "Phase MV" (MV-2 mv_warp pass — D-027), "DASH.7" (Dashboard SwiftUI port; producer-side types live in Renderer/Dashboard/).

10. **docs/SHADER_CRAFT.md §17 (Preset Metadata Format) + §11.1 (Coarse-to-fine workflow)** — every preset's `.json` sidecar lists its render passes; the renderer's `applyPreset` and `RenderPipeline+PresetSwitching` are the consumers of those declarations. CA.7 verifies the pass-name → dispatch-path mapping matches what preset JSON sidecars declare.

11. **docs/RUNBOOK.md** — search for "Debug Overlay" / "G-buffer" / "frame budget" — runtime tweaks Matt uses to diagnose renderer state.

If any of these files do not exist, record the missing reference as a finding and continue with what does exist.

## Hard rules for this phase

1. **No code changes during the audit.** Findings are documented; fixes are separate increments scheduled after the audit publishes. The only file modifications allowed in CA.7 are the new audit document and minor corrections to load-bearing docs (`ARCHITECTURE.md` / `ENGINEERING_PLAN.md` / `KNOWN_ISSUES.md` / `CLAUDE.md`) that the audit surfaces as drift.

2. **BUG-012-i1 instrumentation files remain read-only.** The 8 instrumented files include `MLDispatchScheduler.swift` (per CA.5's broader count — line 190 carries BUG012Probe.log). CA.7 reads it freely but does not edit it. If a doc-drift correction would require editing one of them, surface for Matt's call before landing.

3. **Evidence-based**: every claim cites a file and line. "X exists at path/file.swift:NNN" or "X is referenced but file does not exist." No claims unverified by inspection of the actual source.

4. **`production-orphan` verdicts require a cited grep** (carried forward from CA.2). "X has zero consumers" must be backed by the exact grep command run and a summary of its results. The grep should cover `PhospheneApp/`, `PhospheneEngine/Sources/`, `PhospheneEngine/Tests/`, and `PhospheneAppTests/`. Production-orphan claims without a cited grep will be rejected at closeout.

5. **Pre-grep visibility verification** (carried forward from CA.3 + CA.5 + CA.6). When parallelising file reads via Explore agents, do not trust an agent's "this type is public" / "this method is internal" reports without cross-checking. After receiving each agent's report, run a single visibility grep per file:
   ```
   grep -nE "^public|^[[:space:]]+public|^internal|^[[:space:]]+internal" PhospheneEngine/Sources/Renderer/<file>.swift
   ```
   Reconcile each agent-claimed `public` against the grep. **CA.7 note:** at 38 files / 13k LoC, the hybrid direct-read + Explore-agent approach is the right default. Direct-read the largest files (`RayMarchPipeline.swift` 539, `RenderPipeline.swift` 471, `RenderPipeline+MVWarp.swift` 397, `PostProcessChain.swift` 395, `RayIntersector.swift` 378, `RayMarchPipeline+Passes.swift` 360, `RenderPipeline+Draw.swift` 344, `RenderPipeline+ICB.swift` 338, `ProceduralGeometry.swift` 333, `IBLManager.swift` 309) and any file > 250 lines; batch the rest across 3-4 parallel Explore agents.

6. **Cross-check the kickoff prompt against KNOWN_ISSUES.md as Pass 0** (carried forward from CA.3 + CA.4 + CA.5 + CA.6). Verify every BUG cited in this kickoff against actual status:
   - **BUG-001** — should still be Open (DSP defect; not Renderer-affecting at the apply path).
   - **BUG-011** — should still be Closed against drops-only criteria (Tier 2 frame budget on M2 Pro accepted as known limitation).
   - **BUG-012** — should still be Open (instrumentation in place).
   - **BUG-013** — should still be Open.
   - **BUG-016** — should still be Open (Lumen Mosaic; CA.5 inventoried the App-layer apply path; CA.6 added Renderer-side observation that no `Preset rendered successfully` feedback signal exists).
   - If any kickoff claim disagrees with KNOWN_ISSUES.md, the audit's first finding is the kickoff staleness.

7. **Sub-scope decision is mandatory and document the choice.** At 38 files / ~13k LoC, the Renderer subsystem may exceed the "one increment" budget. Two recommended sub-scope options:
   - **(a) Single increment.** Audit all 38 files in one pass. Methodology: hybrid direct-read + 3-4 parallel Explore agents. Total wall-clock ~8-10 minutes for Pass 1; total audit ~1-2 hours. Risk: agent-batch sizes become harder to coordinate.
   - **(b) CA.7a + CA.7b split.**
     - **CA.7a** = "core pipeline": `RenderPipeline` + 9 `RenderPipeline+*` extensions + `RayMarchPipeline` + 2 `RayMarchPipeline+*` extensions + `FrameBudgetManager` + `MLDispatchScheduler` + `MetalContext` + `IBLManager` + `TextureManager` + `Protocols` + `ShaderLibrary` + `DynamicTextOverlay` + `PostProcessChain` = ~22 files / ~7.5k LoC.
     - **CA.7b** = "supporting" (Dashboard/ 8 files + Geometry/ 4 files + RayTracing/ 3 files = 15 files / ~5.5k LoC).
     The split is justified architecturally: CA.7a is the load-bearing per-frame dispatch path; CA.7b is supporting infrastructure that CA.7a depends on but doesn't drive frame timing. CA.7a closes the test/prod parity question (Failed Approach #66) and the GPU contract verification; CA.7b closes the DASH.7 producer side, the particle/mesh geometry families, and ray tracing.

   **Recommendation:** option (b) split into CA.7a + CA.7b. Reasons: (i) CA.7a has the load-bearing verifications (GPU contract, MLDispatchScheduler algorithm, FrameBudgetManager governor, mv_warp dispatch); these deserve focused attention without competing with the supporting modules. (ii) CA.6's 8.3k LoC was the largest single-increment audit to date and the methodology felt at the limit. (iii) Splitting also leaves a natural "intermediate report" point — Matt can sanity-check CA.7a before CA.7b commits scope.

   Document the choice in the audit doc's §Scope section before Pass 1 begins. If the auditor chooses option (a), justify why a single-pass at 13k LoC is feasible. If option (b), CA.7a is the natural first half and the kickoff scope below details CA.7a's contents.

8. **Exhaustive within scope.** Every public / internal type, every public / internal method in the chosen scope gets a verdict. Coverage is binary for the scope you commit to, not best-effort.

9. **Stop-and-report criteria** (in addition to the standard CLAUDE.md set):
   - Found a `broken-but-claimed` finding that affects production behavior right now (file as BUG-XXX entry; surface immediately — BUG-015 in CA.4 is the load-bearing precedent).
   - The audit's reading of the GPU contract reveals a slot-binding inconsistency between `RenderPipeline` and a documented decision (D-LM-buffer-slot-8, D-092, D-093, D-094).
   - The audit reveals an MLDispatchScheduler or FrameBudgetManager constant that drifts from the documented D-059 spec.
   - The audit reveals a test that bypasses to `preset.pipelineState` for a temporal-behaviour preset (mv_warp / staged / feedback / ray_march + post_process) — the CLAUDE.md "Test in the production-grade rendering pipeline" rule violation.
   - The audit reveals a flake-class regression beyond the U.10 / U.11 pre-existing set.
   - Audit scope is growing beyond the chosen sub-scope. Note the boundary crossing; continue within scope; flag as `boundary-noted` or `boundary-deferred` per the CA.3 convention.
   - The audit format is producing low-value output. Pause, redesign before continuing.

10. **Closeout report cites the audit document, not the audit's findings.** The audit document IS the deliverable.

## Scope of CA.7 (recommendation: CA.7a — core pipeline)

If the auditor chooses option (b) per Pass 0:

### Files in scope — CA.7a "core pipeline" (~22 files, ~7,500 LoC)

**RenderPipeline cluster (10 files, ~3,800 LoC):**
- `RenderPipeline.swift` (471 LoC) — primary owner of MTKView delegate; per-frame render entry; per-preset state binding via slot 6/7/8 setters per D-LM-buffer-slot-8 / D-092 / D-094; `onFrameRendered` + `onFrameTimingObserved` closures consumed by SessionRecorder + soak harness + scheduler per D-060c.
- `RenderPipeline+Draw.swift` (344 LoC) — fragment-only direct-draw path.
- `RenderPipeline+MeshDraw.swift` — mesh-shader path.
- `RenderPipeline+RayMarch.swift` — ray-march dispatch entry (delegates to `RayMarchPipeline`).
- `RenderPipeline+FeedbackDraw.swift` — feedback-warp pass.
- `RenderPipeline+MVWarp.swift` (397 LoC) — mv_warp per-vertex feedback accumulator (D-027 / MV-2; load-bearing for Arachne, Gossamer, Aurora Veil, VolumetricLithograph).
- `RenderPipeline+PostProcess.swift` — post-process chain dispatch.
- `RenderPipeline+Staged.swift` — staged-composition contract (Arachne WORLD → COMPOSITE via texture(13) sample per D-092 / D-093).
- `RenderPipeline+ICB.swift` (338 LoC) — Indirect Command Buffer architecture (Murmuration particle preset; D-097).
- `RenderPipeline+BudgetGovernor.swift` — `FrameBudgetManager` consumer + per-pass gating.
- `RenderPipeline+PresetSwitching.swift` — `applyPreset` / preset switching state-reset machinery; the surface that CA.5 audited from the App-layer side (`VisualizerEngine+Presets.applyPreset`).

**RayMarchPipeline cluster (3 files, ~1,440 LoC):**
- `RayMarchPipeline.swift` (539 LoC) — ray-march dispatch (G-buffer + lighting + composite); the mesh-vs-SDF branch surfaces Failed Approach #66.
- `RayMarchPipeline+Passes.swift` (360 LoC) — per-pass implementations.
- `RayMarchPipeline+PipelineStates.swift` — pipeline-state cache + lookup.

**Frame-budget / dispatch-scheduling (2 files, ~530 LoC):**
- `FrameBudgetManager.swift` (294 LoC) — 30-frame rolling window, 180-frame upshift hysteresis, per-tier budget thresholds; consumed by `MLDispatchScheduler` via `FrameTimingProviding` protocol per D-059e.
- `MLDispatchScheduler.swift` — 5-rule dispatch algorithm per D-059; Tier 1 (2 s / 30 frames) vs Tier 2 (1.5 s / 20 frames) deferral caps. **BUG-012-i1 instrumented — read-only.**

**Resource managers (3 files, ~700 LoC):**
- `MetalContext.swift` — `MetalContext: Sendable`; device + commandQueue + textureLoader + library cache; shared singleton via `MetalContext.shared`.
- `IBLManager.swift` (309 LoC) — Image-Based Lighting cubemap setup; async load via `setupBackgroundTextures` per CA.5's reading of `VisualizerEngine+InitHelpers`.
- `TextureManager.swift` — texture cache + slot binding for background textures.

**Post-process + supporting (3 files, ~520 LoC):**
- `PostProcessChain.swift` (395 LoC) — multi-pass post-process composition (tonemap, color grading, etc.).
- `Protocols.swift` — public protocols the renderer exposes to clients (CA.7 verifies which protocols actually have non-test consumers).
- `ShaderLibrary.swift` — shader source / library loading + preamble compilation per D-085 ordering.

**Other (1 file):**
- `DynamicTextOverlay.swift` — SpectralCartograph mode label rendering surface; consumed by the SpectralCartograph preset for the on-frame BPM / lock / mode display.

### Files deferred to CA.7b (if Pass 0 picks the split)

**Dashboard/ (8 files, ~1,700 LoC)** — DASH.7 producer side:
- `DashboardCardLayout.swift`, `DashboardSnapshot.swift`, `DashboardFontLoader.swift`, `StemEnergyHistory.swift` (value types + font loading).
- `BeatCardBuilder.swift`, `StemsCardBuilder.swift`, `PerfCardBuilder.swift` (3 card builders consumed by `DashboardOverlayViewModel`).
- `PerfSnapshot.swift` (perf-card data carrier).

**Geometry/ (4 files, ~1,200 LoC)**:
- `MeshGenerator.swift` — mesh-shader geometry.
- `ParticleGeometry.swift`, `ParticleGeometryRegistry.swift` — particle-preset geometry surface (siblings-not-subclasses pattern per D-097; Murmuration is the sole current conformer).
- `ProceduralGeometry.swift` (333 LoC) — procedural geometry primitives.

**RayTracing/ (3 files, ~750 LoC)**:
- `BVHBuilder.swift` — bounding-volume hierarchy construction.
- `RayIntersector.swift` (378 LoC) — ray-intersection dispatch.
- `RayIntersector+Internal.swift` — internal-helper extension.

### Boundary surfaces (in scope, with annotation)

- **Renderer ↔ App.** Every public capability of `RenderPipeline` is consumed by `VisualizerEngine` (CA.5 audited from the App side). CA.7 audits the producer-side declarations: which methods are actually called by App-layer code; which fields are publicly exposed but read only by tests; which protocol conformances are stub-only.
- **Renderer ↔ DSP / ML.** `FeatureVector` / `StemFeatures` (consumed via `RenderPipeline.setFeatures(...)`); `EmotionalState` (via `RenderPipeline.setMood(...)`); `BeatGrid` (via `updateFeedbackBeatValue`). All defined in `Shared` (out of CA.7 scope) but referenced in Renderer signatures. Verify Renderer reads them via the documented byte layout per CLAUDE.md `Key Types (Shared Module)` pointer.
- **Renderer ↔ Presets.** Per-preset state classes (`ArachneState`, `GossamerState`, etc.) live in `Sources/Presets/` (CA-Presets later) and bind to slots 6/7/8 via `RenderPipeline.setDirectPresetFragmentBuffer{,2,3}`. CA.7 audits the slot-reservation contract; the per-preset state-class internals are deferred to CA-Presets.
- **Renderer ↔ Audio.** The `RenderPipeline` is constructed in `VisualizerEngine.init` after `AudioInputRouter` and reads `FeatureVector` produced by the analysis queue. No direct Audio module import; the dependency is data-flow only.
- **Renderer ↔ Diagnostics.** `FrameBudgetManager` exposes the `FrameTimingProviding` protocol consumed by `MLDispatchScheduler` AND by `SoakTestHarness.FrameTimingReporter` per D-060c. CA.7 audits both consumer paths.

### Explicit exclusions (out of CA.7a scope)

- **CA.7b** subdirectories (`Dashboard/`, `Geometry/`, `RayTracing/`) — deferred to CA.7b if the split is chosen.
- **`PhospheneEngine/Sources/Audio/`** — CA-Audio (later).
- **`PhospheneEngine/Sources/Presets/`** per-preset Metal shaders + state classes — CA-Presets (later).
- **`PhospheneEngine/Sources/Shared/`** — deferred (CLAUDE.md `Key Types` pointer references it; CA-Shared eventually).
- **`PhospheneEngine/Tests/`** — read freely for test discriminators, but audit verdicts apply to production code, not tests.

If something in the boundary surfaces seems important enough that the audit's value is reduced without it, note the gap and continue. Do not expand scope.

## Methodology

The methodology is the same as CA.5 + CA.6 with no new additions — the format is stable. Quick recap:

### Pass 0 — Kickoff cross-check + sub-scope decision

Before reading any source file:
- **BUG cross-check.** Verify every BUG cited in this kickoff against `docs/QUALITY/KNOWN_ISSUES.md` (BUG-001, BUG-011, BUG-012, BUG-013, BUG-016 — all per the kickoff's claims). If any kickoff claim disagrees, file the disagreement as Finding #1.
- **Sub-scope decision.** Default recommendation: option (b) — CA.7a (core pipeline ~22 files) now; CA.7b (Dashboard/Geometry/RayTracing) later. State the chosen scope explicitly in the audit doc's §Scope section before Pass 1 begins.
- **Verify pre-existing follow-ups.** CA.6-FU-1/2/3 + CA.5-FU-2 all landed 2026-05-21 same day as CA.6 closeout. No carry-forward needed unless something regressed.

### Pass 1 — Inventory + verdict assignment

For each file in scope, produce:
- File summary — one paragraph: what this file owns; the kind of work it does.
- Public / internal surface — every public / internal type and every public / internal method, with brief signatures.
- Documented features — comment headers, MARK sections, doc-comments. Quote verbatim where the claim matters.
- Notable internal types / private members if load-bearing (e.g., `@Published` properties, NSLock-guarded state, dispatch-queue ownership).
- File-level constants / tuning values with names and values (frame-budget thresholds, scheduler deferral caps, mv_warp accumulator decay, etc.).
- Any code-level TODOs / FIXMEs / placeholder branches.

**Read strategy:** at ~7.5k LoC for CA.7a, the hybrid approach is the right default. Direct-read the largest files (RayMarchPipeline.swift, RenderPipeline.swift, RenderPipeline+MVWarp.swift, PostProcessChain.swift, RayMarchPipeline+Passes.swift, RenderPipeline+Draw.swift, RenderPipeline+ICB.swift, IBLManager.swift, FrameBudgetManager.swift) and any file > 250 lines; batch the rest across 2-3 parallel Explore agents.

After each agent's report, run the visibility verification grep per file. Reconcile each agent-claimed `public` against the grep.

Then for each capability, trace consumers via grep:
- `grep -rn "TypeName" PhospheneApp PhospheneAppTests PhospheneEngine/Sources PhospheneEngine/Tests` — type usage.
- `grep -rn "\.functionName(" …` — call sites.
- `grep -rn ": ProtocolName" …` — conformances.
- For types referenced only in tests: note as test-only (different verdict than production).

Record per capability: production consumers, test consumers, no consumers. For any `production-orphan` candidate, the cited grep command + result count is mandatory.

Cross-reference each capability against the load-bearing docs. Record: claimed in docs (yes/no, citations), doc claim aligned with code (yes/no, divergence noted), documented as planned-but-not-built (yes/no).

**Behaviour validation:** the Renderer subsystem has a substantial test surface. Key discriminators by domain:
- `PhospheneEngineTests/Renderer/RayMarchPipelineTests.swift` — ray-march dispatch contract.
- `PresetRegressionTests.swift` — golden-hash regression for every preset (the load-bearing visual-fidelity gate; failing hashes block merges).
- `PresetVisualReviewTests.swift` — `RENDER_VISUAL=1`-gated per-stage contact-sheet harness.
- `MLDispatchSchedulerTests.swift` — the 5-rule algorithm per D-059.
- `FrameBudgetManagerTests.swift` — rolling-window + hysteresis behaviour.
- `IBLManagerTests.swift` — cubemap load + binding.
- `RenderPipeline+MVWarpTests` (if it exists) or `AuroraVeilMVWarpAccumulationTest` — the multi-frame mv_warp accumulator harness CLAUDE.md mandates.

Use them as the discriminators they are.

Assign verdict per capability (definitions carried forward from CA.6):

| Verdict | Meaning |
|---|---|
| `production-active` | Consumed by production code; doc claims match code behavior; behavior validated. |
| `production-orphan` | Consumed nowhere in production code (test consumers only OR no consumers). Requires cited grep. |
| `dead` | Confirmed dead — no consumers anywhere; safe to delete. |
| `stub` | Exists as signature; body empty / default / unimplemented. |
| `documented-but-missing` | Docs claim it exists; code does not. |
| `built-but-undocumented` | Code has it; no doc references it. |
| `broken-but-claimed` | Docs claim it works; runtime behavior contradicts. File a BUG-XXX entry immediately. |
| `unverified-claim` | Consumed; docs claim correctness; no evidence of correctness. |
| `boundary-noted` | Lives at a subsystem boundary; verdict is complete (no future re-audit obligation). |
| `boundary-deferred` | Lives at a subsystem boundary; full verdict requires the other subsystem's audit. |

### Pass 2 — Doc-drift triangulation

Once verdicts are assigned, scan load-bearing docs for additional drift:
- Does `ARCHITECTURE.md §Renderer` (lines 134-184) accurately describe the current Renderer architecture?
- Does `ARCHITECTURE.md §Module Map Renderer/` block list every file?
- Are tuning constants quoted in docs identical to the code's values? (FrameBudgetManager rolling-window size; MLDispatchScheduler tier deferral caps; mv_warp accumulator decay; per-tier budget thresholds.)
- Does any architectural claim describe a render path that no longer exists? Was retired? Was renamed?
- Do any decisions in `DECISIONS.md` reference Renderer-type names that have moved or been renamed?
- Does `CLAUDE.md §GPU Contract Details` match the slot reservations in code?

Record drift findings as a separate cross-reference section in the audit doc.

## Output structure (template — extends CA.6 with Renderer-specific sections)

**Output file:** `docs/CAPABILITY_REGISTRY/RENDERER.md` (if CA.7a only) or split into `RENDERER_CORE.md` + `RENDERER_SUPPORTING.md` if the auditor prefers. Recommendation: single `RENDERER.md` if option (a); `RENDERER.md` for CA.7a then append CA.7b as appendix or new doc per auditor preference.

```
# Capability Registry — Renderer Subsystem
**Audit increment:** CA.7 (or CA.7a if split)
**Date:** 2026-05-XX
**Auditor:** Claude (session-driven, read-only)
**Scope:** PhospheneEngine/Sources/Renderer/ <subset per Pass 0 sub-scope decision>
**Methodology:** Phase CA scoping document (CA.7 kickoff).
**Reads relied on:** [list]

## Summary
[One paragraph: capability counts per verdict, top findings, follow-up count, kickoff-vs-KNOWN_ISSUES cross-check result.]
[Markdown table of verdict counts.]

## Sub-scope decision
[State the scope chosen at Pass 0 explicitly. Justify the choice. If single-pass, document why 13k LoC is feasible.]

## Findings by verdict
[Per-finding citations as CA.5 / CA.6 template.]

## Per-file capability index
[One section per file or per family. Consolidation allowed if verdicts heavily concentrate in production-active.]

## Verification of GPU Contract slot reservations (CA.7-specific)
[Required section. CLAUDE.md §GPU Contract Details + ARCHITECTURE.md §GPU Contract Details claim a specific binding layout (textures 0-11, buffers 0-8). Verify the implementation in RenderPipeline + RayMarchPipeline matches the documented layout exactly. Per-slot table: documented purpose, implementation site (file:line), consumer chain, verdict.]

## Verification of MLDispatchScheduler D-059 algorithm (CA.7-specific)
[Required section. Verify the 5-rule decide(now:budget:) algorithm matches D-059 spec, the Tier 1 / Tier 2 deferral cap constants match (2000ms / 30 frames; 1500ms / 20 frames), and the FrameTimingProviding seam at the FrameBudgetManager boundary is the single source of truth per D-059e. Cite line-by-line.]

## Verification of FrameBudgetManager governor algorithm (CA.7-specific)
[Required section. Verify the 30-frame rolling window, 180-frame upshift hysteresis, per-tier budget thresholds match ARCHITECTURE.md §Renderer + §Support Tiers. BUG-011 closure depended on this algorithm's documented behaviour — verify code matches.]

## Verification of mv_warp accumulator dispatch path (CA.7-specific)
[Required section. Verify the RenderPipeline+MVWarp.swift dispatch path (scene → warp → compose → swap loop) matches D-027 / MV-2 spec; the per-frame accumulator decay constant matches the documented value; the dispatch is reachable from tests (NOT bypassed via preset.pipelineState alone) per CLAUDE.md "Test in the production-grade rendering pipeline" rule.]

## Verification of Failed Approach #66 test/prod parity (CA.7-specific)
[Required section. Verify the RayMarchPipeline.render mesh-vs-SDF branch is documented and that test fixtures can be configured to exercise the same branch the live app uses by construction (NOT by accident). Cross-reference the Ferrofluid Ocean round-57 retirement of the mesh path; verify setMeshGBufferEncoder(nil) is the reset path on every applyPreset.]

## Cross-references
### Updates needed in CLAUDE.md
### Updates needed in ARCHITECTURE.md
### Updates needed in ENGINEERING_PLAN.md
### Updates needed in DECISIONS.md
### New BUG entries
### KNOWN_ISSUES.md sweep

## Follow-up Backlog
| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.7-FU-1** | … | … | … | … |
| **CA.7-FU-2** | … | … | … | … |

## Approach validation
[Critique of methodology. What worked? What didn't? Recommended changes for CA.7b / CA-Audio / CA-Presets.]
```

## File the artifact + cross-references

Per CLAUDE.md increment closeout protocol:
- The audit document is the primary deliverable.
- Any `broken-but-claimed` findings get BUG-XXX entries in `KNOWN_ISSUES.md` immediately. The next available BUG number is **BUG-017** (BUG-016 was filed 2026-05-21; nothing filed since).
- `ENGINEERING_PLAN.md` gets an entry in **Recently Completed** (CA.7 ✅) plus the CA.7 row in the Phase CA section.
- `CLAUDE.md` / `ARCHITECTURE.md` drift findings are corrected in this same increment.

**Commit shape** (matches CA.1 / CA.2 / CA.3 / CA.4 / CA.5 / CA.6 — two commits, doc-only):
1. `[CA.7] Renderer audit: capability registry + findings`
2. `[CA.7] ARCHITECTURE.md / ENGINEERING_PLAN.md / CLAUDE.md: doc-drift corrections from Renderer audit (if any)`

## Done-when

CA.7 closes when:
- [ ] `docs/CAPABILITY_REGISTRY/RENDERER.md` published.
- [ ] Sub-scope decision documented explicitly (CA.7a / CA.7b / single).
- [ ] Every public / internal capability in the chosen scope has a verdict.
- [ ] Every `production-orphan` verdict cites the grep command used.
- [ ] Every Explore-agent-claimed public / internal symbol was cross-checked against a visibility grep.
- [ ] Kickoff-vs-KNOWN_ISSUES.md cross-check ran as Pass 0 step 1.
- [ ] Every non-`production-active` finding either ships a doc-fix in this increment OR is registered as a `CA.7-FU-N` follow-up.
- [ ] All `broken-but-claimed` findings have BUG entries in `KNOWN_ISSUES.md`.
- [ ] GPU contract slot-reservation verification produced byte-level confirmations against CLAUDE.md / ARCHITECTURE.md.
- [ ] MLDispatchScheduler D-059 algorithm verified line-by-line.
- [ ] FrameBudgetManager governor constants verified against the documented spec.
- [ ] mv_warp accumulator dispatch path verified reachable from tests (CLAUDE.md "production-grade pipeline" rule).
- [ ] Failed Approach #66 test/prod parity verified at the RayMarchPipeline branch.
- [ ] Drift corrections to load-bearing docs landed.
- [ ] "Approach validation" section produces an honest critique of whether this format should continue into CA.7b / CA-Audio / CA-Presets.
- [ ] All commits land on `main` (local). Push only on Matt's explicit approval.
- [ ] No edits to BUG-012-i1 instrumented files (`MLDispatchScheduler.swift` is in scope as read-only).

## After CA.7 lands

Surface to Matt:
- The audit summary (broken-but-claimed count, documented-but-missing count, production-orphan count, follow-up count).
- The verdict on the GPU contract slot reservations — match CLAUDE.md byte-for-byte, or divergence found.
- The verdict on the MLDispatchScheduler D-059 algorithm — match the documented spec, or drift found.
- The verdict on the FrameBudgetManager governor — match the documented behaviour BUG-011 closure depended on, or drift found.
- The verdict on the mv_warp accumulator + Failed Approach #66 test/prod parity.
- Any BUG-016-adjacent findings (Lumen Mosaic slot-8 binding race candidate; LumenPatternEngine init failure surface).
- Any BUG-011-adjacent findings (Tier 2 frame budget governor behaviour; M2 Pro Arachne perf headroom).
- Any new CA.7-FU items registered.
- The recommended next subsystem — **CA.7b** (Dashboard/ + Geometry/ + RayTracing/ — the supporting Renderer modules deferred from CA.7a) if the split was chosen; OR **CA-Audio** (`Sources/Audio/` — smaller; closes AudioInputRouter / SilenceDetector / InputLevelMonitor / StreamingMetadata / MetadataPreFetcher per CA.3's boundary-noted item) if the auditor's read shows Audio is more time-critical.

Do not start CA.7b or CA-Audio in the same session.

## Failure modes to watch for

Specifically for Renderer-shaped audit work:

1. **Treating `RenderPipeline` as a black box.** RenderPipeline is the load-bearing center of the Metal stack. Every public method, every `setXxx(...)` slot binder, every `setMeshPresetTick`/`setDirectPresetFragmentBuffer{,2,3}` is per-line-traceable. The audit's job is to verify the implementation matches the GPU contract + the documented D-027 / D-059 / D-LM-buffer-slot-8 / D-092 / D-093 / D-094 decisions.

2. **Trivial-finding inflation across 22 files.** Most extension methods will be production-active with little drama. The depth targets are: GPU contract slot bindings (load-bearing for every preset); MLDispatchScheduler decide() algorithm; FrameBudgetManager rolling-window + hysteresis; mv_warp dispatch path; RayMarchPipeline mesh-vs-SDF branch (Failed Approach #66); RenderPipeline+PresetSwitching reset machinery (the CA.5 App-side `applyPreset` consumer); SessionRecorder + soak-harness `onFrameRendered` / `onFrameTimingObserved` closure fan-out (D-060c). Smaller files (Protocols, ShaderLibrary entry points, MetalContext singleton, DynamicTextOverlay) get surface-level production-active rows.

3. **GPU contract slot verification.** Re-grep for every CLAUDE.md GPU Contract slot. The textures are `0-11` (`scene`, `depth`, IBL, post-process, foam noise, world textures); the buffers are `0-8` (FeatureVector, FeedbackParams, StemFeatures, SceneUniforms, accumulatedAudioTime, SpectralHistoryBuffer per D-030, slots 6/7 per-preset world per D-092, slot 8 per D-LM-buffer-slot-8). Each slot's binding site in `RenderPipeline.swift` and `RayMarchPipeline.swift` is verifiable by grep. Any mismatch is a real finding.

4. **MLDispatchScheduler verification.** The D-059 algorithm has 5 ordered rules + Tier 1 / Tier 2 deferral cap constants. Verify each rule's branch in the code matches the doc's order; verify the constants match exactly. If the actual algorithm has 6 rules or the constants drifted, that's a real finding — BUG-011 closure depended on this algorithm's documented behaviour.

5. **FrameBudgetManager verification.** The 30-frame rolling window + 180-frame upshift hysteresis + per-tier budget thresholds. Verify `recentMaxFrameMs` is the rolling max (not the rolling mean or median) per D-059a. Verify the upshift hysteresis prevents oscillation.

6. **mv_warp accumulator verification.** Verify the dispatch path scene → warp → compose → swap matches D-027 spec. Verify the per-frame decay constant matches the documented value. Verify the path is exercised by `AuroraVeilMVWarpAccumulationTest` (the multi-frame production-grade harness CLAUDE.md mandates) and NOT just by single-frame `preset.pipelineState` tests.

7. **Failed Approach #66 verification.** The Ferrofluid Ocean round-57 retirement of the mesh G-buffer path means today's production code only uses the SDF branch. Verify `setMeshGBufferEncoder(nil)` is the reset path on every `applyPreset` (CA.5 confirmed this at `VisualizerEngine+Presets.swift:72`). Verify the test harness can exercise the mesh branch when a future preset needs it.

8. **Citing without verifying.** Same as CA.1-CA.6's rule. Every claim is evidence-backed with a `file:line` or a `doc:line`.

9. **Producing structure as a substitute for substance.** Headers must be backed by content. Empty buckets should be said-empty, not pretended-incomplete.

10. **Scope creep into App, DSP, ML, Session, Orchestrator territory.** When the audit's reading of a Renderer file surfaces an App-side touchpoint (e.g., a publisher signature change), flag as `boundary-noted` (CA.5 / CA.6 already audited App) and proceed. Do not silently expand back into App.

11. **Scope creep into CA-Audio / CA-Presets territory.** `RenderPipeline` accepts FeatureVector / StemFeatures from the analysis queue, but the producer side is Audio + DSP + ML (already audited). The per-preset state classes (`ArachneState`, etc.) live in `Sources/Presets/` — out of CA.7 scope; flag as `boundary-deferred` to CA-Presets.

## Status on entry

**Branch:** `main`. CA.0 + CA.1 + CA.2 + CA.3 + CA.4 + CA.5 + CA.6 + four post-CA.6 follow-ups (CA.5-FU-2, CA.6-FU-1, CA.6-FU-2, CA.6-FU-3) all landed on local `main` as of 2026-05-21. Recent commits (most-recent first, post-CA.6 closeout):

```
<CA.7 kickoff commit (this doc)>
<CA.6 follow-ups commit chain — 4-5 commits>
bd2e9ae3  [CA.6] ARCHITECTURE.md + ENGINEERING_PLAN.md: doc-drift corrections from App Views audit
8afaddbd  [CA.6] App Views audit: capability registry + findings
5393b065  [CA.6] Scoping: kickoff doc for App Views + ViewModels capability audit
f2cc75ab  [test-flake] RELEASE_NOTES_DEV: log the engine fixture restore + cancel widening
…
```

Local + remote: local `main` is ahead of `origin/main` by several CA.6 + follow-up commits as of CA.7 kickoff. Working tree clean apart from the documented `default.profraw` build artifact.

**SwiftLint baseline:** 0 violations across 371 files. Any violation in active source paths is a regression per `project_swiftlint_baseline.md` memory note. CA.7 should remain at 0.

**Pre-existing flakes** continue per the [`dev-2026-05-21-c`/`d`/`e`] chip baselines: engine-side `MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel`, `MemoryReporter` (env-dependent, `isIntermittent: true`); app-side timing margins widened per U.10 / U.11. None are Renderer-internal.

**BUG-012 is Open.** BUG-012-i1 instrumentation in place across 8 files including `MLDispatchScheduler.swift` (in CA.7a scope; read-only). Step 2 (diagnosis) waits on a reproduction.

**BUG-011 is Closed** against drops-only criteria — Tier 2 frame budget on M2 Pro accepted as known limitation. CA.7's FrameBudgetManager governor verification should confirm the algorithm matches what the closure decision depended on.

**BUG-016 is Open.** Lumen Mosaic symptom uncharacterised. CA.5 inventoried the App-layer apply path; CA.6 added the View-tree observation that no "preset rendered successfully" feedback signal exists. CA.7 may surface Renderer-side observations (slot-8 binding race candidate; ShaderLibrary lookup failure surface).

**BUG-001 is Open.** DSP defect; Renderer-side may have ancillary observations (the SpectralCartograph mode label rendered via `DynamicTextOverlay`).

**BUG-013 is Open.** Audio-side defect; not Renderer-affecting at the audit-path level.

**CA.6-FU-4** (RUNBOOK §Test Timing Margins documentation) — registered as optional in CA.6's Follow-up Backlog. Out of CA.7 scope unless it becomes relevant to a Renderer test discriminator.

**No CA.7 code or audit has landed.** This is the kickoff.

## Sign-off

This prompt is the canonical entry point for **Increment CA.7 (Renderer)**. The Phase CA wider scoping (what subsystem comes next after CA.7, the master `docs/CAPABILITY_REGISTRY.md` index file) continues to be one-increment-at-a-time per the CA.0 scoping decision.

If you find the prompt is wrong or stale during the audit, update the prompt before continuing — do not work against a brief you know to be incorrect.

— Matt + Claude (2026-05-21 design session, post-CA.6 closeout + follow-up sweep)

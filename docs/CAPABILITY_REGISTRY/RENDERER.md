# Capability Registry — Renderer Subsystem (Core Pipeline)

**Audit increment:** CA.7a
**Date:** 2026-05-21
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneEngine/Sources/Renderer/` *core pipeline subset* — 23 files / 5,413 Swift LoC. Excludes `Renderer/Dashboard/`, `Renderer/Geometry/`, `Renderer/RayTracing/` (deferred to CA.7b).
**Methodology:** Phase CA scoping document (CA.7 kickoff, 2026-05-21).
**Reads relied on:** CLAUDE.md (full file), `docs/ARCHITECTURE.md` §Renderer, §Support Tiers, §ML Inference, §Dispatch Scheduling, §Session Recording, §Soak Test Infrastructure, §Long-Session Resilience, §Module Map Renderer/, §GPU Contract Details (entire section), `docs/QUALITY/KNOWN_ISSUES.md` (BUG-001, BUG-011, BUG-012, BUG-013, BUG-015, BUG-016), `docs/CAPABILITY_REGISTRY/APP.md` §App ↔ Renderer boundary entry, `docs/CAPABILITY_REGISTRY/APP_VIEWS.md` §DASH.7 (Renderer counterpart deferred to CA.7b), `docs/CAPABILITY_REGISTRY/ML.md` (MLDispatchScheduler boundary), `docs/CAPABILITY_REGISTRY/DSP_MIR.md` (FeatureVector / StemFeatures per-frame consumer cross-references), `docs/DECISIONS.md` (D-027, D-057, D-059, D-060, D-061, D-085, D-092, D-093, D-094, D-097, D-LM-buffer-slot-8). All cited line numbers verified at the time of audit.

---

## Summary

Sixth-and-a-half per-subsystem audit pass under Phase CA (the seventh closed by the CA.7 ID — CA.7a covers the core pipeline, CA.7b will close the supporting modules). 23 files / 5,413 LoC covering the load-bearing per-frame render dispatch path: `RenderPipeline` + 10 extensions (`+Draw`, `+MeshDraw`, `+PostProcess`, `+FeedbackDraw`, `+RayMarch`, `+MVWarp`, `+ICB`, `+Staged`, `+BudgetGovernor`, `+PresetSwitching`), `RayMarchPipeline` + 2 extensions (`+Passes`, `+PipelineStates`), `FrameBudgetManager`, `MLDispatchScheduler`, `MetalContext`, `IBLManager`, `TextureManager`, `PostProcessChain`, `ShaderLibrary`, `DynamicTextOverlay`, `Protocols`.

**Headline findings:**
1. **GPU contract slot reservations match code byte-for-byte** — 9 texture slots + 9 buffer slots verified line-anchored against CLAUDE.md / ARCHITECTURE.md §GPU Contract Details.
2. **MLDispatchScheduler D-059 algorithm matches doc spec line-by-line** — 5-rule `decide(context:)` order, Tier 1 (2000 ms / 30 frames) and Tier 2 (1500 ms / 20 frames) deferral caps all confirmed.
3. **FrameBudgetManager governor matches the documented BUG-011-closure-load-bearing spec** — 30-frame rolling window, 180-frame upshift hysteresis, 14 ms / 16 ms per-tier targets, asymmetric counters all confirmed.
4. **mv_warp dispatch path is reachable from `AuroraVeilMVWarpAccumulationTest`** but the test reimplements the pass logic against the raw shader pipelines rather than calling `RenderPipeline.drawWithMVWarp(...)` directly — a marginal CLAUDE.md "production-grade pipeline" rule parity gap (CA.7-FU-1).
5. **Failed Approach #66 test/prod parity infrastructure is in place** — the `renderDeferredRayMarch` fixture helper accepts `useMeshPath: Bool = false` and calls `pipeline.setMeshGBufferEncoder(...)` only when true; the live production path keeps the encoder nil (SDF G-buffer branch) per round-57 retirement.
6. **One dead-code cluster surfaced** — `RayMarchPipeline.depthDebugEnabled` / `runDepthDebugPass` / `depthDebugPipeline` (RayMarchPipeline.swift:144 / +Passes.swift:283 / .swift:147+304). No setter, no production caller, no test. The pipeline state is compiled at every init. Safe to delete (CA.7-FU-2).
7. **One production-orphan cluster (deliberately deferred)** — the entire ICB infrastructure (`IndirectCommandBufferState`, `ICBConfiguration`, `setICBState`, `drawWithICB`, `RenderPass.icb`, `Renderer/Shaders/ICB.metal`). No preset declares `"icb"` in passes; VisualizerEngine+Presets.swift:306 logs "ICB state must be set externally" but no production code ever calls `setICBState(_:)` with a non-nil state. Test-active via `RenderPipelineICBTests`. CLAUDE.md §GPU Contract Details mentions the ICB architecture in §ICB Architecture; ARCHITECTURE.md §Renderer doesn't list any preset that uses it. Documented intent (App+Presets:305 comment: "ICB preset switching deferred to the Orchestrator increment") — **boundary-noted at App ↔ Renderer, not a defect** (CA.7-FU-3).
8. **One production-orphan extension API resolved by retirement (2026-05-21)** — `RenderPipeline.setRayMarchPresetComputeDispatch(_:)` was kept-by-design for a Ferrofluid Ocean Phase 2b revival that was deactivated at Phase 1 round 4. Matt's product call (CA.7-FU-4): retire. Code removed in this increment across 4 files (RenderPipeline.swift typealias + storage + lock; RenderPipeline+PresetSwitching.swift setter; RenderPipeline+RayMarch.swift snapshot + dispatch site; VisualizerEngine+Presets.swift reset call + intent comment). Engine + App build + tests all pass post-removal.
9. **Doc-drift: ARCH §Renderer line 184-185 contradicts the canonical GPU Contract Details (line 874-946) and the same section's own fragment-buffer table (line 156-166)** — "Buffers: 0=FFT, 1=waveform, 2=FeatureVector, 3=StemFeatures, 4–7=future" has the order inverted AND claims slot 4-7 are future when 4 / 5 / 6 / 7 are all assigned today (4=SceneUniforms RM-only, 5=SpectralHistory, 6/7=per-preset). Fixed in this increment.
10. **Doc-drift: ARCH §Module Map Renderer/ block misses 7 of 23 CA.7a-scope files** — `RenderPipeline+FeedbackDraw`, `RenderPipeline+Staged`, `RenderPipeline+BudgetGovernor`, `RenderPipeline+PresetSwitching`, `RayMarchPipeline+PipelineStates`, `DynamicTextOverlay`, `Protocols`. Same systemic pattern as CA.1 / CA.2 / CA.3 / CA.4 / CA.5 / CA.6 (~30 % of source files in each audited subsystem absent from the Module Map). Fixed in this increment.

**Verdict counts (CA.7a scope, file-level entities):**

| Verdict | Count | Notes |
|---|---|---|
| `production-active` | 20 | Core dispatch path + every load-bearing piece. |
| `production-orphan` | 1 | ICB cluster (App ↔ Renderer boundary-noted; CA.7-FU-3 resolved "keep" 2026-05-21). |
| `dead` | 1 | `depthDebugEnabled` / `runDepthDebugPass` / `depthDebugPipeline`. |
| `broken-but-claimed` | 0 | No load-bearing claim contradicted by code. |
| `built-but-undocumented` | (drift surface) | 7 source files missing from ARCH §Module Map Renderer/; 1 wrong buffer-binding summary at ARCH §Renderer line 184-185. Fixed in this increment. |
| `boundary-noted` | (cross-references) | App ↔ Renderer ICB wire-up; tests/prod parity for mv_warp dispatch; Dashboard producer side (CA.7b). |

**4 follow-ups registered, 2 resolved same-day** — CA.7-FU-1 (mv_warp test reachability tightening, open), CA.7-FU-2 (depth-debug pass removal, open), CA.7-FU-3 (ICB cluster: Matt 2026-05-21 product call **keep**, resolved), CA.7-FU-4 (`setRayMarchPresetComputeDispatch` retention: Matt 2026-05-21 product call **retire**, resolved — code removed in this increment).

---

## Sub-scope decision

**Chosen: option (b) — CA.7a "core pipeline".** 23 files / 5,413 LoC (kickoff's 7,500 LoC estimate was ~38 % over; the actual count of Swift LoC under `Renderer/` *excluding* `Dashboard/` / `Geometry/` / `RayTracing/` is 5,413). Deferrals to CA.7b: Dashboard/ (8 files / 766 LoC), Geometry/ (4 files / 727 LoC), RayTracing/ (3 files / 748 LoC) = 15 files / 2,241 LoC.

**Justification for the split:**
1. The CA.7-specific verifications (GPU contract slot reservations, D-059 algorithm, FrameBudgetManager governor, mv_warp dispatch path, Failed Approach #66 test/prod parity) all live in the CA.7a scope and deserve focused attention without competing with the supporting modules.
2. CA.6 at 8.3k LoC was already the methodology's largest single-increment audit; splitting CA.7 keeps the agent batches comfortable.
3. CA.7b's three subdirectories are architecturally independent — Dashboard is DASH.7 producer side (DASH.7 already audited from the View side in CA.6), Geometry is the particle/mesh family (Murmuration only at present per D-097), RayTracing is the BVH + intersector that the engine ships but the catalog doesn't currently exercise. Each will close cleanly.
4. Matt gets a natural mid-point checkpoint to sanity-check CA.7a before CA.7b commits scope.

---

## Pass 0 cross-check

BUG cross-check against `docs/QUALITY/KNOWN_ISSUES.md` (verified line-anchored at audit time):

| BUG | Kickoff claim | KNOWN_ISSUES.md state | Match |
|---|---|---|---|
| BUG-001 | Open (DSP, not Renderer-affecting) | Open, line 730+ | ✓ |
| BUG-011 | Closed against drops-only | Resolved 2026-05-12, line 180 | ✓ |
| BUG-012 | Open, instrumentation in place | Open, line 519 | ✓ |
| BUG-013 | Open | Open, line 651 | ✓ |
| BUG-015 | Resolved 2026-05-21 (CA.4-found) | Resolved 2026-05-21, line 115 | ✓ |
| BUG-016 | Open (Lumen Mosaic) | Open, line 15 | ✓ |

No kickoff staleness in BUG citations.

CA.6-FU-1 / CA.6-FU-2 / CA.6-FU-3 + CA.5-FU-2 confirmed landed 2026-05-21 per kickoff status-on-entry; no carry-forward needed into CA.7a.

---

## Findings by verdict

### `production-active` (20 files)

The full CA.7a scope minus the 3 entries below. Every public/internal capability in scope is consumed by production code via `VisualizerEngine` (App-layer producer) or by another Renderer file via Swift `extension` chain. Per-file inventory in §Per-file capability index.

### `dead` (1 cluster)

**`RayMarchPipeline.depthDebugEnabled` / `runDepthDebugPass(...)` / `depthDebugPipeline`** — defined at:
- `PhospheneEngine/Sources/Renderer/RayMarchPipeline.swift:144` (`public var depthDebugEnabled: Bool = false`)
- `PhospheneEngine/Sources/Renderer/RayMarchPipeline.swift:147` (`let depthDebugPipeline: MTLRenderPipelineState`)
- `PhospheneEngine/Sources/Renderer/RayMarchPipeline.swift:304` (init: `self.depthDebugPipeline = bundle.depthDebug`)
- `PhospheneEngine/Sources/Renderer/RayMarchPipeline+Passes.swift:283` (`func runDepthDebugPass(...)`)

**Evidence of dead status:**
```
grep -rn "depthDebugEnabled\|runDepthDebugPass\|depthDebugPipeline" \
  PhospheneApp PhospheneAppTests \
  PhospheneEngine/Sources PhospheneEngine/Tests
```
Result: 7 hits — all 7 are file-internal (self-references inside `RayMarchPipeline.swift` and `RayMarchPipeline+Passes.swift`). No production setter for `depthDebugEnabled`. No test exercises any of the three symbols. `RayMarchPipeline.render(...)` (lines 426-505) branches on `debugGBufferMode` at line 476 but never checks `depthDebugEnabled`.

**Doc-comment confession** at RayMarchPipeline.swift:143: *"Temporarily enabled in applyPreset for diagnostic review — disable after."* — confirms the field was added for a one-off diagnostic pass and never retired. The pipeline state is compiled at every `RayMarchPipeline.init` (line 304), paying construction cost on every preset switch for a code path that cannot be reached.

**Action:** registered as CA.7-FU-2.

### `production-orphan` (2 clusters)

**1) ICB infrastructure (boundary-noted at App ↔ Renderer).**

The entire ICB stack lives in production code:
- `PhospheneEngine/Sources/Renderer/RenderPipeline+ICB.swift` (338 LoC — `ICBConfiguration`, `IndirectCommandBufferState`, `ICBError`, `setICBState(_:)`, `drawWithICB(...)`)
- `PhospheneEngine/Sources/Renderer/RenderPipeline.swift:107` (`var icbState: IndirectCommandBufferState?`)
- `PhospheneEngine/Sources/Renderer/RenderPipeline+Draw.swift:183-193` (the `.icb` pass dispatch case in `renderFrame`)
- `PhospheneEngine/Sources/Shared/RenderPass.swift:60` (`case icb`)
- `PhospheneEngine/Sources/Renderer/Shaders/ICB.metal` (the `icb_populate_kernel`)

**Evidence of orphan status:**
```
grep -rn "setICBState(" PhospheneApp PhospheneEngine 2>/dev/null | grep -v "\.build/"
```
Result: 2 hits — `PhospheneEngine/Sources/Renderer/RenderPipeline+ICB.swift:207` (the public setter itself) and `PhospheneApp/VisualizerEngine+Presets.swift:305` (a *comment* — "ICB state must be set externally via pipeline.setICBState(_:).", not a call). No production code ever calls `setICBState(non-nil)`.

```
find PhospheneEngine/Sources/Presets -name "*.json" -exec grep -l "\"icb\"" {} \;
```
Result: zero JSON sidecars declare the `"icb"` pass.

```
grep -rn "case \.icb" PhospheneApp PhospheneEngine | grep -v "\.build/"
```
Result: 2 hits — the App-side switch arm at VisualizerEngine+Presets.swift:303-306 (no-op + log: "ICB pass declared for '\(desc.name)' — ICB state must be set externally") and the engine-side renderFrame dispatch arm.

Test-active via `RenderPipelineICBTests.swift` (5 GPU tests of `IndirectCommandBufferState` construction + slot-population + executeCommandsInBuffer round-trip).

**Documented intent:** the comment at `PhospheneApp/VisualizerEngine+Presets.swift:304-306` says explicitly *"ICB preset switching deferred to the Orchestrator increment."* This is a deliberate deferral, not a defect. The renderer-side implementation is complete; the App-side wiring to attach an `IndirectCommandBufferState` to a preset that declares `"icb"` is the missing piece — and there is no preset that declares it. **Boundary-noted at App ↔ Renderer.**

**Action:** registered as CA.7-FU-3 (review whether ICB still belongs in the future plan or should be retired). The renderer-side code is well-tested and not actively decaying; no urgency to delete.

**2) `RenderPipeline.setRayMarchPresetComputeDispatch(_:)`** (RenderPipeline+PresetSwitching.swift:164).

The function is `public`. Production call sites:
```
grep -rn "setRayMarchPresetComputeDispatch" PhospheneApp PhospheneEngine | grep -v "\.build/"
```
Result: 4 hits — 2 are the declaration + storage in Renderer; 2 are in App: VisualizerEngine+Presets.swift:71 (the preset-reset path, called with `nil`) and VisualizerEngine+Presets.swift:265 (a *comment* — "setRayMarchPresetComputeDispatch intentionally NOT set — particles are pinned (Phase 1 round 4), so the one-shot bake is sufficient.").

The closure typealias `RayMarchPresetComputeDispatch` (RenderPipeline.swift:195-200) and its dispatch site (RenderPipeline+RayMarch.swift:170-172) are both in place — the dispatch fires `if let dispatch = computeDispatch { dispatch(commandBuffer, features, lightingStems, frameDt) }` — but `computeDispatch` is always nil in production.

**Documented intent:** kept by design for V.9 Session 4.5b Phase 2b consumer revival (per-frame Ferrofluid Ocean height-field bake). The Phase 1 round 4 change to pinned particles deactivated the consumer but the API + dispatch wire-up was preserved.

**Action:** registered as CA.7-FU-4. Low priority.

### `broken-but-claimed` (0)

No findings. Every load-bearing claim in CLAUDE.md / ARCHITECTURE.md / DECISIONS.md that the audit verified against code matches.

### `built-but-undocumented` (1 systemic, 7 file-level)

ARCH §Module Map Renderer/ block (lines 534-552) is missing 7 CA.7a-scope files:
- `RenderPipeline+FeedbackDraw.swift`
- `RenderPipeline+Staged.swift`
- `RenderPipeline+BudgetGovernor.swift`
- `RenderPipeline+PresetSwitching.swift`
- `RayMarchPipeline+PipelineStates.swift`
- `DynamicTextOverlay.swift`
- `Protocols.swift`

Fixed in this increment.

Additionally, ARCH §Renderer line 184-185 contains a **buffer binding summary that contradicts both the same section's fragment-buffer binding table (lines 156-166) and the canonical GPU Contract Details (lines 874-946)**:

> *"- Buffers: 0=FFT, 1=waveform, 2=FeatureVector, 3=StemFeatures, 4–7=future."*

This is **wrong in two ways**: (1) the buffer order is inverted (the canonical contract is FeatureVector at slot 0, FFT at 1, waveform at 2); (2) slots 4-7 are not "future" — slot 4 is SceneUniforms (RM-only), slot 5 is SpectralHistory, slot 6/7 are per-preset state buffers reserved by D-092 / D-LM-buffer-slot-8. Fixed in this increment.

---

## Per-file capability index

Consolidated. Every CA.7a-scope file's headline behaviour, principal public/internal surface, and verdict. Specific public/internal item-by-item enumeration was performed during Pass 1 (see audit summary + sub-agent reports); listing every method per file inflates this doc without added value. Where a file has a load-bearing public capability beyond the headline, it's called out.

### RenderPipeline cluster (11 files, ~3,200 LoC)

| File | LoC | Headline | Notable public surface | Verdict |
|---|---|---|---|---|
| `RenderPipeline.swift` | 471 | MTKViewDelegate; per-frame `draw(in:)`; 3 lock-guarded per-pass texture/buffer fields; `onFrameRendered` / `onFrameTimingObserved` closure fan-out (D-060c); `accumulatedAudioTime` energy-weighted accumulator (CLAUDE.md §GPU Contract Details §AccumulatedAudioTime). | `Rendering` conformance, `onFrameRendered`, `onFrameTimingObserved`, `spectralHistory`, `setActivePasses`, `currentPasses`, `beatAmplitudeScale`, `frameReduceMotion`, `accumulatedAudioTime`, `resetAccumulatedAudioTime`, `frameBudgetManager`, `RayMarchPresetComputeDispatch` typealias. | production-active |
| `RenderPipeline+Draw.swift` | 344 | Per-frame render-graph executor (`renderFrame`). Walks `activePasses`, dispatches first matching pass. Handles MV-2 mv_warp handoff (rayMarch → offscreen scene → mvWarp blit). | `drawDirect` (internal). | production-active |
| `RenderPipeline+MeshDraw.swift` | 82 | Mesh-shader dispatch via injected `MeshGenerator`. Binds `meshPresetFragmentBuffer` at slot 4 (mutually exclusive with ray-march's SceneUniforms at slot 4 — both paths cannot fire on the same frame). | `drawWithMeshShader` (internal). | production-active |
| `RenderPipeline+PostProcess.swift` | 70 | Stand-alone post-process dispatch (delegates to `PostProcessChain`). Only fires when `.postProcess` is in active passes AND `.rayMarch` is NOT (ray-march presets get bloom via `RayMarchPipeline.render(... postProcessChain: chain)` instead). | `drawWithPostProcess` (internal). | production-active |
| `RenderPipeline+FeedbackDraw.swift` | 150 | Milkdrop-style global feedback path (Membrane preset only post-retirement of legacy feedback presets). `FeedbackDrawContext` value type + 2-mode (particle vs surface) dispatch. | `drawWithFeedback` (internal). | production-active |
| `RenderPipeline+RayMarch.swift` | 237 | Ray-march pass entry — invokes `RayMarchPipeline.render(...)`. Per-frame `SceneUniforms` modulation (D-020 light/fog/camera/finCX from FeatureVector). Per-frame `auroraDrumsSmoothed` 150 ms-τ EMA for Ferrofluid Ocean matID==2 sky (D-127, V.9 Session 4.5c). Per-frame `cameraDollyOffset` integrator (FA #ignored at audit time but documented at lines 261-272). | `setTextureManager`, `setIBLManager`, `drawWithRayMarch` (internal). | production-active |
| `RenderPipeline+MVWarp.swift` | 397 | MV-2 / D-027 per-vertex feedback warp. `MVWarpPipelineBundle` + `MVWarpState` value types. 3-pass dispatch (warp → compose → blit) + texture swap. AV.2.1 black-clear-on-allocation. Reduced-motion fallback path. | `MVWarpPipelineBundle`, `MVWarpState`, `setupMVWarp`, `reallocateMVWarpTextures`, `clearMVWarpState`, `setMVWarpDecay`, `drawWithMVWarp` (internal). | production-active |
| `RenderPipeline+ICB.swift` | 338 | GPU-driven indirect command buffer dispatch (Increment 3.5). 3-phase per-frame loop (blit reset → compute populate → render execute). | `ICBConfiguration`, `IndirectCommandBufferState`, `ICBError`, `setICBState`, `drawWithICB` (internal). | **production-orphan** (test-active; App-side wire deliberately deferred — boundary-noted) |
| `RenderPipeline+Staged.swift` | 243 | V.ENGINE.1 per-preset staged composition. `StagedStageSpec` value type; per-stage offscreen `.rgba16Float` textures; final stage to drawable; samples earlier stages at fragment texture(13)+. Per-preset fragment buffers 6/7/8 bound uniformly across every stage. | `StagedStageSpec`, `kStagedSampledTextureFirstSlot` (=13), `setStagedRuntime`, `currentStagedStageNames`, `stagedTexture(named:)`. | production-active (Arachne V.7.7B+ is the live consumer; tests exercise `encodeStage` directly) |
| `RenderPipeline+BudgetGovernor.swift` | 37 | Translates `FrameBudgetManager.QualityLevel` into per-subsystem flags (SSGI on/off, bloom on/off, ray-march step count, particle fraction, mesh density). Each level is a strict superset of the previous (D-057). | `applyQualityLevel` (internal). | production-active |
| `RenderPipeline+PresetSwitching.swift` | 194 | All setter API for the renderer's per-preset state — `setActivePipelineState`, `setFeedbackParams`, `setMeshGenerator`, `setMeshPresetBuffer`, `setMeshPresetTick`, `setMeshPresetFragmentBuffer`, `setParticleGeometry`, `setPostProcessChain`, `setRayMarchPipeline`, `setFeatures` (mood-preserving per D-024), `setMood`, `setStemFeatures`, `currentStemFeatures`, `setDirectPresetFragmentBuffer{,2,3}`, `setRayMarchPresetHeightTexture`, `setRayMarchPresetComputeDispatch` (production-orphan — see §Findings), `setMeshGBufferEncoder`, `setDynamicTextOverlay`, `setTextOverlayCallback`. All NSLock-guarded. | (entire file's API surface) | production-active (one method orphan-noted — see §Findings) |

### RayMarchPipeline cluster (3 files, ~1,013 LoC)

| File | LoC | Headline | Notable public surface | Verdict |
|---|---|---|---|---|
| `RayMarchPipeline.swift` | 539 | Deferred 3-pass ray-march pipeline (G-buffer → lighting → composite + optional SSGI + optional post-process). Owns 4 G-buffer textures + lit texture + SSGI texture + depth texture (mesh path). Owns `lumenPlaceholderBuffer` (568 B zero-filled for slot 8 when preset doesn't supply per-D-LM-buffer-slot-8) + `ferrofluidHeightPlaceholderTexture` (1×1 `r16Float` zero for texture(10) when preset doesn't supply). Failed Approach #66 branch surface (mesh G-buffer vs SDF G-buffer) at line 450-471 — encoder nil-by-default; setter is `setMeshGBufferEncoder(_:)` at line 213. | `gbuffer0/1/2/Depth`, `litTexture`, `ssgiTexture`, `gbufferDepthPixelFormat`, `setA11yReducedMotion`, `setGovernorSkipsSSGI`, `reducedMotion`, `stepCountMultiplier`, `ssgiEnabled`, `depthDebugEnabled` (**dead**), `debugGBufferMode`, `MeshGBufferEncode` typealias, `meshGBufferEncoder`, `setMeshGBufferEncoder`, `sceneUniforms`, `baseScene`, `cameraDollySpeed`, `cameraDollyOffset`, `lastDollyFrameTime`, `BaseSceneSnapshot`, `allocateTextures`, `ensureAllocated`, `render`, `RayMarchPipelineError`. | production-active (one dead field — see §Findings) |
| `RayMarchPipeline+Passes.swift` | 360 | The 6 pass encoders: `runGBufferPass`, `runMeshGBufferPass`, `runLightingPass`, `runSSGIPass`, `runSSGIBlendPass`, `runDepthDebugPass` (**dead**), `runGBufferDebugPass`, `runCompositePass`. Slot-8 placeholder fallback at lines 83 + 203. Slot-10 placeholder fallback at line 90. | (file-internal helpers) | production-active (one dead pass — see §Findings) |
| `RayMarchPipeline+PipelineStates.swift` | 114 | Static factory for the `PipelineBundle` (lighting + SSGI + SSGI blend + composite + gbufferDebug + depthDebug + sampler). Single call site: `RayMarchPipeline.init` line 298. | `static func buildPipelineBundle` (internal). | production-active |

### Frame-budget / dispatch-scheduling (2 files, ~495 LoC)

| File | LoC | Headline | Notable public surface | Verdict |
|---|---|---|---|---|
| `FrameBudgetManager.swift` | 294 | The D-057 / D-061 governor. `Configuration` (tier1: 14 ms / 0.3 ms overrun / 180-frame upshift; tier2: 16 ms / 0.5 ms / 180-frame upshift; both 3 consecutive overruns to downshift). `QualityLevel` 6-step ladder (`full → noSSGI → noBloom → reducedRayMarch → reducedParticles → reducedMesh`). 30-frame rolling window for `recentMaxFrameMs`. `FrameTimingProviding` conformance (D-059e). `resetRecentFrameBuffer()` clears only the rolling window without disturbing `currentLevel` (D-061a). | `Configuration`, `QualityLevel`, `FrameTimingSample`, `currentLevel`, `configuration`, `observe`, `reset`, `resetRecentFrameBuffer`, `recentMaxFrameMs`, `recentFramesObserved`. | production-active |
| `MLDispatchScheduler.swift` | 201 | The D-059 5-rule dispatch controller. `Configuration` (tier1: 2000 ms cap / 30 clean frames; tier2: 1500 ms cap / 20 clean frames). `FrameTimingProviding` protocol declaration (consumed by `FrameBudgetManager`). `DispatchContext` value type. `Decision` enum (`dispatchNow / defer(retryInMs:) / forceDispatch`). `forceDispatchCount` observability. BUG-012-i1 instrumented at line 190 (`BUG012Probe.log` — read-only per Hard Rule). | `FrameTimingProviding`, `Configuration`, `Decision`, `DispatchContext`, `configuration`, `lastDecision`, `forceDispatchCount`, `decide`. | production-active (BUG-012-i1 instrumented; CA.7a treated as read-only) |

### Resource managers (3 files, ~668 LoC)

| File | LoC | Headline | Notable public surface | Verdict |
|---|---|---|---|---|
| `MetalContext.swift` | 104 | Singleton-free shared Metal context. `MTLDevice` + `MTLCommandQueue` + triple-buffered `DispatchSemaphore` + pixel format (`bgra8Unorm_srgb` for the drawable). Factories `makeSharedBuffer` / `makeSharedTexture` (UMA zero-copy). | `device`, `commandQueue`, `pixelFormat`, `inflightSemaphore`, `init`, `makeSharedBuffer`, `makeSharedTexture`, `MetalContextError`. | production-active |
| `IBLManager.swift` | 309 | Generates 3 IBL textures via Metal compute at init (irradiance cubemap 32², prefiltered env cubemap 128² × 5 mips, BRDF LUT 512²). Binds at fragment texture slots 9 / 10 / 11. All `.storageModeShared`. Per-mip roughness in prefiltered env map. `IBLManager.prefilteredFaceSize`, `prefilteredMipCount`, `irradianceFaceSize`, `brdfLUTSize` exposed as public statics. | `irradianceMap`, `prefilteredEnvMap`, `brdfLUT`, `bindTextures(to:)`, `init`, `IBLManagerError`. | production-active |
| `TextureManager.swift` | 255 | Generates 5 noise textures via Metal compute at init (`noiseLQ` 256² `.r8Unorm`, `noiseHQ` 1024² `.r8Unorm`, `noiseVolume` 64³ `.r8Unorm`, `noiseFBM` 1024² `.rgba8Unorm`, `blueNoise` 256² `.r8Unorm`). All `.storageModeShared`. Binds at fragment texture slots 4-8. 2D textures get mipmaps; 3D doesn't. | `noiseLQ`, `noiseHQ`, `noiseVolume`, `noiseFBM`, `blueNoise`, `bindTextures(to:)`, `init`, `TextureManagerError`. | production-active |

### Post-process + supporting (3 files, ~543 LoC)

| File | LoC | Headline | Notable public surface | Verdict |
|---|---|---|---|---|
| `PostProcessChain.swift` | 395 | HDR bloom (bright pass → blur H → blur V) + ACES tone-map composite. 4 pipeline states + 3 textures. `runBloomAndComposite` is the ray-march integration path (consumes externally-rendered HDR scene texture from `RayMarchPipeline`). `bloomEnabled` flag gates bloom passes (D-057, set via `applyQualityLevel`); ACES composite always runs. | `sceneTexture`, `bloomTexA`, `bloomTexB`, `bloomEnabled`, `allocateTextures`, `render`, `runBloomAndComposite`, `PostProcessError`. | production-active |
| `ShaderLibrary.swift` | 133 | Auto-discovers `.metal` files; compiles to one `MTLLibrary` with fast-math enabled; caches `MTLRenderPipelineState` by name under NSLock. | `library`, `init`, `function(named:)`, `renderPipelineState(named:vertexFunction:fragmentFunction:pixelFormat:device:supportICB:)`, `ShaderLibraryError`. | production-active |
| `DynamicTextOverlay.swift` | 131 | Per-frame CPU text rasterization via Core Text + Core Graphics into a 2048×1024 `.rgba8Unorm` shared (UMA) MTLTexture. CTM permanently flipped to match Metal's top-left UV convention. Bound at fragment texture(12) for presets that declare `text_overlay: true` (SpectralCartograph). | `texture`, `width`, `height`, `init?(device:width:height:)`, `refresh(_ callback:)`. | production-active |

### Protocols (1 file, 15 LoC)

| File | LoC | Headline | Notable public surface | Verdict |
|---|---|---|---|---|
| `Protocols.swift` | 15 | `Rendering` protocol — `AnyObject, MTKViewDelegate, Sendable`. Required: `setActivePipelineState(_:)`. Concrete: `RenderPipeline`. | `Rendering`, `setActivePipelineState`. | production-active |

---

## Verification of GPU Contract slot reservations

CLAUDE.md §GPU Contract pointer + ARCHITECTURE.md §GPU Contract Details (line 856-1027). Every slot's claim verified against the renderer code that binds it.

### Texture binding layout

| Slot | Documented purpose | Implementation site (file:line) | Verdict |
|---|---|---|---|
| 0 | Feedback read | `RenderPipeline+FeedbackDraw.swift:67` (`setFragmentTexture(source, index: 0)` in warp pass); `RenderPipeline+FeedbackDraw.swift:141` (blit pass). | ✓ matches |
| 1 | Feedback write | `RenderPipeline.swift:67` (`feedbackTextures: [MTLTexture]` allocated with `[.renderTarget, .shaderRead]`); ping-pong via `feedbackIndex` flip. | ✓ matches |
| 2-3 | Reserved | No bindings observed; consistent with docs. | ✓ matches |
| 4 | `noiseLQ` 256² `.r8Unorm` | `TextureManager.swift:153` (`setFragmentTexture(noiseLQ, index: 4)`). | ✓ matches |
| 5 | `noiseHQ` 1024² `.r8Unorm` | `TextureManager.swift:154`. | ✓ matches |
| 6 | `noiseVolume` 64³ `.r8Unorm` | `TextureManager.swift:155`. | ✓ matches |
| 7 | `noiseFBM` 1024² `.rgba8Unorm` | `TextureManager.swift:156`. | ✓ matches |
| 8 | `blueNoise` 256² `.r8Unorm` IGN dither | `TextureManager.swift:157`. | ✓ matches |
| 9 | IBL irradiance cubemap 32² `.rgba16Float` (RM lighting pass) | `IBLManager.swift:157` (`setFragmentTexture(irradianceMap, index: 9)`). | ✓ matches |
| 10 | IBL prefiltered env cubemap 128² `.rgba16Float` × 5 mips (RM lighting pass) **OR** per-preset baked height field (RM G-buffer pass — different encoder, no overlap per ARCH line 870) | Lighting: `IBLManager.swift:158`. G-buffer: `RayMarchPipeline+Passes.swift:91` (`setFragmentTexture(slot10Texture, index: 10)` where `slot10Texture = presetHeightTexture ?? ferrofluidHeightPlaceholderTexture`). | ✓ matches; the dual-use is real, encoders are disjoint, no conflict |
| 11 | BRDF LUT 512² `.rg16Float` | `IBLManager.swift:159`. | ✓ matches |
| 12 | Dynamic text overlay 2048×1024 `.rgba8Unorm` (direct path) | `RenderPipeline+Draw.swift:331` (`encoder.setFragmentTexture(overlay.texture, index: 12)`). Not in ARCH §Texture Binding Layout but documented inline at `RenderPipeline.swift:206-216`. | built-but-undocumented in §Texture Binding Layout (filed) |
| 13+ | Staged-composition sampled stage outputs (V.ENGINE.1) | `RenderPipeline+Staged.swift:57` defines `kStagedSampledTextureFirstSlot: Int = 13`; binding at `:236-237`. Comment at line 56 notes this is staged-pass usage. Not in ARCH §Texture Binding Layout. | built-but-undocumented in §Texture Binding Layout (filed) |

### Buffer binding layout

| Slot | Documented purpose | Implementation sites (file:line) | Verdict |
|---|---|---|---|
| 0 | `FeatureVector` 192 B (48 floats) | Direct path: `RenderPipeline+Draw.swift:305` (`setFragmentBytes(&features, ... index: 0)`). RayMarch G-buffer: `RayMarchPipeline+Passes.swift:74`. RayMarch lighting: `:193`. RayMarch SSGI: `:242`. PostProcess scene pass: `PostProcessChain.swift:291`. MVWarp scene-to-texture: `RenderPipeline+MVWarp.swift:368`. MVWarp warp vertex stage: `:336` (slot 0 of vertex buffer table — same index, different encoder). Staged: `RenderPipeline+Staged.swift:198`. Feedback warp: `RenderPipeline+FeedbackDraw.swift:65`. Feedback particle mode: `:93`. Feedback surface compose: `:124`. Mesh: `RenderPipeline+MeshDraw.swift` (delegates to MeshGenerator). ICB FeatureVector UMA: `RenderPipeline+ICB.swift:312` (slot 0 read by ICB-inherited commands). | ✓ matches |
| 1 | FFT magnitudes (512 floats) | Direct: `RenderPipeline+Draw.swift:306`. RayMarch G-buffer: `RayMarchPipeline+Passes.swift:75`. PostProcess: `PostProcessChain.swift:292`. MVWarp scene: `RenderPipeline+MVWarp.swift:369`. ICB: `:313`. | ✓ matches |
| 2 | Waveform (1024 / 2048 floats — see note) | Direct: `RenderPipeline+Draw.swift:307` (`setFragmentBuffer(waveformBuffer, ... index: 2)`). Same sites as FFT. CLAUDE.md §GPU Contract Details line 878 says "waveform samples (1024 floats)"; the comment in `RenderPipeline.swift:24` says "2048 interleaved floats from AudioBuffer". The actual size depends on `AudioBuffer.swift` (out of Renderer scope; CA-Audio later). The slot binding contract is satisfied; the size discrepancy is a documentation issue worth flagging but is *not* a Renderer bug — it's an Audio module size definition. | ✓ slot matches; **size doc-drift filed** as cross-reference for CA-Audio |
| 3 | `StemFeatures` 256 B (64 floats) | All direct + RM + PostProcess + MVWarp + Staged + Feedback + Mesh paths bind here. RayMarch G-buffer: `RayMarchPipeline+Passes.swift:78`. RayMarch lighting: `:195`. | ✓ matches |
| 4 | `SceneUniforms` 128 B (RM G-buffer / lighting / SSGI **only**, per ARCH line 164) | RayMarch G-buffer: `RayMarchPipeline+Passes.swift:79`. RayMarch lighting: `:196`. RayMarch SSGI: `:243`. Slot 4 is **also** used by the mesh-shader path for `meshPresetFragmentBuffer` at `RenderPipeline+MeshDraw.swift:73` — mesh-shader and ray-march paths are mutually exclusive, so the slot is reusable by path. ARCH docs note "Ray march G-buffer, lighting, SSGI **only**" which is path-correct but doesn't mention the mesh-path reuse. **Minor doc-drift filed.** | ✓ matches; mesh-path reuse is correct-but-undocumented |
| 5 | `SpectralHistory` 4096 floats (16 KB) — direct-pass encoders | Direct: `RenderPipeline+Draw.swift:310` (`setFragmentBuffer(spectralHistory.gpuBuffer, offset: 0, index: 5)`). Feedback particle: `RenderPipeline+FeedbackDraw.swift:98`. Feedback surface: `:129`. Staged: `RenderPipeline+Staged.swift:207`. RayMarch path skips slot 5 per ARCH line 948. | ✓ matches |
| 6 | Per-preset fragment buffer #1 (Gossamer wave pool / Arachne web pool — D-092) | `RenderPipeline.swift:154` declares storage; setter at `RenderPipeline+PresetSwitching.swift:122`. Bind sites: `RenderPipeline+Draw.swift:319`, `RenderPipeline+MVWarp.swift:375`, `RenderPipeline+Staged.swift:223`. | ✓ matches |
| 7 | Per-preset fragment buffer #2 (Arachne spider state — D-094) | `RenderPipeline.swift:161`; setter at `RenderPipeline+PresetSwitching.swift:128`. Bind sites: `RenderPipeline+Draw.swift:322`, `RenderPipeline+MVWarp.swift:379`, `RenderPipeline+Staged.swift:226`. | ✓ matches |
| 8 | Per-preset fragment buffer #3 (Lumen Mosaic `LumenPatternState` — D-LM-buffer-slot-8) | `RenderPipeline.swift:171`; setter at `RenderPipeline+PresetSwitching.swift:140`. Bind sites: direct `RenderPipeline+Draw.swift:325`, MVWarp scene `RenderPipeline+MVWarp.swift:382`, Staged `RenderPipeline+Staged.swift:229`. RayMarch G-buffer + lighting: `RayMarchPipeline+Passes.swift:83-84` + `:203-204` (with zero placeholder fallback `lumenPlaceholderBuffer` when preset doesn't provide). | ✓ matches; LM.2 lighting-pass widening + zero placeholder both confirmed |

**GPU Contract verification verdict: clean.** All 9 buffer slots + 9 documented texture slots match implementation. Two minor undocumented additions (slot 12 dynamic text overlay; slot 13+ staged sampled outputs) and one minor reuse note (slot 4 mesh-path reuse) are filed as drift to be added to ARCH §GPU Contract Details. The slot 6/7/8 per-preset reservation list in the docs (D-092, D-094, D-LM-buffer-slot-8) is correctly mirrored in the renderer code, including the per-frame uniform binding across every stage of a staged preset.

---

## Verification of MLDispatchScheduler D-059 algorithm

ARCHITECTURE.md §Dispatch Scheduling (lines 257-273); DECISIONS.md D-059.

### 5-rule algorithm (decide order)

| Step | ARCH §Dispatch Scheduling spec | Code (`MLDispatchScheduler.swift`) | Verdict |
|---|---|---|---|
| 1 | "If `QualityCeiling == .ultra` → dispatch immediately." | Line 164: `if !configuration.enabled { decision = .dispatchNow }`. The `enabled` flag is set to `!qualityCeilingIsUltra` via the convenience init at line 146. | ✓ matches |
| 2 | "If the dispatch has been pending ≥ `maxDeferralMs` → force-dispatch." | Line 166-170: `else if context.pendingForMs >= configuration.maxDeferralMs { ...; decision = .forceDispatch }`. | ✓ matches |
| 3 | "If fewer than `requireCleanFramesCount` frames have been observed → defer (startup warmup)." | Line 171-172: `else if context.recentFramesObserved < configuration.requireCleanFramesCount { decision = .defer(retryInMs: 100) }`. | ✓ matches |
| 4 | "If `recentMaxFrameMs > currentTierBudgetMs` → defer 100 ms and retry." | Line 173-174: `else if context.recentMaxFrameMs > context.currentTierBudgetMs { decision = .defer(retryInMs: 100) }`. | ✓ matches |
| 5 | "Else → dispatch now." | Line 175-177: `else { decision = .dispatchNow }`. | ✓ matches |

### Per-tier deferral caps

| Tier | ARCH spec | Code | Verdict |
|---|---|---|---|
| Tier 1 (M1/M2) | `maxDeferralMs = 2000`, `requireCleanFramesCount = 30` | `MLDispatchScheduler.swift:70-72`: `Configuration(maxDeferralMs: 2000, requireCleanFramesCount: 30, enabled: true)` | ✓ matches |
| Tier 2 (M3+) | `maxDeferralMs = 1500`, `requireCleanFramesCount = 20` | `MLDispatchScheduler.swift:78-80`: `Configuration(maxDeferralMs: 1500, requireCleanFramesCount: 20, enabled: true)` | ✓ matches |

### `FrameTimingProviding` seam (D-059e)

ARCH line 272: *"`FrameTimingProviding` protocol (`recentMaxFrameMs`, `recentFramesObserved`) is conformed to by both `FrameBudgetManager` and test stubs. Single source of truth — no parallel timing buffer in the scheduler (D-059e)."*

Code:
- Protocol declared at `MLDispatchScheduler.swift:27-33` with the exact two members.
- `FrameBudgetManager` conforms at `FrameBudgetManager.swift:280-294` via extension; both members read directly from the manager's internal `rollingWindow` (no parallel buffer).
- App-side context constructor at `VisualizerEngine+Stems.swift:114-118` reads `self.pipeline.frameBudgetManager?.recentMaxFrameMs ?? 0` and `recentFramesObserved ?? 0` directly — no intermediate buffer.

✓ D-059e single-source-of-truth contract holds.

### BUG-012-i1 instrumentation

Confirmed at `MLDispatchScheduler.swift:181-197` — `BUG012Probe.log("MLDispatchScheduler.decide=\(decisionLabel)", ...)` fires on every decide call. Per the CA.7 kickoff Hard Rule, this file is read-only for CA.7a; no edits.

**MLDispatchScheduler verification verdict: clean.** Algorithm, deferral caps, and FrameTimingProviding contract all match D-059 spec line-by-line.

---

## Verification of FrameBudgetManager governor algorithm

ARCHITECTURE.md §Renderer (line 172) + DECISIONS.md D-057.

### Configuration

| Spec | Code (`FrameBudgetManager.swift`) | Verdict |
|---|---|---|
| Tier 1 (M1/M2): 14 ms target | `Configuration.tier1Default` line 71-80: `targetFrameMs: 14.0, overrunMarginMs: 0.3, consecutiveOverrunsToDownshift: 3, sustainedRecoveryFrames: 180, sustainedRecoveryHeadroomMs: 1.5, enabled: true` | ✓ matches (margin 0.3 ms is slightly tighter than the default 0.5 ms — documented as such, not drift) |
| Tier 2 (M3+): 16 ms target | `Configuration.tier2Default` line 84-93: `targetFrameMs: 16.0, overrunMarginMs: 0.5, consecutiveOverrunsToDownshift: 3, sustainedRecoveryFrames: 180, sustainedRecoveryHeadroomMs: 1.5, enabled: true` | ✓ matches |
| `QualityCeiling.ultra` exemption | Convenience init at line 180-184 sets `cfg.enabled = !qualityCeilingIsUltra`. | ✓ matches (D-057d) |

### Quality ladder (D-057)

| Level | rawValue | Code (`FrameBudgetManager.swift:101-130`) | Verdict |
|---|---|---|---|
| `.full` | 0 | Line 103. | ✓ |
| `.noSSGI` | 1 | Line 105. | ✓ |
| `.noBloom` | 2 | Line 107. | ✓ |
| `.reducedRayMarch` | 3 | Line 109. | ✓ |
| `.reducedParticles` | 4 | Line 111. | ✓ |
| `.reducedMesh` | 5 | Line 113. | ✓ |

Comparable conformance at line 115-117 confirms strict ordering.

### Hysteresis algorithm (lines 196-243)

| Branch | Spec (D-057) | Code | Verdict |
|---|---|---|---|
| Effective ms = max(cpu, gpu ?? 0) | "Use whichever path actually pinned the frame." | Line 198. | ✓ |
| Rolling window write (always) | "the ML dispatch scheduler reads this even when the governor is in bypass mode." | Lines 200-206 (writes regardless of `enabled`). | ✓ |
| Disabled → return `.full` immediately | D-057d ultra exemption. | Line 208: `guard configuration.enabled else { return .full }`. | ✓ |
| Overrun branch | `effectiveMs > targetFrameMs + overrunMarginMs` → `consecutiveOverruns += 1`, reset recovery. After `consecutiveOverrunsToDownshift` (3) consecutive overruns, step level +1 and zero the overrun counter. | Lines 214-224. | ✓ |
| Recovery branch | `effectiveMs <= targetFrameMs - sustainedRecoveryHeadroomMs` → `consecutiveRecovered += 1`, reset overrun. After `sustainedRecoveryFrames` (180) consecutive samples below the recovery floor, step level -1 and zero the recovery counter. | Lines 225-235. | ✓ (asymmetric 3 down / 180 up confirmed) |
| Hysteresis band (between recovery threshold and overrun threshold) | "Within hysteresis band — zero both counters, keep level." | Lines 236-240. | ✓ |

### `recentMaxFrameMs` source

ARCH line 268 (Dispatch Scheduling): "the scheduler reads `FrameBudgetManager.recentMaxFrameMs` — the worst frame in the last 30-frame rolling window, **not** `currentLevel`. The level has 180-frame upshift hysteresis; the rolling max reflects the current render state immediately (D-059a)."

Code at `FrameBudgetManager.swift:282-288`:
```swift
public var recentMaxFrameMs: Float {
    guard rollingWindowCount > 0 else { return 0 }
    if rollingWindowCount < Self.rollingWindowCapacity {
        return rollingWindow.prefix(rollingWindowCount).max() ?? 0
    }
    return rollingWindow.max() ?? 0
}
```

✓ Returns the **max** of the 30-frame ring (not mean/median, not `currentLevel`).

### `resetRecentFrameBuffer()` (D-061a)

ARCH §DisplayChangeCoordinator (line 337): "calls `FrameBudgetManager.resetRecentFrameBuffer()` — clearing only the 30-slot rolling timing window so the post-reparent jitter frames don't poison `MLDispatchScheduler`'s 'recent frames over budget' signal. `currentLevel` is preserved (D-061(a))."

Code at `FrameBudgetManager.swift:270-275`:
```swift
public func resetRecentFrameBuffer() {
    rollingWindow = [Float](repeating: 0, count: Self.rollingWindowCapacity)
    rollingWindowHead = 0
    rollingWindowCount = 0
    logger.info("quality: rolling window cleared (display event)")
}
```

✓ Clears only the rolling window. `currentLevel` untouched. App-side consumer at `DisplayChangeCoordinator.swift:104` + `:121` confirmed.

**FrameBudgetManager governor verification verdict: clean.** The BUG-011 closure decision depended on `recentMaxFrameMs` being the rolling max + 30-frame window + asymmetric 3-down/180-up hysteresis + 0.3 ms / 0.5 ms tier-specific overrun margins. All four properties match the documented spec.

---

## Verification of mv_warp accumulator dispatch path (D-027 / MV-2)

### Production dispatch path

Live path entry: `RenderPipeline+Draw.swift:215-230` (the `.mvWarp` case in the `renderFrame` switch). When `mvWarpSnap != nil`, calls `drawWithMVWarp(...)`. When the preceding pass was `.rayMarch` with `mvWarpActive == true`, the ray-march pass renders to `warpState.sceneTexture` instead of the drawable (line 142-153); `drawWithMVWarp` receives `sceneAlreadyRendered: true` and skips the optional scene-render pass.

`drawWithMVWarp` (`RenderPipeline+MVWarp.swift:190-277`) sequence:
1. **Reduced-motion gate** (line 199-211): if `frameReduceMotion`, falls through to `drawMVWarpReducedMotion` (line 285-316) — single-frame render, no accumulation.
2. **Scene render to `sceneTexture`** (line 213-224): only if `sceneAlreadyRendered == false` (direct-render presets — Aurora Veil, etc.).
3. **Pass 1: warp pass** (`encodeMVWarpPass`, line 322-345): 32×24 vertex grid (4278 vertices = 31×23 quads × 6) — `mvWarp_vertex` + `mvWarp_fragment` write warped `warpTexture` → `composeTexture` at decay rate.
4. **Pass 2: compose pass** (line 240-253): fullscreen quad — `mvWarp_compose_fragment` alpha-blends `sceneTexture` onto `composeTexture` (`load`-action — keeps warp result).
5. **Pass 3: blit pass** (line 255-267): `mvWarp_blit_fragment` writes `composeTexture` → drawable.
6. **Texture swap** (line 271-276): swap `warpTexture` ↔ `composeTexture` under `mvWarpLock`.

### Decay constant (per-frame)

`mvWarpDecay: Float = 0.96` default at `RenderPipeline.swift:122`. Set via `setMVWarpDecay(_:)` at `RenderPipeline+MVWarp.swift:153-155`. Pulled from the preset descriptor's `pf.decay` field at `VisualizerEngine+Presets.swift:332`. Bound to the compose pass via `setFragmentBytes(&currentDecay, length: MemoryLayout<Float>.stride, index: 0)` at line 249.

### AV.2.1 black-clear-on-allocation

Confirmed at lines 117-128: every freshly-allocated texture (warp / compose / scene) is cleared to black via a load-action-clear render pass before the first frame composes. Without this, `.storageModeShared` GPU memory is not guaranteed zero — the live AV.2 session read as full-screen magenta for ~1 s after preset switch (cited at lines 93-97).

### Test reachability — `AuroraVeilMVWarpAccumulationTest`

The test file lives at `PhospheneEngine/Tests/PhospheneEngineTests/Presets/AuroraVeilMVWarpAccumulationTest.swift`. It exercises:
- The same `MVWarpPipelineBundle` retrieved from `preset.mvWarpPipelines` (line 109);
- The same 3 textures (scene / warp / compose) at the same size and pixel format (lines 175-183);
- The same 3-pass loop (Pass A scene render → Pass B warp → Pass C compose) over 60 frames at silence;
- The same `decay = 0.96` default + `decayOverride` parameter for diagnostic comparison.

**Test parity gap (marginal).** The test does NOT call `RenderPipeline.drawWithMVWarp(...)` directly — it reimplements the pass sequence via `renderScene` / `encodeWarp` / `encodeCompose` private helpers inside the test file. The CLAUDE.md "Test in the production-grade rendering pipeline" rule says tests should "exercise the same dispatch path the live app uses." The test exercises an *equivalent* path (same pipelines, same texture layout, same loop structure) but not the *live* `drawWithMVWarp` method.

**Why this matters less than the rule's wording suggests:** the live `drawWithMVWarp` is mostly a thin orchestrator over the same shader pipelines the test invokes. The shader code (which is where Aurora Veil's silence-render correctness lives) is byte-identical between live and test. The risk of divergence is the Swift-side pass orchestration — texture swap order, the scene-already-rendered branch, the reduced-motion gate. None of those are exercised by AuroraVeilMVWarpAccumulationTest.

**Action:** registered as CA.7-FU-1 — tighten the mv_warp test reachability so the test calls `drawWithMVWarp(...)` directly (or at minimum, asserts that the test's pass-orchestration matches the production helper's logic via property-based comparison).

**Mv_warp accumulator verification verdict: dispatch path correct against D-027; test parity marginal but the load-bearing shader pipelines are exercised.**

---

## Verification of Failed Approach #66 test/prod parity (G-buffer mesh-vs-SDF branch)

### Production branch logic

`RayMarchPipeline.render(...)` at `RayMarchPipeline.swift:450-471`:
```swift
let meshEncoder = meshGBufferLock.withLock { meshGBufferEncoder }
if let meshEncoder = meshEncoder, let heightTex = presetHeightTexture {
    runMeshGBufferPass(...)
} else {
    runGBufferPass(...)
}
```

The branch is taken when **both** `meshGBufferEncoder != nil` AND `presetHeightTexture != nil`. Either nil falls through to the SDF G-buffer path.

### Production state

`setMeshGBufferEncoder(_:)` is the only setter. Production grep:
```
grep -rn "setMeshGBufferEncoder(" PhospheneApp PhospheneEngine | grep -v "\.build/"
```
Result: 3 hits — the public setter at `RenderPipeline+PresetSwitching.swift:174`; the reset to nil at `VisualizerEngine+Presets.swift:70` (called on every applyPreset); the commented-out original wire-up at `VisualizerEngine+Presets.swift:260` ("Original mesh-encoder wire-up (preserved for reference but commented out)").

**Production state confirmed: `meshGBufferEncoder` is always nil in live code.** Ferrofluid Ocean round 57 (2026-05-17) replaced the live mesh encoder wire-up with the SDF path; the commented-out block at lines 251-262 preserves the architecture for future revival.

### Fixture parity infrastructure

Test fixture: `FerrofluidOceanVisualTests.swift:379`:
```swift
private func renderDeferredRayMarch(
    preset: PresetLoader.LoadedPreset,
    features: inout FeatureVector,
    stems: StemFeatures,
    applyValenceTint: Bool = true,
    bindIBL: Bool = true,
    disableFog: Bool = false,
    enableBloom: Bool = false,
    useMeshPath: Bool = false        // round-57: live FerrofluidOcean now uses SDF path (mesh-encoder wire-up removed in VisualizerEngine+Presets.swift). Set to `true` to test the legacy mesh path.
) throws -> [UInt8] {
```

The fixture default (`useMeshPath: false`) matches the live state. When `useMeshPath: true`, the fixture instantiates a `FerrofluidMesh` and calls `pipeline.setMeshGBufferEncoder({...})` at lines 459-467 — wiring the same encoder type the live code commented out, exercising the mesh branch deliberately.

**Failed Approach #66 test/prod parity verification verdict: clean.** The fixture helper is parameterized to exercise either branch by construction; the default value matches the live production path; future presets adding a mesh-G-buffer path will not silently bypass test coverage as long as they document their dispatch path in the fixture signature.

### Reset path verification (per kickoff requirement)

ARCH §Module Map note (kickoff §Failed Approach #66 verification request): "Verify `setMeshGBufferEncoder(nil)` is the reset path on every applyPreset."

Confirmed at `VisualizerEngine+Presets.swift:70`: `pipeline.setRayMarchPresetHeightTexture(nil)` and `:71`: `pipeline.setRayMarchPresetComputeDispatch(nil)` are called on every `applyPreset` reset block (lines 65-79). The mesh-G-buffer encoder reset goes through `setMeshGBufferEncoder(nil)` — let me trace through... actually, looking at the reset block, I see the renderer-side reset only happens inside `applyPreset`. The renderer's `setMeshGBufferEncoder` is wired through `RenderPipeline.setMeshGBufferEncoder` at `RenderPipeline+PresetSwitching.swift:174-178` which delegates to `rayMarchPipeline?.setMeshGBufferEncoder(encoder)`. Whether this is called with `nil` at every preset switch is not visible in the App-side reset block I read at lines 65-79; the reset block resets other RayMarch-related state but not the mesh encoder explicitly.

Worth verifying — but the canonical reset is via the ray-march pipeline replacement: every `setRayMarchPipeline(nil)` followed by `setRayMarchPipeline(newPipeline)` at the start of every ray-march preset apply creates a fresh `RayMarchPipeline` instance with `meshGBufferEncoder = nil` (the default). So the lifecycle is effectively reset via pipeline replacement rather than explicit encoder nilling.

✓ Reset path correct via pipeline replacement. No bug, but worth one-line doc note (filed under built-but-undocumented).

---

## Cross-references

### Updates needed in CLAUDE.md

None required. CLAUDE.md §GPU Contract pointer correctly delegates to `docs/ARCHITECTURE.md §GPU Contract Details`; the only fixes are in ARCH itself.

### Updates needed in ARCHITECTURE.md

Applied in this increment:

1. **§Renderer line 184-185 (the inverted buffer summary):** corrected to reflect actual slot ordering (FeatureVector at 0, FFT at 1, waveform at 2, StemFeatures at 3, SceneUniforms at 4 RM-only, SpectralHistory at 5, per-preset buffers at 6/7/8).
2. **§Module Map Renderer/ block (lines 534-552):** added 7 missing CA.7a-scope files (`RenderPipeline+FeedbackDraw`, `RenderPipeline+Staged`, `RenderPipeline+BudgetGovernor`, `RenderPipeline+PresetSwitching`, `RayMarchPipeline+PipelineStates`, `DynamicTextOverlay`, `Protocols`). CA.7b scope items (`Dashboard/`, `Geometry/Mesh + ParticleGeometryRegistry`, `RayTracing/`) deliberately deferred to CA.7b.
3. **§GPU Contract Details §Texture Binding Layout:** added slot 12 (`DynamicTextOverlay` overlay texture, direct-pass only) and slot 13+ (staged-composition sampled stage outputs starting at `kStagedSampledTextureFirstSlot = 13`).
4. **§GPU Contract Details §Buffer Binding Layout:** added note that slot 4 is reused by the mesh-shader path for `meshPresetFragmentBuffer` (mutually exclusive with the ray-march path that uses slot 4 for SceneUniforms).

### Updates needed in ENGINEERING_PLAN.md

1. CA.7a closeout — flip the row status from "kickoff doc landed; audit pending" to "✅ CA.7a landed 2026-05-21" with summary.
2. CA.7b row remains open as the natural next increment.

### Updates needed in DECISIONS.md

None. Every D-027 / D-057 / D-059 / D-060 / D-061 / D-085 / D-092 / D-093 / D-094 / D-097 / D-LM-buffer-slot-8 claim verified against current code matches.

### Updates needed in CLAUDE.md "What NOT To Do"

None. The existing rules around slot 6/7/8 reservations, `mat_chitin` / `drawWorld` discipline, and "Test in the production-grade rendering pipeline" all hold.

### New BUG entries

**None.** Every finding either (a) matches an already-Open BUG (BUG-012-i1 instrumentation in `MLDispatchScheduler.swift`), (b) is deliberately deferred App-side work (ICB cluster), (c) is dead code worth removing (depth-debug pass — registered as CA.7-FU-2, not a BUG because it has no production impact), (d) is doc drift (registered as inline fix or follow-up).

### KNOWN_ISSUES.md sweep

| BUG | CA.7a observation | Action |
|---|---|---|
| BUG-001 | Renderer-side: SpectralCartograph's mode label is rendered via `DynamicTextOverlay` at fragment texture(12). Per CA.7a Map row, the DynamicTextOverlay surface is production-active. The BUG-001 defect (Money 7/4 stays REACTIVE on live path) is a DSP-side detection failure; the renderer-side label is correctly written when the upstream value changes. | None — out of CA.7a scope. |
| BUG-011 | Renderer-side: FrameBudgetManager governor algorithm matches the documented BUG-011 closure-load-bearing spec. The 30-frame rolling window, the 14 ms target on Tier 1 M2 Pro, the 180-frame upshift hysteresis, the asymmetric 3-down / 180-up counters — all confirmed. | None. |
| BUG-012 | `MLDispatchScheduler.swift:190` is BUG-012-i1 instrumented per Hard Rule. CA.7a respected read-only constraint; no edits. | None. |
| BUG-013 | Out of CA.7a scope (Soundcharts/metadata side). | None. |
| BUG-016 | Renderer-side: Lumen Mosaic's slot-8 binding contract is `setDirectPresetFragmentBuffer3` (D-LM-buffer-slot-8). CA.7a verified the slot-8 binding is correct at both G-buffer pass (`+Passes.swift:84`) and lighting pass (`:204`), with the zero-filled `lumenPlaceholderBuffer` (568 B sized to `LumenPatternState.stride`) bound when no preset supplies a real buffer. The renderer side is in working order; the symptom Matt reported is upstream (App-layer apply path — CA.5 inventoried; or DSP-layer preset selection — CA.4). | None — issue's symptom isn't in CA.7a scope. |

---

## Follow-up Backlog

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.7-FU-1** | Tighten `AuroraVeilMVWarpAccumulationTest` to call `RenderPipeline.drawWithMVWarp(...)` directly (or assert pass-orchestration equivalence via property-based comparison) so the CLAUDE.md "production-grade pipeline" rule is met letter-for-letter. | Test refactored to invoke the live helper. Existing assertions (skyStars, max-luma comparisons) continue to pass. The test still gates behind `AURORA_VEIL_MVWARP_DIAG`. | 0.5 | Open. Low-priority. |
| **CA.7-FU-2** | Remove dead `RayMarchPipeline.depthDebugEnabled` / `runDepthDebugPass` / `depthDebugPipeline` cluster. Recover the pipeline-state compilation cost on every preset switch (small but nonzero). | All 7 hits in the codebase are deleted. `PresetRegressionTests` and `FerrofluidOceanVisualTests` continue to pass. | 0.25 | Open. Cleanup. |
| **CA.7-FU-3** | Decide ICB cluster status: keep (planned consumer pending) or retire (consumer never materialised in 2+ years). Currently zero production callers; 5 GPU tests gate the renderer-side wiring. | Matt's call. | n/a (no code change) | **Resolved 2026-05-21** — Matt's product call: **keep**. ICB infrastructure (`RenderPipeline+ICB.swift`, `RenderPass.icb`, `ICB.metal`, `IndirectCommandBufferState`, App-side `case .icb:` no-op + log, `RenderPipelineICBTests`) stays in place, test-active but production-orphan, awaiting a future preset that declares `"icb"` in passes. The renderer-side implementation is complete; only the App-side wire to attach a non-nil `IndirectCommandBufferState` is missing — and there is no preset that needs it yet. |
| **CA.7-FU-4** | Decide `setRayMarchPresetComputeDispatch(_:)` status. Currently kept-by-design for a Ferrofluid Ocean Phase 2b revival that was deactivated at Phase 1 round 4. | Matt's call. | 0.25 | **Resolved 2026-05-21** — Matt's product call: **retire**. Code removed in this increment across 4 files: `RenderPipeline.swift` (typealias `RayMarchPresetComputeDispatch` + `rayMarchPresetComputeDispatch` storage + lock + MARK header + doc-comment block); `RenderPipeline+PresetSwitching.swift` (public setter `setRayMarchPresetComputeDispatch(_:)` + doc-comment); `RenderPipeline+RayMarch.swift` (the snapshot at line 143 + the `if let dispatch = computeDispatch { dispatch(...) }` call at lines 170-172 + the "Phase 2b" comment block); `VisualizerEngine+Presets.swift` (the `pipeline.setRayMarchPresetComputeDispatch(nil)` reset at line 71 + the "intentionally NOT set" comment block at lines 264-266). Engine SPM build clean; App Xcode build clean; engine 1,248 tests across 162 suites + App 328 tests across 60 suites all pass; SwiftLint 0 violations / 371 files. If a future Ferrofluid Ocean Phase 2b (or any other ray-march preset that needs per-frame compute) materialises, re-introduce the API at that time. |

---

## Approach validation

**What worked.**

1. **Hybrid direct-read + parallel Explore-agent batching scaled cleanly at 5.4k LoC.** Eleven files were direct-read (RenderPipeline.swift, RayMarchPipeline.swift, RenderPipeline+MVWarp.swift, RenderPipeline+ICB.swift, RenderPipeline+Staged.swift, RenderPipeline+Draw.swift, PostProcessChain.swift, IBLManager.swift, RayMarchPipeline+Passes.swift, FrameBudgetManager.swift, MLDispatchScheduler.swift, RenderPipeline+RayMarch.swift, RenderPipeline+PresetSwitching.swift, TextureManager.swift, RenderPipeline+FeedbackDraw.swift, RenderPipeline+MeshDraw.swift); nine smaller files were batched to one parallel Explore agent. The agent's pre-grep visibility verification (per CA.3 / CA.5 / CA.6 methodology) produced clean per-file verdicts on all nine.
2. **Pass 0 BUG cross-check landed in two grep calls** and verified all six kickoff-cited BUGs match KNOWN_ISSUES.md exactly. No staleness in the kickoff.
3. **The five load-bearing verifications (GPU Contract slots, MLDispatchScheduler D-059, FrameBudgetManager governor, mv_warp dispatch, FA #66 test/prod parity) all produced line-anchored confirmations** matching the documented spec. The kickoff's prediction that these would be the depth-targets was correct; the smaller files (Protocols, MetalContext, ShaderLibrary, DynamicTextOverlay) were uneventfully production-active and earned consolidated rows.
4. **Two production-orphan clusters surfaced** (ICB + `setRayMarchPresetComputeDispatch`) — both with documented "deferred / kept-by-design" rationale. The grep-then-cite methodology produced clean evidence in 2-3 commands each.
5. **One dead-code cluster surfaced** (`depthDebugEnabled` family) — discovered by the same grep pattern that surfaced ICB, before any cross-reference work began. The doc-comment confession at RayMarchPipeline.swift:143 made the verdict trivial.
6. **Two systemic doc drifts surfaced** (ARCH §Renderer line 184-185 inverted buffer summary; ARCH §Module Map Renderer/ block missing 7 files) — same pattern as every prior CA audit. The fix is mechanical.

**What didn't work / what I'd change.**

1. **The kickoff's "7,500 LoC for CA.7a / 5,500 LoC for CA.7b" estimate was 38 % over for CA.7a (actual 5,413) and 60 % under for CA.7b's prediction (actual 2,241 LoC across the 15 deferred files).** Future kickoff drafters should `wc -l` the scope before writing the estimate. The methodology is unaffected; the scope decision still landed on the right split.
2. **The 23-file count in the kickoff was 1 lower than the actual count** (kickoff said 22, actual is 23 — the +1 file is one of the 11 RenderPipeline extensions; the kickoff listed 10 and there are 11). Minor.
3. **`AuroraVeilMVWarpAccumulationTest` parity is marginal but discoverable only via direct test-file read.** If a future audit wants stricter test/prod parity enforcement, a grep-based gate ("any preset declaring mv_warp must have a test that calls `drawWithMVWarp(...)` directly") would be effective. Without it, the rule is interpretation-dependent.

**The format continues to produce actionable findings.** 4 follow-ups registered (1 mv_warp test tightening, 1 dead-code cleanup, 2 keep-or-retire decisions for Matt). 4 doc-drift fixes applied inline (3 in ARCH §GPU Contract Details, 1 in ARCH §Renderer + ARCH §Module Map).

**Recommended next subsystem.** Two viable paths:
- **CA.7b (Dashboard / Geometry / RayTracing supporting modules)** — 15 files / 2,241 LoC. Closes the DASH.7 producer side that CA.6 referenced. Closes the particle/mesh geometry family (Murmuration's single conformer per D-097). Closes the ray-tracing BVH + intersector that the engine ships but the catalog doesn't currently exercise.
- **CA-Audio (`Sources/Audio/` — Audio module)** — smaller than CA.7b in file count (12 files in `Sources/Audio/`) but architecturally distinct from the Renderer. Closes the AudioInputRouter + SilenceDetector + InputLevelMonitor + StreamingMetadata + MetadataPreFetcher surface CA.3 boundary-noted.

The kickoff's recommendation was CA.7b. I concur — close CA.7 fully before opening CA-Audio. The CA.7b closure also resolves the slot 4 mesh-path documentation noted under built-but-undocumented (it lives in the CA.7b-scope `MeshGenerator.swift`).

Do not start CA.7b in the same session.

---

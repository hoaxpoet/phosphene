# Phosphene Codebase Review Findings

**Date:** 2026-04-13  
**Scope:** All production Swift and Metal files in PhospheneEngine/Sources/ and PhospheneApp/  
**Review tasks:** GPU struct alignment, thread safety, error handling, Metal resource management,
shader correctness, API contract violations, logic bugs, code hygiene, test coverage gaps, known issues  
**Tests after fixes:** 239 swift-testing + 93 XCTest = 332 total, 3 skipped, 0 failures

---

## Fixes Applied

### P0 — `Common.metal` FeatureVector struct missing 8 fields (FIXED)

**File:** `PhospheneEngine/Sources/Renderer/Shaders/Common.metal`

**Severity:** P0 — silent GPU data corruption on every frame using a feedback preset.

**Root cause:** Increment 3.15 (Extended Shader Uniforms) correctly updated:
- `PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift` (preamble for runtime-compiled preset shaders)
- `PhospheneEngine/Sources/Shared/AudioFeatures+Analyzed.swift` (Swift source of truth)

But missed updating `Common.metal`, which is compiled into the Renderer module's static shader library. This library contains `feedback_warp_fragment` and `feedback_blit_fragment`.

**Impact:** Both warp and blit shaders declared a 24-float (96-byte) `FeatureVector` struct. The Swift pipeline uploads 128 bytes from the @frozen FeatureVector. The GPU read the correct first 24 floats but the struct boundary was wrong — `features.time`, `features.delta_time`, `features.mid_att`, etc. were misaligned in practice because the struct itself was declared consistently (fields match), but any future addition relying on the struct size/stride in these shaders would be wrong. More critically, since `RenderPipeline+Draw.swift` binds with `MemoryLayout<FeatureVector>.stride` (128 bytes) but the MSL struct was only 96 bytes, all fields after position 24 in the MSL binding are valid because Metal binds the full 128-byte buffer — the shader simply wouldn't see `accumulated_audio_time`.

**Fix applied:** Added `accumulated_audio_time` and `_pad1`–`_pad7` (8 floats) to `Common.metal`'s FeatureVector struct definition, matching the preamble and Swift struct exactly.

---

### P2 — Stale comment: `RenderPipeline+ICB.swift` says FeatureVector is "96 bytes" (FIXED)

**File:** `PhospheneEngine/Sources/Renderer/RenderPipeline+ICB.swift`, line 64

**Fix applied:** Updated doc comment from "96 bytes" to "128 bytes". Code (`MemoryLayout<FeatureVector>.stride`) was already correct.

---

### P2 — Stale log message: `VisualizerEngine.swift` says "500K particles" (FIXED)

**File:** `PhospheneApp/VisualizerEngine.swift`, line 255

The `makeParticleGeometry` function creates `particleCount: 5_000` (5 thousand particles) but the log said "500K particles".

**Fix applied:** Updated log to "5K particles".

---

## Issues Not Fixed (Require Significant Infrastructure)

### P2 — `makeSceneUniforms` has no guard against degenerate camera direction

**File:** `PhospheneApp/VisualizerEngine+Presets.swift`, `makeSceneUniforms(from:)` (line ~143)

**Issue:** When the camera forward direction is parallel or anti-parallel to world-up `SIMD3(0,1,0)`, `simd_cross(fwd, worldUp)` returns a zero vector. `simd_normalize` of a zero vector is undefined (returns NaN on some implementations). The resulting camera basis would contain NaN values, producing a black or corrupted scene.

**Reproduction:** Set `scene_camera.position: [0, 5, 0]` and `scene_camera.target: [0, 0, 0]` in a preset JSON — forward is `(0, -1, 0)` which is anti-parallel to world-up.

**Recommended fix:** Guard against the degenerate case by using an alternative world-up vector:
```swift
let worldUp = SIMD3<Float>(0, 1, 0)
let altUp = SIMD3<Float>(0, 0, 1)
let useAltUp = abs(simd_dot(fwd, worldUp)) > 0.999
let upRef = useAltUp ? altUp : worldUp
let right = simd_normalize(simd_cross(fwd, upRef))
let up = simd_cross(right, fwd)
```
This handles looking straight up or straight down without NaN.

---

### P3 — `ShaderLibrary.renderPipelineState` has TOCTOU race on pipeline cache

**File:** `PhospheneEngine/Sources/Renderer/ShaderLibrary.swift`, `renderPipelineState(named:...)` (lines 96–123)

**Issue:** The method releases the lock between checking the cache and creating the pipeline, then re-acquires to write. Under concurrent calls with the same name (unlikely in practice but possible during preset hot-reload), two threads could both miss the cache and create duplicate pipeline states. The second write overwrites the first, both are valid, so this is not a correctness bug — just a minor inefficiency.

**Not a priority fix** — shader compilation is expensive but only happens at startup and hot-reload, not per-frame.

---

### P3 — `PostProcessChain.runBloomAndComposite` mutates `sceneTexture` reference

**File:** `PhospheneEngine/Sources/Renderer/PostProcessChain.swift`, `runBloomAndComposite(from:to:commandBuffer:)` (line 241)

**Issue:** `sceneTexture = externalSceneTexture` temporarily replaces the chain's owned scene texture with an externally-provided HDR texture. After the bloom passes complete, `sceneTexture` retains the external reference — the chain's original `sceneTexture` allocation is orphaned until `allocateTextures` is called again. This means:
1. The ray march path leaks one texture reference per call (until reallocated)
2. If the chain is also used for non-ray-march post-process in the same frame (which the current code prevents via the pass-checking logic in `drawWithRayMarch`), there would be a conflict

**Impact:** Low in practice because `runBloomAndComposite` is only called for ray march presets and the chain's `sceneTexture` is not used otherwise in that path. But it's fragile design.

**Recommended fix:** Take the external texture as a local parameter and don't mutate `self.sceneTexture`. Pass `externalSceneTexture` directly to `runBrightPass` instead of via `self.sceneTexture`.

---

### P3 — `MIRPipeline` recording mode uses non-locked `elapsedSeconds` and `stableKey`

**File:** `PhospheneEngine/Sources/DSP/MIRPipeline.swift`, `writeRecordingRow(...)` (line 307)

**Issue:** `writeRecordingRow` is called from `process()` which runs on the analysis queue, but it accesses `stableKey` and `stableBPM` which are `@unchecked Sendable` properties set under the same lock. The method is called after `lock.unlock()` at the end of `updateCPUSideProperties`. Since both `writeRecordingRow` and `updateCPUSideProperties` run sequentially on the analysis queue, there is no actual race — but the code reads properties set in a previous lock scope without holding the lock again. This is a code clarity issue; in practice it's safe because it's all serial.

---

## Clean Code Observations (No Action Required)

### CLAUDE.md test count discrepancy

CLAUDE.md states "314 tests (239 swift-testing + 75 XCTest)" but the actual count is 332 total (239 swift-testing + 93 XCTest). The discrepancy reflects tests added after the last CLAUDE.md update. This is expected and not a defect.

### `drawWithFeedback` no-op beatValue assignment

**File:** `PhospheneEngine/Sources/Renderer/RenderPipeline+Draw.swift`, line 262

```swift
ctx.params.beatValue = ctx.params.beatValue
```

This self-assignment does nothing. The beat value is set by `updateFeedbackBeatValue(from:)` before this call. The line is a dead-code artifact from a refactor. Safe to remove in a future cleanup pass.

### `MIRPipeline.buildFeatureVector` omits `_pad0` from init parameters

**File:** `PhospheneEngine/Sources/DSP/MIRPipeline.swift`, `buildFeatureVector(_:)` (line 251)

The `FeatureVector.init` has `_pad0` defaulting to 0 (correct — it's padding). `buildFeatureVector` doesn't pass `_pad0` or `accumulatedAudioTime` explicitly, relying on defaults. This is by design — `accumulatedAudioTime` is managed by the render pipeline, not the MIR pipeline. No defect, but the comment in `buildFeatureVector` would be clearer if it noted why these fields are omitted.

---

## Areas Reviewed Without Defects Found

- **Audio capture pipeline:** `SystemAudioCapture.swift` — `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` is correct; cleanup order in `cleanup()` is correct (stop → destroy proc → destroy aggregate → destroy tap)
- **Thread safety:** All 12 NSLock instances in `RenderPipeline` are used correctly. `NSLock.withLock {}` is used consistently (not raw lock/unlock pairs) in non-async contexts.
- **Triple-buffered semaphore:** `context.inflightSemaphore.wait()` at frame start; `addCompletedHandler` always signals — deadlock-free.
- **Render graph:** `renderFrame`'s pass-walking logic is correct. Snapshots all subsystem state before the loop. Falls back to `drawDirect` when no pass matches.
- **Feedback ping-pong:** `feedbackIndex = 1 - feedbackIndex` after each feedback frame — correct.
- **UMA buffers:** All shared CPU/GPU buffers use `.storageModeShared`. No `.storageModeManaged` present.
- **FeatureVector layout (preamble):** `PresetLoader+Preamble.swift` has the correct 32-float (128-byte) struct — matches Swift source of truth.
- **StemFeatures layout:** 16-float (64-byte) struct matches in Swift, Common.metal, and preamble.
- **FeedbackParams layout:** 8-float (32-byte) struct matches in Swift, Common.metal, and preamble.
- **SceneUniforms layout:** 8 × SIMD4<Float> = 128 bytes — matches in Swift and both MSL locations (Common.metal and preamble).
- **PostProcess shaders:** Gaussian kernel weights sum to 1.0 (verified). ACES ACES coefficients match Narkowicz 2015.
- **Ray march shader:** Cook-Torrance denominator `max(4 * NdotV * NdotL, 1e-6)` correct. Normal estimation uses correct central-differences epsilon.
- **ICB kernel:** Thread count matches `dispatchThreads(MTLSize(width: maxCount, ...))` — no out-of-bounds.
- **Noise texture generation:** All five textures use correct pixel formats and `.storageModeShared`. Mipmaps generated for 2D textures; 3D texture correctly skips mipmaps. `dispatchThreads` (not `dispatchThreadgroups`) used for non-power-of-two tiles.
- **PresetDescriptor JSON decoding:** All fields use `decodeIfPresent` with sensible defaults. Only `name` is required. Backward-compatible pass synthesis via `synthesizePasses(from:)` handles legacy `use_feedback` / `use_mesh_shader` booleans.
- **RayMarchPipeline.sceneUniforms thread safety:** Analyzed carefully — not a real race. `applyPreset` writes uniforms to a new object before passing it to `setRayMarchPipeline` (which acquires `rayMarchLock`). The render thread can only see the new pipeline after the lock is released post-write.
- **MeshGenerator:** Hardware capability detection at init time is correct. Both mesh (M3+) and vertex fallback (M1/M2) paths produce valid `MTLRenderPipelineState` objects. Object shader is optional — nil is valid.
- **ProceduralGeometry:** Particle init correctly uses golden-angle spiral distribution. Blend state is alpha blending (not additive) — correct for dark silhouettes over sky.
- **ShaderLibrary concatenation order:** Files sorted alphabetically before concatenation. Common.metal compiles first — `FeatureVector`, `StemFeatures`, `FeedbackParams`, `SceneUniforms` structs are available to all subsequent shader files.
- **PresetLoader hot-reload:** `Thread.sleep(0.2)` before reload is an unusual pattern but acceptable for a file-system watcher. `currentIndex` clamped after reload to prevent out-of-bounds access.
- **Audio analysis:** BandEnergyProcessor, BeatDetector, ChromaExtractor, SpectralAnalyzer, MIRPipeline all use NSLock correctly and handle zero-magnitude inputs without division by zero.
- **StemSeparator / StemModelEngine:** MPSGraph pipeline correctly uses `.stride` (not `.size`) for FeatureVector. No CoreML import remains.
- **MoodClassifier:** Pure Accelerate MLP. No CoreML dependency. Non-throwing init.

# Render Capability Registry

**Status legend**

- **Supported** — capability exists in the renderer, exercised by at least one shipping preset, and covered by tests.
- **Partial** — capability exists for one path or one preset family but is not generalised across the renderer; using it from a new preset family requires non-trivial wiring.
- **Missing** — capability does not exist in the codebase. Adding it is a renderer change, not a preset change.
- **Unknown** — capability has been discussed but not investigated; status to be confirmed before any preset depends on it.

This registry was first compiled from the Arachne v8 architecture audit (`docs/VISUAL_REFERENCES/arachne/Arachne_Rendering_Architecture_Contract.md`). It is the engine-side source of truth for "what we can already render" and the gating document for new preset families.

Entries should cite source files. When adding a capability, link to the files that implement it. When marking a capability missing, link to the closest related code so future work has a starting point.

---

## 1. Composition capabilities

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Direct fragment to drawable | Supported | `RenderPipeline+Draw.swift` (drawDirect path); all 2D presets | Default rendering path. |
| Render-to-offscreen-texture (single target) | Supported | `RenderPipeline+MVWarp.swift:325` ("Render the preset's direct fragment shader to an offscreen texture"); `RenderPipeline+RayMarch.swift:90–95` (`if let offscreen = sceneOutputTexture`) | Used by mv_warp warp grid and by ray-march for the warp-target case. |
| Multipass orchestration with named per-pass outputs (per-preset DAG) | Supported (linear) | V.ENGINE.1: `RenderPass.staged` + `PresetDescriptor.stages: [PresetStage]` + `RenderPipeline+Staged.swift`. Diagnostic preset `StagedSandbox` declares `["world", "composite"]` and ships green in `StagedCompositionTests`. | Linear-only DAG (later stages may sample any earlier stage; no fan-out / branching graph). Sufficient for Arachne v8's WORLD → BG_WEBS → FG_WEB → DROPLETS → COMPOSITE chain. A general DAG is deferred. |
| Half-resolution offscreen targets | Partial | SSGI uses half-res `.rgba16Float` (CLAUDE.md §SSGI) | Only the SSGI pass is half-res; no general half-res scratchpad available to other preset passes. |
| Sample-previously-rendered-pass texture from a later fragment in the same frame | Supported | V.ENGINE.1: stage `samples: [...]` array binds earlier stage textures starting at `[[texture(13)]]` (`kStagedSampledTextureFirstSlot`). Tested end-to-end in `StagedCompositionTests.stagedSandboxRendersAndSamplesEarlierStage`. | Slot range: 13+. Slots 0–12 remain reserved for FFT/wave/stems/scene/spectral-history (buffers) and noise/IBL/text (textures). |
| Per-preset multipass shaders (e.g. WORLD → COMPOSITE) | Supported | V.ENGINE.1: `Sources/Renderer/RenderPipeline+Staged.swift`; preset declares `passes: ["staged"]` + `stages: [...]` and the renderer compiles one fragment pipeline per stage. `StagedSandbox` is the diagnostic. | Bridges via `StagedStageSpec` in Renderer / `LoadedStage` in Presets / `setStagedRuntime(_:drawableSize:)` on `RenderPipeline`. |
| Depth attachments / explicit depth buffer for direct fragment presets | Missing | Ray-march has its own G-buffer depth (CLAUDE.md §G-Buffer Layout); direct-fragment passes have none | No depth available to atmospheric / DoF effects in 2D presets. |
| Compositing a 3D ray-march scene under a 2D direct fragment overlay | Missing | — | Not currently a documented combination. |
| ACES tone-map composite | Supported | `PostProcessChain` + `Shaders/PostProcess.metal` (CLAUDE.md §PostProcessChain). Composite always runs even when bloom is gated by the budget governor. | Standard tail of the post-process pass. |
| Bloom (bright-pass + ping-pong blur) | Supported | `PostProcessChain` (gated by `bloomEnabled`) | Gated off by `FrameBudgetManager` at quality `.noBloom` and below. |

## 2. Geometry capabilities

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Fullscreen quad / direct fragment SDF | Supported | `Common.metal` `fullscreen_vertex`; every 2D preset | The default 2D path. |
| 2D SDF utility library (primitives, boolean, modifiers, displacement, hex tile, ray march) | Supported | `Sources/Presets/Shaders/Utilities/Geometry/` (V.2, see CLAUDE.md §Module Map) | 30 `sd_*` primitives + booleans + modifiers + adaptive ray march + hex tile. |
| 3D SDF ray march (deferred G-buffer + lighting) | Supported | `RayMarchPipeline.swift`, `RayMarchPipeline+Passes.swift`, `Shaders/RayMarch.metal` | Cook-Torrance PBR deferred lighting. Used by Volumetric Lithograph, Glass Brutalist, Kinetic Sculpture, Test Sphere. |
| GPU procedural particle system (compute + render, UMA buffer) | Supported | `Sources/Renderer/Geometry/ProceduralGeometry.swift`; `Shaders/Particles.metal` | Murmuration / starburst path. `activeParticleFraction` scales dispatch under the budget governor. |
| Mesh shaders on M3+ (with M1/M2 vertex fallback) | Supported | `Sources/Renderer/Geometry/MeshGenerator.swift`; `Shaders/MeshShaders.metal` | Used by Stalker. `densityMultiplier` is governor-gated. |
| Indirect command buffers | Supported | `RenderPipeline+ICB.swift`; `Shaders/MeshShaders.metal` ICB populate kernel | Used by ICB-driven preset paths. |
| Hardware ray tracing (acceleration structures, intersector) | Supported | `Sources/Renderer/RayTracing/BVHBuilder.swift`, `RayIntersector.swift`; `Shaders/RayTracing.metal` | Available; not yet wired into a shipping preset. |
| Displacement / domain warp / extrusion / revolve helpers | Supported | `Shaders/Utilities/Geometry/SDFDisplacement.metal`, `SDFModifiers.metal` | Lipschitz-safe displacement variants present. |
| Per-pass output of "anchor positions" or other geometric metadata buffers consumed by a later pass | Missing | — | Required for Arachne v8 (the WORLD pass must publish branch-attachment points so the WEB pass terminates radials on real branches). No mechanism exists. |

## 3. Material capabilities

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| PBR utility tree (Fresnel, GGX/Smith, Lambert, Oren-Nayar, Cook-Torrance, Ashikhmin-Shirley) | Supported | `Sources/Presets/Shaders/Utilities/PBR/` (V.1) | Snake_case API documented in CLAUDE.md §Module Map. |
| V.3 materials cookbook (19 surface recipes incl. chrome, brushed aluminum, gold, copper, ferrofluid, ceramic, frosted glass, wet stone, bark, leaf, silk thread, chitin, ocean, ink, marble, granite, velvet, sand glints, concrete) | Supported | `Sources/Presets/Shaders/Utilities/Materials/` (CLAUDE.md §Module Map) | Returns `MaterialResult`. Caller unpacks into `sceneMaterial` out-params for ray-march; usable directly in 2D fragment too. |
| Triplanar texturing | Supported | `Utilities/PBR/Triplanar.metal` (V.1) + procedural triplanar in `Materials/MaterialResult.metal` | Available; usage policy in Arachne is N/A (2D SDF). |
| Detail normals (UDN / whiteout combine) | Supported | `Utilities/PBR/DetailNormals.metal` | |
| Parallax occlusion mapping | Supported | `Utilities/PBR/POM.metal` (`parallax_occlusion`, `parallax_shadowed`) | |
| SSS / fiber BRDF (Marschner-lite, hair TT/TRT lobes) | Supported | `Utilities/PBR/Fiber.metal`, `SSS.metal` | Per-Arachne-v8 review, this is *secondary* for Arachne; reserved for other presets. |
| Thin-film / iridescence | Supported | `Utilities/PBR/Thin.metal` (`thinfilm_rgb`, `hue_rotate`) | |
| Image-based lighting (irradiance cubemap + prefiltered env + BRDF LUT) | Supported | `IBLManager.swift`; `Shaders/IBL.metal` | Bound at textures 9–11 for ray-march presets. |
| Refractive material with screen-space sampling of a previously-rendered texture | Missing | — | Only `refract()` math is available (Metal stdlib). No engine-supported "scene texture" to sample for refraction in a 2D preset. Required for Arachne v8 droplets (`docs/ARACHNE_V8_DESIGN.md §5.8, Pass 4`). |
| Refractive material with depth-aware DoF | Missing | — | No depth source for 2D presets, see §1. |
| Per-fragment material ID routing in 2D presets | Partial | Ray-march path has materialID in the G-buffer; 2D presets typically branch on local SDF state | Works ad-hoc per preset; no engine convention. |

## 4. Lighting capabilities

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Direct lighting via `SceneUniforms` (camera basis, key light, fog, near/far) | Supported | `PresetDescriptor+SceneUniforms.swift`; `RenderPipeline+RayMarch.swift` writes per-frame audio-reactive `SceneUniforms` | Ray-march only. Direct fragment 2D presets must synthesise their own light vectors (e.g. Arachne hardcodes `kL`). |
| IBL ambient with mood-tinted lightColor | Supported | `RayMarchPipeline+Passes.swift` (per CLAUDE.md §Failed Approach #24 — ambient multiplied by `lightColor.rgb`) | Ray-march only. |
| Screen-space global illumination (SSGI) | Supported | `RayMarchPipeline.swift`, `Shaders/SSGI.metal` | Half-res, additive, governor-gated. |
| Volumetric lighting (light shafts, god rays, dust beams) | Partial | `Utilities/Volume/LightShafts.metal` provides `ls_radial_step_uv`, `ls_shadow_march`, `ls_sun_disk`, `ls_intensity_audio` | Utility functions exist; no shipping preset composes shafts as a separate pass. Required for Arachne WORLD pass §4.2.6. |
| Volumetric fog / participating media | Partial | `Utilities/Volume/HenyeyGreenstein.metal`, `ParticipatingMedia.metal`, `Clouds.metal`, `Caustics.metal` | Functions exist. No depth for 2D presets, so true depth-modulated fog is not currently authorable in a 2D fragment. |
| Caustics | Supported (utility) | `Utilities/Volume/Caustics.metal` | |
| Hero specular highlight | Supported | Cook-Torrance / GGX in PBR utilities; pinpoint specular trivially expressible | Used everywhere. |
| Backlit silk / fiber rim emission | Supported | `sss_backlit`, `wrap_lighting` (V.1 PBR/SSS) | Used by Gossamer, Arachne. |
| Per-pass lighting composite (e.g. apply shafts after WEB) | Missing | — | Currently lighting is per-fragment per-preset. No "compositing pass" abstraction. Arachne Pass 5. |

## 5. Atmosphere capabilities

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Procedural sky / horizon gradient | Partial | Trivially expressible in any 2D fragment (`mix(botCol, topCol, uv.y)`). No shared utility. | If multiple presets want it, lift into a Color or Atmosphere utility. |
| Atmospheric mist / fbm-based haze | Supported | `Utilities/Noise/FBM.metal` (`fbm4/8/12`); used in Volumetric Lithograph and Arachne | |
| Aerial perspective (depth-modulated colour shift) | Partial | Available in ray-march via `apply_fog`; not generalised to 2D | |
| Dust mote field (hash-lattice or fbm-thresholded) | Partial | Authored ad-hoc per preset (Arachne, planned for Gossamer). No shared utility. | Worth promoting to `Utilities/Atmosphere/`. |
| Light shafts as a composable pass | Missing | Utilities exist (`Utilities/Volume/LightShafts.metal`) but no preset uses them as a composited pass | Arachne WORLD §4.2.6. |
| Aurora / large-scale sky structure | Missing | — | Arachne high-arousal variant (ref 15). |
| Forest-stage layered backdrop (sky + distant trees + mid trunks + near branches + floor + atmosphere) as a reusable preset module | Missing | — | First instance will be the Arachne WORLD pass. Should be authored so future "in-the-world" presets (Gossamer revisit, future Stalker variants) can reuse. |

## 6. Motion / state capabilities

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Per-vertex feedback warp (mv_warp) with decay | Supported | `RenderPipeline+MVWarp.swift`; `Shaders/MVWarp.metal` | Required for Milkdrop-class temporal accumulation (D-027). |
| Feedback ping-pong texture | Supported | `RenderPipeline+FeedbackDraw.swift` | Pre-mv_warp generation. |
| Per-preset Swift-side state (per-frame ticking, pool management, GPU buffer flush) | Supported | `Arachnid/ArachneState.swift`, `Gossamer/GossamerState.swift`, `Stalker/StalkerState.swift` | Pattern is established and reusable. |
| Beat-anchored phase clock (`beatPhase01`, `beatsUntilNext`) for anticipation curves | Supported | `MIRPipeline` + `BeatPredictor` (D-028) and post-DSP.2 the offline `BeatGrid` + `LiveBeatDriftTracker` | Authoritative motion source per Failed Approach #33. |
| Accumulated audio time (`accumulated_audio_time`) | Supported | `FeatureVector.accumulated_audio_time` (float 25); `sceneParamsA.x` | For continuous slow drifts that must pause at silence. |
| Whole-scene shake / vibration triggered by audio (e.g. spider footstep bass thump) | Missing | — | Required by Arachne SPIDER pass §6 vibration model. Closest existing primitive is preset-side feedback warp; no engine-level shake. |
| Track-change reset hooks for preset state | Supported | `RenderPipeline.resetAccumulatedAudioTime()`; per-preset `State.reset(...)`; `MIRPipeline.reset()` | Used everywhere; pattern is solid. |
| Per-preset depth-of-focus / per-layer blur | Missing | Bloom blur exists (`PostProcessChain`) but cannot be retargeted to a single layer | Arachne Pass 5 needs DoF on background webs only. |

## 7. Audio-reactivity capabilities

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Continuous energy bands (3-band + 6-band, instant + attenuated) on GPU | Supported | `BandEnergyProcessor` → `FeatureVector` floats 1–24 | Primary visual driver per CLAUDE.md §Audio Data Hierarchy. |
| AGC-normalised deviation primitives (`xRel`, `xDev`, `xAttRel`) | Supported | `FeatureVector` floats 26–34; `StemFeatures` floats 17–24 (D-026, MV-1) | Required style. Absolute-threshold patterns are an anti-pattern. |
| Beat onset pulses (per-band + composite) | Supported | `BeatDetector` → `OnsetPulses` → `FeatureVector` | Accent-only by policy. |
| Beat-phase clock (analytic, drift-tracked) | Supported (post-DSP.2) | `LiveBeatDriftTracker` + offline `BeatGrid` (DSP.2 S5–S8) | For anticipation curves and beat-anchored motion. |
| Per-stem energy + per-stem deviation primitives | Supported | `StemFeatures` floats 1–24 | |
| Per-stem rich metadata (onsetRate, centroid, attackRatio, energySlope) | Supported | `StemAnalyzer` → `StemFeatures` floats 25–40 (MV-3a) | |
| Vocals pitch (YIN) | Supported | `PitchTracker` → `StemFeatures` floats 41–42 (MV-3c) | Used by Gossamer. |
| Mood (valence / arousal) | Supported | `MoodClassifier` → `RenderPipeline.setMood` → `FeatureVector` | Smoothing happens in preset state; never write valence/arousal through `setFeatures` (Failed Approach #25). |
| Spectral history ring buffer (FFT-resolution trails) | Supported | `SpectralHistoryBuffer` (16 KB UMA at fragment buffer 5) | Used by SpectralCartograph; available to any direct-fragment preset. |
| Stem warmup blending for first ~10 s / ad-hoc mode | Supported | `smoothstep(0.02, 0.06, totalStemEnergy)` convention (D-019) | Mandatory for any preset reading `stems.*`. |
| Beat-grid-driven structural prediction (section boundaries) | Supported | `StructuralAnalyzer`, `NoveltyDetector` → `StructuralPrediction` | Consumed by Orchestrator. |

## 8. Visual harness / tooling capabilities

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Per-preset golden dHash regression | Supported | `PresetRegressionTests.swift` (Increment 5.3, D-039) | 64-bit dHash, Hamming ≤ 8 tolerance. |
| Per-preset acceptance invariants (silence non-black, beat ratio, form complexity) | Supported | `PresetAcceptanceTests.swift` (Increment 5.2, D-037) | |
| Final-frame visual review harness (PNG export at 1920×1280, multi-fixture contact sheet) | Supported | `PresetVisualReviewTests.swift` (Increment V.7.6.1) | Gated by `RENDER_VISUAL=1`. |
| Pass-separated capture (e.g. WORLD-only, WEB-only, BG-only) | Supported (staged presets) | V.ENGINE.1: `PresetVisualReviewTests.renderStagedPresetPerStage` writes one PNG per stage per fixture under `RENDER_VISUAL=1`; `RENDER_STAGE=<name>` filters to a single stage. Headless render-through is also covered by `StagedCompositionTests` so the path is exercised on every `swift test` run. | Available only for presets that adopt `RenderPass.staged`. mv_warp / ray-march presets remain final-frame-only at the harness level (their internal passes do not surface as named stages). |
| Anti-reference rejection gate (final frame must not Hamming-match a known anti-reference) | Missing | — | Anti-references exist as JPEGs (`09_anti_clipart_symmetry.jpg`, `10_anti_neon_stylized_glow.jpg`). No automated check. |
| Reference image completeness lint (preset folder has README + N images, names match `_NAMING_CONVENTION.md`) | Supported | `swift run --package-path PhospheneTools CheckVisualReferences` (Increment V.5, D-064) | |
| Automated rubric evaluator (M1 cascade, M2 octaves, M3 materials, M4 deviation, M5 silence, M6 perf, M7 manual; E1–E4; P1–P4) | Supported | `Sources/Presets/Certification/FidelityRubric.swift`; `PresetCertificationStore` (Increment V.6) | |
| Quality reel orchestrator | Partial | `docs/quality_reel.mp4` exists; recording workflow documented | No automated reel-record harness yet. |
| Per-pass timing breakdown (engine-level) | Partial | `FrameTimingReporter` (cumulative + rolling); `FrameBudgetManager` | Frame-level only; no per-pass attribution. |

## 9. Performance / certification capabilities

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Frame budget governor (quality ladder, asymmetric hysteresis, per-tier configuration) | Supported | `FrameBudgetManager.swift` (Increment 6.2, D-057) | Six levels: full → noSSGI → noBloom → reducedRayMarch → reducedParticles → reducedMesh. |
| Quality ceiling override (Auto / Performance / Balanced / Ultra) | Supported | `QualityCeiling` enum; `SettingsStore.qualityCeiling` (Increment U.8) | Ultra exempts the governor. |
| ML dispatch gating (defer stem separation when frames are over budget) | Supported | `MLDispatchScheduler.swift` (Increment 6.3, D-059) | Tier-aware; max defer 2 s / 1.5 s. |
| Memory reporter (`phys_footprint`, matches Activity Monitor) | Supported | `Sources/Diagnostics/MemoryReporter.swift` (Increment 7.1, D-060) | |
| Frame timing histogram + rolling buffer | Supported | `Sources/Diagnostics/FrameTimingReporter.swift` | 100-bucket 0.5 ms histogram + 1000-frame rolling window. |
| Soak test harness (headless, JSON+Markdown report) | Supported | `Sources/Diagnostics/SoakTestHarness.swift`; `SoakRunner` CLI | `Scripts/run_soak_test.sh` for 2-hour runs. |
| Display hot-plug / capture-mode switch resilience | Supported | `DisplayChangeCoordinator`, `CaptureModeSwitchCoordinator`, `NetworkRecoveryCoordinator` (Increment 7.2, D-061) | |
| Per-preset complexity cost gate (per device tier) | Supported | `ComplexityCost`; `DefaultPresetScorer` exclusion (Increment 4.0) | |
| Certification rubric ladder (mandatory / expected / preferred) | Supported | V.6 `FidelityRubric` + `PresetDescriptor.certified` | Uncertified presets excluded from Orchestrator by default (D-067). |
| Per-pass GPU timestamp / breakdown for governor decisions | Missing | Frame-level only | Would help diagnose which pass is breaching budget when staged compositing lands. |
| p95 / p99 frame-time tracking surfaced to certification | Partial | `FrameTimingReporter` exposes percentiles; rubric M6 reads `complexity_cost`, not measured p95 | Closing this means the governor's data feeds rubric M6 directly. |

---

## Preset implications

The capability gaps above shape what preset families are buildable today, what is buildable with localised additions, and what is blocked.

### Buildable today (no engine work)

- **Direct-fragment 2D SDF presets that read FeatureVector + StemFeatures + SpectralHistory** (instrument-family diagnostics like Spectral Cartograph; minimal abstract presets like Plasma, Waveform, Nebula).
- **Direct-fragment + mv_warp presets** that need temporal feedback accumulation but no per-pass compositing (Volumetric Lithograph, Starburst, Gossamer's current architecture).
- **Ray-march scene presets** with deferred PBR + IBL + SSGI + post-process (Glass Brutalist, Kinetic Sculpture, Test Sphere). These already get fog, IBL ambient, hero specular, optional SSGI for free.
- **Mesh-shader / particle / ICB presets** for any concept where the visual element is geometry-instanced (Stalker; future murmuration variants).

### Buildable today with localised additions

- **Volumetric / participating-media-heavy presets** (cloudscapes, fog rooms). Volume utilities exist (`Utilities/Volume/*`); a preset would compose them in-fragment without needing engine changes, but lacks depth so anything depth-modulated is approximate.
- **Caustics, reaction-diffusion, voronoi-based texture presets**. Utilities are in place (V.2 Texture tree).
- **Atmosphere-utility-promoted presets** (sky band, dust motes, light-shaft helpers). Lifting Arachne's atmosphere into shared utilities would unblock similar treatments in future presets at low cost.

### Unblocked by V.ENGINE.1

- **Per-preset multipass with named offscreen textures and pass-separated harness capture.** The `RenderPass.staged` scaffold (linear DAG, samples bound at `[[texture(13)]]`+) plus the `RENDER_VISUAL=1` per-stage harness landed in V.ENGINE.1. `StagedSandbox` is the live diagnostic. **V.7.7A (2026-05-05) migrated Arachne onto this path** with placeholder WORLD + COMPOSITE stages; full WORLD detail, refractive droplets, full silk geometry, and the spider arrive in V.7.7B+. Refractive 2D droplets sampling a previously-rendered WORLD texture, depth-of-focus on a single named layer, and any future "small foreground elements refract the scene behind them" preset (rain on a window, oil-on-water, wet fabric, aquarium glass) can now be authored without further renderer changes.

### Still blocked or severely limited until renderer changes land

- **Anchor-position metadata buffer from one stage consumed by the next.** V.ENGINE.1 plumbs textures across stages but not arbitrary uniform buffers. Arachne v8 needs the WORLD pass to publish 4–7 branch-attachment positions for the WEB pass to terminate radials on. A small follow-up (named per-stage `MTLBuffer` outputs in addition to texture outputs) closes this; until then the WEB stage must derive anchor positions from the same `rng_seed` the WORLD stage uses.
- **Depth attachment for 2D staged presets.** Stages output color only. True depth-modulated fog and depth-aware DoF still require either a per-stage `.r16Float` depth target or a synthesised depth buffer. Approximate DoF (per-stage uniform blur intensity) is authorable today.
- **Whole-scene shake / vibration on bass impulses** (spider footstep; dub-bass room shake). No engine-level scene-shake primitive; would currently require preset-side feedback-warp tricks that don't compose cleanly with mv_warp.
- **Forest-stage / nature-scene presets that re-use a layered backdrop** (Arachne v8, future Gossamer "in the world" revisit, future Stalker forest variant). The first WORLD pass is bespoke; without promotion to a shared module, every nature-scene preset re-pays the implementation cost.
- **Light-shaft-as-composited-pass presets** (cathedral interior; sun through trees; dance-floor smoke beams). Volume utilities exist, but no compositing pass to apply shafts on top of the previously-rendered scene.
- **Presets that need to combine 3D ray-march with 2D direct-fragment overlay** (a ray-marched object inside a 2D illustrated frame). Not currently a documented combination.
- **Per-pass anti-reference rejection** for any preset where a known wrong-output JPEG should hard-fail certification. Affects Arachne (refs 09, 10), and would apply to any future preset with anti-references.

### Implication for the implementation queue

V.ENGINE.1 (2026-05-05) landed the highest-leverage engine investment: per-preset multipass orchestration with named offscreen textures and a pass-separated harness hook. V.7.7A (2026-05-05) migrated Arachne onto the scaffold with placeholder WORLD + COMPOSITE stages — V.7.7B+ now layers the real WORLD detail, refractive droplets, full silk geometry, and spider on top of the staged shape. Any future preset family that needs cross-pass texture sampling is unblocked.

The remaining engine investments, in priority order:

1. **Per-stage uniform-buffer outputs** (small follow-up). Lets the WORLD pass publish anchor positions for the WEB pass to read. Closes the last "Missing" entry in §2 and §4 of this registry that Arachne v8 specifically depends on.
2. **Per-stage `.r16Float` depth attachment** for 2D staged presets. Unblocks true depth-modulated fog and depth-aware DoF.
3. **Whole-scene shake primitive** at the renderer level, distinct from preset-side feedback warp. Spider footstep / dub-bass room shake.
4. **Per-pass GPU timing attribution** for the budget governor. Frame-level only today; per-stage cost data would let the governor scale the most expensive stage instead of dropping the whole pass.
5. **Anti-reference rejection gate** in the certification harness — automated dHash comparison against known anti-reference JPEGs (refs 09 / 10 for Arachne).
6. **Atmosphere-utility promotion** (sky band, dust motes, light-shaft helpers) into shared utilities once Arachne's WORLD stage is authored, so future "in-the-world" presets reuse rather than re-author.
7. **Harness PNG-export bug for staged presets** (small follow-up). `PresetVisualReviewTests.makeBGRAPipeline` currently calls `Bundle.module.url(forResource: "Shaders")` from the test target's bundle, where `Shaders` is not a resource — throws `cgImageFailed` for any staged preset under `RENDER_VISUAL=1`. Fix: source the `.metal` file via `Bundle(for: PresetLoader.self)`. Required before V.7.7B's harness contact-sheet review since per-stage PNGs are how WORLD-only / WEB-only / COMPOSITE outputs are inspected during authoring.

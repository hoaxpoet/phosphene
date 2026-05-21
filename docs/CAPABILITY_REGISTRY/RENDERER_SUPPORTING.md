# Capability Registry — Renderer Subsystem (Supporting Modules)

**Audit increment:** CA.7b
**Date:** 2026-05-21
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneEngine/Sources/Renderer/Dashboard/` (8 files / 766 LoC) + `Geometry/` (4 files / 727 LoC) + `RayTracing/` (3 files / 748 LoC) — **15 files / 2,241 LoC**.
**Methodology:** Phase CA scoping document (CA.7b kickoff, 2026-05-21).
**Reads relied on:**
- `CLAUDE.md` (full — D-097 ban surface; Failed Approach #58; §What NOT To Do)
- `docs/CAPABILITY_REGISTRY/RENDERER.md` (CA.7a sibling audit)
- `docs/CAPABILITY_REGISTRY/APP_VIEWS.md` (CA.6 — DASH.7 consumer chain)
- `docs/CAPABILITY_REGISTRY/APP.md` (CA.5 — `VisualizerEngine+Dashboard` producer)
- `docs/QUALITY/KNOWN_ISSUES.md` (BUG-016/015/012/011/013/001 status verification)
- `docs/ARCHITECTURE.md` §Module Map Renderer/ block (lines 555-582), §UI Layer (line 239)
- `docs/DECISIONS.md` §D-051 (mesh-shader vertex fallback), §D-087 (DASH.7 SwiftUI port), §D-088 (DASH.7.1 brand alignment), §D-089 (DASH.7.2 dark surface), §D-096 (V.8.0-spec Arachne3D — `RayIntersector` planned consumer), §D-097 (particle siblings), §D-099 (Common.metal struct extension)
- `docs/ENGINEERING_PLAN.md` (DASH.6/7 history at §3214-3328, CA.7a closeout at §3866)

**Sibling audit:** [`docs/CAPABILITY_REGISTRY/RENDERER.md`](RENDERER.md) (CA.7a core pipeline, 23 files / 5,413 LoC, closed 2026-05-21).

## Summary

Renderer/Dashboard/ is the **DASH.7 producer side** that pairs with CA.6's view-side audit; all 8 files are production-active, the producer chain matches CA.6's 16 line-anchored DASH.7 view-side confirmations byte-for-byte, and the D-087 / D-088 / D-089 brand-and-contrast contract is honoured everywhere it shows up in the builders. Renderer/Geometry/ is the home of the D-097 particle-geometry siblings-not-subclasses architecture; all 4 files are production-active and `ProceduralGeometry` shows no parameterisation to host a non-Murmuration preset (the CLAUDE.md §What NOT To Do invariant). `MeshGenerator`'s D-051 dispatch (Apple silicon family 8+ → native mesh, M1/M2 → vertex fallback) matches the spec line-by-line — `device.supportsFamily(.apple8)` gates the branch at init and at every draw call. **The most consequential finding is in `RayTracing/`** — all 3 files (`BVHBuilder`, `RayIntersector`, `RayIntersector+Internal`) are **production-orphan**: zero production consumers across the entire `PhospheneApp/` + `PhospheneEngine/Sources/` tree; test-active via `BVHBuilderTests` + `RayIntersectorTests`; the only planned consumer is `Arachne3D` (D-096, V.8.0-spec filed 2026-05-08 + V.8.x deferred indefinitely per Matt's sequencing call). The audit recommends `keep-by-design` analogous to CA.7-FU-3's ICB resolution, registered as **CA.7b-FU-3** for Matt's keep/retire decision. **Two doc-drift items** in ARCHITECTURE.md §Module Map need correction: `DashboardTextLayer` and `DashboardCardRenderer` are still listed (lines 564 + 566) despite DASH.7 retirement (D-087). **One missing entry**: `ParticleGeometryRegistry` is absent from §Module Map Geometry/ block. **Zero broken-but-claimed; zero new BUG entries filed.**

**Verdict counts:**

| Verdict | Count | Files |
|---|---|---|
| `production-active` | 12 | 8 Dashboard + 4 Geometry |
| `production-orphan` | 3 | BVHBuilder, RayIntersector, RayIntersector+Internal |
| `broken-but-claimed` | 0 | — |
| `dead` | 0 | — |
| `documented-but-missing` | 0 | — |
| `built-but-undocumented` | 1 systemic | ARCH §Module Map (2 stale + 1 missing entry) |
| `boundary-noted` | 2 | RayTracing cluster (App ↔ Renderer = no consumer); slot-1 mesh-shader binding collision (CA.7a-scope cross-ref) |
| `boundary-deferred` | 0 | — |

**Kickoff-vs-KNOWN_ISSUES.md cross-check (Pass 0):** all six BUG citations match current status — BUG-001 / 012 / 013 / 016 are Open; BUG-011 / 015 are Resolved. No staleness Finding #1 needed.

**Follow-up backlog produced:** 3 entries — CA.7b-FU-1 ARCH stale-entry fixes (resolved in this increment), CA.7b-FU-3 RayTracing keep/retire decision (**Resolved 2026-05-21: keep, Matt product call**), CA.7b-FU-4 `setMeshPresetBuffer` cleanup (open, low-priority).

## Sub-scope decision

**Single-pass increment.** At 15 files / 2,241 LoC (1.4× CA.3 Session, 0.4× CA.7a core pipeline), CA.7b sits comfortably below the CA.7a / CA.6 / CA.5 threshold where the split-by-subdomain pattern paid off. Per-subdirectory subscopes (Dashboard / Geometry / RayTracing) flow as natural sections inside the single audit document; no operational gain from splitting into three separate audit doc files.

## Pass 0 cross-check

| Kickoff claim | KNOWN_ISSUES.md status | Match? |
|---|---|---|
| BUG-001 Open | Open (line 730-734) | ✅ |
| BUG-011 Closed against drops-only criteria | Resolved 2026-05-12 (line 180) | ✅ |
| BUG-012 Open (instrumentation in place) | Open (line 515-519) | ✅ |
| BUG-013 Open | Open (line 647-651) | ✅ |
| BUG-016 Open | Open (line 11-15) | ✅ |
| BUG-015 Resolved | Resolved 2026-05-21 (line 111-115) | ✅ |

**CA.7a follow-up status (carried per kickoff):**
- CA.7-FU-1 (mv_warp test reachability tightening): open, marginal. Out of scope for CA.7b. Untouched.
- CA.7-FU-2 (depth-debug dead-code removal): open, mechanical. Out of scope for CA.7b. Untouched.
- CA.7-FU-3 (keep ICB): Resolved same-day 2026-05-21 per `[CA.7-FU-3 + CA.7-FU-4]` commit `d48a6778`.
- CA.7-FU-4 (retire `setRayMarchPresetComputeDispatch`): Resolved same-day 2026-05-21 per commit `8ac45e73` (code removed across 4 files) + doc-update commit `d48a6778`. **Note for next CA-Renderer revisit:** this is a precedent for CA.7b-FU-3 (RayTracing) — Matt's product call resolved a structurally analogous "kept-by-design / no consumer surfaced" cluster within hours of the audit publishing.

No drift surfaced from Pass 0.

## Findings by verdict

### `production-active` (12 files)

All 12 Dashboard + Geometry files have ≥1 production consumer cited at file:line, and every documented behaviour traces to the current code. See §Per-file capability index for per-file rows.

### `production-orphan` (1 cluster, 3 files)

#### RayTracing/ cluster — BVHBuilder + RayIntersector + RayIntersector+Internal

**Files:** `Renderer/RayTracing/BVHBuilder.swift` (269 LoC), `Renderer/RayTracing/RayIntersector.swift` (378 LoC), `Renderer/RayTracing/RayIntersector+Internal.swift` (101 LoC) — total 748 LoC.

**Grep evidence (cited per CA.2-carry-forward rule):**

```bash
$ grep -rn "BVHBuilder\|RayIntersector" PhospheneApp PhospheneEngine/Sources --include="*.swift"
PhospheneEngine/Sources/Renderer/RayTracing/BVHBuilder.swift:1: …  (self)
PhospheneEngine/Sources/Renderer/RayTracing/RayIntersector.swift:1: … (self)
PhospheneEngine/Sources/Renderer/RayTracing/RayIntersector+Internal.swift:1: … (self)
PhospheneEngine/Sources/Shared/AudioFeatures+SceneUniforms.swift:9: // …documented in RayIntersector+Internal.swift.
```

Plus `Renderer/Shaders/RayTracing.metal` (the MSL counterpart, hosts `rt_nearest_hit_kernel` + `rt_shadow_kernel` — only the test path consumes them via `RayIntersector`).

**Test consumers (test-only — not production):**

```bash
$ grep -rn "BVHBuilder\|RayIntersector" PhospheneEngine/Tests --include="*.swift"
PhospheneEngine/Tests/PhospheneEngineTests/Renderer/BVHBuilderTests.swift     # 4 tests, dedicated suite
PhospheneEngine/Tests/PhospheneEngineTests/Renderer/RayIntersectorTests.swift # 4 functional + 1 perf test
```

**Indirect ray-tracing references (no live consumer):**

```bash
$ grep -rn "supportsRaytracing\|MTLAccelerationStructure" PhospheneApp PhospheneEngine/Sources --include="*.swift"
# Returns only RayTracing/ self-references.
```

**Architectural intent — planned consumer.** D-096 (V.8.0-spec Arachne3D, filed 2026-05-08) line 2571 cites `RayIntersector` as part of the toolkit for Arachne3D: *"V.2 SDF tree + V.3 material cookbook + V.7.7D §6.2 chitin inline + existing `IBLManager` / `RayIntersector` / `PostProcessChain` are the toolkit. Arachne3D is a port onto existing tech."* D-096 also references BVH refraction (Decision 3, line 2555): *"BVH refraction (C.2) explicitly deferred past V.8.7."* V.8.x is currently deferred per Matt's 2026-05-08 sequencing call (DECISIONS.md:2495 — "V.8.x ... deferred per Matt's 2026-05-08 sequencing call — simpler presets first, then return to V.8.1"). At present (2026-05-21), no V.8.x work has started; V.9 (Ferrofluid Ocean) was certified 2026-05-18 and the immediate roadmap continues into AV.2.x (Aurora Veil) per recent SR.1 / PT.1 work.

**Architectural intent — research scaffold.** The complete render-loop integration story documented in BVHBuilder.swift:42-57 + RayIntersector.swift:43-57 (BVH build encoded into the same command buffer as intersection work, no CPU stall) is unambiguous — this code was built to support per-frame audio-reactive geometry. None of the production presets currently exercises this path.

**Verdict:** `production-orphan` (test-only consumers) + `boundary-noted` at App ↔ Renderer (no consumer to defer to). Functionally analogous to CA.7a's ICB cluster (no production caller; planned-but-deferred future use; test-active so still costs `swift test` time + binary bytes; doc-cited so authors know it exists).

**Recommendation:** **CA.7b-FU-3 — keep-or-retire decision for Matt.** Same shape as CA.7-FU-3 (ICB keep, resolved 2026-05-21). Two product-level options:

- **Option A (keep, recommended):** explicitly retain as planned infrastructure for Arachne3D + future BVH refraction (V.8.7+). The cost is ongoing — ~750 LoC of compiled Swift + 5 GPU integration tests on every CI run. The benefit is that when V.8.x revives, no scaffolding cost.
- **Option B (retire):** delete all 3 Swift files + `Shaders/RayTracing.metal` + the 2 test files + the AudioFeatures+SceneUniforms comment cross-reference (`Shared/AudioFeatures+SceneUniforms.swift:9`). Net delete: ~900 LoC + 8 tests. If V.8.x ever revives, re-introduce from git history at that time (same shape as how Drift Motes' `ProceduralGeometry`-sibling code is preserved per CLAUDE.md FA #58).

**Audit author's recommendation:** Option A. The ICB precedent (CA.7-FU-3) and D-096 explicit toolkit citation are convergent signals that the code is genuinely planned, not abandoned. If V.8.x is permanently shelved (Matt's call), Option B becomes correct — but the current product trajectory still includes V.8.x ("return to V.8.1" per DECISIONS.md:2495).

## Per-file capability index

### Renderer/Dashboard/ (8 files, 766 LoC)

| File | LoC | Public surface | Verdict | Notes |
|---|---|---|---|---|
| `BeatCardBuilder.swift` | 156 | `BeatCardBuilder` (struct, Sendable) — `init()`, `build(from:width:)` | `production-active` | Consumed at `PhospheneApp/Views/Dashboard/DashboardOverlayViewModel.swift:29` (`private let beatBuilder = BeatCardBuilder()`) + `:70` (`.build(from: snapshot.beat, width: cardWidth)`). 4-row layout (MODE / BPM / BAR / BEAT), D-088 colour palette (`textBody` / `coral` / `teal` / `purple`), D-089 dark-surface contrast. BEAT phase derivation `barPhase01 × beatsPerBar − (beatInBar − 1)` matches doc-comment lines 21-26. Test suite: `BeatCardBuilderTests` (6 tests). |
| `DashboardCardLayout.swift` | 116 | `DashboardCardLayout` (struct, Sendable) — title/rows/width/padding/titleSize/rowSpacing + `Row` enum (4 variants `.singleValue` / `.bar` / `.progressBar` / `.timeseries`) + height constants (`singleHeight=39`, `barHeight=32`, `progressBarHeight=32`, `timeseriesHeight=47`, `labelToValueGap=4`) + computed `height` | `production-active` | Consumed by all three Builders (`Beat/Stems/PerfCardBuilder`) as output type; by `DashboardOverlayViewModel.swift:25` (`@Published var layouts: [DashboardCardLayout]`); by `DashboardCardView.swift:19` + `DashboardRowView.swift:25-26` (View-side renderers). |
| `DashboardFontLoader.swift` | 151 | `DashboardFontLoader` (enum) — `FontResolution` (struct, Sendable, Equatable; 5 fields) + `resolveFonts(in:)` (idempotent, OSAllocatedUnfairLock-guarded) + `resetCacheForTesting()` (test seam) | `production-active` | Consumed at `PhospheneApp/PhospheneApp.swift:44` (`_ = DashboardFontLoader.resolveFonts(in: nil)` — one-shot resolution at app launch) + `PhospheneApp/Views/Dashboard/DashboardCardView.swift:23-24` (per-view resolution via cache). Test seam used by `DashboardFontLoaderTests` (3 tests). Fonts: Epilogue-Regular + Epilogue-Medium (TTF) + ClashDisplay-Medium (OTF/TTF) registered from bundle `Fonts/` subdir, system fallbacks documented at lines 105 + 123. |
| `DashboardSnapshot.swift` | 39 | `DashboardSnapshot` (struct, Sendable, Equatable; beat/stems/perf fields) + private `bytewiseEqual<T>` helper for `BeatSyncSnapshot` + `StemFeatures` (which lack `Equatable`) | `production-active` | Produced at `PhospheneApp/VisualizerEngine+Dashboard.swift:21` (`dashboardSnapshot = DashboardSnapshot(beat:stems:perf:)`); published at `VisualizerEngine.swift:62` (`@Published var dashboardSnapshot: DashboardSnapshot?`); consumed at `PhospheneApp/Views/Dashboard/DashboardOverlayViewModel.swift:42` (`init(snapshotPublisher:)`). Per-frame contract between Renderer (writes) and App (reads via Combine). Doc-comment "Throttled there to ~30 Hz" matches `DashboardOverlayViewModel.throttleInterval = .milliseconds(33)` line 37. |
| `PerfCardBuilder.swift` | 131 | `PerfCardBuilder` (struct, Sendable) — `init()`, `build(from:width:)`, `warningRatio: Float = 0.70` (static) | `production-active` | Consumed at `PhospheneApp/Views/Dashboard/DashboardOverlayViewModel.swift:31` (`private let perfBuilder = PerfCardBuilder()`) + `:72` (`.build(from: snapshot.perf, width: cardWidth)`). Dynamic row count (1-3 rows): FRAME always present; QUALITY hides when governor is `full` + warmed up (line 92-94); ML hides on idle / dispatchNow (line 109, default branch returns nil). `warningRatio = 0.70` matches the DASH.7.1 spec (PerfCardBuilder.swift:42-44 + D-088 line 2049). Test discriminator: not currently a dedicated `PerfCardBuilderTests` suite — covered transitively by `DashboardOverlayViewModelTests` (5 tests in `PhospheneAppTests/`). |
| `PerfSnapshot.swift` | 78 | `PerfSnapshot` (struct, Sendable, Equatable; 7 fields: `recentMaxFrameMs`/`recentFramesObserved`/`targetFrameMs`/`qualityLevelRawValue`/`qualityLevelDisplayName`/`mlDecisionCode`/`mlDeferRetryMs`) + `.zero` static | `production-active` | Produced at `PhospheneApp/VisualizerEngine+Dashboard.swift:41-49` (`assemblePerfSnapshot(pipeline:)` reads `pipe.frameBudgetManager?` + `self.mlDispatchScheduler?.lastDecision`); consumed by `PerfCardBuilder.build(from:)`. Decision-encoding `Int` (0=no decision, 1=dispatchNow, 2=defer, 3=forceDispatch) matches doc-comment lines 38-43 + the switch at `VisualizerEngine+Dashboard.swift:33-40`. **Minor doc-drift in ARCH §569** (see Cross-references). |
| `StemEnergyHistory.swift` | 38 | `StemEnergyHistory` (struct, Sendable, Equatable; 4 stem arrays + `capacity: 240` static + `.empty` static) | `production-active` | Held privately by `DashboardOverlayViewModel` (`PhospheneApp/Views/Dashboard/DashboardOverlayViewModel.swift:33` `private var stemHistory = MutableStemHistory()` + `:88` `private let capacity = StemEnergyHistory.capacity`); snapshotted into immutable form at `:104-106` (`func snapshot() -> StemEnergyHistory`). 240 samples ≈ 8 s at 30 Hz redraw cadence (doc-comment line 9). |
| `StemsCardBuilder.swift` | 57 | `StemsCardBuilder` (struct, Sendable) — `init()`, `build(from:width:)` | `production-active` | Consumed at `PhospheneApp/Views/Dashboard/DashboardOverlayViewModel.swift:30` (`private let stemsBuilder = StemsCardBuilder()`) + `:71` (`.build(from: history, width: cardWidth)`). 4 `.timeseries` rows in percussion-first order (DRUMS / BASS / VOCALS / OTHER) per D-088. Range `-1.0 ... 1.0` (line 52). `valueText: ""` (sparkline IS the readout, Sakamoto-liner-note discipline per D-088). Fill colour `DashboardTokens.Color.teal` (stem indicators are MIR-data-class per D-088). Test suite: `StemsCardBuilderTests` (3 tests). |

### Renderer/Geometry/ (4 files, 727 LoC)

| File | LoC | Public surface | Verdict | Notes |
|---|---|---|---|---|
| `MeshGenerator.swift` | 283 | `MeshGeneratorConfiguration` (struct, Sendable; 4 fields with defaults `maxVerticesPerMeshlet=256`, `maxPrimitivesPerMeshlet=512`, `meshThreadCount=3`, `objectThreadCount=1`) + `MeshGenerator` (final class, @unchecked Sendable) — `configuration`/`usesMeshShaderPath`/`pipelineState`/`densityMultiplier` (var), 2 inits (library / pipelineState), `draw(encoder:features:)` + `MeshGeneratorError` enum (functionNotFound / pipelineCreationFailed) | `production-active` | Consumed at `PhospheneApp/VisualizerEngine+Presets.swift:88-99` (`case .meshShader:` constructs `MeshGeneratorConfiguration(maxVerticesPerMeshlet: 256, maxPrimitivesPerMeshlet: 512, meshThreadCount: desc.meshThreadCount)` + wraps `preset.pipelineState` via the second init + attaches via `pipeline.setMeshGenerator(gen)`). Drawn at `PhospheneEngine/Sources/Renderer/RenderPipeline+MeshDraw.swift:77` (`meshGenerator.draw(encoder: encoder, features: features)`). D-051 dispatch verified clean — see §Verification of MeshGenerator D-051 dispatch. Only mesh-shader-using preset today: **Fractal Tree** (`PhospheneEngine/Sources/Presets/Shaders/FractalTree.json:7` `"passes": ["mesh_shader"]`). Test suite: `MeshGeneratorTests` (6 tests). |
| `ParticleGeometry.swift` | 79 | `ParticleGeometry` (protocol; AnyObject + Sendable) — 3 required members: `var activeParticleFraction: Float { get set }`, `func update(features:stemFeatures:commandBuffer:)`, `func render(encoder:features:)` | `production-active` | Storage on `PhospheneEngine/Sources/Renderer/RenderPipeline.swift:31` (`var particleGeometry: (any ParticleGeometry)?`). Setter API at `RenderPipeline+PresetSwitching.swift:61` (`public func setParticleGeometry(_ geometry: (any ParticleGeometry)?)`). Threaded through `RenderPipeline+Draw.swift:26 + :280` (`particles: (any ParticleGeometry)?`) and `RenderPipeline+FeedbackDraw.swift:84`. App-layer typing matches: `VisualizerEngine.swift:190` (`var murmurationGeometry: (any ParticleGeometry)?`) + `:730` + `:754` (`resolveParticleGeometry(forPresetName:) -> (any ParticleGeometry)?`). D-097 protocol surface clean — see §Verification of D-097. |
| `ParticleGeometryRegistry.swift` | 32 | `ParticleGeometryRegistry` (enum) — `knownPresetNames: Set<String> = ["Murmuration"]` (static) | `production-active` | Consumed by `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ParticleDispatchRegistryTests.swift:38` (`#expect(ParticleGeometryRegistry.knownPresetNames.contains(name)`) + `:52` (`#expect(ParticleGeometryRegistry.knownPresetNames.contains("Murmuration"))`). The test walks the production preset catalog and asserts every preset whose `passes` contains `.particles` is listed in the registry — closes the silent-fall-through hole where a JSON-side typo in the preset name would render an audio-driven backdrop with no particles (doc-comment lines 14-18). Sole entry is `"Murmuration"`. **Built-but-undocumented**: file is missing from ARCH §Module Map (see Cross-references). |
| `ProceduralGeometry.swift` | 333 | `Particle` (struct, Sendable, @frozen; 16 Floats = 64 bytes incl. 2 pad fields) + `ParticleConfiguration` (struct, Sendable; 5 fields w/ defaults `particleCount=65_536`, `decayRate=1.8`, `burstThreshold=0.15`, `burstVelocity=3.5`, `drag=2.5`) + `ProceduralGeometry` (final class, @unchecked Sendable; conforms `ParticleGeometry`) — `particleBuffer`/`configuration`/`activeParticleFraction` public, plus `update(features:stemFeatures:commandBuffer:)` + `render(encoder:features:)` D-097 protocol members + `ProceduralGeometryError` enum (bufferAllocationFailed / functionNotFound) | `production-active` | Constructed at `PhospheneApp/VisualizerEngine.swift:731-741` (`makeMurmurationGeometry` — `particleCount: 5_000`, `decayRate: 0.0` ["birds don't die"], `burstThreshold: 0.4`, `burstVelocity: 1.0` [unused for flocking], `drag: 0.8`). Resolved at `:754-759` (`resolveParticleGeometry(forPresetName:)` switch — only `"Murmuration"` returns geometry). Attached at `VisualizerEngine+Presets.swift:296` (`pipeline.setParticleGeometry(geometry)`). D-097 verified clean — see §Verification of D-097. `Particle` struct layout (line 18-63) is 64 bytes; matches MSL `Particle` per doc-comment line 14 ("matching the MSL `Particle` struct layout (64 bytes)") + ARCH §576. Test suites: `ProceduralGeometryTests` (5 tests) + `MurmurationStemRoutingTests` (8 tests via direct `ProceduralGeometry.update()` calls). |

### Renderer/RayTracing/ (3 files, 748 LoC)

| File | LoC | Public surface | Verdict | Notes |
|---|---|---|---|---|
| `BVHBuilder.swift` | 269 | `BVHBuilderError` (enum, Error+Sendable; 5 cases) + `BVHBuilder` (final class, @unchecked Sendable) — `Triangle` (struct, Sendable; 3 SIMD3<Float> vertices), `device`/`accelerationStructure`/`triangleCount` public, `init(device:)` (requires `supportsRaytracing`), `build(triangles:)` (blocking), `rebuild(triangles:)` (alias), `encodeBuild(triangles:into:)` (non-blocking, `@discardableResult`) | `production-orphan` (test-only) + `boundary-noted` | See §RayTracing/ cluster finding. Only consumers are `BVHBuilderTests` (4 tests) + `RayIntersectorTests` (uses Triangle for fixtures). Doc-comments line 1-20 describe dynamic-geometry per-frame use; no production preset exercises it. Architectural intent: D-096 (V.8.0-spec Arachne3D, currently deferred) cites `RayIntersector` as planned toolkit at DECISIONS.md:2571. |
| `RayIntersector.swift` | 378 | `RayIntersectorError` (enum; functionNotFound / pipelineCreationFailed) + `RayIntersector` (final class, @unchecked Sendable) — `Ray` (struct, Sendable; origin/direction/minDistance/maxDistance), `Intersection` (struct, Sendable; distance/primitiveIndex/coordinates/isHit), `device` public, `init(device:library:)` (compiles `rt_nearest_hit_kernel` + `rt_shadow_kernel`), `intersect(rays:against:commandQueue:)` (blocking), `shadowRay(origin:direction:maxDistance:against:commandQueue:)` (blocking), `encodeNearestHit(rays:against:rayBuffer:hitBuffer:into:)` (non-blocking), `encodeShadow(rays:against:rayBuffer:visibilityBuffer:into:)` (non-blocking), `reflectionDirection(incident:normal:)` (static, pure CPU) | `production-orphan` (test-only) + `boundary-noted` | See §RayTracing/ cluster finding. Test consumers: 4 functional + 1 performance test in `RayIntersectorTests`. Required MSL kernels live in `Renderer/Shaders/RayTracing.metal:82` (`rt_nearest_hit_kernel`) + `:127` (`rt_shadow_kernel`). |
| `RayIntersector+Internal.swift` | 101 | `RayGPUData` (internal struct; 32 bytes / 8 Floats matching RTRay) + `NearestHitData` (internal struct; 16 bytes matching RTNearestHit) + `RayIntersector.Intersection.init(data:)` (internal extension init) + `RayIntersector` extension methods (`makeRayBuffer`/`populateRayBuffer`/`readNearestHits`/`makePipeline` — all internal) | `production-orphan` (test-only) + `boundary-noted` | Internal helpers separated from `RayIntersector.swift` per the 400-LoC file budget. No public surface; consumed only by the parent file's own methods. |

## Verification of DASH.7 producer side (CA.7b-specific)

CA.6 (`APP_VIEWS.md`) verified the View-side (`DashboardOverlayView` + `DashboardCardView` + `DashboardRowView` + `DashboardOverlayViewModel`) against D-088 + D-089 with 16 line-anchored confirmations. CA.7b closes the producer-side: each card type the View renders has a Builder in `Renderer/Dashboard/`, the Builders produce `DashboardCardLayout` values from the `DashboardSnapshot` published per-frame by `VisualizerEngine`, and the chain is byte-identical to the CA.6 confirmations.

### End-to-end producer → consumer trace

**1. Per-frame snapshot pump (Renderer → App-layer publisher):**

- `RenderPipeline` per-frame timing → `pipe.onFrameRendered` hook
- `PhospheneApp/VisualizerEngine+InitHelpers.swift:59-65` `setupDashboardSnapshotPump(pipe:)` subscribes:
  ```swift
  pipe.stemSnapshotPublisher.sink { [weak self] stems in
      self?.publishDashboardSnapshot(stems: stems)
  }
  ```
- `PhospheneApp/VisualizerEngine+Dashboard.swift:18-22`:
  ```swift
  func publishDashboardSnapshot(stems: StemFeatures) {
      let beat = beatSyncLock.withLock { latestBeatSyncSnapshot }
      let perf = assemblePerfSnapshot(pipeline: pipeline)
      dashboardSnapshot = DashboardSnapshot(beat: beat, stems: stems, perf: perf)
  }
  ```
- `PhospheneApp/VisualizerEngine.swift:62` `@Published var dashboardSnapshot: DashboardSnapshot?`

**2. PerfSnapshot assembly (FrameBudgetManager + MLDispatchScheduler → PerfSnapshot):**

`PhospheneApp/VisualizerEngine+Dashboard.swift:27-50`:

```swift
@MainActor
func assemblePerfSnapshot(pipeline pipe: RenderPipeline) -> PerfSnapshot {
    let mgr = pipe.frameBudgetManager
    let level = mgr?.currentLevel ?? .full
    let recentMs = mgr?.recentMaxFrameMs ?? 0
    let observed = mgr?.recentFramesObserved ?? 0
    let target = mgr?.configuration.targetFrameMs ?? 14
    let (mlCode, deferMs): (Int, Float) = {
        switch self.mlDispatchScheduler?.lastDecision {
        case .none:                          return (0, 0)
        case .dispatchNow:                   return (1, 0)
        case .defer(let ms):                 return (2, ms)
        case .forceDispatch:                 return (3, 0)
        }
    }()
    return PerfSnapshot(
        recentMaxFrameMs: recentMs,
        recentFramesObserved: observed,
        targetFrameMs: target,
        qualityLevelRawValue: level.rawValue,
        qualityLevelDisplayName: level.displayName,
        mlDecisionCode: mlCode,
        mlDeferRetryMs: deferMs
    )
}
```

Maps cleanly into `PerfSnapshot.swift:14-78` 7-field struct. **`PerfSnapshot.zero` default `targetFrameMs: 14` matches `assemblePerfSnapshot` fallback at line 32 — both 14 ms (Tier 1).**

**3. View-side consumption (Combine throttle → Builders → SwiftUI layouts):**

- `PhospheneApp/Views/Playback/PlaybackView.swift:80` injects `dashboardSnapshotPublisher: AnyPublisher<DashboardSnapshot?, Never>` (default `engine.$dashboardSnapshot.eraseToAnyPublisher()` per the conventional pattern).
- `PhospheneApp/Views/Dashboard/DashboardOverlayViewModel.swift:42-54` `init(snapshotPublisher:)`:
  ```swift
  snapshotPublisher
      .compactMap { $0 }
      .throttle(for: Self.throttleInterval, scheduler: DispatchQueue.main, latest: true)
      .sink { [weak self] snapshot in self?.apply(snapshot) }
      .store(in: &cancellables)
  ```
  with `static let throttleInterval: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(33)` line 37 → matches CA.6 confirmation #6 (`throttle 33ms (~30 Hz)`).
- `:65-74` `apply(_:)`:
  ```swift
  stemHistory.append(stems: snapshot.stems)
  let history = stemHistory.snapshot()
  let cardWidth: CGFloat = 280
  layouts = [
      beatBuilder.build(from: snapshot.beat, width: cardWidth),
      stemsBuilder.build(from: history, width: cardWidth),
      perfBuilder.build(from: snapshot.perf, width: cardWidth)
  ]
  ```
  — three Builders fire in BEAT / STEMS / PERF order.

**4. Stem history ring (CA.6 #8 — "240-sample stem history per stem"):**

`DashboardOverlayViewModel.swift:82-107` `MutableStemHistory`:
- 4 private `[Float]` arrays (drums/bass/vocals/other)
- `private let capacity = StemEnergyHistory.capacity` (line 88) — uses `StemEnergyHistory.capacity = 240` (StemEnergyHistory.swift:22)
- `append(stems:)` pushes `stems.drumsEnergyRel` / `.bassEnergyRel` / `.vocalsEnergyRel` / `.otherEnergyRel` (the `*EnergyRel` D-026 deviation-class fields, **not** the absolute AGC-normalised values — matches DASH.7 doc-comment line 8 in `StemEnergyHistory.swift`).
- `snapshot() -> StemEnergyHistory` (line 104-106) returns the immutable value type.

### Per-Builder D-088 / D-089 confirmation

**BeatCardBuilder (4-row layout MODE / BPM / BAR / BEAT):**

| Row | Source line | Spec | Match? |
|---|---|---|---|
| MODE: REACTIVE/UNLOCKED → `textBody` | `BeatCardBuilder.swift:83+86` | D-089 / AAA on dark (file-comment lines 73-76) | ✅ |
| MODE: LOCKING → `coral` | `:84` | D-089 promotion from `coralMuted` (file-comment lines 77-79) | ✅ |
| MODE: LOCKED → `teal` | `:85` | D-088 brand-aligned (file-comment line 76: "8.2:1 on dark, AAA") | ✅ |
| BPM no-grid → `—` + `textMuted` | `:91-98` | doc-comment lines 16-18 (stable no-grid state, no transient strings) | ✅ |
| BPM with grid → `%.0f` + `textHeading` | `:99-104` | matches | ✅ |
| BAR fill → `purple` | `:121+128` | D-089 (file-comment lines 112-115: "purpleGlow failed 3:1; full purple gives ~4.5:1") | ✅ |
| BEAT fill → `coral` | `:143+151` | D-083 (BEAT primary accent) | ✅ |
| BEAT phase derivation `barPhase01 × beatsPerBar − (beatInBar − 1)` clamped to [0,1] | `:146-149` | matches doc-comment lines 21-26 | ✅ |

**StemsCardBuilder (4 timeseries rows DRUMS / BASS / VOCALS / OTHER):**

| Aspect | Source line | Spec | Match? |
|---|---|---|---|
| Row order percussion-first | `:36-39` | doc-comment line 7 + D-088 | ✅ |
| Range `-1.0 ... 1.0` | `:52` | doc-comment line 11 | ✅ |
| `valueText: ""` (sparkline IS the readout) | `:53` | doc-comment line 53 ("sparkline is the value (D-088)") | ✅ |
| Fill colour `teal` (analytical/MIR data) | `:54` | D-088 (file-comment lines 16-18 + comment line 54) | ✅ |

**PerfCardBuilder (1-3 rows; FRAME always, QUALITY/ML conditional):**

| Row | Source line | Spec | Match? |
|---|---|---|---|
| FRAME always-present `.progressBar` | `:51 + 67-89` | DASH.7 (file-comment line 8-11) | ✅ |
| FRAME valueText `"%.1f / %.0fms"` | `:81` | DASH.7.1 compact form (file-comment line 9) | ✅ |
| FRAME status `teal` when `rawRatio < warningRatio(0.70)`, else `coral` | `:78-80` | file-comment line 10-11 ("teal healthy / coralMuted stressed") + DASH.7.2 D-089 promotion `coralMuted → coral` | ✅ |
| FRAME no-obs `textMuted + "—"` | `:74-76` | matches | ✅ |
| QUALITY hides when `recentFramesObserved > 0 && qualityLevelRawValue == 0` | `:93-95` | file-comment line 13-14 | ✅ |
| QUALITY surface colour: `textMuted` when not warmed, `coral` when downshifted | `:96-98` | DASH.7.2 D-089 (file-comment lines 26-28) | ✅ |
| ML hides on `mlDecisionCode == 0 \| 1` (idle / dispatchNow); surfaces on `2` (defer → "WAIT") / `3` (forceDispatch → "FORCED") | `:107-127` | file-comment lines 15-18 | ✅ |

**Card width 280 pt:** all three Builders default `width: CGFloat = 280` and `DashboardOverlayViewModel.apply(_:)` passes `cardWidth: CGFloat = 280`. ARCH §239 + CA.6 #5 say the dashboard panel itself is 320 pt wide; the 280 pt cards sit inside the 320 pt panel chrome — consistent.

**Throttle = 33 ms (~30 Hz):** confirmed at `DashboardOverlayViewModel.swift:37` matches `DashboardSnapshot.swift:5` doc-comment ("Throttled there to ~30 Hz") + CA.6 #6.

**`ingestForTest(_:)` test seam:** `DashboardOverlayViewModel.swift:59-61` — matches CA.6 #7. Used by `PhospheneAppTests/DashboardOverlayViewModelTests.swift` (5 tests).

**Verdict:** DASH.7 producer-side **clean against D-087 / D-088 / D-089 + CA.6's 16 line-anchored confirmations**. No drift.

## Verification of D-097 particle-geometry siblings-not-subclasses (CA.7b-specific)

D-097 is the load-bearing architectural rule: particle presets are siblings, not subclasses. Each particle preset owns its own compute+render pipelines via the `ParticleGeometry` protocol; future presets ship sibling conformers rather than parameterising `ProceduralGeometry`. CLAUDE.md §What NOT To Do enforces the operational invariant ("Do not parameterize `ProceduralGeometry` to host a non-Murmuration particle preset's behavior").

### Protocol surface (D-097 spec)

`Renderer/Geometry/ParticleGeometry.swift:33-79`:

```swift
public protocol ParticleGeometry: AnyObject, Sendable {
    var activeParticleFraction: Float { get set }
    func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer)
    func render(encoder: MTLRenderCommandEncoder, features: FeatureVector)
}
```

| Spec aspect (D-097 + kickoff) | Code | Match? |
|---|---|---|
| 3 required members | `activeParticleFraction` (var) + `update(...)` + `render(...)` | ✅ |
| AnyObject + Sendable | `: AnyObject, Sendable` line 33 | ✅ |
| `RenderPipeline.particleGeometry` typed as `(any ParticleGeometry)?` | `RenderPipeline.swift:31` (`var particleGeometry: (any ParticleGeometry)?`) | ✅ |
| `setParticleGeometry(_:)` API typed identically | `RenderPipeline+PresetSwitching.swift:61` (`public func setParticleGeometry(_ geometry: (any ParticleGeometry)?)`) | ✅ |
| App-layer storage matches | `VisualizerEngine.swift:190` (`var murmurationGeometry: (any ParticleGeometry)?`) + `:730` (`-> (any ParticleGeometry)?`) | ✅ |
| `activeParticleFraction` doc-comment cites D-057 governor gate | `ParticleGeometry.swift:36-42` | ✅ |
| Warmup-window blend `smoothstep(0.02, 0.06, totalStemEnergy)` per D-019 | doc-comment `ParticleGeometry.swift:55-56` | ✅ |

### ProceduralGeometry conformance — no parameterisation

`Renderer/Geometry/ProceduralGeometry.swift`:

- `final class ProceduralGeometry: ParticleGeometry, @unchecked Sendable` (line 132)
- `var activeParticleFraction: Float = 1.0` (line 149) — protocol conformance
- `func update(features:stemFeatures:commandBuffer:)` (line 256-299) — protocol conformance
- `func render(encoder:features:)` (line 312-323) — protocol conformance

**Parameterisation check (the CLAUDE.md ban):**

```bash
$ grep -nE "presetName|presetKind|kernelName|kernelOverride|computeKernelName|fragmentName|vertexFunction.*[^=]$|let kernel|preset:.*String" PhospheneEngine/Sources/Renderer/Geometry/ProceduralGeometry.swift
```

Returns no parameterisation hits. The compute kernel name `"particle_update"` is hardcoded at line 212; the render functions `"particle_vertex"` + `"particle_fragment"` are hardcoded at line 219-220. `ParticleConfiguration` exposes 5 tunables (`particleCount` / `decayRate` / `burstThreshold` / `burstVelocity` / `drag`) — all are numerical knobs within Murmuration's design space, not preset-name-dependent or pluggable-kernel overrides.

The conformance is satisfied by `activeParticleFraction` (Frame Budget Governor section), `update(...)` (Update section), and `render(...)` (Render section); existing MARK groupings stay lifecycle-organized rather than being collapsed under a single header (doc-comment at line 120-124). ✅ matches D-097 spec.

### ParticleGeometryRegistry catalog gate

`Renderer/Geometry/ParticleGeometryRegistry.swift:24-32`:

```swift
public enum ParticleGeometryRegistry {
    public static let knownPresetNames: Set<String> = [
        "Murmuration"
    ]
}
```

Sole entry is `"Murmuration"` (post-Drift Motes retirement at D-102, 2026-05-11). The comment at line 28-29 explicitly notes "Murmuration" is a literal because `ProceduralGeometry` is part of DM.0's frozen surface (D-097) — matches the architecture.

**Catalog gate test:** `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ParticleDispatchRegistryTests.swift`:

```swift
@Test("every .particles-pass preset is registered in ParticleGeometryRegistry")
func everyParticlesPassPresetIsRegistered() throws {
    for descriptor in loadAllPresetDescriptors() where descriptor.passes.contains(.particles) {
        #expect(ParticleGeometryRegistry.knownPresetNames.contains(descriptor.name), …)
    }
}
@Test func murmurationIsRegistered() {
    #expect(ParticleGeometryRegistry.knownPresetNames.contains("Murmuration"))
}
```

The test closes the silent-fall-through hole where a JSON-side typo in the preset name (e.g. `"Mumuration"`) would render an audio-driven backdrop with no particles. ✅ load-bearing gate working.

### Verdict

**D-097 particle-geometry siblings architecture verified clean.** Protocol surface matches spec; `ProceduralGeometry` conforms without parameterisation (CLAUDE.md §What NOT To Do invariant respected); `ParticleGeometryRegistry` carries only the sole post-Drift-Motes entry; the catalog gate test exists and runs. No drift.

## Verification of MeshGenerator D-051 dispatch (CA.7b-specific)

D-051 specifies: M3+ (Apple silicon family 8+) uses native mesh shader dispatch via `MTLMeshRenderPipelineDescriptor`; M1/M2 (pre-apple8) uses a vertex-shader fallback with the same `MTLRenderPipelineState` surface. Presets never branch on hardware tier.

### Branch logic (`MeshGenerator.swift`)

**Init paths (both compile via the gate):**

- Library-based init (line 122-145): `let supportsMesh = device.supportsFamily(.apple8)` (line 131) → `self.usesMeshShaderPath = supportsMesh` (line 132) → if true: `compileMeshPipeline` (line 135); else: `compileFallbackPipeline` (line 140). Logger at lines 138 + 143 reports the chosen path.
- Pre-compiled init (line 161-171; the path `VisualizerEngine+Presets.swift:94-99` uses): `self.usesMeshShaderPath = device.supportsFamily(.apple8)` (line 168). Logger at line 170.

**Pipeline compilation:**

- `compileMeshPipeline` (line 229-251): builds `MTLMeshRenderPipelineDescriptor` with `objectFunction = "mesh_object_shader"` (optional, line 241) + `meshFunction = "mesh_shader"` (line 234) + `fragmentFunction = "mesh_fragment"` (line 237).
- `compileFallbackPipeline` (line 254-272): builds standard `MTLRenderPipelineDescriptor` with `vertexFunction = "mesh_fallback_vertex"` (line 259) + `fragmentFunction = "mesh_fragment"` (line 262).

Both produce the same return type `MTLRenderPipelineState` — preset shaders see no API surface difference.

**Draw dispatch:**

`MeshGenerator.draw(encoder:features:)` lines 192-224:

| Branch | Code | Spec |
|---|---|---|
| `usesMeshShaderPath == true` | `drawMeshThreadgroups(MTLSize(1,1,1), threadsPerObjectThreadgroup: MTLSize(width: configuration.objectThreadCount), threadsPerMeshThreadgroup: MTLSize(width: configuration.meshThreadCount))` (line 211-219) | Native mesh dispatch (D-051) |
| `usesMeshShaderPath == false` | `drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)` (line 222) | Fullscreen triangle fallback |

### Buffer slot bindings (CA.7a slot-4 reuse note + slot 0 / slot 1)

**Slot 0 (FeatureVector):** bound to all stages on the mesh path; only fragment stage on the fallback path:

- Mesh path: `setObjectBytes(&feat, ..., index: 0)` (line 199) + `setMeshBytes(&feat, ..., index: 0)` (line 200) + `setFragmentBytes(&feat, ..., index: 0)` (line 207)
- Fallback path: only `setFragmentBytes(&feat, ..., index: 0)` (line 207) fires (object/mesh setters are inside the `if usesMeshShaderPath` block at line 196-206)

**Slot 1 (governor `densityMultiplier`, D-057, Apple8+ only):**

- Mesh path: `setObjectBytes(&density, length: MemoryLayout<Float>.stride, index: 1)` (line 204) + `setMeshBytes(&density, length: MemoryLayout<Float>.stride, index: 1)` (line 205)
- Fallback path: documented no-op per `densityMultiplier` doc-comment lines 99-101 (M1/M2 fullscreen-triangle vertex count is fixed; the flag has no opt-in mechanism on the vertex path).

**Slot 4 mesh-shader path reuse (CA.7a-added ARCH note):**

CA.7a's audit added a note to ARCH §GPU Contract Details that the mesh-shader fragment path binds `meshPresetFragmentBuffer` at fragment slot 4 (mutually exclusive with ray-march's SceneUniforms at slot 4). The binding code lives in `Renderer/RenderPipeline+MeshDraw.swift:72-74`:

```swift
if let fragBuf = meshPresetFragmentBufferLock.withLock({ meshPresetFragmentBuffer }) {
    encoder.setFragmentBuffer(fragBuf, offset: 0, index: 4)
}
```

`MeshGenerator.draw()` does NOT touch fragment slot 4 — confirmed by inspection of lines 192-224 (only `setFragmentBytes(..., index: 0)` at line 207 fires on the fragment stage). Contract is honoured: ray-march's SceneUniforms at slot 4 and mesh-shader's `meshPresetFragmentBuffer` at slot 4 are mutually exclusive (different presets, different render paths, never simultaneously).

### Live mesh-shader preset

Only one preset declares the mesh-shader pass:

```bash
$ find PhospheneEngine/Sources/Presets -name "*.json" -exec grep -l '"passes".*"mesh_shader"' {} \;
PhospheneEngine/Sources/Presets/Shaders/FractalTree.json
```

`FractalTree.json:7` `"passes": ["mesh_shader"]` + `:13` `"mesh_thread_count": 64` + `:8` `"vertex_function": "fractal_tree_fallback_vertex"` (vertex fallback function for M1/M2). The preset's MSL shader is at `Renderer/Shaders/FractalTree.metal` (out of CA.7b scope; CA-Presets territory).

### Verdict

**MeshGenerator D-051 dispatch verified clean.** The Apple silicon family 8 gate at init + the dispatch branch at every draw call match the spec. Buffer-slot bindings (slot 0 FeatureVector, slot 1 densityMultiplier on apple8+, slot 4 fragment-stage `meshPresetFragmentBuffer` — managed by RenderPipeline+MeshDraw not MeshGenerator) honour the contract documented in CA.7a's ARCH extension. No drift.

### Cross-reference finding (CA.7a-scope, surfaced from CA.7b inspection)

While verifying the slot-1 binding on the mesh-shader path, the audit noticed that `Renderer/RenderPipeline+MeshDraw.swift:65-67` binds `meshPresetBuffer` to **object/mesh slot 1** if non-nil:

```swift
if let presetBuf = meshPresetBufferLock.withLock({ meshPresetBuffer }) {
    encoder.setObjectBuffer(presetBuf, offset: 0, index: 1)
    encoder.setMeshBuffer(presetBuf, offset: 0, index: 1)
}
```

And `MeshGenerator.draw()` at line 204-205 binds `densityMultiplier` to **object/mesh slot 1**:

```swift
encoder.setObjectBytes(&density, length: MemoryLayout<Float>.stride, index: 1)
encoder.setMeshBytes(&density, length: MemoryLayout<Float>.stride, index: 1)
```

Dispatch order: RenderPipeline+MeshDraw line 66-67 binds first (preset buffer), then `meshGenerator.draw()` (line 77) is called which **overwrites slot 1 with `densityMultiplier`** (last write wins).

**Today this is a latent issue, not a live bug:** `setMeshPresetBuffer(_:)` has zero non-nil production callers — the only call site in the entire `PhospheneApp/` + `PhospheneEngine/Sources/` tree is `VisualizerEngine+Presets.swift:55` (`pipeline.setMeshPresetBuffer(nil)` — the reset). So `meshPresetBuffer` is always nil, the slot-1 collision never manifests, FractalTree (the only mesh-shader preset) doesn't use `meshPresetBuffer`, and there's no symptomatic bug. But if a future mesh-shader preset DID set the buffer non-nil expecting to use it from MSL object/mesh shaders, `densityMultiplier` would silently clobber it.

This finding lives in CA.7a-scope files (`RenderPipeline+MeshDraw.swift` + `RenderPipeline+PresetSwitching.swift`'s `setMeshPresetBuffer`/`setMeshPresetFragmentBuffer` setters). CA.7a audited them as `production-active` without flagging this. Surface as `boundary-noted` cross-reference; register **CA.7b-FU-4** for either (a) renaming `setMeshPresetBuffer` to bind a different slot, (b) deprecating + removing the setters since they have zero non-nil callers (similar to CA.7-FU-4 `setRayMarchPresetComputeDispatch` retirement precedent), or (c) leaving the latent collision documented with a `// TODO: slot-1 collision with densityMultiplier` comment if Matt decides the API surface should stay for a future caller.

## Verification of RayTracing/ consumer surface (CA.7b-specific)

**The single most important verification of CA.7b** — kickoff question: which preset (if any) in `Sources/Presets/` consumes `BVHBuilder` + `RayIntersector`?

### Cited grep commands and results

```bash
# All production-tree usages
$ grep -rn "BVHBuilder\|RayIntersector" PhospheneApp PhospheneEngine/Sources --include="*.swift"
PhospheneEngine/Sources/Renderer/RayTracing/BVHBuilder.swift                  # 17 self-references
PhospheneEngine/Sources/Renderer/RayTracing/RayIntersector.swift              # 19 self-references
PhospheneEngine/Sources/Renderer/RayTracing/RayIntersector+Internal.swift     # 4 self-references
PhospheneEngine/Sources/Shared/AudioFeatures+SceneUniforms.swift:9            # documentation comment only
# Zero PhospheneApp/ hits.
# Zero PhospheneEngine/Sources/Presets/ hits.
# Zero PhospheneEngine/Sources/Renderer/ hits outside RayTracing/ self-references.

# Indirect ray-tracing API usage (in case RayTracing types are wrapped)
$ grep -rn "supportsRaytracing\|MTLAccelerationStructure\|primitive_acceleration_structure" PhospheneApp PhospheneEngine/Sources --include="*.swift"
# Returns only Renderer/RayTracing/BVHBuilder.swift self-references.

# MSL counterpart consumers
$ grep -rn "rt_nearest_hit_kernel\|rt_shadow_kernel" PhospheneApp PhospheneEngine/Sources --include="*.swift"
# Returns only Renderer/RayTracing/RayIntersector.swift (the Swift-side init that compiles the kernels).
$ grep -rn "rt_nearest_hit_kernel\|rt_shadow_kernel" PhospheneEngine/Sources/Renderer/Shaders --include="*.metal"
PhospheneEngine/Sources/Renderer/Shaders/RayTracing.metal:82  kernel void rt_nearest_hit_kernel(
PhospheneEngine/Sources/Renderer/Shaders/RayTracing.metal:127 kernel void rt_shadow_kernel(
# No other .metal file imports or invokes these kernels.

# Test consumers (test-only — not production)
$ grep -rn "BVHBuilder\|RayIntersector" PhospheneEngine/Tests --include="*.swift"
PhospheneEngine/Tests/PhospheneEngineTests/Renderer/BVHBuilderTests.swift     # 4 tests
PhospheneEngine/Tests/PhospheneEngineTests/Renderer/RayIntersectorTests.swift # 4 functional + 1 perf test
```

### Result

**Zero production consumers across PhospheneApp/ + PhospheneEngine/Sources/.** The only non-self reference is a pure documentation cross-reference at `Sources/Shared/AudioFeatures+SceneUniforms.swift:9` (commenting on packed_float3 vs SIMD3<Float> alignment — references `RayIntersector+Internal.swift` because that file documents the same alignment trick).

### Architectural intent verification

**D-096 V.8.0-spec Arachne3D (filed 2026-05-08)** explicitly cites `RayIntersector` as part of the future toolkit (DECISIONS.md:2571):

> No new external dependencies, no new pass types, no new SDF utilities, no new material recipes. V.2 SDF tree + V.3 material cookbook + V.7.7D §6.2 chitin inline + existing `IBLManager` / `RayIntersector` / `PostProcessChain` are the toolkit. Arachne3D is a port onto existing tech.

D-096 also references BVH refraction explicitly deferred (DECISIONS.md:2555):

> BVH refraction (C.2) explicitly deferred past V.8.7.

**V.8.x status:** deferred per Matt's 2026-05-08 sequencing call (DECISIONS.md:2495):

> V.8.x (Arachne3D parallel preset, D-096) deferred per Matt's 2026-05-08 sequencing call — simpler presets first, then return to V.8.1.

V.8.1 increment is filed in ENGINEERING_PLAN.md:1723 with status "not started" — nothing landed against V.8.x in the 13 days since D-096 was filed. ENGINEERING_PLAN.md:24 lists "hardware ray tracing" as a Phase 3 technology marker.

### Architectural intent confidence

The full BVH-build-and-intersection-in-the-same-command-buffer dynamic-geometry story is documented in detail (BVHBuilder.swift:42-57 + RayIntersector.swift:43-57). This is not vestigial Apple-sample-app boilerplate — it's deliberately-built infrastructure for per-frame audio-reactive geometry, exactly the pattern Arachne3D would need at V.8.7 (BVH refraction). The grep result + D-096 toolkit citation + V.8.x deferral state are convergent: the cluster is planned-but-not-yet-started, **not** retired-but-not-removed.

### Verdict

**`production-orphan` (test-only consumers) + `boundary-noted` (no consumer to defer to).** Structurally analogous to CA.7a's ICB cluster:

| Property | ICB (CA.7-FU-3) | RayTracing (CA.7b-FU-3) |
|---|---|---|
| Production callers of public setter | 0 non-nil | 0 (no setter; planned consumer would use directly via injection) |
| Test consumers | `RenderPipelineICBTests` | `BVHBuilderTests` + `RayIntersectorTests` |
| Documented planned consumer | `VisualizerEngine+Presets.swift:305` comment ("ICB preset switching deferred to the Orchestrator increment") | D-096 toolkit citation (DECISIONS.md:2571) |
| Matt's resolution | Keep (CA.7-FU-3, 2026-05-21) | **TBD — CA.7b-FU-3** |

**Recommendation: Option A keep-by-design.** ICB precedent points toward keep; D-096's explicit toolkit citation is a stronger signal than CA.7a's ICB inline-comment citation; V.8.x deferral is "later," not "never" (DECISIONS.md:2495 phrasing). If V.8.x is permanently shelved, Option B retire becomes correct (~900 LoC + 8 tests to remove); the audit author cannot make that product call.

## Cross-references

### Updates needed in CLAUDE.md

**None.** The CLAUDE.md §What NOT To Do entry for D-097 (`Do not parameterize ProceduralGeometry to host a non-Murmuration particle preset's behavior`) matches the verified code. No CLAUDE.md drift surfaced.

### Updates needed in ARCHITECTURE.md

**§Module Map Renderer/ block needs 3 corrections (applied in this increment per the CA.7a precedent):**

1. **Line 564 — Delete `Dashboard/DashboardTextLayer` entry.** File was retired in DASH.7 (D-087) per ENGINEERING_PLAN.md:3274: *"DASH.7 ports the dashboard to SwiftUI, retiring `DashboardComposer` + `DashboardCardRenderer` + `DashboardTextLayer` + `Dashboard.metal`."* `find` confirms the file no longer exists.

2. **Line 566 — Delete `Dashboard/DashboardCardRenderer` entry.** Same DASH.7 retirement (D-087). `find` confirms the file no longer exists.

3. **Insert `Geometry/ParticleGeometryRegistry` entry** (after the `Geometry/MeshGenerator` line at 560). Currently undocumented; load-bearing for catalog correctness (`ParticleDispatchRegistryTests`) and serves as the D-097 catalog mirror of `VisualizerEngine.resolveParticleGeometry`.

**§Module Map Renderer/Dashboard/PerfSnapshot drift (line 569):** entry currently states `MLDispatchScheduler.lastDecision / forceDispatchCount` — but `PerfSnapshot.swift` has no `forceDispatchCount` field. Decision encoding is `mlDecisionCode: Int` + `mlDeferRetryMs: Float` (PerfSnapshot.swift:43-47). Updated in this increment.

**§Renderer (lines 134-184, CA.7a-extended) doesn't need further changes** — the CA.7a slot-4 mesh-shader path reuse note + slot 12 + slot 13+ extensions are correct and confirmed by CA.7b reading of MeshGenerator + RenderPipeline+MeshDraw.

### Updates needed in ENGINEERING_PLAN.md

Add a CA.7b row + flip the kickoff status from "open" to "✅ landed" per the standard increment-closeout pattern.

### Updates needed in DECISIONS.md

**None.** D-051 (mesh-shader vertex fallback), D-088 / D-089 (DASH.7 brand + dark surface), D-097 (particle siblings), D-096 (V.8.0-spec / RayIntersector planned consumer) all match the code. No drift.

### Updates needed in CLAUDE.md "What NOT To Do"

**None.** The D-097 ban is currently honoured.

### New BUG entries

**Zero.** The RayTracing production-orphan cluster is `boundary-noted` per CA.7-FU-3 precedent; it's not a runtime defect. The slot-1 collision is latent (no caller); it's filed as CA.7b-FU-4, not a BUG.

### KNOWN_ISSUES.md sweep

**None.** No CA.7b-internal flakes; no Renderer-supporting-class regressions.

## Follow-up Backlog

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.7b-FU-1** | ARCH §Module Map Dashboard drift (DashboardTextLayer + DashboardCardRenderer + PerfSnapshot drift) + Geometry insert (ParticleGeometryRegistry) | All three lines reflect current code state; `find` shows zero stale-file mentions; ParticleGeometryRegistry has a one-line entry. | 0 (landing in this increment's doc-fix commit) | Resolved 2026-05-21 (this increment) |
| **CA.7b-FU-2** | (consolidated into CA.7b-FU-1) | — | — | Folded into CA.7b-FU-1 |
| **CA.7b-FU-3** | **RayTracing keep-or-retire decision.** Same shape as CA.7-FU-3 (ICB keep). | — | — | **Resolved 2026-05-21 (keep).** Matt's product call: keep. RayTracing infrastructure (`BVHBuilder.swift`, `RayIntersector.swift`, `RayIntersector+Internal.swift`, `Shaders/RayTracing.metal`, the 2 test suites) stays in place. Rationale per Matt: *"it will be used eventually by presets we haven't created yet"* — D-096 Arachne3D toolkit citation + V.8.7+ BVH refraction are documented planned consumers, plus other future ray-tracing-using presets not yet specced. Registry-only resolution; no code change. ARCH §Module Map lines 561-562 already extended in this increment with production-orphan + planned-consumer notes. |
| **CA.7b-FU-4** | **`setMeshPresetBuffer` / `setMeshPresetFragmentBuffer` non-nil consumer audit + slot-1 collision resolution.** CA.7a-scope files (`RenderPipeline+PresetSwitching.swift` setters + `RenderPipeline+MeshDraw.swift` consumers). `setMeshPresetBuffer(_:)` has zero non-nil production callers; the slot-1 binding at lines 66-67 would be silently overwritten by `MeshGenerator.draw()`'s `densityMultiplier` write at line 204-205 if a future caller appeared. Three resolution options: (a) rebind preset buffer to a different object/mesh slot (e.g. slot 2), (b) deprecate + remove the setter pair (`setMeshPresetBuffer` has no non-nil callers; `setMeshPresetFragmentBuffer`'s slot-4 binding doesn't collide), (c) document the latent collision with a `// TODO:` comment. Audit-author recommendation: option (b) — deprecate + remove (precedent: CA.7-FU-4 `setRayMarchPresetComputeDispatch` retirement). | Matt's call on (a/b/c); corresponding commit. | 1 session (decision + commit + 4 file edits if option b) | Open — low-priority cleanup; latent only |

## Approach validation

The audit format continues to produce actionable findings at this scale. Three observations for the next CA-Audio / CA-Presets iteration:

1. **Direct-read scaled cleanly at 2.2k LoC.** All 15 files read directly without Explore agents. The visibility-grep verification step adds value mostly when agents abstract symbols away from the reader — at direct-read scale you have file:line in hand for every symbol claim, so the grep verification is precautionary rather than load-bearing. For CA-Audio (likely smaller than CA.7b), direct-read is recommended again. For CA-Presets (likely larger), an Explore-agent split per preset family will be needed.

2. **The "is there a non-nil caller?" production-orphan check at setter granularity is a new pattern.** CA.7a verified `setMeshGenerator` / `setParticleGeometry` / `setMeshGBufferEncoder` etc. as production-active because the setters had non-nil call sites somewhere. CA.7b's slot-1 collision discovery happened because the audit grepped for non-nil call sites specifically — and `setMeshPresetBuffer`'s only call site is `pipeline.setMeshPresetBuffer(nil)` (the reset). This is a finer-grained check than CA.7a applied. Recommend adopting this pattern in CA-Audio / CA-Presets: for any setter API, grep for non-nil callers, not just `setX\(` callers; a setter with only nil-reset callers is a production-orphan API surface even if it appears `production-active` at the file level.

3. **Doc-drift in ARCH §Module Map is a recurring systemic finding.** CA.5 + CA.6 + CA.7a + CA.7b all surfaced one or more ARCH §Module Map drift items (stale-file entries / missing-file entries / typo'd field references). This is now 4-in-a-row. Suggest the next App-adjacent or doc-pruning increment audits the entire ARCH §Module Map cohesively against `find PhospheneEngine/Sources -name "*.swift"` + `find PhospheneApp -name "*.swift"` and fixes drift in one bulk pass rather than continuing to find one or two items per CA increment.

The format **does not need redesign** for CA-Audio / CA-Presets. Per-Builder verification tables (used in §DASH.7 producer-side) are a useful pattern when a section has many small contracts to verify; carry forward where applicable.

---

*Audit complete 2026-05-21.*

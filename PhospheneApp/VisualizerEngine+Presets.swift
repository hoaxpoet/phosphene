// VisualizerEngine+Presets — Preset switching and render-path configuration.
// swiftlint:disable file_length

import Combine
import CoreGraphics
import Foundation
import Metal
import os.log
import Orchestrator
import Presets
import Renderer
import Shared

private let logger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

/// Map a `marks.primitive` descriptor string to an `MTLPrimitiveType` (Skein.ENGINE.1.1,
/// D-143). The descriptor lives in the Presets module, which does not import Metal, so it
/// stores the primitive as a string; the mapping lives here in the app (Metal-importing)
/// layer. Unknown values default to `.triangle` with a logged error.
private func mvWarpMarksPrimitive(_ name: String, presetName: String) -> MTLPrimitiveType {
    switch name {
    case "point":          return .point
    case "line":           return .line
    case "line_strip":     return .lineStrip
    case "triangle":       return .triangle
    case "triangle_strip": return .triangleStrip
    default:
        logger.error("mv_warp preset '\(presetName)' has unknown marks.primitive '\(name)' — defaulting to .triangle")
        return .triangle
    }
}

extension VisualizerEngine {

    // MARK: - Preset Cycling

    /// Advance to the next preset and update the pipeline.
    func nextPreset() {
        guard let preset = presetLoader.nextPreset() else { return }
        // LFPLAN.3: manual cycle holds the plan until the next track.
        orchestratorLock.withLock { manualPresetOverrideThisTrack = true }
        applyPreset(preset)
        showPresetName(preset.descriptor.name)
    }

    /// Go back to the previous preset and update the pipeline.
    func previousPreset() {
        guard let preset = presetLoader.previousPreset() else { return }
        // LFPLAN.3: manual cycle holds the plan until the next track.
        orchestratorLock.withLock { manualPresetOverrideThisTrack = true }
        applyPreset(preset)
        showPresetName(preset.descriptor.name)
    }

    /// Per-track deterministic seed for `SkeinState` (Skein.3 §5.7 — same track → same
    /// painting). Reuses the shared FNV-1a `title|artist` hash (the LumenPatternEngine seed
    /// precedent), truncated to the 32-bit seed SkeinState perturbs its trajectory with.
    /// Returns 0 before any track resolves (a fixed, still-deterministic default).
    func currentSkeinSeed() -> UInt32 {
        guard let identity = lastResolvedTrackIdentity else { return 0 }
        return UInt32(truncatingIfNeeded: Self.lumenTrackSeedHash(for: identity))
    }

    /// BUG-044: per-track preset-state reset shared by BOTH track-change paths — the streaming
    /// metadata callback (`VisualizerEngine+Capture`) AND the local-file queue advance
    /// (`advanceLocalFileQueue` — next / prev / natural EOF). Any preset whose per-track state
    /// lives outside `resetStemPipeline` resets HERE, or it silently survives track changes on
    /// whichever path forgets it (the BUG-024 complementary-path class — the Skein §1.5 canvas
    /// wipe was wired only on the streaming path for 5 days before a local-file listen caught it).
    ///
    /// PRECONDITION: `lastResolvedTrackIdentity` must already hold the NEW track's identity —
    /// `currentSkeinSeed()` derives the reseed from it (call after `applyLocalFileTrackState`
    /// on the LF path).
    func resetPerTrackPresetState() {
        // NB.4: settle Nimbus into the new track. Zeroing the bloom follower shrinks/dims the
        // body to its floor and the flow phase re-seeds; the dim settle-in masks the gas re-seed
        // so the body blooms back UP into the new track rather than popping (DESIGN §1.5).
        // No-op when Nimbus is not the active preset (state is nil).
        nimbusState?.reset()
        // Skein.3 (§1.5): a new track paints its OWN canvas (the held painting is the previous
        // track's visual fingerprint). Wipe the canvas back to the ground and re-seed the painter
        // from the new track's identity (same track → same painting, §5.7). No-op when Skein
        // is not the active preset (skeinState is nil → the canvas clear is skipped too).
        if skeinState != nil {
            skeinState?.reseed(currentSkeinSeed())
            // Skein.5.3b: the new track's palette carries its GROUND (light or dark) — push it
            // as the canvas-ground override BEFORE the wipe so the fresh canvas clears to the
            // new palette's ground, and any mid-track resize re-clears to the same. LINEAR
            // (Metal encodes on store for the sRGB canvas).
            if let skeinGround = skeinState?.groundLinear {
                pipeline.setMVWarpCanvasGround(SIMD4<Double>(
                    Double(skeinGround.x), Double(skeinGround.y), Double(skeinGround.z), 1.0))
            }
            pipeline.clearMVWarpCanvasToGround()
        }
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    // applyPreset iterates the passes array with one case per capability type.
    // The switch is the whole point — extracting cases would obscure the configuration
    // logic. The disable is narrowly scoped to this function.

    /// Apply a preset to the render pipeline by iterating its declared render passes.
    ///
    /// Each pass in `preset.descriptor.passes` configures the corresponding subsystem.
    /// All subsystems are reset before the new preset is applied, so stale state from
    /// a previous preset cannot leak through.
    func applyPreset(_ preset: PresetLoader.LoadedPreset) {
        let desc = preset.descriptor

        // Reset frame-budget governor to .full on each preset change — new presets have
        // unknown cost characteristics; start optimistic and let the controller re-converge.
        pipeline.frameBudgetManager?.reset()

        // Reset all active passes and subsystems before applying the new preset.
        // This prevents stale subsystem state from the previous preset bleeding through.
        pipeline.setActivePasses([])
        pipeline.setMeshGenerator(nil)
        pipeline.setMeshPresetTick(nil)
        pipeline.setMVWarpWetnessDecay(1.0)   // Skein.ENGINE.2: reset to "held" (only Skein decays A)
        pipeline.setStructuralPrediction(.none)   // Skein.ENGINE.3 (D-151): reset to inert default on preset switch
        pipeline.setMVWarpCanvasGround(nil)   // Skein.5.3b: drop the per-track ground override (only Skein sets it)
        arachneState = nil
        gossamerState = nil
        auroraVeilState = nil
        nimbusState = nil
        skeinState = nil
        lumenPatternEngine = nil
        ferrofluidParticles = nil
        ferrofluidMesh = nil
        spectralCartographOverlay = nil
        pipeline.setDynamicTextOverlay(nil)
        pipeline.setTextOverlayCallback(nil)
        pipeline.setDirectPresetFragmentBuffer(nil)
        pipeline.setDirectPresetFragmentBuffer2(nil)
        pipeline.setDirectPresetFragmentBuffer3(nil)
        pipeline.setDirectRenderScale(1.0)   // NB.8: full-res unless a preset opts into half-res below
        pipeline.setRayMarchPresetHeightTexture(nil)
        pipeline.setMeshGBufferEncoder(nil)
        pipeline.setPostProcessChain(nil)
        pipeline.setRayMarchPipeline(nil)
        pipeline.setFeedbackParams(nil)
        pipeline.setFeedbackComposePipeline(nil)
        pipeline.setParticleGeometry(nil)
        pipeline.clearMVWarpState()
        pipeline.setStagedRuntime(nil, drawableSize: pipeline.mvWarpDrawableSize)
        currentRayMarchPipeline = nil

        // Set the primary pipeline state (overridden for ray march below).
        pipeline.setActivePipelineState(preset.pipelineState)

        // Configure each declared pass.
        for pass in desc.passes {
            switch pass {

            case .meshShader:
                let config = MeshGeneratorConfiguration(
                    maxVerticesPerMeshlet: 256,
                    maxPrimitivesPerMeshlet: 512,
                    meshThreadCount: desc.meshThreadCount
                )
                let gen = MeshGenerator(
                    device: context.device,
                    pipelineState: preset.pipelineState,
                    configuration: config
                )
                pipeline.setMeshGenerator(gen)

            case .postProcess:
                do {
                    // `try?` here discarded the PostProcessError; surface it (parity with
                    // the rayMarch path below) so a sampler/shader-function failure is
                    // diagnosable. Fallback: chain stays nil (set above), so the preset
                    // renders its base pass without post-processing — degraded, not black.
                    let chain = try PostProcessChain(context: context, shaderLibrary: shaderLibrary)
                    pipeline.setPostProcessChain(chain)
                } catch {
                    logger.error("Failed to create PostProcessChain for preset '\(desc.name)': \(error)")
                }

            case .rayMarch:
                guard let rmPipelineState = preset.rayMarchPipelineState else {
                    logger.error("Ray march preset '\(desc.name)' missing compiled G-buffer state")
                    break
                }
                do {
                    let rmPipeline = try RayMarchPipeline(context: context, shaderLibrary: shaderLibrary)
                    // Ray march presets use the G-buffer state, not the standard placeholder.
                    pipeline.setActivePipelineState(rmPipelineState)
                    pipeline.setRayMarchPipeline(rmPipeline)
                    let uniforms = makeSceneUniforms(from: desc)
                    rmPipeline.sceneUniforms = uniforms
                    rmPipeline.debugGBufferMode = debugGBufferMode

                    // Capture JSON baseline so per-frame audio modulation in
                    // RenderPipeline+RayMarch.swift is applied additively on
                    // top of the preset's intent rather than clobbering it.
                    var snap = RayMarchPipeline.BaseSceneSnapshot()
                    snap.cameraPosition = SIMD3(uniforms.cameraOriginAndFov.x,
                                                uniforms.cameraOriginAndFov.y,
                                                uniforms.cameraOriginAndFov.z)
                    snap.lightIntensity = uniforms.lightPositionAndIntensity.w
                    snap.lightColor = SIMD3(uniforms.lightColor.x,
                                            uniforms.lightColor.y,
                                            uniforms.lightColor.z)
                    snap.fogFar = uniforms.sceneParamsB.y
                    rmPipeline.baseScene = snap

                    // Per-preset base dolly speed (world units per second).  Set
                    // to 0 for camera-static presets.  `drawWithRayMarch`
                    // multiplies this per-frame by a bass-modulated factor
                    // (0.5 + bassContribution), so the actual speed varies
                    // ~0.5×-1.6× the base depending on audio.  Camera still
                    // always moves (autonomous baseline) — bass just
                    // modulates the pace.
                    rmPipeline.cameraDollySpeed = {
                        switch desc.name {
                        case "Glass Brutalist":       return 2.5
                        case "Volumetric Lithograph": return 1.8
                        default:                      return 0
                        }
                    }()

                    // Reset the dolly integrator state on preset (re)apply so
                    // re-entering a ray-march preset doesn't jump forward by
                    // the distance accumulated during its previous activation.
                    rmPipeline.cameraDollyOffset = 0
                    rmPipeline.lastDollyFrameTime = nil

                    currentRayMarchPipeline = rmPipeline

                    // Lumen Mosaic: allocate the 4-light pattern engine and
                    // wire its 336-byte slot-8 buffer + per-frame tick. The
                    // tick reads (FeatureVector, StemFeatures), advances mood
                    // smoothing + drift Lissajous + beat-locked dance, and
                    // flushes the result for the next G-buffer + lighting
                    // pass to read at fragment slot 8. (LM.2 / D-LM-buffer-slot-8.)
                    if desc.name == "Lumen Mosaic" {
                        if let engine = LumenPatternEngine(device: context.device) {
                            lumenPatternEngine = engine
                            pipeline.setDirectPresetFragmentBuffer3(engine.patternBuffer)
                            pipeline.setMeshPresetTick { [weak engine] features, stems in
                                engine?.tick(features: features, stems: stems)
                            }
                            // BUG-016 fix (2026-05-26): load the per-song
                            // palette immediately on preset activation. Before
                            // this call existed, the palette payload stayed at
                            // its zero-initialised default (every entry
                            // (0,0,0)) until the next track change fired
                            // `resetStemPipeline → refreshLumenPaletteForTrack`.
                            // Cells rendered black; the cell-boundary frost
                            // halo mixed toward float3(1.0) — visible result
                            // was a black-and-white Voronoi grid with no
                            // perceptible motion (per-beat palette-index walk
                            // had nothing to walk through). The fix calls the
                            // same helper `resetStemPipeline` does, gated on
                            // the most-recently-resolved `TrackIdentity`
                            // persisted by the track-change handler in
                            // `VisualizerEngine+Capture.swift`.
                            if let identity = lastResolvedTrackIdentity {
                                refreshLumenPaletteForTrack(
                                    identity: identity,
                                    lumenEngine: engine
                                )
                            }
                        } else {
                            logger.error(
                                "LumenPatternEngine: failed to allocate slot-8 buffer for preset '\(desc.name)'"
                            )
                            // BUG-016 / CA-Presets-FU-4 instrumentation: persist the
                            // failure to session.log so the next reproduction is
                            // greppable from the on-disk artifact. The logger.error
                            // line above writes only to the unified log (category
                            // "VisualizerEngine"); the SessionRecorder writer below
                            // lands the same event in ~/Documents/phosphene_sessions/
                            // <ts>/session.log. Engine-side parallel log at
                            // LumenPatternEngine.swift:586 (category "session").
                            sessionRecorder?.log(
                                "LumenPatternEngine: failed to allocate slot-8 buffer for preset '\(desc.name)'"
                            )
                        }
                    }

                    // Ferrofluid Ocean (V.9 Session 4.5c): the §5.8 stage-rig
                    // wiring was removed; direct audio→sky-aurora routing
                    // replaces it in the next commit. Phase 2b particle
                    // scaffolding stays.
                    if desc.name == "Ferrofluid Ocean" {
                        // V.9 Session 4.5b Phase 1: allocate the 2048-particle
                        // scaffolding + bake the 512×512 height field once.
                        // Particles are static in Phase 1; the bake produces a
                        // height texture structurally equivalent to the Phase A
                        // `voronoi_smooth` path (particles sit at smooth-Voronoi
                        // cell-center XZ; Quilez polynomial smooth-min + apex
                        // smoothing matches Leitl's published technique).
                        // Phase 2 will replace the one-shot bake with a per-
                        // frame SPH-lite compute pass driven by audio forces.
                        if let particles = FerrofluidParticles(device: context.device,
                                                               library: shaderLibrary.library) {
                            // V.9 Session 4.5c Phase 1 round 4 (2026-05-14):
                            // PIN PARTICLES. The one-shot bake at preset apply
                            // is the ONLY bake. Particles stay at canonical
                            // voronoi positions for the lifetime of the
                            // preset; heightfield topology is static; spike
                            // HEIGHT modulates at sample time via
                            // `fo_spike_strength` (`liveGate × 2.0 +
                            // bass_energy_dev × 0.7`). Closest to real
                            // ferrofluid physics — spikes are pinned at
                            // field-gradient peaks and only their height
                            // varies with field strength.
                            //
                            // The Phase 2c force-and-integrate per-frame
                            // dispatch (SPH pressure + drums radial impulse
                            // + rotation + arousal scale) was producing
                            // frame-to-frame topology drift that read as
                            // "smudged blur" rather than discrete spikes.
                            // D-127(d) rejected the Phase 2c force model;
                            // this commit goes one step further and removes
                            // motion entirely until the geometry character
                            // reads as ferrofluid in static form. Phase 3
                            // (wave-coherent motion) is deferred behind
                            // that gate.
                            particles.bakeHeightField(commandQueue: context.commandQueue)
                            ferrofluidParticles = particles
                            pipeline.setRayMarchPresetHeightTexture(particles.heightTexture)

                            // V.9 Session 4.5c Phase 1 Step B (2026-05-15) —
                            // mesh-displacement G-buffer path was introduced
                            // to replace the SDF ray-march path for Ferrofluid
                            // Ocean, mirroring Leitl's `spikes.vert.glsl`
                            // architecture.
                            //
                            // **Round 57 (2026-05-17) — disabled.** The mesh
                            // path's per-pixel normal computation (heightmap
                            // sampling at ±0.039 wu eps) produced visible
                            // "scoop" artifacts on foreground cones — eps
                            // crosses cone-edge boundaries (cone radius 0.17
                            // wu) and produces tilted normals that reflect
                            // wrong sky directions. Diagnostics in rounds
                            // 50-56 chased this across SDF tuning before
                            // realizing the live render path was the mesh
                            // path the whole time (test fixtures had been
                            // exercising the SDF path; the test/prod gap was
                            // structural). Switching live back to the SDF
                            // path uses the round-56 Lipschitz-corrected
                            // `sceneSDF` which renders cleanly. The mesh
                            // path is preserved in the codebase for a future
                            // increment that addresses its normal-computation
                            // properly; this commit just unwires it from
                            // live so users see clean cones immediately.
                            //
                            // Original mesh-encoder wire-up (preserved for
                            // reference but commented out):
                            //
                            //   let gbufferFormats: [MTLPixelFormat] = [
                            //       .rg16Float, .rgba8Snorm, .rgba8Unorm
                            //   ]
                            //   if let mesh = FerrofluidMesh(
                            //       device: context.device,
                            //       library: shaderLibrary.library,
                            //       colorAttachmentFormats: gbufferFormats,
                            //       depthAttachmentFormat: RayMarchPipeline.gbufferDepthPixelFormat) {
                            //       ferrofluidMesh = mesh
                            //       pipeline.setMeshGBufferEncoder(
                            //           makeFerrofluidMeshEncoder(mesh: mesh))
                            //   }
                            _ = ferrofluidMesh  // intentionally unused under round 57
                        } else {
                            // swiftlint:disable:next line_length
                            logger.error("FerrofluidParticles: failed to allocate particle scaffolding for preset '\(desc.name)' — falling back to placeholder (no spikes)")
                        }
                    }
                } catch {
                    logger.error("Failed to create RayMarchPipeline for preset '\(desc.name)': \(error)")
                }

            case .feedback:
                guard let fbPipeline = preset.feedbackPipelineState else {
                    logger.error("Feedback preset '\(desc.name)' missing compose pipeline state")
                    break
                }
                let params = FeedbackParams(
                    decay: desc.decay,
                    baseZoom: desc.baseZoom,
                    baseRot: desc.baseRot,
                    beatZoom: desc.beatZoom,
                    beatRot: desc.beatRot,
                    beatSensitivity: desc.beatSensitivity
                )
                pipeline.setFeedbackParams(params)
                pipeline.setFeedbackComposePipeline(fbPipeline)

            case .particles:
                // Siblings, not subclasses (D-097). Resolution table lives in
                // VisualizerEngine.resolveParticleGeometry; ParticleGeometryRegistry
                // mirrors the catalog and ParticleDispatchRegistryTests gates it.
                let geometry = resolveParticleGeometry(forPresetName: desc.name)
                if geometry == nil {
                    logger.error("No particle geometry registered for preset '\(desc.name)'")
                }
                pipeline.setParticleGeometry(geometry)

            case .icb:
                // ICB preset switching deferred to the Orchestrator increment.
                // ICB state must be set externally via pipeline.setICBState(_:).
                logger.info("ICB pass declared for '\(desc.name)' — ICB state must be set externally")

            case .ssgi:
                // SSGI is wired automatically in drawWithRayMarch when .ssgi is in activePasses.
                // No separate subsystem setup required here.
                break

            case .mvWarp:
                // MV-2: build the MVWarpPipelineBundle from the preset's compiled states and
                // the current drawable size, then wire it into the render pipeline.
                guard let warpPipelines = preset.mvWarpPipelines else {
                    logger.error("mv_warp preset '\(desc.name)' missing compiled warp pipeline states")
                    break
                }
                // Feedback textures use the drawable (8-bit) format — matching
                // butterchurn/Milkdrop (UNSIGNED_BYTE RGBA); the per-frame clamp is
                // load-bearing for Dragon Bloom's saturated no-decay equilibrium.
                // MUST match PresetLoader.feedbackFormat (the format the warp/compose/
                // scene pipelines were compiled for) or the render encoder gets an
                // attachment-format mismatch and the GPU stalls.
                // Fata Morgana (D-139): LINEAR feedback (.bgra8Unorm) matching butterchurn
                // + PresetLoader.feedbackFormat — MUST match the format the pipelines were
                // compiled for or the GPU stalls (the D-138 attachment-mismatch pitfall).
                // Nacre (NACRE.2b): HDR .rgba16Float feedback (unclamped iridescence/bloom;
                // bounded by the 0.9 in-warp decay) — also MUST mirror PresetLoader.feedbackFormat.
                let fbFormat: MTLPixelFormat
                switch desc.name {
                case "Fata Morgana": fbFormat = .bgra8Unorm
                case "Nacre":        fbFormat = .rgba16Float
                default:             fbFormat = context.pixelFormat
                }
                // Skein.ENGINE.1.1 (D-143): per-preset canvas clear ground. Marks-on-top
                // presets skip Pass 0, so the feedback-texture clear IS the held ground
                // (Skein's cream). Sourced from the preset's `marks.canvas_clear`; black
                // (default) for every other preset → byte-identical.
                let canvasClear = desc.marks?.canvasClear.map {
                    SIMD4<Double>(Double($0.x), Double($0.y), Double($0.z), 1)
                } ?? SIMD4<Double>(0, 0, 0, 1)
                let bundle = MVWarpPipelineBundle(
                    warpState: warpPipelines.warpState,
                    composeState: warpPipelines.composeState,
                    blitState: warpPipelines.blitState,
                    pixelFormat: context.pixelFormat,
                    feedbackFormat: fbFormat,
                    // Fata Morgana (D-139): non-nil ⇒ the render pipeline runs the fata
                    // branch (blur → custom warp → mirage comp). nil for every other
                    // mv_warp preset (their libraries define no `*_blur_fragment`).
                    blurState: warpPipelines.blurState,
                    // Nacre (NACRE.2b): routes the draw path to the nacre branch (custom
                    // warp → signature comp → swap). false for every other mv_warp preset.
                    isNacre: desc.name == "Nacre",
                    canvasClearColor: canvasClear
                )
                // Use the last drawable size reported by drawableSizeWillChange so
                // mid-session preset switches allocate at the correct resolution.
                // Falls back to 1920×1080 only before the first drawable size event.
                let drawableSize = pipeline.mvWarpDrawableSize
                pipeline.setupMVWarp(bundle: bundle, size: drawableSize)
                // Plumb the descriptor decay so the compose pass matches pf.decay in the shader.
                pipeline.setMVWarpDecay(desc.decay)

                // Marks-on-top overlay (D-138; generalised per-preset in Skein.ENGINE.1.1,
                // D-143). If the preset compiled a scene-geometry overlay pipeline, wire it
                // with the preset's OWN draw params + chromatic + comp + beat pump declared
                // in its `marks` descriptor block — no longer hard-coded to Dragon Bloom.
                // Dragon Bloom's `marks` block carries its exact prior values verbatim
                // (1536/3/lineStrip, chromatic 1.0, comp invert 1 / echo 0.5 / gamma 1.07,
                // beat pump on) ⇒ byte-identical. Skein declares chromatic 0 + comp-identity
                // + a fullscreen-triangle disc. Presets with no overlay keep chromatic 0 +
                // comp-identity exactly as before.
                if let geoState = warpPipelines.sceneGeometryState, let marks = desc.marks {
                    pipeline.setSceneGeometry(
                        geoState,
                        vertexCount: marks.vertexCount,
                        instanceCount: marks.instanceCount,
                        primitive: mvWarpMarksPrimitive(marks.primitive, presetName: desc.name))
                    pipeline.setMVWarpChromatic(marks.chromatic)
                    pipeline.setMVWarpPost(
                        invert: marks.comp.invert,
                        echo: marks.comp.echo,
                        gamma: marks.comp.gamma,
                        beatPulse: marks.beatPulse)
                } else {
                    if warpPipelines.sceneGeometryState != nil {
                        logger.error("mv_warp '\(desc.name)' has a geometry overlay but no `marks` block.")
                    }
                    pipeline.setSceneGeometry(nil, vertexCount: 0, instanceCount: 0, primitive: .lineStrip)
                    pipeline.setMVWarpChromatic(0.0)
                    pipeline.setMVWarpPost(invert: 0.0, echo: 0.0, gamma: 1.0)
                }

                // Fata Morgana (D-139, FM.L2): wire the custom-shape pipelines (the
                // fata draw branch keys on the blur pipeline; the shapes draw on top of
                // the warp target). nil/nil for every other mv_warp preset.
                pipeline.setFataShapePipelines(
                    additive: warpPipelines.shapeAdditiveState,
                    normal: warpPipelines.shapeNormalState)

                // Arachne-specific: allocate web pool + spider buffer and wire tick + fragment buffers.
                if desc.name == "Arachne" {
                    if let state = ArachneState(device: context.device) {
                        arachneState = state
                        pipeline.setDirectPresetFragmentBuffer(state.webBuffer)    // buffer(6)
                        pipeline.setDirectPresetFragmentBuffer2(state.spiderBuffer) // buffer(7)
                        pipeline.setMeshPresetTick { [weak state] features, stems in
                            state?.tick(features: features, stems: stems)
                        }
                    } else {
                        logger.error("ArachneState: failed to allocate web pool for preset '\(desc.name)'")
                    }
                }

                // Gossamer-specific: allocate wave pool and wire tick + fragment buffer.
                if desc.name == "Gossamer" {
                    if let state = GossamerState(device: context.device) {
                        gossamerState = state
                        pipeline.setDirectPresetFragmentBuffer(state.waveBuffer)
                        pipeline.setMeshPresetTick { [weak state] features, stems in
                            state?.tick(deltaTime: features.deltaTime,
                                        features: features,
                                        stems: stems)
                        }
                    } else {
                        logger.error("GossamerState: failed to allocate wave pool for preset '\(desc.name)'")
                    }
                }

                // Skein-specific (Skein.ENGINE.1.2): allocate the painter state + onset-burst
                // ring and wire the per-frame tick + the gated slot-6 marks-on-top overlay
                // buffer. The buffer reaches `skein_geometry_fragment` via the strands-on-top
                // slot-6 binding (RenderPipeline+MVWarpScene). The per-track seed is installed
                // on track change (resetSkeinSeed); construct with the current track's seed so
                // the painting is deterministic from frame 1.
                if desc.name == "Skein" {
                    if let state = SkeinState(device: context.device, seed: currentSkeinSeed()) {
                        skeinState = state
                        pipeline.setDirectPresetFragmentBuffer(state.skeinBuffer)   // buffer(6)
                        // Skein.5.3b: the palette's GROUND travels with the track. setupMVWarp
                        // already cleared the canvas to the JSON cream before this state existed
                        // — push the per-track ground override and re-wipe so the first track's
                        // canvas opens on ITS palette's ground (light or dark).
                        let ground = state.groundLinear
                        pipeline.setMVWarpCanvasGround(SIMD4<Double>(
                            Double(ground.x), Double(ground.y), Double(ground.z), 1.0))
                        pipeline.clearMVWarpCanvasToGround()
                        // Skein.ENGINE.2: the per-frame wetness-channel decay (pauses at silence)
                        // is pushed to the warp/hold pass from the tick hook. Capture the pipeline
                        // WEAKLY (via a local) so the @Sendable closure holds no retain cycle —
                        // self keeps the pipeline alive; the weak ref just tracks the object.
                        let renderPipeline = pipeline
                        pipeline.setMeshPresetTick { [weak state, weak renderPipeline] features, stems in
                            guard let state else { return }
                            // Skein.ENGINE.3 (D-151): read the live structural-section signal from
                            // the gated bridge and pass it into the tick (CPU-only; STORED for
                            // Skein.5's structural bias — no visual effect yet, byte-identical today).
                            state.tick(deltaTime: features.deltaTime,
                                       features: features,
                                       stems: stems,
                                       structure: renderPipeline?.latestStructuralPrediction ?? .none)
                            // skein_warp_fragment reads this at fragment buffer 1 (decays ALPHA only).
                            renderPipeline?.setMVWarpWetnessDecay(state.wetnessDecay)
                        }
                    } else {
                        logger.error("SkeinState: failed to allocate painter state for preset '\(desc.name)'")
                    }
                }

                // Nacre (NACRE.2b): no per-preset CPU state. The render branch
                // (RenderPipeline+Nacre) computes NacreUniforms inline each frame (time +
                // drawable size + trebleDev — stateless, like Fata Morgana) and binds them
                // to the warp + comp passes; the bass-onset kick runs GPU-side off bassDev.
                // HDR float feedback is opted in by name (PresetLoader.feedbackFormat).

                // (Aurora Veil's per-preset state was previously here, inside
                // case .mvWarp. AV.2.2 dropped mv_warp from Aurora Veil's
                // passes, so this nested block never fires anymore. The state
                // allocation moved OUT of the switch to a pass-agnostic block
                // below — see "Aurora Veil-specific" after the `for pass` loop.)

            case .staged:
                // V.ENGINE.1: bridge per-stage compiled pipelines into the renderer.
                let stageSpecs = preset.stages.map { stage in
                    StagedStageSpec(
                        name: stage.name,
                        pipelineState: stage.pipelineState,
                        samples: stage.samples,
                        writesToDrawable: stage.writesToDrawable
                    )
                }
                guard !stageSpecs.isEmpty else {
                    logger.error("Staged preset '\(desc.name)' has no compiled stages — skipping setup")
                    break
                }
                pipeline.setStagedRuntime(stageSpecs, drawableSize: pipeline.mvWarpDrawableSize)

                // V.7.7B: per-preset state for staged Arachne. Mirrors the mv_warp
                // branch above — allocate the ArachneState pool, bind webBuffer at
                // fragment slot 6 + spiderBuffer at slot 7 (per CLAUDE.md GPU
                // Contract), and wire the per-frame tick so web stages advance and
                // mood data lands in webs[0].row4. Without this the staged WORLD +
                // COMPOSITE fragments read zeros from slots 6/7 and the WORLD
                // palette collapses to the silence anchor.
                if desc.name == "Arachne" {
                    if let state = ArachneState(device: context.device) {
                        arachneState = state
                        // V.7.7C.2 (D-095): reset the foreground BuildState +
                        // per-segment spider cooldown at segment-start. The
                        // canonical entry point per V.7.7C.2 §5.2 SUB-ITEM 2.
                        state.reset()
                        pipeline.setDirectPresetFragmentBuffer(state.webBuffer)    // buffer(6)
                        pipeline.setDirectPresetFragmentBuffer2(state.spiderBuffer) // buffer(7)
                        pipeline.setMeshPresetTick { [weak state] features, stems in
                            state?.tick(features: features, stems: stems)
                        }
                    } else {
                        logger.error("ArachneState: failed to allocate web pool for staged preset '\(desc.name)'")
                    }
                }

            case .direct:
                break // No subsystem setup required; direct rendering is the default fallback.
            }
        }

        // Aurora Veil-specific (AV.2.2b): allocate kink accumulator +
        // pitch-smoother state and wire it at slot 6 + per-frame tick.
        // This block sits OUTSIDE the `for pass` switch above because
        // AV.2.2 dropped mv_warp from Aurora Veil's passes (`passes: []`),
        // and a nested-in-`.mvWarp` setup block never fires when the
        // passes array is empty. AV.2.2a's drawDirect slot-6 binding fix
        // was necessary but not sufficient — the buffer was never being
        // created, so even the corrected drawDirect skipped it (nil
        // setter). Live session 2026-05-18T23-07-33Z still crashed.
        //
        // The setMeshPresetTick closure is invoked from RenderPipeline+Draw
        // line ~120 once per frame regardless of dispatch path, so it
        // works correctly for both mv_warp and direct presets.
        if desc.name == "Aurora Veil" {
            if let state = AuroraVeilState(device: context.device) {
                auroraVeilState = state
                state.reset()
                pipeline.setDirectPresetFragmentBuffer(state.stateBuffer)
                pipeline.setMeshPresetTick { [weak state] features, stems in
                    state?.tick(deltaTime: features.deltaTime,
                                features: features,
                                stems: stems)
                }
            } else {
                logger.error("AuroraVeilState: failed to allocate state for preset '\(desc.name)'")
            }
        }

        // Nimbus-specific (NB.4): allocate the Energy bloom follower + gas
        // flow-phase state and wire it at slot 6 + per-frame tick. Same
        // direct-preset (`passes: []`) slot-6 pattern as Aurora Veil — the
        // setMeshPresetTick closure runs once per frame on the direct path
        // (RenderPipeline+Draw), advancing the fast-attack/slow-release bloom
        // and the flow accumulator before the scene draw reads buffer(6).
        // reset() zeroes the follower so the body settles into each new
        // track/segment rather than carrying the prior bloom across the cut
        // (DESIGN §1.5).
        if desc.name == "Nimbus" {
            if let state = NimbusState(device: context.device) {
                nimbusState = state
                state.reset()
                pipeline.setDirectPresetFragmentBuffer(state.stateBuffer)
                pipeline.setMeshPresetTick { [weak state] features, stems in
                    state?.tick(deltaTime: features.deltaTime,
                                features: features,
                                stems: stems)
                }
                // NB.8: render the volumetric march at half resolution + upscale.
                // The body swells to fill the frame at full energy, where a
                // full-res march exceeds the 7 ms Tier-2 ceiling; 0.5× is ~4×
                // cheaper and the soft gas tolerates the upscale. Reset to 1.0
                // for every other preset at the top of applyPreset.
                pipeline.setDirectRenderScale(0.5)
            } else {
                logger.error("NimbusState: failed to allocate state for preset '\(desc.name)'")
            }
        }

        // Text overlay: allocate and wire when the preset declares text_overlay: true.
        if desc.textOverlay {
            if let overlay = DynamicTextOverlay(device: context.device) {
                spectralCartographOverlay = overlay
                pipeline.setDynamicTextOverlay(overlay)
                let histBuf = pipeline.spectralHistory
                pipeline.setTextOverlayCallback { [weak histBuf, weak self] overlay, features in
                    guard let histBuf, let self else { return }
                    let (bpm, lockState) = histBuf.readOverlayState()
                    let sessionMode = histBuf.readSessionMode()
                    let driftMs = histBuf.readDriftMs()
                    let phaseOffsetMs = self.mirPipeline.liveDriftTracker.visualPhaseOffsetMs
                    overlay.refresh { ctx, size in
                        SpectralCartographText.draw(
                            in: ctx,
                            size: size,
                            bpm: bpm,
                            lockState: lockState,
                            sessionMode: sessionMode,
                            beatPhase01: features.beatPhase01,
                            barPhase01: features.barPhase01,
                            beatsPerBar: Int(features.beatsPerBar.rounded()),
                            driftMs: driftMs,
                            phaseOffsetMs: phaseOffsetMs
                        )
                    }
                }
            } else {
                logger.error("DynamicTextOverlay: init failed for preset '\(desc.name)' — text overlay disabled")
            }
        }

        // Activate the passes after all subsystems are configured.
        pipeline.setActivePasses(desc.passes)

        // V.7.6.2: subscribe to preset completion signal if the active state object
        // conforms to `PresetSignaling`. Resets on every applyPreset call so a stale
        // subscription cannot fire after a preset switch.
        wirePresetCompletionSubscription()
        currentSegmentStartTime = Date().timeIntervalSinceReferenceDate
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    // MARK: - Scene Uniforms Construction

    /// Build a `SceneUniforms` value from a preset descriptor's scene configuration.
    ///
    /// Delegates to `PresetDescriptor.makeSceneUniforms()` in the Presets module so the
    /// camera math is testable without an app-layer dependency.
    func makeSceneUniforms(from desc: PresetDescriptor) -> SceneUniforms {
        return desc.makeSceneUniforms()
    }

    // MARK: - Preset Completion Signal (V.7.6.2)

    /// Connects the active preset's `PresetSignaling.presetCompletionEvent` to the
    /// orchestrator. Cancels any prior subscription. No-op for presets that do not
    /// conform to `PresetSignaling` (most do not).
    func wirePresetCompletionSubscription() {
        presetCompletionCancellable?.cancel()
        presetCompletionCancellable = nil

        let signal = activePresetSignaling()
        guard let signal else { return }

        presetCompletionCancellable = signal.presetCompletionEvent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePresetCompletionEvent()
                }
            }
    }

    /// Returns the currently active per-preset state object that conforms to
    /// `PresetSignaling`, or nil. Currently only `ArachneState` is a candidate
    /// (Gossamer/Stalker/etc. are cyclical and never emit).
    ///
    /// V.7.7C.2: `ArachneState` now conforms via `Sources/Orchestrator/
    /// ArachneStateSignaling.swift` (placement forced by the Presets→Orchestrator
    /// module-cycle constraint — see that file's note). The conditional cast
    /// became unconditional once the conformance landed.
    private func activePresetSignaling() -> (any PresetSignaling)? {
        return arachneState
    }

    /// Build the per-frame G-buffer encode closure for Ferrofluid Ocean
    /// (Phase 1 round 20). Reads the live BPM from
    /// `mirPipeline.liveDriftTracker.currentBPM` each frame and converts
    /// to `tempoScale = bpm / 60` for the Gerstner phase advancement.
    /// At silence / pre-grid-lock state `currentBPM = 0` → tempoScale = 0
    /// → waves freeze (also gated by amplitude `presenceGate`).
    private func makeFerrofluidMeshEncoder(
        mesh: FerrofluidMesh
    ) -> RayMarchPipeline.MeshGBufferEncode {
        return { [weak mesh, weak self] encoder, features, stems, sceneUniforms, heightTex in
            guard let mesh = mesh else { return }
            let bpm = self?.mirPipeline.liveDriftTracker.currentBPM ?? 0
            let tempoScale = Float(bpm) / 60.0
            var meshUniforms = FerrofluidMesh.MeshUniforms(tempoScale: tempoScale)
            mesh.encodeGBufferPass(into: encoder,
                                    features: &features,
                                    stems: &stems,
                                    sceneUniforms: &sceneUniforms,
                                    meshUniforms: &meshUniforms,
                                    heightTexture: heightTex)
        }
    }

    /// Handle a `PresetSignaling.presetCompletionEvent` firing.
    ///
    /// Honours the event only when the segment has been on screen for at least
    /// `PresetSignalingDefaults.minSegmentDuration` seconds. Below the floor, the
    /// event is dropped — preset authors should treat the signal as a *request*.
    ///
    /// V.7.7C.4 / D-095 follow-up: also honours `diagnosticPresetLocked`. When
    /// the L key (or any future "lock to preset" UX) is engaged, completion-
    /// driven transitions are fully suppressed — letting Matt watch the full
    /// build cycle on Arachne (or any future PresetSignaling-emitting preset)
    /// without the orchestrator cycling away every ~60 s. Pre-V.7.7C.4 the
    /// L lock only suppressed mood-override switching (in `applyLiveUpdate`);
    /// the orchestrator continued to fire on completion events. Manual
    /// `applyPresetByID(_:)` is unaffected — Matt can always cycle via
    /// `⌘[`/`⌘]`.
    @MainActor
    private func handlePresetCompletionEvent() {
        if diagnosticPresetLocked {
            logger.info("Orchestrator: preset completion suppressed (diagnosticPresetLocked)")
            return
        }
        let elapsed = Date().timeIntervalSinceReferenceDate - currentSegmentStartTime
        guard elapsed >= PresetSignalingDefaults.minSegmentDuration else {
            logger.info("Orchestrator: preset completion ignored (\(elapsed) s < min)")
            return
        }
        presetCompletionAdvanceCount += 1
        logger.info("Orchestrator: preset completion honoured — advancing segment")
        nextPreset()
    }
}

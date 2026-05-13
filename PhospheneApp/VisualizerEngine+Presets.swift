// VisualizerEngine+Presets — Preset switching and render-path configuration.
// swiftlint:disable file_length

import Combine
import CoreGraphics
import Foundation
import os.log
import Orchestrator
import Presets
import Renderer
import Shared

private let logger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

extension VisualizerEngine {

    // MARK: - Preset Cycling

    /// Advance to the next preset and update the pipeline.
    func nextPreset() {
        guard let preset = presetLoader.nextPreset() else { return }
        applyPreset(preset)
        showPresetName(preset.descriptor.name)
    }

    /// Go back to the previous preset and update the pipeline.
    func previousPreset() {
        guard let preset = presetLoader.previousPreset() else { return }
        applyPreset(preset)
        showPresetName(preset.descriptor.name)
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
        pipeline.setMeshPresetBuffer(nil)
        pipeline.setMeshPresetFragmentBuffer(nil)
        pipeline.setMeshPresetTick(nil)
        arachneState = nil
        gossamerState = nil
        lumenPatternEngine = nil
        ferrofluidStageRig = nil
        spectralCartographOverlay = nil
        pipeline.setDynamicTextOverlay(nil)
        pipeline.setTextOverlayCallback(nil)
        pipeline.setDirectPresetFragmentBuffer(nil)
        pipeline.setDirectPresetFragmentBuffer2(nil)
        pipeline.setDirectPresetFragmentBuffer3(nil)
        pipeline.setDirectPresetFragmentBuffer4(nil)
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
                if let chain = try? PostProcessChain(context: context, shaderLibrary: shaderLibrary) {
                    pipeline.setPostProcessChain(chain)
                } else {
                    logger.error("Failed to create PostProcessChain for preset: \(desc.name)")
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
                        } else {
                            logger.error(
                                "LumenPatternEngine: failed to allocate slot-8 buffer for preset '\(desc.name)'"
                            )
                        }
                    }

                    // Ferrofluid Ocean (V.9): allocate the §5.8 stage-rig and
                    // wire its 208-byte slot-9 buffer + per-frame tick. The
                    // tick reads (FeatureVector, StemFeatures, dt), advances
                    // the orbital phase + drums-envelope intensity + per-light
                    // palette phase (with vocals_pitch_hz / other_energy_dev
                    // pitch-shift), and flushes the result for the next
                    // G-buffer + lighting pass to read at fragment slot 9.
                    // matID == 2 dispatch in raymarch_lighting_fragment loops
                    // over the per-frame light state. (D-125 first consumer;
                    // generic StageRigEngine extraction deferred to second.)
                    if desc.name == "Ferrofluid Ocean", let stageRigDesc = desc.stageRig {
                        if let rig = FerrofluidStageRig(device: context.device, descriptor: stageRigDesc) {
                            ferrofluidStageRig = rig
                            pipeline.setDirectPresetFragmentBuffer4(rig.buffer)
                            pipeline.setMeshPresetTick { [weak rig] features, stems in
                                rig?.tick(features: features,
                                          stems: stems,
                                          dt: TimeInterval(features.deltaTime))
                            }
                        } else {
                            logger.error(
                                "FerrofluidStageRig: failed to allocate slot-9 buffer for preset '\(desc.name)'"
                            )
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
                let bundle = MVWarpPipelineBundle(
                    warpState: warpPipelines.warpState,
                    composeState: warpPipelines.composeState,
                    blitState: warpPipelines.blitState,
                    pixelFormat: context.pixelFormat
                )
                // Use the last drawable size reported by drawableSizeWillChange so
                // mid-session preset switches allocate at the correct resolution.
                // Falls back to 1920×1080 only before the first drawable size event.
                let drawableSize = pipeline.mvWarpDrawableSize
                pipeline.setupMVWarp(bundle: bundle, size: drawableSize)
                // Plumb the descriptor decay so the compose pass matches pf.decay in the shader.
                pipeline.setMVWarpDecay(desc.decay)

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

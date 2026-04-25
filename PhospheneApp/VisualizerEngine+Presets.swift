// VisualizerEngine+Presets — Preset switching and render-path configuration.

import CoreGraphics
import os.log
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
        pipeline.setDirectPresetFragmentBuffer(nil)
        pipeline.setDirectPresetFragmentBuffer2(nil)
        pipeline.setPostProcessChain(nil)
        pipeline.setRayMarchPipeline(nil)
        pipeline.setFeedbackParams(nil)
        pipeline.setFeedbackComposePipeline(nil)
        pipeline.setParticleGeometry(nil)
        pipeline.clearMVWarpState()
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
                pipeline.setParticleGeometry(particleGeometry)

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

            case .direct:
                break // No subsystem setup required; direct rendering is the default fallback.
            }
        }

        // Activate the passes after all subsystems are configured.
        pipeline.setActivePasses(desc.passes)
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
}

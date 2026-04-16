// VisualizerEngine+Presets — Preset switching and render-path configuration.

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

        // Reset all active passes and subsystems before applying the new preset.
        // This prevents stale subsystem state from the previous preset bleeding through.
        pipeline.setActivePasses([])
        pipeline.setMeshGenerator(nil)
        pipeline.setPostProcessChain(nil)
        pipeline.setRayMarchPipeline(nil)
        pipeline.setFeedbackParams(nil)
        pipeline.setFeedbackComposePipeline(nil)
        pipeline.setParticleGeometry(nil)
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

                    // Per-preset dolly speed. Only Glass Brutalist uses forward
                    // dolly for now; others stay camera-static unless the
                    // preset author opts in.
                    rmPipeline.cameraDollySpeed = (desc.name == "Glass Brutalist") ? 2.5 : 0

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

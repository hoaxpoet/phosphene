// VisualizerEngine+Presets — Preset switching and render-path configuration.

import os.log
import Presets
import Renderer
import Shared
import simd

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
                    rmPipeline.sceneUniforms = makeSceneUniforms(from: desc)
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
    /// Falls back to `SceneUniforms()` defaults for any field not declared in the JSON.
    /// `audioTime` and `aspectRatio` are left at their defaults (0 and 16/9) — the
    /// render loop overwrites them each frame in `drawWithRayMarch`.
    func makeSceneUniforms(from desc: PresetDescriptor) -> SceneUniforms {
        var uniforms = SceneUniforms()

        // sceneParamsA: x=audioTime (overwritten per-frame), y=aspectRatio (overwritten per-frame),
        // z=nearPlane, w=farPlane.  SwiftUI zero-initialises SceneUniforms, so nearPlane and
        // farPlane must be set here — drawWithRayMarch only updates x and y each frame.
        // A farPlane of 0 causes the G-buffer ray march loop to never execute (t < 0 is always
        // false), producing an all-sky frame regardless of scene geometry.
        uniforms.sceneParamsA = SIMD4(0, 16.0 / 9.0, 0.1, 30.0)

        // Camera — compute orthonormal basis from position and target.
        if let cam = desc.sceneCamera {
            let fwd = simd_normalize(cam.target - cam.position)
            let worldUp = SIMD3<Float>(0, 1, 0)
            // Guard against degenerate case where forward is parallel to world-up.
            let right = simd_normalize(simd_cross(fwd, worldUp))
            let up = simd_cross(right, fwd)
            uniforms.cameraOriginAndFov = SIMD4(cam.position.x, cam.position.y, cam.position.z, cam.fov)
            uniforms.cameraForward = SIMD4(fwd.x, fwd.y, fwd.z, 0)
            uniforms.cameraRight = SIMD4(right.x, right.y, right.z, 0)
            uniforms.cameraUp = SIMD4(up.x, up.y, up.z, 0)
        }

        // Primary light — only the first entry is used (single-light SceneUniforms).
        if let light = desc.sceneLights.first {
            uniforms.lightPositionAndIntensity = SIMD4(
                light.position.x, light.position.y, light.position.z, light.intensity)
            uniforms.lightColor = SIMD4(light.color.x, light.color.y, light.color.z, 0)
        }

        // Fog: map density → fogFar distance; ambient stored in sceneParamsB.z.
        let fogFar: Float = desc.sceneFog > 0 ? max(1.0, 1.0 / desc.sceneFog) : uniforms.sceneParamsB.y
        uniforms.sceneParamsB = SIMD4(
            uniforms.sceneParamsB.x,
            fogFar,
            desc.sceneAmbient,
            0
        )

        return uniforms
    }
}

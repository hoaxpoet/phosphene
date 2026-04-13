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

    /// Apply a preset to the render pipeline, including feedback, mesh, post-process,
    /// ray march, and particle configuration.
    func applyPreset(_ preset: PresetLoader.LoadedPreset) {
        let desc = preset.descriptor
        pipeline.setActivePipelineState(preset.pipelineState)

        if desc.useRayMarch, let rmPipelineState = preset.rayMarchPipelineState {
            applyRayMarchPreset(preset: preset, rmPipelineState: rmPipelineState, desc: desc)
        } else if desc.useMeshShader {
            // Mesh shader preset: wrap the compiled pipeline state in a MeshGenerator
            // and route all rendering through drawWithMeshShader. Feedback and particles
            // are incompatible with the mesh path in this increment.
            let config = MeshGeneratorConfiguration(
                maxVerticesPerMeshlet: 256,
                maxPrimitivesPerMeshlet: 512,
                meshThreadCount: desc.meshThreadCount  // from JSON sidecar, default 64
            )
            let gen = MeshGenerator(
                device: context.device,
                pipelineState: preset.pipelineState,
                configuration: config
            )
            pipeline.setMeshGenerator(gen, enabled: true)
            pipeline.setPostProcessChain(nil, enabled: false)
            pipeline.setFeedbackParams(nil)
            pipeline.setFeedbackComposePipeline(nil)
            pipeline.setParticleGeometry(nil)
        } else if desc.usePostProcess {
            // HDR post-process preset (e.g. Popcorn): pipeline compiled for .rgba16Float,
            // rendered through PostProcessChain (scene → bloom → ACES tone map → drawable).
            pipeline.setMeshGenerator(nil, enabled: false)
            pipeline.setFeedbackParams(nil)
            pipeline.setFeedbackComposePipeline(nil)
            pipeline.setParticleGeometry(nil)
            if let chain = try? PostProcessChain(context: context, shaderLibrary: shaderLibrary) {
                pipeline.setPostProcessChain(chain, enabled: true)
            } else {
                logger.error("Failed to create PostProcessChain for preset: \(desc.name)")
                pipeline.setPostProcessChain(nil, enabled: false)
            }
        } else if desc.useFeedback, let fbPipeline = preset.feedbackPipelineState {
            pipeline.setMeshGenerator(nil, enabled: false)
            pipeline.setPostProcessChain(nil, enabled: false)
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
            // Attach particles only for presets that declare use_particles in their JSON.
            pipeline.setParticleGeometry(desc.useParticles ? particleGeometry : nil)
        } else {
            pipeline.setMeshGenerator(nil, enabled: false)
            pipeline.setPostProcessChain(nil, enabled: false)
            pipeline.setFeedbackParams(nil)
            pipeline.setFeedbackComposePipeline(nil)
            // Detach particles — non-feedback presets don't use compute particles.
            pipeline.setParticleGeometry(nil)
        }
    }

    // MARK: - Ray March Setup

    /// Configure the render pipeline for a ray march preset.
    ///
    /// Extracts the multi-step setup out of `applyPreset` to keep that method within
    /// the SwiftLint `function_body_length` limit.  All other render paths are disabled
    /// before enabling the deferred G-buffer + PBR lighting path.
    private func applyRayMarchPreset(
        preset: PresetLoader.LoadedPreset,
        rmPipelineState: MTLRenderPipelineState,
        desc: PresetDescriptor
    ) {
        // Ray march preset: deferred G-buffer + PBR lighting + ACES composite.
        // Disable all other render paths — they are incompatible with the G-buffer pipeline.
        pipeline.setMeshGenerator(nil, enabled: false)
        pipeline.setFeedbackParams(nil)
        pipeline.setFeedbackComposePipeline(nil)
        pipeline.setParticleGeometry(nil)

        let rmPipeline: RayMarchPipeline
        do {
            rmPipeline = try RayMarchPipeline(context: context, shaderLibrary: shaderLibrary)
        } catch {
            logger.error("Failed to create RayMarchPipeline for preset '\(desc.name)': \(error)")
            pipeline.setRayMarchPipeline(nil, enabled: false)
            pipeline.setPostProcessChain(nil, enabled: false)
            return
        }
        // Wire the preset's compiled G-buffer state into the pipeline for use each frame.
        pipeline.setActivePipelineState(rmPipelineState)
        pipeline.setRayMarchPipeline(rmPipeline, enabled: true)

        // If the preset also requests post-process bloom, attach the chain.
        // RayMarchPipeline.render() will call chain.runBloomAndComposite when non-nil.
        if desc.usePostProcess {
            if let chain = try? PostProcessChain(context: context, shaderLibrary: shaderLibrary) {
                pipeline.setPostProcessChain(chain, enabled: true)
            } else {
                logger.error("Failed to create PostProcessChain for ray march preset: \(desc.name)")
                pipeline.setPostProcessChain(nil, enabled: false)
            }
        } else {
            pipeline.setPostProcessChain(nil, enabled: false)
        }
    }
}

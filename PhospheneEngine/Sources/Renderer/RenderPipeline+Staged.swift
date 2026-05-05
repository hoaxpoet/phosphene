// RenderPipeline+Staged — Per-preset staged composition with named offscreen
// textures and pass-separated harness capture (V.ENGINE.1).
//
// A staged preset declares an ordered `stages: [...]` array on its JSON sidecar.
// Each stage names a fragment function and an optional list of earlier stages
// whose outputs it samples at fragment textures starting at `[[texture(13)]]`.
// Non-final stages render to per-stage `.rgba16Float` offscreen textures; the
// final stage renders to the drawable.
//
// This is the minimum scaffold needed for Arachne v8's staged WORLD → WEB →
// COMPOSITE architecture and any future preset family that needs per-pass
// compositing (refraction sampling a previously-rendered scene texture; depth
// of focus on one layer; light shafts as a composited pass; etc.).
//
// See `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` for the engine capability
// matrix that motivates this scaffold.

import Metal
@preconcurrency import MetalKit
import Shared

// MARK: - Staged Stage Spec

/// One stage in the renderer's active staged-composition spec.
///
/// `RenderPipeline.setStagedRuntime(_:)` accepts an ordered array of these,
/// allocates one offscreen texture per non-final stage, and dispatches the
/// stages each frame in `drawWithStaged(...)`.
public struct StagedStageSpec: Sendable {
    /// Stage identifier — must be unique within the runtime; matches the
    /// stage's `name` in `PresetDescriptor.stages`.
    public let name: String
    /// Compiled fragment pipeline. Non-final stages target `.rgba16Float`; the
    /// final stage targets the drawable pixel format.
    public let pipelineState: MTLRenderPipelineState
    /// Names of earlier stages whose outputs this stage samples at
    /// `[[texture(13)]]`, `[[texture(14)]]`, ... in the listed order.
    public let samples: [String]
    /// True if this stage targets the drawable; false if `.rgba16Float`.
    public let writesToDrawable: Bool

    public init(
        name: String,
        pipelineState: MTLRenderPipelineState,
        samples: [String],
        writesToDrawable: Bool
    ) {
        self.name = name
        self.pipelineState = pipelineState
        self.samples = samples
        self.writesToDrawable = writesToDrawable
    }
}

/// First fragment-texture binding slot used by staged sampled inputs.
/// Slots 0–12 are reserved (noise textures 4–8, IBL 9–11, text overlay 12).
public let kStagedSampledTextureFirstSlot: Int = 13

// MARK: - RenderPipeline + Staged

extension RenderPipeline {

    // MARK: Configuration

    /// Configure the renderer for a staged-composition preset.
    ///
    /// Pass an ordered array of stage specs (last entry must have
    /// `writesToDrawable == true`). Allocates one `.rgba16Float` offscreen
    /// texture per non-final stage, sized to the supplied drawable dimensions.
    /// Pass `nil` to clear the staged path (call on every preset switch).
    public func setStagedRuntime(_ stages: [StagedStageSpec]?, drawableSize: CGSize) {
        stagedLock.withLock {
            stagedStages = stages ?? []
            stagedTextures.removeAll(keepingCapacity: true)
        }
        if let stages, !stages.isEmpty {
            allocateStagedTextures(size: drawableSize)
        }
    }

    /// Snapshot of the active staged stages (for tests / diagnostics).
    public var currentStagedStageNames: [String] {
        stagedLock.withLock { stagedStages.map(\.name) }
    }

    /// Reallocate per-stage offscreen textures at the new size. Called from
    /// `mtkView(_:drawableSizeWillChange:)` so resizes pick up immediately.
    func reallocateStagedTextures(size: CGSize) {
        let hasStages = stagedLock.withLock { !stagedStages.isEmpty }
        guard hasStages else { return }
        allocateStagedTextures(size: size)
    }

    private func allocateStagedTextures(size: CGSize) {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        stagedLock.withLock {
            stagedTextures.removeAll(keepingCapacity: true)
            for stage in stagedStages where !stage.writesToDrawable {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba16Float,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                desc.usage = [.renderTarget, .shaderRead]
                desc.storageMode = .private
                if let tex = context.device.makeTexture(descriptor: desc) {
                    stagedTextures[stage.name] = tex
                }
            }
        }
    }

    // MARK: Texture Lookup

    /// Lookup an offscreen stage texture by name. Returns nil for the final
    /// stage (which writes to the drawable) or any unknown name.
    public func stagedTexture(named name: String) -> MTLTexture? {
        stagedLock.withLock { stagedTextures[name] }
    }

    // MARK: Draw

    /// Walk the staged-composition stages for the active preset and render
    /// each into its target. The final stage renders to the drawable; all
    /// earlier stages render into named offscreen textures.
    @MainActor
    func drawWithStaged(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures
    ) {
        let snapshot = stagedLock.withLock { (stagedStages, stagedTextures) }
        let stages = snapshot.0
        let textures = snapshot.1
        guard !stages.isEmpty else { return }

        // Fast path: for each non-final stage, render to its own offscreen texture.
        for stage in stages where !stage.writesToDrawable {
            guard let target = textures[stage.name] else {
                continue
            }
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = target
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor =
                MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            descriptor.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                continue
            }
            encodeStage(stage: stage,
                        encoder: encoder,
                        features: &features,
                        stemFeatures: stemFeatures,
                        textures: textures)
            encoder.endEncoding()
        }

        // Final stage: render to drawable.
        guard let finalStage = stages.last,
              finalStage.writesToDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }
        descriptor.colorAttachments[0].clearColor =
            MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encodeStage(stage: finalStage,
                    encoder: encoder,
                    features: &features,
                    stemFeatures: stemFeatures,
                    textures: textures)
        encoder.endEncoding()
        commandBuffer.present(drawable)
    }

    // MARK: Encoding

    private func encodeStage(
        stage: StagedStageSpec,
        encoder: MTLRenderCommandEncoder,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        textures: [String: MTLTexture]
    ) {
        encoder.setRenderPipelineState(stage.pipelineState)
        encoder.setFragmentBytes(&features,
                                 length: MemoryLayout<FeatureVector>.size,
                                 index: 0)
        encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
        var stems = stemFeatures
        encoder.setFragmentBytes(&stems,
                                 length: MemoryLayout<StemFeatures>.size,
                                 index: 3)
        encoder.setFragmentBuffer(spectralHistory.gpuBuffer, offset: 0, index: 5)
        bindNoiseTextures(to: encoder)

        // Bind sampled stage outputs at texture(13)+.
        for (offset, sampleName) in stage.samples.enumerated() {
            guard let tex = textures[sampleName] else { continue }
            encoder.setFragmentTexture(tex,
                                       index: kStagedSampledTextureFirstSlot + offset)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}

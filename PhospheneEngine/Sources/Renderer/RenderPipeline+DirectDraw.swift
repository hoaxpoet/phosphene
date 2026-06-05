// RenderPipeline+DirectDraw — shared helpers for the direct-fragment draw path
// (full-res and the NB.8 half-res + upscale variant). Split out of
// RenderPipeline+Draw.swift to keep that file under the 400-line lint ceiling.

import Metal
import Shared

extension RenderPipeline {

    // MARK: - Direct-preset draw helpers (NB.8)

    // swiftlint:disable function_parameter_count

    /// Binds the audio buffers + per-preset slot-6/7/8 state + noise textures and
    /// draws the fullscreen direct-preset fragment (and any particles) into
    /// `encoder`. Shared by the full-res and half-res `drawDirect` paths so the
    /// binding contract stays in one place. (Slot-6 was AV.2.2's first direct
    /// consumer — `AuroraVeilState`; an unbound `[[buffer(6)]]` read crashes.)
    func encodePresetVisualization(
        into encoder: MTLRenderCommandEncoder,
        activePipeline: MTLRenderPipelineState,
        features: inout FeatureVector,
        stems stemFeatures: StemFeatures,
        particles: (any ParticleGeometry)?,
        textOverlay: DynamicTextOverlay?
    ) {
        encoder.setRenderPipelineState(activePipeline)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
        var stems = stemFeatures
        encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.size, index: 3)
        encoder.setFragmentBuffer(spectralHistory.gpuBuffer, offset: 0, index: 5)
        if let presetBuf = directPresetFragmentBufferLock.withLock({ directPresetFragmentBuffer }) {
            encoder.setFragmentBuffer(presetBuf, offset: 0, index: 6)
        }
        if let presetBuf2 = directPresetFragmentBuffer2Lock.withLock({ directPresetFragmentBuffer2 }) {
            encoder.setFragmentBuffer(presetBuf2, offset: 0, index: 7)
        }
        if let presetBuf3 = directPresetFragmentBuffer3Lock.withLock({ directPresetFragmentBuffer3 }) {
            encoder.setFragmentBuffer(presetBuf3, offset: 0, index: 8)
        }
        bindNoiseTextures(to: encoder)
        if let overlay = textOverlay {
            encoder.setFragmentTexture(overlay.texture, index: 12)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        particles?.render(encoder: encoder, features: features)
    }

    // swiftlint:enable function_parameter_count

    /// Lazily (re)allocates the half-res offscreen target for the direct path.
    /// Render-thread only (called from `drawDirect`). Re-creates only when the
    /// scaled dimensions change (drawable resize / scale change).
    func halfResTarget(drawableWidth: Int, drawableHeight: Int, scale: Float) -> MTLTexture? {
        let scaledW = max(Int(Float(drawableWidth) * scale), 1)
        let scaledH = max(Int(Float(drawableHeight) * scale), 1)
        if let tex = halfResTexture, halfResTextureSize == (scaledW, scaledH) { return tex }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat, width: scaledW, height: scaledH, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let tex = context.device.makeTexture(descriptor: desc)
        halfResTexture = tex
        halfResTextureSize = (scaledW, scaledH)
        return tex
    }
}

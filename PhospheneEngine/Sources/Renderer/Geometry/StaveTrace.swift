// StaveTrace — Stave's `ParticleGeometry` conformer: the Metal seam for the dispersion.
//
// A sibling, not a subclass (D-097). The whole model lives in `StaveDispersionModel`; this
// file uploads its curves and issues one fullscreen draw.
//
// Reads the engine's `waveformBuffer` directly — the same `.storageModeShared` buffer the
// fragment stages bind at slot 2, handed to the geometry so the band split can run on the CPU.
// That is the Meniscus precedent (MEN.2b, the FFT buffer handed to `MeniscusSurface`); no new
// engine surface, no protocol change.
//
// ⚠ The preset is `family: waveform` and for a long time did not read the waveform at all —
// it plotted an 8 s scrolling window of EMA-centred band energy, which is an envelope
// statistic, not a wave. Every stage of that pipeline removed life: 20 Hz decimation killed
// everything fast, EMA-centring removed level, soft saturation compressed the dynamics, and
// the window smeared what was left. Matt's M7 verdict was "deeply boring", and the cause was
// mechanical rather than cosmetic. This reads the actual signal, every frame.

import Metal
import Shared
import os.log

private let staveLogger = Logger(subsystem: "com.phosphene.renderer", category: "Stave")

// MARK: - GPU mirror

/// 32 bytes, all scalar floats — no vector members, so there is no alignment padding to get
/// wrong on either side. Field ORDER is the contract, not field names.
struct StaveUniformsGPU {
    var bandCount: Int32 = 0
    var sampleCount: Int32 = 0
    var thickness: Float = 0.010
    var fan: Float = 0
    var spacing: Float = 0.5
    var pad0: Float = 0
    var pad1: Float = 0
    var pad2: Float = 0
}

// MARK: - StaveTrace

public final class StaveTrace: ParticleGeometry, @unchecked Sendable {

    public let configuration: StaveConfiguration

    /// Protocol requirement (D-057 governor), unused: the whole preset is one fullscreen pass
    /// over a 1024-sample window. There is no particle count to throttle.
    public var activeParticleFraction: Float = 1.0

    /// The model. Exposed so harnesses and tests can drive and inspect it without a device.
    public let model: StaveDispersionModel

    /// Current spread, for harness evidence.
    public var fan: Float { model.fan }

    private let waveform: MTLBuffer
    private let curveBuffer: MTLBuffer
    private let colourBuffer: MTLBuffer
    private let pipeline: MTLRenderPipelineState?
    private var uniforms = StaveUniformsGPU()

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        waveform: MTLBuffer,
        configuration: StaveConfiguration,
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.configuration = configuration
        self.model = StaveDispersionModel(configuration: configuration)
        self.waveform = waveform

        let bands = StaveBandPlan.count
        guard let curves = device.makeBuffer(
                  length: bands * configuration.sampleCount * MemoryLayout<Float>.stride,
                  options: .storageModeShared),
              let colours = device.makeBuffer(
                  length: bands * MemoryLayout<SIMD4<Float>>.stride,
                  options: .storageModeShared) else {
            throw StaveError.bufferAllocationFailed
        }
        self.curveBuffer = curves
        self.colourBuffer = colours

        if let pixelFormat {
            guard let vertexFunction = library.makeFunction(name: "stave_disp_vertex"),
                  let fragmentFunction = library.makeFunction(name: "stave_disp_fragment") else {
                throw StaveError.functionNotFound("stave_disp")
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0]?.pixelFormat = pixelFormat
            self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } else {
            self.pipeline = nil
        }

        // Colours are fixed for the life of the preset — the mapping is physical, not animated.
        let colourPtr = colours.contents().bindMemory(to: SIMD4<Float>.self, capacity: bands)
        for (index, rgb) in model.colours.enumerated() {
            colourPtr[index] = SIMD4(rgb.x, rgb.y, rgb.z, 1)
        }
        uniforms.bandCount = Int32(bands)
        uniforms.sampleCount = Int32(configuration.sampleCount)
        uniforms.spacing = configuration.spacing

        staveLogger.info(
            "StaveTrace: \(bands)-band dispersion over \(configuration.sampleCount) samples")
    }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        // No compute encoder: the band split is ~8 prefix-sum passes over 1024 samples.
        // Advancing in the protocol's per-frame slot keeps the tick on the seam every other
        // particle preset uses, so the harnesses drive the identical path.
        let frames = waveform.length / (2 * MemoryLayout<Float>.stride)
        guard frames > 8 else { return }
        let base = waveform.contents().bindMemory(to: Float.self, capacity: frames * 2)
        model.advance(
            waveform: base,
            frames: frames,
            deltaTime: features.deltaTime,
            occupancy: features.waveformOccupancy
        )
        upload()
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let pipeline else { return }
        var local = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBuffer(curveBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(colourBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(&local, length: MemoryLayout<StaveUniformsGPU>.stride, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    // MARK: - Upload

    private func upload() {
        let count = model.curves.count
        let pointer = curveBuffer.contents().bindMemory(to: Float.self, capacity: count)
        model.curves.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            pointer.update(from: base, count: count)
        }
        uniforms.fan = model.fan
    }
}

// MARK: - Errors

public enum StaveError: Error, Sendable {
    case bufferAllocationFailed
    case functionNotFound(String)
}

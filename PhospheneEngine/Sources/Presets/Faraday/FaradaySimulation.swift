// FaradaySimulation — per-frame Swift–Hohenberg simulation driving the Faraday preset.
//
// The music drives a real pattern-forming PDE (see `FaradaySim.metal` for the
// physics and the numerics). The resulting field is bound at fragment texture(10)
// via `RenderPipeline.setRayMarchPresetHeightTexture`, where the preset's
// `sceneSDF` reads it as a liquid heightfield.
//
// Unlike Ferrofluid Ocean's one-shot bake (the other slot-10 consumer), this steps
// EVERY frame — the pattern is the music's behaviour, not a static topology.

import Foundation
import Metal
import simd
import Shared

/// Mirror of the MSL `FaradayConfig`. Keep the two in lockstep.
struct FaradayConfig {
    var width: UInt32 = 0
    var height: UInt32 = 0
    var frame: UInt32 = 0
    var dt: Float = 0
    var k0: Float = 0
    var drive: Float = 0
    var quad: Float = 0
    var noise: Float = 0
    var uMean: Float = 0
    var meanDamp: Float = 0
    var modeDepth: Float = 0
    var modeA: Float = 0
    var modeB: Float = 0
}

/// Swift–Hohenberg simulation of parametrically-driven surface waves.
public final class FaradaySimulation: @unchecked Sendable {

    // MARK: - Tunables

    /// Simulation grid. The field is toroidal, so the preset tiles it across the world.
    public static let gridWidth = 512
    public static let gridHeight = 512

    /// Integration step. Bounded by the cubic term (dt * 3u^2 < 2); with u clamped to
    /// 2.5 this leaves comfortable margin. Larger values let the grid-scale
    /// checkerboard mode win — that is instability, not physics.
    static let dt: Float = 0.05
    /// Substeps per frame. dt * substeps sets how fast pattern establishes after the
    /// drive crosses threshold; ~0.8 time units/frame reaches a formed lattice in
    /// well under a second, which is what a musically-responsive threshold needs.
    static let substeps = 16

    /// Quadratic term — selects cells over stripes.
    static let quad: Float = 0.62
    /// Thermal noise per substep. Small: at 0.004 it random-walks to the same
    /// amplitude as the pattern and the field reads as grain rather than cells.
    static let noise: Float = 0.00035
    /// Volume-conservation gain. Applied per substep against a mean measured LAST
    /// frame, so the per-frame product (gain * dt * substeps) must stay near 1.0 —
    /// a delayed feedback with gain >> 1 oscillates and drives the field to its clamp.
    static let meanDamp: Float = 1.0
    /// How strongly the plate mode gates the drive (large-scale figure).
    static let modeDepth: Float = 0.5

    /// A lattice needs TIME at a fixed wavelength to anneal into an ordered state.
    /// Feeding k0 straight from the audio re-selects the wavelength every frame and
    /// the pattern stays a defect-ridden mush, so it is smoothed hard.
    static let k0Alpha: Float = 0.012
    static let k0Min: Float = 0.15
    static let k0Range: Float = 0.15

    /// Drive mapping. Calibrated against REAL band ranges, not an assumed 0-1 (FA #31,
    /// the CR.1.1 lesson): `bass` sits around p50 0.27 / p95 0.67 on real music while
    /// `mid` p95 is ~0.09, so bass carries the range. The offset puts the Faraday
    /// THRESHOLD inside the music's real dynamics — quiet passages fall below it and
    /// the surface goes glassy, loud ones erupt into cells.
    static let driveOffset: Float = -0.13
    static let driveGain: Float = 1.25

    // MARK: - State

    private let device: MTLDevice
    private let lapPipeline: MTLComputePipelineState
    private let stepPipeline: MTLComputePipelineState
    private var texA: MTLTexture
    private var texB: MTLTexture
    private var readback: MTLBuffer

    private var k0Smoothed: Float = 0
    private var meanU: Float = 0
    private var frameIndex: UInt32 = 0

    /// The live field. `.r` is the surface amplitude the preset reads as height.
    public var heightTexture: MTLTexture { texA }

    // MARK: - Init

    public init?(device: MTLDevice, library: MTLLibrary) {
        guard let lapFn = library.makeFunction(name: "faraday_lap_pass"),
              let stepFn = library.makeFunction(name: "faraday_step_pass"),
              let lapPSO = try? device.makeComputePipelineState(function: lapFn),
              let stepPSO = try? device.makeComputePipelineState(function: stepFn)
        else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg32Float,
            width: Self.gridWidth,
            height: Self.gridHeight,
            mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared

        guard let front = device.makeTexture(descriptor: desc),
              let back = device.makeTexture(descriptor: desc),
              let meanBuffer = device.makeBuffer(
                length: Self.gridWidth * Self.gridHeight * 8,
                options: .storageModeShared)
        else { return nil }

        self.device = device
        self.lapPipeline = lapPSO
        self.stepPipeline = stepPSO
        self.texA = front
        self.texB = back
        self.readback = meanBuffer

        seed()
    }

    /// Seed a small random field. Below threshold it decays to a flat mirror anyway;
    /// above it, this is what the instability grows from.
    private func seed() {
        var values = [Float](repeating: 0, count: Self.gridWidth * Self.gridHeight * 2)
        var generator = SystemRandomNumberGenerator()
        for i in 0..<(Self.gridWidth * Self.gridHeight) {
            values[i * 2] = Float.random(in: -0.15...0.15, using: &generator)
        }
        values.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texA.replace(region: MTLRegionMake2D(0, 0, Self.gridWidth, Self.gridHeight),
                         mipmapLevel: 0,
                         withBytes: base,
                         bytesPerRow: Self.gridWidth * 8)
        }
    }

    // MARK: - Per-frame step

    /// Advance the simulation one frame, encoding into `commandBuffer`.
    ///
    /// - Parameters:
    ///   - features: live audio. Loudness drives the pattern across the Faraday
    ///     threshold; spectral centroid selects the cell size.
    public func step(commandBuffer: MTLCommandBuffer, features: FeatureVector) {
        // Loudness -> drive. Bass carries the dynamic range on real music.
        let loud = min(max(features.bass * 0.85 + features.mid * 0.55, 0), 1.6)
        let drive = Self.driveOffset + loud * Self.driveGain

        // Timbre -> wavelength. `spectral_centroid` occupies roughly 0.085-0.18 on
        // real music, so map THAT band rather than 0-1 (FA #31).
        let centroid = min(max((features.spectralCentroid - 0.085) / 0.095, 0), 1)
        let k0Target = Self.k0Min + centroid * Self.k0Range
        k0Smoothed = k0Smoothed == 0 ? k0Target
                                     : k0Smoothed + (k0Target - k0Smoothed) * Self.k0Alpha

        // Plate mode indices ride the timbre on a slow ladder, so the large-scale
        // FIGURE changes over musical time rather than per frame.
        let ladder = 2.0 + (centroid * 4.0).rounded()

        var cfg = FaradayConfig()
        cfg.width = UInt32(Self.gridWidth)
        cfg.height = UInt32(Self.gridHeight)
        cfg.frame = frameIndex
        cfg.dt = Self.dt
        cfg.k0 = k0Smoothed
        cfg.drive = drive
        cfg.quad = Self.quad
        cfg.noise = Self.noise
        cfg.uMean = meanU
        cfg.meanDamp = Self.meanDamp
        cfg.modeDepth = Self.modeDepth
        cfg.modeA = ladder
        cfg.modeB = ladder + 1

        let threadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let grid = MTLSize(width: (Self.gridWidth + 15) / 16,
                           height: (Self.gridHeight + 15) / 16,
                           depth: 1)

        for _ in 0..<Self.substeps {
            for computePipeline in [lapPipeline, stepPipeline] {
                guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
                encoder.setComputePipelineState(computePipeline)
                encoder.setBytes(&cfg, length: MemoryLayout<FaradayConfig>.stride, index: 0)
                encoder.setTexture(texA, index: 0)
                encoder.setTexture(texB, index: 1)
                encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: threadgroup)
                encoder.endEncoding()
                swap(&texA, &texB)
            }
        }

        frameIndex &+= 1
        measureMeanAsync(commandBuffer: commandBuffer)
    }

    /// Measure the field mean for the next frame's volume-conservation term.
    ///
    /// Read back on completion rather than blocking: the mean moves slowly compared
    /// with a frame, so one frame of latency is harmless, and stalling the GPU here
    /// would cost far more than the correction is worth.
    private func measureMeanAsync(commandBuffer: MTLCommandBuffer) {
        let source = texA
        let buffer = readback
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: Self.gridWidth, height: Self.gridHeight, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: Self.gridWidth * 8,
            destinationBytesPerImage: Self.gridWidth * Self.gridHeight * 8)
        blit.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            let count = Self.gridWidth * Self.gridHeight
            let pointer = buffer.contents().bindMemory(to: Float.self, capacity: count * 2)
            var total: Float = 0
            // Stride the grid rather than summing every cell — a uniform 1-in-8
            // sample estimates the mean to far better precision than the correction
            // needs, at an eighth of the CPU cost.
            var index = 0
            var samples: Float = 0
            while index < count {
                total += pointer[index * 2]
                samples += 1
                index += 8
            }
            self.meanU = samples > 0 ? total / samples : 0
        }
    }
}

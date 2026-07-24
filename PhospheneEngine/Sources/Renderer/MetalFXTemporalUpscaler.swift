// MetalFXTemporalUpscaler — MFX.1 temporal anti-aliasing for the ray-march path.
//
// WHY (BUG-071): a ray-marched fractal has unbounded sub-pixel detail. Sampled
// once per pixel per frame it aliases into shimmer/moiré under any camera motion
// — the defect that failed Fractal Fly-By's first live M7. The fix is temporal
// accumulation: jitter the camera by a sub-pixel offset each frame and let
// MetalFX reproject + blend the previous frames, so the detail resolves instead
// of boiling.
//
// WHY THIS IS VIABLE HERE (and was not for Nimbus at NB.8): MetalFX Temporal
// needs per-pixel motion vectors. A procedural *volume* has no surface to track,
// which is why NB.8 rejected it and shipped a bilinear half-res upscale instead.
// A ray-marched SDF does have a surface, and for an analytically-animated scene
// (Fractal Fly-By's scale descent) the previous-frame position of a hit point is
// a CLOSED FORM — so motion vectors are exact, not estimated. Presets opt in and
// supply `scenePrevPosition` (see PresetLoader+Preamble).
//
// MEASURED (MFX.1): the scaler costs ~8.5 ms at 1080p when run 1:1, which blows
// the 7 ms Tier-2 budget outright — temporal AA is NOT free. It only pays for
// itself when it also UPSCALES: the ray-march chain runs at `render_scale` of the
// display size (a quadratic saving on the expensive DE march) and MetalFX
// reconstructs to full resolution. That is exactly the §A8 design, and why
// `render_scale` is part of the contract rather than an optimization.

import Foundation
import Metal
import MetalFX
import os

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "MetalFXTemporal")

// MARK: - MetalFXTemporalUpscaler

/// Wraps `MTLFXTemporalScaler` with lazy (re)creation on size change and the
/// Halton jitter sequence that drives the temporal accumulation.
public final class MetalFXTemporalUpscaler {

    /// Pixel formats the scaler is configured for. These must match the textures
    /// handed to `encode` exactly or MetalFX raises at encode time.
    public static let colorFormat: MTLPixelFormat  = .rgba16Float
    public static let depthFormat: MTLPixelFormat  = .r32Float
    public static let motionFormat: MTLPixelFormat = .rg16Float

    private let device: MTLDevice
    private var scaler: MTLFXTemporalScaler?
    private var scalerWidth = 0
    private var scalerHeight = 0

    /// Frame counter driving the Halton jitter sequence.
    private var frameIndex: UInt32 = 0

    /// Set when history must be discarded (first frame, preset switch, resize).
    private var needsReset = true

    public init(device: MTLDevice) {
        self.device = device
    }

    /// True when this device supports temporal scaling at all.
    public static func isSupported(device: MTLDevice) -> Bool {
        MTLFXTemporalScalerDescriptor.supportsDevice(device)
    }

    /// Drop the accumulated history — call on preset switch or any discontinuity
    /// (a jump in the scene that reprojection cannot explain would otherwise
    /// smear across frames).
    public func reset() { needsReset = true }

    // MARK: Jitter

    /// Radical-inverse base-`base` Halton term.
    private static func halton(_ index: UInt32, _ base: UInt32) -> Float {
        var result: Float = 0
        var fraction: Float = 1
        var i = index
        while i > 0 {
            fraction /= Float(base)
            result += fraction * Float(i % base)
            i /= base
        }
        return result
    }

    /// Sub-pixel camera jitter for the CURRENT frame, in pixels, centred on 0.
    /// The G-buffer ray generation must apply this and the same value must be
    /// handed to `encode` — MetalFX uses it to undo the offset when reprojecting.
    public func currentJitter() -> SIMD2<Float> {
        // Halton(2,3) is the standard TAA sequence; index from 1 so frame 0 isn't
        // the degenerate (0,0) sample.
        let i = frameIndex &+ 1
        return SIMD2(Self.halton(i, 2) - 0.5, Self.halton(i, 3) - 0.5)
    }

    /// Advance the jitter sequence. Called once per rendered frame.
    public func advanceFrame() {
        frameIndex = (frameIndex &+ 1) % 64   // 64-frame cycle: long enough to resolve, short enough to stay coherent
    }

    // MARK: Encode

    private var scalerOutWidth = 0
    private var scalerOutHeight = 0

    private func ensureScaler(width: Int, height: Int,
                              outWidth: Int, outHeight: Int) -> MTLFXTemporalScaler? {
        if let scaler, scalerWidth == width, scalerHeight == height,
           scalerOutWidth == outWidth, scalerOutHeight == outHeight { return scaler }

        let desc = MTLFXTemporalScalerDescriptor()
        desc.inputWidth        = width
        desc.inputHeight       = height
        desc.outputWidth       = outWidth
        desc.outputHeight      = outHeight
        desc.colorTextureFormat  = Self.colorFormat
        desc.depthTextureFormat  = Self.depthFormat
        desc.motionTextureFormat = Self.motionFormat
        desc.outputTextureFormat = Self.colorFormat

        guard let made = desc.makeTemporalScaler(device: device) else {
            logger.error("MTLFXTemporalScaler creation failed at \(width)×\(height) — TAA disabled this session")
            scaler = nil
            return nil
        }
        // Depth is written normalized 0 (near) → 1 (far), not reversed-Z.
        made.isDepthReversed = false

        scaler = made
        scalerWidth = width
        scalerHeight = height
        scalerOutWidth = outWidth
        scalerOutHeight = outHeight
        needsReset = true
        logger.info("MTLFXTemporalScaler created \(width)×\(height) → \(outWidth)×\(outHeight)")
        return made
    }

    /// Encode one temporal resolve. `jitter` MUST be the same value the G-buffer
    /// used to offset its rays this frame.
    ///
    /// - Returns: true when the resolve was encoded; false when unsupported (the
    ///   caller should fall back to using the unresolved colour directly).
    public struct Inputs {
        public let color: MTLTexture
        public let depth: MTLTexture
        public let motion: MTLTexture
        public let output: MTLTexture
        public let jitter: SIMD2<Float>
        public init(color: MTLTexture, depth: MTLTexture, motion: MTLTexture,
                    output: MTLTexture, jitter: SIMD2<Float>) {
            self.color = color; self.depth = depth; self.motion = motion
            self.output = output; self.jitter = jitter
        }
    }

    @discardableResult
    public func encode(commandBuffer: MTLCommandBuffer, inputs: Inputs) -> Bool {
        let color = inputs.color, output = inputs.output
        guard let scaler = ensureScaler(
            width: color.width,
            height: color.height,
            outWidth: output.width,
            outHeight: output.height
        ) else { return false }

        scaler.colorTexture  = color
        scaler.depthTexture  = inputs.depth
        scaler.motionTexture = inputs.motion
        scaler.outputTexture = output
        // Motion is stored in NDC-ish units of the render target; scale to pixels.
        scaler.motionVectorScaleX = Float(color.width)
        scaler.motionVectorScaleY = Float(color.height)
        // MetalFX expects the jitter that was ADDED to the projection, negated.
        scaler.jitterOffsetX = -inputs.jitter.x
        scaler.jitterOffsetY = -inputs.jitter.y
        scaler.reset = needsReset
        needsReset = false

        scaler.encode(commandBuffer: commandBuffer)
        return true
    }
}

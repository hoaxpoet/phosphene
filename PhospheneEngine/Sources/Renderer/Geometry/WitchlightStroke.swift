// WitchlightStroke — the Witchlight ribbon's `ParticleGeometry` conformer.
//
// A sibling, not a subclass (D-097): it owns its bead buffer and its four render
// pipelines and does not parameterise a shared one. The motion model lives in
// `WitchlightPath` (pure CPU, unit-tested); this file is the Metal seam.
//
// Unlike its structural template Filigree, Witchlight runs NO compute pass — the trail is
// ~1024 beads on the CPU, which is cheaper to advance in Swift than to dispatch, and it
// has to be a Swift-side array anyway because the relaxation pass reads each bead's two
// neighbours. `update` advances the path and uploads; `render` issues the four draws.
//
// The trail lives in this ring buffer rather than in a feedback accumulator BY DESIGN
// (WITCHLIGHT_DESIGN §7.1): an accumulator trail would smear the beads and destroy the
// beads-on-a-thread register (trait #1), and it would make the record approximate where
// the concept needs it exact. `decay` is set low in the sidecar so the sky is redrawn
// each frame; the sky is a backdrop, not the trail mechanism. No `mv_warp`.

import Metal
import Shared
import os.log

private let witchlightLogger = Logger(subsystem: "com.phosphene.renderer", category: "Witchlight")

// MARK: - WLConfig (mirror of MSL `WLConfig`, 2 × uint + 17 × float = 76 bytes)

struct WLConfig {
    var beadCount: UInt32 = 0
    var frame: UInt32 = 0
    var trailSeconds: Float = 30
    var baseRadius: Float = 0.011
    var aspect: Float = 16.0 / 9.0
    var tumbleYaw: Float = 0
    var tumblePitch: Float = 0
    var tumbleRoll: Float = 0
    var centroidX: Float = 0
    var centroidY: Float = 0
    var viewScale: Float = 1
    var headX: Float = 0
    var headY: Float = 0
    var headZ: Float = 0
    var headR: Float = 1
    var headG: Float = 1
    var headB: Float = 1
    var flareIntensity: Float = 0
    var lineAlpha: Float = 0.34
    /// WL.4 — the per-frame energy breath, 0…1, centred ~0.5 at the track's own typical
    /// level. The ONLY continuous-energy coupling in the preset; see `energyBreath` below.
    var energyBreath: Float = 0.5
}

// MARK: - Configuration

public struct WitchlightConfiguration: Sendable {
    /// Bead ring capacity. 30 s × 34 Hz ≈ 1020 (WITCHLIGHT_DESIGN §3.3).
    public var beadCapacity: Int
    /// Bead radius at emission, as a fraction of HALF the frame height (screen-space, not
    /// world-space — see `wl_screen_extent`). 0.011 ≈ a 12 px bead at 1080p, which is the
    /// scale the beads read at in the register anchor `00`.
    public var baseRadius: Float
    /// Alpha of the connecting thread relative to the beads.
    public var lineAlpha: Float
    public var tuning: WitchlightTuning

    public init(
        beadCapacity: Int = 1024,
        baseRadius: Float = 0.011,   // 1.1% of frame height — the source's bead size (WL.2-f)

        lineAlpha: Float = 0.34,
        tuning: WitchlightTuning = WitchlightTuning()
    ) {
        self.beadCapacity = beadCapacity
        self.baseRadius = baseRadius
        self.lineAlpha = lineAlpha
        self.tuning = tuning
    }
}

// MARK: - WitchlightStroke

public final class WitchlightStroke: ParticleGeometry, @unchecked Sendable {

    public let configuration: WitchlightConfiguration

    /// Protocol requirement (D-057 governor), unused: the trail is an exact record of
    /// where the pen has been, so it cannot skip a fraction of its beads without putting
    /// holes in the drawing. 1024 beads is far inside budget at any quality level.
    public var activeParticleFraction: Float = 1.0

    /// The motion model. Exposed so tests and the app-layer track-change hook can reach
    /// `reset()` / `ingestStructure(_:)` and the §3.1(b) clamp instrumentation.
    public let path: WitchlightPath

    private let beadBuffer: MTLBuffer
    private let suppressPipeline: MTLRenderPipelineState?
    private let linePipeline: MTLRenderPipelineState?
    private let beadPipeline: MTLRenderPipelineState?
    private let flarePipeline: MTLRenderPipelineState?

    private var config: WLConfig
    private var frameCounter: UInt32 = 0

    private var uploadedBeadCount = 0

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: WitchlightConfiguration = .init(),
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.configuration = configuration
        self.path = WitchlightPath(tuning: configuration.tuning)
        var initial = WLConfig()
        initial.trailSeconds = configuration.tuning.trailSeconds
        initial.baseRadius = configuration.baseRadius
        initial.lineAlpha = configuration.lineAlpha
        self.config = initial

        let bytes = configuration.beadCapacity * MemoryLayout<WitchlightBead>.stride
        guard let buffer = device.makeBuffer(length: bytes, options: .storageModeShared) else {
            throw WitchlightError.bufferAllocationFailed
        }
        self.beadBuffer = buffer

        if let pixelFormat {
            let factory = PipelineFactory(device: device, library: library, pixelFormat: pixelFormat)
            self.suppressPipeline = try factory.make(prefix: "witchlight_suppress", blend: .darken)
            self.linePipeline = try factory.make(prefix: "witchlight_line", blend: .additive)
            self.beadPipeline = try factory.make(prefix: "witchlight_bead", blend: .additive)
            self.flarePipeline = try factory.make(prefix: "witchlight_flare", blend: .additive)
        } else {
            self.suppressPipeline = nil
            self.linePipeline = nil
            self.beadPipeline = nil
            self.flarePipeline = nil
        }
        witchlightLogger.info(
            "WitchlightStroke: \(configuration.beadCapacity) beads, trail \(configuration.tuning.trailSeconds) s")
    }

    // MARK: - Pipelines

    private enum BlendMode { case additive, darken }

    /// Builds the four `witchlight_*` pipelines. The device/library/format triple is held
    /// here rather than threaded through every call so the factory stays inside the
    /// parameter-count lint and the four call sites read as a list of passes.
    private struct PipelineFactory {
        let device: MTLDevice
        let library: MTLLibrary
        let pixelFormat: MTLPixelFormat

        /// `prefix` names a `<prefix>_vertex` / `<prefix>_fragment` pair.
        func make(prefix: String, blend: BlendMode) throws -> MTLRenderPipelineState {
            guard let vertexFunction = library.makeFunction(name: "\(prefix)_vertex"),
                  let fragmentFunction = library.makeFunction(name: "\(prefix)_fragment") else {
                throw WitchlightError.functionNotFound(prefix)
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            guard let attachment = descriptor.colorAttachments[0] else {
                throw WitchlightError.functionNotFound("\(prefix): colorAttachments[0]")
            }
            attachment.pixelFormat = pixelFormat
            attachment.isBlendingEnabled = true
            switch blend {
            case .additive:
                // Emissive: light adds to whatever is behind it.
                attachment.sourceRGBBlendFactor = .one
                attachment.destinationRGBBlendFactor = .one
            case .darken:
                // dst *= (1 - src.a). Removes light without adding any — the star-suppression
                // depth cue (trait #6).
                attachment.sourceRGBBlendFactor = .zero
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            }
            attachment.sourceAlphaBlendFactor = .zero
            attachment.destinationAlphaBlendFactor = .one
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
    }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        // No compute encoder: the whole simulation is 1024 CPU beads. Advancing here (the
        // protocol's per-frame compute slot) keeps the tick on the same seam every other
        // particle preset uses, so the harnesses drive the identical path.
        path.advance(deltaTime: features.deltaTime, features: features, stems: stemFeatures)
        frameCounter &+= 1
        upload(features: features)
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard uploadedBeadCount > 0 else { return }
        var cfg = config

        // 1. Star suppression — the ribbon occludes the field before anything is added.
        if let state = suppressPipeline {
            encoder.setRenderPipelineState(state)
            encoder.setVertexBuffer(beadBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&cfg, length: MemoryLayout<WLConfig>.stride, index: 1)
            encoder.drawPrimitives(
                type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: uploadedBeadCount)
        }
        // 2. The thread.
        if let state = linePipeline, uploadedBeadCount >= 2 {
            encoder.setRenderPipelineState(state)
            encoder.setVertexBuffer(beadBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&cfg, length: MemoryLayout<WLConfig>.stride, index: 1)
            encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: uploadedBeadCount)
        }
        // 3. The beads.
        if let state = beadPipeline {
            encoder.setRenderPipelineState(state)
            encoder.setVertexBuffer(beadBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&cfg, length: MemoryLayout<WLConfig>.stride, index: 1)
            encoder.drawPrimitives(
                type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: uploadedBeadCount)
        }
        // 4. The head flare — skipped entirely when it is not lit, so an unfired frame
        //    costs nothing and cannot contribute stray luminance.
        if let state = flarePipeline, cfg.flareIntensity > 0.002 {
            encoder.setRenderPipelineState(state)
            encoder.setVertexBytes(&cfg, length: MemoryLayout<WLConfig>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    // MARK: - Upload

    private func upload(features: FeatureVector) {
        let beads = path.beads
        let count = min(beads.count, configuration.beadCapacity)
        uploadedBeadCount = count
        if count > 0 {
            let pointer = beadBuffer.contents()
                .bindMemory(to: WitchlightBead.self, capacity: configuration.beadCapacity)
            beads.suffix(count).enumerated().forEach { pointer[$0.offset] = $0.element }
        }
        config.beadCount = UInt32(count)
        config.frame = frameCounter
        config.trailSeconds = path.trailWindow
        config.baseRadius = configuration.baseRadius
        config.lineAlpha = configuration.lineAlpha
        config.energyBreath = path.energyBreath
        config.aspect = features.aspectRatio > 0.05 ? features.aspectRatio : 16.0 / 9.0
        config.tumbleYaw = path.tumbleYaw
        config.tumblePitch = path.tumblePitch
        config.tumbleRoll = path.tumbleRoll
        config.centroidX = path.cameraX
        config.centroidY = path.cameraY
        config.viewScale = path.viewScale
        config.flareIntensity = path.flareIntensity
        if let head = beads.last {
            config.headX = head.posX
            config.headY = head.posY
            config.headZ = head.posZ
            config.headR = head.colR
            config.headG = head.colG
            config.headB = head.colB
        }
    }
}

// MARK: - Errors

public enum WitchlightError: Error, Sendable {
    case bufferAllocationFailed
    case functionNotFound(String)
}

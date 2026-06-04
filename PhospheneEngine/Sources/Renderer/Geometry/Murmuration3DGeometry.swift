// Murmuration3DGeometry — the 3D version of the proven parametric-ellipse flock.
//
// Drives `Murmuration3D.metal`: the 40-round 2D Murmuration architecture
// (Particles.metal — birds spring-pulled to home slots in a morphing ellipse,
// dense and framed by construction) lifted into 3D with perspective depth and
// real banking. A `ParticleGeometry` sibling (D-097) — owns its own M3DParticle
// layout + `murmuration3d_*` kernels rather than parameterising ProceduralGeometry
// or the (retired) emergent Flock2. See `docs/presets/MURMURATION_DESIGN.md`.

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "Murmuration3D")

// MARK: - M3DParticle (mirror of MSL `M3DParticle`, 64 bytes)

/// Scalar floats (not SIMD) so the layout matches the MSL `packed_float3` members
/// byte-for-byte. `bank` is the signed banking that drives the dark-band shading.
@frozen
public struct M3DParticle: Sendable {
    public var positionX: Float; public var positionY: Float; public var positionZ: Float
    public var life: Float
    public var velocityX: Float; public var velocityY: Float; public var velocityZ: Float
    public var size: Float
    public var colorR: Float; public var colorG: Float; public var colorB: Float; public var colorA: Float
    public var seed: Float
    public var age: Float
    public var bank: Float
    // swiftlint:disable:next identifier_name
    public var _pad: Float

    public init() {
        positionX = 0; positionY = 0; positionZ = 0; life = 0
        velocityX = 0; velocityY = 0; velocityZ = 0; size = 1
        colorR = 0; colorG = 0; colorB = 0; colorA = 1
        seed = 0; age = 0; bank = 0; _pad = 0
    }
}

// MARK: - M3DConfig (mirror of MSL `M3DConfig`, 32 bytes)

struct M3DConfig {
    var particleCount: UInt32
    var drag: Float
    var camDist: Float
    var camPitch: Float
    var time: Float
    var viewScale: Float
    var motionPhase: Float    // vigor-paced morph clock (integrated CPU-side)
    var energyEnv: Float      // smoothed music energy → vigor + swell + drift range
    var beatEnv: Float        // smoothed beat pulse → agitation wave + squash
    var vocalEnv: Float       // smoothed vocals → density breathing
    // swiftlint:disable:next identifier_name
    var _pad0: Float
    // swiftlint:disable:next identifier_name
    var _pad1: Float
}

// MARK: - Configuration

public struct Murmuration3DConfiguration: Sendable {
    public var particleCount: Int
    public var drag: Float          // velocity damping (matches the proven 2D `1 − 3·dt`)
    public var camDist: Float       // perspective camera distance (world units)
    public var camPitch: Float      // downward look angle (rad) — shows the 3D volume
    public var viewScale: Float     // screen zoom so the flock fills the frame

    public init(
        particleCount: Int = 14_000,
        drag: Float = 3.0,
        camDist: Float = 3.2,        // camera further back (Matt 2026-06-04: room to traverse)
        camPitch: Float = 0.35,
        viewScale: Float = 1.05      // zoomed out → room for the energy-swelled flock to roam
    ) {
        self.particleCount = particleCount
        self.drag = drag
        self.camDist = camDist
        self.camPitch = camPitch
        self.viewScale = viewScale
    }
}

// MARK: - Murmuration3DGeometry

public final class Murmuration3DGeometry: ParticleGeometry, @unchecked Sendable {

    public let particleBuffer: MTLBuffer
    public let configuration: Murmuration3DConfiguration

    /// D-057 governor gate. At ~6 K the preset is cheap enough that the governor
    /// never throttles it, so the controlled flock never loses birds.
    public var activeParticleFraction: Float = 1.0

    // ── Music envelopes (smoothed CPU-side; the global-envelope coupling) ──
    private var motionPhase: Double = 0   // vigor-paced morph clock (Double: no long-run drift)
    private var energyEnv: Float = 0      // smoothed music energy
    private var beatEnv: Float = 0        // smoothed beat pulse
    private var vocalEnv: Float = 0       // smoothed vocals

    private let computePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState?

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: Murmuration3DConfiguration = .init(),
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.configuration = configuration
        let count = configuration.particleCount
        let stride = MemoryLayout<M3DParticle>.stride
        guard let buf = device.makeBuffer(length: count * stride, options: .storageModeShared) else {
            throw Murmuration3DError.bufferAllocationFailed
        }
        self.particleBuffer = buf
        Self.seed(into: buf, count: count)

        guard let fn = library.makeFunction(name: "murmuration3d_update") else {
            throw Murmuration3DError.functionNotFound("murmuration3d_update")
        }
        self.computePipeline = try device.makeComputePipelineState(function: fn)

        if let pixelFormat {
            guard let vfn = library.makeFunction(name: "murmuration3d_vertex"),
                  let ffn = library.makeFunction(name: "murmuration3d_fragment") else {
                throw Murmuration3DError.functionNotFound("murmuration3d_vertex/fragment")
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = pixelFormat
            // Dark silhouettes over the sky — alpha-blend RGB, pin dst alpha = 1.
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .zero
            desc.colorAttachments[0].destinationAlphaBlendFactor = .one
            self.renderPipeline = try device.makeRenderPipelineState(descriptor: desc)
        } else {
            self.renderPipeline = nil
        }
        logger.info("Murmuration3DGeometry: \(count) birds (3D parametric-ellipse flock)")
    }

    /// Deterministic seed: a small 3D cloud near the origin with a light tangential
    /// swirl, so the flock settles into its ellipsoid quickly and reproducibly.
    private static func seed(into buffer: MTLBuffer, count: Int) {
        let ptr = buffer.contents().bindMemory(to: M3DParticle.self, capacity: count)
        var rng: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float((rng >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        for i in 0..<count {
            var bird = M3DParticle()
            let az = next() * 2 * .pi
            let el = acos(2 * next() - 1)
            let rad = 0.25 * powf(next(), 1.0 / 3.0)
            bird.positionX = rad * sinf(el) * cosf(az)
            bird.positionY = rad * sinf(el) * sinf(az) * 0.6
            bird.positionZ = rad * cosf(el)
            bird.velocityX = -bird.positionZ * 0.3
            bird.velocityZ = bird.positionX * 0.3
            bird.life = 1
            bird.seed = Float(i) / Float(count)
            ptr[i] = bird
        }
    }

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        guard let enc = commandBuffer.makeComputeCommandEncoder() else {
            logger.error("Murmuration3D.update: encoder failed"); return
        }
        advanceEnvelopes(features: features, stems: stemFeatures)
        var cfg = makeConfig(time: features.time)
        var feat = features
        var stems = stemFeatures
        enc.setComputePipelineState(computePipeline)
        enc.setBuffer(particleBuffer, offset: 0, index: 0)
        enc.setBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 1)
        enc.setBytes(&cfg, length: MemoryLayout<M3DConfig>.stride, index: 2)
        enc.setBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 3)
        // All birds integrate every frame (a flock is coupled — never freeze a
        // fraction; cf. the round-5 governor-freeze lesson). At 6 K it fits budget.
        let tg = min(computePipeline.maxTotalThreadsPerThreadgroup, 256)
        enc.dispatchThreadgroups(
            MTLSize(width: (configuration.particleCount + tg - 1) / tg, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: tg, height: 1, depth: 1))
        enc.endEncoding()
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let state = renderPipeline else { return }
        var cfg = makeConfig(time: features.time)
        encoder.setRenderPipelineState(state)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&cfg, length: MemoryLayout<M3DConfig>.stride, index: 2)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: configuration.particleCount)
    }

    // MARK: - Music envelopes

    /// Advance the smoothed music envelopes that drive the global coupling. Computing
    /// them once CPU-side (rather than per-bird in the shader) keeps the response
    /// coherent and lets us low-pass without per-particle state. Tuned against the
    /// measured driver ranges (stem energies ~0.3 mean / ~0.7 p99; drumsBeat a clean
    /// 0→1 pulse) so the response is sized to real music, not input = 1.0.
    private func advanceEnvelopes(features: FeatureVector, stems: StemFeatures) {
        var dt = features.deltaTime
        if !(dt > 0) { dt = 1.0 / 60.0 }
        dt = min(dt, 1.0 / 30.0)

        // Continuous music energy: stems when present, else the full-mix fallback.
        let stemTotal = stems.drumsEnergy + stems.bassEnergy + stems.otherEnergy + stems.vocalsEnergy
        let blend = Self.smoothstep(0.02, 0.06, stemTotal)
        let stemEnergy = (stems.drumsEnergy + stems.bassEnergy + stems.otherEnergy) / 3 + 0.4 * stems.vocalsEnergy
        let fullEnergy = (features.bass + features.mid) * 0.5
        let rawEnergy = fullEnergy + (stemEnergy - fullEnergy) * blend
        let rawBeat   = features.beatBass + (stems.drumsBeat - features.beatBass) * blend
        let rawVocal  = stems.vocalsEnergy * blend

        // EMAs: alpha = dt / (tau + dt).
        energyEnv += Float(dt / (0.45 + dt)) * (rawEnergy - energyEnv)
        vocalEnv += Float(dt / (0.50 + dt)) * (rawVocal - vocalEnv)
        // Beat: fast attack so each hit reads, slower release so the band sweeps as it decays.
        let beatAlpha = rawBeat > beatEnv ? dt / (0.02 + dt) : dt / (0.14 + dt)
        beatEnv += Float(beatAlpha) * (rawBeat - beatEnv)

        // Vigor-paced morph clock: energetic → faster churn/wheel/drift, calm → slower.
        let energyNorm = max(0, min(1.3, (energyEnv - 0.18) / 0.45))
        let vigorSpeed = 0.55 + 0.85 * energyNorm
        motionPhase += Double(dt) * 0.7 * 1.2 * Double(vigorSpeed)
    }

    private func makeConfig(time: Float) -> M3DConfig {
        M3DConfig(
            particleCount: UInt32(configuration.particleCount),
            drag: configuration.drag,
            camDist: configuration.camDist,
            camPitch: configuration.camPitch,
            time: time,
            viewScale: configuration.viewScale,
            motionPhase: Float(motionPhase),
            energyEnv: energyEnv,
            beatEnv: beatEnv,
            vocalEnv: vocalEnv,
            _pad0: 0,
            _pad1: 0)
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let tn = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return tn * tn * (3 - 2 * tn)
    }
}

// MARK: - Errors

public enum Murmuration3DError: Error, Sendable {
    case bufferAllocationFailed
    case functionNotFound(String)
}

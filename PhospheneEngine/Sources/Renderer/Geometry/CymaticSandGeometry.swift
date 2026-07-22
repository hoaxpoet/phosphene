// CymaticSandGeometry — vibrating-sand Chladni simulation (CR.2 rebuild).
//
// A `ParticleGeometry` sibling (D-097), modelled on `PhysarumGeometry`: owns its
// grain buffer, per-cell deposit accumulator, ping-pong r16Float density textures,
// and the `sand_*` pipelines. Per frame: reset → grains (vibration-driven random
// walk on the plate field, deposit) → diffuse → display the glowing sand density.
//
// The music envelopes live here (CPU-side), folding in the CR mode-ladder + hue
// logic: brightness (`spectral_centroid`, deviation-blend) picks the mode; loudness
// scales the vibration; a `bass_dev` beat is a burst; harmony (`tonal_phase_fifths`)
// rotates the hue. See CymaticSand.metal for the kernels and `docs/DECISIONS.md`
// (the CR.2 rebuild) for the phenomenon-not-figure rationale.

import Metal
import Shared
import os.log

private let sandLogger = Logger(subsystem: "com.phosphene.renderer", category: "CymaticSand")

// MARK: - SandConfig (mirror of MSL `SandConfig`, 56 bytes: 4×uint + 10×float)

struct SandConfig {
    var width: UInt32
    var height: UInt32
    var grainCount: UInt32
    var frame: UInt32
    var ladderPos: Float
    var vibAmp: Float
    var beatBurst: Float
    var gradientDrift: Float
    var minWalk: Float
    var decay: Float
    var depositF: Float
    var energyEnv: Float
    var hueOffset: Float
    var aspect: Float   // drawable w/h for the display cover-fit
}

// MARK: - SandGrain (mirror of MSL `SandGrain`, 16 bytes)

@frozen
public struct SandGrain: Sendable {
    public var posX: Float
    public var posY: Float
    public var age: Float
    public var pad: Float
}

// MARK: - Configuration

public struct CymaticSandConfiguration: Sendable {
    public var width: Int
    public var height: Int
    public var grainCount: Int
    public var vibAmp: Float          // baseline vibration step (px) at unit amp·drive
    public var gradientDrift: Float   // px/frame drift toward the node (crisp lines)
    public var minWalk: Float         // stochastic floor (px)
    public var decay: Float           // density-texture persistence
    public var depositF: Float

    public init(
        width: Int = 720,
        height: Int = 720,
        grainCount: Int = 400_000,
        vibAmp: Float = 2.9,
        gradientDrift: Float = 3.1,   // CR.2.3: faster settle → a hit reads as a crisp pulse, not a smear
        minWalk: Float = 0.10,
        decay: Float = 0.22,          // CR.2.3: less density persistence → sharper response
        depositF: Float = 0.55        // compensate the faster decay so lines stay bright
    ) {
        self.width = width
        self.height = height
        self.grainCount = grainCount
        self.vibAmp = vibAmp
        self.gradientDrift = gradientDrift
        self.minWalk = minWalk
        self.decay = decay
        self.depositF = depositF
    }
}

// MARK: - CymaticSandGeometry

public final class CymaticSandGeometry: ParticleGeometry, @unchecked Sendable {

    public let configuration: CymaticSandConfiguration
    public var activeParticleFraction: Float = 1.0   // coupled field; all grains every frame

    public let grainBuffer: MTLBuffer
    private let accumBuffer: MTLBuffer
    private let density: [MTLTexture]   // 2× r16Float, ping-pong
    private var cur = 0

    private let resetPipeline: MTLComputePipelineState
    private let grainsPipeline: MTLComputePipelineState
    private let diffusePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState?

    // Music envelopes.
    private var energyEnv: Float = 0
    private var beatEnv: Float = 0
    private var centroidEMA: Float = 0
    private var slowCentroid: Float = 0
    private var ladderSmooth: Float = 0
    private var energyForGate: Float = 0
    private var sinT: Float = 0
    private var cosT: Float = 0
    private var hueOffset: Float = 0
    private var modeWanderPhase: Float = 0   // CR.2.1 beat/energy-driven mode variety
    private var prevBeatEnv: Float = 0       // CR.2.2 beat-edge detect for the mode kick
    private var ladderFinal: Float = 0
    private var frameCounter: UInt32 = 0

    // CR.2.1 mode-wander (M7: "highly repetitive, cycling between 2 patterns once the
    // full band kicks in"). Centroid barely varies on real tracks (Hummer: same
    // 0.08–0.17 band loud or quiet), so beats + energy drive a continuous wander
    // AROUND the centroid baseline — the figure keeps stepping through varied modes
    // when the music is busy. Two incommensurate sines so it never obviously repeats.
    private static let wanderAmp: Float = 4.4         // ± rungs of wander (CR.2.2: 3.6→4.4, more variety)
    private static let wanderBaseDrift: Float = 0.16  // slow floor so it never locks
    private static let wanderEnergyDrift: Float = 0.9 // loud → faster wander
    private static let wanderBeatDrift: Float = 1.3   // beaty → faster wander
    /// CR.2.2 (M7 "more variety; connection feels loose") — each beat STEPS the mode
    /// wander forward, so the figure visibly changes ON the beat (variety tied to the
    /// music, tighter connection) rather than only drifting autonomously.
    private static let wanderBeatKick: Float = 0.5

    // Ladder / mapping constants (mirror CymaticResonanceState / D-197).
    private static let ladderCount = 11
    private static let centroidTau: Float = 0.5
    private static let baselineTau: Float = 12.0
    private static let centroidDevGain: Float = 12.0
    private static let absLo: Float = 0.05
    private static let absHi: Float = 0.30
    private static let adaptiveWeight: Float = 0.7
    private static let hueTau: Float = 1.5

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: CymaticSandConfiguration = .init(),
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.configuration = configuration
        let cells = configuration.width * configuration.height

        let grainBytes = configuration.grainCount * MemoryLayout<SandGrain>.stride
        guard let grains = device.makeBuffer(length: grainBytes, options: .storageModeShared) else {
            throw CymaticSandError.bufferAllocationFailed
        }
        self.grainBuffer = grains
        Self.seed(into: grains, configuration: configuration)

        guard let accum = device.makeBuffer(length: cells * MemoryLayout<UInt32>.stride,
                                             options: .storageModeShared) else {
            throw CymaticSandError.bufferAllocationFailed
        }
        self.accumBuffer = accum

        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float, width: configuration.width, height: configuration.height, mipmapped: false)
        td.usage = [.shaderRead, .shaderWrite]
        td.storageMode = .shared
        var textures: [MTLTexture] = []
        for _ in 0..<2 {
            guard let tex = device.makeTexture(descriptor: td) else { throw CymaticSandError.textureAllocationFailed }
            textures.append(tex)
        }
        self.density = textures
        Self.zero(textures: textures, width: configuration.width, height: configuration.height)

        func compute(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else { throw CymaticSandError.functionNotFound(name) }
            return try device.makeComputePipelineState(function: fn)
        }
        self.resetPipeline = try compute("sand_reset")
        self.grainsPipeline = try compute("sand_grains")
        self.diffusePipeline = try compute("sand_diffuse")

        if let pixelFormat {
            guard let vfn = library.makeFunction(name: "fullscreen_vertex"),
                  let ffn = library.makeFunction(name: "sand_density_fragment") else {
                throw CymaticSandError.functionNotFound("fullscreen_vertex/sand_density_fragment")
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = pixelFormat
            self.renderPipeline = try device.makeRenderPipelineState(descriptor: desc)
        } else {
            self.renderPipeline = nil
        }
        sandLogger.info("CymaticSand: \(configuration.grainCount) grains, \(configuration.width)×\(configuration.height)")
    }

    // Diagnostics for the sketch tests.
    public var currentEnergyEnv: Float { energyEnv }
    public var currentLadderPos: Float { ladderSmooth }
    public var currentBeatEnv: Float { beatEnv }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        advanceEnvelopes(features: features, stems: stemFeatures)
        frameCounter &+= 1
        var cfg = makeConfig()

        guard let enc = commandBuffer.makeComputeCommandEncoder() else {
            sandLogger.error("CymaticSand.update: encoder failed"); return
        }
        let src = density[cur], dst = density[1 - cur]
        let cellCount = configuration.width * configuration.height

        enc.setComputePipelineState(resetPipeline)
        enc.setBuffer(accumBuffer, offset: 0, index: 0)
        enc.setBytes(&cfg, length: MemoryLayout<SandConfig>.stride, index: 1)
        dispatch1D(enc, count: cellCount, pipeline: resetPipeline)
        enc.memoryBarrier(scope: .buffers)

        enc.setComputePipelineState(grainsPipeline)
        enc.setBuffer(grainBuffer, offset: 0, index: 0)
        enc.setBytes(&cfg, length: MemoryLayout<SandConfig>.stride, index: 1)
        enc.setBuffer(accumBuffer, offset: 0, index: 2)
        dispatch1D(enc, count: configuration.grainCount, pipeline: grainsPipeline)
        enc.memoryBarrier(scope: .buffers)

        enc.setComputePipelineState(diffusePipeline)
        enc.setBytes(&cfg, length: MemoryLayout<SandConfig>.stride, index: 0)
        enc.setBuffer(accumBuffer, offset: 0, index: 1)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        let tpg = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(
            width: (configuration.width + 15) / 16,
            height: (configuration.height + 15) / 16,
            depth: 1)
        enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tpg)
        enc.endEncoding()

        cur = 1 - cur
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let state = renderPipeline else { return }
        var cfg = makeConfig()
        cfg.aspect = max(features.aspectRatio, 0.01)   // display cover-fit (CR.2.4)
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(&cfg, length: MemoryLayout<SandConfig>.stride, index: 0)
        encoder.setFragmentTexture(density[cur], index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// Reset envelopes at track change so the plate settles into the new track.
    public func reset() {
        energyEnv = 0; beatEnv = 0
        centroidEMA = 0; slowCentroid = 0; ladderSmooth = 0; energyForGate = 0
        sinT = 0; cosT = 0; hueOffset = 0
        modeWanderPhase = 0; prevBeatEnv = 0; ladderFinal = 0
    }

    // MARK: - Music envelopes

    private func advanceEnvelopes(features: FeatureVector, stems: StemFeatures) {
        var dt = features.deltaTime
        if !(dt > 0) { dt = 1.0 / 60.0 }
        dt = min(dt, 1.0 / 30.0)

        // Energy (vibration drive): stems when present, full-mix fallback (Physarum recipe).
        let stemTotal = stems.drumsEnergy + stems.bassEnergy + stems.otherEnergy + stems.vocalsEnergy
        let blend = Self.smoothstep(0.02, 0.06, stemTotal)
        let stemEnergy = (stems.drumsEnergy + stems.bassEnergy + stems.otherEnergy) / 3 + 0.4 * stems.vocalsEnergy
        let fullEnergy = (features.bass + features.mid) * 0.5
        let rawEnergy = fullEnergy + (stemEnergy - fullEnergy) * blend
        energyEnv += Float(dt / (0.18 + dt)) * (rawEnergy - energyEnv)   // CR.2.3: faster (was 0.25)
        energyForGate += Float(dt / (0.20 + dt)) * (stemTotal - energyForGate)

        // Beat burst — fast transient of bass_dev (+ drums stem dev), grains jump.
        let hitRaw = max(features.bassDev, 0.8 * stems.drumsEnergyDev * blend)
        let hitAlpha = hitRaw > beatEnv ? dt / (0.012 + dt) : dt / (0.14 + dt)
        beatEnv += Float(hitAlpha) * (hitRaw - beatEnv)

        // Brightness → mode ladder (CR.1.1/D-197 deviation-blend).
        let centroid = min(max(features.spectralCentroid, 0), 1)
        centroidEMA += (centroid - centroidEMA) * coeff(dt, Self.centroidTau)
        slowCentroid += (centroidEMA - slowCentroid) * coeff(dt, Self.baselineTau)
        let adaptNorm = min(max(0.5 + (centroidEMA - slowCentroid) * Self.centroidDevGain, 0), 1)
        let absNorm = min(max((centroidEMA - Self.absLo) / (Self.absHi - Self.absLo), 0), 1)
        let ladderNorm = adaptNorm * Self.adaptiveWeight + absNorm * (1 - Self.adaptiveWeight)
        let silenceGate = Self.smoothstep(0.0, 0.04, energyForGate)
        let ladderTarget = ladderNorm * Float(Self.ladderCount - 1) * silenceGate
        ladderSmooth += (ladderTarget - ladderSmooth) * coeff(dt, 0.8)

        // CR.2.1 mode wander — beats + energy keep the figure moving through varied
        // modes even when the centroid (and so ladderSmooth) is stable. Gated by the
        // silence gate so silence rests on the fundamental.
        // Beat kick — a beat rising edge steps the mode forward (variety tied to the beat).
        if beatEnv > 0.5 && prevBeatEnv <= 0.5 { modeWanderPhase += Self.wanderBeatKick }
        prevBeatEnv = beatEnv
        let driftRate = Self.wanderBaseDrift + Self.wanderEnergyDrift * energyEnv
                      + Self.wanderBeatDrift * beatEnv
        modeWanderPhase += dt * driftRate
        // Three incommensurate sines → visits more modes without an obvious cycle.
        let wander = Self.wanderAmp * (0.5 * sin(modeWanderPhase)
                                       + 0.3 * sin(modeWanderPhase * 1.7 + 1.3)
                                       + 0.2 * sin(modeWanderPhase * 2.6 + 0.4)) * silenceGate
        ladderFinal = min(max(ladderSmooth + wander, 0), Float(Self.ladderCount - 1))

        // Harmony → hue (circular smoothing).
        let tonal = features.tonalPhaseFifths
        let hueCoeff = coeff(dt, Self.hueTau)
        sinT += (sin(tonal) - sinT) * hueCoeff
        cosT += (cos(tonal) - cosT) * hueCoeff
        hueOffset = atan2(sinT, cosT) / (2 * .pi) + 0.5
    }

    private func makeConfig() -> SandConfig {
        SandConfig(
            width: UInt32(configuration.width),
            height: UInt32(configuration.height),
            grainCount: UInt32(configuration.grainCount),
            frame: frameCounter,
            ladderPos: ladderFinal,
            vibAmp: configuration.vibAmp,
            beatBurst: min(beatEnv, 2.4),   // CR.2.3: strong bass hits (bassDev up to ~3.9) throw harder
            gradientDrift: configuration.gradientDrift,
            minWalk: configuration.minWalk,
            decay: configuration.decay,
            depositF: configuration.depositF,
            energyEnv: max(0, min(1.2, energyEnv)),
            hueOffset: hueOffset,
            aspect: 1.0)   // square by default; render() overrides with the live frame aspect
    }

    // MARK: - Helpers

    private func coeff(_ dt: Float, _ tau: Float) -> Float { 1.0 - exp(-dt / tau) }

    private func dispatch1D(_ enc: MTLComputeCommandEncoder, count: Int, pipeline: MTLComputePipelineState) {
        let tg = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        enc.dispatchThreadgroups(
            MTLSize(width: (count + tg - 1) / tg, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: tg, height: 1, depth: 1))
    }

    private static func seed(into buffer: MTLBuffer, configuration: CymaticSandConfiguration) {
        let count = configuration.grainCount
        let ptr = buffer.contents().bindMemory(to: SandGrain.self, capacity: count)
        var rng: UInt64 = 0x2545F4914F6CDD1D
        func next() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float((rng >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        let fw = Float(configuration.width), fh = Float(configuration.height)
        for i in 0..<count {
            ptr[i] = SandGrain(posX: next() * fw, posY: next() * fh, age: 0, pad: 0)
        }
    }

    private static func zero(textures: [MTLTexture], width: Int, height: Int) {
        let zeros = [UInt16](repeating: 0, count: width * height)
        let region = MTLRegionMake2D(0, 0, width, height)
        zeros.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for tex in textures {
                tex.replace(region: region, mipmapLevel: 0, withBytes: base, bytesPerRow: width * 2)
            }
        }
    }

    private static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let tn = max(0, min(1, (x - e0) / (e1 - e0)))
        return tn * tn * (3 - 2 * tn)
    }
}

// MARK: - Errors

public enum CymaticSandError: Error, Sendable {
    case bufferAllocationFailed
    case textureAllocationFailed
    case functionNotFound(String)
}

// MitosisGeometry — throwaway reaction–diffusion (Gray–Scott) cell-colony SKETCH.
//
// NOT a preset (no sidecar, no certification). Proves framerate + the
// onset→division SYNC that the physarum/Filigree trail substrate could not carry
// (FILIGREE_DESIGN §"sync finding"). Gates a real preset increment (sketch spec
// §7/§8 go/no-go). See `Mitosis.metal` for the Gray–Scott kernel.
//
// A `ParticleGeometry` sibling (D-097), modelled byte-for-byte on
// `PhysarumGeometry`'s per-frame-compute contract so it drops into the existing
// render loop and reuses the live FeatureVector stream (no synthetic audio —
// FA #27). Difference from Physarum: no agents/accumulator — state is ONE
// rg16Float (A,B) texture pair, ping-ponged across N react substeps per frame,
// with a `.textures` barrier between dependent substeps.

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "Mitosis")

// MARK: - MitosisConfig (mirror of MSL `MitosisConfig`, 48 bytes)

struct MitosisConfig {
    var width: UInt32
    var height: UInt32
    var frame: UInt32
    var Da: Float
    var Db: Float
    var feed: Float
    var kill: Float
    var dt: Float
    var feedBurst: Float
    var energyEnv: Float
    var paletteId: UInt32
    var pad: Float = 0
}

// MARK: - Configuration

public struct MitosisConfiguration: Sendable {
    /// Sim grid. RD is cheap per cell; a smaller grid than the 1080p output keeps
    /// the spots large enough to read division and leaves headroom for substeps.
    public var width: Int
    public var height: Int
    /// React substeps per frame at rest. RD needs many iterations/frame (§4); energy
    /// scales this up toward `maxSubsteps` (faster metabolism when loud).
    public var baseSubsteps: Int
    public var maxSubsteps: Int
    /// Gray–Scott mitosis regime (mrob Xmorphia). F≈0.0367, k≈0.0649 splits spots.
    public var feed: Float
    public var kill: Float
    public var paletteId: UInt32

    public init(
        width: Int = 320,
        height: Int = 180,
        baseSubsteps: Int = 8,
        maxSubsteps: Int = 18,
        // Regime: F=0.034 with k swept across the death boundary by energy (see
        // `makeConfig`). Empirically (MitosisSketchRenderTests.test_regimeProbe) the
        // canonical "mitosis" F=0.0367/k=0.0649 DECAYS to extinction in this r16Float
        // discretisation; k≈0.063 (the "u-skate" regime) self-sustains a living field
        // of discrete, dividing cells, and k climbing toward ~0.0645 dies them back —
        // which is the merge/divide handle.
        feed: Float = 0.034,
        kill: Float = 0.063,
        paletteId: UInt32 = 0
    ) {
        self.width = width
        self.height = height
        self.baseSubsteps = baseSubsteps
        self.maxSubsteps = maxSubsteps
        self.feed = feed
        self.kill = kill
        self.paletteId = paletteId
    }
}

// MARK: - MitosisGeometry

public final class MitosisGeometry: ParticleGeometry, @unchecked Sendable {

    public let configuration: MitosisConfiguration

    /// Protocol requirement (D-057 governor), unused: an RD field is fully coupled —
    /// every cell integrates every frame.
    public var activeParticleFraction: Float = 1.0

    private let state: [MTLTexture]   // 2× rg16Float (r=A, g=B), ping-pong
    private var cur = 0

    private let reactPipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState?

    // CPU-side music envelopes (one primitive per layer — D-026, FA #67).
    private var energyEnv: Float = 0   // smoothed continuous energy → metabolism + brightness
    private var hitEnv: Float = 0      // fast drum/bass transient → onset mitosis burst (the sync)
    private var frameCounter: UInt32 = 0

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: MitosisConfiguration = .init(),
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.configuration = configuration

        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float, width: configuration.width, height: configuration.height, mipmapped: false)
        td.usage = [.shaderRead, .shaderWrite]
        td.storageMode = .shared
        // ponytail: shared storage on UMA — simplest seed + readback for the metric.
        var textures: [MTLTexture] = []
        for _ in 0..<2 {
            guard let tex = device.makeTexture(descriptor: td) else { throw MitosisError.textureAllocationFailed }
            textures.append(tex)
        }
        self.state = textures
        Self.seed(textures: textures, configuration: configuration)

        guard let fn = library.makeFunction(name: "mitosis_react") else {
            throw MitosisError.functionNotFound("mitosis_react")
        }
        self.reactPipeline = try device.makeComputePipelineState(function: fn)

        if let pixelFormat {
            guard let vfn = library.makeFunction(name: "fullscreen_vertex"),
                  let ffn = library.makeFunction(name: "mitosis_fragment") else {
                throw MitosisError.functionNotFound("fullscreen_vertex/mitosis_fragment")
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = pixelFormat
            self.renderPipeline = try device.makeRenderPipelineState(descriptor: desc)
        } else {
            self.renderPipeline = nil
        }
        logger.info("Mitosis: \(configuration.width)×\(configuration.height), \(configuration.baseSubsteps)–\(configuration.maxSubsteps) substeps/frame")
    }

    /// Smoothed energy envelope. Exposed for the render test's metabolism assertions.
    public var currentEnergyEnv: Float { energyEnv }
    /// Fast transient envelope (onset burst). Exposed for the render test's sync assertions.
    public var currentHitEnv: Float { hitEnv }

    /// The latest state texture — exposed so the render test can read back the B
    /// channel and count spots (the divide/merge metric).
    public var currentStateTexture: MTLTexture { state[cur] }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        advanceEnvelopes(features: features, stems: stemFeatures)
        frameCounter &+= 1

        // Metabolism: louder → more substeps/frame → faster division. (§6 sustained
        // energy sets the division/growth rate.)
        let en = max(0, min(1.2, energyEnv))
        let substeps = configuration.baseSubsteps +
            Int(Float(configuration.maxSubsteps - configuration.baseSubsteps) * min(1, en))

        guard let enc = commandBuffer.makeComputeCommandEncoder() else {
            logger.error("Mitosis.update: encoder failed"); return
        }
        enc.setComputePipelineState(reactPipeline)
        let tpg = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(
            width: (configuration.width + 15) / 16,
            height: (configuration.height + 15) / 16,
            depth: 1)

        for step in 0..<substeps {
            var cfg = makeConfig(energy: en, frameSalt: frameCounter &+ UInt32(step),
                                 // Inject the onset burst only on the first substep — one
                                 // bounded pulse per frame, not N× (flash-safe).
                                 burst: step == 0 ? min(1, hitEnv) : 0)
            let src = state[cur], dst = state[1 - cur]
            enc.setBytes(&cfg, length: MemoryLayout<MitosisConfig>.stride, index: 0)
            enc.setTexture(src, index: 0)
            enc.setTexture(dst, index: 1)
            enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tpg)
            // Metal does not serialise consecutive dispatches; each substep reads the
            // previous one's full neighbourhood (cf. PhysarumGeometry).
            enc.memoryBarrier(scope: .textures)
            cur = 1 - cur
        }
        enc.endEncoding()
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let state = renderPipeline else { return }
        var cfg = makeConfig(energy: max(0, min(1.2, energyEnv)), frameSalt: frameCounter, burst: 0)
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(&cfg, length: MemoryLayout<MitosisConfig>.stride, index: 0)
        encoder.setFragmentTexture(self.state[cur], index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: - Music envelopes

    /// Continuous energy (metabolism) + fast transient (onset burst). Energy blend
    /// mirrors Murmuration/Physarum so it's sized to real music (stems when present).
    private func advanceEnvelopes(features: FeatureVector, stems: StemFeatures) {
        var dt = features.deltaTime
        if !(dt > 0) { dt = 1.0 / 60.0 }
        dt = min(dt, 1.0 / 30.0)

        let stemTotal = stems.drumsEnergy + stems.bassEnergy + stems.otherEnergy + stems.vocalsEnergy
        let blend = Self.smoothstep(0.02, 0.06, stemTotal)
        let stemEnergy = (stems.drumsEnergy + stems.bassEnergy + stems.otherEnergy) / 3 + 0.4 * stems.vocalsEnergy
        let fullEnergy = (features.bass + features.mid) * 0.5
        let rawEnergy = fullEnergy + (stemEnergy - fullEnergy) * blend
        energyEnv += Float(dt / (0.30 + dt)) * (rawEnergy - energyEnv)

        // Per-beat transient: fast-attack/slow-release envelope of the drum (+bass)
        // deviation primitives — the onset signal that fires the mitosis burst.
        let hitRaw = max(stems.drumsEnergyDev, 0.7 * stems.bassEnergyDev) * blend
        let hitAlpha = hitRaw > hitEnv ? dt / (0.012 + dt) : dt / (0.16 + dt)
        hitEnv += Float(hitAlpha) * (hitRaw - hitEnv)
    }

    private func makeConfig(energy: Float, frameSalt: UInt32, burst: Float) -> MitosisConfig {
        // Energy shifts k across the death boundary (the divide↔merge layer): quiet →
        // high k → cells shrink/coalesce (merge, sparse); loud → low k → teeming
        // division. Centred so rest sits in the living regime, clamped short of full
        // extinction. (Substep count — set in `update` — carries the metabolism rate.)
        let en = max(0, min(1, energy))
        let killEff = configuration.kill + 0.0008 - 0.0026 * en   // [≈0.0612 loud … ≈0.0638 quiet]
        return MitosisConfig(
            width: UInt32(configuration.width),
            height: UInt32(configuration.height),
            frame: frameSalt,
            Da: 1.0,
            Db: 0.5,
            feed: configuration.feed,
            kill: killEff,
            dt: 1.0,
            feedBurst: burst,
            energyEnv: energy,
            paletteId: configuration.paletteId)
    }

    // MARK: - Seeding

    /// Background A=1, B=0 (the stable rest state); stamp deterministic random B
    /// blobs to start the reaction (Karl Sims seed). Same scatter every run.
    private static func seed(textures: [MTLTexture], configuration: MitosisConfiguration) {
        let w = configuration.width, h = configuration.height
        // rg16Float: two Float16 per cell. Default (A,B) = (1, 0).
        var buf = [Float16](repeating: 0, count: w * h * 2)
        for i in 0..<(w * h) { buf[i * 2] = 1.0 }   // A=1 everywhere

        var rng: UInt64 = 0x2545F4914F6CDD1D
        func next() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float((rng >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        let blobs = max(8, (w * h) / 4000)
        for _ in 0..<blobs {
            let cx = Int(next() * Float(w)), cy = Int(next() * Float(h))
            let r = 3 + Int(next() * 3)
            for dy in -r...r {
                for dx in -r...r where dx * dx + dy * dy <= r * r {
                    let x = ((cx + dx) % w + w) % w
                    let y = ((cy + dy) % h + h) % h
                    buf[(y * w + x) * 2 + 1] = 0.5   // B=0.5 in the blob (A stays 1)
                }
            }
        }

        let region = MTLRegionMake2D(0, 0, w, h)
        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for tex in textures {
                tex.replace(region: region, mipmapLevel: 0, withBytes: base, bytesPerRow: w * 2 * MemoryLayout<Float16>.stride)
            }
        }
    }

    private static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let tn = max(0, min(1, (x - e0) / (e1 - e0)))
        return tn * tn * (3 - 2 * tn)
    }
}

// MARK: - Errors

public enum MitosisError: Error, Sendable {
    case textureAllocationFailed
    case functionNotFound(String)
}

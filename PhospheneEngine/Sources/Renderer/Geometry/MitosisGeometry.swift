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
    var diffuseA: Float   // MSL `Da`
    var diffuseB: Float   // MSL `Db`
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
    /// Number of B seed blobs. Few cells → the colony divides/spreads as a visible
    /// process (Matt, MITOSIS.2: "if this preset favors division, start with only a
    /// couple of cells"); a dense seed fills instantly into a static grid.
    public var seedBlobs: Int

    public init(
        width: Int = 320,
        height: Int = 180,
        baseSubsteps: Int = 8,
        maxSubsteps: Int = 18,
        // Regime (MITOSIS.2): F=0.034, base k=0.0655 leans to the DEATH side — cells
        // continuously die back (merge) — and each drum onset transiently drops k to
        // trigger a division burst (see `update`). Constant-parameter Gray–Scott always
        // FREEZES to a static grid (the live M7 failure; every regime in
        // `test_regimeProbeDynamic` ended with activity ≈ 0), so the music drives the
        // churn. At this death-leaning base the cells stay DISCRETE + round (lower k
        // writhes into connected worms — `test_onsetChurnProbe` frames).
        feed: Float = 0.034,
        kill: Float = 0.0655,
        paletteId: UInt32 = 0,
        seedBlobs: Int = 3
    ) {
        self.width = width
        self.height = height
        self.baseSubsteps = baseSubsteps
        self.maxSubsteps = maxSubsteps
        self.feed = feed
        self.kill = kill
        self.paletteId = paletteId
        self.seedBlobs = seedBlobs
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
        let cfg = configuration
        logger.info("Mitosis: \(cfg.width)×\(cfg.height) sim, \(cfg.baseSubsteps)–\(cfg.maxSubsteps) substeps/frame")
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

        // Constant-parameter Gray–Scott always FREEZES to a static grid (MITOSIS.2
        // probe: every regime end-activity ≈ 0) — the "mitosis" is the transient, not a
        // steady state. So the music must keep the field out of equilibrium. Base k
        // leans to the death side → cells continuously die back (MERGE) between beats;
        // each drum onset drops k → a DIVISION burst on the beat (Matt's locked role).
        // The field perpetually divides-on-beat / merges-between, never freezing.
        let en = max(0, min(1.2, energyEnv))
        let hit = min(1.4, hitEnv)
        // Keep the SUSTAINED base k inside the discrete-cell band (≈0.063–0.066) at all
        // energies — a sustained low k writhes into a connected worm labyrinth, not cells
        // (MITOSIS.2 production render). Energy nudges it only slightly (loud a touch
        // denser). The churn comes from the BRIEF per-onset k-dip: a short excursion
        // divides without time to worm-ify (cf. test_onsetChurnProbe discrete frames).
        let killBase = configuration.kill - 0.002 * min(1, en)   // 0.0655 quiet → 0.0635 loud (both discrete)
        let killEff = killBase - 0.0085 * hit                    // onset → brief division burst
        // Survival-floor nucleation gate: only while music plays (no Drift-Motes in
        // silence), keeps the death-leaning field recoverable.
        let nucleate = Self.smoothstep(0.03, 0.12, energyEnv)
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
            // Nucleation trickle on the first substep only (one bounded pass/frame).
            let burst: Float = step == 0 ? nucleate : 0
            var cfg = makeConfig(energy: en, killEff: killEff, burst: burst, frameSalt: frameCounter &+ UInt32(step))
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
        let en = max(0, min(1.2, energyEnv))
        var cfg = makeConfig(energy: en, killEff: configuration.kill, burst: 0, frameSalt: frameCounter)
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

    /// `killEff` is computed per-frame in `update` (base k − energy density shift −
    /// onset division pulse); the onset drives the divide↔merge churn (see `update`).
    private func makeConfig(energy: Float, killEff: Float, burst: Float, frameSalt: UInt32) -> MitosisConfig {
        MitosisConfig(
            width: UInt32(configuration.width),
            height: UInt32(configuration.height),
            frame: frameSalt,
            diffuseA: 1.0,
            diffuseB: 0.5,
            feed: configuration.feed,
            kill: killEff,
            dt: 1.0,
            feedBurst: burst,   // energy-gated survival-floor nucleation (MITOSIS.2)
            energyEnv: energy,
            paletteId: configuration.paletteId)
    }

    // MARK: - Seeding

    /// Background A=1, B=0 (the stable rest state); stamp deterministic random B
    /// blobs to start the reaction (Karl Sims seed). Same scatter every run.
    private static func seed(textures: [MTLTexture], configuration: MitosisConfiguration) {
        let width = configuration.width, height = configuration.height
        // rg16Float: two Float16 per cell. Default (A,B) = (1, 0).
        var buf = [Float16](repeating: 0, count: width * height * 2)
        for i in 0..<(width * height) { buf[i * 2] = 1.0 }   // A=1 everywhere

        var rng: UInt64 = 0x2545F4914F6CDD1D
        func next() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float((rng >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        let blobs = max(1, configuration.seedBlobs)
        for _ in 0..<blobs {
            let cx = Int(next() * Float(width)), cy = Int(next() * Float(height))
            let radius = 3 + Int(next() * 3)
            for dy in -radius...radius {
                for dx in -radius...radius where dx * dx + dy * dy <= radius * radius {
                    let x = ((cx + dx) % width + width) % width
                    let y = ((cy + dy) % height + height) % height
                    buf[(y * width + x) * 2 + 1] = 0.5   // B=0.5 in the blob (A stays 1)
                }
            }
        }

        let region = MTLRegionMake2D(0, 0, width, height)
        let bytesPerRow = width * 2 * MemoryLayout<Float16>.stride
        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for tex in textures {
                tex.replace(region: region, mipmapLevel: 0, withBytes: base, bytesPerRow: bytesPerRow)
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

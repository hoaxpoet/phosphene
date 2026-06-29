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
    var huePhase: Float = 0
    var colorBias: Float = 0
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

    /// Seconds for one grow→crowd→dissolve cycle at moderate energy (Matt MITOSIS.2c:
    /// few cells divide into many until crowded over 25–35 s, then dissolve & regrow).
    public var cyclePeriod: Float

    public init(
        // Higher sim res than 1080p/6 → cells are crisp on upscale, not blurry
        // (Matt MITOSIS.2c "much too blurry"). 640×360 = 3× upscale.
        width: Int = 640,
        height: Int = 360,
        // LOW substep count paces the SLOW growth (Matt: "much too fast"; 25–35 s to
        // crowded, not < 10 s). Energy modulates the division rate within that.
        baseSubsteps: Int = 2,
        maxSubsteps: Int = 5,
        // GROWTH regime (MITOSIS.2c): few seeds divide into a crowded field of discrete
        // cells, then saturate ("too crowded to divide further"). The dissolve phase
        // raises k to melt the field back to a few cells; then it regrows (cycle).
        feed: Float = 0.0260,
        kill: Float = 0.0600,
        paletteId: UInt32 = 0,
        seedBlobs: Int = 4,
        cyclePeriod: Float = 34
    ) {
        self.width = width
        self.height = height
        self.baseSubsteps = baseSubsteps
        self.maxSubsteps = maxSubsteps
        self.feed = feed
        self.kill = kill
        self.paletteId = paletteId
        self.seedBlobs = seedBlobs
        self.cyclePeriod = cyclePeriod
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
    private var energyEnv: Float = 0   // smoothed continuous energy → division rate / cycle pace (PRIMARY)
    private var cycleClock: Float = 0   // 0→1 grow→crowd→dissolve cycle position
    private var huePhase: Float = 0     // music-paced hue animation (the psychedelic colour sync)
    private var centroidEnv: Float = 0  // smoothed spectral centroid → hue bias (timbre → colour)
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
    /// Cycle position 0→1 (grow→dissolve). Exposed for the render test.
    public var currentCycleClock: Float { cycleClock }

    /// The latest state texture — exposed so the render test can read back the B
    /// channel and count spots (the divide/merge metric).
    public var currentStateTexture: MTLTexture { state[cur] }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        advanceEnvelopes(features: features, stems: stemFeatures)
        frameCounter &+= 1
        let en = max(0, min(1.2, energyEnv))

        // MITOSIS.2c — "psychedelic cell division" as a SLOW GROWTH ARC, not a per-beat
        // churn (the churn was over-engineering). Few cells divide into many until the
        // field is crowded, over ~25–35 s; then it DISSOLVES back to a few cells and
        // REGROWS (Matt's cycle). Continuous energy paces the cycle + division rate
        // (Audio Data Hierarchy: energy primary). One grow→dissolve loop per `cyclePeriod`.
        var dt = features.deltaTime
        if !(dt > 0) { dt = 1.0 / 60.0 }
        dt = min(dt, 1.0 / 30.0)
        let pace = 0.6 + 0.8 * min(1, en)                     // louder → faster division/cycle
        cycleClock += Float(dt) * pace / configuration.cyclePeriod
        let regrew = cycleClock >= 1
        if regrew { cycleClock -= 1 }

        // Grow for the first ~82 % of the cycle (killEff = growth regime → cells divide
        // and fill); DISSOLVE over the last ~18 % (killEff ramps high → the field melts
        // back). A fresh seed-cluster burst at the very top of each cycle gives the
        // "few cells" the regrowth starts from.
        let growFrac: Float = 0.82
        let killEff: Float
        if cycleClock < growFrac {
            killEff = configuration.kill                      // growth regime
        } else {
            let diss = (cycleClock - growFrac) / (1 - growFrac)  // 0→1 across the dissolve
            killEff = configuration.kill + 0.013 * Self.smoothstep(0, 1, diss)   // high k melts the field
        }
        let reseed: Float = cycleClock < 0.05 ? 1.0 : 0       // seed the few cells to regrow from
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
            let burst: Float = step == 0 ? reseed : 0
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

    /// Smoothed continuous energy — the primary driver (Audio Data Hierarchy): paces the
    /// growth/cycle rate. Blend mirrors Murmuration/Physarum so it's sized to real music.
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

        // Psychedelic colour SYNC (Matt MITOSIS.2c "tie shimmer to the music"): the hue
        // animation phase accumulates faster when louder; the spectral centroid (timbre
        // brightness) biases which hues dominate. So the colour visibly responds to the
        // music rather than free-running.
        huePhase += Float(dt) * (0.10 + 0.9 * max(0, min(1.2, energyEnv)))
        centroidEnv += Float(dt / (0.50 + dt)) * (max(0, min(1, features.spectralCentroid)) - centroidEnv)
    }

    /// `killEff` (growth regime, or the high dissolve k) and `burst` (cycle-start reseed)
    /// are computed per-frame in `update`; `huePhase`/`colorBias` carry the music→colour sync.
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
            feedBurst: burst,   // cycle-start cluster reseed (the "few cells" to regrow from)
            energyEnv: energy,
            paletteId: configuration.paletteId,
            huePhase: huePhase,
            colorBias: centroidEnv)
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

// PhysarumGeometry — throwaway physarum (slime-mold) agent-network SKETCH.
//
// NOT a preset (no sidecar, no certification). Proves framerate + look + the
// energy→consolidation musical role on Apple Silicon, gating a real preset
// increment. See the Physarum sketch spec (§4 architecture, §5 audio, §7 gate)
// and `Physarum.metal` for the kernels.
//
// A `ParticleGeometry` sibling (D-097): owns its agent buffer, atomic deposit
// accumulator, ping-pong trail textures, and the four `physarum_*` pipelines —
// it does not parameterise a shared pipeline. Modelled on Murmuration3DGeometry's
// per-frame compute contract so it drops into the existing render loop for the
// live Phase-2 audio-lock test, reusing the app's live FeatureVector stream
// (no synthetic audio — FA #27).

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "Physarum")

// MARK: - PhysConfig (mirror of MSL `PhysConfig`, 48 bytes)

struct PhysConfig {
    var width: UInt32
    var height: UInt32
    var agentCount: UInt32
    var frame: UInt32
    var sensorDistance: Float
    var sensorAngle: Float
    var rotationAngle: Float
    var moveDistance: Float
    var depositF: Float
    var decay: Float
    var collapseEnv: Float
    var energyEnv: Float
    var paletteId: UInt32
}

// MARK: - PhysAgent (mirror of MSL `PhysAgent`, 16 bytes — scalar floats so the
// layout matches `float2 pos; float heading; float age` byte-for-byte)

@frozen
public struct PhysAgent: Sendable {
    public var positionX: Float
    public var positionY: Float
    public var heading: Float
    public var age: Float
}

// MARK: - Configuration

public struct PhysarumConfiguration: Sendable {
    /// Trail-map resolution (sim grid). Spec §6 start point: 1280×720.
    public var width: Int
    public var height: Int
    /// Agent count. Spec §4: start 2^18 (262 144); scale toward 2^20 per headroom.
    public var agentCount: Int

    // Base agent-loop params (energy scales sensor/move/deposit/decay each frame).
    public var baseSensorDistance: Float   // px
    public var sensorAngle: Float          // rad
    public var rotationAngle: Float        // rad
    public var baseMoveDistance: Float     // px/step
    public var baseDepositF: Float

    /// Display palette: 0 bioluminescence · 1 Physarum polycephalum · 2 kintsugi.
    public var paletteId: UInt32

    /// How strongly real peaks "bloom" the web into consolidated veins (scales
    /// the bloom-driven sensor/move range + persistence). 1.0 = peaks bloom to
    /// veins (the web-dominant concept). 0.0 = pure web at every energy — energy
    /// then only brightens/quickens it, never coarsens.
    public var formEnergyCoupling: Float

    public init(
        width: Int = 1280,
        height: Int = 720,
        agentCount: Int = 262_144,
        baseSensorDistance: Float = 9.0,
        sensorAngle: Float = 0.40,
        rotationAngle: Float = 0.50,
        baseMoveDistance: Float = 1.0,
        baseDepositF: Float = 0.18,
        paletteId: UInt32 = 2,   // locked: Kintsugi (gold veins on pure black)
        formEnergyCoupling: Float = 1.0
    ) {
        self.width = width
        self.height = height
        self.agentCount = agentCount
        self.baseSensorDistance = baseSensorDistance
        self.sensorAngle = sensorAngle
        self.rotationAngle = rotationAngle
        self.baseMoveDistance = baseMoveDistance
        self.baseDepositF = baseDepositF
        self.paletteId = paletteId
        self.formEnergyCoupling = formEnergyCoupling
    }
}

// MARK: - PhysarumGeometry

public final class PhysarumGeometry: ParticleGeometry, @unchecked Sendable {

    public let configuration: PhysarumConfiguration

    /// Protocol requirement (D-057 governor), unused: physarum agents are a
    /// coupled field — a slime network can't drop a fraction of its agents, so
    /// all are updated every frame. Stored only to satisfy `ParticleGeometry`.
    public var activeParticleFraction: Float = 1.0

    public let agentBuffer: MTLBuffer
    private let accumBuffer: MTLBuffer
    private let trail: [MTLTexture]      // 2× r16Float, ping-pong
    private var cur = 0

    private let resetPipeline: MTLComputePipelineState
    private let agentsPipeline: MTLComputePipelineState
    private let diffusePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState?

    // CPU-side music envelopes (the global-envelope coupling, like Murmuration).
    private var energyEnv: Float = 0       // slow continuous energy → consolidation
    private var hitEnv: Float = 0          // fast drum/bass transient → per-beat accent (PHYS.4)
    private var collapseEnv: Float = 0     // triggered pulse → dissolve/regrow accent
    private var frameCounter: UInt32 = 0

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: PhysarumConfiguration = .init(),
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.configuration = configuration
        let cells = configuration.width * configuration.height

        // Agent buffer — seeded uniformly across the field.
        let agentBytes = configuration.agentCount * MemoryLayout<PhysAgent>.stride
        guard let agents = device.makeBuffer(length: agentBytes, options: .storageModeShared) else {
            throw PhysarumError.bufferAllocationFailed
        }
        self.agentBuffer = agents
        Self.seed(into: agents, configuration: configuration)

        // Deposit accumulator — one atomic_uint per cell.
        guard let accum = device.makeBuffer(length: cells * MemoryLayout<UInt32>.stride,
                                             options: .storageModeShared) else {
            throw PhysarumError.bufferAllocationFailed
        }
        self.accumBuffer = accum

        // Ping-pong trail textures (r16Float — filterable, so agents can bilinearly
        // sample; bump to r32Float if precision/stability needs it, but r32 isn't
        // filterable so agents would lose the smooth sense, §9 precision risk).
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float, width: configuration.width, height: configuration.height, mipmapped: false)
        td.usage = [.shaderRead, .shaderWrite]
        td.storageMode = .shared
        // ponytail: shared storage on UMA — simplest zeroing + readback; private gains nothing here.
        var textures: [MTLTexture] = []
        for _ in 0..<2 {
            guard let tex = device.makeTexture(descriptor: td) else { throw PhysarumError.textureAllocationFailed }
            textures.append(tex)
        }
        self.trail = textures
        Self.zero(textures: textures, width: configuration.width, height: configuration.height)

        // Compute pipelines.
        func compute(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else { throw PhysarumError.functionNotFound(name) }
            return try device.makeComputePipelineState(function: fn)
        }
        self.resetPipeline = try compute("physarum_reset")
        self.agentsPipeline = try compute("physarum_agents")
        self.diffusePipeline = try compute("physarum_diffuse")

        // Display pipeline (fullscreen_vertex from Common.metal + physarum_trail_fragment).
        if let pixelFormat {
            guard let vfn = library.makeFunction(name: "fullscreen_vertex"),
                  let ffn = library.makeFunction(name: "physarum_trail_fragment") else {
                throw PhysarumError.functionNotFound("fullscreen_vertex/physarum_trail_fragment")
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = pixelFormat
            self.renderPipeline = try device.makeRenderPipelineState(descriptor: desc)
        } else {
            self.renderPipeline = nil
        }
        logger.info("Physarum: \(configuration.agentCount) agents, \(configuration.width)×\(configuration.height)")
    }

    // ponytail: collapse is an input, not a detector — detection is promotion/Orchestrator work (§8).
    /// Trigger the collapse-regrow accent. Driven externally — by the render
    /// test for deterministic frames, and (Phase 2) by the real structural
    /// signal. The sketch ships no auto-detector: structural detection isn't
    /// available headless and beat phase is the wrong source (spec §5).
    public func requestCollapse() { collapseEnv = 1.0 }

    /// Smoothed energy envelope [0, ~1.2]. Exposed for the render test's
    /// consolidation assertions.
    public var currentEnergyEnv: Float { energyEnv }

    /// Fast drum/bass transient envelope (PHYS.4 per-beat accent). Exposed for the
    /// render test's beat-response assertions.
    public var currentHitEnv: Float { hitEnv }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        advanceEnvelopes(features: features, stems: stemFeatures)
        frameCounter &+= 1
        var cfg = makeConfig()

        guard let enc = commandBuffer.makeComputeCommandEncoder() else {
            logger.error("Physarum.update: encoder failed"); return
        }
        let src = trail[cur], dst = trail[1 - cur]
        let cellCount = configuration.width * configuration.height

        // 1) Reset accumulator.
        enc.setComputePipelineState(resetPipeline)
        enc.setBuffer(accumBuffer, offset: 0, index: 0)
        enc.setBytes(&cfg, length: MemoryLayout<PhysConfig>.stride, index: 1)
        dispatch1D(enc, count: cellCount, pipeline: resetPipeline)

        // Metal does not serialize consecutive dispatches — barrier the
        // accumulator between reset, agent-deposit, and diffuse-read
        // (cf. FerrofluidParticles.swift).
        enc.memoryBarrier(scope: .buffers)

        // 2) Agents: sense src, steer, move, deposit into accumulator.
        enc.setComputePipelineState(agentsPipeline)
        enc.setBuffer(agentBuffer, offset: 0, index: 0)
        enc.setBytes(&cfg, length: MemoryLayout<PhysConfig>.stride, index: 1)
        enc.setBuffer(accumBuffer, offset: 0, index: 2)
        enc.setTexture(src, index: 0)
        dispatch1D(enc, count: configuration.agentCount, pipeline: agentsPipeline)

        enc.memoryBarrier(scope: .buffers)

        // 3) Diffuse + decay + this-frame deposit → dst.
        enc.setComputePipelineState(diffusePipeline)
        enc.setBytes(&cfg, length: MemoryLayout<PhysConfig>.stride, index: 0)
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

        cur = 1 - cur   // dst is now the latest trail
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let state = renderPipeline else { return }
        var cfg = makeConfig()
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(&cfg, length: MemoryLayout<PhysConfig>.stride, index: 0)
        encoder.setFragmentTexture(trail[cur], index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: - Music envelopes

    /// Slow continuous-energy envelope (the primary consolidation driver) plus
    /// the collapse-pulse release. Energy blend mirrors Murmuration's proven
    /// recipe (stems when present, full-mix fallback) so it's sized to real music.
    private func advanceEnvelopes(features: FeatureVector, stems: StemFeatures) {
        var dt = features.deltaTime
        if !(dt > 0) { dt = 1.0 / 60.0 }
        dt = min(dt, 1.0 / 30.0)

        let stemTotal = stems.drumsEnergy + stems.bassEnergy + stems.otherEnergy + stems.vocalsEnergy
        let blend = Self.smoothstep(0.02, 0.06, stemTotal)
        let stemEnergy = (stems.drumsEnergy + stems.bassEnergy + stems.otherEnergy) / 3 + 0.4 * stems.vocalsEnergy
        let fullEnergy = (features.bass + features.mid) * 0.5
        let rawEnergy = fullEnergy + (stemEnergy - fullEnergy) * blend
        energyEnv += Float(dt / (0.30 + dt)) * (rawEnergy - energyEnv)   // PHYS.4: faster than 0.45 (track surges)

        // Per-beat transient (PHYS.4 event channel): fast-attack / fast-release
        // envelope of the drum (+ bass) deviation primitives — the sharp signals that
        // actually spike on real-music hits (session: drumsEnergyDev p95 ~0.83, max
        // ~3.4), which the slow energyEnv smooths away. Warmup-gated by `blend`.
        let hitRaw = max(stems.drumsEnergyDev, 0.7 * stems.bassEnergyDev) * blend
        let hitAlpha = hitRaw > hitEnv ? dt / (0.012 + dt) : dt / (0.16 + dt)
        hitEnv += Float(hitAlpha) * (hitRaw - hitEnv)

        // Collapse: 0.6 s linear release after a trigger.
        collapseEnv = max(0, collapseEnv - Float(dt) / 0.6)
    }

    private func makeConfig() -> PhysConfig {
        // Web is home. Sustained energy (`en`) raises the baseline consolidation
        // (`bloomBase`); each drum/bass transient (`hit`) punches a brief bloom +
        // motion + brightness accent on top — the per-beat event the eye locks onto
        // (PHYS.4). Threshold lowered 0.55→0.40 to the measured real-music energyEnv
        // range (p50 ~0.48) so the baseline tracks, not just rare peaks.
        let en = max(0, min(1.2, energyEnv))
        let hit = min(1.3, hitEnv)
        let bloomBase = Self.smoothstep(0.40, 0.90, en) * configuration.formEnergyCoupling
        let bloom = min(1.0, bloomBase + 0.60 * hit)   // PHYS.4: bold per-beat contraction (flash-free redistribution)
        return PhysConfig(
            width: UInt32(configuration.width),
            height: UInt32(configuration.height),
            agentCount: UInt32(configuration.agentCount),
            frame: frameCounter,
            sensorDistance: configuration.baseSensorDistance * (1 + 1.4 * bloom),
            sensorAngle: configuration.sensorAngle,
            rotationAngle: configuration.rotationAngle,
            moveDistance: configuration.baseMoveDistance * (1 + 1.0 * bloom + 0.7 * hit),
            depositF: configuration.baseDepositF * (0.7 + 0.7 * en + 1.0 * bloom + 0.5 * hit),
            decay: Self.mix(0.86, 0.965, bloom),
            collapseEnv: collapseEnv,
            energyEnv: en,
            paletteId: configuration.paletteId)
    }

    // MARK: - Dispatch helper

    private func dispatch1D(_ enc: MTLComputeCommandEncoder, count: Int, pipeline: MTLComputePipelineState) {
        let tg = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        enc.dispatchThreadgroups(
            MTLSize(width: (count + tg - 1) / tg, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: tg, height: 1, depth: 1))
    }

    // MARK: - Seeding / zeroing

    /// Deterministic uniform seed: agents scattered across the field with random
    /// headings (reproducible — same scatter every run, like Murmuration's seed).
    private static func seed(into buffer: MTLBuffer, configuration: PhysarumConfiguration) {
        let count = configuration.agentCount
        let ptr = buffer.contents().bindMemory(to: PhysAgent.self, capacity: count)
        var rng: UInt64 = 0x2545F4914F6CDD1D
        func next() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float((rng >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        let fwidth = Float(configuration.width), fheight = Float(configuration.height)
        for i in 0..<count {
            ptr[i] = PhysAgent(
                positionX: next() * fwidth,
                positionY: next() * fheight,
                heading: next() * 2 * .pi,
                age: 0)
        }
    }

    /// Zero both trail textures (makeTexture contents are undefined).
    private static func zero(textures: [MTLTexture], width: Int, height: Int) {
        let zeros = [UInt16](repeating: 0, count: width * height)   // r16Float 0 == bits 0
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

    private static func mix(_ lo: Float, _ hi: Float, _ tn: Float) -> Float { lo + (hi - lo) * tn }
}

// MARK: - Errors

public enum PhysarumError: Error, Sendable {
    case bufferAllocationFailed
    case textureAllocationFailed
    case functionNotFound(String)
}

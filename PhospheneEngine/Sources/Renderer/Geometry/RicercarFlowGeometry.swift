// RicercarFlowGeometry.swift — audio-reactive glowing particle flow-field conformer (Fantasia rebuild).
//
// A `ParticleGeometry` sibling (D-097) modelled on Mitosis/Physarum's per-frame-compute + ping-pong-trail
// contract (kernels in RicercarFlow.metal); Robert Hodgin *Magnetosphere* lineage. Thousands of particles
// advect through curl-noise + audio force fields, each carrying an instrument-family colour, deposited as
// additive glowing sprites into an HDR trail that decays each frame — the deposit-and-fade trail IS the
// glowing weaving ribbon of light, over a deep ground (RICERCAR_DESIGN §FANTASIA REBUILD).
//
// Audio (Audio Data Hierarchy + FA #67 — one primitive per layer): MOTION (zero-lag) ← band deviations
// per-colour drift; COLOUR/identity (lag-tolerant) ← band-stem|family hybrid; LINE CHARACTER ← per-stem
// AttackRatio (FL.14: staccato→short choppy life, legato→long flowing life).

import Metal
import simd
import Shared

// MARK: - GPU-mirrored structs (layouts match RicercarFlow.metal exactly)

/// Mirror of MSL `FlowConfig` — 4 uint + 28 float, all 4-byte members, no padding.
struct RicercarFlowConfig {
    var width: UInt32
    var height: UInt32
    var particleCount: UInt32
    var frame: UInt32
    var dt: Float
    var time: Float
    var flowSpeed: Float
    var turbulence: Float
    var decay: Float
    var exposure: Float
    var homePull: Float
    var famStrings: Float       // per-family HYBRID activity env (drives colour brightness + motion)
    var famBrass: Float
    var famWoodwinds: Float
    var famPercussion: Float
    var pointSize: Float
    var baseGlow: Float
    var energyGlow: Float
    var energy: Float
    var aspect: Float
    var d0x: Float; var d0y: Float   // per-family drift: strings
    var d1x: Float; var d1y: Float   //   brass
    var d2x: Float; var d2y: Float   //   woodwinds
    var d3x: Float; var d3y: Float   //   percussion
    // per-family articulation 0..1 (0=legato→long life, 1=staccato→short life)
    var art0: Float; var art1: Float; var art2: Float; var art3: Float
}

/// Mirror of MSL `FlowParticle` — two float4 (32 bytes), no alignment trap.
struct FlowParticle {
    var posVel: SIMD4<Float>   // pos.xy in [0,1], vel.xy in fraction/frame
    var misc: SIMD4<Float>     // family(0..3), age, life, seed
}

// MARK: - Configuration

public struct RicercarFlowConfiguration: Sendable {
    /// HDR trail-texture resolution (the sim canvas; the display fragment upscales to the drawable).
    public var width: Int
    public var height: Int
    /// Particle count (evenly split across the four instrument families).
    public var particleCount: Int

    public init(width: Int = 1280, height: Int = 720, particleCount: Int = 1_200) {
        self.width = width
        self.height = height
        self.particleCount = particleCount
    }
}

// MARK: - RicercarFlowGeometry

public final class RicercarFlowGeometry: ParticleGeometry, @unchecked Sendable {

    /// A particle field is fully coupled — the governor gate is unused (all particles advance each frame).
    public var activeParticleFraction: Float = 1.0

    public let configuration: RicercarFlowConfiguration

    private let particleBuffer: MTLBuffer
    private let trail: [MTLTexture]        // 2× rgba16Float, ping-pong
    private var cur = 0

    private let updatePSO: MTLComputePipelineState
    private let decayPSO: MTLRenderPipelineState?
    private let depositPSO: MTLRenderPipelineState?
    private let displayPSO: MTLRenderPipelineState?

    // CPU music envelopes (one primitive per layer — D-026, FA #67).
    private var energyEnv: Float = 0       // zero-lag continuous energy → flow vigour + turbulence (PRIMARY)
    private var beatEnv: Float = 0         // cached-grid beat pulse (computed + tested; unwired since FL.13)
    private var driftAngle = SIMD4<Float>(0.7, 2.1, 3.8, 5.2)   // per-family current directions (diverge, turn slowly)
    private var fam = SIMD4<Float>(repeating: 0)   // per-family HYBRID env: max(band-stem dev, family-capture dev)
    private var artic = SIMD4<Float>(repeating: 0) // per-family articulation 0..1 (0=legato, 1=staccato)
    private var time: Float = 0; private var frameCounter: UInt32 = 0

    /// Per-family soft-saturation working points (IFC.6 corpus; hue order) — a strong entry paints full.
    private static let familySaturation = SIMD4<Float>(0.30, 0.85, 0.35, 0.20)

    public enum FlowError: Error { case bufferAllocationFailed, textureAllocationFailed, functionNotFound(String) }

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: RicercarFlowConfiguration = .init(),
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.configuration = configuration

        // Particle buffer — deterministically seeded (same scatter every run, like Murmuration/Mitosis).
        let bytes = configuration.particleCount * MemoryLayout<FlowParticle>.stride
        guard let buf = device.makeBuffer(length: bytes, options: .storageModeShared) else {
            throw FlowError.bufferAllocationFailed
        }
        self.particleBuffer = buf
        Self.seed(into: buf, configuration: configuration)

        // HDR ping-pong trail (rgba16Float — additive deposit accumulates light; filterable for bloom taps).
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: configuration.width, height: configuration.height, mipmapped: false)
        td.usage = [.shaderRead, .renderTarget]
        td.storageMode = .private
        var textures: [MTLTexture] = []
        for _ in 0..<2 {
            guard let tex = device.makeTexture(descriptor: td) else { throw FlowError.textureAllocationFailed }
            textures.append(tex)
        }
        self.trail = textures

        func compute(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else { throw FlowError.functionNotFound(name) }
            return try device.makeComputePipelineState(function: fn)
        }
        self.updatePSO = try compute("ricercar_flow_update")

        func fn(_ name: String) throws -> MTLFunction {
            guard let function = library.makeFunction(name: name) else { throw FlowError.functionNotFound(name) }
            return function
        }
        let trailFormat: MTLPixelFormat = .rgba16Float

        // Decay pass: opaque fullscreen copy of the previous trail × decay → the current target.
        let decayDesc = MTLRenderPipelineDescriptor()
        decayDesc.vertexFunction = try fn("fullscreen_vertex")
        decayDesc.fragmentFunction = try fn("ricercar_flow_decay_fragment")
        decayDesc.colorAttachments[0].pixelFormat = trailFormat
        self.decayPSO = try device.makeRenderPipelineState(descriptor: decayDesc)

        // Deposit pass: additive (one/one) glowing point sprites on top of the decayed trail.
        let depDesc = MTLRenderPipelineDescriptor()
        depDesc.vertexFunction = try fn("ricercar_flow_point_vertex")
        depDesc.fragmentFunction = try fn("ricercar_flow_point_fragment")
        depDesc.colorAttachments[0].pixelFormat = trailFormat
        depDesc.colorAttachments[0].isBlendingEnabled = true
        depDesc.colorAttachments[0].rgbBlendOperation = .add
        depDesc.colorAttachments[0].alphaBlendOperation = .add
        depDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        depDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        depDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        depDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        self.depositPSO = try device.makeRenderPipelineState(descriptor: depDesc)

        // Display pass: tonemap the HDR trail → luminous over the deep ground, into the drawable.
        if let pixelFormat {
            let dispDesc = MTLRenderPipelineDescriptor()
            dispDesc.vertexFunction = try fn("fullscreen_vertex")
            dispDesc.fragmentFunction = try fn("ricercar_flow_display_fragment")
            dispDesc.colorAttachments[0].pixelFormat = pixelFormat
            self.displayPSO = try device.makeRenderPipelineState(descriptor: dispDesc)
        } else {
            self.displayPSO = nil
        }

        // Zero the trail textures — `.private` contents are undefined; a NaN there NEVER decays (the FL.10 bug).
        Self.clear(textures: textures, device: device)
    }

    /// Clear both trail textures to black via a no-draw clear render pass (works for `.private`).
    private static func clear(textures: [MTLTexture], device: MTLDevice) {
        guard let queue = device.makeCommandQueue(), let cmd = queue.makeCommandBuffer() else { return }
        for tex in textures {
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = tex
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            rpd.colorAttachments[0].storeAction = .store
            cmd.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
        }
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    // MARK: - Test hooks

    /// Smoothed zero-lag energy envelope. Exposed for the render test's motion assertions.
    public var currentEnergyEnv: Float { energyEnv }
    /// Cached-grid beat-pulse envelope (0…1). Exposed so a test can assert it pulses on the beat.
    public var currentBeatEnv: Float { beatEnv }
    /// Per-family articulation env (0=legato→flowing, 1=staccato→choppy). FL.14 test hook.
    public var currentArticulation: SIMD4<Float> { artic }
    /// Mean particle age (s) per family. Staccato families respawn faster ⇒ lower mean age. FL.14 hook.
    public func meanAgeByFamily() -> SIMD4<Float> {
        let count = configuration.particleCount
        let ptr = particleBuffer.contents().bindMemory(to: FlowParticle.self, capacity: count)
        var sum = SIMD4<Float>(repeating: 0), cnt = SIMD4<Float>(repeating: 0)
        for i in 0..<count { let fm = Int(ptr[i].misc.x.rounded()) & 3; sum[fm] += ptr[i].misc.y; cnt[fm] += 1 }
        return sum / cnt   // families split evenly across the buffer ⇒ each count ≥ 1
    }
    /// The latest trail texture — exposed so a render test can read it back.
    public var currentTrailTexture: MTLTexture { trail[cur] }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        advanceEnvelopes(features: features, stems: stemFeatures)
        frameCounter &+= 1
        var cfg = makeConfig()

        // 1. Advance every particle (curl-noise flow + homeward pull + beat scatter).
        if let enc = commandBuffer.makeComputeCommandEncoder() {
            enc.setComputePipelineState(updatePSO)
            enc.setBuffer(particleBuffer, offset: 0, index: 0)
            enc.setBytes(&cfg, length: MemoryLayout<RicercarFlowConfig>.stride, index: 1)
            let tg = min(updatePSO.maxTotalThreadsPerThreadgroup, 256)
            enc.dispatchThreadgroups(
                MTLSize(width: (configuration.particleCount + tg - 1) / tg, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tg, height: 1, depth: 1))
            enc.endEncoding()
        }

        // 2. Decay the previous trail into the next target, then deposit the particles additively on top.
        guard let decayPSO, let depositPSO else { return }
        let dst = trail[1 - cur], src = trail[cur]
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = dst
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(decayPSO)
            enc.setFragmentBytes(&cfg, length: MemoryLayout<RicercarFlowConfig>.stride, index: 0)
            enc.setFragmentTexture(src, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

            enc.setRenderPipelineState(depositPSO)
            enc.setVertexBuffer(particleBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&cfg, length: MemoryLayout<RicercarFlowConfig>.stride, index: 1)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: configuration.particleCount)
            enc.endEncoding()
        }
        cur = 1 - cur
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let displayPSO else { return }
        var cfg = makeConfig()
        encoder.setRenderPipelineState(displayPSO)
        encoder.setFragmentBytes(&cfg, length: MemoryLayout<RicercarFlowConfig>.stride, index: 0)
        encoder.setFragmentTexture(trail[cur], index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: - Music envelopes

    private static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let tn = max(0, min(1, (x - e0) / (e1 - e0)))
        return tn * tn * (3 - 2 * tn)
    }

    /// soft-saturate a deviation vs its working point → 0…~1 (1 − e^(−x/sat)).
    private static func softSat(_ dev: Float, _ sat: Float) -> Float {
        1.0 - exp(-max(0, dev) / max(sat, 1e-4))
    }

    /// Advance the CPU envelopes: energy (primary), beat (unwired), hybrid activity (motion+colour), articulation.
    private func advanceEnvelopes(features feat: FeatureVector, stems stem: StemFeatures) {
        var dt = feat.deltaTime
        if !(dt > 0) { dt = 1.0 / 60.0 }
        dt = min(dt, 1.0 / 30.0)
        time += dt

        // Zero-lag energy: soft-saturated band-deviation sum (D-026), sat 0.5 sized to REAL band-dev (sum ~0.2–0.6).
        let rawEnergy = Self.softSat(max(0, feat.bassDev) + max(0, feat.midDev) + max(0, feat.trebDev), 0.5)
        energyEnv += Float(dt / (0.10 + dt)) * (rawEnergy - energyEnv)

        // Beat pulse from the CACHED GRID (beatPhase01), NOT the saturated live `beatComposite` (FL.10 sync gap).
        // Sharp on the beat, sharper on the downbeat, gated by pulseAmp01. NOT wired to the render after FL.13.
        let amp = max(0, min(1, feat.pulseAmp01))
        let beatPulse = powf(max(0, 1 - feat.beatPhase01), 5.0)   // 1.0 at the beat → ~0 by mid-beat
        let downbeat = powf(max(0, 1 - feat.barPhase01), 6.0)     // sharper, peaks on the bar's "1"
        let rawBeat = amp * min(1.0, beatPulse + 0.7 * downbeat)
        // Instant attack + short release floor so a near-miss frame still reads as a crisp bloom, not a strobe.
        beatEnv = max(rawBeat, beatEnv - Float(dt) / 0.12)

        // Per-family HYBRID activity env (FL.13): MAX of a colour's mapped BAND-STEM dev (zero-lag, alive on
        // rock/pop) and its FAMILY capture dev (alive on orchestral, laggy) → differentiates on ANY genre.
        // Warmup-gated, soft-saturated, smoothed ~0.3 s. colour←(band-stem|family). Drives motion + colour.
        let stemTotal = stem.drumsEnergy + stem.bassEnergy + stem.otherEnergy + stem.vocalsEnergy
        let blend = Self.smoothstep(0.02, 0.06, stemTotal)
        let fsat = Self.familySaturation
        let bandStem = SIMD4<Float>(                    // zero-lag band stems (soft-sat vs the dev p99 ~0.85)
            Self.softSat(stem.vocalsEnergyDev, 0.85),
            Self.softSat(stem.bassEnergyDev, 0.85),
            Self.softSat(stem.otherEnergyDev, 0.85),
            Self.softSat(stem.drumsEnergyDev, 0.85))
        let familyCap = SIMD4<Float>(                   // orchestral-section capture (soft-sat vs its working point)
            Self.softSat(stem.stringsActivityDev, fsat.x),
            Self.softSat(stem.brassActivityDev, fsat.y),
            Self.softSat(stem.woodwindsActivityDev, fsat.z),
            Self.softSat(stem.percussionActivityDev, fsat.w))
        let target = max(bandStem, familyCap) * blend   // whichever separation is alive
        let alpha = Float(dt / (0.30 + dt))
        fam += (target - fam) * alpha

        // Per-family ARTICULATION env (FL.14, Matt "staccato → shorter choppier lines; strings flowing"): each
        // colour reads ITS stem's AttackRatio (baseline ~1.0, sharp peaks ~3.0) via FL.13's colour→stem hybrid.
        // A real-time band-stem signal, alive on ALL genres → no family fallback. Same warmup `blend` gate +
        // ~0.3 s smoothing (shift by section, not per-note). Drives per-family LIFE at respawn; MOTION untouched.
        let staccato = SIMD4<Float>(
            Self.smoothstep(1.05, 2.2, stem.vocalsAttackRatio),
            Self.smoothstep(1.05, 2.2, stem.bassAttackRatio),
            Self.smoothstep(1.05, 2.2, stem.otherAttackRatio),
            Self.smoothstep(1.05, 2.2, stem.drumsAttackRatio)) * blend
        artic += (staccato - artic) * alpha

        // Turn each family's drift slowly at its OWN rate (colours diverge), a touch faster when it's active.
        let turnRate = SIMD4<Float>(0.13, -0.10, 0.17, -0.15)
        driftAngle += (turnRate + fam * 0.30) * Float(dt)
    }

    private func makeConfig() -> RicercarFlowConfig {
        let en = max(0, min(1.2, energyEnv))
        // Per-family drift: each colour follows its OWN current — own turning angle, own speed (slow base + env).
        func drift(_ i: Int) -> (Float, Float) {
            let mag = 0.0010 + 0.0042 * fam[i]
            return (cosf(driftAngle[i]) * mag, sinf(driftAngle[i]) * mag)
        }
        let (d0x, d0y) = drift(0)
        let (d1x, d1y) = drift(1)
        let (d2x, d2y) = drift(2)
        let (d3x, d3y) = drift(3)
        return RicercarFlowConfig(
            width: UInt32(configuration.width),
            height: UInt32(configuration.height),
            particleCount: UInt32(configuration.particleCount),
            frame: frameCounter,
            dt: 1.0 / 60.0,
            time: time,
            // flowSpeed = CURL SWIRL strength (gentle so each family's drift direction dominates, not churn).
            flowSpeed: 0.0012 + 0.0016 * en,
            turbulence: 0.06 + 0.40 * en,   // near-laminar → long coherent streams (ribbons)
            decay: 0.950,                   // long light-trails → each sparse particle draws a long ribbon
            exposure: 1.0,
            homePull: 0.006,                // loose home band → colour identity, currents still weave across
            famStrings: fam.x,
            famBrass: fam.y,
            famWoodwinds: fam.z,
            famPercussion: fam.w,
            pointSize: 6.0,                 // clean light-lines (few, distinct ribbons over dark space)
            baseGlow: 0.006,                // dark ground — the ribbons are the content, dark space between
            energyGlow: 0.60,               // few particles → each ribbon glows bright
            energy: en,
            aspect: Float(configuration.width) / Float(configuration.height),
            d0x: d0x,
            d0y: d0y,
            d1x: d1x,
            d1y: d1y,
            d2x: d2x,
            d2y: d2y,
            d3x: d3x,
            d3y: d3y,
            art0: artic.x,
            art1: artic.y,
            art2: artic.z,
            art3: artic.w)
    }

    // MARK: - Seeding

    /// Deterministic seed: particles split evenly across families, spawned near their home band with staggered
    /// ages. misc.z (life) is legacy — the shader computes life from articulation each frame (FL.14).
    private static func seed(into buffer: MTLBuffer, configuration: RicercarFlowConfiguration) {
        let count = configuration.particleCount
        let ptr = buffer.contents().bindMemory(to: FlowParticle.self, capacity: count)
        var rng: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float((rng >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        let homeY: [Float] = [0.42, 0.24, 0.58, 0.78]   // strings, brass, woodwinds, percussion
        for i in 0..<count {
            let family = i % 4
            let age = next() * 16.0                      // staggered start over a legato-scale life span
            let y = min(0.98, max(0.02, homeY[family] + (next() - 0.5) * 0.42))
            ptr[i] = FlowParticle(
                posVel: SIMD4<Float>(next(), y, 0, 0),
                misc: SIMD4<Float>(Float(family), age, 0, next()))   // misc.z (life) legacy — set in-shader
        }
    }
}

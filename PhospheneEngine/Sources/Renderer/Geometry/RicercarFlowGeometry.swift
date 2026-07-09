// RicercarFlowGeometry.swift — audio-reactive glowing particle flow-field conformer (Fantasia rebuild).
//
// Replaces the rejected fluid-dye geometry (git history preserved via `git mv`). A `ParticleGeometry`
// sibling (D-097), modelled on MitosisGeometry/PhysarumGeometry's per-frame-compute + ping-pong-trail
// contract. The technique is Robert Hodgin's *Magnetosphere* lineage (kernels in RicercarFlow.metal):
// thousands of particles advected through curl-noise turbulence + audio force fields, each carrying an
// instrument-family colour, deposited as additive glowing sprites into an HDR trail that decays each
// frame — the deposit-and-fade trail IS the glowing weaving ribbon of light, tonemapped luminous over a
// deep ground (RICERCAR_DESIGN §FANTASIA REBUILD; refs 01 morphology, deep-space spirit not the light ground).
//
// Audio (Audio Data Hierarchy + FA #67 — one primitive per layer):
//   • MOTION (primary, zero-lag): band deviations `bass/mid/trebDev` → flow speed + turbulence;
//     `beatComposite` rising edge → outward scatter impulse. Motion never rides the laggy family signal.
//   • COLOUR / identity (lag-tolerant): instrument-family capture (StemFeatures 48–55) → per-particle
//     colour brightness. A family lagging a beat reads fine; motion lagging does not (the IFC.6 failure).

import Metal
import simd
import Shared

// MARK: - GPU-mirrored structs (layouts match RicercarFlow.metal exactly)

/// Mirror of MSL `FlowConfig` — 4 uint + 16 float, all 4-byte members ⇒ 80 bytes, no padding.
struct RicercarFlowConfig {
    var width: UInt32
    var height: UInt32
    var particleCount: UInt32
    var frame: UInt32
    var dt: Float
    var time: Float
    var flowSpeed: Float
    var turbulence: Float
    var beat: Float
    var decay: Float
    var exposure: Float
    var homePull: Float
    var famStrings: Float
    var famBrass: Float
    var famWoodwinds: Float
    var famPercussion: Float
    var pointSize: Float
    var baseGlow: Float
    var energyGlow: Float
    var energy: Float
    var aspect: Float
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
    private var beatEnv: Float = 0         // cached-grid beat pulse → on-beat bloom + surge (ACCENT)
    private var fam = SIMD4<Float>(repeating: 0)   // smoothed family activations (identity, lag-tolerant)
    private var time: Float = 0
    private var frameCounter: UInt32 = 0

    /// Per-family soft-saturation working points (IFC.6 dumper corpus) — strings, brass, woodwinds, perc
    /// (hue order). A characteristic strong entry paints full regardless of the family's natural loudness.
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

        // HDR ping-pong trail (rgba16Float — additive deposit accumulates light; filterable for the
        // display bloom taps).
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

        // Zero the trail textures — `.private` contents are undefined, and any NaN there NEVER decays
        // (NaN × decay = NaN), so an unclearedd trail leaves permanent garbage channels (the FL.10 bug).
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

    /// Advance the CPU envelopes. Energy is the zero-lag primary (band deviations), smoothed just enough
    /// to avoid strobe; the beat drives a fast-attack/decay scatter pulse; family activations are the
    /// lag-tolerant colour identity (slower smoothing).
    private func advanceEnvelopes(features feat: FeatureVector, stems stem: StemFeatures) {
        var dt = feat.deltaTime
        if !(dt > 0) { dt = 1.0 / 60.0 }
        dt = min(dt, 1.0 / 30.0)
        time += dt

        // Zero-lag energy: soft-saturated band-deviation sum (D-026), fast smoothing so the flow visibly
        // surges with the music without frame jitter. Saturation 0.5 sizes the response to REAL band-dev
        // magnitudes (typical sum ~0.2–0.6, peaks ~1.5 — devs run small; synthetic 0.45s overstated it).
        let rawEnergy = Self.softSat(max(0, feat.bassDev) + max(0, feat.midDev) + max(0, feat.trebDev), 0.5)
        energyEnv += Float(dt / (0.10 + dt)) * (rawEnergy - energyEnv)

        // Beat pulse from the CACHED GRID (beatPhase01 — a clean per-beat 0→1 ramp, live-drift-locked to
        // ±~20 ms), NOT the live `beatComposite` (saturated near 1.0 on real sessions → fires ~95% of
        // frames → no rhythm at all: the FL.10 sync gap, diagnosed from session 2026-07-09T02-11-28Z).
        // Sharp ON the beat, decaying across it; a stronger accent on the downbeat (barPhase01); gated by
        // pulseAmp01 so silence doesn't pulse. Beat-locked motion on the cached grid is the sanctioned
        // technique (Audio Data Hierarchy Layer 4; the Ferrofluid D-153→D-158 precedent).
        let amp = max(0, min(1, feat.pulseAmp01))
        let beatPulse = powf(max(0, 1 - feat.beatPhase01), 5.0)   // 1.0 at the beat → ~0 by mid-beat
        let downbeat = powf(max(0, 1 - feat.barPhase01), 6.0)     // sharper, peaks on the bar's "1"
        let rawBeat = amp * min(1.0, beatPulse + 0.7 * downbeat)
        // Instant attack (snap up on the beat) + a short release floor so a frame that just misses the
        // exact beat instant still reads as a crisp bloom, not a strobe.
        beatEnv = max(rawBeat, beatEnv - Float(dt) / 0.12)

        // Family activations (identity): warmup-gate on the stem mix (D-019), soft-saturate vs each
        // family's working point, smooth ~0.25 s. Order: strings, brass, woodwinds, percussion (hue order).
        let stemTotal = stem.drumsEnergy + stem.bassEnergy + stem.otherEnergy + stem.vocalsEnergy
        let blend = Self.smoothstep(0.02, 0.06, stemTotal)
        let sat = Self.familySaturation
        let target = SIMD4<Float>(
            Self.softSat(stem.stringsActivityDev, sat.x) * blend,
            Self.softSat(stem.brassActivityDev, sat.y) * blend,
            Self.softSat(stem.woodwindsActivityDev, sat.z) * blend,
            Self.softSat(stem.percussionActivityDev, sat.w) * blend)
        let alpha = Float(dt / (0.25 + dt))
        fam += (target - fam) * alpha
    }

    private func makeConfig() -> RicercarFlowConfig {
        let en = max(0, min(1.2, energyEnv))
        return RicercarFlowConfig(
            width: UInt32(configuration.width),
            height: UInt32(configuration.height),
            particleCount: UInt32(configuration.particleCount),
            frame: frameCounter,
            dt: 1.0 / 60.0,
            time: time,
            // Flow: a slow autonomous drift at rest, surging when loud (the motion sync). Turbulence is
            // kept LOW so the curl cells are large and particles follow long COHERENT paths — the trail
            // then reads as a weaving ribbon of light (ref 01), not a dense turbulent fuzz.
            // flowSpeed is kept BELOW pointSize (in px) so each particle's per-frame deposits OVERLAP into
            // a continuous ribbon — if the step exceeds the sprite width the trail reads as spaced dots. A
            // small on-beat surge (beatEnv) quickens the flow on the beat — an accent ≪ the energy term.
            flowSpeed: 0.0015 + 0.0040 * en + 0.0030 * beatEnv,
            turbulence: 0.06 + 0.40 * en,   // near-laminar → long coherent streams (ribbons)
            beat: beatEnv,
            decay: 0.950,                   // long light-trails → each sparse particle draws a long ribbon
            exposure: 1.0,
            homePull: 0.005,                // very loose → the flow carries families across → weaving, not stripes
            famStrings: fam.x,
            famBrass: fam.y,
            famWoodwinds: fam.z,
            famPercussion: fam.w,
            pointSize: 6.0,                 // clean light-lines (few, distinct ribbons over dark space)
            baseGlow: 0.006,                // dark ground — the ribbons are the content, dark space between
            energyGlow: 0.60,               // few particles → each ribbon glows bright
            energy: en,
            aspect: Float(configuration.width) / Float(configuration.height))
    }

    // MARK: - Seeding

    /// Deterministic seed: particles split evenly across the four families, each spawned near its home
    /// band with a random x and staggered ages/lives (so respawns don't pulse in sync).
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
            let life = 8.0 + next() * 12.0              // 8–20 s (long-lived → long continuous ribbons)
            let age = next() * life                     // staggered start
            let y = min(0.98, max(0.02, homeY[family] + (next() - 0.5) * 0.42))
            ptr[i] = FlowParticle(
                posVel: SIMD4<Float>(next(), y, 0, 0),
                misc: SIMD4<Float>(Float(family), age, life, next()))
        }
    }
}

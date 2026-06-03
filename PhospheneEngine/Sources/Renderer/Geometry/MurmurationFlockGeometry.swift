// MurmurationFlockGeometry — Phase MM emergent starling-flock conformer.
//
// GPU boids (separation / alignment / cohesion) over a 3D spatial grid + a soft
// global roost attractor + per-bird banking, simulated in 3D and projected to
// screen. The dense morphing shape + core→edge density gradient are emergent.
// See docs/presets/MURMURATION_DESIGN.md.
//
// A `ParticleGeometry` sibling (D-097) — owns its own 48-byte `Bird` layout and
// `MurmurationFlock.metal` kernels rather than parameterizing ProceduralGeometry
// (which it replaces as Murmuration's geometry). MM.2 established the silence
// baseline; MM.3 (`computeAudio`) ports the original Particles.metal audio brain
// onto the boids substrate — bass drift/elongation (L1), the drum turning-wave
// (L2), mid edge flutter (L4), vocals breathing (L5) — all from deviation
// primitives (D-026), all inert at zero audio.

// swiftlint:disable file_length

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "MurmurationFlock")

// MARK: - Bird (mirror of MSL `MurmurationBird`, 48 bytes)

/// Per-bird state. Scalar floats (not SIMD) to match the MSL `packed_float3`
/// layout exactly — no alignment padding inside the struct.
@frozen
public struct MurmurationBird: Sendable {
    public var positionX: Float
    public var positionY: Float
    public var positionZ: Float
    public var seed: Float
    public var velocityX: Float
    public var velocityY: Float
    public var velocityZ: Float
    public var bank: Float
    public var speedRnd: Float
    public var neighborCount: Float
    // swiftlint:disable:next identifier_name
    public var _pad0: Float
    // swiftlint:disable:next identifier_name
    public var _pad1: Float

    public init() {
        positionX = 0; positionY = 0; positionZ = 0; seed = 0
        velocityX = 0; velocityY = 0; velocityZ = 0; bank = 0
        speedRnd = 0; neighborCount = 0; _pad0 = 0; _pad1 = 0
    }
}

// MARK: - FlockParams (mirror of MSL `FlockParams`, 144 bytes)

struct FlockParams {
    var particleCount: UInt32
    var gridSide: UInt32
    var cellCapacity: UInt32
    var dt: Float

    var time: Float
    var worldHalfSpan: Float
    var maxSpeed: Float
    var minSpeed: Float

    var maxForce: Float
    var cohesionRadius: Float
    var separationRadius: Float
    var alignmentRadius: Float

    var cohesionWeight: Float
    var separationWeight: Float
    var alignmentWeight: Float
    var roostWeight: Float

    var roostFar: Float
    var bankingRate: Float
    var neighborCap: UInt32
    var wanderWeight: Float

    var roostTarget: SIMD4<Float>

    // MM.3 audio coupling (inert at zero audio). `FlockParams` is uploaded via
    // setBytes each frame (not a persistent GPU contract), so its size may grow
    // freely as long as the MSL mirror in MurmurationFlock.metal stays
    // byte-identical. Re-check `MemoryLayout<FlockParams>.stride == 144`.
    var flockAxis: SIMD4<Float>   // xyz = unit elongation/wave axis, w = elongation
    var drive: SIMD4<Float>       // x = turnGain, y = beatValue, z = propDir, w = waveWidth
    var midEdgeGain: Float        // L4 mid edge-flutter amplitude
    var flockExtent: Float        // nominal half-extent for the wave bird-coordinate
    var audioPad0: Float
    var audioPad1: Float
}

// MARK: - FlockAudio (per-frame coupling scalars, CPU-computed)

/// The per-frame audio drive computed from `FeatureVector` + `StemFeatures`,
/// consumed by `makeParams` to populate the audio fields of `FlockParams` and
/// to modulate the boids weights. All-zero at silence (`.silent`).
struct FlockAudio {
    var flockAxis: SIMD3<Float> = SIMD3(1, 0, 0)  // unit elongation / wave-travel axis
    var elongation: Float = 0                     // L1 comma/ribbon [0, 0.72]
    var driftOffset: SIMD3<Float> = .zero         // L1 macro drift added to the roost
    var turnGain: Float = 0                       // L2 turning-wave FORCE (gentle — must not translate)
    var waveDarkAmp: Float = 0                    // L2 wave DARKENING amplitude (visual, decoupled from force)
    var beatValue: Float = 0                      // L2 decaying beat pulse [0,1]
    var propDir: Float = 1                        // L2 wave direction (±1, per epoch)
    var waveWidth: Float = 0.22                   // L2 triangular bump half-width
    var midEdgeGain: Float = 0                    // L4 edge-flutter amplitude
    var breath: Float = 0                         // L5 cohesion-tightening [0,1]

    static let silent = FlockAudio()
}

// MARK: - Configuration

/// CPU-side flock configuration. The boids weights/radii are the MM.2 silence
/// baseline starting values; tuned against rendered frames + (MM.3) live audio.
public struct MurmurationFlockConfiguration: Sendable {
    public var particleCount: Int
    public var gridSide: Int
    public var cellCapacity: Int
    public var worldHalfSpan: Float

    public var maxSpeed: Float
    public var minSpeed: Float
    public var maxForce: Float
    public var cohesionRadius: Float
    public var alignmentRadius: Float
    public var separationRadius: Float
    public var cohesionWeight: Float
    public var alignmentWeight: Float
    public var separationWeight: Float
    public var roostWeight: Float
    public var roostFar: Float
    public var wanderWeight: Float
    public var bankingRate: Float
    public var neighborCap: Int

    // ── MM.3 audio-coupling gains (all default to a deliberately under-reactive
    // baseline per design §3.1). Continuous substrate drivers are sized well
    // above the per-beat event amplitude (Audio Data Hierarchy ≥ 2×). ──

    /// L1 — world units the roost target drifts per unit of smoothed bass
    /// deviation. The dominant continuous motion (PRIMARY driver).
    public var bassDriftGain: Float
    /// L1 — elongation (comma/ribbon) per unit of positive smoothed bass.
    /// Capped at 0.72 → ≈ 3:1 aspect at sustained high bass.
    public var elongationGain: Float
    /// L2 — peak per-beat turning-wave amplitude before the master energy gate
    /// and `drums_energy_dev` scaling. Kept below the substrate (accent only).
    public var turnBaseAmp: Float
    /// L4 — mid edge-flutter amplitude per unit of positive mid deviation.
    public var midEdgeAmp: Float
    /// L5 — fractional cohesion tightening at full vocal breath (the dark pulse).
    public var vocalsBreathDepth: Float
    /// Seconds (EMA τ) for the slow bass/vocals substrate smoothers.
    public var substrateTau: Float
    /// Nominal flock half-extent normalising the wave bird-coordinate.
    public var flockExtent: Float

    public init(
        particleCount: Int = 55_000,
        gridSide: Int = 24,
        cellCapacity: Int = 96,
        worldHalfSpan: Float = 2.0,
        maxSpeed: Float = 0.7,
        minSpeed: Float = 0.12,
        maxForce: Float = 10.0,
        cohesionRadius: Float = 0.16,
        alignmentRadius: Float = 0.16,
        separationRadius: Float = 0.075,
        cohesionWeight: Float = 3.0,
        alignmentWeight: Float = 3.5,
        separationWeight: Float = 7.0,
        roostWeight: Float = 1.0,
        roostFar: Float = 2.5,
        wanderWeight: Float = 0.34,
        bankingRate: Float = 4.0,
        neighborCap: Int = 32,
        bassDriftGain: Float = 1.0,
        elongationGain: Float = 0.7,
        turnBaseAmp: Float = 0.16,
        midEdgeAmp: Float = 0.22,
        vocalsBreathDepth: Float = 0.30,
        substrateTau: Float = 6.0,
        flockExtent: Float = 0.6
    ) {
        self.particleCount = particleCount
        self.gridSide = gridSide
        self.cellCapacity = cellCapacity
        self.worldHalfSpan = worldHalfSpan
        self.maxSpeed = maxSpeed
        self.minSpeed = minSpeed
        self.maxForce = maxForce
        self.cohesionRadius = cohesionRadius
        self.alignmentRadius = alignmentRadius
        self.separationRadius = separationRadius
        self.cohesionWeight = cohesionWeight
        self.alignmentWeight = alignmentWeight
        self.separationWeight = separationWeight
        self.roostWeight = roostWeight
        self.roostFar = roostFar
        self.wanderWeight = wanderWeight
        self.bankingRate = bankingRate
        self.neighborCap = neighborCap
        self.bassDriftGain = bassDriftGain
        self.elongationGain = elongationGain
        self.turnBaseAmp = turnBaseAmp
        self.midEdgeAmp = midEdgeAmp
        self.vocalsBreathDepth = vocalsBreathDepth
        self.substrateTau = substrateTau
        self.flockExtent = flockExtent
    }
}

// MARK: - MurmurationFlockGeometry

public final class MurmurationFlockGeometry: ParticleGeometry, @unchecked Sendable {

    // MARK: Properties

    public let birdBuffer: MTLBuffer
    public let configuration: MurmurationFlockConfiguration

    /// Frame-budget governor gate (D-057): fraction of birds integrated per frame.
    public var activeParticleFraction: Float = 1.0

    private let cellCountBuffer: MTLBuffer    // atomic_uint per cell
    private let cellSlotBuffer: MTLBuffer     // cellCapacity uint indices per cell

    private let resetPipeline: MTLComputePipelineState
    private let binPipeline: MTLComputePipelineState
    private let boidsPipeline: MTLComputePipelineState
    private let renderPipelineState: MTLRenderPipelineState?

    // MARK: Audio-coupling smoother state (MM.3)
    //
    // EMA accumulators for the slow substrate drivers + master energy gate.
    // Mutated only from `update()` on the single render thread (consistent with
    // the `@unchecked Sendable` contract — no concurrent access).
    private var bassSmoothed: Float = 0          // L1 smoothed bass deviation (signed)
    private var vocalsSmoothed: Float = 0        // L5 smoothed positive vocal deviation
    private var energySmoothed: Float = 0        // master-gate smoothed energy deviation
    private var driftSmoothed: SIMD3<Float> = .zero  // L1 extra-smoothed drift offset
    private var windPhase: Float = 0             // elongation / drift axis rotation

    // MARK: Init

    /// - Parameters:
    ///   - device: Metal device.
    ///   - library: engine `Renderer` library containing the `murmuration_*` functions.
    ///   - configuration: flock parameters.
    ///   - pixelFormat: render output format; pass `nil` for compute-only (tests).
    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: MurmurationFlockConfiguration = .init(),
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.configuration = configuration

        let count = configuration.particleCount
        let birdStride = MemoryLayout<MurmurationBird>.stride
        guard let birds = device.makeBuffer(length: count * birdStride, options: .storageModeShared) else {
            throw MurmurationFlockError.bufferAllocationFailed
        }
        self.birdBuffer = birds

        let cells = configuration.gridSide * configuration.gridSide * configuration.gridSide
        guard let countBuf = device.makeBuffer(length: cells * MemoryLayout<UInt32>.stride,
                                               options: .storageModeShared) else {
            throw MurmurationFlockError.bufferAllocationFailed
        }
        self.cellCountBuffer = countBuf

        let slotBytes = cells * configuration.cellCapacity * MemoryLayout<UInt32>.stride
        guard let slotBuf = device.makeBuffer(length: slotBytes, options: .storageModeShared) else {
            throw MurmurationFlockError.bufferAllocationFailed
        }
        self.cellSlotBuffer = slotBuf

        Self.seedBirds(into: birds, count: count, worldHalfSpan: configuration.worldHalfSpan)

        func compute(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else {
                throw MurmurationFlockError.functionNotFound(name)
            }
            return try device.makeComputePipelineState(function: fn)
        }
        self.resetPipeline = try compute("murmuration_reset_cells")
        self.binPipeline = try compute("murmuration_bin")
        self.boidsPipeline = try compute("murmuration_boids")

        if let pixelFormat {
            guard let vfn = library.makeFunction(name: "murmuration_flock_vertex"),
                  let ffn = library.makeFunction(name: "murmuration_flock_fragment") else {
                throw MurmurationFlockError.functionNotFound("murmuration_flock_vertex/fragment")
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = pixelFormat
            // Dark silhouettes over a bright sky → alpha-blend the RGB, but pin
            // the destination ALPHA channel at 1 (the target is opaque). Letting
            // dst-alpha fall below 1 in sparse regions makes premultiplied
            // consumers (the PNG harness, any compositor) lift those areas toward
            // white — the white-halo artifact. src*0 + dst*1 keeps alpha = 1.
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .zero
            desc.colorAttachments[0].destinationAlphaBlendFactor = .one
            self.renderPipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } else {
            self.renderPipelineState = nil
        }

        logger.info("MurmurationFlockGeometry: \(count) birds, grid \(configuration.gridSide)^3")
    }

    /// Deterministic initial cloud: a loose sphere near the origin with small
    /// tangential velocity so the flock starts already wheeling. Deterministic
    /// (seeded LCG) so test harnesses are reproducible.
    private static func seedBirds(into buffer: MTLBuffer, count: Int, worldHalfSpan: Float) {
        let ptr = buffer.contents().bindMemory(to: MurmurationBird.self, capacity: count)
        var rng: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float((rng >> 33) & 0xFFFFFF) / Float(0xFFFFFF)   // [0,1]
        }
        let radius = min(0.5, worldHalfSpan * 0.25)
        for i in 0..<count {
            var bird = MurmurationBird()
            // Uniform-ish point in a ball (rounded at-rest mass).
            let rndA = next(); let rndB = next(); let rndC = next()
            let theta = rndA * 2.0 * .pi
            let phi = acos(2.0 * rndB - 1.0)
            let rad = radius * powf(rndC, 1.0 / 3.0)
            let sx = rad * sinf(phi) * cosf(theta)
            let sy = rad * sinf(phi) * sinf(theta)
            let sz = rad * cosf(phi)
            bird.positionX = sx; bird.positionY = sy; bird.positionZ = sz
            bird.seed = next()
            bird.speedRnd = next()
            // Tangential start velocity (swirl around y axis).
            bird.velocityX = -sz * 0.6
            bird.velocityY = (next() - 0.5) * 0.2
            bird.velocityZ = sx * 0.6
            ptr[i] = bird
        }
    }

    // MARK: ParticleGeometry — update (reset → bin → boids)

    public func update(
        features: FeatureVector,
        stemFeatures: StemFeatures,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            logger.error("MurmurationFlock.update: makeComputeCommandEncoder failed")
            return
        }

        let cfg = configuration
        // Clamp dt — a long first frame must not blow the integrator up.
        var dt = features.deltaTime
        if !(dt > 0) { dt = 1.0 / 60.0 }
        dt = min(dt, 1.0 / 30.0)

        // MM.3 — compute the per-frame audio drive (D-026 deviation primitives,
        // D-019 warmup blend, §3.1 energy-gated event layer) and displace the
        // procedural roost by the bass-driven macro drift.
        let audio = computeAudio(features: features, stemFeatures: stemFeatures, dt: dt)
        let roost = roostTarget(time: features.time) + audio.driftOffset
        var fp = makeParams(dt: dt, time: features.time, roost: roost, audio: audio)

        // Pass 1: reset cell counts.
        encoder.setComputePipelineState(resetPipeline)
        encoder.setBuffer(cellCountBuffer, offset: 0, index: 0)
        encoder.setBytes(&fp, length: MemoryLayout<FlockParams>.stride, index: 1)
        let cellTotal = cfg.gridSide * cfg.gridSide * cfg.gridSide
        dispatch(encoder, threads: cellTotal)
        encoder.memoryBarrier(scope: .buffers)

        // Pass 2: bin all birds (atomic slot reserve).
        encoder.setComputePipelineState(binPipeline)
        encoder.setBuffer(birdBuffer, offset: 0, index: 0)
        encoder.setBytes(&fp, length: MemoryLayout<FlockParams>.stride, index: 1)
        encoder.setBuffer(cellCountBuffer, offset: 0, index: 2)
        encoder.setBuffer(cellSlotBuffer, offset: 0, index: 3)
        dispatch(encoder, threads: cfg.particleCount)
        encoder.memoryBarrier(scope: .buffers)

        // Pass 3: boids integrate. Governor reduces the integrated count; the
        // remainder keep their previous positions (still binned correctly).
        let fraction = max(0.0, min(1.0, activeParticleFraction))
        let activeCount = max(1, Int(Float(cfg.particleCount) * fraction))
        encoder.setComputePipelineState(boidsPipeline)
        encoder.setBuffer(birdBuffer, offset: 0, index: 0)
        encoder.setBytes(&fp, length: MemoryLayout<FlockParams>.stride, index: 1)
        encoder.setBuffer(cellCountBuffer, offset: 0, index: 2)
        encoder.setBuffer(cellSlotBuffer, offset: 0, index: 3)
        dispatch(encoder, threads: activeCount)

        encoder.endEncoding()
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, threads: Int) {
        let tgSize = 64
        let groups = (threads + tgSize - 1) / tgSize
        encoder.dispatchThreadgroups(
            MTLSize(width: groups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: tgSize, height: 1, depth: 1)
        )
    }

    /// Absolute, bounded global attractor position (world space, near origin).
    /// A slowly-drifting target the flock wanders around — bounded so the mass
    /// stays on-screen. The distance-scaled `roostFar` leash holds the flock
    /// together around it (anti-fragmentation). MM.2 ambient motion (FA #33
    /// carve-out); MM.3 displaces this with the bass-driven roost.
    private func roostTarget(time: Float) -> SIMD3<Float> {
        SIMD3<Float>(
            0.30 * sinf(time * 0.11) + 0.12 * cosf(time * 0.05),
            0.16 * sinf(time * 0.09) + 0.07 * sinf(time * 0.04),
            0.22 * sinf(time * 0.07)
        )
    }

    /// Build the per-frame parameter block. `roost` = flock centroid + drift
    /// bias; `audio` carries the MM.3 coupling (silent for the render path).
    ///
    /// L5 vocals "breathing" (the dark pulse) is applied here as a tightening of
    /// the cohesion/separation weights — denser packing on vocal entries. All
    /// audio terms collapse to the MM.2 baseline when `audio == .silent`.
    private func makeParams(
        dt: Float, time: Float, roost: SIMD3<Float>, audio: FlockAudio
    ) -> FlockParams {
        let cfg = configuration
        let breath = audio.breath
        // L5 dark pulse — density compression. Tighten the inter-bird SPACING
        // (smaller separation radius/weight → birds pack closer, the whole mass
        // contracts) rather than cranking cohesion, which fights the minSpeed
        // floor into a hollow orbiting shell (MM.2 finding).
        let cohesionWeight = cfg.cohesionWeight
        let separationRadius = cfg.separationRadius * (1 - cfg.vocalsBreathDepth * breath)
        let separationWeight = cfg.separationWeight * (1 - 0.20 * breath)
        return FlockParams(
            particleCount: UInt32(cfg.particleCount),
            gridSide: UInt32(cfg.gridSide),
            cellCapacity: UInt32(cfg.cellCapacity),
            dt: dt,
            time: time,
            worldHalfSpan: cfg.worldHalfSpan,
            maxSpeed: cfg.maxSpeed,
            minSpeed: cfg.minSpeed,
            maxForce: cfg.maxForce,
            cohesionRadius: cfg.cohesionRadius,
            separationRadius: separationRadius,
            alignmentRadius: cfg.alignmentRadius,
            cohesionWeight: cohesionWeight,
            separationWeight: separationWeight,
            alignmentWeight: cfg.alignmentWeight,
            roostWeight: cfg.roostWeight,
            roostFar: cfg.roostFar,
            bankingRate: cfg.bankingRate,
            neighborCap: UInt32(cfg.neighborCap),
            wanderWeight: cfg.wanderWeight,
            roostTarget: SIMD4<Float>(roost.x, roost.y, roost.z, 0),
            flockAxis: SIMD4<Float>(audio.flockAxis, audio.elongation),
            drive: SIMD4<Float>(audio.turnGain, audio.beatValue, audio.propDir, audio.waveWidth),
            midEdgeGain: audio.midEdgeGain,
            flockExtent: cfg.flockExtent,
            audioPad0: audio.waveDarkAmp,   // L2 wave darkening (decoupled from the curl force)
            audioPad1: 0
        )
    }

    // MARK: ParticleGeometry — audio coupling (MM.3)

    /// Compute the per-frame audio drive from the live `FeatureVector` and
    /// `StemFeatures`. This is the original `Particles.metal` audio brain ported
    /// onto the boids substrate (design §3.2): drum turning-wave (L2), bass
    /// drift + elongation (L1), mid edge flutter (L4), vocals breathing (L5),
    /// the D-019 warmup stem-blend and the FA #26 cross-genre beat — with the
    /// one improvement over the original: every read is a **deviation primitive**
    /// (D-026), not raw AGC energy.
    ///
    /// Returns `.silent` semantics at zero input: all drives are 0, the smoother
    /// state stays at 0, and `makeParams` reproduces the MM.2 baseline exactly.
    func computeAudio(features feat: FeatureVector, stemFeatures st: StemFeatures, dt: Float) -> FlockAudio {
        let cfg = configuration

        // D-019 warmup blend: full-mix FeatureVector routing → stem routing as
        // stems arrive (~first 10 s are all-zero stems).
        let totalStem = st.drumsEnergy + st.bassEnergy + st.otherEnergy + st.vocalsEnergy
        let blend = Self.smoothstep(0.02, 0.06, totalStem)

        // Per-layer deviation primitives (D-026), warmup-blended, then SOFT-
        // SATURATED. On real music these primitives spike to ~3× (drumsEnergyDev
        // / bassEnergyRel reach ~3.2–3.4, not the docs' ~±0.5) — see
        // project_deviation_primitive_real_range. tanh preserves the common
        // 0.1–0.4 range and caps the transients near ±1 so a 3× spike can't
        // produce a 3× force that tears the boids flock apart (the MM.3 M7
        // failure; FA #4 inverted by over-driven accents).
        // L1 bass (continuous, signed Rel — relaxes negative in quiet sections).
        let bassRel = Self.saturate(Self.lerp(feat.bassAttRel, st.bassEnergyRel, blend))
        // L2 drums (accent, positive Dev). Full-mix proxy: bass_dev.
        let drumsDev = Self.saturate(Self.lerp(feat.bassDev, st.drumsEnergyDev, blend))
        // FA #26 — cross-genre beat: snare- and kick-driven tracks both register.
        let fmBeat = max(feat.beatBass, max(feat.beatMid, feat.beatComposite))
        let beatPulse = Self.lerp(fmBeat, st.drumsBeat, blend)
        // L4 mid edge flutter. Full-mix: mid_att_rel; stem: "other" (§3.2).
        let midRel = Self.saturate(Self.lerp(feat.midAttRel, st.otherEnergyRel, blend))
        // L5 vocals breathing (only present once stems arrive).
        let vocalsDev = Self.saturate(st.vocalsEnergyDev * blend)

        // Slow substrate smoothers (~tau s) — the 4–8 s shape/breath cadence.
        bassSmoothed = Self.ema(bassSmoothed, bassRel, dt: dt, tau: cfg.substrateTau)
        vocalsSmoothed = Self.ema(vocalsSmoothed, max(0, vocalsDev), dt: dt, tau: cfg.substrateTau)

        // Event-layer energy gate (§3.1 master lever) — scales the drum-wave by
        // overall arousal / smoothed energy deviation so calm passages stay
        // near-pure-substrate. Default bias: under-react.
        let energyNow = max(0, bassRel) + max(0, drumsDev) + max(0, midRel)
        energySmoothed = Self.ema(energySmoothed, energyNow, dt: dt, tau: 0.8)
        let arousal01 = max(0, min(1, (feat.arousal + 1) * 0.5))
        let eventGate = max(0, min(1, 0.2 + 0.8 * max(arousal01 - 0.2, energySmoothed)))

        // Elongation/drift axis: a SLOW rotation (a coherent sweep the flock can
        // actually follow, the original's "large sweeping arc"). Rotating it
        // faster than the flock's leash time would self-cancel the macro drift.
        windPhase += dt * (0.05 + 0.05 * abs(bassSmoothed))
        let rawAxis = SIMD3<Float>(cos(windPhase),
                                   0.32 * sin(windPhase * 0.7),
                                   0.22 * sin(windPhase * 0.5))
        let axis = Self.normalized(rawAxis)

        // L1 macro drift (PRIMARY continuous motion) — the whole roost translates
        // along the axis, signed by smoothed bass. Extra-smoothed for inertia,
        // then HARD-BOUNDED to a fraction of the world so the roost (and the
        // flock that follows it) can never be dragged off-screen by a loud
        // passage — the flock must stay framed (the static-wide-camera contract).
        let driftTarget = axis * (bassSmoothed * cfg.bassDriftGain)
        driftSmoothed = Self.ema3(driftSmoothed, driftTarget, dt: dt, tau: cfg.substrateTau * 0.4)
        let driftCap = cfg.worldHalfSpan * 0.30
        let driftMag = driftSmoothed.x * driftSmoothed.x + driftSmoothed.y * driftSmoothed.y
                     + driftSmoothed.z * driftSmoothed.z
        if driftMag > driftCap * driftCap {
            driftSmoothed *= driftCap / driftMag.squareRoot()
        }

        // L1 elongation (comma/ribbon) — only sustained high bass stretches it.
        let elong = max(0, min(0.72, max(0, bassSmoothed) * cfg.elongationGain))

        // L2 drum wave (ACCENT) — gated to ~0 in calm music. The DARKENING
        // amplitude (what reads visually) is decoupled from the FORCE: the curl
        // force must stay gentle (a strong force would translate the flock and
        // invert the Audio Data Hierarchy — the M7 failure), but the dark band
        // can read strong. waveDarkAmp drives the pad0 darkening; turnGain (a
        // small fraction of it) drives the physical roll.
        let waveDarkAmp = max(0, drumsDev) * eventGate
        let turnGain = waveDarkAmp * cfg.turnBaseAmp
        let epoch = floor(feat.time * 2.5)
        let propDir: Float = Self.hash11(epoch) > 0.5 ? 1 : -1

        // L4 mid edge-flutter amplitude.
        let midGain = max(0, midRel) * cfg.midEdgeAmp

        return FlockAudio(
            flockAxis: axis,
            elongation: elong,
            driftOffset: driftSmoothed,
            turnGain: turnGain,
            waveDarkAmp: waveDarkAmp,
            beatValue: max(0, min(1, beatPulse)),
            propDir: propDir,
            waveWidth: 0.30,
            midEdgeGain: midGain,
            breath: max(0, min(1, vocalsSmoothed))
        )
    }

    // MARK: - Math helpers (match the MSL-side primitives)

    private static func smoothstep(_ lo: Float, _ hi: Float, _ value: Float) -> Float {
        guard hi > lo else { return value >= lo ? 1 : 0 }
        let frac = max(0, min(1, (value - lo) / (hi - lo)))
        return frac * frac * (3 - 2 * frac)
    }

    private static func lerp(_ from: Float, _ toValue: Float, _ frac: Float) -> Float {
        from + (toValue - from) * frac
    }

    /// Soft-saturate an audio driver into a bounded operating range. `tanh`
    /// preserves the common 0.1–0.4 deviation range almost linearly and caps the
    /// ~3× transients near ±1, so a loud spike can't produce a proportionally
    /// huge force (the MM.3 M7 failure). See
    /// project_deviation_primitive_real_range.
    private static func saturate(_ value: Float) -> Float { tanh(value) }

    /// Frame-rate-independent EMA toward `target` with time constant `tau` s.
    private static func ema(_ current: Float, _ target: Float, dt: Float, tau: Float) -> Float {
        guard tau > 1e-5, dt > 0 else { return target }
        let alpha = 1 - exp(-dt / tau)
        return current + (target - current) * alpha
    }

    private static func ema3(_ current: SIMD3<Float>, _ target: SIMD3<Float>, dt: Float, tau: Float) -> SIMD3<Float> {
        guard tau > 1e-5, dt > 0 else { return target }
        let alpha = 1 - exp(-dt / tau)
        return current + (target - current) * alpha
    }

    private static func normalized(_ vec: SIMD3<Float>) -> SIMD3<Float> {
        let len = (vec.x * vec.x + vec.y * vec.y + vec.z * vec.z).squareRoot()
        return len > 1e-5 ? vec / len : SIMD3<Float>(1, 0, 0)
    }

    private static func hash11(_ value: Float) -> Float {
        let raw = sin(value) * 43758.5453123
        return raw - floor(raw)
    }

    // MARK: ParticleGeometry — render

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let state = renderPipelineState else {
            logger.warning("MurmurationFlock.render: no render pipeline (compute-only)")
            return
        }
        // The vertex shader reads only position/velocity/bank/neighbourCount +
        // worldHalfSpan; the audio fields are unused on the render path.
        let roost = roostTarget(time: features.time)
        var fp = makeParams(dt: 1.0 / 60.0, time: features.time, roost: roost, audio: .silent)
        encoder.setRenderPipelineState(state)
        encoder.setVertexBuffer(birdBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&fp, length: MemoryLayout<FlockParams>.stride, index: 2)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: configuration.particleCount)
    }
}

// MARK: - Errors

public enum MurmurationFlockError: Error, Sendable {
    case bufferAllocationFailed
    case functionNotFound(String)
}

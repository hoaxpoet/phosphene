// MurmurationFlockGeometry — Phase MM emergent starling-flock conformer.
//
// MM.6 REBUILD on Rama Hoetzlein's **Flock2** orientation-based model (a faithful
// port of the published, code-available reference — FA #73). Each bird carries a
// body **quaternion** + a scalar speed; neighbour influence is a desire to TURN
// (an orientation target in the body frame), not a summed force. The travelling
// dark orientation bands EMERGE from alignment+avoidance coupling; the flock is
// held cohesive AND framed by the peripheral-boundary turn (no roost-attractor
// force). This REPLACES the MM.2/MM.3 force-based boids substrate that fragmented
// under real audio at the MM.3 M7 live review. See `MurmurationFlock.metal` for
// the ported kernel and `docs/presets/MURMURATION_DESIGN.md` §12.
//
// A `ParticleGeometry` sibling (D-097) — owns its own `Bird` layout and
// `MurmurationFlock.metal` kernels. The reset → bin → boids encoder structure,
// render-pass wiring, governor hook, and multi-frame production-path test harness
// pattern are carried forward from MM.2/MM.3; the integrator + audio coupling are
// the MM.6 replacement.

// swiftlint:disable file_length

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "MurmurationFlock")

// MARK: - Bird (mirror of MSL `MurmurationBird`, 64 bytes)

/// Per-bird state. Scalar floats (not SIMD) so the layout matches the MSL
/// `float4 orient` + `packed_float3` members byte-for-byte (no SIMD alignment
/// padding). `orient` is the body quaternion (xyzw); `target` is the persistent
/// heading desire (degrees: x=roll, y=pitch, z=yaw).
@frozen
public struct MurmurationBird: Sendable {
    public var orientX: Float
    public var orientY: Float
    public var orientZ: Float
    public var orientW: Float
    public var positionX: Float
    public var positionY: Float
    public var positionZ: Float
    public var seed: Float
    public var velocityX: Float
    public var velocityY: Float
    public var velocityZ: Float
    public var neighborCount: Float
    public var targetX: Float
    public var targetY: Float
    public var targetZ: Float
    public var speedRnd: Float

    public init() {
        orientX = 0; orientY = 0; orientZ = 0; orientW = 1
        positionX = 0; positionY = 0; positionZ = 0; seed = 0
        velocityX = 0; velocityY = 0; velocityZ = 0; neighborCount = 0
        targetX = 0; targetY = 0; targetZ = 0; speedRnd = 0
    }
}

// MARK: - FlockParams (mirror of MSL `FlockParams`, 208 bytes)

struct FlockParams {
    var particleCount: UInt32
    var gridSide: UInt32
    var cellCapacity: UInt32
    var dt: Float

    var time: Float
    var worldHalfSpan: Float
    var neighborRadius: Float
    var fovCos: Float

    var minSpeed: Float
    var maxSpeed: Float
    var reactionSpeed: Float
    var dynamicStability: Float

    // Faithful aero (metre units; source constants).
    var mass: Float
    var powerParam: Float
    var wingArea: Float
    var liftFactor: Float

    var dragFactor: Float
    var airDensity: Float
    var gravityY: Float
    var neighborCap: UInt32

    var avoidAmt: Float
    var alignAmt: Float
    var cohesionAmt: Float
    var boundaryAmt: Float

    var boundaryCnt: Float
    var pitchDecay: Float
    var pitchMin: Float
    var pitchMax: Float

    var boundHalfY: Float
    var boundSoften: Float
    var avoidGroundAmt: Float
    var avoidCeilAmt: Float

    var anchor: SIMD4<Float>       // xyz = flock anchor (boundary-turn centre) + bass drift

    // ── MM.6 audio turn-desire biases (inert at zero audio) ──
    var flockAxis: SIMD4<Float>    // xyz = unit elongation/wave axis, w = elongation
    var drive: SIMD4<Float>        // x = waveRollDeg(gated), y = beatValue, z = propDir, w = waveWidth
    var midEdgeDeg: Float          // L4 edge-flutter turn jitter (degrees)
    var flockExtent: Float         // guide-segment + wave-coord half-extent (m)
    var framingRadius: Float       // horizontal soft containment radius (m)
    var framingAmt: Float          // framing turn strength

    var viewRadius: Float          // render: world metres → clip half-extent
    var renderYOffset: Float       // render: vertical recentre
    var audioPad0: Float
    var audioPad1: Float
}

// MARK: - FlockAudio (per-frame coupling scalars, CPU-computed)

/// The per-frame audio drive computed from `FeatureVector` + `StemFeatures`,
/// consumed by `makeParams`. All-zero at silence (`.silent`) → the MM.2 silence
/// baseline is reproduced exactly. Every magnitude is a turn-desire bias (degrees
/// or a length offset), never a force.
struct FlockAudio {
    var flockAxis: SIMD3<Float> = SIMD3(1, 0, 0)  // unit elongation / maneuver-sweep axis
    var elongation: Float = 0                     // L1 comma/ribbon envelope stretch [0,0.72]
    var driftOffset: SIMD3<Float> = .zero         // L1 macro drift added to the anchor
    var maneuverYawDeg: Float = 0                 // bar maneuver: gated yaw-swing amplitude (deg)
    var barSweep: Float = 0                       // bar maneuver: wavefront position = barPhase01
    var maneuverDir: Float = 1                    // bar maneuver: sweep direction (±1, per bar)
    var waveWidth: Float = 0.40                   // bar maneuver: triangular bump half-width
    var breath: Float = 0                         // L5 envelope contraction [0,1]

    static let silent = FlockAudio()
}

// MARK: - Configuration

/// CPU-side flock configuration. MM.6 simulates in **literal metre units** with
/// Flock2's faithful aerodynamic model and source constants (Matt's call: don't
/// simplify). The flock self-sizes by the metre-space density (radius ∝ N^⅓);
/// the framing radius, view radius and domain scale as `cbrt(count /
/// referenceCount)` so the per-cell density — and thus the topological neighbour
/// structure and the `boundaryCnt` threshold — is invariant across the test
/// counts (2–6 k) and the production count, while the flock fills the same frame
/// fraction at any count. `neighborRadius` is the real `psmoothradius` (10 m) and
/// the grid resolution follows the domain. Aero / coefficient values are the
/// Flock2 source defaults (app_flock.cpp).
public struct MurmurationFlockConfiguration: Sendable {
    public var particleCount: Int
    public var gridSide: Int
    public var cellCapacity: Int
    public var neighborCap: Int

    // Metre-space substrate.
    public var worldHalfSpan: Float       // domain half (m)
    public var neighborRadius: Float      // psmoothradius (m, source 10)
    public var minSpeed: Float            // m/s (source 5)
    public var maxSpeed: Float            // m/s (source 18)
    public var flockExtent: Float         // guide-segment / wave-coord half-extent (m)
    public var framingRadius: Float       // horizontal containment radius (m)
    public var framingAmt: Float
    public var boundHalfY: Float          // vertical band half-height (m)
    public var boundSoften: Float         // ground/ceiling detection range (m)
    public var avoidGroundAmt: Float
    public var avoidCeilAmt: Float
    public var viewRadius: Float          // render metres → clip half-extent
    public var renderYOffset: Float       // render vertical recentre (m)

    // Faithful aero (source constants).
    public var mass: Float
    public var powerParam: Float
    public var wingArea: Float
    public var liftFactor: Float
    public var dragFactor: Float
    public var airDensity: Float
    public var gravityY: Float

    // Flock2 heading-controller coefficients (source defaults).
    public var reactionSpeed: Float       // control reaction time (ms)
    public var dynamicStability: Float    // [0,1] body→velocity realign per frame
    public var avoidAmt: Float            // k_avoid (source 0.01)
    public var alignAmt: Float            // k_align (source 0.40)
    public var cohesionAmt: Float         // k_coh  (source 0.001)
    public var boundaryAmt: Float         // k_bound (source 0.40)
    public var boundaryCnt: Float         // r_nbrs below which a bird is peripheral
    public var pitchDecay: Float          // source 0.95
    public var pitchMin: Float            // source −40°
    public var pitchMax: Float            // source +20°
    public var fovDegrees: Float          // source 240°

    // ── MM.6 audio-coupling gains (deliberately under-reactive, §3.1). ──
    /// L1 — anchor drift per unit smoothed bass deviation, in `worldHalfSpan`
    /// fractions (hard-capped to 0.30·worldHalfSpan so the flock stays framed).
    public var bassDriftGain: Float
    /// L1 — envelope elongation per unit positive smoothed bass (comma/ribbon).
    public var elongationGain: Float
    /// Bar maneuver — peak per-bar yaw-swing (degrees) before the energy gate and
    /// drum modulation. The flock turns once per bar; the banking wave emerges.
    public var maneuverYawDeg: Float
    /// L5 — fractional envelope contraction at full vocal breath (the dark pulse).
    public var vocalsBreathDepth: Float
    /// Seconds (EMA τ) for the slow bass/vocals substrate smoothers.
    public var substrateTau: Float

    public init(
        particleCount: Int = 48_000,
        referenceCount: Int = 48_000,
        referenceHalfSpan: Float = 75,
        cellCapacity: Int = 64,
        neighborCap: Int = 96,
        reactionSpeed: Float = 2600,
        dynamicStability: Float = 0.8,
        boundaryCnt: Float = 10,
        framingAmt: Float = 0.8,
        avoidGroundAmt: Float = 6.0,
        avoidCeilAmt: Float = 1.5,
        renderYOffset: Float = 0,
        bassDriftGain: Float = 0.6,
        elongationGain: Float = 1.1,
        maneuverYawDeg: Float = 6.0,
        vocalsBreathDepth: Float = 0.16,
        substrateTau: Float = 6.0
    ) {
        self.particleCount = particleCount
        self.cellCapacity = cellCapacity
        self.neighborCap = neighborCap

        // MM.6 round-5 reframe — size the world for VISUAL DENSITY, not the
        // source's open-domain simulation. Matching the source's bird density (10k
        // in 400×150×200 m) spread 48k birds across a ~190 m half-span domain; viewed
        // as a framed murmuration that reads as a small dense core inside a wide
        // sparse spray of countable individuals — the `05_anti_dispersed_no_shape`
        // anti-reference (M7 round-4 failure: maxR reached 355 m, ~1.8× whs — the
        // flock leaked to the world corners and wrapped into a permanent halo).
        //
        // The reference `01` look is a single COHERENT contained ellipsoid that
        // fills the frame: depth-stacking through a coherent mass makes the centre
        // dense (uncountable) and the edge feather, even at 48k. So we (a) size a
        // COMPACT world whose half-span scales as cbrt(count) off a reference span
        // (density + topology count-invariant; flock fills the same frame fraction
        // at any count), (b) scale neighborRadius WITH the domain so the topological
        // gather's 3×3×3-cell candidate count stays UNDER neighborCap — otherwise
        // the examine cap undercounts `rNbrs` and the peripheral-boundary turn
        // degenerates into a weak everyone-pulls-to-anchor (the round-4 spray), and
        // (c) let the topological equilibrium SET the flock size (framingRadius ≈
        // the natural radius) with a direct-velocity containment (in the kernel)
        // catching escapees — the angle-target wall alone saturates through
        // mf_fmodulus and cannot reliably turn a leaked bird home.
        let countScale = powf(Float(max(particleCount, 1)) / Float(max(referenceCount, 1)), 1.0 / 3.0)
        let whs = referenceHalfSpan * countScale
        self.worldHalfSpan = whs
        let nr = whs * (6.0 / 75.0)                         // psmoothradius ∝ domain (6 m at ref)
        self.neighborRadius = nr
        self.gridSide = max(4, Int((2 * whs / nr).rounded()))  // ~25, count-invariant
        let framingR = 0.50 * whs                           // the oblate-wall horizontal radius
        self.framingRadius = framingR
        self.framingAmt = framingAmt
        self.flockExtent = 1.30 * framingR                  // guide-segment reach (comma/ribbon)
        self.boundHalfY = 0.50 * framingR                   // flat-ish disk; the camera tilt rounds it
        self.boundSoften = 0.5 * (0.50 * framingR)
        self.avoidGroundAmt = avoidGroundAmt
        self.avoidCeilAmt = avoidCeilAmt
        // The view maps metres → clip half-extent. Size it so the contained oblate
        // mass (horizontal radius ≈ framingRadius) fills ~70 % of the frame width
        // with a little sky margin, and the feathered edge reaches toward the
        // border — one dense body, individual birds sub-pixel.
        self.viewRadius = framingR * 1.15
        self.renderYOffset = renderYOffset

        // Faithful aero — Flock2 source constants with speeds SCALED for the
        // visual cadence. Source runs at 5-18 m/s in a 200m box viewed from far
        // away; Phosphene fills the frame with a ~40m flock, so real starling
        // speeds look too fast. Scale speeds by 0.3× (preserving the 3.6:1
        // max:min ratio and the thrust/drag/gravity balance — the force
        // Faithful aero — Flock2 source constants VERBATIM (app_flock.cpp).
        // No speed scaling. Sub-stepped at DT=0.005 (200 Hz) per the source.
        self.minSpeed = 5
        self.maxSpeed = 18
        self.mass = 0.08
        self.powerParam = 0.2173
        self.wingArea = 0.0224
        self.liftFactor = 0.5714
        self.dragFactor = 0.1731
        self.airDensity = 1.225
        self.gravityY = -9.8                                // faithful (verbatim source)

        self.reactionSpeed = reactionSpeed
        self.dynamicStability = dynamicStability
        // Avoidance is the mutual-repulsion rule that gives the flock its VOLUME
        // (spacing). The source value (0.01) was calibrated for its loose open
        // domain; in our compact framed world it is too weak to inflate the mass
        // into the vertical envelope, so the flock collapsed to a thin level sheet
        // (round-5b). Raised so birds puff apart in 3D and fill the oblate wall —
        // the rounded ovoid of reference `01` rather than a flat pancake.
        self.avoidAmt = 0.05
        self.alignAmt = 0.40
        self.cohesionAmt = 0.001
        self.boundaryAmt = 0.40
        // boundaryCnt is a TOPOLOGICAL edge threshold (birds with fewer than this
        // many radius+FOV neighbours are "peripheral" and turn inward). Because the
        // domain and neighborRadius both scale as cbrt(count), the equilibrium
        // per-bird neighbour count is count-invariant, so boundaryCnt is a constant
        // (NOT count-scaled — the old linear scaling was a workaround for the fixed
        // 10 m radius). It is kept low (≈10) so the 3×3×3-cell candidate count stays
        // under neighborCap and `rNbrs` is counted accurately: a true topological
        // edge, not the degenerate everyone-is-peripheral state the examine cap
        // produced when boundaryCnt was 96 in a dense neighbourhood.
        self.boundaryCnt = min(boundaryCnt, Float(neighborCap))
        self.pitchDecay = 0.95
        self.pitchMin = -40
        self.pitchMax = 20
        self.fovDegrees = 240

        self.bassDriftGain = bassDriftGain
        self.elongationGain = elongationGain
        self.maneuverYawDeg = maneuverYawDeg
        self.vocalsBreathDepth = vocalsBreathDepth
        self.substrateTau = substrateTau
    }
}

// MARK: - MurmurationFlockGeometry

// swiftlint:disable:next type_body_length
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

    // MARK: Audio-coupling smoother state (MM.6)
    //
    // Mutated only from `update()` / `computeAudio()` on the single render thread
    // (consistent with the `@unchecked Sendable` contract — no concurrent access).
    private var bassSmoothed: Float = 0
    private var vocalsSmoothed: Float = 0
    private var energySmoothed: Float = 0
    private var driftSmoothed: SIMD3<Float> = .zero
    private var windPhase: Float = 0
    // Bar-anchored maneuver state (MM.6 musicality rethink): one coordinated
    // heading-swing per BAR (not per beat — too twitchy), alternating direction,
    // amplitude latched at the downbeat and gated by energy. The banking wave
    // EMERGES from the swing; we do not inject per-bird accents.
    private var lastBarPhase: Float = 0
    private var maneuverDir: Float = 1
    private var maneuverAmp: Float = 0

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
            // the destination ALPHA at 1 (the white-halo fix — see MM.2): a
            // premultiplied consumer would otherwise lift sparse regions toward
            // white. src*0 + dst*1 keeps alpha = 1.
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

    /// Deterministic initial cloud: a loose sphere near the origin with a small
    /// tangential velocity (the flock starts already wheeling) and a body
    /// quaternion already aligned to that velocity. Deterministic (seeded LCG) so
    /// test harnesses are reproducible.
    private static func seedBirds(into buffer: MTLBuffer, count: Int, worldHalfSpan: Float) {
        let ptr = buffer.contents().bindMemory(to: MurmurationBird.self, capacity: count)
        var rng: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float((rng >> 33) & 0xFFFFFF) / Float(0xFFFFFF)   // [0,1]
        }
        let radius = worldHalfSpan * 0.35
        for i in 0..<count {
            var bird = MurmurationBird()
            let rndA = next(); let rndB = next(); let rndC = next()
            let theta = rndA * 2.0 * .pi
            let phi = acos(2.0 * rndB - 1.0)
            let rad = radius * powf(rndC, 1.0 / 3.0)
            let sx = rad * sinf(phi) * cosf(theta)
            let sy = rad * sinf(phi) * sinf(theta) * 0.6   // flatter at rest (aspect)
            let sz = rad * cosf(phi)
            bird.positionX = sx; bird.positionY = sy; bird.positionZ = sz
            bird.seed = next()
            bird.speedRnd = next()
            // Tangential start velocity (swirl around y).
            let vx = -sz * 0.6
            let vy = (next() - 0.5) * 0.1
            let vz = sx * 0.6
            let vel = Self.normalized(SIMD3(vx, vy, vz))
            let startSpeed: Float = 10   // m/s, mid of [5,18] (source range)
            bird.velocityX = vel.x * startSpeed
            bird.velocityY = vel.y * startSpeed
            bird.velocityZ = vel.z * startSpeed
            // Body quaternion aligned so forward (+x) points along velocity.
            let quat = Self.quatFromTo(SIMD3(1, 0, 0), vel)
            bird.orientX = quat.x; bird.orientY = quat.y; bird.orientZ = quat.z; bird.orientW = quat.w
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
        var frameDt = features.deltaTime
        if !(frameDt > 0) { frameDt = 1.0 / 60.0 }
        frameDt = min(frameDt, 1.0 / 30.0)

        let audio = computeAudio(features: features, stemFeatures: stemFeatures, dt: frameDt)
        let anchor = anchorTarget(time: features.time) + audio.driftOffset

        // Sub-step at the source's DT=0.005 (200 Hz). At 60 fps this is ~3 steps
        // per frame. The source's constants are tuned for this rate; running them
        // at 60 Hz directly gives wrong turn rates and unstable aero. Each sub-step
        // re-bins (the grid is UMA-shared, fits in cache at 48k). Audio params are
        // computed once per frame (global-envelope coupling, not per-step dynamics).
        let physicsDt: Float = 0.005
        let steps = max(1, Int(ceilf(frameDt / physicsDt)))
        let stepDt = frameDt / Float(steps)

        let cellTotal = cfg.gridSide * cfg.gridSide * cfg.gridSide
        let fraction = max(0.0, min(1.0, activeParticleFraction))
        let activeCount = max(1, Int(Float(cfg.particleCount) * fraction))

        for _ in 0..<steps {
            var fp = makeParams(dt: stepDt, time: features.time, anchor: anchor, audio: audio)

            encoder.setComputePipelineState(resetPipeline)
            encoder.setBuffer(cellCountBuffer, offset: 0, index: 0)
            encoder.setBytes(&fp, length: MemoryLayout<FlockParams>.stride, index: 1)
            dispatch(encoder, threads: cellTotal)
            encoder.memoryBarrier(scope: .buffers)

            encoder.setComputePipelineState(binPipeline)
            encoder.setBuffer(birdBuffer, offset: 0, index: 0)
            encoder.setBytes(&fp, length: MemoryLayout<FlockParams>.stride, index: 1)
            encoder.setBuffer(cellCountBuffer, offset: 0, index: 2)
            encoder.setBuffer(cellSlotBuffer, offset: 0, index: 3)
            dispatch(encoder, threads: cfg.particleCount)
            encoder.memoryBarrier(scope: .buffers)

            encoder.setComputePipelineState(boidsPipeline)
            encoder.setBuffer(birdBuffer, offset: 0, index: 0)
            encoder.setBytes(&fp, length: MemoryLayout<FlockParams>.stride, index: 1)
            encoder.setBuffer(cellCountBuffer, offset: 0, index: 2)
            encoder.setBuffer(cellSlotBuffer, offset: 0, index: 3)
            dispatch(encoder, threads: activeCount)
            encoder.memoryBarrier(scope: .buffers)
        }

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

    /// Slowly-drifting flock anchor (world space, near origin). The boundary
    /// term frames the flock around this point; the static camera does not
    /// follow it, so this drift IS the ambient motion (FA #33 carve-out). MM.6
    /// adds the bass-driven drift on top (bounded).
    private func anchorTarget(time: Float) -> SIMD3<Float> {
        let whs = configuration.worldHalfSpan
        return SIMD3<Float>(
            whs * (0.03 * sinf(time * 0.11) + 0.015 * cosf(time * 0.05)),
            whs * (0.015 * sinf(time * 0.09)),
            whs * (0.025 * sinf(time * 0.07))
        )
    }

    /// Build the per-frame parameter block. `anchor` = flock centre + bass drift;
    /// `audio` carries the MM.6 turn-desire biases (silent for the render path).
    /// L5 vocals "breathing" tightens the boundary pull (the mass contracts on
    /// vocal phrases). All audio terms collapse to the silence baseline when
    /// `audio == .silent`.
    private func makeParams(
        dt: Float, time: Float, anchor: SIMD3<Float>, audio: FlockAudio
    ) -> FlockParams {
        let cfg = configuration
        // L5 vocals "breathing": on a vocal swell the mass DILATES vertically (the
        // McGill blackening↔dilution). The flock's SIZE is a stiff emergent
        // equilibrium that tightening a bound does NOT shrink (it sits well inside
        // both the framing ellipse and the vertical band) — but an ACTIVE
        // anisotropic force does move it (the same mechanism that elongates it
        // horizontally). So breath drives an active vertical spread: birds pitch
        // away from the band centre → the mass swells in Y, then settles.
        let breathPull = cfg.vocalsBreathDepth * audio.breath
        let fovCos = cosf(cfg.fovDegrees * 0.5 * .pi / 180.0)
        return FlockParams(
            particleCount: UInt32(cfg.particleCount),
            gridSide: UInt32(cfg.gridSide),
            cellCapacity: UInt32(cfg.cellCapacity),
            dt: dt,
            time: time,
            worldHalfSpan: cfg.worldHalfSpan,
            neighborRadius: cfg.neighborRadius,
            fovCos: fovCos,
            minSpeed: cfg.minSpeed,
            maxSpeed: cfg.maxSpeed,
            reactionSpeed: cfg.reactionSpeed,
            dynamicStability: cfg.dynamicStability,
            mass: cfg.mass,
            powerParam: cfg.powerParam,
            wingArea: cfg.wingArea,
            liftFactor: cfg.liftFactor,
            dragFactor: cfg.dragFactor,
            airDensity: cfg.airDensity,
            gravityY: cfg.gravityY,
            neighborCap: UInt32(cfg.neighborCap),
            avoidAmt: cfg.avoidAmt,
            alignAmt: cfg.alignAmt,
            cohesionAmt: cfg.cohesionAmt,
            boundaryAmt: cfg.boundaryAmt,
            boundaryCnt: cfg.boundaryCnt,
            pitchDecay: cfg.pitchDecay,
            pitchMin: cfg.pitchMin,
            pitchMax: cfg.pitchMax,
            boundHalfY: cfg.boundHalfY,
            boundSoften: cfg.boundSoften,
            avoidGroundAmt: cfg.avoidGroundAmt,
            avoidCeilAmt: cfg.avoidCeilAmt,
            anchor: SIMD4<Float>(anchor.x, anchor.y, anchor.z, 0),
            flockAxis: SIMD4<Float>(audio.flockAxis, audio.elongation),
            drive: SIMD4<Float>(audio.maneuverYawDeg, audio.barSweep, audio.maneuverDir, audio.waveWidth),
            midEdgeDeg: 0,
            flockExtent: cfg.flockExtent,
            framingRadius: cfg.framingRadius,
            framingAmt: cfg.framingAmt,
            viewRadius: cfg.viewRadius,
            renderYOffset: cfg.renderYOffset,
            audioPad0: breathPull,    // L5 breath → active vertical spread (dilation)
            audioPad1: 0
        )
    }

    // MARK: ParticleGeometry — audio coupling (MM.6)

    /// Compute the per-frame audio drive from the live `FeatureVector` and
    /// `StemFeatures`, re-expressed (vs MM.3) as gentle biases on the Flock2
    /// turn-desires rather than forces — which is why it can no longer tear the
    /// flock (orientation nudges cannot fling birds). Routes: L1 bass → anchor
    /// drift + guide-segment elongation; L2 drums → swept yaw bias (intensifies
    /// the emergent orientation wave); L4 mid → edge turn-jitter; L5 vocals →
    /// boundary tightening (breathing). D-019 warmup blend + FA #26 cross-genre
    /// beat kept; every read is a deviation primitive (D-026), tanh-saturated and
    /// sized against the real ~3× range (project_deviation_primitive_real_range).
    ///
    /// Returns `.silent` semantics at zero input: all drives 0, smoother state at
    /// 0, `makeParams` reproduces the silence baseline exactly.
    func computeAudio(features feat: FeatureVector, stemFeatures st: StemFeatures, dt: Float) -> FlockAudio {
        let cfg = configuration

        // D-019 warmup blend: full-mix FeatureVector → stem routing as stems arrive.
        let totalStem = st.drumsEnergy + st.bassEnergy + st.otherEnergy + st.vocalsEnergy
        let blend = Self.smoothstep(0.02, 0.06, totalStem)

        // Per-layer deviation primitives (D-026), warmup-blended, then SOFT-
        // SATURATED. On real music these spike to ~3× (drumsEnergyDev/
        // bassEnergyRel reach ~3.2–3.4) — tanh keeps the common 0.1–0.4 range
        // ~linear and caps the spikes near ±1.
        let bassRel = Self.saturate(Self.lerp(feat.bassAttRel, st.bassEnergyRel, blend))
        let drumsDev = Self.saturate(Self.lerp(feat.bassDev, st.drumsEnergyDev, blend))
        let vocalsDev = Self.saturate(st.vocalsEnergyDev * blend)

        // Slow substrate smoothers (~tau s) — the 4–8 s shape/breath cadence.
        bassSmoothed = Self.ema(bassSmoothed, bassRel, dt: dt, tau: cfg.substrateTau)
        vocalsSmoothed = Self.ema(vocalsSmoothed, max(0, vocalsDev), dt: dt, tau: cfg.substrateTau)

        // Event-layer energy gate (§3.1 master lever) — scales the maneuver by
        // overall arousal / smoothed energy so calm passages stay near-pure
        // substrate. Default bias: under-react.
        let energyNow = max(0, bassRel) + max(0, drumsDev)
        energySmoothed = Self.ema(energySmoothed, energyNow, dt: dt, tau: 0.8)
        let arousal01 = max(0, min(1, (feat.arousal + 1) * 0.5))
        let eventGate = max(0, min(1, 0.15 + 0.85 * max(arousal01 - 0.2, energySmoothed)))

        // Elongation / drift axis: a SLOW rotation (a coherent sweep the flock can
        // follow). Rotating faster than the flock's turn time would self-cancel.
        windPhase += dt * (0.012 + 0.018 * abs(bassSmoothed))
        let rawAxis = SIMD3<Float>(cos(windPhase),
                                   0.28 * sin(windPhase * 0.7),
                                   0.22 * sin(windPhase * 0.5))
        let axis = Self.normalized(rawAxis)

        // L1 macro drift (PRIMARY continuous motion) — the anchor translates along
        // the axis, signed by smoothed bass; extra-smoothed for inertia, then
        // HARD-BOUNDED to 0.30·worldHalfSpan so the flock can never be dragged
        // off-frame (static-wide-camera contract). Expressed in world units.
        let driftTarget = axis * (bassSmoothed * cfg.bassDriftGain * cfg.worldHalfSpan)
        driftSmoothed = Self.ema3(driftSmoothed, driftTarget, dt: dt, tau: cfg.substrateTau * 0.4)
        let driftCap = cfg.worldHalfSpan * 0.10   // keep the mass framed even under sustained loud bass
        let driftMag2 = driftSmoothed.x * driftSmoothed.x + driftSmoothed.y * driftSmoothed.y
                      + driftSmoothed.z * driftSmoothed.z
        if driftMag2 > driftCap * driftCap {
            driftSmoothed *= driftCap / driftMag2.squareRoot()
        }

        // L1 elongation (comma/ribbon) — only sustained high bass stretches the
        // containment ellipse along the flock axis. Capped WORLD-RELATIVE so the
        // stretched along-axis wall (framingRadius·(1+3·elong)) stays well inside
        // the world half-span: past it the wall would exceed the wrap boundary and
        // the flock would leak/fragment under sustained loud bass. At framingRadius
        // = 0.5·whs this caps elong ≈ 0.09 (stretch ≈ 1.28) — a clear comma that
        // stays framed and core-dense even under sustained loud bass (the round-5
        // over-stretch read as a thin ribbon drifted to the frame edge — coherent,
        // but over-reacting; the design bias is under-react).
        let elongMax = max(0.05, min(0.5, (cfg.worldHalfSpan * 0.64 / cfg.framingRadius - 1.0) / 3.0))
        let elong = max(0, min(elongMax, max(0, bassSmoothed) * cfg.elongationGain))

        // BAR-ANCHORED MANEUVER (the rethink). On each bar downbeat the flock
        // executes ONE coordinated heading-swing — a gentle yaw that sweeps
        // across the flock axis over the bar (barPhase01 0→1), alternating
        // direction each bar (the weaving zigzag; net translation cancels). The
        // dark banking wave EMERGES from the swing — we do not inject it. The
        // swing amplitude is latched at the downbeat, gated by energy (calm bars
        // barely move) and modulated by the bar's drum energy.
        let barPhase = max(0, min(1, feat.barPhase01))
        if barPhase + 0.5 < lastBarPhase {                 // wrapped 1→0 = downbeat
            maneuverDir = -maneuverDir
            maneuverAmp = cfg.maneuverYawDeg * eventGate * (0.5 + min(1.5, max(0, drumsDev)))
        }
        lastBarPhase = barPhase
        // Fade the swing in over the early bar and out near the end so it reads as
        // one smooth sweep, not a step.
        let barEnvelope = sinf(barPhase * .pi)             // 0 at downbeat, peak mid-bar, 0 at next
        let maneuverNow = maneuverAmp * barEnvelope

        return FlockAudio(
            flockAxis: axis,
            elongation: elong,
            driftOffset: driftSmoothed,
            maneuverYawDeg: maneuverNow,
            barSweep: barPhase,
            maneuverDir: maneuverDir,
            waveWidth: 0.40,
            breath: max(0, min(1, vocalsSmoothed))
        )
    }

    // MARK: - Math helpers

    private static func smoothstep(_ lo: Float, _ hi: Float, _ value: Float) -> Float {
        guard hi > lo else { return value >= lo ? 1 : 0 }
        let frac = max(0, min(1, (value - lo) / (hi - lo)))
        return frac * frac * (3 - 2 * frac)
    }

    private static func lerp(_ from: Float, _ toValue: Float, _ frac: Float) -> Float {
        from + (toValue - from) * frac
    }

    /// Soft-saturate an audio driver into a bounded operating range. `tanh` keeps
    /// the common 0.1–0.4 deviation range ~linear and caps ~3× transients near
    /// ±1, so a loud spike can't produce a proportionally huge bias.
    private static func saturate(_ value: Float) -> Float { tanh(value) }

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

    /// Unit quaternion rotating `from` onto `to` (roll = 0). Matches the MSL
    /// `mf_q_fromto` convention so the seeded orientation is consistent with the
    /// kernel.
    private static func quatFromTo(_ from: SIMD3<Float>, _ to: SIMD3<Float>) -> SIMD4<Float> {
        let fn = normalized(from), tn = normalized(to)
        let dot = max(-1, min(1, fn.x * tn.x + fn.y * tn.y + fn.z * tn.z))
        if dot > 0.9999 { return SIMD4(0, 0, 0, 1) }
        if dot < -0.9999 { return SIMD4(0, 0, 1, 0) }   // 180° about z (for +x → −x)
        let axis = normalized(SIMD3(
            fn.y * tn.z - fn.z * tn.y,
            fn.z * tn.x - fn.x * tn.z,
            fn.x * tn.y - fn.y * tn.x
        ))
        let half = acos(dot) * 0.5
        let sinH = sin(half)
        return SIMD4(sinH * axis.x, sinH * axis.y, sinH * axis.z, cos(half))
    }

    // MARK: ParticleGeometry — render

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let state = renderPipelineState else {
            logger.warning("MurmurationFlock.render: no render pipeline (compute-only)")
            return
        }
        let anchor = anchorTarget(time: features.time)
        var fp = makeParams(dt: 1.0 / 60.0, time: features.time, anchor: anchor, audio: .silent)
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

// DriftMotesGeometry — Compute + sprite pipeline for the Drift Motes preset.
//
// Sibling conformer of `ParticleGeometry` alongside `ProceduralGeometry`
// (Murmuration). Particle presets are siblings, not subclasses (D-097).
//
// Owns its own particle buffer (800 × `Particle`), compute pipeline state
// (`motes_update`), and render pipeline state (`motes_vertex` +
// `motes_fragment` with additive blending). The shared 64-byte `Particle`
// struct is reused as-is — no extension. The Session 2 plan packs hue
// data into the `packed_float4 color` slot at emission time and unpacks
// it in the sprite fragment, so no struct extension is needed there
// either; the open question recorded in `DRIFT_MOTES_DESIGN.md §11.1` is
// resolved by reusing the four 32-bit colour lanes (DM.0/DM.1).
//
// MSL placement decision (DM.1, Task 2.2): the compute kernel and sprite
// vertex/fragment shaders live in the engine library next to
// `Particles.metal` (option a). `ShaderLibrary` concatenates every engine
// `.metal` file into a single MSL translation unit before compilation,
// in **lexicographic filename order**. The shared `Particle` and
// `ParticleConfig` structs declared in `Particles.metal` must therefore
// be in scope before `motes_*` references them — the sibling MSL file is
// named `ParticlesDriftMotes.metal` so it sorts after `Particles.metal`
// (`P-a-r-t-i-c-l-e-s` then `.` (0x2E) < `D` (0x44)). No duplicate struct
// declaration is needed. The preset library hosts the sky-backdrop
// fragment only (`Presets/Shaders/DriftMotes.metal`).

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "DriftMotesGeometry")

// MARK: - Kernel Constants (single source of truth)

/// Canonical constants shared by `DriftMotesGeometry`'s Swift init and the
/// `motes_update` Metal kernel. Swift is the source of truth at runtime —
/// the values here are packed into a `DriftMotesConfig` struct each frame
/// and bound at compute buffer(4); the kernel reads them from the bound
/// config rather than hardcoding. This guarantees the steady-state
/// velocity used at init agrees with the steady state the kernel
/// converges to under its own integration. Retuning wind direction or
/// magnitude in DM.3 happens here once.
public enum DriftMotesKernelConstants {

    /// Direction the wind blows the dust through the volume.
    ///
    /// DM.3.3 retune (Matt 2026-05-11 M7 review): primarily DOWNWARD,
    /// slight leftward drift. Pre-DM.3.3 wind was (-1, -0.2, 0) —
    /// strongly leftward, weak downward — which combined with DM.3.1's
    /// tight upper-right spawn band produced the M7 failure mode:
    /// particles cluster only in the top-right corner because they
    /// drift out the left edge in ~25 s but never traverse the vertical
    /// extent (y-wind 0.059 m/s × max life 9 s = 0.53 visible units —
    /// they can't cross the frame top-to-bottom).
    ///
    /// New wind aligns with the user's "drift down the screen" mental
    /// model: y-velocity 0.287 m/s × 25 s mean lifetime ≈ 7.2 visible
    /// units = the visible vertical extent. Particles complete a full
    /// top-to-bottom traversal during their life.
    ///
    /// NOT a unit vector; the kernel normalises it.
    public static let windDirection = SIMD3<Float>(-0.3, -1.0, 0.0)

    /// Wind force magnitude (world units per second). DM.4 will scale this
    /// by `f.bass_att_rel`; in DM.3.x the magnitude is fixed.
    public static let windMagnitude: Float = 0.3

    /// Velocity damping coefficient applied per integration step. Smaller
    /// values damp faster; the value here gives a velocity time-constant of
    /// ~1/(1-0.97) = 33 frames at 60 fps (~0.55 s).
    public static let dampingPerFrame: Float = 0.97

    /// Frame `delta_time` assumed when computing the init steady-state
    /// velocity. The kernel uses the actual `features.delta_time` per frame;
    /// the small mismatch between the assumed and actual dt at frame 1 is a
    /// negligible first-frame transient that the damping absorbs in <1 s.
    public static let assumedFrameDt: Float = 1.0 / 60.0

    /// Curl-of-fBM turbulence amplitude. Smaller than `windMagnitude` so
    /// the directional sweep dominates the wandering.
    public static let turbulenceScale: Float = 0.15

    /// Spatial frequency of the curl-noise sample point — `pos * freq` is
    /// the noise input. Larger values produce smaller eddies.
    public static let turbulenceSpatialFreq: Float = 0.6

    /// Phase advance into the noise field per second of wall clock.
    /// NOT a `sin(time)` oscillation — this is a translation through a
    /// 3D noise field, which is Failed-Approach-#33-compliant.
    public static let turbulenceTimePhase: Float = 0.1

    /// Half-extent of the shaft volume in world units (`±BOUNDS`).
    /// Particles outside this volume recycle to the top slab.
    public static let bounds = SIMD3<Float>(8.0, 8.0, 4.0)

    /// Particle life in seconds: uniform random in `[lifeMin, lifeMin + lifeRange]`.
    ///
    /// DM.3.3 retune: 5–9 s → 20–30 s. The pre-DM.3.3 lifetime was tuned
    /// against a leftward-dominant wind (visible-region traversal time
    /// ~25 s in x); with the new DM.3.3 downward wind (visible vertical
    /// traversal ~25 s in y), a 20–30 s baseline lets particles complete
    /// the full top-to-bottom drift before dying. At peak music
    /// compression (DM.3 emission-rate scaling, divisor up to 2.35×),
    /// lifetime compresses to 8.5–12.8 s — particles still complete
    /// ~30 % of vertical traversal, faster turnover during loud passages.
    public static let lifeMin: Float = 20.0

    /// See `lifeMin`.
    public static let lifeRange: Float = 10.0

    /// Default warm-amber emission colour. Session 2 replaces this per
    /// particle with a hue baked from `vocalsPitchHz` at emission time.
    public static let defaultWarmHue = SIMD4<Float>(1.0, 0.78, 0.45, 1.0)

    /// Steady-state velocity the kernel's velocity damping converges to
    /// under wind alone (turbulence has zero mean over space). Derived
    /// analytically from `windDirection`, `windMagnitude`, `dampingPerFrame`,
    /// and `assumedFrameDt`: `vel_ss = (force * dt) / (1 - damping)`.
    /// Used to seed velocities at init so particles are already at their
    /// steady-state speed on frame 0 (eliminates the global ramp transient
    /// that biases pairwise-distance statistics in DriftMotesNonFlockTest).
    public static var steadyStateWindVelocity: SIMD3<Float> {
        let len = (windDirection * windDirection).sum().squareRoot()
        let normalized = windDirection / len
        let force = normalized * windMagnitude
        return force * assumedFrameDt / (1.0 - dampingPerFrame)
    }
}

// MARK: - DriftMotesConfig (Metal-side, 64 bytes)

/// GPU-side configuration struct for `motes_update`. 16 floats × 4 bytes
/// = 64 bytes, no padding mismatches with the MSL counterpart (the MSL
/// struct uses `packed_float3` to avoid 16-byte vector alignment).
struct DriftMotesConfig {
    var windDirX: Float
    var windDirY: Float
    var windDirZ: Float
    var windMagnitude: Float
    var boundsX: Float
    var boundsY: Float
    var boundsZ: Float
    var dampingPerFrame: Float
    var turbScale: Float
    var turbSpatialFreq: Float
    var turbTimePhase: Float
    var lifeMin: Float
    var lifeRange: Float
    // swiftlint:disable identifier_name
    var _pad0: Float
    var _pad1: Float
    var _pad2: Float
    // swiftlint:enable identifier_name

    static func current() -> DriftMotesConfig {
        let k = DriftMotesKernelConstants.self
        return DriftMotesConfig(
            windDirX: k.windDirection.x,
            windDirY: k.windDirection.y,
            windDirZ: k.windDirection.z,
            windMagnitude: k.windMagnitude,
            boundsX: k.bounds.x,
            boundsY: k.bounds.y,
            boundsZ: k.bounds.z,
            dampingPerFrame: k.dampingPerFrame,
            turbScale: k.turbulenceScale,
            turbSpatialFreq: k.turbulenceSpatialFreq,
            turbTimePhase: k.turbulenceTimePhase,
            lifeMin: k.lifeMin,
            lifeRange: k.lifeRange,
            _pad0: 0,
            _pad1: 0,
            _pad2: 0
        )
    }
}

// MARK: - DriftMotesGeometry

/// GPU compute + sprite pipeline for the Drift Motes preset (Session 1).
///
/// Particles drift through a directional force field — slow base wind,
/// curl-of-fBM turbulence, recycle on bounds-exit or age expiry. There
/// is no flocking, no neighbour query, no inter-particle force. Audio
/// coupling is intentionally limited in DM.1 to forward compatibility
/// only; the Session 1 field is fully audio-independent.
public final class DriftMotesGeometry: ParticleGeometry, @unchecked Sendable {

    // MARK: - Catalog identity

    /// The preset name that maps to this conformer in the
    /// `applyPreset .particles:` switch. Single source of truth — both the
    /// app-layer dispatch and any preset-name match in tests should refer
    /// to this constant rather than re-typing the literal.
    public static let presetName = "Drift Motes"

    /// Particle count on Tier 2 (M3+) per `DRIFT_MOTES_DESIGN.md §5.7`.
    public static let tier2ParticleCount = 800

    /// Particle count on Tier 1 (M1/M2) per `DRIFT_MOTES_DESIGN.md §5.7`.
    public static let tier1ParticleCount = 400

    // MARK: - Properties

    /// UMA particle buffer — written by `motes_update`, read by `motes_vertex`.
    public let particleBuffer: MTLBuffer

    /// Active particle count (fixed at 800 for Tier 2 in Session 1).
    public let particleCount: Int

    // MARK: - Frame Budget Governor Gate (D-057)

    /// Fraction of particles that receive compute updates each frame.
    /// Range `[0.0, 1.0]`. Default `1.0`.
    public var activeParticleFraction: Float = 1.0

    private let computePipelineState: MTLComputePipelineState
    private let renderPipelineState: MTLRenderPipelineState?

    // MARK: - Init

    /// Build the Drift Motes geometry.
    ///
    /// - Parameters:
    ///   - device: Metal device.
    ///   - library: Compiled engine library containing `motes_update`,
    ///     `motes_vertex`, `motes_fragment`.
    ///   - particleCount: Particle count. Default 800 (Tier 2 target from
    ///     `DRIFT_MOTES_DESIGN.md §5.7`). Tier 1 uses 400 — set externally.
    ///   - pixelFormat: Render target format. Pass `nil` for compute-only
    ///     mode (tests).
    public init(
        device: MTLDevice,
        library: MTLLibrary,
        particleCount: Int = 800,
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.particleCount = particleCount

        // Allocate the particle buffer — UMA zero-copy.
        let stride = MemoryLayout<Particle>.stride
        let byteLength = particleCount * stride
        guard let buffer = device.makeBuffer(length: byteLength, options: .storageModeShared) else {
            throw DriftMotesGeometryError.bufferAllocationFailed
        }
        self.particleBuffer = buffer
        Self.seedParticles(buffer: buffer, count: particleCount)

        // Compile compute pipeline.
        guard let computeFn = library.makeFunction(name: "motes_update") else {
            throw DriftMotesGeometryError.functionNotFound("motes_update")
        }
        self.computePipelineState = try device.makeComputePipelineState(function: computeFn)
        self.renderPipelineState = try Self.makeRenderPipelineState(
            device: device,
            library: library,
            pixelFormat: pixelFormat
        )

        logger.info("DriftMotesGeometry initialized: \(particleCount) particles, \(byteLength) bytes")
    }

    /// Seed the particle buffer with the steady-state cloud distribution.
    ///
    /// DM.3.3 retune: seed uniformly across the VISIBLE region (clip
    /// space ±1, world ±3.64 in x/y) instead of the full ±8 box. Pre-
    /// DM.3.3 init seeded across the entire box, of which only ~20 %
    /// landed inside the visible region at frame 0; combined with the
    /// upper-right-corner steady-state spawn band (DM.3.1's tight band)
    /// the visible field collapsed to a corner cluster within ~25 s.
    /// New seed: ~700 particles visible at frame 0, distributed across
    /// the full visible frame. The init transient is shorter and the
    /// field reads as populated from the first user-visible frame.
    ///
    /// Z range is unchanged (full ±bounds.z) because z is not mapped to
    /// clip space — it affects only sprite UV / shaft math.
    ///
    /// Extracted from `init` to keep the initializer under SwiftLint's
    /// 60-line function-body cap.
    private static func seedParticles(buffer: MTLBuffer, count: Int) {
        let ptr = buffer.contents().bindMemory(to: Particle.self, capacity: count)
        let kc = DriftMotesKernelConstants.self
        let bounds = kc.bounds
        let velSS = kc.steadyStateWindVelocity
        let warm = kc.defaultWarmHue
        // Visible region half-extent in world space (matches vertex shader
        // scale = 2.2 / 8.0 → visibleEdge = 1.0 / scale = 3.636…).
        let visibleEdge: Float = 3.64
        for i in 0..<count {
            let seed = Float(i)
            let s1 = hash01(seed * 0.1234567)
            let s2 = hash01(seed * 0.7654321)
            let s3 = hash01(seed * 1.4142136)
            let s4 = hash01(seed * 0.31831)
            let s5 = hash01(seed * 2.7182818)
            let life = kc.lifeMin + kc.lifeRange * s4
            var particle = Particle(
                positionX: (s1 * 2.0 - 1.0) * visibleEdge,
                positionY: (s2 * 2.0 - 1.0) * visibleEdge,
                positionZ: (s3 * 2.0 - 1.0) * bounds.z,
                life: life,
                size: 6.0,
                colorR: warm.x,
                colorG: warm.y,
                colorB: warm.z,
                colorA: warm.w,
                seed: s1,
                age: s5 * life * 0.999  // [0, life) — avoid frame-0 mass respawn.
            )
            // Initialise velocity to the steady-state wind so particles do
            // not all accelerate from zero in unison (which produces a
            // single global ramp transient that biases pairwise-distance
            // statistics, D-098). `steadyStateWindVelocity` is derived from
            // the same constants the kernel reads from buffer(4), so the
            // directional steady-state agrees by construction.
            particle.velocityX = velSS.x
            particle.velocityY = velSS.y
            particle.velocityZ = velSS.z
            ptr[i] = particle
        }
    }

    /// Build the render pipeline state with additive blending baked in.
    /// Returns `nil` when called without a `pixelFormat` (compute-only
    /// mode for tests). Extracted from `init` to keep the initializer
    /// under SwiftLint's 60-line function-body cap.
    private static func makeRenderPipelineState(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat?
    ) throws -> MTLRenderPipelineState? {
        guard let pixelFormat else { return nil }
        guard let vertexFn = library.makeFunction(name: "motes_vertex"),
              let fragmentFn = library.makeFunction(name: "motes_fragment") else {
            throw DriftMotesGeometryError.functionNotFound("motes_vertex/motes_fragment")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Update

    public func update(
        features: FeatureVector,
        stemFeatures: StemFeatures,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            logger.error("Failed to create compute command encoder")
            return
        }

        // ParticleConfig matches Murmuration's MSL layout (32 bytes). Drift
        // Motes' kernel only reads `particleCount` and `time` from it; the
        // other fields are ignored but kept for binding-layout compatibility
        // with the shared `ParticleConfig` struct in `Particles.metal`.
        var config = ParticleConfig(
            particleCount: UInt32(particleCount),
            decayRate: 0,
            burstThreshold: 0,
            burstVelocity: 0,
            drag: 0,
            time: features.time,
            _pad0: 0,
            _pad1: 0
        )
        var feat = features
        var stems = stemFeatures
        var motesConfig = DriftMotesConfig.current()

        encoder.setComputePipelineState(computePipelineState)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 1)
        encoder.setBytes(&config, length: MemoryLayout<ParticleConfig>.stride, index: 2)
        encoder.setBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 3)
        encoder.setBytes(&motesConfig, length: MemoryLayout<DriftMotesConfig>.stride, index: 4)

        let fraction = max(0.0, min(1.0, activeParticleFraction))
        let activeCount = max(1, Int(Float(particleCount) * fraction))
        let threadgroupSize = min(computePipelineState.maxTotalThreadsPerThreadgroup, 256)
        let threadgroupCount = (activeCount + threadgroupSize - 1) / threadgroupSize

        encoder.dispatchThreadgroups(
            MTLSize(width: threadgroupCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: 1, depth: 1)
        )
        encoder.endEncoding()
    }

    // MARK: - Render

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let renderState = renderPipelineState else {
            logger.warning("render() called without render pipeline state (compute-only mode)")
            return
        }
        var feat = features
        encoder.setRenderPipelineState(renderState)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
    }

    // MARK: - Helpers

    /// Stable hash → [0, 1). Mirrors the MSL `dm_hash_f01` helper so CPU-side
    /// initial seeds match GPU-side rehydration seeds.
    private static func hash01(_ x: Float) -> Float {
        let scaled = sin(x) * 43758.5453
        return scaled - floor(scaled)
    }
}

// MARK: - Errors

public enum DriftMotesGeometryError: Error, Sendable {
    case bufferAllocationFailed
    case functionNotFound(String)
}

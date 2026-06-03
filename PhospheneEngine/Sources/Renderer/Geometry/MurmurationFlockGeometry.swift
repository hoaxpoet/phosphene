// MurmurationFlockGeometry — Phase MM emergent starling-flock conformer.
//
// GPU boids (separation / alignment / cohesion) over a 3D spatial grid + a soft
// global roost attractor + per-bird banking, simulated in 3D and projected to
// screen. The dense morphing shape + core→edge density gradient are emergent.
// See docs/presets/MURMURATION_DESIGN.md.
//
// A `ParticleGeometry` sibling (D-097) — owns its own 48-byte `Bird` layout and
// `MurmurationFlock.metal` kernels rather than parameterizing ProceduralGeometry
// (which it replaces as Murmuration's geometry). MM.2 = the silence baseline; no
// audio coupling yet (roost drifts procedurally, wander noise low). Audio drives
// the roost / orientation-wave / breathing in MM.3.

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

// MARK: - FlockParams (mirror of MSL `FlockParams`, 96 bytes)

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

    var noiseWeight: Float
    var bankingRate: Float
    var neighborCap: UInt32
    var wanderWeight: Float

    var roostTarget: SIMD4<Float>
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
    public var wanderWeight: Float
    public var bankingRate: Float
    public var neighborCap: Int

    public init(
        particleCount: Int = 55_000,
        gridSide: Int = 24,
        cellCapacity: Int = 96,
        worldHalfSpan: Float = 2.0,
        maxSpeed: Float = 0.7,
        minSpeed: Float = 0.18,
        maxForce: Float = 8.0,
        cohesionRadius: Float = 0.16,
        alignmentRadius: Float = 0.16,
        separationRadius: Float = 0.06,
        cohesionWeight: Float = 3.5,
        alignmentWeight: Float = 2.8,
        separationWeight: Float = 5.0,
        roostWeight: Float = 0.9,
        wanderWeight: Float = 0.22,
        bankingRate: Float = 4.0,
        neighborCap: Int = 32
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
        self.wanderWeight = wanderWeight
        self.bankingRate = bankingRate
        self.neighborCap = neighborCap
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

        var fp = makeParams(dt: dt, time: features.time)

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

    /// Build the per-frame parameter block. MM.2: the roost target drifts on a
    /// slow procedural path (ambient — FA #33 carve-out); MM.3 swaps this for
    /// the bass-driven attractor.
    private func makeParams(dt: Float, time: Float) -> FlockParams {
        let cfg = configuration
        let rx = 0.18 * sinf(time * 0.13) + 0.08 * cosf(time * 0.07)
        let ry = 0.10 * sinf(time * 0.11) + 0.05 * sinf(time * 0.05)
        let rz = 0.14 * sinf(time * 0.09)
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
            separationRadius: cfg.separationRadius,
            alignmentRadius: cfg.alignmentRadius,
            cohesionWeight: cfg.cohesionWeight,
            separationWeight: cfg.separationWeight,
            alignmentWeight: cfg.alignmentWeight,
            roostWeight: cfg.roostWeight,
            noiseWeight: 0,
            bankingRate: cfg.bankingRate,
            neighborCap: UInt32(cfg.neighborCap),
            wanderWeight: cfg.wanderWeight,
            roostTarget: SIMD4<Float>(rx, ry, rz, 0)
        )
    }

    // MARK: ParticleGeometry — render

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let state = renderPipelineState else {
            logger.warning("MurmurationFlock.render: no render pipeline (compute-only)")
            return
        }
        var fp = makeParams(dt: 1.0 / 60.0, time: features.time)
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

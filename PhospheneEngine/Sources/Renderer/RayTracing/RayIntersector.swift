// RayIntersector — GPU ray-triangle intersection via native Metal ray tracing.
//
// Uses MTLComputePipelineState + the rt_nearest_hit_kernel / rt_shadow_kernel
// kernels defined in RayTracing.metal.  No MPS dependency.
//
// Two usage patterns:
//
//   Blocking (tests, one-off queries):
//     intersect(rays:against:commandQueue:) → [Intersection]
//     shadowRay(origin:direction:maxDistance:against:commandQueue:) → Bool
//     Both submit a command buffer and wait for GPU completion.
//
//   Non-blocking (render loop, audio-reactive dynamic geometry):
//     encodeNearestHit(rays:against:rayBuffer:hitBuffer:into:)
//     encodeShadow(rays:against:rayBuffer:visibilityBuffer:into:)
//     Encode compute work into a caller-provided command buffer.  Use these
//     after encodeBuild(triangles:into:) in the SAME command buffer so Metal
//     serialises BVH build → intersection without a CPU stall.
//     Pre-allocate rayBuffer / hitBuffer / visibilityBuffer once and reuse.
//
// reflectionDirection is a pure CPU helper — no GPU required.

import Metal
import simd
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "RayIntersector")

// MARK: - RayIntersectorError

/// Errors thrown by ``RayIntersector/init(device:library:)``.
public enum RayIntersectorError: Error, Sendable {
    /// A required Metal shader function was not found in the library.
    case functionNotFound(String)
    /// Compute pipeline state creation failed.
    case pipelineCreationFailed(String)
}

// MARK: - RayIntersector

/// Casts rays against a ``BVHBuilder`` acceleration structure using native Metal kernels.
///
/// ## Dynamic geometry (per-frame audio-reactive use)
///
/// Pre-allocate shared-mode buffers once per in-flight frame:
/// ```swift
/// let rayBuf = device.makeBuffer(length: maxRays * 32, options: .storageModeShared)!
/// let hitBuf = device.makeBuffer(length: maxRays * 16, options: .storageModeShared)!
/// ```
/// Then each frame:
/// ```swift
/// let cmdBuf = commandQueue.makeCommandBuffer()!
/// bvh.encodeBuild(triangles: audioGeometry, into: cmdBuf)   // BVH first
/// intersector.encodeNearestHit(rays: rays, against: bvh.accelerationStructure!,
///                              rayBuffer: rayBuf, hitBuffer: hitBuf, into: cmdBuf)
/// cmdBuf.commit()   // no waitUntilCompleted — GPU runs in parallel with CPU
/// ```
public final class RayIntersector: @unchecked Sendable {

    // MARK: - Types

    /// A ray defined by origin, direction, and distance bounds.
    public struct Ray: Sendable {
        /// Ray origin in world space.
        public var origin: SIMD3<Float>
        /// Minimum intersection distance (> 0 to avoid self-intersection).
        public var minDistance: Float
        /// Ray direction in world space (need not be unit-length).
        public var direction: SIMD3<Float>
        /// Maximum intersection distance.
        public var maxDistance: Float

        /// Create a ray.
        ///
        /// - Parameters:
        ///   - origin: World-space origin.
        ///   - direction: World-space direction.
        ///   - minDistance: Near clip (default 1e-4 to avoid self-intersection).
        ///   - maxDistance: Far clip (default `.infinity`).
        public init(
            origin: SIMD3<Float>,
            direction: SIMD3<Float>,
            minDistance: Float = 1e-4,
            maxDistance: Float = .infinity
        ) {
            self.origin = origin
            self.minDistance = minDistance
            self.direction = direction
            self.maxDistance = maxDistance
        }
    }

    /// The result of a nearest-hit intersection query.
    public struct Intersection: Sendable {
        /// Distance along the ray to the hit. Negative when no triangle was hit.
        public let distance: Float
        /// Index of the intersected triangle. Valid only when ``isHit``.
        public let primitiveIndex: UInt32
        /// Barycentric (u, v) coordinates at the hit point. Valid only when ``isHit``.
        public let coordinates: SIMD2<Float>

        /// `true` when the ray intersected a triangle.
        public var isHit: Bool { distance >= 0 }
    }

    // MARK: - Properties

    /// The Metal device used for buffer allocation and compute dispatch.
    public let device: MTLDevice

    private let nearestHitPipeline: MTLComputePipelineState
    private let shadowPipeline: MTLComputePipelineState

    // MARK: - Initialization

    /// Create a ray intersector, compiling compute pipelines from the given library.
    ///
    /// The library must contain `rt_nearest_hit_kernel` and `rt_shadow_kernel`
    /// (defined in `Renderer/Shaders/RayTracing.metal`).
    ///
    /// - Parameters:
    ///   - device: Metal device on which intersection work will execute.
    ///   - library: Compiled Metal library containing the ray tracing kernels.
    /// - Throws: ``RayIntersectorError`` if a function is missing or pipeline compilation fails.
    public init(device: MTLDevice, library: MTLLibrary) throws {
        self.device = device
        nearestHitPipeline = try Self.makePipeline(
            device: device, library: library, functionName: "rt_nearest_hit_kernel"
        )
        shadowPipeline = try Self.makePipeline(
            device: device, library: library, functionName: "rt_shadow_kernel"
        )
        logger.info("RayIntersector initialized on \(device.name)")
    }

    // MARK: - Blocking Intersection (tests / one-off queries)

    /// Cast rays against an acceleration structure and return nearest-hit results.
    ///
    /// Submits a GPU compute pass and **blocks** until completion.  Use
    /// ``encodeNearestHit(rays:against:rayBuffer:hitBuffer:into:)`` for render-loop use.
    ///
    /// - Parameters:
    ///   - rays: Rays to cast. Order preserved in the returned array.
    ///   - structure: BVH to test against (from ``BVHBuilder``).
    ///   - commandQueue: Queue for submitting GPU work.
    /// - Returns: Per-ray ``Intersection`` results. Empty if encoding fails.
    public func intersect(
        rays: [Ray],
        against structure: MTLAccelerationStructure,
        commandQueue: MTLCommandQueue
    ) -> [Intersection] {
        guard !rays.isEmpty else { return [] }

        guard let rayBuf = makeRayBuffer(rays: rays) else {
            logger.error("RayIntersector.intersect: ray buffer allocation failed")
            return []
        }
        let hitLen = rays.count * MemoryLayout<NearestHitData>.stride
        guard let hitBuf = device.makeBuffer(length: hitLen, options: .storageModeShared) else {
            logger.error("RayIntersector.intersect: hit buffer allocation failed")
            return []
        }
        guard let cmdBuf = commandQueue.makeCommandBuffer() else {
            logger.error("RayIntersector.intersect: command buffer creation failed")
            return []
        }

        encodeNearestHitInternal(
            rayCount: rays.count,
            against: structure,
            rayBuffer: rayBuf,
            hitBuffer: hitBuf,
            into: cmdBuf
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        if let err = cmdBuf.error {
            logger.error("RayIntersector.intersect: GPU error — \(err.localizedDescription)")
            return []
        }
        return readNearestHits(from: hitBuf, count: rays.count)
    }

    /// Test whether a shadow ray is occluded between a surface point and a light.
    ///
    /// Submits a GPU compute pass and **blocks** until completion.  Use
    /// ``encodeShadow(rays:against:rayBuffer:visibilityBuffer:into:)`` for render-loop use.
    ///
    /// - Parameters:
    ///   - origin: Surface point being tested.
    ///   - direction: Direction toward the light source.
    ///   - maxDistance: Far clip — geometry beyond this is not an occluder.
    ///   - structure: BVH to test against.
    ///   - commandQueue: Queue for submitting GPU work.
    /// - Returns: `true` if the ray is occluded (surface is in shadow).
    public func shadowRay(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        maxDistance: Float,
        against structure: MTLAccelerationStructure,
        commandQueue: MTLCommandQueue
    ) -> Bool {
        let ray = Ray(
            origin: origin,
            direction: direction,
            minDistance: 1e-4,
            maxDistance: maxDistance
        )
        guard let rayBuf = makeRayBuffer(rays: [ray]) else {
            logger.error("RayIntersector.shadowRay: ray buffer allocation failed")
            return false
        }
        guard let visBuf = device.makeBuffer(
            length: MemoryLayout<Float>.stride, options: .storageModeShared
        ) else {
            logger.error("RayIntersector.shadowRay: visibility buffer allocation failed")
            return false
        }
        guard let cmdBuf = commandQueue.makeCommandBuffer() else {
            logger.error("RayIntersector.shadowRay: command buffer creation failed")
            return false
        }

        encodeShadowInternal(
            rayCount: 1,
            against: structure,
            rayBuffer: rayBuf,
            visibilityBuffer: visBuf,
            into: cmdBuf
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        if let err = cmdBuf.error {
            logger.error("RayIntersector.shadowRay: GPU error — \(err.localizedDescription)")
            return false
        }
        let ptr = visBuf.contents().bindMemory(to: Float.self, capacity: 1)
        return ptr[0] < 0.5  // 0.0 = occluded, 1.0 = lit
    }

    // MARK: - Non-Blocking Encode (render loop / dynamic geometry)

    /// Encode a nearest-hit intersection compute pass into a caller-provided command buffer.
    ///
    /// Designed for per-frame audio-reactive use.  Call after
    /// ``BVHBuilder/encodeBuild(triangles:into:)`` in the same command buffer so Metal
    /// serialises BVH build then intersection without a CPU stall.
    ///
    /// Callers should pre-allocate `rayBuffer` and `hitBuffer` once per in-flight frame
    /// (stride: 32 bytes/ray and 16 bytes/ray respectively) and reuse them.
    ///
    /// - Parameters:
    ///   - rays: Rays to cast. Written into `rayBuffer` immediately.
    ///   - structure: BVH built by ``BVHBuilder``.
    ///   - rayBuffer: Pre-allocated shared-mode buffer (≥ `rays.count × 32` bytes).
    ///   - hitBuffer: Pre-allocated shared-mode buffer (≥ `rays.count × 16` bytes).
    ///   - commandBuffer: Command buffer to encode into.
    public func encodeNearestHit(
        rays: [Ray],
        against structure: MTLAccelerationStructure,
        rayBuffer: MTLBuffer,
        hitBuffer: MTLBuffer,
        into commandBuffer: MTLCommandBuffer
    ) {
        guard !rays.isEmpty else { return }
        populateRayBuffer(rayBuffer, rays: rays)
        encodeNearestHitInternal(
            rayCount: rays.count,
            against: structure,
            rayBuffer: rayBuffer,
            hitBuffer: hitBuffer,
            into: commandBuffer
        )
    }

    /// Encode a shadow (any-hit) intersection compute pass into a caller-provided command buffer.
    ///
    /// Uses `accept_any_intersection(true)` on the GPU — the intersector stops as soon
    /// as the first occluder is found, which is more efficient than nearest-hit for
    /// shadow queries.
    ///
    /// - Parameters:
    ///   - rays: Shadow rays. Written into `rayBuffer` immediately.
    ///   - structure: BVH built by ``BVHBuilder``.
    ///   - rayBuffer: Pre-allocated shared-mode buffer (≥ `rays.count × 32` bytes).
    ///   - visibilityBuffer: Pre-allocated shared-mode buffer (≥ `rays.count × 4` bytes).
    ///                       Written as Float: 1.0 = lit, 0.0 = occluded.
    ///   - commandBuffer: Command buffer to encode into.
    public func encodeShadow(
        rays: [Ray],
        against structure: MTLAccelerationStructure,
        rayBuffer: MTLBuffer,
        visibilityBuffer: MTLBuffer,
        into commandBuffer: MTLCommandBuffer
    ) {
        guard !rays.isEmpty else { return }
        populateRayBuffer(rayBuffer, rays: rays)
        encodeShadowInternal(
            rayCount: rays.count,
            against: structure,
            rayBuffer: rayBuffer,
            visibilityBuffer: visibilityBuffer,
            into: commandBuffer
        )
    }

    // MARK: - Reflection Direction

    /// Compute the specular reflection direction for an incident ray.
    ///
    /// Pure CPU math — no GPU required. Both inputs should be unit-length.
    ///
    /// - Parameters:
    ///   - incident: Incident direction (pointing **toward** the surface).
    ///   - normal: Surface normal (pointing **away** from the surface).
    /// - Returns: Normalised reflection direction.
    public static func reflectionDirection(
        incident: SIMD3<Float>,
        normal: SIMD3<Float>
    ) -> SIMD3<Float> {
        simd_normalize(incident - 2.0 * simd_dot(incident, normal) * normal)
    }

    // MARK: - Private Encode Helpers

    private func encodeNearestHitInternal(
        rayCount: Int,
        against structure: MTLAccelerationStructure,
        rayBuffer: MTLBuffer,
        hitBuffer: MTLBuffer,
        into cmdBuf: MTLCommandBuffer
    ) {
        guard let encoder = cmdBuf.makeComputeCommandEncoder() else {
            logger.error("RayIntersector: failed to create compute encoder (nearest-hit)")
            return
        }
        encoder.setComputePipelineState(nearestHitPipeline)
        encoder.setAccelerationStructure(structure, bufferIndex: 0)
        encoder.setBuffer(rayBuffer, offset: 0, index: 1)
        encoder.setBuffer(hitBuffer, offset: 0, index: 2)
        dispatch(encoder: encoder, pipeline: nearestHitPipeline, count: rayCount)
        encoder.endEncoding()
    }

    private func encodeShadowInternal(
        rayCount: Int,
        against structure: MTLAccelerationStructure,
        rayBuffer: MTLBuffer,
        visibilityBuffer: MTLBuffer,
        into cmdBuf: MTLCommandBuffer
    ) {
        guard let encoder = cmdBuf.makeComputeCommandEncoder() else {
            logger.error("RayIntersector: failed to create compute encoder (shadow)")
            return
        }
        encoder.setComputePipelineState(shadowPipeline)
        encoder.setAccelerationStructure(structure, bufferIndex: 0)
        encoder.setBuffer(rayBuffer, offset: 0, index: 1)
        encoder.setBuffer(visibilityBuffer, offset: 0, index: 2)
        dispatch(encoder: encoder, pipeline: shadowPipeline, count: rayCount)
        encoder.endEncoding()
    }

    private func dispatch(
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        count: Int
    ) {
        let width = min(count, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
    }
}

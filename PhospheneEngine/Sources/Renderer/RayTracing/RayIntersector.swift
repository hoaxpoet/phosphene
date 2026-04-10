// RayIntersector — GPU ray-triangle intersection via MPSRayIntersector.
//
// Supports two query modes:
//   • Nearest-hit (intersect): finds the closest triangle hit by each ray.
//   • Any-hit (shadowRay): returns true as soon as any occluder is found —
//     more efficient for shadow testing since the GPU stops early.
//
// Both modes submit a Metal command buffer, wait for GPU completion, and read
// results from a .storageModeShared buffer (UMA zero-copy).
//
// reflectionDirection is a pure CPU math helper — no GPU required.

import Metal
import MetalPerformanceShaders
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "RayIntersector")

// MARK: - RayIntersector

/// Casts rays against a ``BVHBuilder`` acceleration structure using MPSRayIntersector.
///
/// Create once and reuse across frames. The underlying `MPSRayIntersector` is
/// configured at init time; do not call from multiple threads concurrently.
public final class RayIntersector: @unchecked Sendable {

    // MARK: - Types

    /// A ray defined by origin, direction, and distance bounds.
    public struct Ray: Sendable {
        /// Ray origin in world space.
        public var origin: SIMD3<Float>
        /// Minimum intersection distance (set > 0 to avoid self-intersection).
        public var minDistance: Float
        /// Ray direction in world space (need not be unit-length).
        public var direction: SIMD3<Float>
        /// Maximum intersection distance.
        public var maxDistance: Float

        /// Create a ray.
        ///
        /// - Parameters:
        ///   - origin: World-space origin.
        ///   - direction: World-space direction (need not be normalised).
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
        /// Distance along the ray to the hit point. Negative when no triangle was hit.
        public let distance: Float
        /// Index of the hit triangle in the original geometry array. Valid only when ``isHit``.
        public let primitiveIndex: UInt32
        /// Barycentric (u, v) coordinates of the hit point. Valid only when ``isHit``.
        public let coordinates: SIMD2<Float>

        /// `true` when the ray intersected a triangle.
        public var isHit: Bool { distance >= 0 }
    }

    // MARK: - Properties

    /// The Metal device used for buffer allocation and command submission.
    public let device: MTLDevice

    // Nearest-hit intersector: finds the closest triangle.
    private let nearestIntersector: MPSRayIntersector
    // Any-hit intersector: stops as soon as the first occluder is found (shadow queries).
    private let shadowIntersector: MPSRayIntersector

    // MARK: - Initialization

    /// Create a ray intersector backed by the given Metal device.
    ///
    /// - Parameter device: Metal device on which GPU intersection work will execute.
    public init(device: MTLDevice) {
        self.device = device

        nearestIntersector = MPSRayIntersector(device: device)
        nearestIntersector.rayDataType          = .originMinDistanceDirectionMaxDistance
        nearestIntersector.intersectionDataType = .distancePrimitiveIndexCoordinates

        shadowIntersector = MPSRayIntersector(device: device)
        shadowIntersector.rayDataType          = .originMinDistanceDirectionMaxDistance
        // Distance-only result is sufficient for occlusion tests.
        shadowIntersector.intersectionDataType = .distance

        logger.info("RayIntersector initialized on \(device.name)")
    }

    // MARK: - Nearest-Hit Intersection

    /// Cast rays against an acceleration structure and return nearest-hit results.
    ///
    /// Submits a GPU compute pass and blocks until completion.
    ///
    /// - Parameters:
    ///   - rays: Rays to cast. Order preserved in the returned array.
    ///   - structure: BVH to test against (from ``BVHBuilder``).
    ///   - commandQueue: Queue for submitting GPU work.
    /// - Returns: Per-ray ``Intersection`` results. Empty if encoding fails.
    public func intersect(
        rays: [Ray],
        against structure: MPSTriangleAccelerationStructure,
        commandQueue: MTLCommandQueue
    ) -> [Intersection] {
        guard !rays.isEmpty else { return [] }

        var rayData = rays.map(RayGPUData.init)
        let rayLen  = rayData.count * MemoryLayout<RayGPUData>.stride

        guard let rayBuf = device.makeBuffer(
            bytes: &rayData, length: rayLen, options: .storageModeShared
        ) else {
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

        nearestIntersector.encodeIntersection(
            commandBuffer: cmdBuf,
            intersectionType: .nearest,
            rayBuffer: rayBuf,
            rayBufferOffset: 0,
            intersectionBuffer: hitBuf,
            intersectionBufferOffset: 0,
            rayCount: rays.count,
            accelerationStructure: structure
        )

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        if let err = cmdBuf.error {
            logger.error("RayIntersector.intersect: GPU error — \(err.localizedDescription)")
            return []
        }

        let ptr = hitBuf.contents().bindMemory(to: NearestHitData.self, capacity: rays.count)
        return (0..<rays.count).map { Intersection(data: ptr[$0]) }
    }

    // MARK: - Shadow Ray

    /// Test whether a shadow ray is occluded between a surface point and a light.
    ///
    /// Uses an any-hit query, which is faster than nearest-hit: the GPU stops as
    /// soon as it finds any occluder within `[minDistance, maxDistance]`.
    ///
    /// - Parameters:
    ///   - origin: Surface point being tested (shadow ray origin).
    ///   - direction: Direction toward the light source.
    ///   - maxDistance: Maximum distance to the light. Geometry beyond this is ignored.
    ///   - structure: BVH to test against.
    ///   - commandQueue: Queue for submitting GPU work.
    /// - Returns: `true` if the ray is occluded (surface is in shadow).
    public func shadowRay(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        maxDistance: Float,
        against structure: MPSTriangleAccelerationStructure,
        commandQueue: MTLCommandQueue
    ) -> Bool {
        let ray = Ray(origin: origin, direction: direction, minDistance: 1e-4, maxDistance: maxDistance)
        var rayData = RayGPUData(ray: ray)

        guard let rayBuf = device.makeBuffer(
            bytes: &rayData,
            length: MemoryLayout<RayGPUData>.stride,
            options: .storageModeShared
        ) else {
            logger.error("RayIntersector.shadowRay: ray buffer allocation failed")
            return false
        }

        guard let hitBuf = device.makeBuffer(
            length: MemoryLayout<ShadowHitData>.stride,
            options: .storageModeShared
        ) else {
            logger.error("RayIntersector.shadowRay: hit buffer allocation failed")
            return false
        }

        guard let cmdBuf = commandQueue.makeCommandBuffer() else {
            logger.error("RayIntersector.shadowRay: command buffer creation failed")
            return false
        }

        shadowIntersector.encodeIntersection(
            commandBuffer: cmdBuf,
            intersectionType: .any,
            rayBuffer: rayBuf,
            rayBufferOffset: 0,
            intersectionBuffer: hitBuf,
            intersectionBufferOffset: 0,
            rayCount: 1,
            accelerationStructure: structure
        )

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        if let err = cmdBuf.error {
            logger.error("RayIntersector.shadowRay: GPU error — \(err.localizedDescription)")
            return false
        }

        let ptr = hitBuf.contents().bindMemory(to: ShadowHitData.self, capacity: 1)
        return ptr[0].distance >= 0
    }

    // MARK: - Reflection Direction

    /// Compute the specular reflection direction for an incident ray.
    ///
    /// Pure CPU math — no GPU work. Both inputs should be unit-length.
    ///
    /// - Parameters:
    ///   - incident: Incident ray direction (pointing **toward** the surface).
    ///   - normal: Surface normal at the hit point (pointing **away** from the surface).
    /// - Returns: Normalised reflection direction.
    public static func reflectionDirection(
        incident: SIMD3<Float>,
        normal: SIMD3<Float>
    ) -> SIMD3<Float> {
        simd_normalize(incident - 2.0 * simd_dot(incident, normal) * normal)
    }
}

// MARK: - Internal GPU Data Layouts

/// Tightly-packed ray struct matching MPSRayOriginMinDistanceDirectionMaxDistance.
///
/// MPS expects packed_float3 (12 bytes), not vector_float3 (16 bytes).
/// Laying out as 8 individual Floats guarantees 32-byte stride with no padding.
private struct RayGPUData {
    var originX: Float
    var originY: Float
    var originZ: Float
    var minDistance: Float
    var directionX: Float
    var directionY: Float
    var directionZ: Float
    var maxDistance: Float

    init(ray: RayIntersector.Ray) {
        originX     = ray.origin.x
        originY     = ray.origin.y
        originZ     = ray.origin.z
        minDistance = ray.minDistance
        directionX  = ray.direction.x
        directionY  = ray.direction.y
        directionZ  = ray.direction.z
        maxDistance = ray.maxDistance
    }
}

/// Nearest-hit result matching MPSIntersectionDistancePrimitiveIndexCoordinates (16 bytes).
private struct NearestHitData {
    var distance: Float
    var primitiveIndex: UInt32
    var baryU: Float
    var baryV: Float
}

/// Any-hit result matching MPSIntersectionDataType.distance (4 bytes).
/// Negative distance means no intersection.
private struct ShadowHitData {
    var distance: Float
}

// MARK: - Intersection initialiser from raw GPU data

private extension RayIntersector.Intersection {
    init(data: NearestHitData) {
        self.distance       = data.distance
        self.primitiveIndex = data.primitiveIndex
        self.coordinates = SIMD2<Float>(data.baryU, data.baryV)
    }
}

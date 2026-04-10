// RayIntersector+Internal — Private GPU buffer layout types for RayIntersector.
//
// Separated from RayIntersector.swift to keep each file within the 400-line limit.
//
// Struct layouts (must match Metal structs in RayTracing.metal exactly):
//   RayGPUData     → RTRay         (32 bytes: 8 × Float, packed_float3 layout)
//   NearestHitData → RTNearestHit  (16 bytes: Float + UInt32 + Float × 2)

import Metal
import simd

// MARK: - RayGPUData

/// Packed ray matching RTRay in RayTracing.metal (32 bytes, 8 × Float).
///
/// Uses individual Float fields to guarantee packed_float3 layout (12 bytes per vector)
/// rather than Swift's SIMD3<Float> which is 16 bytes (aligned).
struct RayGPUData {
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

// MARK: - NearestHitData

/// Nearest-hit result matching RTNearestHit in RayTracing.metal (16 bytes).
struct NearestHitData {
    var distance: Float
    var primitiveIndex: UInt32
    var coordU: Float
    var coordV: Float
}

// MARK: - Intersection initializer from GPU data

extension RayIntersector.Intersection {
    init(data: NearestHitData) {
        self.distance       = data.distance
        self.primitiveIndex = data.primitiveIndex
        self.coordinates    = SIMD2<Float>(data.coordU, data.coordV)
    }
}

// MARK: - Buffer helpers + pipeline compilation

extension RayIntersector {

    func makeRayBuffer(rays: [Ray]) -> MTLBuffer? {
        var data = rays.map(RayGPUData.init)
        return device.makeBuffer(
            bytes: &data,
            length: data.count * MemoryLayout<RayGPUData>.stride,
            options: .storageModeShared
        )
    }

    func populateRayBuffer(_ buffer: MTLBuffer, rays: [Ray]) {
        let ptr = buffer.contents().bindMemory(to: RayGPUData.self, capacity: rays.count)
        for (index, ray) in rays.enumerated() {
            ptr[index] = RayGPUData(ray: ray)
        }
    }

    func readNearestHits(from buffer: MTLBuffer, count: Int) -> [Intersection] {
        let ptr = buffer.contents().bindMemory(to: NearestHitData.self, capacity: count)
        return (0..<count).map { Intersection(data: ptr[$0]) }
    }

    static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        functionName: String
    ) throws -> MTLComputePipelineState {
        guard let function = library.makeFunction(name: functionName) else {
            throw RayIntersectorError.functionNotFound(functionName)
        }
        do {
            return try device.makeComputePipelineState(function: function)
        } catch {
            throw RayIntersectorError.pipelineCreationFailed(
                "\(functionName): \(error.localizedDescription)"
            )
        }
    }
}

// BVHBuilderTests — 4 tests covering BVH construction and rebuild.
//
// Uses XCTest to match the Renderer test pattern from MeshGeneratorTests.
// All tests exercise BVHBuilder directly — no RayIntersector required.

import XCTest
import Metal
@testable import Renderer

final class BVHBuilderTests: XCTestCase {

    private var device: MTLDevice!

    override func setUpWithError() throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        guard dev.supportsRaytracing else {
            throw XCTSkip("Device does not support Metal ray tracing")
        }
        device = dev
    }

    // MARK: - 1. Build with triangles

    /// Building with at least one triangle must produce a non-nil acceleration structure.
    func test_build_withTriangles_createsAccelerationStructure() throws {
        let builder = try BVHBuilder(device: device)
        builder.build(triangles: [
            BVHBuilder.Triangle(
                v0: SIMD3<Float>(-1, -1, -2),
                v1: SIMD3<Float>( 1, -1, -2),
                v2: SIMD3<Float>( 0,  1, -2)
            )
        ])

        XCTAssertNotNil(builder.accelerationStructure,
            "accelerationStructure must be non-nil after building with one triangle")
    }

    // MARK: - 2. Empty geometry

    /// Passing an empty array must not crash and must leave accelerationStructure nil.
    func test_build_emptyGeometry_handlesGracefully() throws {
        let builder = try BVHBuilder(device: device)

        // Must not crash.
        builder.build(triangles: [])

        XCTAssertNil(builder.accelerationStructure,
            "accelerationStructure must be nil when built with empty geometry")
    }

    // MARK: - 3. Rebuild after geometry change

    /// Calling rebuild with different geometry must succeed and replace the previous structure.
    func test_rebuild_afterGeometryChange_succeeds() throws {
        let builder = try BVHBuilder(device: device)

        builder.build(triangles: [
            BVHBuilder.Triangle(
                v0: SIMD3<Float>(-1, 0, -1),
                v1: SIMD3<Float>( 1, 0, -1),
                v2: SIMD3<Float>( 0, 1, -1)
            )
        ])
        XCTAssertNotNil(builder.accelerationStructure, "First build must succeed")

        builder.rebuild(triangles: [
            BVHBuilder.Triangle(
                v0: SIMD3<Float>(-2, -2, -3),
                v1: SIMD3<Float>( 2, -2, -3),
                v2: SIMD3<Float>( 0,  2, -3)
            )
        ])
        XCTAssertNotNil(builder.accelerationStructure,
            "Rebuild with new geometry must produce a non-nil acceleration structure")
    }

    // MARK: - 4. Acceleration structure is not nil

    /// After a successful build the structure is non-nil and triangleCount is correct.
    func test_accelerationStructure_isNotNil() throws {
        let builder = try BVHBuilder(device: device)
        builder.build(triangles: [
            BVHBuilder.Triangle(
                v0: SIMD3<Float>(-1, -1, -1),
                v1: SIMD3<Float>( 1, -1, -1),
                v2: SIMD3<Float>( 0,  1, -1)
            ),
            BVHBuilder.Triangle(
                v0: SIMD3<Float>(-2, -2, -2),
                v1: SIMD3<Float>( 2, -2, -2),
                v2: SIMD3<Float>( 0,  2, -2)
            ),
        ])

        XCTAssertNotNil(builder.accelerationStructure,
            "accelerationStructure must be non-nil after a successful build")
        XCTAssertEqual(builder.triangleCount, 2,
            "triangleCount must equal the number of input triangles")
    }
}

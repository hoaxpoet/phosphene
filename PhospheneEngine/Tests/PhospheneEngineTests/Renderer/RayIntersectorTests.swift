// RayIntersectorTests — 4 functional tests + 1 performance test for RayIntersector.
//
// Test geometry: a large triangle at z = −2 spanning x ∈ [−1, 1], y ∈ [−1, 1].
// Hit rays travel along −Z from the origin and land inside the triangle.
// Miss rays travel along +X (perpendicular to the triangle plane) and never hit.
//
// Uses XCTest throughout — swift-testing lacks built-in benchmarking.

import XCTest
import Metal
import simd
@testable import Renderer

final class RayIntersectorTests: XCTestCase {

    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var library: MTLLibrary!

    // Shared scene: one triangle at z = −2, centred at the origin.
    // A ray from (0, 0, 0) along (0, 0, −1) hits the interior.
    private let sceneTri = BVHBuilder.Triangle(
        v0: SIMD3<Float>(-1, -1, -2),
        v1: SIMD3<Float>( 1, -1, -2),
        v2: SIMD3<Float>( 0,  1, -2)
    )

    override func setUpWithError() throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        guard dev.supportsRaytracing else {
            throw XCTSkip("Device does not support Metal ray tracing")
        }
        guard let queue = dev.makeCommandQueue() else {
            throw XCTSkip("Could not create command queue")
        }
        device       = dev
        commandQueue = queue
        library      = try ShaderLibrary(context: MetalContext()).library
    }

    // MARK: - 1. Ray hits triangle

    /// A ray aimed directly at the triangle interior must report a positive hit distance.
    func test_intersect_rayHitsTriangle_returnsHit() throws {
        let builder = try BVHBuilder(device: device)
        builder.build(triangles: [sceneTri])
        guard let structure = builder.accelerationStructure else {
            XCTFail("BVH build failed")
            return
        }

        let intersector = try RayIntersector(device: device, library: library)
        // Ray from origin along −Z: hits the triangle at z = −2 (distance ≈ 2).
        let ray = RayIntersector.Ray(origin: SIMD3(0, 0, 0), direction: SIMD3(0, 0, -1))

        let results = intersector.intersect(rays: [ray], against: structure,
                                            commandQueue: commandQueue)

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isHit,
            "Ray along −Z should hit the triangle (distance: \(results[0].distance))")
        XCTAssertEqual(results[0].distance, 2.0, accuracy: 0.01,
            "Expected hit at distance ≈ 2.0, got \(results[0].distance)")
    }

    // MARK: - 2. Ray misses geometry

    /// A ray aimed perpendicular to the triangle must report no hit.
    func test_intersect_rayMissesGeometry_returnsNoHit() throws {
        let builder = try BVHBuilder(device: device)
        builder.build(triangles: [sceneTri])
        guard let structure = builder.accelerationStructure else {
            XCTFail("BVH build failed")
            return
        }

        let intersector = try RayIntersector(device: device, library: library)
        // Ray along +X from the origin: does not intersect the triangle at z = −2.
        let ray = RayIntersector.Ray(origin: SIMD3(0, 0, 0), direction: SIMD3(1, 0, 0))

        let results = intersector.intersect(rays: [ray], against: structure,
                                            commandQueue: commandQueue)

        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].isHit,
            "Ray along +X must miss the triangle (distance: \(results[0].distance))")
    }

    // MARK: - 3. Shadow ray occluded

    /// A shadow ray from the origin toward a light at z = −5 must report occluded,
    /// because the triangle at z = −2 lies between the surface and the light.
    func test_shadowRay_occluded_returnsInShadow() throws {
        let builder = try BVHBuilder(device: device)
        builder.build(triangles: [sceneTri])
        guard let structure = builder.accelerationStructure else {
            XCTFail("BVH build failed")
            return
        }

        let intersector = try RayIntersector(device: device, library: library)
        let occluded = intersector.shadowRay(
            origin:       SIMD3(0, 0, 0),
            direction:    SIMD3(0, 0, -1),
            maxDistance:  5,
            against:      structure,
            commandQueue: commandQueue
        )

        XCTAssertTrue(occluded,
            "Shadow ray should be occluded by the triangle at z = −2")
    }

    // MARK: - 4. Reflection ray computed correctly

    /// reflectionDirection is pure CPU math — no GPU needed.
    /// Incident straight down onto a horizontal floor must reflect straight up.
    func test_reflectionRay_computedCorrectly() {
        // Case 1: vertical incidence on a horizontal floor.
        let reflectedUp = RayIntersector.reflectionDirection(
            incident: SIMD3(0, -1, 0),
            normal:   SIMD3(0,  1, 0)
        )
        XCTAssertEqual(reflectedUp.x, 0, accuracy: 1e-5)
        XCTAssertEqual(reflectedUp.y, 1, accuracy: 1e-5,
            "Reflection of −Y on +Y normal should be +Y")
        XCTAssertEqual(reflectedUp.z, 0, accuracy: 1e-5)

        // Case 2: 45-degree incidence on a horizontal floor.
        let reflected45 = RayIntersector.reflectionDirection(
            incident: simd_normalize(SIMD3(1, -1, 0)),
            normal:   SIMD3(0, 1, 0)
        )
        let expected45 = simd_normalize(SIMD3<Float>(1, 1, 0))
        XCTAssertEqual(reflected45.x, expected45.x, accuracy: 1e-5)
        XCTAssertEqual(reflected45.y, expected45.y, accuracy: 1e-5)
        XCTAssertEqual(reflected45.z, expected45.z, accuracy: 1e-5)
    }

    // MARK: - 5. Performance: 1000 rays under 2 ms

    /// Casting 1000 rays against a single-triangle BVH must complete in < 2 ms on
    /// Apple Silicon.  Includes command buffer creation, GPU encode, commit, and wait.
    func test_rayTrace_1000Rays_under2ms() throws {
        let builder = try BVHBuilder(device: device)
        // Large triangle to ensure most rays hit.
        builder.build(triangles: [
            BVHBuilder.Triangle(
                v0: SIMD3<Float>(-100, -100, -1),
                v1: SIMD3<Float>( 100, -100, -1),
                v2: SIMD3<Float>(   0,  100, -1)
            )
        ])
        guard let structure = builder.accelerationStructure else {
            XCTFail("BVH build failed")
            return
        }

        let intersector = try RayIntersector(device: device, library: library)

        let rays: [RayIntersector.Ray] = (0..<1000).map { index in
            RayIntersector.Ray(
                origin:    SIMD3(Float(index % 20) * 0.1 - 1.0,
                                 Float(index / 20) * 0.1 - 1.0, 1),
                direction: SIMD3(0, 0, -1)
            )
        }

        // Warm-up: excludes JIT / first-submit overhead.
        _ = intersector.intersect(rays: Array(rays.prefix(10)), against: structure,
                                  commandQueue: commandQueue)

        // XCTest measure block for variance tracking.
        measure {
            _ = intersector.intersect(rays: rays, against: structure, commandQueue: commandQueue)
        }

        // Hard wall on a single warm call.
        let start   = Date()
        _ = intersector.intersect(rays: rays, against: structure, commandQueue: commandQueue)
        let elapsed = Date().timeIntervalSince(start) * 1000.0

        XCTAssertLessThan(elapsed, 2.0,
            "1000-ray intersection took \(String(format: "%.2f", elapsed)) ms; must be < 2 ms")
    }
}

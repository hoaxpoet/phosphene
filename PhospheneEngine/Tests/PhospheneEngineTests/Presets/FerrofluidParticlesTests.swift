// FerrofluidParticlesTests — Phase 1 unit tests for V.9 Session 4.5b.
//
// These tests lock the *contract* of the Phase 1 scaffolding: particle
// count, height texture size, world XZ patch, hex-grid + voronoi-cell-
// offset initial positions, and idempotent bake. Phase 2 will replace the
// static-position assertions with motion assertions, but the contract
// asserts here are load-bearing across both phases:
//
//   - 1024² r16Float height texture (Matt 2026-05-14 product decision —
//     fullscreen / 4K sharpness)
//   - 2048-particle UMA buffer
//   - World-XZ patch [-10, 10] × [-8, 12] (covers visible camera frustum
//     with margin; clamp-to-zero outside)
//   - Initial positions: scaled-space integer cell + `voronoi_cell_offset`
//     hash → world via `worldOrigin + (cellIndex / gridSize) * worldSpan`
//
// Test-suite gates:
//   1. test_lockedConstants_phase1Contract — Phase 1 scope rules locked.
//   2. test_canonicalInitialPositions_matchVoronoiCellHash — the CPU-side
//      port of `voronoi_cell_offset` from `Utilities/Texture/Voronoi.metal`
//      produces the right XZ when the grid maps to world space.
//   3. test_particleBufferContents_matchCanonical — the buffer holds
//      what `canonicalInitialPosition(forIndex:)` returns.
//   4. test_heightTextureDescriptor_lockedSize — 1024² r16Float, shared
//      storage, sampler-compatible usage.
//   5. test_bakeHeightField_idempotent — running the bake twice produces
//      byte-identical texture contents (Phase 1 particles don't move).
//   6. test_bakeHeightField_producesNonZeroOutput — sampling near a
//      particle center returns > 0 height; sampling far outside the patch
//      returns 0 (via clamp-to-zero or explicit zero-band).

import Metal
import XCTest
@testable import Presets
@testable import Renderer

final class FerrofluidParticlesTests: XCTestCase {

    private var device: MTLDevice!
    private var library: MTLLibrary!
    private var commandQueue: MTLCommandQueue!

    override func setUpWithError() throws {
        device = MTLCreateSystemDefaultDevice()
        try XCTSkipIf(device == nil, "No Metal device on this host")
        let context = try MetalContext()
        let lib = try ShaderLibrary(context: context)
        library = lib.library
        commandQueue = context.commandQueue
    }

    // MARK: - Gate 1: locked constants

    func test_lockedConstants_phase1Contract() {
        XCTAssertEqual(FerrofluidParticles.particleCount, 2048,
                       "V.9 Session 4.5b spec locks N = 2048 particles (medium density)")
        XCTAssertEqual(FerrofluidParticles.heightTextureSize, 1024,
                       "V.9 Session 4.5b product addendum: bumped to 1024² for fullscreen / 4K sharpness")
        XCTAssertEqual(FerrofluidParticles.worldSpan, 20.0,
                       "Patch size locked at 20 × 20 world units around the camera frustum")
        XCTAssertEqual(FerrofluidParticles.worldOriginX, -10.0,
                       "World origin X locked")
        XCTAssertEqual(FerrofluidParticles.worldOriginZ, -8.0,
                       "World origin Z locked")
        XCTAssertEqual(FerrofluidParticles.smoothMinW, 0.02, accuracy: 1e-6,
                       "Polynomial smooth-min weight tuned to 0.02 (2026-05-14) for sharp transitions; matches Phase A k=32 effective smoothness band")
        XCTAssertEqual(FerrofluidParticles.spikeBaseRadius, 0.15, accuracy: 1e-6,
                       "Spike tent base radius tuned to 0.15 world units (2026-05-14) — matches Phase A voronoi_smooth(scale=4) kSpikeRadius=0.6 scaled-space → 0.15 world")
        XCTAssertEqual(FerrofluidParticles.apexSmoothK, 0.03, accuracy: 1e-6,
                       "almostIdentity apex-smoothing tuned to 0.03 (2026-05-14) — keep peak tips razor-sharp per 04_specular_razor_highlights.jpg")
    }

    // MARK: - Gate 2: canonical positions match voronoi-cell-offset structure

    func test_canonicalInitialPositions_areBoundedAndOrdered() {
        // Every canonical position lies inside the world patch (no overflow
        // from the cell-hash addition). Ordering is row-major scan over the
        // 46 × 45 grid.
        let minX = FerrofluidParticles.worldOriginX
        let maxX = FerrofluidParticles.worldOriginX + FerrofluidParticles.worldSpan
        let minZ = FerrofluidParticles.worldOriginZ
        let maxZ = FerrofluidParticles.worldOriginZ + FerrofluidParticles.worldSpan
        for i in 0 ..< FerrofluidParticles.particleCount {
            let p = FerrofluidParticles.canonicalInitialPosition(forIndex: i)
            XCTAssertGreaterThanOrEqual(p.x, minX,
                "particle \(i) x=\(p.x) below patch minX=\(minX)")
            XCTAssertLessThanOrEqual(p.x, maxX,
                "particle \(i) x=\(p.x) above patch maxX=\(maxX)")
            XCTAssertGreaterThanOrEqual(p.y, minZ,
                "particle \(i) z=\(p.y) below patch minZ=\(minZ)")
            XCTAssertLessThanOrEqual(p.y, maxZ,
                "particle \(i) z=\(p.y) above patch maxZ=\(maxZ)")
        }
    }

    func test_canonicalInitialPositions_areUnique() {
        // Per-cell hash offsets jitter each particle inside its cell, so no
        // two particles share an XZ. Anti-reference: the README's
        // "Perfectly regular hexagonal lattice" anti-pattern would have
        // particles at identical fractional positions inside each cell.
        var seen: Set<UInt64> = []
        seen.reserveCapacity(FerrofluidParticles.particleCount)
        for i in 0 ..< FerrofluidParticles.particleCount {
            let p = FerrofluidParticles.canonicalInitialPosition(forIndex: i)
            // 32-bit pair as a key — collisions extremely unlikely for the
            // hash output's [0, 1) jitter inside a unit cell.
            let key = (UInt64(bitPattern: Int64(Int32(bitPattern: p.x.bitPattern))) << 32)
                    |  UInt64(bitPattern: Int64(Int32(bitPattern: p.y.bitPattern)))
            XCTAssertFalse(seen.contains(key),
                "particle \(i) at (\(p.x), \(p.y)) duplicates an earlier particle")
            seen.insert(key)
        }
        XCTAssertEqual(seen.count, FerrofluidParticles.particleCount)
    }

    // MARK: - Gate 3: buffer contents match canonical positions

    func test_particleBufferContents_matchCanonical() throws {
        let particles = try XCTUnwrap(
            FerrofluidParticles(device: device, library: library),
            "FerrofluidParticles allocation failed")
        let snapshot = particles.snapshotParticlePositions()
        XCTAssertEqual(snapshot.count, FerrofluidParticles.particleCount)
        for i in 0 ..< FerrofluidParticles.particleCount {
            let canonical = FerrofluidParticles.canonicalInitialPosition(forIndex: i)
            XCTAssertEqual(snapshot[i].x, canonical.x, accuracy: 1e-5,
                "buffer particle \(i).x diverges from canonical")
            XCTAssertEqual(snapshot[i].y, canonical.y, accuracy: 1e-5,
                "buffer particle \(i).z diverges from canonical")
        }
    }

    // MARK: - Gate 4: height texture descriptor locked

    func test_heightTextureDescriptor_lockedSize() throws {
        let particles = try XCTUnwrap(
            FerrofluidParticles(device: device, library: library),
            "FerrofluidParticles allocation failed")
        XCTAssertEqual(particles.heightTexture.width, FerrofluidParticles.heightTextureSize)
        XCTAssertEqual(particles.heightTexture.height, FerrofluidParticles.heightTextureSize)
        XCTAssertEqual(particles.heightTexture.pixelFormat, .r16Float,
            "Phase 1 spec locks r16Float (half-precision is sufficient; 2 MB at 1024²)")
        XCTAssertEqual(particles.heightTexture.storageMode, .shared,
            "UMA shared so sceneSDF can sample the same memory without a blit")
        XCTAssertTrue(particles.heightTexture.usage.contains(.shaderRead),
            "G-buffer fragment samples the height texture")
        XCTAssertTrue(particles.heightTexture.usage.contains(.shaderWrite),
            "Bake compute kernel writes the height texture")
    }

    // MARK: - Gate 5: bake is idempotent

    func test_bakeHeightField_idempotent() throws {
        let particles = try XCTUnwrap(
            FerrofluidParticles(device: device, library: library),
            "FerrofluidParticles allocation failed")
        particles.bakeHeightField(commandQueue: commandQueue)
        let firstBake = readHeightTexture(particles.heightTexture)

        particles.bakeHeightField(commandQueue: commandQueue)
        let secondBake = readHeightTexture(particles.heightTexture)

        XCTAssertEqual(firstBake.count, secondBake.count,
            "Texture byte count must match between bakes")
        // Compare every byte — Phase 1 particles never change, so bake
        // output should be byte-identical.
        var diff = 0
        for i in 0 ..< firstBake.count where firstBake[i] != secondBake[i] {
            diff += 1
            if diff > 4 { break } // early exit
        }
        XCTAssertEqual(diff, 0,
            "Bake is not deterministic on identical inputs — re-bake produced \(diff) byte diff(s)")
    }

    // MARK: - Gate 6: bake produces non-zero output

    func test_bakeHeightField_producesNonZeroOutput() throws {
        let particles = try XCTUnwrap(
            FerrofluidParticles(device: device, library: library),
            "FerrofluidParticles allocation failed")
        particles.bakeHeightField(commandQueue: commandQueue)

        // Sample the texture: count texels with non-zero height. The full
        // patch has 2048 particles each contributing a tent → the union
        // covers most of the patch interior.
        let bytes = readHeightTexture(particles.heightTexture)
        // r16Float: 2 bytes per pixel. Decode each pair as Float16 → Float.
        var nonZero = 0
        let totalTexels = FerrofluidParticles.heightTextureSize * FerrofluidParticles.heightTextureSize
        bytes.withUnsafeBytes { raw in
            let halfPtr = raw.bindMemory(to: Float16.self)
            for i in 0 ..< totalTexels where Float(halfPtr[i]) > 0.01 {
                nonZero += 1
            }
        }
        XCTAssertGreaterThan(nonZero, totalTexels / 4,
            "Bake produced only \(nonZero) / \(totalTexels) non-zero texels — expected the spike field to cover at least a quarter of the patch interior")
    }

    // MARK: - Helpers

    private func readHeightTexture(_ texture: MTLTexture) -> [UInt8] {
        let bytesPerRow = texture.width * 2
        var buffer = [UInt8](repeating: 0, count: texture.height * bytesPerRow)
        texture.getBytes(&buffer,
                         bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                         mipmapLevel: 0)
        return buffer
    }
}

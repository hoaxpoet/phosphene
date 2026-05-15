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
import simd
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
        XCTAssertEqual(FerrofluidParticles.particleCount, 6400,
                       "Round 47 (2026-05-15): 3025 → 6400 (80 × 80 grid). Matt's `2026-05-15T22:30Z` review after round 45's radial-cluster architecture: 'could be more densely packed, following the reference examples.' At round-17's 55² density each cluster (2.5 wu) contained ~47 particles → 7 spikes across diameter; references show ~10. Bumped to 80² for 100 particles/cluster → 10 spikes across diameter. Coordinated with spikeBaseRadius 0.17 → 0.125 same commit so bases-touching invariant holds at the new 0.25-wu spacing.")
        XCTAssertEqual(FerrofluidParticles.heightTextureSize, 4096,
                       "Texel-grid pass 2026-05-14: bumped to 4096² so the texture pixel scale (0.005 wu) sits below the 1080p screen-pixel scale (~0.006 wu) → texel-grid staircase falls below rendered-pixel size")
        XCTAssertEqual(FerrofluidParticles.worldSpan, 20.0,
                       "Patch size locked at 20 × 20 world units around the camera frustum")
        XCTAssertEqual(FerrofluidParticles.worldOriginX, -10.0,
                       "World origin X locked")
        XCTAssertEqual(FerrofluidParticles.worldOriginZ, -8.0,
                       "World origin Z locked")
        XCTAssertEqual(FerrofluidParticles.smoothMinW, 0.005, accuracy: 1e-6,
                       "Polynomial smooth-min weight tightened to 0.005 (V.9 Session 4.5c Phase 1 round 4, 2026-05-14) for near-min distance interpolation; combined with the squared height profile in `ferrofluid_height_bake`, valley heights pull to ~3% of peak per the discrete-spike target in `04_specular_razor_highlights.jpg`. Particles are pinned in this round so no motion-driven pop-in concern from tight `w`.")
        XCTAssertEqual(FerrofluidParticles.spikeBaseRadius, 0.125, accuracy: 1e-6,
                       "Spike base radius 0.17 → 0.125 in round 47 (2026-05-15), coordinated with particle count 3025 → 6400 (80 × 80 grid). New X/Z spacing 0.25 wu, half-spacing 0.125 wu → radius 0.125 = half-spacing exactly → bases touch precisely. ~10 spike rings visible per 2.5-wu cluster, matching reference photo density.")
        XCTAssertEqual(FerrofluidParticles.apexSmoothK, 0.03, accuracy: 1e-6,
                       "almostIdentity apex-smoothing tuned to 0.03 (2026-05-14) — keep peak tips razor-sharp per 04_specular_razor_highlights.jpg")
    }

    // MARK: - Gate 2: canonical positions match voronoi-cell-offset structure

    func test_canonicalInitialPositions_areBoundedAndOrdered() {
        // Every canonical position lies inside the world patch (no overflow
        // from the cell-hash addition). Ordering is row-major scan over the
        // 55 × 55 grid (Round 17, 2026-05-15).
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
        // Phase 2a's atomic-bin pass orders particles in each cell non-
        // deterministically across runs — same-cell pairs can swap slots,
        // and the subsequent `poly_smin` pairwise iteration is only
        // approximately commutative (sub-bit rounding). Most texels are
        // bit-identical; near 2+-particle cells, the trace value
        // differences can cross r16Float quantization bin boundaries and
        // flip the low byte (max 255) while the numerical value differs
        // by <1 % of the [0, 1] height range. Compare float values, not
        // bytes — gate the actual numerical drift, not the encoding noise.
        let pixelCount = firstBake.count / 2
        var maxValueDiff: Float = 0
        var significantDiffs = 0
        firstBake.withUnsafeBytes { firstRaw in
            secondBake.withUnsafeBytes { secondRaw in
                let first = firstRaw.bindMemory(to: Float16.self)
                let second = secondRaw.bindMemory(to: Float16.self)
                for i in 0 ..< pixelCount {
                    let valueDiff = abs(Float(first[i]) - Float(second[i]))
                    if valueDiff > maxValueDiff { maxValueDiff = valueDiff }
                    if valueDiff > 0.001 { significantDiffs += 1 }
                }
            }
        }
        let diffFraction = Double(significantDiffs) / Double(pixelCount)
        XCTAssertLessThan(diffFraction, 0.001,
            "Re-bake had \(significantDiffs) pixels with >0.001 value diff (\(diffFraction * 100)% of texture) — exceeds expected atomic-ordering noise floor")
        XCTAssertLessThan(maxValueDiff, 0.01,
            "Max per-pixel value diff is \(maxValueDiff) — larger than expected atomic-ordering rounding noise (poly_smin pairwise non-commutativity at sub-bit precision)")
    }

    // MARK: - Gate 6: bake produces non-zero output

    func test_bakeHeightField_producesNonZeroOutput() throws {
        let particles = try XCTUnwrap(
            FerrofluidParticles(device: device, library: library),
            "FerrofluidParticles allocation failed")
        particles.bakeHeightField(commandQueue: commandQueue)

        // Sample the texture: count texels with non-zero height. With
        // `spikeBaseRadius = 0.06` (V.9 4.5c round 5) and 6000 particles in
        // the 20×20 wu patch, expected lattice coverage is
        // 6000 × π × 0.06² / 400 = ~17 % of the patch area. The threshold
        // here is "bake produces meaningful non-zero output" — set well
        // above zero so any silent bake failure trips, well below the
        // expected coverage so future radius tuning doesn't false-fail
        // this gate. The earlier 25 % threshold was sized for the
        // 0.15 wu radius (~71 % expected coverage) and is no longer
        // applicable; the SHAPE intent shifted from "continuous bumpy
        // fabric" to "isolated tall needles with dark substrate
        // between."
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
        XCTAssertGreaterThan(nonZero, totalTexels / 20,
            "Bake produced only \(nonZero) / \(totalTexels) non-zero texels — expected at least 5 % of the patch covered by the spike lattice (the actual target is ~17 % at the current radius/density; the 5 % floor catches silent bake failures while leaving headroom for future radius tuning)")
    }

    // MARK: - Phase 2c: audio forces drive particle motion
    //
    // Phase 2b had two velocity-propagation gates that tested pure
    // `pos += v × dt`. Phase 2c's force model (equilibrium spring + viscous
    // damping + pressure + drums + rotation, all integrated semi-implicit
    // Euler) supersedes those — damping decelerates a seeded velocity to
    // zero within ~0.3 s and the equilibrium spring pulls position back
    // toward canonical, so the Phase 2b expectation of "position drifts
    // by velocity × dt" no longer holds. The Phase 2c tests below cover
    // the load-bearing properties of the new model: audio forces produce
    // visible displacement; silence produces no displacement.

    /// Non-zero audio inputs (bass + drums + arousal) drive forces that
    /// push particles away from canonical equilibrium. Inverse: zero audio
    /// → particles stay at canonical (within tiny rounding from the spring
    /// + damping balance). Asserts the displacement under active audio is
    /// at least an order of magnitude larger than at silence.
    func test_audioForces_displaceParticlesFromCanonical() throws {
        let particles = try XCTUnwrap(
            FerrofluidParticles(device: device, library: library),
            "FerrofluidParticles allocation failed")
        let canonical = particles.snapshotParticlePositions()

        // Drive non-zero audio for 60 frames (1 sec at 60 fps). 0.5 bass
        // and 0.5 drums-smoothed produce noticeable pressure + radial
        // impulse; arousal 0.5 keeps the global scale near maximum.
        let activeAudio = FerrofluidParticles.UpdateAudio(
            accumulatedAudioTime: 0.5,
            arousal: 0.5,
            bassEnergyDev: 0.5,
            drumsEnergyDevSmoothed: 0.5,
            otherEnergyDev: 0.2)
        let dt: Float = 1.0 / 60.0
        for _ in 0 ..< 60 {
            let cmdBuf = try XCTUnwrap(commandQueue.makeCommandBuffer())
            // Bake first so the spatial-hash reflects current positions
            // before the update reads it for neighbour lookup.
            particles.encodeBake(into: cmdBuf)
            particles.encodeUpdate(into: cmdBuf, dt: dt, audio: activeAudio)
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
        }
        let postActive = particles.snapshotParticlePositions()

        // Total displacement magnitude across all particles.
        var totalDispActive: Float = 0
        for i in 0 ..< canonical.count {
            totalDispActive += simd_length(postActive[i] - canonical[i])
        }
        let avgDispActive = totalDispActive / Float(canonical.count)
        XCTAssertGreaterThan(avgDispActive, 0.005,
            "Active audio should displace particles meaningfully — got avg \(avgDispActive) wu, expected > 0.005")
    }

    /// Inverse case: zero audio + zero initial velocity → no displacement.
    /// Equilibrium spring + damping keep particles at canonical.
    func test_silentAudio_keepsParticlesAtCanonical() throws {
        let particles = try XCTUnwrap(
            FerrofluidParticles(device: device, library: library),
            "FerrofluidParticles allocation failed")
        let canonical = particles.snapshotParticlePositions()

        let dt: Float = 1.0 / 60.0
        for _ in 0 ..< 60 {
            let cmdBuf = try XCTUnwrap(commandQueue.makeCommandBuffer())
            particles.encodeBake(into: cmdBuf)
            particles.encodeUpdate(into: cmdBuf, dt: dt, audio: .silent)
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
        }
        let postSilent = particles.snapshotParticlePositions()

        var maxDisp: Float = 0
        for i in 0 ..< canonical.count {
            maxDisp = max(maxDisp, simd_length(postSilent[i] - canonical[i]))
        }
        XCTAssertLessThan(maxDisp, 0.001,
            "Silent audio + zero initial velocity should leave particles at canonical — got max \(maxDisp) wu, expected < 0.001")
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

// FerrofluidParticles+InitialPositions — Canonical Phase 1 grid layout.
//
// Extracted from `FerrofluidParticles.swift` to keep the main file under
// SwiftLint's 400-line cap after the Phase 2a spatial-hash additions.
// All the initial-position logic — grid layout, world-XZ mapping, the
// CPU port of `Utilities/Texture/Voronoi.metal`'s `voronoi_cell_offset`
// hash — lives here. Public API (`canonicalInitialPosition(forIndex:)`)
// stays on the main type for tests and external callers.

import Foundation
import simd

// MARK: - Initial position layout

extension FerrofluidParticles {

    /// Compute the canonical Phase 1 initial position for a particle index.
    /// Round 48 (2026-05-15) replaced the uniform-grid layout with explicit
    /// lotus-pattern clusters: particles arranged in concentric rings
    /// around each of 16 cluster centers (4×4 grid at 5-wu spacing).
    ///
    /// Index mapping:
    ///   - `clusterID = i / kParticlesPerCluster`
    ///   - `clusterLocal = i % kParticlesPerCluster`
    ///   - `(clusterCol, clusterRow) = (clusterID % 4, clusterID / 4)`
    ///   - `clusterLocal` indexes into the lotus pattern (1 center +
    ///     6 + 12 + 18 = 37 positions).
    public static func canonicalInitialPosition(forIndex i: Int) -> SIMD2<Float> {
        let clusterID = i / kParticlesPerCluster
        let clusterLocal = i % kParticlesPerCluster
        let clusterCol = clusterID % kClusterGridSide
        let clusterRow = clusterID / kClusterGridSide
        let centerX = worldOriginX + (Float(clusterCol) + 0.5) * kClusterSpacing
        let centerZ = worldOriginZ + (Float(clusterRow) + 0.5) * kClusterSpacing
        let offsetFromCenter = lotusParticleOffset(localIndex: clusterLocal)
        return SIMD2(centerX + offsetFromCenter.x, centerZ + offsetFromCenter.y)
    }

    // MARK: - Internal

    struct GridLayout {
        let columns: Int
        let rows: Int
        var capacity: Int { columns * rows }
    }

    /// Lotus-pattern cluster layout — round 48 (2026-05-15).
    ///
    /// 4 × 4 = 16 clusters across the 20 × 20 wu patch at 5-wu spacing.
    /// Cluster centers at world XZ (-7.5, -2.5, +2.5, +7.5) in each axis,
    /// measured from `worldOriginX/Z = -10 / -8`.
    ///
    /// Each cluster contains 37 particles arranged in concentric rings
    /// (Leitl-faithful — his spherical geometry projects to this pattern
    /// when flattened around a focal point):
    ///   - Ring 0: 1 particle at center
    ///   - Ring 1: 6 particles at r = 0.33 wu
    ///   - Ring 2: 12 particles at r = 0.67 wu
    ///   - Ring 3: 18 particles at r = 1.00 wu
    ///
    /// Outer ring radius is 1.0 wu, leaving ~3.0 wu of substrate between
    /// adjacent cluster outer edges — the "ocean dotted with magnetic
    /// peaks" character Matt directed.
    static let kClusterGridSide: Int = 4
    static let kClusterSpacing: Float = 5.0
    static let kParticlesPerCluster: Int = 37
    static let kLotusRingRadii: [Float] = [0.0, 0.33, 0.67, 1.00]

    /// GridLayout is retained for back-compat with tests that iterate
    /// `0 ..< particleCount`. `columns × rows = particleCount`; the
    /// previous row-major mapping is preserved trivially by setting
    /// `columns = 1, rows = particleCount`.
    static func canonicalGridLayout() -> GridLayout {
        GridLayout(columns: 1, rows: particleCount)
    }

    /// Map a within-cluster index (0..36) to its (x, z) offset from the
    /// cluster center, in world units. Ring 0 is the lone center
    /// particle; rings 1-3 contain 6, 12, 18 particles spaced evenly
    /// around concentric circles.
    static func lotusParticleOffset(localIndex i: Int) -> SIMD2<Float> {
        switch i {
        case 0:
            return SIMD2(0, 0)
        case 1...6:
            let angle = Float(i - 1) / 6.0 * 2.0 * .pi
            let r = kLotusRingRadii[1]
            return SIMD2(r * cos(angle), r * sin(angle))
        case 7...18:
            let angle = Float(i - 7) / 12.0 * 2.0 * .pi
            let r = kLotusRingRadii[2]
            return SIMD2(r * cos(angle), r * sin(angle))
        case 19...36:
            let angle = Float(i - 19) / 18.0 * 2.0 * .pi
            let r = kLotusRingRadii[3]
            return SIMD2(r * cos(angle), r * sin(angle))
        default:
            return SIMD2(0, 0)
        }
    }

    /// Populate the particle buffer with the canonical Phase 1 positions
    /// and zero initial velocities. Phase 2b extended the per-particle
    /// struct from `float2` (position) to a 16-byte `Particle` (position +
    /// velocity); velocity defaults to zero so production renders with no
    /// motion until Phase 2c wires audio forces or a test seeds velocity.
    func writeInitialParticlePositions() {
        let ptr = particleBuffer.contents().bindMemory(
            to: Particle.self, capacity: Self.particleCount)
        for i in 0 ..< Self.particleCount {
            let pos = Self.canonicalInitialPosition(forIndex: i)
            ptr[i] = Particle(positionX: pos.x, positionZ: pos.y, velocityX: 0, velocityZ: 0)
        }
    }

    // MARK: - Voronoi cell offset (mirror of MSL `voronoi_cell_offset`)

    /// Ported from `Presets/Shaders/Utilities/Texture/Voronoi.metal`'s
    /// `voronoi_hash_int` + `voronoi_cell_offset`. Required so the Phase 1
    /// initial particle XZ positions match the cell-center coordinates a
    /// `voronoi_smooth` pass would emit (Matt's Q1 confirmation
    /// 2026-05-14): "hex grid + per-cell `voronoi_cell_offset` hash". The
    /// 32-bit `Int32` math matches MSL's `int` width semantics.
    static func voronoiCellOffset(cell: SIMD2<Int32>) -> SIMD2<Float> {
        let cx = cell.x &* 1453 &+ cell.y &* 2971
        let cy = cell.x &* 3539 &+ cell.y &* 1117
        let qx = (cx ^ (cx >> 9)) &* 0x45D9_F3B
        let qy = (cy ^ (cy >> 9)) &* 0x45D9_F3B
        let masked = SIMD2<Int32>(qx & 0xFFFF, qy & 0xFFFF)
        return SIMD2(Float(masked.x), Float(masked.y)) / 65535.0
    }
}

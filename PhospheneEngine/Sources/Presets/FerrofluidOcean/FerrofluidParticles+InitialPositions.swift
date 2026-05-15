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
    /// Public so tests can verify the bake input without re-reading GPU memory.
    public static func canonicalInitialPosition(forIndex i: Int) -> SIMD2<Float> {
        let layout = canonicalGridLayout()
        let row = i / layout.columns
        let col = i % layout.columns
        let cellCoord = SIMD2<Int32>(Int32(col), Int32(row))
        let offset = voronoiCellOffset(cell: cellCoord)
        // Map (col + offset.x, row + offset.y) from scaled-space [0..cols] /
        // [0..rows] to world XZ [worldOriginX, +span] / [worldOriginZ, +span].
        let scaledX = Float(col) + offset.x
        let scaledZ = Float(row) + offset.y
        let normalisedX = scaledX / Float(layout.columns)
        let normalisedZ = scaledZ / Float(layout.rows)
        let worldX = worldOriginX + normalisedX * worldSpan
        let worldZ = worldOriginZ + normalisedZ * worldSpan
        return SIMD2(worldX, worldZ)
    }

    // MARK: - Internal

    struct GridLayout {
        let columns: Int
        let rows: Int
        var capacity: Int { columns * rows }
    }

    /// Canonical grid: **55 × 55 = 3025 cells** (Round 17, 2026-05-15).
    /// X / Z spacing `worldSpan / 55 = 0.3636 world units` — isotropic.
    /// Particles at this density with `spikeBaseRadius = 0.17` have bases
    /// that nearly touch (half-spacing 0.182 > radius 0.17 by only
    /// 0.012 wu) → dense lattice with thin substrate channels between
    /// peaks, matching the reference set's packing density per
    /// `01_macro_ferrofluid_at_swell_scale.jpg`.
    ///
    /// History:
    ///   - 80 × 75 = 6000 cells with radius 0.15 (wall-to-wall overlap)
    ///   - 80 × 75 = 6000 cells with radius 0.06 (isolated, but
    ///     per-spike screen coverage too small — Matt's
    ///     `2026-05-15T12-36-08Z` review: "still nowhere close to actual
    ///     ferrofluid")
    ///   - 40 × 38 = 1520 cells with radius 0.12 (Round 11) — discrete
    ///     pyramids registered but Matt's `2026-05-15T14-31-24Z` review
    ///     flagged "too few spikes, lots of empty space between spikes"
    ///     vs the reference set's ~35-40 visible spike-rows.
    ///   - 55 × 55 = 3025 cells with radius 0.17 (Round 17, current) —
    ///     ~2× more spike-rows, bases nearly touch, area coverage
    ///     17 % → 75 %.
    static func canonicalGridLayout() -> GridLayout {
        GridLayout(columns: 55, rows: 55)
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

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

    /// Canonical Phase 1 grid: **80 × 75 = 6000 cells** (no trim). X spacing
    /// `worldSpan / 80 = 0.25 world units` matches Phase A's
    /// `voronoi_smooth(scale = 4)` cell side exactly; Z spacing
    /// `worldSpan / 75 = 0.267 world units` adds a ~7 % anisotropy that's
    /// not visible at the camera tilt (the eye doesn't compare X vs Z cell
    /// spacing across a tilted ground plane). Particles overlap their tent
    /// base at this spacing (peak base radius 0.15 → diameter 0.30 > 0.25
    /// spacing) for wall-to-wall coverage — Matt's "peaks touch
    /// base-to-base" spec, finally satisfied at the empirical density.
    static func canonicalGridLayout() -> GridLayout {
        GridLayout(columns: 80, rows: 75)
    }

    /// Populate the particle buffer with the canonical Phase 1 positions.
    /// Mirrors `canonicalInitialPosition(forIndex:)` for the actual write.
    func writeInitialParticlePositions() {
        let ptr = particleBuffer.contents().bindMemory(
            to: SIMD2<Float>.self, capacity: Self.particleCount)
        for i in 0 ..< Self.particleCount {
            ptr[i] = Self.canonicalInitialPosition(forIndex: i)
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

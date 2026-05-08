// ArachneBranchAnchorsTests — V.7.7C.5 / D-100 (originally V.7.7C.2 / D-095).
//
// `ArachneState.branchAnchors` (Swift) and `kBranchAnchors[6]` (Arachne.metal)
// are the two sources of truth that the WEB pillar's polygon-from-anchors
// path consumes (`packPolygonAnchors` → shader `decodePolygonAnchors` →
// `arachneEvalWeb` polygon clipping + frame thread polygon edges). The §4
// atmospheric reframe (D-100) retired the WORLD-side capsule-twig SDF that
// previously also consumed these positions; the constants are now polygon
// vertex sources only.
//
// V.7.7C.5 (D-100 / Q14): anchors moved to or just past the visible UV
// border (`[-0.06, 1.06]² \ [0,1]²`) so silk threads enter the canvas
// from outside — see `docs/VISUAL_REFERENCES/arachne/
// 20_macro_backlit_purple_canvas_filling_web.jpg`.
//
// These tests:
//   1. Lock the Swift array shape and contents (regression against accidental
//      reordering / value drift).
//   2. Lock the V.7.7C.5 off-frame invariants (each anchor lies in
//      `[-0.06, 1.06]²` and at least one coordinate is outside `[0, 1]`).
//   3. Lock the Swift↔MSL sync by string-searching `Arachne.metal` for the
//      same `float2(x, y)` literals.
//
// A future increment will extract the constants into a shared `.metal` header
// imported by both contexts; until then the regression test is the
// load-bearing invariant.

import Foundation
import Testing
@testable import Presets

@Suite("ArachneBranchAnchors") struct ArachneBranchAnchorsTests {

    // MARK: - Test 1: Swift array shape + contents

    @Test("branchAnchors has exactly 6 entries with the V.7.7C.5 §5.3 values")
    func swiftArrayContents() {
        let anchors = ArachneState.branchAnchors
        #expect(anchors.count == 6)
        // Spot-check each entry — exact match required.
        #expect(anchors[0] == SIMD2<Float>(-0.05, 0.05))
        #expect(anchors[1] == SIMD2<Float>(1.05, 0.02))
        #expect(anchors[2] == SIMD2<Float>(1.06, 0.52))
        #expect(anchors[3] == SIMD2<Float>(1.04, 0.97))
        #expect(anchors[4] == SIMD2<Float>(-0.04, 0.95))
        #expect(anchors[5] == SIMD2<Float>(-0.06, 0.48))
    }

    // MARK: - Test 2: anchors lie in the off-frame band [-0.06, 1.06]²

    @Test("each anchor sits in [-0.06, 1.06]² with at least one coord outside [0,1]")
    func swiftArrayBounds() {
        let lo: Float = -0.06
        let hi: Float = 1.06
        for anchor in ArachneState.branchAnchors {
            // V.7.7C.5 (D-100 / Q14): anchors are on or just past the visible
            // UV border so silk threads enter the canvas from outside.
            #expect(anchor.x >= lo && anchor.x <= hi)
            #expect(anchor.y >= lo && anchor.y <= hi)
            // At least one coord must lie outside [0, 1] — i.e., the anchor
            // is genuinely off-canvas, not inside the visible UV square.
            let xOutside = anchor.x < 0 || anchor.x > 1
            let yOutside = anchor.y < 0 || anchor.y > 1
            #expect(xOutside || yOutside,
                    "Anchor \(anchor) sits inside [0,1]²; V.7.7C.5 / Q14 requires off-canvas")
        }
    }

    // MARK: - Test 2b: distribution is asymmetric (no opposing-edge tie)

    @Test("opposing-edge anchors do not share the same vertical position")
    func swiftArrayAsymmetry() {
        // §5.3 Q14: "asymmetrically distributed (no two on opposing edges at
        // the same vertical position)". Pair the upper-left/upper-right,
        // mid-left/mid-right, and lower-left/lower-right as currently
        // structured by the array order.
        let anchors = ArachneState.branchAnchors
        let upperPairY  = abs(anchors[0].y - anchors[1].y)  // upper-left vs upper-right
        let midPairY    = abs(anchors[2].y - anchors[5].y)  // right-mid vs left-mid
        let lowerPairY  = abs(anchors[3].y - anchors[4].y)  // lower-right vs lower-left
        let minDelta: Float = 0.01
        #expect(upperPairY >= minDelta,
                "Upper anchors share y (Δ \(upperPairY)); polygon would read as symmetric")
        #expect(midPairY   >= minDelta,
                "Mid anchors share y (Δ \(midPairY)); polygon would read as symmetric")
        #expect(lowerPairY >= minDelta,
                "Lower anchors share y (Δ \(lowerPairY)); polygon would read as symmetric")
    }

    // MARK: - Test 3: Swift↔MSL byte-for-byte sync

    @Test("Arachne.metal kBranchAnchors[6] matches Swift branchAnchors")
    func metalSourceMatchesSwift() throws {
        let metalSource = try loadArachneMetalSource()
        // Locate the kBranchAnchors[6] constant block.
        guard let kRange = metalSource.range(of: "constant float2 kBranchAnchors[6]") else {
            Issue.record("kBranchAnchors[6] declaration not found in Arachne.metal")
            return
        }
        let blockStart = kRange.upperBound
        guard let blockEnd = metalSource.range(of: "};", range: blockStart..<metalSource.endIndex) else {
            Issue.record("kBranchAnchors[6] block has no closing `};`")
            return
        }
        let block = String(metalSource[blockStart..<blockEnd.lowerBound])
        // Each Swift entry must appear as a `float2(x, y)` literal in the block.
        // Allow either `float2(0.18, 0.22)` or `float2(0.18,0.22)` (no/with space).
        for (i, anchor) in ArachneState.branchAnchors.enumerated() {
            let xStr = formatLiteral(anchor.x)
            let yStr = formatLiteral(anchor.y)
            let withSpace    = "float2(\(xStr), \(yStr))"
            let withoutSpace = "float2(\(xStr),\(yStr))"
            let found = block.contains(withSpace) || block.contains(withoutSpace)
            #expect(found, "Swift branchAnchors[\(i)] = (\(xStr), \(yStr)) not found in Arachne.metal kBranchAnchors block")
        }
    }

    // MARK: - Helpers

    private func loadArachneMetalSource() throws -> String {
        guard let shadersURL = PresetLoader.bundledShadersURL else {
            throw BranchAnchorsTestError.shadersBundleMissing
        }
        let metalURL = shadersURL.appendingPathComponent("Arachne.metal")
        return try String(contentsOf: metalURL, encoding: .utf8)
    }

    /// Format a Float as it appears in the Swift+Metal sources (e.g. `0.18`).
    /// Handles canonical 2-decimal-place values used by branchAnchors.
    private func formatLiteral(_ v: Float) -> String {
        // The §5.9 values are all 2-decimal-place fractions; render with 2dp.
        String(format: "%.2f", v)
    }
}

private enum BranchAnchorsTestError: Error {
    case shadersBundleMissing
}

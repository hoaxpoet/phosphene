// ArachneBranchAnchorsTests — V.7.7C.2 §5.9 / D-095.
//
// `ArachneState.branchAnchors` (Swift) and `kBranchAnchors[6]` (Arachne.metal)
// are the two sources of truth that both `drawWorld()` (renders dark capsule
// twigs at these positions) and the WEB pillar's frame polygon builder
// (V.7.7C.2 Sub-item 3) consume. They MUST stay byte-for-byte in sync.
//
// These tests:
//   1. Lock the Swift array shape and contents (regression against accidental
//      reordering / value drift).
//   2. Lock the Swift↔MSL sync by string-searching `Arachne.metal` for the
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

    @Test("branchAnchors has exactly 6 entries with the V.7.7C.2 §5.9 values")
    func swiftArrayContents() {
        let anchors = ArachneState.branchAnchors
        #expect(anchors.count == 6)
        // Spot-check each entry — exact match required.
        #expect(anchors[0] == SIMD2<Float>(0.18, 0.22))
        #expect(anchors[1] == SIMD2<Float>(0.82, 0.18))
        #expect(anchors[2] == SIMD2<Float>(0.92, 0.55))
        #expect(anchors[3] == SIMD2<Float>(0.78, 0.84))
        #expect(anchors[4] == SIMD2<Float>(0.20, 0.78))
        #expect(anchors[5] == SIMD2<Float>(0.10, 0.50))
    }

    // MARK: - Test 2: anchors are inside the unit UV square + away from corners

    @Test("each anchor sits inside [0,1] and at least 0.05 from any corner")
    func swiftArrayBounds() {
        for anchor in ArachneState.branchAnchors {
            #expect(anchor.x >= 0 && anchor.x <= 1)
            #expect(anchor.y >= 0 && anchor.y <= 1)
            // Anchors deep in corners read as forced (per the §5.9 commentary).
            // Min distance from any corner ≥ 0.05.
            let corners: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)
            ]
            for corner in corners {
                let dx = anchor.x - corner.x
                let dy = anchor.y - corner.y
                #expect(sqrt(dx * dx + dy * dy) >= 0.05)
            }
        }
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

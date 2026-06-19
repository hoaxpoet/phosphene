// StructuralAnalysisRegressionTests — Golden-value regression test for structural analysis.
// Feeds a known AABA section sequence and asserts detected boundaries match golden times.
//
// BUG-042: the analyzer decimates to 2 Hz before the similarity matrix, so the minimum
// detectable section is ~8 s. The AABA pattern therefore uses 20 s sections (golden
// boundaries at 40 s and 60 s), not the note-scale 2.5 s sections of the pre-fix fixture.
// The pattern is generated inline — it is just constant feature blocks per section, so a
// 60 KB on-disk JSON blob bought nothing over a 6-line loop.

import Testing
import Foundation
@testable import DSP
@testable import Shared

// MARK: - AABA Boundary Regression

@Test func structuralAnalysis_aabaPattern_boundariesMatchGolden() {
    // 16-dim feature blocks (12 chroma + centroid/flux/rolloff/energy) for two
    // contrasting sections. A→A is identical (no boundary); A→B and B→A are sharp.
    let sectionA: [Float] = [0.9, 0.05, 0.05, 0.05, 0.8, 0.05, 0.05, 0.7, 0.05, 0.05, 0.05, 0.05,
                             0.3, 0.1, 0.4, 0.3]
    let sectionB: [Float] = [0.05, 0.8, 0.05, 0.05, 0.05, 0.05, 0.9, 0.05, 0.05, 0.05, 0.7, 0.05,
                             0.8, 0.7, 0.9, 0.8]

    let analyzer = StructuralAnalyzer(
        maxHistory: 600, featureDim: 16, detectionInterval: 2
    )

    // AABA at 20 s/section, 60 fps: A[0,20) A[20,40) B[40,60) A[60,80).
    // True boundaries at 40 s (A→B) and 60 s (B→A); the A→A seam at 20 s is NOT a boundary.
    let pattern: [[Float]] = [sectionA, sectionA, sectionB, sectionA]
    let secondsPerSection: Float = 20
    let fps: Float = 60
    for (sectionIndex, block) in pattern.enumerated() {
        let chroma = Array(block[0..<12])
        let summary = StructuralAnalyzer.SpectralSummary(
            centroid: block[12], flux: block[13], rolloff: block[14], energy: block[15]
        )
        let base = Float(sectionIndex) * secondsPerSection
        for i in 0..<Int(secondsPerSection * fps) {
            _ = analyzer.process(chroma: chroma, spectral: summary, time: base + Float(i) / fps)
        }
    }

    let detected = analyzer.boundaryTimestamps
    let golden: [Float] = [40.0, 60.0]
    let tolerance: Float = 3.0  // 4 s checkerboard block + 0.5 s decimation quantization.

    #expect(detected.count >= golden.count,
            "Should detect at least \(golden.count) boundaries, got \(detected.count): \(detected)")

    // For each golden boundary, the closest detected boundary must be within tolerance.
    for goldenTime in golden {
        let closestDistance = detected.map { abs($0 - goldenTime) }.min() ?? Float.infinity
        #expect(closestDistance <= tolerance,
                "Golden boundary at \(goldenTime)s: closest detected is \(closestDistance)s away (tolerance \(tolerance)s). Detected: \(detected)")
    }
}

// StructuralAnalysisRegressionTests — Golden-value regression tests for structural analysis.
// Feeds a known AABA feature sequence and asserts detected boundaries match golden timestamps.

import Testing
import Foundation
@testable import DSP
@testable import Shared

// MARK: - AABA Boundary Regression

@Test func structuralAnalysis_aabaPattern_boundariesMatchGolden() throws {
    // Load fixture.
    guard let url = Bundle.module.url(
        forResource: "aaba_structural_fixture",
        withExtension: "json",
        subdirectory: "Fixtures"
    ) else {
        throw StructuralRegressionError.fixtureNotFound("aaba_structural_fixture")
    }
    let data = try Data(contentsOf: url)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let framesArray = json["frames"] as? [[String: Any]],
          let goldenBoundaries = json["goldenBoundaries"] as? [Double] else {
        throw StructuralRegressionError.fixtureParseError("aaba_structural_fixture")
    }

    // Create analyzer with matching parameters.
    let analyzer = StructuralAnalyzer(
        maxHistory: 600, featureDim: 16, detectionInterval: 10
    )

    // Feed all frames.
    for frameDict in framesArray {
        guard let features = frameDict["features"] as? [Double],
              let time = frameDict["time"] as? Double else {
            continue
        }
        let floatFeatures = features.map { Float($0) }
        guard floatFeatures.count >= 16 else { continue }

        let chroma = Array(floatFeatures[0..<12])
        _ = analyzer.process(
            chroma: chroma,
            spectral: StructuralAnalyzer.SpectralSummary(
                centroid: floatFeatures[12],
                flux: floatFeatures[13],
                rolloff: floatFeatures[14],
                energy: floatFeatures[15]
            ),
            time: Float(time)
        )
    }

    // Check detected boundaries against golden values.
    let detected = analyzer.boundaryTimestamps
    let golden = goldenBoundaries.map { Float($0) }
    let tolerance: Float = 0.5  // ±500ms

    // The AABA pattern has 2 real boundaries (A→B at 5.0s, B→A at 7.5s).
    // The A→A boundary at 2.5s should NOT be detected (same features).
    #expect(detected.count >= golden.count,
            "Should detect at least \(golden.count) boundaries, got \(detected.count): \(detected)")

    // For each golden boundary, find the closest detected boundary.
    for goldenTime in golden {
        let closestDistance = detected.map { abs($0 - goldenTime) }.min() ?? Float.infinity
        #expect(closestDistance <= tolerance,
                "Golden boundary at \(goldenTime)s: closest detected is \(closestDistance)s away (tolerance \(tolerance)s). Detected: \(detected)")
    }
}

// MARK: - Errors

private enum StructuralRegressionError: Error {
    case fixtureNotFound(String)
    case fixtureParseError(String)
}

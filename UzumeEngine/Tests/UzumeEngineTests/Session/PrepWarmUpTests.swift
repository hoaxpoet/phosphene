// PrepWarmUpTests — PREPPERF.2 ②: the ML-graph warm-up must actually issue one
// stem-separation + one beat-grid pass (that's what forces MPSGraph compilation off
// the critical path). A warm-up that silently calls neither model is a no-op "fix";
// this guards against that regression.

import Metal
import XCTest
@testable import Audio
@testable import DSP
@testable import Session
@testable import Shared

/// Counting spy for the beat-grid analyzer.
private final class SpyBeatGridAnalyzer: BeatGridAnalyzing, @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var lastSampleCount = 0
    func analyzeBeatGrid(samples: [Float], sampleRate: Double) -> BeatGrid {
        callCount += 1
        lastSampleCount = samples.count
        return .empty
    }
}

@available(macOS 14.2, *)
final class PrepWarmUpTests: XCTestCase {

    func testWarmUpCallsBothModelsOnce() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        let separator = try FakeStemSeparator(device: device)
        let grid = SpyBeatGridAnalyzer()

        SessionPreparer.warmUpModels(separator: separator, beatGridAnalyzer: grid)

        XCTAssertEqual(separator.separateCallCount, 1, "stem graph must be warmed once")
        XCTAssertEqual(grid.callCount, 1, "beat-grid graph must be warmed once")
        // Non-empty buffer → both models actually run a frame (not an early bail).
        XCTAssertGreaterThan(separator.lastInputSampleCount, 0)
        XCTAssertGreaterThan(grid.lastSampleCount, 0)
    }

    func testWarmUpToleratesAbsentBeatGridAnalyzer() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        let separator = try FakeStemSeparator(device: device)
        // nil analyzer (tests / no-metadata config) must not crash and still warms stems.
        SessionPreparer.warmUpModels(separator: separator, beatGridAnalyzer: nil)
        XCTAssertEqual(separator.separateCallCount, 1)
    }
}

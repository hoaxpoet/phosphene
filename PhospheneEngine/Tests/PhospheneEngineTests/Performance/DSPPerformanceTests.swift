// DSPPerformanceTests — XCTest.measure benchmarks for DSP analysis hot paths.
// Each benchmark processes ~48 frames of magnitude data (simulating 1s at ~48fps).
// Budget: < 5ms per analyzer for 1s of audio.

import XCTest
@testable import DSP

final class DSPPerformanceTests: XCTestCase {

    /// Benchmark: SpectralAnalyzer on 48 consecutive frames.
    func test_spectralAnalyzer_1Second_performance() {
        let analyzer = SpectralAnalyzer()
        let frames = generateFrames(count: 48)

        measure {
            for frame in frames {
                _ = analyzer.process(magnitudes: frame)
            }
            analyzer.reset()
        }
    }

    /// Benchmark: ChromaExtractor on 48 consecutive frames.
    func test_chromaExtractor_1Second_performance() {
        let extractor = ChromaExtractor()
        let frames = generateFrames(count: 48)

        measure {
            for frame in frames {
                _ = extractor.process(magnitudes: frame)
            }
        }
    }

    /// Benchmark: BeatDetector on 48 consecutive frames with kick pattern.
    func test_beatDetector_1Second_performance() {
        let detector = BeatDetector()
        let frames = generateFramesWithKicks(count: 48, kickEvery: 12)

        measure {
            for frame in frames {
                _ = detector.process(magnitudes: frame, fps: 48, deltaTime: 1.0 / 48.0)
            }
            detector.reset()
        }
    }

    // MARK: - Helpers

    /// Generate `count` frames of synthetic magnitude data.
    private func generateFrames(count: Int) -> [[Float]] {
        (0..<count).map { i in
            AudioFixtures.syntheticMagnitudes(peaks: [
                (bin: 5, magnitude: 0.3 + 0.2 * sinf(Float(i) * 0.3)),
                (bin: 50, magnitude: 0.2),
                (bin: 200, magnitude: 0.1 + 0.1 * sinf(Float(i) * 0.5)),
            ])
        }
    }

    /// Generate frames with periodic loud kicks in the bass region.
    private func generateFramesWithKicks(count: Int, kickEvery: Int) -> [[Float]] {
        (0..<count).map { i in
            if i % kickEvery == 0 {
                var mags = [Float](repeating: 0.01, count: 512)
                for j in 0..<10 { mags[j] = 1.0 }
                return mags
            } else {
                return AudioFixtures.syntheticMagnitudes(peaks: [
                    (bin: 50, magnitude: 0.1),
                    (bin: 200, magnitude: 0.05),
                ])
            }
        }
    }
}

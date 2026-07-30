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

    // MARK: - DBN.2 — decoder budget

    /// `BeatActivationDecoder` must decode a 30 s activation window (1500 frames at
    /// 50 fps) in **< 50 ms** — BEAT_SYNC_PROGRAM_PLAN §DBN.2, restated in
    /// `docs/design/DBN_DECODER_SPEC.md` §8.
    ///
    /// The spec is explicit that this is only reachable with the tempo-conditioned
    /// design (a narrow band around the incumbent BPM estimate): at Krebs's tuned 55
    /// tempo states across 4 meters the cost is ≈113 M Viterbi operations, which does
    /// not fit. **If this fails, change the design — do not widen the budget.**
    ///
    /// **The 50 ms budget is NOT verified by this test, and must not be reported as
    /// met.** It is a release figure, and `swift test -c release` does not build in this
    /// package (BUG-079: `ArachneState.forceActivateForTest` is `#if DEBUG`-gated in
    /// source but its callers in the test target are not). Until that is fixed there is
    /// no way to measure the number the plan actually specifies.
    ///
    /// So this asserts a *regression* ceiling on the debug figure instead — wide enough
    /// not to flake, tight enough to catch an algorithmic regression. Deriving a release
    /// estimate by dividing the debug number by an invented constant would be exactly
    /// the budget-widening the spec forbids, so it is not done.
    ///
    /// Debug history, for regression context (M2 Pro, 4 meters × 11 tempo states):
    ///   * 17,067 ms — naive: beat positions recomputed and `log` called per state/frame
    ///   *  2,603 ms — observation classes and per-frame terms precomputed
    ///   *  1,350 ms — flattened transition table, unsafe buffers in the inner loop
    func test_beatActivationDecoder_30sWindow_performance() {
        let frameRate = 50.0
        let frames = 1500
        var beatProbs = [Float](repeating: 0.02, count: frames)
        var downbeatProbs = [Float](repeating: 0.02, count: frames)
        var time = 0.0
        var beat = 0
        while time < Double(frames) / frameRate {
            let f = Int(time * frameRate)
            if f < frames {
                beatProbs[f] = 0.95
                if beat % 4 == 0 { downbeatProbs[f] = 0.95 }
            }
            time += 0.5
            beat += 1
        }
        let decoder = BeatActivationDecoder()
        // Warm-up so first-call allocation is not charged to the measurement.
        _ = decoder.decode(beatProbs: beatProbs, downbeatProbs: downbeatProbs,
                           frameRate: frameRate, tempoHintBPM: 120)

        let start = DispatchTime.now().uptimeNanoseconds
        _ = decoder.decode(beatProbs: beatProbs, downbeatProbs: downbeatProbs,
                           frameRate: frameRate, tempoHintBPM: 120)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0

        // Regression ceiling, ~3× the measured debug figure. NOT the plan's budget.
        let regressionCeilingMs = 4000.0
        print(String(format: "[DBN.2 budget] 30 s window decoded in %.1f ms (DEBUG). "
                             + "Release budget is 50 ms and is UNVERIFIED — see BUG-079.",
                     elapsedMs))
        XCTAssertLessThan(
            elapsedMs, regressionCeilingMs,
            "decoder took \(String(format: "%.1f", elapsedMs)) ms in debug, over the "
            + "\(Int(regressionCeilingMs)) ms regression ceiling — something got "
            + "algorithmically slower. Per the spec, change the design (fewer tempo "
            + "states, narrower band, fewer meters); do NOT widen the ceiling."
        )
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

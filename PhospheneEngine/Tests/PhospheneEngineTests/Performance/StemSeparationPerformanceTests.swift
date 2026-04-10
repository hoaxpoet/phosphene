// StemSeparationPerformanceTests — XCTest.measure benchmark for stem
// separation. Uses XCTest for measure {} blocks (Swift Testing lacks
// built-in benchmarking).
//
// ## Baselines
//
// Increment 3.1a replaced the CPU STFT/iSTFT with GPU (MPSGraph),
// dropping full `separate()` from ~6500ms to ~2000ms.
//
// Increment 3.1a-followup replaced scalar loops with vDSP_mtrans
// bulk transposes and memcpy:
//   - Total: ~2000ms → ~620ms (3.2× improvement)
//
// Increment 3.9 replaced CoreML (ANE, Float16) with MPSGraph (GPU, Float32),
// eliminating the ~420ms Float16→Float32 conversion and MLMultiArray
// pack/unpack overhead:
//   - Total: ~620ms → ~150ms (4× improvement)
//
// Warm-call breakdown (typical, post-3.9):
//   prep=1ms, stft=9ms, memcpy=0ms, predict=102ms,
//   reconstruct=35ms (iSTFT + mono avg), write=0ms → total ≈ 150ms

import XCTest
import Metal
@testable import ML
@testable import Audio
@testable import Shared

final class StemSeparationPerformanceTests: XCTestCase {

    private var device: MTLDevice!

    override func setUpWithError() throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        device = dev
    }

    /// Hard assertion: warm-call `separate()` must complete under 400ms.
    ///
    /// Post-3.9 budget: ~9ms STFT + ~102ms MPSGraph predict + ~35ms iSTFT
    /// + ~15ms overhead = ~161ms, with generous headroom to 400ms.
    /// The first call includes MPSGraph JIT compilation, so we warm up
    /// once before measuring.
    func test_separate_1SecondAudio_performance() throws {
        let separator = try StemSeparator(device: device)

        let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 44100, duration: 1.0)
        let stereo = AudioFixtures.mixStereo(left: mono, right: mono)

        // Warm up: first call includes MPSGraph JIT compilation.
        _ = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)

        // Hard assertion on a warm call.
        let start = Date()
        _ = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.40,
            "separate() took \(String(format: "%.0f", elapsed * 1000))ms, target is 400ms")
    }

    /// XCTest.measure benchmark for averaged timing across multiple iterations.
    func test_separate_1SecondAudio_measureBlock() throws {
        let separator = try StemSeparator(device: device)

        let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 44100, duration: 1.0)
        let stereo = AudioFixtures.mixStereo(left: mono, right: mono)

        // Warm up outside measure block.
        _ = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)

        measure {
            do {
                _ = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)
            } catch {
                XCTFail("Separation failed: \(error)")
            }
        }
    }
}

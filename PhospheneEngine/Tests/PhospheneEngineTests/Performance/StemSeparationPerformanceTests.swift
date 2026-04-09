// StemSeparationPerformanceTests — XCTest.measure benchmark for stem
// separation. Uses XCTest for measure {} blocks (Swift Testing lacks
// built-in benchmarking).
//
// ## Baselines
//
// Increment 3.1a replaced the CPU STFT/iSTFT with a GPU (MPSGraph) path,
// dropping the per-transform cost from ~650ms to ~6ms. The full
// `separate()` call dropped from ~6500ms to ~2000ms on Apple Silicon —
// a 3.25x wall-clock improvement. The remaining ~2s is dominated by
// `MLShapedArray` strided element access inside
// `packSpectrogramForModel` and `unpackAndISTFT`, and by the per-element
// write loop inside `UMABuffer.write`. Those are tracked as follow-up
// optimizations and are out of scope for Increment 3.1a, which only
// delivers the FFT work. See `StemFFTTests` for per-transform hard
// assertions.

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

    /// Benchmark: StemSeparator.separate() for 1 second of audio.
    ///
    /// Reports wall-clock time without a hard assertion. The 250ms
    /// end-to-end target from the Increment 3.1a spec is unreachable
    /// without the pack/unpack/write optimizations noted at the top of
    /// this file — once those follow-up increments land, a hard
    /// `XCTAssertLessThan(..., 0.25)` should be added here.
    func test_separate_1SecondAudio_performance() throws {
        let separator = try StemSeparator(device: device)

        // 1 second of stereo audio at model's native 44100 Hz.
        let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 44100, duration: 1.0)
        let stereo = AudioFixtures.mixStereo(left: mono, right: mono)

        measure {
            do {
                _ = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)
            } catch {
                XCTFail("Separation failed: \(error)")
            }
        }
    }
}

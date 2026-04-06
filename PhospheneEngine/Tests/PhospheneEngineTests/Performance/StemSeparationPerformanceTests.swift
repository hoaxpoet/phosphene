// StemSeparationPerformanceTests — XCTest.measure benchmark for stem separation.
// Uses XCTest for measure {} blocks (Swift Testing lacks built-in benchmarking).

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
    /// Expected < 50ms on Apple Silicon with ANE.
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

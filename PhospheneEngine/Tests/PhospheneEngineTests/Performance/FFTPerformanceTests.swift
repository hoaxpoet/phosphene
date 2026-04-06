// FFTPerformanceTests — XCTest.measure benchmarks for FFT and AudioBuffer hot paths.
// Uses XCTest for measure {} blocks (Swift Testing lacks built-in benchmarking).

import XCTest
import Metal
@testable import Audio
@testable import Shared

final class FFTPerformanceTests: XCTestCase {

    private var device: MTLDevice!

    override func setUpWithError() throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        device = dev
    }

    /// Benchmark: FFTProcessor.process() for 1024 samples.
    /// Expected < 0.1ms on M-series Apple Silicon.
    func test_fftProcess_1024Samples_performance() throws {
        let fftProcessor = try FFTProcessor(device: device)
        let samples = AudioFixtures.sineWave(frequency: 440, sampleRate: 48000, duration: 0.1)
        let input = Array(samples.prefix(1024))

        measure {
            fftProcessor.process(samples: input, sampleRate: 48000)
        }
    }

    /// Benchmark: AudioBuffer.write() for 48000 samples (1 second of audio).
    /// Establishes the baseline for the hot path from Core Audio tap callback.
    func test_audioBufferWrite_48000Samples_performance() throws {
        let audioBuffer = try AudioBuffer(device: device)
        let samples = AudioFixtures.sineWave(frequency: 440, sampleRate: 48000, duration: 1.0)
        let stereo = AudioFixtures.mixStereo(left: samples, right: samples)

        measure {
            stereo.withUnsafeBufferPointer { ptr in
                _ = audioBuffer.write(from: ptr.baseAddress!, count: ptr.count)
            }
        }
    }
}

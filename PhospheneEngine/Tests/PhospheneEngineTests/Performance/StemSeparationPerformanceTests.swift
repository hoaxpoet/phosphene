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
//   - pack: 275ms → 1ms (raw MLMultiArray + vDSP_mtrans)
//   - write: 231ms → <1ms (Float-specialized memcpy in UMABuffer)
//   - unpack transpose: nested scalar loops → vDSP_mtrans
//   - deinterleave: scalar loop → vDSP_ctoz
//   - mono averaging: scalar loop → vDSP_vadd + vDSP_vsmul
//   - Total: ~2000ms → ~620ms (3.2× improvement)
//
// ## Remaining bottleneck
//
// The ANE outputs Float16 MLMultiArrays. `MLShapedArray<Float>(converting:)`
// performs the Float16→Float32 conversion, which takes ~420ms for ~7M
// elements — this is internal to CoreML and cannot be optimized further
// from Swift. The original spec's 250ms target assumed Float32 ANE output.
//
// Warm-call breakdown (typical):
//   prep=1ms, stft=9ms, pack=1ms, predict=140ms,
//   unpackIstft=475ms (420ms F16→F32 + 5ms transpose + 50ms iSTFT),
//   write=0ms → total ≈ 625ms

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

    /// Hard assertion: warm-call `separate()` must complete under 750ms.
    ///
    /// This ceiling accounts for ~140ms ANE prediction + ~420ms Float16→Float32
    /// conversion + ~50ms iSTFT + ~15ms overhead, with 20% headroom.
    /// The first call includes MPSGraph JIT and CoreML compilation, so we
    /// warm up once before measuring.
    func test_separate_1SecondAudio_performance() throws {
        let separator = try StemSeparator(device: device)

        let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 44100, duration: 1.0)
        let stereo = AudioFixtures.mixStereo(left: mono, right: mono)

        // Warm up: first call includes MPSGraph JIT and CoreML compilation.
        _ = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)

        // Hard assertion on a warm call.
        let start = Date()
        _ = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.75,
            "separate() took \(String(format: "%.0f", elapsed * 1000))ms, target is 750ms")
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

// FeatureVectorExtendedTests — Tests for the Increment 3.15 FeatureVector extensions:
// accumulatedAudioTime field and the render-loop accumulation formula.
//
// Four tests: size, zero-at-start, accumulation with volume, and reset on track change.

import XCTest
import Metal
@testable import Renderer
@testable import Shared

// MARK: - FeatureVectorExtendedTests

final class FeatureVectorExtendedTests: XCTestCase {

    // MARK: - Test 1: FeatureVector is 128 bytes after adding accumulatedAudioTime + padding

    func test_featureVector_size_is128Bytes() {
        XCTAssertEqual(
            MemoryLayout<FeatureVector>.size, 128,
            "FeatureVector must be 128 bytes (32 × Float) after Increment 3.15 — "
            + "got \(MemoryLayout<FeatureVector>.size)"
        )
        XCTAssertEqual(
            MemoryLayout<FeatureVector>.stride, 128,
            "FeatureVector stride must be 128 bytes — got \(MemoryLayout<FeatureVector>.stride)"
        )
        XCTAssertEqual(
            MemoryLayout<FeatureVector>.stride % 16, 0,
            "FeatureVector stride must be 16-byte aligned for GPU uniform upload"
        )
    }

    // MARK: - Test 2: accumulatedAudioTime is zero in a default FeatureVector

    func test_accumulatedAudioTime_zeroAtStart() {
        let fv = FeatureVector()
        XCTAssertEqual(fv.accumulatedAudioTime, 0,
            "Default FeatureVector.accumulatedAudioTime must be 0")

        let zero = FeatureVector.zero
        XCTAssertEqual(zero.accumulatedAudioTime, 0,
            "FeatureVector.zero.accumulatedAudioTime must be 0")
    }

    // MARK: - Test 3: Energy-weighted accumulation formula matches expected value

    /// Validates the render-loop accumulation formula in isolation:
    ///   accumulatedAudioTime += max(0, (bass + mid + treble) / 3.0) × deltaTime
    ///
    /// 60 frames at energy 0.6, deltaTime = 1/60 s  →  0.6 s accumulated.
    func test_accumulatedAudioTime_accumulatesWithVolume() {
        var accumulated: Float = 0
        let bass: Float = 0.6
        let mid: Float = 0.6
        let treble: Float = 0.6
        let dt: Float = 1.0 / 60.0

        for _ in 0..<60 {
            let energy = max(0, (bass + mid + treble) / 3.0)
            accumulated += energy * dt
        }

        // 60 × 0.6 × (1/60) = 0.6
        XCTAssertEqual(accumulated, 0.6, accuracy: 0.001,
            "60 frames at energy 0.6, dt=1/60 s must accumulate ~0.6 s, got \(accumulated)")
    }

    // MARK: - Test 4: resetAccumulatedAudioTime() zeroes the value (track change)

    func test_accumulatedAudioTime_resetsOnTrackChange() throws {
        let context = try MetalContext()
        let lib = try ShaderLibrary(context: context)
        let fftBuf = try XCTUnwrap(
            context.device.makeBuffer(length: 512 * MemoryLayout<Float>.stride,
                                      options: .storageModeShared),
            "Failed to allocate FFT buffer"
        )
        let wavBuf = try XCTUnwrap(
            context.device.makeBuffer(length: 2048 * MemoryLayout<Float>.stride,
                                      options: .storageModeShared),
            "Failed to allocate waveform buffer"
        )
        let pipeline = try RenderPipeline(
            context: context,
            shaderLibrary: lib,
            fftBuffer: fftBuf,
            waveformBuffer: wavBuf
        )

        // Simulate several frames of audio accumulation.
        for _ in 0..<30 {
            pipeline.stepAccumulatedTime(energy: 0.5, deltaTime: 1.0 / 60.0)
        }
        XCTAssertGreaterThan(pipeline.accumulatedAudioTime, 0,
            "accumulatedAudioTime must be > 0 after simulated frames")

        // Simulate a track change — must reset to exactly zero.
        pipeline.resetAccumulatedAudioTime()
        XCTAssertEqual(pipeline.accumulatedAudioTime, 0,
            "accumulatedAudioTime must be 0 after resetAccumulatedAudioTime() (track change)")
    }
}

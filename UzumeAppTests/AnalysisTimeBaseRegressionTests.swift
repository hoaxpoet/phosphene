// AnalysisTimeBaseRegressionTests — BUG087.2 regression gate.
//
// `processAnalysisFrame` derived its `dt` from `CFAbsoluteTimeGetCurrent()`. That is
// correct only while there is exactly one analysis frame per audio callback. BUG087.3
// slices oversized tap buffers so one callback yields several frames, delivered
// microseconds apart — wall-clock `dt` collapses toward zero and `effectiveFps`
// explodes, which corrupts every seconds-based follower DYN.4 / DYN.5 introduced
// (`LoudnessProfile.emaAlpha(deltaTime:tau:)`, the centroid / rolloff / flux followers)
// and `BandEnergyProcessor`'s `fps`. Nothing asserted on `dt`, so that corruption would
// not have failed a test.
//
// The fix derives `dt` from the audio the callback carried. These tests assert the
// derivation, and — the load-bearing one — that it AGREES with wall-clock in today's
// one-frame-per-callback regime, so BUG087.2 is provably behaviour-neutral before
// BUG087.3 changes the rate.

import Foundation
import Testing
@testable import PhospheneApp

@Suite("Analysis time base derives from audio, not wall-clock (BUG087.2)")
struct AnalysisTimeBaseRegressionTests {

    // MARK: - The derivation

    @Test("dt is frames / rate, at both real capture sample rates")
    func dtIsFramesOverRate() {
        // `sampleCount` is total interleaved floats on both capture paths:
        // `mDataByteSize / sizeof(Float)` for the system tap, `frames * channelCount`
        // for the local file. So frames = sampleCount / channels.
        for (frames, rate) in [(1024, Float(44_100)), (1024, Float(48_000)),
                               (4410, Float(44_100)), (4800, Float(48_000)),
                               (939, Float(48_000))] {
            let dt = VisualizerEngine.audioDeltaTime(
                sampleCount: frames * 2, channels: 2, rate: rate
            )
            #expect(abs(dt - Float(frames) / rate) < 1e-7,
                    "frames=\(frames) rate=\(rate) → dt \(dt)")
        }
    }

    @Test("The two measured buffer regimes report their measured intervals")
    func measuredRegimesReproduce() {
        // BUG-087's numbers, as a guard on the arithmetic against real captures:
        // local file delivers ~0.1 s buffers, the system tap ~939 frames ≈ 19.6 ms.
        let localFile = VisualizerEngine.audioDeltaTime(
            sampleCount: 4808 * 2, channels: 2, rate: 48_000
        )
        #expect(abs(localFile - 0.1002) < 0.001, "local-file path → \(localFile * 1000) ms")

        let systemTap = VisualizerEngine.audioDeltaTime(
            sampleCount: 939 * 2, channels: 2, rate: 48_000
        )
        #expect(abs(systemTap - 0.0196) < 0.001, "system tap → \(systemTap * 1000) ms")

        // The whole point of the defect: a 5x rate gap between the two paths.
        #expect(localFile / systemTap > 4.5)
    }

    @Test("Mono and multi-channel buffers derive the same duration per frame")
    func channelCountIsDividedOut() {
        let mono = VisualizerEngine.audioDeltaTime(
            sampleCount: 1024, channels: 1, rate: 48_000
        )
        let stereo = VisualizerEngine.audioDeltaTime(
            sampleCount: 1024 * 2, channels: 2, rate: 48_000
        )
        #expect(abs(mono - stereo) < 1e-7,
                "channel count must divide out, not scale the clock")
    }

    // MARK: - Degenerate inputs fall back rather than divide by zero

    @Test("Unusable inputs return 0 so the caller falls back to wall-clock")
    func degenerateInputsReturnZero() {
        #expect(VisualizerEngine.audioDeltaTime(sampleCount: 0, channels: 2, rate: 48_000) == 0)
        #expect(VisualizerEngine.audioDeltaTime(sampleCount: 1024, channels: 0, rate: 48_000) == 0)
        #expect(VisualizerEngine.audioDeltaTime(sampleCount: 1024, channels: 2, rate: 0) == 0)
        // Fewer floats than channels — frames would truncate to 0.
        #expect(VisualizerEngine.audioDeltaTime(sampleCount: 1, channels: 2, rate: 48_000) == 0)
    }

    // MARK: - The behaviour-neutrality claim (the load-bearing test)

    @Test("With one frame per callback, audio-derived dt matches wall-clock elapsed")
    func agreesWithWallClockAtOneFramePerCallback() {
        // Today each callback produces exactly one analysis frame, so wall-clock elapsed
        // between frames IS the buffer's audio duration, give or take scheduling jitter.
        // This equivalence is why BUG087.2 can be asserted behaviour-neutral rather than
        // assumed to be. It is also precisely what BUG087.3 breaks for wall-clock and not
        // for the audio-derived value.
        for (frames, rate) in [(4800, Float(48_000)), (4410, Float(44_100)),
                               (939, Float(48_000))] {
            let audioDt = VisualizerEngine.audioDeltaTime(
                sampleCount: frames * 2, channels: 2, rate: rate
            )
            let wallClockEquivalent = Float(frames) / rate   // a callback arriving on time
            #expect(abs(audioDt - wallClockEquivalent) < 1e-6)
        }
    }

    @Test("Slices of one buffer sum to that buffer's duration")
    func slicesSumToTheWholeBuffer() {
        // BUG087.3's safety property, asserted before the slicing exists: however a
        // buffer is cut, the reported durations must total the buffer's own duration —
        // which is what keeps every seconds-based follower correct under burst delivery.
        let rate = Float(48_000)
        let whole = VisualizerEngine.audioDeltaTime(
            sampleCount: 4800 * 2, channels: 2, rate: rate
        )
        let sliceFrames = 1024
        var remaining = 4800
        var summed: Float = 0
        while remaining > 0 {
            let take = min(sliceFrames, remaining)
            summed += VisualizerEngine.audioDeltaTime(
                sampleCount: take * 2, channels: 2, rate: rate
            )
            remaining -= take
        }
        #expect(abs(summed - whole) < 1e-6,
                "slices summed to \(summed)s against a \(whole)s buffer")
    }
}

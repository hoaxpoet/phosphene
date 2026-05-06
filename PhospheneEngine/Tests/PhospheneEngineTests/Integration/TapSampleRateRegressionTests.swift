// TapSampleRateRegressionTests — QR.1 / D-079.
//
// Engine-level guards that prevent the literal-44100 regression cataloged
// as Failed Approach #52. The app-layer call sites (StemSeparator.separate,
// DefaultBeatGridAnalyzer.analyzeBeatGrid) live in `PhospheneApp` and are
// not directly reachable from this SPM test target; what *is* reachable is
// the rate-aware `StemSampleBuffer` API the app threads tapSampleRate
// through. If the buffer ever silently falls back to its stored 44100
// default again, these tests fail loud.
//
// Coverage gap (intentional, documented in QR.1 closeout): the actual
// `tapSampleRate` capture path runs in VisualizerEngine, which can't be
// instantiated under SPM (Metal + audio tap). App-target coverage is a
// follow-up; the lint gate `Scripts/check_sample_rate_literals.sh` plus
// these structural tests prevent the most common regression mode (silent
// reversion to 44100 in the buffer/RMS path).

import Testing
import Foundation
@testable import Shared

@Suite("Tap sample rate regression (QR.1 / D-079)")
struct TapSampleRateRegressionTests {

    // MARK: - Helpers

    /// Fill a buffer with `fillSeconds` of stereo audio at `fillRate`, then
    /// snapshot `requestSeconds` at `readRate` from the rate-aware overload.
    private func fillAndSnapshot(
        bufferInitRate: Double = 44100,
        fillRate: Double,
        fillSeconds: Double,
        requestSeconds: Double,
        readRate: Double
    ) -> [Float] {
        let buf = StemSampleBuffer(sampleRate: bufferInitRate, maxSeconds: 16)
        let count = Int(fillRate * 2 * fillSeconds)
        var samples = [Float](repeating: 0.1, count: count)
        samples.withUnsafeMutableBufferPointer { ptr in
            buf.write(samples: ptr.baseAddress!, count: count)
        }
        return buf.snapshotLatest(seconds: requestSeconds, sampleRate: readRate)
    }

    // MARK: - Snapshot at 48 kHz

    @Test("snapshotLatest_at48kHz_retrieves960kSamples_for10s")
    func test_snapshotLatest_at48kHz_full10s() {
        // Production path: tap fills at 48 kHz, request 10 s through the
        // rate-aware overload at 48 kHz. Must retrieve 960k stereo samples,
        // not 882k (which is what the no-rate overload would size against
        // the buffer's stored 44100 default — DSP.3.4 root cause #3).
        let snap = fillAndSnapshot(
            bufferInitRate: 44100,
            fillRate: 48000, fillSeconds: 12,
            requestSeconds: 10, readRate: 48000
        )
        #expect(snap.count == 960_000,
                "rate-aware overload must size against the explicit rate (48 kHz × 10 s × 2 ch = 960k), got \(snap.count)")
    }

    @Test("snapshotLatest_at48kHz_with44100Buffer_retrievesActualRateFrames")
    func test_snapshotLatest_48kHz_with44100Buffer() {
        // Pre-DSP.3.4 the buffer was 44100-init and the no-rate overload
        // returned only 9.1875 s of real audio on a 48 kHz tap. The
        // rate-aware overload — which the production code now uses on every
        // call site — must return the full 10 s at the actual tap rate.
        let snap48 = fillAndSnapshot(
            bufferInitRate: 44100,
            fillRate: 48000, fillSeconds: 12,
            requestSeconds: 10, readRate: 48000
        )
        #expect(snap48.count == 960_000)

        // Contrast: requesting at 44100 (the legacy/buggy behaviour) returns
        // 882k, which is only 9.1875 s of actual 48 kHz tap audio.
        let snap44 = fillAndSnapshot(
            bufferInitRate: 44100,
            fillRate: 48000, fillSeconds: 12,
            requestSeconds: 10, readRate: 44100
        )
        #expect(snap44.count == 882_000)
    }

    // MARK: - RMS at 48 kHz

    @Test("rmsRateAware_at48kHz_doesNotSilentlyTruncate")
    func test_rmsRateAware_at48kHz() {
        let buf = StemSampleBuffer(sampleRate: 44100, maxSeconds: 16)
        // Fill 12 s of stereo audio at 48 kHz with a known constant 0.5
        // amplitude. RMS of a constant-0.5 signal is 0.5 exactly.
        let count = 48_000 * 2 * 12
        var samples = [Float](repeating: 0.5, count: count)
        samples.withUnsafeMutableBufferPointer { ptr in
            buf.write(samples: ptr.baseAddress!, count: count)
        }
        let rmsAware = buf.rms(seconds: 10, sampleRate: 48000)
        #expect(abs(rmsAware - 0.5) < 1e-4,
                "rate-aware RMS should be 0.5 for constant-0.5 signal, got \(rmsAware)")
    }

    @Test("rmsLegacyOverload_routesToRateAwareOverloadWithStoredRate")
    func test_rmsLegacy_matchesAware() {
        let buf = StemSampleBuffer(sampleRate: 44100, maxSeconds: 5)
        let count = 44_100 * 2 * 4
        var samples = [Float](repeating: 0.3, count: count)
        samples.withUnsafeMutableBufferPointer { ptr in
            buf.write(samples: ptr.baseAddress!, count: count)
        }
        let legacy = buf.rms(seconds: 2)
        let aware = buf.rms(seconds: 2, sampleRate: 44100)
        #expect(abs(legacy - aware) < 1e-6,
                "legacy rms(seconds:) must match rate-aware overload at the buffer's stored rate")
    }
}

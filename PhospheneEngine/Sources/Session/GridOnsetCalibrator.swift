// GridOnsetCalibrator — Per-track offset between Beat This! grid timing and the
// sub-bass onset detector (BUG-007.8).
//
// Beat This! reports beat timestamps based on broadband perceptual beat detection
// (transformer trained on human tap annotations). At playback time, Phosphene's
// sub-bass onset detector fires on kick-band spectral energy peaks. These two
// signals can be offset by track-specific amounts (typically ±50–150 ms) due to:
//   • Different kick attack envelopes (sharp vs soft)
//   • Sub-bass leakage from synth pads / bass guitar
//   • Spotify preview clip not starting on a song bar boundary
//   • Beat This!'s intrinsic detection latency vs our onset detector's latency
//
// This calibrator runs at preparation time on the same 30 s preview audio that
// Beat This! analysed, replays it through our `BeatDetector`, and computes the
// median time offset between the resulting onsets and the grid's beat times.
// `LiveBeatDriftTracker.setGrid(_:initialDriftMs:)` consumes this offset as an
// initial drift bias so the EMA starts at the right value rather than chasing
// it at runtime over the first ~4 s of playback.
//
// Output sign convention matches `LiveBeatDriftTracker`'s drift:
//   offset > 0 → grid beats are LATER than detected onsets (onsets fire early)
//   offset < 0 → grid beats are EARLIER than detected onsets (onsets fire late)

import Accelerate
import DSP
import Foundation

public struct GridOnsetCalibrator {

    // MARK: - Constants

    /// FFT window size — must match the live BeatDetector's expectation.
    private static let fftSize = 1024
    /// log2 of fftSize for vDSP_fft_zrip.
    private static let log2n = vDSP_Length(10)
    /// Half of fftSize — number of magnitude bins.
    private static let binCount = 512
    /// Maximum onset-to-grid distance (seconds) considered a match. Onsets
    /// further than this from any grid beat are excluded from the median —
    /// they're noise, not a calibrable offset.
    private static let maxMatchWindow: Double = 0.200

    // MARK: - Init

    public init() {}

    // MARK: - Calibrate

    /// Compute the median offset (ms) between grid beats and onset detections
    /// over the given mono audio. Returns 0 when calibration is impossible
    /// (empty grid, insufficient samples, or no matched onsets).
    ///
    /// - Parameters:
    ///   - samples: Mono Float32 PCM samples of the preview audio.
    ///   - sampleRate: Sample rate in Hz (typically 22050 for Spotify previews
    ///                 after decode, or 44100/48000 for live tap audio).
    ///   - grid: The `BeatGrid` produced by Beat This! on the same audio.
    /// - Returns: Median (gridBeat − onsetTime) in milliseconds, or 0 on
    ///            insufficient data.
    public func calibrate(samples: [Float], sampleRate: Double, grid: BeatGrid) -> Double {
        guard !grid.beats.isEmpty, samples.count >= Self.fftSize else { return 0 }
        let onsetTimes = computeSubBassOnsets(samples: samples, sampleRate: sampleRate)
        guard !onsetTimes.isEmpty else { return 0 }
        let offsets = matchOnsetsToGrid(onsetTimes: onsetTimes, gridBeats: grid.beats)
        guard !offsets.isEmpty else { return 0 }
        return medianMs(of: offsets)
    }

    // MARK: - Helpers

    /// Run the live BeatDetector offline against the preview audio, returning
    /// sub-bass onset timestamps in seconds (relative to sample 0).
    private func computeSubBassOnsets(samples: [Float], sampleRate: Double) -> [Double] {
        let detector = BeatDetector(
            binCount: Self.binCount,
            sampleRate: Float(sampleRate),
            fftSize: Self.fftSize
        )
        var fftSetup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))
        defer { vDSP_destroy_fftsetup(fftSetup) }
        let window = makeHannWindow(size: Self.fftSize)

        var onsetTimes: [Double] = []
        let hop = Self.fftSize   // non-overlapping, matches live FFT cadence
        let frameRate = Float(sampleRate) / Float(hop)
        let dt = Float(1.0 / Double(frameRate))

        var frameIdx = 0
        var sampleStart = 0
        while sampleStart + Self.fftSize <= samples.count {
            let mags = computeMagnitudes(
                samples: samples,
                start: sampleStart,
                window: window,
                fftSetup: fftSetup
            )
            let result = detector.process(magnitudes: mags, fps: frameRate, deltaTime: dt)
            // result.onsets[0] = sub_bass band (matches live drift-tracker source).
            if !result.onsets.isEmpty && result.onsets[0] {
                let onsetTime = Double(frameIdx) * Double(hop) / sampleRate
                onsetTimes.append(onsetTime)
            }
            frameIdx += 1
            sampleStart += hop
        }
        return onsetTimes
    }

    /// For each onset, find the nearest grid beat within `maxMatchWindow`.
    /// Returns the signed time offsets (gridBeat − onsetTime) in seconds.
    private func matchOnsetsToGrid(onsetTimes: [Double], gridBeats: [Double]) -> [Double] {
        var offsets: [Double] = []
        offsets.reserveCapacity(onsetTimes.count)
        for onset in onsetTimes {
            guard let nearest = nearestBeat(to: onset, in: gridBeats) else { continue }
            let delta = nearest - onset
            if abs(delta) <= Self.maxMatchWindow {
                offsets.append(delta)
            }
        }
        return offsets
    }

    /// Bisect-search for the nearest beat to `t` in a sorted `beats` array.
    private func nearestBeat(to time: Double, in beats: [Double]) -> Double? {
        guard !beats.isEmpty else { return nil }
        var lo = 0
        var hi = beats.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if beats[mid] < time { lo = mid + 1 } else { hi = mid }
        }
        // beats[lo] is the first beat ≥ time. Compare with the previous beat (if any).
        let upper = beats[lo]
        if lo == 0 { return upper }
        let lower = beats[lo - 1]
        return abs(upper - time) < abs(lower - time) ? upper : lower
    }

    /// Median of values, returned in milliseconds.
    private func medianMs(of values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        let medianS = sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2.0
            : sorted[mid]
        return medianS * 1000.0
    }

    /// Hann window of given size.
    private func makeHannWindow(size: Int) -> [Float] {
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        return window
    }

    /// Compute FFT magnitudes for a single 1024-sample window starting at
    /// `start` in `samples`. Mirrors `FFTProcessor.process` minus the GPU buffer.
    private func computeMagnitudes(
        samples: [Float],
        start: Int,
        window: [Float],
        fftSetup: FFTSetup?
    ) -> [Float] {
        guard let fftSetup else { return [Float](repeating: 0, count: Self.binCount) }
        var windowed = [Float](repeating: 0, count: Self.fftSize)
        let endIdx = min(start + Self.fftSize, samples.count)
        for i in start..<endIdx { windowed[i - start] = samples[i] }
        vDSP_vmul(windowed, 1, window, 1, &windowed, 1, vDSP_Length(Self.fftSize))

        var realPart = [Float](repeating: 0, count: Self.binCount)
        var imagPart = [Float](repeating: 0, count: Self.binCount)
        var magnitudes = [Float](repeating: 0, count: Self.binCount)

        windowed.withUnsafeBufferPointer { srcPtr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    // swiftlint:disable force_unwrapping
                    var splitComplex = DSPSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    srcPtr.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self, capacity: Self.binCount
                    ) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(Self.binCount))
                    }
                    // swiftlint:enable force_unwrapping
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(Self.binCount))
                    var scale = 2.0 / Float(Self.fftSize)
                    vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(Self.binCount))
                }
            }
        }
        return magnitudes
    }
}

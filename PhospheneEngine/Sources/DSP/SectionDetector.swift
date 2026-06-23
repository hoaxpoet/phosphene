// SectionDetector — public façade wiring the SECDET feature + clustering pipeline into
// session prep (SECDET.3b). Resamples full-track PCM to 22050 mono, beat-syncs on the
// cached BeatGrid, and runs McFee/Ellis Laplacian spectral clustering (D-170) to produce
// section-boundary times. The offline/batch boundary source that replaces the live
// novelty detector at prep time — runs once per track on the full local-file decode,
// like the cached BeatGrid. Streaming 30 s previews run it too, but their boundaries
// can't span the real track, so the planner's coverage gate drops them to equal slices.

import AVFoundation
import Foundation
import os

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "SectionDetector")

// MARK: - SectionDetector

/// Full-track section detection: 22050-mono resample → beat-synced 252-CQT + 13-MFCC →
/// McFee/Ellis spectral clustering → ascending section-boundary times.
public struct SectionDetector {

    /// Minimum beat count to attempt detection. The clustering needs
    /// `≥ 2·RecurrenceGraph.width + 2` (= 8) beat segments; below that the detector
    /// returns nothing and the caller falls back to equal slices.
    static let minBeats = 8

    public init() {}

    /// Detect section boundaries for a full track.
    ///
    /// - Parameters:
    ///   - samples: Full-track mono Float32 PCM at `sampleRate`.
    ///   - sampleRate: Native sample rate of `samples` in Hz (decode/live SR).
    ///   - beatTimes: Beat positions in seconds (`BeatGrid.beats`, Beat This!).
    ///   - duration: Track duration in seconds.
    /// - Returns: Interior section-start times in seconds, track-relative, ascending —
    ///   **not** including 0 or `duration` (the `TrackProfile`/planner contract,
    ///   LFPLAN.5). Empty when the input is too short or yields no interior boundaries;
    ///   the caller maps empty → `nil`.
    public func boundaryTimes(
        samples: [Float],
        sampleRate: Double,
        beatTimes: [Double],
        duration: Double
    ) -> [TimeInterval] {
        guard !samples.isEmpty, duration > 0, beatTimes.count >= Self.minBeats else { return [] }

        let targetSR = ConstantQTransform.sampleRate          // 22050
        let hop = Double(ConstantQTransform.hop)              // 512
        let pcm = abs(sampleRate - targetSR) < 1
            ? samples
            : Self.resampleMono(samples, from: sampleRate, to: targetSR)
        guard !pcm.isEmpty else { return [] }

        // Beat This! caps its grid at ~30 s (BeatThisModel.tMax=1500 frames); McFee can
        // only segment the span its beats cover, so extend to the full track (SECDET.5).
        let covered = Self.fullTrackBeats(beatTimes, duration: duration)
        // Beat times (s) → hop-512 frame indices on the 22050 grid.
        let beatFrames = covered.map { Int(($0 * targetSR / hop).rounded()) }
        let features = SectionFeatureExtractor().extract(samples22k: pcm, beatFrames: beatFrames)
        let bounds = SectionFeatureExtractor.syncBoundaries(
            beatFrames: beatFrames, frameCount: features.frameCount)
        let segStarts = bounds.dropLast().map { Double($0) * hop / targetSR }
        let detected = SpectralSectionDetector().boundaryTimes(
            features: features, segmentStartTimes: segStarts, duration: duration)

        // SpectralSectionDetector returns [0, t1, …, duration]; strip the framing
        // boundaries to match the interior-starts contract the planner consumes.
        return detected.dropFirst().dropLast().map { TimeInterval($0) }
    }

    // MARK: - Full-track coverage

    /// Beat This! truncates its grid to a fixed ~30 s window (`BeatThisModel.tMax`), so on a
    /// longer track `beatTimes` only spans the first 30 s — and McFee can only place
    /// boundaries where it has beats (the live failure: a 282 s track segmented only its
    /// first 30 s → coverage gate → equal slices). Extend the grid past its last beat at the
    /// median inter-beat period so the beat-sync covers the whole track. Beat-sync is just
    /// frame-pooling for the recurrence graph, so synthetic beats beyond the tracked region
    /// are adequate for section structure (validated offline, SECDET.5); the real beats
    /// anchor phase + tempo for the part Beat This! actually tracked.
    static func fullTrackBeats(_ beatTimes: [Double], duration: Double) -> [Double] {
        guard beatTimes.count >= 2, let last = beatTimes.last else { return beatTimes }
        let diffs = zip(beatTimes.dropFirst(), beatTimes).map { $0 - $1 }.filter { $0 > 0 }.sorted()
        guard !diffs.isEmpty else { return beatTimes }
        let period = diffs[diffs.count / 2]
        guard period > 0.05, last < duration - period else { return beatTimes }
        var out = beatTimes
        var time = last + period
        while time < duration { out.append(time); time += period }
        return out
    }

    // MARK: - Resampling

    /// Resample mono Float32 from `srcRate` to `dstRate` via AVAudioConverter (libresample;
    /// quality comparable to soxr). Mirrors `BeatThisPreprocessor.resample`. Returns `[]` on
    /// failure so the caller falls back to equal slices rather than feeding wrong-SR audio
    /// to the 22050 CQT.
    static func resampleMono(_ samples: [Float], from srcRate: Double, to dstRate: Double) -> [Float] {
        guard let srcFmt = AVAudioFormat(standardFormatWithSampleRate: srcRate, channels: 1),
              let dstFmt = AVAudioFormat(standardFormatWithSampleRate: dstRate, channels: 1),
              let converter = AVAudioConverter(from: srcFmt, to: dstFmt) else {
            logger.error("SectionDetector: AVAudioConverter init failed \(srcRate)→\(dstRate) Hz")
            return []
        }

        let srcCount = samples.count
        let dstCount = Int(ceil(Double(srcCount) * dstRate / srcRate)) + 1
        guard srcCount > 0,
              let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: AVAudioFrameCount(srcCount)),
              let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFmt, frameCapacity: AVAudioFrameCount(dstCount)) else {
            logger.error("SectionDetector: AVAudioPCMBuffer allocation failed")
            return []
        }

        srcBuf.frameLength = AVAudioFrameCount(srcCount)
        samples.withUnsafeBufferPointer { src in
            // floatChannelData is non-nil for a standardFormat Float32 buffer;
            // baseAddress is non-nil for srcCount ≥ 1 (guarded above).
            // swiftlint:disable:next force_unwrapping
            _ = memcpy(srcBuf.floatChannelData![0], src.baseAddress!, srcCount * MemoryLayout<Float>.size)
        }

        // nonisolated(unsafe): touched only by the convert callback, which
        // AVAudioConverter invokes synchronously on this thread.
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let capturedSrcBuf = srcBuf
        var convError: NSError?
        _ = converter.convert(to: dstBuf, error: &convError) { _, outStatus in
            guard !consumed else { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return capturedSrcBuf
        }

        if let err = convError {
            logger.error("SectionDetector: AVAudioConverter error: \(err)")
            return []
        }
        let outCount = Int(dstBuf.frameLength)
        guard outCount > 0, let out = dstBuf.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: out, count: outCount))
    }
}

// InstrumentFamilyAnalyzer — preview-clip instrument-family activity (IFC.4 / D-177).
//
// Runs PANNsMobileNetV1 over a sliding 2 s window / 1 s hop sweep of the 30 s
// preview clip and feeds each window's 527-class probs through an
// InstrumentFamilyTracker, producing the per-window activity time series
// (strings / brass / woodwinds / percussion). This is Layer 5a — available from
// frame 1 but NOT time-aligned to live playback (scoping §4). The live frame
// samples this series by playback position (see InstrumentFamilyActivity.sample).
//
// Pre-analysis only (runs inside SessionPreparer.analyzePreview on the detached
// analysis task) — no live-latency constraint, so a single PANNs instance is
// reused across the ~29 windows.

import AVFoundation
import Foundation
import Metal
import os.log

private let logger = Logger(subsystem: "com.phosphene.ml", category: "InstrumentFamilyAnalyzer")

// MARK: - Protocol

/// Produces the per-window instrument-family activity series for a preview clip.
/// Injectable (like `BeatGridAnalyzing`) so the prep pipeline can run with a
/// test double that needs no Metal device or model weights.
public protocol InstrumentFamilyAnalyzing: Sendable {
    /// - Parameters:
    ///   - samples: Mono Float32 PCM (any sample rate; resampled internally).
    ///   - sampleRate: Source sample rate (Hz).
    /// - Returns: One `InstrumentFamilyActivity` per 2 s window at a 1 s hop,
    ///   in playback order. Empty when the clip is shorter than one window.
    func analyzeFamilyActivity(samples: [Float], sampleRate: Double) -> [InstrumentFamilyActivity]
}

// MARK: - InstrumentFamilyAnalyzer

/// Default `InstrumentFamilyAnalyzing` backed by `PANNsMobileNetV1`.
public final class InstrumentFamilyAnalyzer: InstrumentFamilyAnalyzing, @unchecked Sendable {

    /// 1 s hop between analysis windows. The series is indexed in these units
    /// when sampled by playback position (see `InstrumentFamilyActivity.sample`).
    public static let hopSeconds: Double = 1.0

    private let model: PANNsMobileNetV1
    /// 2 s window in 32 kHz samples (= `defaultFrames` worth of audio).
    private let windowSamples = PANNsMobileNetV1.hop * (PANNsMobileNetV1.defaultFrames - 1)
    private let hopSamples = PANNsMobileNetV1.sampleRate   // 1 s at 32 kHz

    public init(model: PANNsMobileNetV1) {
        self.model = model
    }

    /// Convenience: build the model on `device` (fixed 201-frame / 2 s window).
    public convenience init(device: MTLDevice) throws {
        self.init(model: try PANNsMobileNetV1(device: device))
    }

    public func analyzeFamilyActivity(samples: [Float], sampleRate: Double) -> [InstrumentFamilyActivity] {
        let mono = sampleRate == Double(PANNsMobileNetV1.sampleRate)
            ? samples
            : resample(samples, from: sampleRate, to: Double(PANNsMobileNetV1.sampleRate))
        guard mono.count >= windowSamples else { return [] }

        var tracker = InstrumentFamilyTracker()
        var series: [InstrumentFamilyActivity] = []
        var offset = 0
        while offset + windowSamples <= mono.count {
            let window = Array(mono[offset..<offset + windowSamples])
            do {
                let probs = try model.predict(waveform: window)
                series.append(tracker.derive(probs: probs))
            } catch {
                logger.error("PANNs predict failed at offset \(offset): \(error.localizedDescription)")
                return series   // partial series is still usable; bail on first failure
            }
            offset += hopSamples
        }
        return series
    }

    // MARK: - Resampling

    /// Resample mono Float32 audio via `AVAudioConverter` (same approach as
    /// `BeatThisPreprocessor`; vDSP has no general-ratio resampler).
    private func resample(_ samples: [Float], from srcRate: Double, to dstRate: Double) -> [Float] {
        guard let srcFmt = AVAudioFormat(standardFormatWithSampleRate: srcRate, channels: 1),
              let dstFmt = AVAudioFormat(standardFormatWithSampleRate: dstRate, channels: 1),
              let converter = AVAudioConverter(from: srcFmt, to: dstFmt) else {
            logger.error("AVAudioConverter init failed \(srcRate)→\(dstRate) Hz")
            return samples
        }
        let srcCount = samples.count
        let dstCount = Int(ceil(Double(srcCount) * dstRate / srcRate)) + 1
        guard srcCount > 0,
              let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: AVAudioFrameCount(srcCount)),
              let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFmt, frameCapacity: AVAudioFrameCount(dstCount)) else {
            return samples
        }
        srcBuf.frameLength = AVAudioFrameCount(srcCount)
        samples.withUnsafeBufferPointer { src in
            // floatChannelData is non-nil for a standard Float32 format; baseAddress
            // is non-nil for srcCount >= 1 (guarded above).
            // swiftlint:disable:next force_unwrapping
            memcpy(srcBuf.floatChannelData![0], src.baseAddress!, srcCount * MemoryLayout<Float>.size)
        }
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
            logger.error("AVAudioConverter error: \(err.localizedDescription)")
            return samples
        }
        let outCount = Int(dstBuf.frameLength)
        // swiftlint:disable:next force_unwrapping
        return Array(UnsafeBufferPointer(start: dstBuf.floatChannelData![0], count: outCount))
    }
}

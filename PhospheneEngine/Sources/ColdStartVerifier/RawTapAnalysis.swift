// RawTapAnalysis — Offline ground-truth beat detection on raw_tap.wav.
//
// raw_tap.wav is the Core Audio tap audio captured before any Phosphene DSP
// (SessionRecorder+RawTap.swift). This module decodes it to mono Float32 and
// replays it through the SAME FFTProcessor → BeatDetector path the live engine
// and `GridOnsetCalibrator` use — at the engine's 1024-sample non-overlapping
// hop — producing sub-bass onset timestamps that are the CS.1 ground truth for
// "audible beat time".
//
// It also emits a low-frequency energy envelope (one value per FFT hop) used by
// ClockAlignment to register raw_tap.wav against features.csv.

import AVFoundation
import Audio
import DSP
import Foundation
import Metal

/// Offline analysis result for one raw_tap.wav.
struct RawTapAnalysis {
    let sampleRate: Double
    let durationS: Double
    /// Sub-bass onset timestamps (seconds, raw-tap clock). BeatDetector onsets[0].
    let onsets: [Double]
    /// Low-frequency energy, one value per `envelopeHopS` (raw-tap clock).
    let lowEnvelope: [Double]
    /// Spacing between consecutive `lowEnvelope` samples, seconds.
    let envelopeHopS: Double

    /// FFT window / hop — matches FFTProcessor.fftSize and the live FFT cadence.
    static let hop = 1024
    /// Magnitude bins summed for the alignment envelope (~47–470 Hz @ 48 kHz):
    /// kick fundamental + low harmonics. Bin 0 (DC) skipped.
    static let envelopeBinRange = 1...10

    static func analyze(url: URL) throws -> RawTapAnalysis {
        let (samples, sampleRate) = try decodeMonoFloat32(url: url)
        guard samples.count >= hop else {
            throw VerifierError.rawTapDecodeFailed("only \(samples.count) samples decoded")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw VerifierError.rawTapDecodeFailed("no Metal device available for FFTProcessor")
        }
        let fft = try FFTProcessor(device: device)
        // BeatDetector / FFTProcessor are driven at the raw_tap's actual rate —
        // never a hardcoded 44100 (D-079, Failed Approach #52).
        let detector = BeatDetector(
            binCount: 512, sampleRate: Float(sampleRate), fftSize: hop)
        let fps = Float(sampleRate) / Float(hop)
        let deltaTime = Float(hop) / Float(sampleRate)
        let envelopeHopS = Double(hop) / sampleRate

        var onsets: [Double] = []
        var envelope: [Double] = []
        var offset = 0
        var frameIdx = 0
        while offset + hop <= samples.count {
            let window = Array(samples[offset..<offset + hop])
            _ = fft.process(samples: window, sampleRate: Float(sampleRate))
            let mags = Array(fft.magnitudeBuffer.pointer)
            envelope.append(lowEnergy(mags))
            let result = detector.process(
                magnitudes: mags, fps: fps, deltaTime: deltaTime)
            if !result.onsets.isEmpty, result.onsets[0] {
                onsets.append(Double(frameIdx) * envelopeHopS)
            }
            offset += hop
            frameIdx += 1
        }
        return RawTapAnalysis(
            sampleRate: sampleRate,
            durationS: Double(samples.count) / sampleRate,
            onsets: onsets,
            lowEnvelope: envelope,
            envelopeHopS: envelopeHopS)
    }

    private static func lowEnergy(_ mags: [Float]) -> Double {
        var sum = 0.0
        for bin in envelopeBinRange where bin < mags.count {
            sum += Double(mags[bin])
        }
        return sum
    }

    /// Decode any AVFoundation-readable audio file to mono Float32. raw_tap.wav
    /// is IEEE-float WAV (SessionRecorder+RawTap.swift writes format tag 3).
    private static func decodeMonoFloat32(url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw VerifierError.rawTapDecodeFailed(error.localizedDescription)
        }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw VerifierError.rawTapDecodeFailed("empty or unreadable audio")
        }
        do {
            try file.read(into: buffer)
        } catch {
            throw VerifierError.rawTapDecodeFailed(error.localizedDescription)
        }
        let actualFrames = Int(buffer.frameLength)
        guard actualFrames > 0, let channelData = buffer.floatChannelData else {
            throw VerifierError.rawTapDecodeFailed("decode produced no samples")
        }
        let channelCount = Int(format.channelCount)
        var samples = [Float](repeating: 0, count: actualFrames)
        if channelCount == 1 {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: actualFrames))
        } else {
            let scale = 1.0 / Float(channelCount)
            for ch in 0..<channelCount {
                let ptr = UnsafeBufferPointer(start: channelData[ch], count: actualFrames)
                for i in 0..<actualFrames { samples[i] += ptr[i] * scale }
            }
        }
        return (samples, format.sampleRate)
    }
}

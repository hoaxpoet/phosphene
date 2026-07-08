// CensusAnalysis — the audio-side of CorpusCensusRunner: decode, resample, and the
// MIR/mood + FFT helpers that mirror the production SessionPreparer.analyzeMIR
// feature assembly. Split out of CorpusCensusRunner.swift to keep the command
// struct small; Metal/AVFoundation-dependent, so not unit-tested (see
// CorpusCensusTests for the pure-function coverage).

import Accelerate
import AVFoundation
import Audio
import DSP
import Foundation
import ML

// MARK: - MIR result

/// Aggregated MIR/mood output for one (samples, rate) pass.
struct MIRResult {
    var feats: [Double]       // 10 means, pre-normalization
    var valence: Double?
    var arousal: Double?
    var keyClass: String
    var bpm: Double?
    var majorR: Double?
    var minorR: Double?

    static let empty = MIRResult(
        feats: [], valence: nil, arousal: nil, keyClass: "", bpm: nil, majorR: nil, minorR: nil
    )
}

// MARK: - Decode

/// Decode a whole audio file to mono Float32 at its native rate (AVFoundation —
/// no ffmpeg). Mirrors TempoDumpRunner.decodeMonoFloat32.
func decodeMonoFloat32(url: URL) throws -> (samples: [Float], sampleRate: Float) {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let frameCount = AVAudioFrameCount(file.length)
    guard frameCount > 0 else { throw CensusError("empty file") }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw CensusError("PCM buffer alloc failed")
    }
    try file.read(into: buffer)
    let actual = Int(buffer.frameLength)
    guard actual > 0, let channelData = buffer.floatChannelData else {
        throw CensusError("decode produced no samples")
    }
    let channels = Int(format.channelCount)
    var samples: [Float]
    if channels == 1 {
        samples = Array(UnsafeBufferPointer(start: channelData[0], count: actual))
    } else {
        samples = [Float](repeating: 0, count: actual)
        let scale = 1.0 / Float(channels)
        for chan in 0..<channels {
            let ptr = UnsafeBufferPointer(start: channelData[chan], count: actual)
            for idx in 0..<actual { samples[idx] += ptr[idx] * scale }
        }
    }
    return (samples, Float(format.sampleRate))
}

/// Resample mono Float32 to a target rate via AVAudioConverter. Returns the input
/// unchanged if rates already match or conversion cannot be set up.
func resampleMono(_ samples: [Float], from srcRate: Double, to dstRate: Double) -> [Float] {
    if abs(srcRate - dstRate) < 1 { return samples }
    guard
        let srcFmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: srcRate, channels: 1, interleaved: false
        ),
        let dstFmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: dstRate, channels: 1, interleaved: false
        ),
        let converter = AVAudioConverter(from: srcFmt, to: dstFmt),
        let srcBuf = AVAudioPCMBuffer(
            pcmFormat: srcFmt, frameCapacity: AVAudioFrameCount(samples.count)
        ),
        let srcChannels = srcBuf.floatChannelData
    else { return samples }
    srcBuf.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { src in
        if let base = src.baseAddress { srcChannels[0].update(from: base, count: samples.count) }
    }
    let capacity = AVAudioFrameCount(Double(samples.count) * dstRate / srcRate + 4096)
    guard
        let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFmt, frameCapacity: capacity),
        let dstChannels = dstBuf.floatChannelData
    else { return samples }
    // Feed the whole source buffer once; state lives in a reference so the
    // @Sendable input block captures no mutable var / non-Sendable buffer.
    let feeder = InputFeeder(srcBuf)
    var err: NSError?
    converter.convert(to: dstBuf, error: &err) { _, status in
        if feeder.fed { status.pointee = .noDataNow; return nil }
        feeder.fed = true; status.pointee = .haveData; return feeder.buffer
    }
    if err != nil { return samples }
    return Array(UnsafeBufferPointer(start: dstChannels[0], count: Int(dstBuf.frameLength)))
}

// MARK: - MIR / mood

/// Run MIRPipeline over `samples` at `sampleRate`, aggregate the MoodClassifier's
/// 10 input features as means across frames, and classify once. Mirrors the
/// production SessionPreparer.analyzeMIR feature order exactly.
func runMIR(samples: [Float], sampleRate: Double) -> MIRResult {
    let fftSize = 1024
    let binCount = fftSize / 2
    guard let fft = try? FFTMagnitudeKernel(fftSize: fftSize) else { return .empty }

    let mir = MIRPipeline(binCount: binCount, sampleRate: Float(sampleRate), fftSize: fftSize)
    let fps = Float(sampleRate) / Float(fftSize)
    let deltaTime = 1.0 / fps

    // 10-feature accumulator (means across frames), matching the production order:
    // 6-band energy, spectralCentroid, rawSmoothedFlux, major-K-S, minor-K-S.
    var sums = [Double](repeating: 0, count: 10)
    var frames = 0
    var offset = 0
    while offset + fftSize <= samples.count {
        fillWindow(fft, samples: samples, offset: offset)
        fft.computeMagnitudes()
        let time = Float(frames) * deltaTime
        let feat = mir.process(magnitudes: fft.magnitudes, fps: fps, time: time, deltaTime: deltaTime)
        let frameVec: [Float] = [
            feat.subBass, feat.lowBass, feat.lowMid, feat.midHigh, feat.highMid, feat.high,
            feat.spectralCentroid, mir.rawSmoothedFlux,
            mir.latestMajorKeyCorrelation, mir.latestMinorKeyCorrelation,
        ]
        for idx in 0..<10 { sums[idx] += Double(frameVec[idx]) }
        frames += 1
        offset += fftSize
    }
    guard frames > 0 else { return .empty }
    let means = sums.map { $0 / Double(frames) }

    // Run MoodClassifier ONCE on the aggregated vector. Fresh instance ⇒ EMA
    // starts from neutral and does not leak across tracks/rates.
    var valence: Double?
    var arousal: Double?
    if let state = try? MoodClassifier().classify(features: means.map { Float($0) }) {
        valence = Double(state.valence)
        arousal = Double(state.arousal)
    }
    return MIRResult(
        feats: means,
        valence: valence,
        arousal: arousal,
        keyClass: mir.estimatedKey ?? "",
        bpm: mir.estimatedTempo.map(Double.init),
        majorR: Double(mir.latestMajorKeyCorrelation),
        minorR: Double(mir.latestMinorKeyCorrelation)
    )
}

// MARK: - Mood A/B (BUG-066 before/after)

/// Before/after mood for one track: run the real MoodClassifier production-style
/// (classify every 30 frames, EMA-accumulated) on TWO parallel MIR pipelines —
/// `old` fed magnitudes ×16 (the pre-fix |FFT|/32 scale) and `new` fed the fixed
/// |FFT|/512 scale. Faithful full-pipeline comparison, not just a flux rescale.
struct MoodABResult {
    var oldV: Double
    var oldA: Double
    var newV: Double
    var newA: Double
    var fluxNew: Double   // mean new-flux (drives the correlation)
}

func runMoodAB(samples: [Float], sampleRate: Double) -> MoodABResult? {
    let fftSize = 1024
    let binCount = fftSize / 2
    guard let fft = try? FFTMagnitudeKernel(fftSize: fftSize) else { return nil }

    let mirNew = MIRPipeline(binCount: binCount, sampleRate: Float(sampleRate), fftSize: fftSize)
    let mirOld = MIRPipeline(binCount: binCount, sampleRate: Float(sampleRate), fftSize: fftSize)
    let clfNew = MoodClassifier()
    let clfOld = MoodClassifier()
    let fps = Float(sampleRate) / Float(fftSize)
    let deltaTime = 1.0 / fps

    var oldMag = [Float](repeating: 0, count: binCount)
    var newV = 0.0, newA = 0.0, oldV = 0.0, oldA = 0.0
    var gotResult = false
    var fluxSum = 0.0
    var frames = 0
    var offset = 0
    while offset + fftSize <= samples.count {
        fillWindow(fft, samples: samples, offset: offset)
        fft.computeMagnitudes()                                   // fixed (new) magnitudes
        let time = Float(frames) * deltaTime
        let fvNew = mirNew.process(magnitudes: fft.magnitudes, fps: fps, time: time, deltaTime: deltaTime)
        for idx in 0..<binCount { oldMag[idx] = fft.magnitudes[idx] * 16 }   // pre-fix |FFT|/32 scale
        let fvOld = mirOld.process(magnitudes: oldMag, fps: fps, time: time, deltaTime: deltaTime)
        fluxSum += Double(mirNew.rawSmoothedFlux)
        if frames % 30 == 0 {   // production classify cadence (analyzeMIR)
            let inNew: [Float] = [
                fvNew.subBass, fvNew.lowBass, fvNew.lowMid, fvNew.midHigh, fvNew.highMid, fvNew.high,
                fvNew.spectralCentroid, mirNew.rawSmoothedFlux,
                mirNew.latestMajorKeyCorrelation, mirNew.latestMinorKeyCorrelation,
            ]
            let inOld: [Float] = [
                fvOld.subBass, fvOld.lowBass, fvOld.lowMid, fvOld.midHigh, fvOld.highMid, fvOld.high,
                fvOld.spectralCentroid, mirOld.rawSmoothedFlux,
                mirOld.latestMajorKeyCorrelation, mirOld.latestMinorKeyCorrelation,
            ]
            if let sNew = try? clfNew.classify(features: inNew), let sOld = try? clfOld.classify(features: inOld) {
                newV = Double(sNew.valence); newA = Double(sNew.arousal)
                oldV = Double(sOld.valence); oldA = Double(sOld.arousal)
                gotResult = true
            }
        }
        frames += 1
        offset += fftSize
    }
    guard gotResult, frames > 0 else { return nil }
    return MoodABResult(oldV: oldV, oldA: oldA, newV: newV, newA: newA, fluxNew: fluxSum / Double(frames))
}

// MARK: - FFT scratch

/// Copy this frame's `fftSize`-sample window into the shared kernel's input scratch.
/// MOOD-FLUX.3: the magnitude math itself lives in `FFTMagnitudeKernel` — the single
/// production formula — so this diagnostic mirror can never drift from the offline
/// path it exists to reproduce (BUG-066). Caller then invokes `fft.computeMagnitudes()`.
private func fillWindow(_ fft: FFTMagnitudeKernel, samples: [Float], offset: Int) {
    samples.withUnsafeBufferPointer { src in
        fft.windowed.withUnsafeMutableBufferPointer { dst in
            guard let srcBase = src.baseAddress, let dstBase = dst.baseAddress else { return }
            dstBase.update(from: srcBase.advanced(by: offset), count: fft.fftSize)
        }
    }
}

// MARK: - Support types

/// One-shot input holder for AVAudioConverter's @Sendable input block.
private final class InputFeeder: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var fed = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}

/// Per-stage wall-clock accumulator (PREPPERF TIMING pattern, ad hoc).
struct StageTimer {
    private var last = Date()
    private var parts: [String] = []
    mutating func mark(_ label: String) {
        let now = Date()
        parts.append("\(label)=\(String(format: "%.2f", now.timeIntervalSince(last)))s")
        last = now
    }
    func summary() -> String { parts.joined(separator: " ") }
}

struct CensusError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

// MARK: - CensusRow factories

extension CensusRow {
    /// A dual-rate extra row: only the MIR/mood columns are populated (grid/drums
    /// come from the native pass and are not re-derived per rate).
    static func mirOnly(relpath: String, nativeRate: Double, windowS: Double, mir: MIRResult) -> CensusRow {
        CensusRow(
            relpath: relpath,
            nativeRate: nativeRate,
            windowS: windowS,
            mirBPM: mir.bpm,
            valence: mir.valence,
            arousal: mir.arousal,
            feats: mir.feats,
            keyClass: mir.keyClass,
            keyMajorR: mir.majorR,
            keyMinorR: mir.minorR
        )
    }
}

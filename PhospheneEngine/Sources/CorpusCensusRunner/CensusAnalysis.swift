// CensusAnalysis — the audio-side of CorpusCensusRunner: decode, resample, and the
// MIR/mood + FFT helpers that mirror the production SessionPreparer.analyzeMIR
// feature assembly. Split out of CorpusCensusRunner.swift to keep the command
// struct small; Metal/AVFoundation-dependent, so not unit-tested (see
// CorpusCensusTests for the pure-function coverage).

import Accelerate
import AVFoundation
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
    let log2n = vDSP_Length(log2(Double(fftSize)))
    guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return .empty }
    defer { vDSP_destroy_fftsetup(fftSetup) }

    var ctx = FFTScratch(fftSize: fftSize, binCount: binCount, log2n: log2n, fftSetup: fftSetup)
    let mir = MIRPipeline(binCount: binCount, sampleRate: Float(sampleRate), fftSize: fftSize)
    let fps = Float(sampleRate) / Float(fftSize)
    let deltaTime = 1.0 / fps

    // 10-feature accumulator (means across frames), matching the production order:
    // 6-band energy, spectralCentroid, rawSmoothedFlux, major-K-S, minor-K-S.
    var sums = [Double](repeating: 0, count: 10)
    var frames = 0
    var offset = 0
    while offset + fftSize <= samples.count {
        ctx.computeMagnitudes(samples: samples, offset: offset)
        let time = Float(frames) * deltaTime
        let feat = mir.process(magnitudes: ctx.magnitudes, fps: fps, time: time, deltaTime: deltaTime)
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

// MARK: - FFT scratch

/// Reusable 1024-pt Hann FFT scratch producing magnitude spectra — the same
/// non-overlapping vDSP path SessionPreparer.computeFFTMagnitudes uses.
private struct FFTScratch {
    let fftSize: Int
    let binCount: Int
    let log2n: vDSP_Length
    let fftSetup: FFTSetup
    var hann: [Float]
    var windowed: [Float]
    var realPart: [Float]
    var imagPart: [Float]
    var magnitudes: [Float]

    init(fftSize: Int, binCount: Int, log2n: vDSP_Length, fftSetup: FFTSetup) {
        self.fftSize = fftSize
        self.binCount = binCount
        self.log2n = log2n
        self.fftSetup = fftSetup
        self.hann = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hann, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.windowed = [Float](repeating: 0, count: fftSize)
        self.realPart = [Float](repeating: 0, count: binCount)
        self.imagPart = [Float](repeating: 0, count: binCount)
        self.magnitudes = [Float](repeating: 0, count: binCount)
    }

    mutating func computeMagnitudes(samples: [Float], offset: Int) {
        samples.withUnsafeBufferPointer { src in
            windowed.withUnsafeMutableBufferPointer { dst in
                guard let srcBase = src.baseAddress, let dstBase = dst.baseAddress else { return }
                dstBase.update(from: srcBase.advanced(by: offset), count: fftSize)
            }
        }
        vDSP_vmul(windowed, 1, hann, 1, &windowed, 1, vDSP_Length(fftSize))
        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                guard let realBase = realBuf.baseAddress, let imagBase = imagBuf.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                windowed.withUnsafeBufferPointer { input in
                    guard let inputBase = input.baseAddress else { return }
                    inputBase.withMemoryRebound(to: DSPComplex.self, capacity: binCount) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(binCount))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                magnitudes.withUnsafeMutableBufferPointer { magBuf in
                    guard let magBase = magBuf.baseAddress else { return }
                    vDSP_zvmags(&split, 1, magBase, 1, vDSP_Length(binCount))
                }
            }
        }
        var scale = Float(fftSize)
        vDSP_vsdiv(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(binCount))
        var cnt = Int32(binCount)
        vvsqrtf(&magnitudes, magnitudes, &cnt)
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

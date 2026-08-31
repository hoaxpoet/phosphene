// PerNoteMagnitudeTests — FTR.7: does anything in the vector carry a per-NOTE magnitude?
//
// WHY THIS OUTLIVED THE INCREMENT THAT PRODUCED IT. Matt asked for melodic tips that keep
// their full 0…8 swing but change on notes (~3/s) instead of continuously (~10/s) — "same
// size, fewer times". That needs a note CLOCK, which a refractory gate on `beat_mid`
// supplies at 2.9 events/s, and a per-note VALUE. The value is what does not exist, and the
// reason generalises well beyond Fractal Tree: **`beat_mid` is a saturating pulse with a
// deterministic per-frame decay, so once a refractory fixes the interval length, EVERY
// statistic of it over that interval is a function of the frame count alone.**
//
// Measured through the production pipeline on two unrelated tracks:
//
//   peak at the note   = the trigger level by construction        1 distinct value
//   interval trough    p50 0.0902, max 0.1178 — IDENTICAL         6–7 distinct
//   interval mean      p05 .3409 p50 .3969 p95 .4310 — IDENTICAL  12–14 distinct
//
// Identical percentiles on two different records is the signature of a clock, not of music.
// The trough variant was built and measured before this was concluded: span 2 against the
// shipped term's 7, i.e. it fails "same size" — the same half FTR.6 had already failed.
//
// Of everything else, only `spectral_flux` carries real per-note variety (582 / 441 distinct,
// spread 0.66 / 0.50) — and it already drives branch spread, so using it is the FA #67
// collision this preset was rebuilt at FTR.2 to remove. Matt declined it (2026-08-09), which
// closes "one tip per note" on this material and is why `MelodicNoteGate` and
// `FeatureVector.melodicTips` were removed rather than left as infrastructure without a
// consumer.
//
// KEPT because MEL.1 is still open and wants a melodic-salience signal: this is the standing
// answer to "which primitive carries per-note information", and the assertion below fails if
// `beat_mid` ever stops saturating — which would make the conclusion stale rather than a
// fact to cite.
//
//   FTR_AUDIO_DIR="/Volumes/Extreme SSD/S/Smashing Pumpkins/[1993] - Siamese Dream" \
//     swift test --package-path PhospheneEngine --filter PerNoteMagnitude

import Testing
import Foundation
import AVFoundation
@testable import Audio
@testable import DSP
@testable import Shared

@Suite("Per-note magnitude candidates (FTR.7)")
struct PerNoteMagnitudeTests {

    private static let fftSize = 1024
    private static let tracks = ["04 Hummer.mp3", "01 Cherub Rock.mp3"]

    // The note clock, as FTR.6/FTR.7 tuned it. Local to this diagnostic now that the
    // production gate is gone — a measurement's own parameters belong with the measurement.
    private static let triggerLevel: Float = 0.90
    private static let refractoryBounds: ClosedRange<Float> = 0.15...0.50
    private static let defaultRefractory: Float = 0.25

    private static func decodeMono(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return ([], 0)
        }
        try file.read(into: buffer)
        let count = Int(buffer.frameLength)
        guard count > 0, let channels = buffer.floatChannelData else { return ([], 0) }
        let channelCount = Int(format.channelCount)
        if channelCount == 1 {
            return (Array(UnsafeBufferPointer(start: channels[0], count: count)), format.sampleRate)
        }
        var mono = [Float](repeating: 0, count: count)
        let scale = 1.0 / Float(channelCount)
        for channel in 0..<channelCount {
            let pointer = UnsafeBufferPointer(start: channels[channel], count: count)
            for index in 0..<count { mono[index] += pointer[index] * scale }
        }
        return (mono, format.sampleRate)
    }

    private struct Run {
        var beatMid: [Float] = []
        var candidates: [String: [Float]] = [:]
        var duration: Double = 0
        var bpm: Float = 0
    }

    /// The REAL `MIRPipeline` over a decoded track — a session CSV was tried first and the
    /// interval trough looked varied on it; on the production pipeline it is a six-value
    /// staircase. The pipeline is the instrument (FA #27).
    private static func run(url: URL) throws -> Run {
        let (samples, sampleRate) = try decodeMono(url)
        guard !samples.isEmpty else { return Run() }
        let pipeline = MIRPipeline(binCount: fftSize / 2,
                                   sampleRate: Float(sampleRate), fftSize: fftSize)
        let fft = try FFTMagnitudeKernel(fftSize: fftSize)
        let fps = Float(sampleRate) / Float(fftSize)
        let deltaTime = Float(fftSize) / Float(sampleRate)
        var out = Run()
        var offset = 0
        var time: Float = 0
        while offset + fftSize <= samples.count {
            samples.withUnsafeBufferPointer { src in
                fft.windowed.withUnsafeMutableBufferPointer { dst in
                    guard let s = src.baseAddress, let d = dst.baseAddress else { return }
                    d.update(from: s.advanced(by: offset), count: fftSize)
                }
            }
            fft.computeMagnitudes()
            let fv = pipeline.process(magnitudes: fft.magnitudes,
                                      fps: fps, time: time, deltaTime: deltaTime)
            out.beatMid.append(fv.beatMid)
            for (key, value) in [("beatTreble", fv.beatTreble), ("beatComposite", fv.beatComposite),
                                 ("spectralFlux", fv.spectralFlux), ("midHigh", fv.midHigh),
                                 ("mid_dev", fv.midDev), ("mid_att", fv.midAtt),
                                 ("bass_dev", fv.bassDev), ("centroid", fv.spectralCentroid)] {
                out.candidates[key, default: []].append(value)
            }
            offset += fftSize
            time += deltaTime
        }
        out.duration = Double(samples.count) / sampleRate
        out.bpm = pipeline.stableBPM ?? 0
        return out
    }

    /// Frame indices of the gated note events — the clock "same size, fewer times" needs.
    private static func noteEvents(_ beatMid: [Float], bpm: Float, deltaTime: Float) -> [Int] {
        let refractory = bpm > 0
            ? min(max(30 / bpm, refractoryBounds.lowerBound), refractoryBounds.upperBound)
            : defaultRefractory
        var out: [Int] = []
        var since = Float.greatestFiniteMagnitude
        for (idx, value) in beatMid.enumerated() {
            since += deltaTime
            if value >= triggerLevel && since >= refractory { out.append(idx); since = 0 }
        }
        return out
    }

    @Test("which primitive carries per-note magnitude (FTR_AUDIO_DIR=…)")
    func reportPerNoteValueCandidates() throws {
        guard let dir = ProcessInfo.processInfo.environment["FTR_AUDIO_DIR"] else { return }
        let base = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        for name in Self.tracks {
            let url = base.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                Issue.record("missing source track \(url.path)"); continue
            }
            let result = try Self.run(url: url)
            guard !result.beatMid.isEmpty else { continue }
            let deltaTime = Float(result.duration / Double(result.beatMid.count))
            let events = Self.noteEvents(result.beatMid, bpm: result.bpm, deltaTime: deltaTime)

            print("\n── PER-NOTE MAGNITUDE CANDIDATES ──────────────────────────────────")
            print(String(format: "file  %@   %d notes over %.0fs (%.2f/s)",
                         name as NSString, events.count, result.duration,
                         Double(events.count) / result.duration))
            for key in result.candidates.keys.sorted() {
                guard let series = result.candidates[key] else { continue }
                let at = events.compactMap { $0 < series.count ? series[$0] : nil }.sorted()
                guard at.count > 20 else { continue }
                print(String(format: "  %-14s spread %7.4f   distinct %4d / %d",
                             (key as NSString).utf8String!,
                             at[at.count * 19 / 20] - at[at.count / 20],
                             Set(at.map { Int($0 * 1000) }).count, at.count))
            }
            print("───────────────────────────────────────────────────────────────────\n")

            // THE CLAIM THIS SUITE EXISTS TO KEEP TRUE. If `beat_mid` ever stops saturating
            // at the note instants, the FTR.7 conclusion is stale and must be re-derived
            // rather than cited — including by MEL.1, which is still open.
            let atNote = events.compactMap { $0 < result.beatMid.count ? result.beatMid[$0] : nil }
            let distinct = Set(atNote.map { Int($0 * 1000) }).count
            #expect(distinct <= 3, """
                \(name): beat_mid takes \(distinct) distinct values at the note instants. \
                FTR.7 concluded it saturates at the trigger and therefore carries no per-note \
                magnitude; if that is no longer true, re-derive before reusing the conclusion.
                """)
        }
    }
}

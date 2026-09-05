// PR.14 — how much did the 30 s clamp distort the grid, across Matt's actual corpus?
//
// The CENSUS full run reported 32.9 % of 24,350 tracks "beat irregular" and that figure
// gates beat-locked visuals (D-154). It was produced by the analyzer that saw only the
// first 30 s — and the metric it used compares a 30 s full-mix grid against a **10 s**
// drums grid (`StemSeparator.requiredMonoSamples` = 440,320 = 9.98 s at 44.1 kHz), i.e. a
// ~60-beat estimate against a ~20-beat one. Unequal spans disagreeing is the same artifact
// that made whole-track decoding look like a regression in FT.4.1.
//
// This measures the cheap, decisive half first: for each sampled track, the grid from the
// first 30 s vs the grid from the WHOLE file. No stems, no MIR — decode + two grids.
//
//   UZUME_CLAMP_IMPACT=1 [CLAMP_LIMIT=120] \
//   swift test --package-path UzumeEngine --filter CorpusClampImpactProbe
import Testing
import Foundation
import AVFoundation
import Metal
@testable import DSP
@testable import Session

@Suite("CorpusClampImpactProbe")
struct CorpusClampImpactProbe {

    private static func decodeMono(url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return ([], 0) }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { return ([], 0) }
        let count = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        if channelCount == 1 {
            return (Array(UnsafeBufferPointer(start: channels[0], count: count)), format.sampleRate)
        }
        var mono = [Float](repeating: 0, count: count)
        let scale = 1.0 / Float(channelCount)
        for channel in 0..<channelCount {
            let ptr = UnsafeBufferPointer(start: channels[channel], count: count)
            for i in 0..<count { mono[i] += ptr[i] * scale }
        }
        return (mono, format.sampleRate)
    }

    /// BPM by least-squares fit of beat time on beat index — not the median IOI, which
    /// quantises to the model's 20 ms frame grid and cannot resolve small differences.
    private static func bpm(_ beats: [Double]) -> Double {
        guard beats.count > 8 else { return 0 }
        var gaps = (0..<(beats.count - 1)).map { beats[$0 + 1] - beats[$0] }
        gaps.sort()
        let nominal = gaps[gaps.count / 2]
        guard nominal > 0 else { return 0 }
        var bestLo = 0, bestLen = 1, lo = 0
        for i in 1..<beats.count {
            if abs((beats[i] - beats[i - 1]) / nominal - 1) < 0.25 {
                if i - lo + 1 > bestLen { bestLen = i - lo + 1; bestLo = lo }
            } else { lo = i }
        }
        guard bestLen > 8 else { return 60.0 / nominal }
        let run = Array(beats[bestLo..<(bestLo + bestLen)])
        let n = Double(run.count)
        let meanIdx = (n - 1) / 2, meanT = run.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (i, t) in run.enumerated() {
            let di = Double(i) - meanIdx
            num += di * (t - meanT); den += di * di
        }
        guard den > 0, num > 0 else { return 60.0 / nominal }
        return 60.0 / (num / den)
    }

    /// Octave-folded relative difference, the same shape D-154's gate uses.
    private static func foldedDisagreement(_ a: Double, _ b: Double) -> Double {
        guard a > 0, b > 0 else { return 0 }
        var ratio = a / b
        while ratio > 1.5 { ratio /= 2 }
        while ratio < 0.67 { ratio *= 2 }
        return abs(ratio - 1)
    }

    @Test("30 s clamp vs whole track, over the corpus pilot",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_CLAMP_IMPACT"] == "1"))
    func probe() throws {
        let root = URL(fileURLWithPath: "/Volumes/Extreme SSD")
        // #filePath is .../UzumeEngine/Tests/UzumeEngineTests/DSP/<file> — five levels
        // up is the repo root. Overridable so the probe can point at any track list.
        let pilot = ProcessInfo.processInfo.environment["CLAMP_LIST"].map(URL.init(fileURLWithPath:))
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("tools/data/corpus_pilot_1000.csv")
        let text = try String(contentsOf: pilot, encoding: .utf8)
        // `\.isNewline`, NOT `$0 == "\n" || $0 == "\r"`: Swift treats CRLF as a SINGLE
        // grapheme cluster, so on a CRLF file that comparison matches neither half and the
        // whole file comes back as one "line". This corpus manifest is CRLF.
        let lines = text.split(whereSeparator: \.isNewline)
        let limit = Int(ProcessInfo.processInfo.environment["CLAMP_LIMIT"] ?? "") ?? 120
        print("  list: \(pilot.lastPathComponent) — \(lines.count) lines, limit \(limit)")

        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)

        var folded: [Double] = []
        var meterChanged = 0, confUp = 0, confDown = 0, done = 0, skipped = 0
        var confClamp: [Double] = [], confWhole: [Double] = []

        for line in lines.dropFirst() {
            if done >= limit { break }
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard let rel = cols.first, !rel.isEmpty else {
                if skipped < 3 { print("  skip[no relpath] cols=\(cols.count)") }
                skipped += 1; continue
            }
            let url = root.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: url.path) else {
                if skipped < 3 { print("  skip[missing] \(rel)") }
                skipped += 1; continue
            }
            guard let (audio, rate) = try? Self.decodeMono(url: url), rate > 0 else {
                if skipped < 6 { print("  skip[decode] \(rel)") }
                skipped += 1; continue
            }
            guard audio.count > Int(rate * 45) else {
                if skipped < 9 { print("  skip[short \(Double(audio.count) / rate)s] \(rel)") }
                skipped += 1; continue
            }

            let clampCount = min(audio.count, Int(30 * rate))
            let clamp = analyzer.analyzeBeatGrid(
                samples: Array(audio[0..<clampCount]), sampleRate: rate, wholeTrack: false)
            let whole = analyzer.analyzeBeatGrid(
                samples: audio, sampleRate: rate, wholeTrack: true)
            let bpmClamp = Self.bpm(clamp.beats), bpmWhole = Self.bpm(whole.beats)
            guard bpmClamp > 0, bpmWhole > 0 else { skipped += 1; continue }

            folded.append(Self.foldedDisagreement(bpmClamp, bpmWhole))
            if clamp.beatsPerBar != whole.beatsPerBar { meterChanged += 1 }
            confClamp.append(Double(clamp.barConfidence))
            confWhole.append(Double(whole.barConfidence))
            if whole.barConfidence > clamp.barConfidence + 0.05 { confUp += 1 }
            if whole.barConfidence < clamp.barConfidence - 0.05 { confDown += 1 }
            done += 1
            if done % 20 == 0 { print("  … \(done) tracks") }
        }

        guard !folded.isEmpty else { Issue.record("no tracks measured"); return }
        let sorted = folded.sorted()
        func pct(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        let over10 = sorted.filter { $0 > 0.10 }.count
        func mean(_ a: [Double]) -> Double { a.reduce(0, +) / Double(a.count) }

        print("""

          PR.14 — 30 s clamp vs WHOLE TRACK, \(done) corpus tracks (\(skipped) skipped)

          Grid BPM disagreement, clamp vs whole-track (octave-folded):
            p50 \(String(format: "%.4f", pct(0.5)))   p90 \(String(format: "%.4f", pct(0.9)))   \
          p99 \(String(format: "%.4f", pct(0.99)))
            above the D-154 0.10 gate: \(over10)/\(done) (\(String(format: "%.1f", Double(over10) / Double(done) * 100)) %)

          Meter changed when the whole track was seen: \(meterChanged)/\(done) \
          (\(String(format: "%.1f", Double(meterChanged) / Double(done) * 100)) %)

          barConfidence  clamp mean \(String(format: "%.3f", mean(confClamp)))  ->  \
          whole mean \(String(format: "%.3f", mean(confWhole)))
            improved by >0.05: \(confUp)   worsened by >0.05: \(confDown)
        """)
    }
}

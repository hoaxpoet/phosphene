// GuitarChannelReportTests — FTR.12: is there any per-stem feature that separates a
// guitar from the drums on real material?
//
// WHY THIS IS OFFLINE AND NOT CAPTURE REPLAY. Fractal Tree's tips have been routed to
// `other_onset_rate` since FTR.8 on the strength of ONE track (Cherub Rock, r +0.14 with
// drums). FTR.11 then measured the same feature on Seven Nation Army at r +0.71 — the same
// route reading the drums under a label that says guitar. The ten sessions on disk are four
// rock tracks Matt happened to play; they cannot answer a question about whether a feature
// GENERALISES. Offline selection costs no live-session time and lets the corpus carry
// guitarless negative controls, which is the whole design (see the corpus doc).
//
// WHY THESE NUMBERS SURVIVE BUG-086. Stem-vs-stem correlation is lag-immune: both series come
// out of the same separation pass, so the ≈2.9 s preset-facing latency cancels. Any comparison
// against a NON-stem series (a FeatureVector field, the beat grid) is not lag-immune and would
// need an explicit lag sweep — none is made here.
//
// PRODUCTION OBJECTS, NOT A PROXY. `StemSeparator.separate` in ~10 s chunks (the model's fixed
// `modelFrameCount = 431` window) → `StemAnalyzer.analyze` per 1024-sample hop, which is
// `SessionPreparer.warmUpAndAnalyze`'s exact framing, capturing every frame instead of only
// the last. Plus `InstrumentFamilyAnalyzer` (IFC.4) and a direct PANNs guitar-class probe.
//
//   FTR12_AUDIO="/Volumes/Extreme SSD/…/track.mp3" FTR12_LABEL=sna \
//     swift test --package-path PhospheneEngine --filter GuitarChannel
//
// Optional: FTR12_SECONDS (default 120), FTR12_FPS (override the fps handed to
// StemAnalyzer — see the ANALYSIS RATE note below), FTR12_SKIP_PANNS=1.
//
// ANALYSIS RATE. `analyze(fps:)` sets the time constant of every internal EMA
// (τ = 1/(α·fps)), so it is a real knob, not bookkeeping. This harness passes
// sampleRate/1024 ≈ 43 Hz, matching the production OFFLINE path (SessionPreparer). The LIVE
// path calls analyze once per render frame at ~60 Hz, so its τ is shorter. r(other, drums) is
// a same-rate comparison inside one run and is unaffected; the absolute p05/p50/p95 figures
// are rate-dependent and should be read as offline-path values.
//
// Reporting, not asserting a verdict. The assertions cover only what is mechanically
// checkable — that audio decoded, stems came back, and the series are not pinned. Whether any
// feature is a usable guitar channel is read off the table.

import Foundation
import Metal
import Testing
@testable import DSP
@testable import ML
@testable import Shared

@Suite("Guitar channel report (FTR.12)", .serialized)
struct GuitarChannelReportTests {

    private static let hop = 1024
    /// Separation chunk — the separator's output-buffer capacity (10 s at 44.1 kHz).
    private static let chunkLen = 441_000

    /// AudioSet (527-class) indices for the guitar, resolved from
    /// `~/panns_data/class_labels_indices.csv` — the same list `tools/panns_reference.py`
    /// indexes, cross-checked against the repo's committed `family_indices` fixture
    /// (Brass instrument 185 / Bowed string instrument 189 / Harp 199 all match).
    ///
    /// `142 Bass guitar` is deliberately EXCLUDED: it is the bass line, and the question is
    /// whether the guitar has a channel of its own.
    private static let guitarClasses: [(Int, String)] = [
        (139, "Plucked string"), (140, "Guitar"), (141, "Electric guitar"),
        (143, "Acoustic guitar"), (144, "Steel/slide"), (146, "Strum")
    ]

    // MARK: - Report

    @Test("report per-stem feature separation on one track (FTR12_AUDIO=…)")
    func reportGuitarChannel() throws {
        guard let path = ProcessInfo.processInfo.environment["FTR12_AUDIO"] else { return }
        let env = ProcessInfo.processInfo.environment
        let label = env["FTR12_LABEL"] ?? URL(fileURLWithPath: path).deletingPathExtension()
            .lastPathComponent
        let maxSeconds = env["FTR12_SECONDS"].flatMap { Float($0) } ?? 120
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

        let sampleRate = StemSeparator.modelSampleRate
        var samples = try Self.decodeMono(url: url, targetSampleRate: Int(sampleRate))
        #expect(!samples.isEmpty, "decoded no audio from \(url.path)")
        guard !samples.isEmpty else { return }
        let maxSamples = Int(maxSeconds * sampleRate)
        if samples.count > maxSamples { samples = Array(samples.prefix(maxSamples)) }

        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("no Metal device — separation cannot run")
            return
        }
        let separator = try StemSeparator(device: device)
        let stems = try Self.separateInChunks(samples: samples, separator: separator,
                                              sampleRate: sampleRate)
        #expect(stems[0].count > Self.hop * 100,
                "\(label): only \(stems[0].count) stem samples — too short to measure")
        guard stems[0].count > Self.hop * 100 else { return }

        let fps = env["FTR12_FPS"].flatMap { Float($0) } ?? sampleRate / Float(Self.hop)
        let series = Self.analyzePerHop(stems: stems, sampleRate: sampleRate, fps: fps)

        print("""

        ── FTR.12 GUITAR CHANNEL ───────────────────────────────────────────
        label         \(label)
        file          \(url.lastPathComponent)
        analysed      \(String(format: "%.1f s", Float(samples.count) / sampleRate)) \
        → \(series.frameCount) frames at \(String(format: "%.1f", fps)) Hz
        """)
        Self.printStemTable(series, label: label)
        if env["FTR12_SKIP_PANNS"] == nil {
            try Self.printRecognizerPanel(url: url, device: device, label: label,
                                          seconds: Float(samples.count) / sampleRate)
        }
        print("────────────────────────────────────────────────────────────────────\n")

        // Mechanical claims only. Whether any of this is a guitar channel is the table's job.
        let other = series.value(.onsetRate, .other)
        #expect(Self.distinct(other) > 1, """
            \(label): otherOnsetRate is a constant \(other.first ?? 0) — the MEASUREMENT is \
            broken, not the feature. Check the separation ran.
            """)
    }

    // MARK: - Feature series

    enum Kind: String, CaseIterable {
        case onsetRate, energyRel, energyDev, energySlope
    }

    enum Stem: Int, CaseIterable {
        case vocals = 0, drums, bass, other
        var name: String { ["vocals", "drums", "bass", "other"][rawValue] }
    }

    /// `[Kind: [Stem-index: series]]`, one sample per analysis frame.
    struct Series {
        var table: [Kind: [[Float]]] = [:]
        var frameCount: Int { table[.onsetRate]?.first?.count ?? 0 }
        func value(_ kind: Kind, _ stem: Stem) -> [Float] { table[kind]?[stem.rawValue] ?? [] }
    }

    private static func analyzePerHop(
        stems: [[Float]], sampleRate: Float, fps: Float
    ) -> Series {
        let analyzer = StemAnalyzer(sampleRate: sampleRate)
        var out = Series()
        for kind in Kind.allCases { out.table[kind] = [[], [], [], []] }
        let sampleCount = stems[0].count
        var offset = 0
        while offset + hop <= sampleCount {
            let frame = stems.map { Array($0[offset..<offset + hop]) }
            let f = analyzer.analyze(stemWaveforms: frame, fps: fps)
            out.table[.onsetRate]?[0].append(f.vocalsOnsetRate)
            out.table[.onsetRate]?[1].append(f.drumsOnsetRate)
            out.table[.onsetRate]?[2].append(f.bassOnsetRate)
            out.table[.onsetRate]?[3].append(f.otherOnsetRate)
            out.table[.energyRel]?[0].append(f.vocalsEnergyRel)
            out.table[.energyRel]?[1].append(f.drumsEnergyRel)
            out.table[.energyRel]?[2].append(f.bassEnergyRel)
            out.table[.energyRel]?[3].append(f.otherEnergyRel)
            out.table[.energyDev]?[0].append(f.vocalsEnergyDev)
            out.table[.energyDev]?[1].append(f.drumsEnergyDev)
            out.table[.energyDev]?[2].append(f.bassEnergyDev)
            out.table[.energyDev]?[3].append(f.otherEnergyDev)
            out.table[.energySlope]?[0].append(f.vocalsEnergySlope)
            out.table[.energySlope]?[1].append(f.drumsEnergySlope)
            out.table[.energySlope]?[2].append(f.bassEnergySlope)
            out.table[.energySlope]?[3].append(f.otherEnergySlope)
            offset += hop
        }
        return out
    }

    // MARK: - Output

    private static func printStemTable(_ s: Series, label: String) {
        print("""
          per-stem features — r is whole-series Pearson against the SAME feature on another
          stem (lag-immune, BUG-086 cancels). cm = common-mode share 1 − var(x−mean4)/var(x),
          whose null is ≈22 % (CHR.1 §1.1 measured control).
          kind         stem    r:drums  r:bass  r:vocal      p05      p50      p95   distinct    cm
        """)
        for kind in Kind.allCases {
            let all: [[Float]] = Stem.allCases.map { s.value(kind, $0) }
            var mean4 = [Float](repeating: 0, count: all[0].count)
            for i in 0..<mean4.count {
                var sum: Float = 0
                for stem in 0..<4 { sum += all[stem][i] }
                mean4[i] = sum / 4
            }
            for stem in Stem.allCases {
                let x = all[stem.rawValue]
                let q: (Float, Float, Float) = percentiles(x)
                let rDrums: Float? = stem == .drums ? nil : correlation(x, all[1])
                let rBass: Float? = stem == .bass ? nil : correlation(x, all[2])
                let rVocals: Float? = stem == .vocals ? nil : correlation(x, all[0])
                let cm: Float = commonMode(x, mean4)
                let n: Int = distinct(x)
                let head: String = "  \(kind.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0))"
                    + stem.name.padding(toLength: 8, withPad: " ", startingAt: 0)
                let rs: String = "\(fmtR(rDrums)) \(fmtR(rBass)) \(fmtR(rVocals))"
                let qs: String = String(format: "  %8.4f %8.4f %8.4f  %8d  %4.0f%%",
                                        q.0, q.1, q.2, n, cm * 100)
                print(head + rs + qs)
                // Machine-parseable line for cross-track aggregation.
                let csv: String = String(format: "%.4f|%.4f|%.4f|%.4f|%d|%.3f",
                                         rDrums ?? Float.nan, q.0, q.1, q.2, n, cm)
                print("  FTR12ROW|\(label)|\(kind.rawValue)|\(stem.name)|" + csv)
            }
        }
    }

    /// IFC.4's four families PLUS a direct PANNs guitar-class probe.
    ///
    /// The family probe is here to record a STRUCTURAL fact, not to measure guitar: IFC.4's
    /// `strings` family is `[189…194, 199]` = bowed strings + harp, and no family contains any
    /// guitar class. The IFC.4 series is reachable offline and cannot report a guitar at all.
    /// The 527-class probs the same model already computes DO carry guitar classes, so those
    /// are read directly — that is the only recognizer evidence available without new weights.
    private static func printRecognizerPanel(
        url: URL, device: MTLDevice, label: String, seconds: Float
    ) throws {
        let panns = try PANNsMobileNetV1(device: device)
        let rate = PANNsMobileNetV1.sampleRate
        var mono = try decodeMono(url: url, targetSampleRate: rate)
        // Same audio as the stem panel above, or the two panels describe different tracks.
        let limit = Int(seconds * Float(rate))
        if mono.count > limit { mono = Array(mono.prefix(limit)) }
        let window = PANNsMobileNetV1.defaultFrames * PANNsMobileNetV1.hop
        guard mono.count >= window else { return }

        var families = InstrumentFamilyTracker()
        var famSeries: [[Float]] = [[], [], [], []]
        var guitarMax: [Float] = []
        var offset = 0
        while offset + window <= mono.count {
            let probs = try panns.predict(waveform: Array(mono[offset..<offset + window]))
            let activity = families.derive(probs: probs)
            for family in InstrumentFamily.allCases {
                famSeries[family.index].append(activity[family].smoothed)
            }
            guitarMax.append(guitarClasses.reduce(Float(0)) { max($0, probs[$1.0]) })
            offset += rate   // IFC.4's 1 s hop
        }
        print("\n  recognizer (PANNs MobileNetV1, \(guitarMax.count) × 1 s windows)")
        print("  IFC.4 family (smoothed)          p50      p95   ← NO family contains a guitar class")
        for family in InstrumentFamily.allCases {
            let q: (Float, Float, Float) = percentiles(famSeries[family.index])
            let name: String = "\(family)".padding(toLength: 30, withPad: " ", startingAt: 0)
            print("    " + name + String(format: "%7.4f  %7.4f", q.1, q.2))
        }
        let gq = percentiles(guitarMax)
        print(String(format: "  guitar classes (max prob)       %7.4f  %7.4f   ← read directly " +
                     "from the 527-class probs", gq.1, gq.2))
        print(String(format: "  FTR12PANNS|%@|%.4f|%.4f|%.4f|%.4f",
                     label, gq.1, gq.2,
                     percentiles(famSeries[InstrumentFamily.strings.index]).1,
                     percentiles(famSeries[InstrumentFamily.percussion.index]).1))
    }

    // MARK: - Separation

    private static func separateInChunks(
        samples: [Float], separator: StemSeparator, sampleRate: Float
    ) throws -> [[Float]] {
        var stems: [[Float]] = [[], [], [], []]
        var offset = 0
        while offset < samples.count {
            let end = min(offset + chunkLen, samples.count)
            let chunk = Array(samples[offset..<end])
            guard chunk.count >= StemSeparator.nFFT else { break }
            let result = try separator.separate(audio: chunk, channelCount: 1,
                                                sampleRate: sampleRate)
            // Trim to the chunk's own length so the tail zero-pad never reaches the analyzer.
            let count = min(min(result.sampleCount, chunk.count), separator.stemBuffers[0].capacity)
            for i in 0..<4 {
                stems[i].append(contentsOf: separator.stemBuffers[i].pointer.prefix(count))
            }
            offset = end
        }
        return stems
    }

    // MARK: - Statistics

    private static func fmtR(_ r: Float?) -> String {
        guard let r, r.isFinite else { return "     —" }
        return String(format: "%+.3f", r)
    }

    /// Pearson r. `nil` when either series has no variance (a constant cannot correlate).
    static func correlation(_ x: [Float], _ y: [Float]) -> Float? {
        let n = min(x.count, y.count)
        guard n > 2 else { return nil }
        let mx = x.prefix(n).reduce(0, +) / Float(n)
        let my = y.prefix(n).reduce(0, +) / Float(n)
        var sxy: Float = 0, sxx: Float = 0, syy: Float = 0
        for i in 0..<n {
            let dx = x[i] - mx, dy = y[i] - my
            sxy += dx * dy; sxx += dx * dx; syy += dy * dy
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }

    static func percentiles(_ x: [Float]) -> (Float, Float, Float) {
        guard !x.isEmpty else { return (0, 0, 0) }
        let s = x.sorted()
        func at(_ p: Float) -> Float { s[min(s.count - 1, max(0, Int(p * Float(s.count - 1)))) ] }
        return (at(0.05), at(0.50), at(0.95))
    }

    /// Distinct-value count. A feature quantised to a handful of levels cannot drive smooth
    /// motion however well it correlates — FTR.11 found all four onset rates sharing one
    /// narrow distribution, and this is the column that shows it.
    static func distinct(_ x: [Float]) -> Int { Set(x).count }

    /// CHR.1's statistic: the share of a trace that is just the mix's loudness envelope.
    /// Biased upward because x is one quarter of `mean4`; CHR.1 §1.1 measured the null at
    /// ≈22 % against a timing-destroyed control.
    static func commonMode(_ x: [Float], _ mean4: [Float]) -> Float {
        let n = min(x.count, mean4.count)
        guard n > 2 else { return 0 }
        func variance(_ v: [Float]) -> Float {
            let m = v.reduce(0, +) / Float(v.count)
            return v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Float(v.count)
        }
        let vx = variance(Array(x.prefix(n)))
        guard vx > 0 else { return 0 }
        return 1 - variance((0..<n).map { x[$0] - mean4[$0] }) / vx
    }

    // MARK: - Decode

    /// ffmpeg mono decode at an exact target rate — the suite-standard path
    /// (`FixtureSessionCaptureGenerator`). Decoding at the target rate means neither the
    /// separator (44.1 kHz) nor PANNs (32 kHz) resamples, so no resampler sits between the
    /// corpus and the measurement.
    private static func decodeMono(url: URL, targetSampleRate: Int) throws -> [Float] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["ffmpeg", "-loglevel", "error", "-i", url.path,
                          "-ac", "1", "-ar", "\(targetSampleRate)", "-f", "f32le", "-"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        try proc.run()
        let raw = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "GuitarChannelReport", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ffmpeg failed for \(url.path)"])
        }
        let count = raw.count / MemoryLayout<Float>.size
        return raw.withUnsafeBytes { buf in
            Array(UnsafeBufferPointer(start: buf.bindMemory(to: Float.self).baseAddress,
                                      count: count))
        }
    }
}

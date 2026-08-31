// LocalFilePrepCostHarness — what local-file preparation costs today, and what a
// full-file stem series would add (LFSTEM scoping measurement).
//
// STATUS: env-gated diagnostic (`UZUME_PREP_COST=1`). Zero production importers
// by design; it exists so a scoping number is measured rather than estimated.
//
// The question it answers: stem features reach presets ~2.5 s late (a 2 s live
// separation window plus 270–474 ms of inference, measured live in session
// `2026-08-26T22-04-58Z`). For a LOCAL file none of that is necessary — the whole
// file is already decoded during preparation (`CachedTrackData.loudnessProfile` is
// measured over it), and the codebase already ships a pre-analyzed series sampled by
// playback position (`instrumentFamilySeries`, IFC.4 / D-177). Stems are cached as a
// single snapshot instead of a series, which is the whole reason for the lag.
//
// Moving them to a series costs preparation time. This harness measures BOTH sides on
// real audio through the production components:
//
//   A. TODAY — one `SessionPreparer.analyzePreview` over the clip (what a fresh
//      local-file analysis pays now).
//   B. PROPOSED — the marginal cost of separating the same audio window-by-window at
//      the series hop, which is what a full-file pass adds on top of A.
//
// Run:
//   UZUME_PREP_COST=1 swift test --package-path UzumeEngine \
//     --filter LocalFilePrepCostHarness
//
// Requires the tempo fixtures + ML weights (`Scripts/link_fixtures.sh` in a worktree).

import Foundation
import Metal
import Testing
@testable import DSP
@testable import ML
@testable import Session
@testable import Shared

// MARK: - LocalFilePrepCostHarness

@Suite("Local-file preparation cost (env-gated)")
struct LocalFilePrepCostHarness {

    /// One 30 s fixture per instrumentation character; the separator's cost is
    /// content-independent but decode and MIR are not.
    private static let fixtures = ["love_rehab.m4a", "so_what.m4a", "there_there.m4a"]

    /// Hop for the proposed stem series. Matches the live separation period
    /// (`VisualizerEngine.stemSeparationPeriodSeconds`), so a series frame lands
    /// wherever a live separation would have.
    private static let seriesHopSeconds: Double = 2.0

    /// Window each series frame separates. `StemSeparator.separate` pads-or-truncates to
    /// `requiredMonoSamples` (440320 = 9.98 s at 44.1 kHz) regardless of what it is handed,
    /// so this must be the model window or the harness would be timing inference over
    /// mostly-zero input. The cost is identical either way — MPSGraph runs a fixed-size
    /// graph — but the features would be meaningless, and this file is a template someone
    /// will copy.
    private static let seriesWindowSeconds: Double =
        Double(StemSeparator.requiredMonoSamples) / 44_100.0

    private static let sampleRate = 44_100

    @Test("Measure current prep cost and the marginal cost of a full-file stem series")
    func measurePrepCost() throws {
        guard ProcessInfo.processInfo.environment["UZUME_PREP_COST"] == "1" else {
            print("LocalFilePrepCostHarness: UZUME_PREP_COST not set, skipping")
            return
        }
        guard #available(macOS 14.2, *) else { return }
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("LocalFilePrepCostHarness: no Metal device, skipping")
            return
        }
        let fixturesDir = URL(fileURLWithPath: String(#filePath))
            .deletingLastPathComponent()   // Diagnostics/
            .deletingLastPathComponent()   // UzumeEngineTests/
            .deletingLastPathComponent()   // Tests/
            .appendingPathComponent("Fixtures/tempo")

        let separator = try StemSeparator(device: device)
        let familyAnalyzer = try InstrumentFamilyAnalyzer(device: device)
        let gridAnalyzer = try DefaultBeatGridAnalyzer(device: device)

        // One untimed warm pass: MPSGraph compiles its graph on first use, and that
        // one-off must not land in the reported per-window cost.
        let warm = [Float](repeating: 0, count: Self.sampleRate)
        _ = try? separator.separate(audio: warm, channelCount: 1, sampleRate: Float(Self.sampleRate))

        print("")
        print("=== LOCAL-FILE PREP COST ===")
        print(String(format: "%-16s %8s %8s %8s %8s %8s",
                     ("fixture" as NSString).utf8String!, ("dur_s" as NSString).utf8String!,
                     ("decode" as NSString).utf8String!, ("prep_s" as NSString).utf8String!,
                     ("win_ms" as NSString).utf8String!, ("ser_s" as NSString).utf8String!))

        for name in Self.fixtures {
            let url = fixturesDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("  \(name): MISSING (run Scripts/link_fixtures.sh) — skipped")
                continue
            }

            // --- decode (part of today's prep, and unchanged by the proposal) ---
            let decodeStart = Date()
            let samples = try Self.decodeMonoFloat32(url: url, targetSampleRate: Self.sampleRate)
            let decodeSeconds = Date().timeIntervalSince(decodeStart)
            let durationSeconds = Double(samples.count) / Double(Self.sampleRate)

            // --- A. today: one analyzePreview over the clip ---
            let preview = PreviewAudio(
                trackIdentity: TrackIdentity(title: name, artist: "fixture",
                                             spotifyID: "local:prepcost:\(name)"),
                pcmSamples: samples,
                sampleRate: Self.sampleRate,
                duration: durationSeconds
            )
            let prepStart = Date()
            _ = try SessionPreparer.analyzePreview(
                preview,
                separator: separator,
                analyzer: StemAnalyzer(sampleRate: Float(Self.sampleRate)),
                classifier: MoodClassifier(),
                beatGridAnalyzer: gridAnalyzer,
                familyAnalyzer: familyAnalyzer,
                prefetchedProfile: nil
            )
            let prepSeconds = Date().timeIntervalSince(prepStart)

            // --- B. proposed: separate window-by-window at the series hop ---
            let windowSamples = Int(Self.seriesWindowSeconds * Double(Self.sampleRate))
            let hopSamples = Int(Self.seriesHopSeconds * Double(Self.sampleRate))
            var windowMs: [Double] = []
            var start = 0
            // A trailing partial window is still a real series frame in production (the
            // separator pads it), but it is excluded here so every timed call is identical.
            while start + windowSamples <= samples.count {
                let window = Array(samples[start..<(start + windowSamples)])
                let t0 = Date()
                _ = try separator.separate(audio: window, channelCount: 1,
                                           sampleRate: Float(Self.sampleRate))
                windowMs.append(Date().timeIntervalSince(t0) * 1000)
                start += hopSamples
            }
            let seriesSeconds = windowMs.reduce(0, +) / 1000
            let medianWindowMs = Self.median(windowMs)

            // --- C. the OTHER half of a series: StemAnalyzer swept over the separated
            // waveforms at the analysis hop. The live path calls analyze() once per
            // analysis frame over a 1024-sample slice (VisualizerEngine+Audio), so a
            // pre-analyzed series has to do the same sweep offline. Separation is the
            // headline cost; this is the term that decides whether it is the ONLY one.
            let sepResult = try separator.separate(
                audio: Array(samples.prefix(windowSamples)),
                channelCount: 1, sampleRate: Float(Self.sampleRate))
            let stemWaveforms = sepResult.stemWaveforms
            let analysisHop = 1024
            let sweepAnalyzer = StemAnalyzer(sampleRate: Float(Self.sampleRate))
            let fps = Float(Self.sampleRate) / Float(analysisHop)
            var frames = 0
            let sweepStart = Date()
            var pos = 0
            while pos + analysisHop <= (stemWaveforms.first?.count ?? 0) {
                let slice = stemWaveforms.map { Array($0[pos..<(pos + analysisHop)]) }
                _ = sweepAnalyzer.analyze(stemWaveforms: slice, fps: fps)
                frames += 1
                pos += analysisHop
            }
            let sweepSeconds = Date().timeIntervalSince(sweepStart)
            let perFrameMs = frames > 0 ? sweepSeconds * 1000 / Double(frames) : 0

            print(String(format: "%-16@ %8.1f %8.2f %8.2f %8.1f %8.2f",
                         name as NSString, durationSeconds, decodeSeconds,
                         prepSeconds, medianWindowMs, seriesSeconds))
            print(String(format: "                 windows=%d  min=%.1f ms  max=%.1f ms",
                         windowMs.count, windowMs.min() ?? 0, windowMs.max() ?? 0))

            // Extrapolation, stated as arithmetic rather than asserted: the separator's
            // per-window cost does not depend on how much audio surrounds the window.
            let fourMinuteWindows = Int(240.0 / Self.seriesHopSeconds)
            let fourMinuteSeries = Double(fourMinuteWindows) * medianWindowMs / 1000
            let fourMinuteFrames = Int(240.0 * Double(Self.sampleRate) / Double(analysisHop))
            let fourMinuteSweep = Double(fourMinuteFrames) * perFrameMs / 1000
            print(String(format: "                 feature sweep: %d frames in %.2f s (%.3f ms/frame)",
                         frames, sweepSeconds, perFrameMs))
            print(String(format: "                 → a 4-min track: %d windows x %.0f ms = %.0f s separation"
                         + "  +  %d frames x %.3f ms = %.0f s features  =  %.0f s TOTAL",
                         fourMinuteWindows, medianWindowMs, fourMinuteSeries,
                         fourMinuteFrames, perFrameMs, fourMinuteSweep,
                         fourMinuteSeries + fourMinuteSweep))
        }
        print("=== END ===")
        print("")
    }

    // MARK: - Helpers

    private static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[s.count / 2]
    }

    /// Suite-standard fixture decode (same ffmpeg path `FixtureSessionCaptureGenerator` uses).
    private static func decodeMonoFloat32(url: URL, targetSampleRate: Int) throws -> [Float] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "ffmpeg", "-loglevel", "error",
            "-i", url.path,
            "-ac", "1",
            "-ar", "\(targetSampleRate)",
            "-f", "f32le", "-"
        ]
        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()
        try proc.run()
        let raw = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "LocalFilePrepCostHarness", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ffmpeg decode failed for \(url.path)"])
        }
        let count = raw.count / MemoryLayout<Float>.size
        return raw.withUnsafeBytes { buf in
            let typed = buf.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: typed.baseAddress, count: count))
        }
    }
}

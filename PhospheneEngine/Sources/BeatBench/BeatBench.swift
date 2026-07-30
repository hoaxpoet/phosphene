// BeatBench — beat-sync benchmark scoring harness (GT.3).
// STATUS: active-tool — standalone CLI (executableTarget). Zero production
//   importers BY DESIGN; not dead. See docs/AUDIT_KEEPLIST.md.
//
// Scores a beat grid against the GT.2 ground truth and emits the metric set the
// program commits to (see the `beatbench` skill). Two grid sources:
//
//   offline-grid   — run Phosphene's own analyzer (BeatThisPreprocessor +
//                    BeatThisModel + BeatGridResolver) over a fixture and score
//                    the grid it produces. This is the prep-time path.
//   session-replay — score a recorded session's live grid (GT.3 follow-up).
//
// Usage:
//   swift run BeatBench --self-test
//   swift run BeatBench --mode offline-grid
//   swift run BeatBench --mode offline-grid --tracks bleed,take_five
//   swift run BeatBench --mode offline-grid --report docs/diagnostics/BEATBENCH_BASELINE_2026-07-30.md

import Foundation
import ArgumentParser
import AVFoundation
import Metal
import DSP
import Session

@main
struct BeatBenchCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "BeatBench",
        abstract: "Score beat grids against BeatBench ground truth.",
        discussion: """
        Ground truth comes from GT.2 (Matt's taps, cross-checked against madmom and
        librosa). Only tracks with a committed groundtruth JSON are scored; tracks
        whose ground truth is undetermined are reported as such rather than skipped
        silently.

        --self-test validates every metric against cases with known answers
        (perfect / half-tempo / offbeat / random) and needs no audio.
        """
    )

    @Option(name: .long, help: "offline-grid | session-replay")
    var mode: String = "offline-grid"

    @Option(name: .long, help: "Comma-separated track ids (default: all with ground truth).")
    var tracks: String = ""

    @Flag(name: .long, help: "Validate the metric implementations in-memory and exit.")
    var selfTest: Bool = false

    @Option(name: .long, help: "Write a markdown baseline report to this path.")
    var report: String = ""

    @Option(name: .long, help: "Fixtures dir (default: $BEATBENCH_FIXTURES_DIR).")
    var fixturesDir: String?

    // MARK: - Paths

    private var beatbenchDir: URL {
        URL(fileURLWithPath: String(#filePath))
            .deletingLastPathComponent()   // → Sources/BeatBench
            .deletingLastPathComponent()   // → Sources
            .deletingLastPathComponent()   // → PhospheneEngine
            .appendingPathComponent("Tests/Fixtures/beatbench")
    }

    private func resolvedFixturesDir() -> URL {
        let raw = fixturesDir
            ?? ProcessInfo.processInfo.environment["BEATBENCH_FIXTURES_DIR"]
            ?? "~/phosphene_beatbench_fixtures"
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    // MARK: - Run

    func run() throws {
        if selfTest { return try runSelfTest() }
        switch mode {
        case "offline-grid": try runOfflineGrid()
        case "session-replay":
            throw ValidationError("session-replay mode is not implemented yet (GT.3 follow-up)")
        default:
            throw ValidationError("--mode must be 'offline-grid' or 'session-replay'")
        }
    }

    // MARK: - Self-test

    private func runSelfTest() throws {
        var failures: [String] = []
        func check(_ label: String, _ ok: Bool) {
            print("  \(ok ? "ok  " : "FAIL") \(label)")
            if !ok { failures.append(label) }
        }
        func num(_ value: Double) -> String { String(format: "%.2f", value) }
        print("BeatBench metric self-test")

        // A clean 120 BPM reference: 0.5 s apart, 60 beats.
        let ref = (0..<60).map { 1.0 + Double($0) * 0.5 }

        // 1. Identity — every metric must be perfect.
        let perfect = Metrics.score(reference: ref, estimate: ref)
        check("perfect: F == 1", abs(perfect.fMeasure - 1) < 1e-9)
        check("perfect: Cemgil == 1", abs(perfect.cemgil - 1) < 1e-9)
        check("perfect: CMLt == 1", abs(perfect.cmlt - 1) < 1e-9)
        check("perfect: AMLt == 1", abs(perfect.amlt - 1) < 1e-9)

        // 2. A small constant lag inside the window still matches, but Cemgil must fall
        //    — that is the whole point of Cemgil over F.
        let lagged = ref.map { $0 + 0.030 }
        let lag = Metrics.score(reference: ref, estimate: lagged)
        check("30 ms lag: F still 1", abs(lag.fMeasure - 1) < 1e-9)
        check("30 ms lag: Cemgil drops below F [\(num(lag.cemgil))]", lag.cemgil < 0.85)

        // 3. Beyond the window nothing matches.
        let wayOff = ref.map { $0 + 0.200 }
        check("200 ms lag: F == 0", Metrics.fMeasure(reference: ref, estimate: wayOff).score < 1e-9)

        // 4. Half tempo — the defining CMLt/AMLt case. CMLt must fall (wrong metrical
        //    level); AMLt must stay high (a listener would accept it).
        let half = stride(from: 0, to: ref.count, by: 2).map { ref[$0] }
        let halfScore = Metrics.score(reference: ref, estimate: half)
        check("half tempo: CMLt low [\(num(halfScore.cmlt))]", halfScore.cmlt < 0.5)
        check("half tempo: AMLt high [\(num(halfScore.amlt))]", halfScore.amlt > 0.8)
        check("half tempo: AMLt > CMLt", halfScore.amlt > halfScore.cmlt)

        // 5. Offbeat — same story: wrong phase, right pulse.
        let offbeat = (0..<(ref.count - 1)).map { (ref[$0] + ref[$0 + 1]) / 2 }
        let offScore = Metrics.score(reference: ref, estimate: offbeat)
        check("offbeat: F == 0 (nothing inside ±70 ms)", offScore.fMeasure < 1e-9)
        check("offbeat: AMLt high [\(num(offScore.amlt))]", offScore.amlt > 0.8)

        // 6. One-to-one matching: a double-rate estimate must NOT score perfect recall
        //    and precision. Without one-to-one it would look flawless.
        var doubled: [Double] = []
        for index in 0..<(ref.count - 1) {
            doubled.append(ref[index])
            doubled.append((ref[index] + ref[index + 1]) / 2)
        }
        let dbl = Metrics.fMeasure(reference: ref, estimate: doubled)
        check("double rate: recall high", dbl.recall > 0.9)
        check("double rate: precision ~0.5 (one-to-one holds) [\(num(dbl.precision))]", dbl.precision < 0.6)

        // 7. Nonsense scores near zero on everything.
        let random = (0..<60).map { _ in Double.random(in: 1...31) }.sorted()
        let noise = Metrics.score(reference: ref, estimate: random)
        check("random: CMLt near zero [\(num(noise.cmlt))]", noise.cmlt < 0.25)

        // 8. Degenerate inputs must not crash or claim success.
        check("empty estimate: F == 0", Metrics.fMeasure(reference: ref, estimate: []).score == 0)
        check("empty reference: F == 0", Metrics.fMeasure(reference: [], estimate: ref).score == 0)
        check("single beat: no crash", Metrics.score(reference: [1.0], estimate: [1.0]).cmlt >= 0)

        guard failures.isEmpty else {
            print("\n\(failures.count) check(s) FAILED")
            throw ExitCode(1)
        }
        print("\nall checks passed")
    }

    // MARK: - Offline grid

    private func runOfflineGrid() throws {
        let truths = try GroundTruthStore.load(dir: beatbenchDir, filter: trackFilter())
        guard !truths.isEmpty else {
            throw ValidationError("no ground truth found — run GT.2 reconciliation first")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ValidationError("no Metal device — BeatThisModel needs a GPU")
        }
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        var rows: [BaselineRow] = []

        for truth in truths.sorted(by: { ($0.suite, $0.trackID) < ($1.suite, $1.trackID) }) {
            guard let filename = truth.audioFile else { continue }
            let url = resolvedFixturesDir().appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                FileHandle.standardError.write(Data("missing fixture: \(url.path)\n".utf8))
                continue
            }
            let (samples, rate) = try AudioDecode.monoFloat32(url: url)
            let grid = analyzer.analyzeBeatGrid(samples: samples, sampleRate: rate)

            // Ground truth may extend past the analyzer's window; score only where both
            // exist, otherwise the grid is penalised for beats it was never shown.
            let gridSpan = (grid.beats.first ?? 0, grid.beats.last ?? 0)
            let refInSpan = truth.beats.filter { $0 >= gridSpan.0 - 1 && $0 <= gridSpan.1 + 1 }
            let scores = Metrics.score(reference: refInSpan, estimate: grid.beats)
            let downbeatF = truth.downbeats.isEmpty || grid.downbeats.isEmpty
                ? nil
                : Metrics.fMeasure(reference: truth.downbeats.filter {
                    $0 >= gridSpan.0 - 1 && $0 <= gridSpan.1 + 1
                }, estimate: grid.downbeats).score

            rows.append(BaselineRow(
                trackID: truth.trackID,
                suite: truth.suite,
                status: truth.status,
                truthBPM: truth.bpm,
                gridBPM: grid.bpm,
                truthMeter: truth.meter,
                gridMeter: grid.beatsPerBar,
                scores: scores,
                downbeatF: downbeatF
            ))
            print(BaselineReport.line(for: rows[rows.count - 1]))
        }

        let text = BaselineReport.render(rows: rows)
        print("\n" + text)
        if !report.isEmpty {
            let url = URL(fileURLWithPath: report)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try BaselineReport.document(rows: rows).write(to: url, atomically: true, encoding: .utf8)
            print("→ \(report)")
        }
    }

    private func trackFilter() -> Set<String> {
        let parts = tracks.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return Set(parts.filter { !$0.isEmpty })
    }
}

// MARK: - Audio

enum AudioDecode {
    static func monoFloat32(url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { throw ValidationError("empty audio: \(url.lastPathComponent)") }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else {
            throw ValidationError("decode produced no samples: \(url.lastPathComponent)")
        }
        let count = Int(buffer.frameLength)
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
}

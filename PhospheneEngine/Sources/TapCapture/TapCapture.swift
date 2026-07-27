// TapCapture — GT.2 human-tap ground-truth capture CLI.
// STATUS: active-tool — standalone CLI (executableTarget). Zero production
//   importers BY DESIGN; not dead. See docs/AUDIT_KEEPLIST.md.
//
// Human taps are one of the two independent ground-truth sources for BeatBench
// (the other is the offline reference-tool pass); where they agree within 70 ms
// the result becomes ground truth, and disagreements go to Matt to arbitrate by
// ear. See BEAT_SYNC_PROGRAM_PLAN.md §GT.2 and the `beatbench` skill.
//
// Usage:
//   # once per sitting — measures output latency + reaction time
//   swift run TapCapture --calibrate
//
//   # then two passes per track
//   swift run TapCapture --track billie_jean --pass beats
//   swift run TapCapture --track billie_jean --pass downbeats
//
//   swift run TapCapture --status        # what is captured so far
//
// Tap with the SPACE bar; 'q' ends a pass early.

import Foundation
import ArgumentParser

@main
struct TapCaptureCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "TapCapture",
        abstract: "Record human beat/downbeat taps against a playing BeatBench fixture.",
        discussion: """
        Run --calibrate once per sitting first: a metronome plays, you tap along, and
        the median tap-minus-click offset is stored and subtracted from every later
        tap. Calibration goes through the same playback path as capture, so it
        measures the latency that actually applies.

        Then run two passes per track (--pass beats, --pass downbeats). Tap SPACE on
        each beat (or each bar's "1" for downbeats). Press q to end a pass early.
        Nothing is overwritten without --force.
        """
    )

    @Option(name: .long, help: "Track id from the BeatBench manifest (e.g. billie_jean).")
    var track: String?

    @Option(name: .long, help: "Audio file path — overrides --track lookup.")
    var audio: String?

    @Option(name: .long, help: "Annotation pass: 'beats' or 'downbeats'.")
    var pass: String = "beats"

    @Flag(name: .long, help: "Run the latency-calibration round and exit.")
    var calibrate: Bool = false

    @Flag(name: .long, help: "Print capture progress across all manifest tracks and exit.")
    var status: Bool = false

    @Flag(name: .long, help: "Validate the calibration arithmetic in-memory and exit.")
    var selfTest: Bool = false

    @Flag(name: .long, help: "Overwrite an existing capture for this track+pass.")
    var force: Bool = false

    @Option(name: .long, help: "Fixtures dir (default: $BEATBENCH_FIXTURES_DIR).")
    var fixturesDir: String?

    @Option(name: .long, help: "Stop after N seconds (0 = whole track). Useful for a dry run.")
    var limitSeconds: Double = 0

    @Option(name: .long, help: "Calibration metronome tempo.")
    var calibrateBpm: Double = 100

    @Option(name: .long, help: "Calibration duration, seconds.")
    var calibrateSeconds: Double = 25

    // MARK: - Paths

    /// Repo-relative artifact root, derived from this source file's location.
    /// #filePath is …/PhospheneEngine/Sources/TapCapture/TapCapture.swift; three
    /// deletions land on the package root (…/PhospheneEngine).
    private var beatbenchDir: URL {
        URL(fileURLWithPath: String(#filePath))
            .deletingLastPathComponent()   // → Sources/TapCapture
            .deletingLastPathComponent()   // → Sources
            .deletingLastPathComponent()   // → PhospheneEngine (package root)
            .appendingPathComponent("Tests/Fixtures/beatbench")
    }

    private var manifestURL: URL { beatbenchDir.appendingPathComponent("manifest.json") }
    private var calibrationURL: URL { beatbenchDir.appendingPathComponent("taps/calibration.json") }

    private func resolvedFixturesDir() -> URL {
        let raw = fixturesDir
            ?? ProcessInfo.processInfo.environment["BEATBENCH_FIXTURES_DIR"]
            ?? "~/phosphene_beatbench_fixtures"
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    private func tapsURL(trackID: String, pass: String) -> URL {
        beatbenchDir.appendingPathComponent("taps/\(trackID).\(pass).json")
    }

    // MARK: - Run

    func run() throws {
        if selfTest { return try runSelfTest() }
        if status { return try printStatus() }
        if calibrate { return try runCalibration() }
        try runCapture()
    }

    /// In-memory check of the arithmetic Matt's tap session depends on. If this is
    /// wrong, a 40-minute capture yields silently-skewed ground truth, so it is
    /// verified independently of the (TTY-only) interactive path.
    private func runSelfTest() throws {
        var failures: [String] = []
        func check(_ label: String, _ condition: Bool) {
            print("  \(condition ? "ok  " : "FAIL") \(label)")
            if !condition { failures.append(label) }
        }
        print("TapCapture self-test")

        // 1. Click track: 100 BPM over 10 s → clicks every 0.6 s from a 0.5 s lead-in.
        let (url, clicks) = try ClickTrack.render(bpm: 100, seconds: 10)
        defer { try? FileManager.default.removeItem(at: url) }
        check("click track renders clicks", clicks.count >= 15)
        check("first click at the 0.5 s lead-in", abs((clicks.first ?? 0) - 0.5) < 1e-9)
        let spacing = clicks.count > 1 ? clicks[1] - clicks[0] : 0
        check("click spacing == 60/BPM", abs(spacing - 0.6) < 1e-9)
        check("click file written", FileManager.default.fileExists(atPath: url.path))

        // 2. A known latency must be recovered from taps built with that latency.
        let latency = 0.082
        let taps = clicks.map { $0 + latency }
        let offsets = CalibrationMath.offsetsMs(taps: taps, clicks: clicks)
        check("every clean tap is matched", offsets.count == clicks.count)
        check("median recovers the injected 82 ms", abs(TapStats.median(offsets) - 82.0) < 0.5)

        // 3. An implausible-latency mis-tap is rejected rather than dragging the median.
        //    (0.3 s past a click is nearer that click than the next, so only the
        //    latency-band guard can catch it — a period/2 test never would.)
        let withMisTap = taps + [(clicks.first ?? 0) + 0.3]
        let guarded = CalibrationMath.offsetsMs(taps: withMisTap, clicks: clicks)
        check("mis-tap rejected", guarded.count == offsets.count)
        check("median unmoved by the mis-tap", abs(TapStats.median(guarded) - 82.0) < 0.5)

        // 4. Correction shifts onto the audio timeline and drops negatives.
        let corrected = CalibrationMath.correct(taps: [0.5, 0.05, 1.1], latencyMs: 82.0)
        check("correction drops pre-zero taps", corrected.count == 2)
        check("correction subtracts the offset", abs((corrected.first ?? 0) - 0.418) < 1e-9)
        check("correction sorts ascending", corrected == corrected.sorted())

        // 5. MAD is 0 for a perfectly steady tapper, non-zero once one tap wanders.
        check("MAD == 0 on identical offsets", TapStats.medianAbsoluteDeviation(offsets) < 1e-9)
        check("MAD > 0 on a genuinely spread set", TapStats.medianAbsoluteDeviation([60, 80, 100, 120]) > 0)

        guard failures.isEmpty else {
            print("\n\(failures.count) check(s) FAILED")
            throw ExitCode(1)
        }
        print("\nall checks passed")
    }

    private func printStatus() throws {
        let manifest = try FixtureManifest.load(at: manifestURL)
        let calibration = loadCalibration()
        print("BeatBench tap capture status")
        if let cal = calibration {
            let offset = String(format: "%.1f", cal.medianOffsetMs)
            let mad = String(format: "%.1f", cal.madMs)
            print("  calibration: \(offset) ms (MAD \(mad) ms, \(cal.tapCount) taps)")
        } else {
            print("  calibration: NONE — run --calibrate first")
        }
        var done = 0
        for entry in manifest.tracks {
            let beats = FileManager.default.fileExists(atPath: tapsURL(trackID: entry.id, pass: "beats").path)
            let downs = FileManager.default.fileExists(atPath: tapsURL(trackID: entry.id, pass: "downbeats").path)
            if beats && downs { done += 1 }
            let mark = { (ok: Bool) in ok ? "✓" : "·" }
            print("  suite \(entry.suite)  \(mark(beats)) beats  \(mark(downs)) downbeats   \(entry.id)")
        }
        print("  \(done)/\(manifest.tracks.count) tracks fully captured")
    }

    private func runCalibration() throws {
        let (url, clicks) = try ClickTrack.render(bpm: calibrateBpm, seconds: calibrateSeconds)
        let prompt = """
        CALIBRATION — tap SPACE on every click (\(Int(calibrateBpm)) BPM, \
        \(Int(calibrateSeconds))s). Starting…
        """
        let taps = try TapRecorder().record(url: url, limitSeconds: calibrateSeconds, prompt: prompt)

        let offsets = CalibrationMath.offsetsMs(taps: taps, clicks: clicks)
        guard offsets.count >= 5 else {
            print("\nOnly \(offsets.count) usable taps — need at least 5. Re-run --calibrate.")
            throw ExitCode(1)
        }

        let result = CalibrationResult(
            calibratedAt: TapArtifactWriter.timestamp(),
            bpm: calibrateBpm,
            clickCount: clicks.count,
            tapCount: offsets.count,
            medianOffsetMs: TapStats.median(offsets),
            madMs: TapStats.medianAbsoluteDeviation(offsets),
            offsetsMs: offsets
        )
        try TapArtifactWriter.write(result, to: calibrationURL)
        let offset = String(format: "%.1f", result.medianOffsetMs)
        let mad = String(format: "%.1f", result.madMs)
        print("\ncalibration: median offset \(offset) ms (MAD \(mad) ms over \(offsets.count) taps)")
        print("→ \(calibrationURL.path)")
        if result.madMs > 40 {
            print("NOTE: MAD > 40 ms — tapping was loose; consider re-running --calibrate.")
        }
    }

    private func runCapture() throws {
        guard pass == "beats" || pass == "downbeats" else {
            throw ValidationError("--pass must be 'beats' or 'downbeats'")
        }
        let (trackID, audioURL) = try resolveTrack()

        let destination = tapsURL(trackID: trackID, pass: pass)
        if FileManager.default.fileExists(atPath: destination.path) && !force {
            print("already captured: \(destination.lastPathComponent) — pass --force to redo")
            throw ExitCode(1)
        }
        guard let calibration = loadCalibration() else {
            print("no calibration found — run: swift run TapCapture --calibrate")
            throw ExitCode(1)
        }

        let what = pass == "beats" ? "every BEAT" : "each bar's DOWNBEAT (the \"1\")"
        let prompt = "\(trackID) [\(pass)] — tap SPACE on \(what). 'q' ends early. Starting…"
        let raw = try TapRecorder().record(url: audioURL, limitSeconds: limitSeconds, prompt: prompt)

        let corrected = CalibrationMath.correct(taps: raw, latencyMs: calibration.medianOffsetMs)
        guard !corrected.isEmpty else {
            print("\nno taps recorded — nothing written")
            throw ExitCode(1)
        }

        let record = TapPass(
            trackID: trackID,
            pass: pass,
            audioFile: audioURL.lastPathComponent,
            capturedAt: TapArtifactWriter.timestamp(),
            latencyOffsetMs: calibration.medianOffsetMs,
            tapCount: corrected.count,
            tapsS: corrected
        )
        try TapArtifactWriter.write(record, to: destination)

        let span = (corrected.last ?? 0) - (corrected.first ?? 0)
        let impliedBPM = span > 0 ? Double(corrected.count - 1) / span * 60.0 : 0
        let bpmStr = String(format: "%.1f", impliedBPM)
        print("\n\(corrected.count) taps over \(String(format: "%.1f", span))s — implied \(bpmStr) BPM")
        print("→ \(destination.path)")
    }

    // MARK: - Helpers

    private func resolveTrack() throws -> (id: String, url: URL) {
        if let audio {
            let url = URL(fileURLWithPath: (audio as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw TapCaptureError.fixtureMissing(url.path)
            }
            return (track ?? url.deletingPathExtension().lastPathComponent, url)
        }
        guard let track else {
            throw ValidationError("provide --track <id> (or --audio <path>); --status lists ids")
        }
        let manifest = try FixtureManifest.load(at: manifestURL)
        guard let entry = manifest.track(id: track), let filename = entry.filename else {
            throw TapCaptureError.unknownTrack(track)
        }
        let url = resolvedFixturesDir().appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TapCaptureError.fixtureMissing(url.path)
        }
        return (track, url)
    }

    private func loadCalibration() -> CalibrationResult? {
        guard let data = try? Data(contentsOf: calibrationURL) else { return nil }
        return try? JSONDecoder().decode(CalibrationResult.self, from: data)
    }
}

// ColdStartVerifier — Phase CS increment CS.1.
//
// Empirically verifies Phosphene's cold-start beat-sync bar: "beat-synced from
// frame 1 of every track" (design doc COLD_START_SYNC_DESIGN_2026-05-20.md §3).
//
// WHAT IT MEASURES
// ----------------
// For a real captured session, for the first N seconds of every track, it
// compares the *visual* beat times (`beatPhase01` wraps in features.csv) against
// the *audible* beats. The per-beat delta distribution, per-track and aggregate,
// is the CS.1 measurement.
//
// MEASUREMENT — OPTION C (design discussion 2026-05-22)
// -----------------------------------------------------
// The audible-beat reference is a one-beat-per-beat grid from Beat This! re-run
// offline on a per-track slice of raw_tap.wav. `beatBass` (the live onset
// feature) was tried first and rejected: it fires >1×/beat, which turns a per-
// beat measurement into a meaningless walking sawtooth. Beat This! is a beat
// *tracker* — exactly one beat per beat.
//
// CLOCK OFFSET
// ------------
// raw_tap.wav and features.csv are both faithful real-time clocks with a per-
// track constant offset. The offset is pinned sync-independently by pairing
// raw_tap BeatDetector onsets against features.csv `beatBass` onsets (same
// physical events, same detector, two clocks) — see ClockOffset. This carries
// no visual-vs-audible sync error, so it cannot hide a real sync error.
//
// DISPLAY-SHIFT CAVEAT
// --------------------
// `beatPhase01` bakes in `visualPhaseOffsetMs + audioOutputLatencyMs`
// (LiveBeatDriftTracker.swift:573). Pass the in-effect shift via
// `--display-shift-ms` to recover the latency-corrected calibration error; the
// report prints both. Audio-output latency itself is out of scope for Phase CS.
//
// HARNESS LOCATION (CS.1, kickoff step 2)
// ---------------------------------------
// A new sibling executable target, not an extension of PresetSessionReplay —
// cold-start sync is engine-level and needs DSP / ML / Session, which the
// preset-rubric tool does not depend on. Follows the project's per-job offline-
// runner pattern (TempoDumpRunner, BeatThisActivationDumper).
//
// USAGE
//   .build/release/ColdStartVerifier --session ~/Documents/phosphene_sessions/<dir>

import ArgumentParser
import Foundation
import Metal
import Session

@main
struct ColdStartVerifierCommand: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "ColdStartVerifier",
        abstract: "Verify Phosphene's cold-start beat-sync bar against a captured session."
    )

    @Option(name: .long, help: "Session directory (must contain features.csv + raw_tap.wav).")
    var session: String?

    @Flag(name: .long, help: "Validate the harness's measurement arithmetic in-memory and exit.")
    var selfTest: Bool = false

    @Flag(name: .long,
          help: "CS.1.y re-diagnosis: measure short-window Beat This! phase accuracy.")
    var rediagnose: Bool = false

    @Option(name: .long,
            help: "Comma-separated window lengths (seconds) for --rediagnose. Default: 3,4,5.")
    var rediagnoseWindows: String = "3,4,5"

    @Flag(name: .long,
          help: "BSAudit.2 Path A.1: within-capture Beat This! position sensitivity sweep.")
    var positionSweep: Bool = false

    @Flag(name: .long,
          help: "BSAudit.2 Path A.2: cross-capture Beat This! reproducibility (--sessions list).")
    var crossCapture: Bool = false

    @Flag(name: .long,
          help: """
                BSAudit.3.validate.1: score the % of audible beats with a visual \
                accent within ±accept-ms. Per-track verdict PASS-firing | \
                PASS-degraded | FAIL; aggregate gate 90 % of catalog.
                """)
    var accentWindowPassRate: Bool = false

    @Option(name: .long,
            help: "Acceptance half-width (ms) around each audible beat for an accent hit.")
    var acceptMs: Double = AccentWindowPassRate.defaultAcceptMs

    @Option(name: .long,
            help: "Rising-edge threshold for the (gated) `beatComposite` column.")
    var accentThreshold: Double = AccentWindowPassRate.defaultAccentThreshold

    @Option(name: .long,
            help: "Per-track PASS-firing gate (fraction of audible beats hit).")
    var perTrackPassRate: Double = AccentWindowPassRate.defaultPerTrackPassRate

    @Option(name: .long,
            help: "PASS-degraded ceiling for max accent_confidence over the window.")
    var degradedConfThreshold: Double = AccentWindowPassRate.defaultDegradedConfThreshold

    @Option(name: .long,
            help: "Comma-separated session directories for --cross-capture (first = reference).")
    var sessions: String = ""

    @Option(name: .long,
            help: "Beat This! slice length (s) for --position-sweep / --cross-capture. Default: 25.")
    var sliceDurationS: Double = 25.0

    @Option(name: .long,
            help: "Position stride (s) for --position-sweep. Default: 10.")
    var positionStrideS: Double = 10.0

    @Option(name: .long,
            help: "Position start (s) into each track for --cross-capture. Default: 0.")
    var crossCaptureStartS: Double = 0.0

    @Option(name: .long, help: "Cold-start window measured per track, seconds.")
    var firstWindowS: Double = 10.0

    @Option(name: .long,
            help: """
                Offset (s) into each track at which the measurement window starts. \
                Default 0 = measure from track start ('approx now' check). \
                Set to ~20 to measure post-snap phase ('exact by ~20 s' check).
                """)
    var windowStartS: Double = 0.0

    @Option(name: .long, help: "Pass tolerance: |delta| within this many ms counts as aligned.")
    var passWindowMs: Double = 50.0

    @Option(name: .long, help: "Aspirational tighter tolerance, ms (reported, not gated).")
    var tightWindowMs: Double = 30.0

    @Option(name: .long, help: "Per-track pass requires this fraction of beats within passWindowMs.")
    var passRate: Double = 0.90

    @Option(name: .long,
            help: "visualPhaseOffsetMs + audioOutputLatencyMs in effect during capture; 0 if engine defaults used.")
    var displayShiftMs: Double = 0.0

    @Option(name: .long, help: "Output Markdown report path. Defaults to <session>/cold_start_report.md.")
    var out: String?

    func run() throws {
        if selfTest {
            do { try SelfTest.run() } catch { throw ExitCode.failure }
            return
        }
        if crossCapture {
            try runCrossCapture()
            return
        }
        guard let session else {
            throw ValidationError("--session is required (or pass --self-test).")
        }
        let loaded = try loadSingleSession(path: session)

        if rediagnose {
            try runReDiagnosis(
                sessionURL: loaded.url,
                artifacts: loaded.artifacts,
                rawTap: loaded.rawTap,
                analyzer: loaded.analyzer)
            return
        }
        if positionSweep {
            try runPositionSweep(
                sessionURL: loaded.url,
                artifacts: loaded.artifacts,
                rawTap: loaded.rawTap,
                analyzer: loaded.analyzer)
            return
        }
        if accentWindowPassRate {
            try runAccentWindowPassRate(
                sessionURL: loaded.url,
                artifacts: loaded.artifacts,
                rawTap: loaded.rawTap,
                analyzer: loaded.analyzer)
            return
        }
        let config = VerifierConfig(
            firstWindowS: firstWindowS,
            windowStartS: windowStartS,
            passWindowMs: passWindowMs,
            tightWindowMs: tightWindowMs,
            passRate: passRate,
            displayShiftMs: displayShiftMs)
        try runVerification(
            sessionURL: loaded.url,
            config: config,
            artifacts: loaded.artifacts,
            rawTap: loaded.rawTap,
            analyzer: loaded.analyzer)
    }

    /// Bundle returned by `loadSingleSession` so per-mode runners receive a
    /// fully-prepared environment.
    struct LoadedSession {
        let url: URL
        let artifacts: SessionArtifacts
        let rawTap: RawTapAnalysis
        let analyzer: DefaultBeatGridAnalyzer
    }

    /// Decode + analyze one session's raw_tap, parse its features.csv / log,
    /// and instantiate the Beat This! analyzer. Shared by --rediagnose,
    /// --position-sweep, and the verification path.
    func loadSingleSession(path: String) throws -> LoadedSession {
        let sessionURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        print("ColdStartVerifier: loading session \(sessionURL.path)")
        let artifacts = try SessionArtifacts.load(directory: sessionURL)
        print("ColdStartVerifier: \(artifacts.frames.count) frames, "
            + "\(artifacts.tracks.count) track segment(s)")
        let rawTapURL = sessionURL.appendingPathComponent("raw_tap.wav")
        guard FileManager.default.fileExists(atPath: rawTapURL.path) else {
            throw VerifierError.missingRawTap(rawTapURL)
        }
        print("ColdStartVerifier: decoding raw_tap.wav + detecting sub-bass onsets")
        let rawTap = try RawTapAnalysis.analyze(url: rawTapURL)
        print("ColdStartVerifier: raw_tap \(rawTap.durationS.rounded())s @ "
            + "\(Int(rawTap.sampleRate)) Hz, \(rawTap.onsets.count) onsets")
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw VerifierError.noMetalDevice
        }
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        return LoadedSession(
            url: sessionURL,
            artifacts: artifacts,
            rawTap: rawTap,
            analyzer: analyzer)
    }

    /// The CS.1 cold-start verification path. Extracted from `run()` to keep
    /// that function under the function-body length gate.
    private func runVerification(
        sessionURL: URL,
        config: VerifierConfig,
        artifacts: SessionArtifacts,
        rawTap: RawTapAnalysis,
        analyzer: DefaultBeatGridAnalyzer
    ) throws {
        print("ColdStartVerifier: running Beat This! per track …")
        let analysis = ColdStartAnalysis.run(
            tracks: artifacts.tracks,
            config: config,
            rawTap: rawTap,
            rawTapStartWallclockS: artifacts.rawTapStartWallclockS,
            analyzer: analyzer)

        let report = VerifierReport.render(
            sessionURL: sessionURL,
            artifacts: artifacts,
            rawTap: rawTap,
            analysis: analysis,
            config: config)
        let outURL = out.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? sessionURL.appendingPathComponent("cold_start_report.md")
        try report.write(to: outURL, atomically: true, encoding: .utf8)

        print("")
        print(analysis.consoleSummary(config: config))
        print("ColdStartVerifier: report → \(outURL.path)")
    }

    /// CS.1.y re-diagnosis: short-window Beat This! phase accuracy. Extracted
    /// from `run()` to keep that function under the function-body length gate.
    private func runReDiagnosis(
        sessionURL: URL,
        artifacts: SessionArtifacts,
        rawTap: RawTapAnalysis,
        analyzer: DefaultBeatGridAnalyzer
    ) throws {
        let windows = try parseRediagnoseWindows()
        let windowList = windows.map { String(format: "%.0f", $0) }.joined(separator: "/")
        print("ColdStartVerifier: re-diagnosis — Beat This! phase accuracy (\(windowList) s) …")
        let rediag = ReDiagnosis.run(
            tracks: artifacts.tracks,
            rawTap: rawTap,
            rawTapStartWallclockS: artifacts.rawTapStartWallclockS,
            analyzer: analyzer,
            windows: windows)
        let md = ReDiagnosis.report(session: sessionURL, rawTap: rawTap, results: rediag)
        let rediagOut = out.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        } ?? sessionURL.appendingPathComponent("cold_start_rediagnosis.md")
        try md.write(to: rediagOut, atomically: true, encoding: .utf8)
        print("")
        print(ReDiagnosis.consoleSummary(rediag))
        print("ColdStartVerifier: re-diagnosis report → \(rediagOut.path)")
    }

    /// Parse `--rediagnose-windows` into a sorted list of positive window
    /// lengths (seconds). Throws a ValidationError on malformed input.
    private func parseRediagnoseWindows() throws -> [Double] {
        let parsed = rediagnoseWindows
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 }
            .sorted()
        guard !parsed.isEmpty else {
            throw ValidationError(
                "--rediagnose-windows must be a comma-separated list of positive numbers.")
        }
        return parsed
    }
}

/// Thresholds + measurement configuration for a verification run.
struct VerifierConfig {
    let firstWindowS: Double
    /// Offset (s) into each track at which the measurement window starts.
    /// 0 = measure from track start ("approx now" check). ~20 = measure
    /// post-snap (CS.1.y.2-redo "exact by ~20 s" check).
    let windowStartS: Double
    let passWindowMs: Double
    let tightWindowMs: Double
    let passRate: Double
    let displayShiftMs: Double
}

enum VerifierError: Error, CustomStringConvertible {
    case missingFile(URL)
    case missingRawTap(URL)
    case missingColumn(String)
    case emptyFeatures
    case rawTapDecodeFailed(String)
    case noMetalDevice

    var description: String {
        switch self {
        case .missingFile(let url):
            return "Required file not found: \(url.path)"
        case .missingRawTap(let url):
            return "raw_tap.wav not found at \(url.path). The session must be captured "
                + "with PHOSPHENE_FULL_RAW_TAP=1 so raw_tap.wav covers every track."
        case .missingColumn(let name):
            return "features.csv is missing the required column '\(name)' — the session "
                + "predates the beat-sync CSV schema."
        case .emptyFeatures:
            return "features.csv has a header but no frame rows — the session recorded "
                + "no playback."
        case .rawTapDecodeFailed(let detail):
            return "raw_tap.wav could not be decoded: \(detail)"
        case .noMetalDevice:
            return "no Metal device available — Beat This! inference requires Metal."
        }
    }
}

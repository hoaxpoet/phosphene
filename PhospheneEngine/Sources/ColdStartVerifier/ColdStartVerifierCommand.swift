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

    @Option(name: .long, help: "Cold-start window measured per track, seconds.")
    var firstWindowS: Double = 10.0

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
            do {
                try SelfTest.run()
            } catch {
                throw ExitCode.failure
            }
            return
        }
        guard let session else {
            throw ValidationError("--session is required (or pass --self-test).")
        }
        let sessionURL = URL(fileURLWithPath: (session as NSString).expandingTildeInPath)
        let config = VerifierConfig(
            firstWindowS: firstWindowS,
            passWindowMs: passWindowMs,
            tightWindowMs: tightWindowMs,
            passRate: passRate,
            displayShiftMs: displayShiftMs)

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
}

/// Thresholds + measurement configuration for a verification run.
struct VerifierConfig {
    let firstWindowS: Double
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

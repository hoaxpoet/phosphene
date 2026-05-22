// ColdStartVerifier — Phase CS increment CS.1.
//
// Empirically verifies Phosphene's cold-start beat-sync bar: "beat-synced from
// frame 1 of every track" (design doc COLD_START_SYNC_DESIGN_2026-05-20.md §3).
//
// WHAT IT MEASURES
// ----------------
// For a real captured session, for the first N seconds of every track, it
// compares the *visual* beat times (when `beatPhase01` wraps in features.csv)
// against the *audible* beat times (sub-bass onsets re-detected offline from
// raw_tap.wav). The per-beat delta distribution, per-track and aggregate, is
// the CS.1 measurement.
//
// HARNESS-LOCATION DECISION (CS.1, kickoff step 2)
// ------------------------------------------------
// This is a NEW sibling executable target, NOT an extension of PresetSessionReplay
// (which the design doc §7.1 floated as a candidate base). Rationale:
//   • CS.1 ground truth requires re-running `BeatDetector` (and, as a follow-up,
//     Beat This!) on raw_tap.wav — i.e. it needs the `DSP` (and `ML`) modules.
//     `PresetSessionReplay` depends only on `Shared` + `Presets`; adding DSP/ML
//     to a preset-rubric tool is scope creep.
//   • Cold-start sync is engine-level and preset-agnostic. PresetSessionReplay's
//     architecture (per-preset routes + image-processing rubric proxies) does
//     not fit a beat-phase measurement.
//   • The project already establishes the pattern of small, single-purpose
//     offline runner targets: `TempoDumpRunner` (Audio+DSP), `BeatThisActivation-
//     Dumper` (DSP+ML). CS.1 fits that pattern exactly.
//
// GROUND-TRUTH DECISION (CS.1, kickoff step 3)
// --------------------------------------------
// Primary ground truth: re-run `BeatDetector` on raw_tap.wav offline — the same
// sub-bass onset detector `GridOnsetCalibrator` and the live `LiveBeatDriftTracker`
// match against. Independent of the live AGC state, frame cadence, and dropped
// frames. Beat This! offline cross-check is a CS.1 follow-up (`--beat-this`,
// not yet implemented) — the BeatDetector path is a complete primary measurement.
//
// CLOCK ALIGNMENT
// ---------------
// features.csv and raw_tap.wav are written by the same SessionRecorder but in
// independent clocks (features.csv `wallclock_s` / per-track `playback_time_s`;
// raw_tap.wav in tap-sample-time). They ARE the same audio, so a low-frequency
// energy-envelope cross-correlation recovers the true per-track offset — a
// measurement-tool alignment of a known-real relationship, not a fudge.
//
// DISPLAY-SHIFT CAVEAT
// --------------------
// `beatPhase01` is computed from `pt + drift + (visualPhaseOffsetMs +
// audioOutputLatencyMs)` (LiveBeatDriftTracker.swift:573). raw_tap.wav is
// tap-time. The raw per-beat delta therefore carries `−displayShift`. Pass the
// in-effect shift via `--display-shift-ms` to recover the latency-corrected
// calibration error; the report prints both. Audio-output-latency itself is
// out of scope for Phase CS (design doc §6.13).
//
// USAGE
//   .build/release/ColdStartVerifier --session ~/Documents/phosphene_sessions/<dir>

import ArgumentParser
import Foundation

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
            displayShiftMs: displayShiftMs
        )

        print("ColdStartVerifier: loading session \(sessionURL.path)")
        let artifacts = try SessionArtifacts.load(directory: sessionURL)
        print("ColdStartVerifier: \(artifacts.frames.count) frames, "
            + "\(artifacts.tracks.count) track segment(s)")

        let rawTapURL = sessionURL.appendingPathComponent("raw_tap.wav")
        guard FileManager.default.fileExists(atPath: rawTapURL.path) else {
            throw VerifierError.missingRawTap(rawTapURL)
        }
        print("ColdStartVerifier: analysing raw_tap.wav (offline BeatDetector ground truth)")
        let rawTap = try RawTapAnalysis.analyze(url: rawTapURL)
        print("ColdStartVerifier: raw_tap \(rawTap.durationS.rounded())s @ "
            + "\(Int(rawTap.sampleRate)) Hz, \(rawTap.onsets.count) sub-bass onsets")

        let analysis = ColdStartAnalysis.run(
            tracks: artifacts.tracks, rawTap: rawTap, config: config)

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
        }
    }
}

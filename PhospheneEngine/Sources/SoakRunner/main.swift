// SoakRunner — CLI entry point for headless soak test runs (Increment 7.1).
//
// Usage:
//   .build/release/SoakRunner --duration 7200
//   .build/release/SoakRunner --duration 300 --audio-file /path/to/loop.wav
//   .build/release/SoakRunner --help
//
// For App Nap prevention during long runs, wrap with caffeinate:
//   caffeinate -i .build/release/SoakRunner --duration 7200
// See Scripts/run_soak_test.sh which does this automatically. D-060(d).

import Foundation
import ArgumentParser
import Audio
import Diagnostics

// MARK: - Command

@main
struct SoakRunnerCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "SoakRunner",
        abstract: "Run a headless Phosphene soak test.",
        discussion: """
        Drives AudioInputRouter with a looping audio file for the specified duration,
        sampling memory + frame timing periodically. Writes JSON + Markdown report to
        ~/Documents/phosphene_soak/<timestamp>/.

        For a full 2-hour run with App Nap prevention:
            caffeinate -i .build/release/SoakRunner --duration 7200
        """
    )

    @Option(name: .long, help: "Run duration in seconds (default: 7200).")
    var duration: Double = 7200

    @Option(name: .long, help: "Sample interval in seconds (default: 60).")
    var sampleInterval: Double = 60

    @Option(name: .long, help: "Path to audio file to loop. Omit for procedural generation.")
    var audioFile: String?

    @Option(name: .long, help: "Report output directory (default: ~/Documents/phosphene_soak).")
    var reportDir: String?

    @MainActor
    func run() async throws {
        guard #available(macOS 14.2, *) else {
            print("SoakRunner requires macOS 14.2 or later.")
            throw ExitCode(1)
        }

        print("SoakRunner: duration=\(Int(duration))s sampleInterval=\(Int(sampleInterval))s")

        let baseDir: URL = reportDir.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/phosphene_soak")

        // Resolve audio file.
        let resolvedAudio: URL?
        if let path = audioFile {
            resolvedAudio = URL(fileURLWithPath: path)
            print("SoakRunner: using audio file: \(path)")
        } else {
            print("SoakRunner: generating procedural audio fixture...")
            resolvedAudio = try SoakTestHarness.generateSyntheticAudioFile()
            print("SoakRunner: audio fixture ready")
        }

        let config = SoakTestHarness.Configuration(
            duration: duration,
            sampleInterval: sampleInterval,
            reportBaseDirectory: baseDir
        )

        let router = AudioInputRouter()
        let harness = SoakTestHarness(configuration: config, audioInputRouter: router)

        print("SoakRunner: run starting...")
        let report = try await harness.run(audioFile: resolvedAudio)

        printSummary(report)

        if report.finalAssessment == .hardFailure {
            throw ExitCode(1)
        }
    }

    @available(macOS 14.2, *)
    @MainActor
    private func printSummary(_ report: SoakTestHarness.Report) {
        let dur = String(format: "%.1f", report.actualDuration)
        print("\n=== SoakRunner Complete ===")
        print("  Duration:    \(dur)s")
        print("  Assessment:  \(report.finalAssessment.rawValue)")
        print("  Snapshots:   \(report.snapshots.count)")
        print("  Signals:     \(report.signalTransitions.count) transitions")
        print("  ML force:    \(report.mlForceDispatches)")
        if !report.alerts.isEmpty {
            print("  Alerts:")
            report.alerts.forEach { print("    ⚠ \($0)") }
        }
        print("==========================")
    }
}

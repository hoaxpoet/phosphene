// SoakTestHarnessTests — Tests for SoakTestHarness (Increment 7.1).
//
// Always-run tests: Configuration defaults, Codable round-trip.
// Soak-tagged tests: gated by SOAK_TESTS=1 environment variable.
//   - 60-second smoke test: verifies report is written, no hard failures.
//   - 5-minute memory check: observes memory growth (no assertion, observability only).
//
// To run soak tests:
//   SOAK_TESTS=1 swift test --package-path PhospheneEngine --filter SoakTestHarnessTests
//
// D-060(d): the 2-hour run is NOT in this suite. Use Scripts/run_soak_test.sh.

import Testing
import Foundation
import QuartzCore
import Audio
@testable import Diagnostics

// MARK: - Always-run Tests

@Suite("SoakTestHarness")
struct SoakTestHarnessTests {

    // MARK: Configuration Defaults

    @Test("Configuration defaults are sensible")
    func configurationDefaults() {
        guard #available(macOS 14.2, *) else { return }
        let config = SoakTestHarness.Configuration()
        #expect(config.duration == 7200,
                "Default duration should be 7200 s (2 hours)")
        #expect(config.sampleInterval == 60,
                "Default sample interval should be 60 s")
        #expect(config.memoryGrowthAlertBytes == 50 * 1024 * 1024,
                "Default memory growth alert should be 50 MB")
        #expect(config.droppedFramesPerHourAlertCount == 60,
                "Default dropped-frame alert threshold should be 60/h")
    }

    // MARK: Report Codable Round-trip

    @Test("Report round-trips through JSON Codable")
    func reportCodableRoundTrip() throws {
        guard #available(macOS 14.2, *) else { return }
        let original = SoakTestHarness.Report(
            configuration: .init(
                duration: 300,
                sampleInterval: 30,
                memoryGrowthAlertBytes: 50 * 1024 * 1024,
                droppedFramesPerHourAlertCount: 60
            ),
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_000_300),
            actualDuration: 300,
            snapshots: [
                .init(
                    elapsedSeconds: 30,
                    residentBytes: 100 * 1024 * 1024,
                    purgeableBytes: 0,
                    cumulativeP50Ms: 15.5,
                    cumulativeP95Ms: 18.0,
                    cumulativeP99Ms: 24.0,
                    cumulativeMaxMs: 31.0,
                    cumulativeDroppedFrames: 0,
                    recentP50Ms: 15.5,
                    recentP95Ms: 17.5,
                    recentMaxMs: 20.0,
                    recentDroppedFrames: 0,
                    qualityLevel: "full"
                )
            ],
            signalTransitions: [
                .init(elapsedSeconds: 0.5, state: "active")
            ],
            qualityLevelTransitions: [],
            mlForceDispatches: 0,
            alerts: [],
            finalAssessment: .pass
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SoakTestHarness.Report.self, from: data)

        #expect(decoded.actualDuration == original.actualDuration)
        #expect(decoded.snapshots.count == original.snapshots.count)
        #expect(decoded.snapshots.first?.cumulativeP50Ms == original.snapshots.first?.cumulativeP50Ms)
        #expect(decoded.finalAssessment == original.finalAssessment)
        #expect(decoded.signalTransitions.first?.state == original.signalTransitions.first?.state)
        #expect(decoded.mlForceDispatches == original.mlForceDispatches)
    }

    // MARK: Assessment Enum Values

    @Test("Assessment has correct raw values")
    func assessmentRawValues() {
        guard #available(macOS 14.2, *) else { return }
        #expect(SoakTestHarness.Report.Assessment.pass.rawValue == "pass")
        #expect(SoakTestHarness.Report.Assessment.passWithSoftAlerts.rawValue == "passWithSoftAlerts")
        #expect(SoakTestHarness.Report.Assessment.hardFailure.rawValue == "hardFailure")
    }
}

// MARK: - Cancel (always-run)

extension SoakTestHarnessTests {

    @Test("cancel() causes run() to return before duration expires")
    @MainActor
    func cancelCausesEarlyReturn() async throws {
        guard #available(macOS 14.2, *) else { return }

        let config = SoakTestHarness.Configuration(
            duration: 3600,
            sampleInterval: 30,
            reportBaseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("phosphene_soak_cancel_\(Int(Date().timeIntervalSince1970))")
        )

        let router = AudioInputRouter()
        let harness = SoakTestHarness(configuration: config, audioInputRouter: router)

        // Run in background task; cancel almost immediately.
        let runTask = Task { @MainActor [harness] in
            try await harness.run(audioFile: nil)
        }

        // Give it half a second to initialise, then cancel.
        try await Task.sleep(for: .milliseconds(500))
        harness.cancel()

        let report = try await runTask.value
        #expect(report.actualDuration < config.duration,
                "actualDuration (\(report.actualDuration)s) should be < configured duration (\(config.duration)s)")
        #expect(report.actualDuration < 5.0,
                "Should have returned within ~5 s of cancel()")
    }
}

// MARK: - Soak-tagged Tests (SOAK_TESTS=1 required)

@Suite("SoakTestHarness (soak)")
struct SoakTestHarnessSoakTests {

    // MARK: 60-second Smoke Run

    @Test("60-second smoke run: report written, no hard failure")
    @MainActor
    func smokeSoakRun() async throws {
        guard ProcessInfo.processInfo.environment["SOAK_TESTS"] == "1" else { return }
        guard #available(macOS 14.2, *) else { return }

        let reportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphene_soak_smoke_\(Int(Date().timeIntervalSince1970))")

        let config = SoakTestHarness.Configuration(
            duration: 60,
            sampleInterval: 10,
            reportBaseDirectory: reportDir
        )

        let router = AudioInputRouter()
        let harness = SoakTestHarness(configuration: config, audioInputRouter: router)
        let report = try await harness.run(audioFile: nil)

        let alertsStr = report.alerts.joined(separator: "; ")
        #expect(report.finalAssessment.rawValue != "hardFailure",
                "Smoke run should not produce a hard failure. Alerts: \(alertsStr)")
        #expect(report.snapshots.count >= 4,
                "Expected ≥ 4 periodic snapshots, got \(report.snapshots.count)")

        // JSON report must be on disk.
        let soakDirs = (try? FileManager.default.contentsOfDirectory(
            at: reportDir, includingPropertiesForKeys: nil)) ?? []
        let allJSON = soakDirs.flatMap { dir in
            (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        }.filter { $0.lastPathComponent == "report.json" }
        #expect(!allJSON.isEmpty, "report.json should be written to disk")

        printSmokeSummary(report, label: "60s smoke")
    }

    // MARK: 5-minute Memory Check

    @Test("5-minute run: memory growth observed (no threshold assertion)")
    @MainActor
    func fiveMinuteMemoryCheck() async throws {
        guard ProcessInfo.processInfo.environment["SOAK_TESTS"] == "1" else { return }
        guard #available(macOS 14.2, *) else { return }

        let reportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphene_soak_5min_\(Int(Date().timeIntervalSince1970))")

        let config = SoakTestHarness.Configuration(
            duration: 300,
            sampleInterval: 30,
            memoryGrowthAlertBytes: 500 * 1024 * 1024,  // observability only, not a hard gate
            reportBaseDirectory: reportDir
        )

        let router = AudioInputRouter()
        let harness = SoakTestHarness(configuration: config, audioInputRouter: router)
        let report = try await harness.run(audioFile: nil)

        let alertsStr = report.alerts.joined(separator: "; ")
        #expect(report.finalAssessment.rawValue != "hardFailure",
                "5-minute run should not produce a hard failure. Alerts: \(alertsStr)")

        printSmokeSummary(report, label: "5min memory")
    }

    // MARK: Helpers

    @available(macOS 14.2, *)
    private nonisolated func printSmokeSummary(_ report: SoakTestHarness.Report, label: String) {
        let dur = String(format: "%.1f", report.actualDuration)
        let snap = report.snapshots.last
        let finalMem = snap.map { "\($0.residentBytes / (1024 * 1024)) MB" } ?? "n/a"
        let p50 = snap.map { String(format: "%.1f", $0.cumulativeP50Ms) } ?? "n/a"
        let p95 = snap.map { String(format: "%.1f", $0.cumulativeP95Ms) } ?? "n/a"
        let p99 = snap.map { String(format: "%.1f", $0.cumulativeP99Ms) } ?? "n/a"
        let drops = snap.map { "\($0.cumulativeDroppedFrames)" } ?? "n/a"
        print("""
        ┌─ SoakSmoke [\(label)] ─────────────────
        │ duration=\(dur)s  assessment=\(report.finalAssessment.rawValue)
        │ memory=\(finalMem)
        │ P50=\(p50)ms  P95=\(p95)ms  P99=\(p99)ms  dropped=\(drops)
        │ signals=\(report.signalTransitions.count)  mlForce=\(report.mlForceDispatches)
        └─────────────────────────────────────
        """)
    }
}

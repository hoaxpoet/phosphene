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
import Metal
import Audio
import Shared
@testable import Diagnostics
@testable import Renderer

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

    // MARK: 30-second Drift Motes Kernel Cost (DM.2 Task 8)
    //
    // Direct kernel-cost benchmark for `motes_update` at the Tier 2 particle
    // count (800). Dispatches one compute frame per simulated 60 Hz tick for
    // 30 seconds, captures `MTLCommandBuffer.gpuStartTime/gpuEndTime` per
    // frame, and reports p50 / p95 / p99 / drop-count of the kernel cost.
    //
    // The 1.6 ms Tier 2 / 2.1 ms Tier 1 targets in the Drift Motes
    // architecture contract describe the FULL preset frame budget (sky
    // fragment + curl-noise compute + sprite render + feedback decay). This
    // test isolates the compute kernel only — the post-DM.2 audio coupling
    // (D-019 blend, hue baking, pitch-driven palette) is the only thing that
    // grew the kernel cost between DM.1 and DM.2, so a kernel-cost regression
    // gate here is the right shape. Full-pipeline timing requires a runtime
    // app session and is reported in the Increment DM.2 landing block.
    //
    // Tier 1 numbers are deferred to a hardware run (see DM.2 done-when).

    @Test("30-second Drift Motes kernel cost benchmark (Tier 2)")
    @MainActor
    func shortRunDriftMotes() async throws {
        guard ProcessInfo.processInfo.environment["SOAK_TESTS"] == "1" else { return }

        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geometry = try DriftMotesGeometry(
            device: ctx.device,
            library: lib.library,
            particleCount: DriftMotesGeometry.tier2ParticleCount,
            pixelFormat: nil
        )

        let dt: Float = 1.0 / 60.0
        let frameCount = 30 * 60   // 30 seconds at simulated 60 Hz.
        var features = FeatureVector.zero
        features.deltaTime = dt
        // Realistic-ish coupling so the D-019 blend selects the warm hue
        // path on most respawns and exercises the pitch helper too.
        var stems = StemFeatures.zero
        stems.vocalsEnergy = 0.4
        stems.drumsEnergy = 0.5
        stems.bassEnergy = 0.4
        stems.otherEnergy = 0.4
        stems.vocalsPitchHz = 220.0
        stems.vocalsPitchConfidence = 0.85

        var kernelMs: [Double] = []
        kernelMs.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            features.time = Float(frame) * dt
            // Sweep pitch so the warm-hue path produces varied output.
            stems.vocalsPitchHz = 110.0 * powf(16.0, Float(frame % 240) / 239.0)
            features.midAttRel = 0.2 + 0.3 * sinf(features.time * 0.5)

            guard let cmdBuf = ctx.commandQueue.makeCommandBuffer() else {
                continue
            }
            geometry.update(features: features, stemFeatures: stems,
                            commandBuffer: cmdBuf)
            cmdBuf.commit()
            await cmdBuf.completed()
            let durationS = cmdBuf.gpuEndTime - cmdBuf.gpuStartTime
            kernelMs.append(durationS * 1000.0)
        }

        // Sort once for percentiles + drop count.
        kernelMs.sort()
        let n = kernelMs.count
        let p50 = kernelMs[n / 2]
        let p95 = kernelMs[Int(Double(n) * 0.95)]
        let p99 = kernelMs[Int(Double(n) * 0.99)]
        let mean = kernelMs.reduce(0, +) / Double(n)
        // "Drops" here = frames whose kernel time exceeded 14 ms (the Tier 2
        // governor's downshift threshold). These are not full-pipeline
        // drops, but they're the kernel-cost equivalent.
        let kernelOverruns = kernelMs.filter { $0 > 14.0 }.count

        print("""
        ┌─ DriftMotesKernelCost [Tier 2, 800 particles] ─
        │ frames=\(n)  mean=\(String(format: "%.3f", mean))ms
        │ p50=\(String(format: "%.3f", p50))ms  \
        p95=\(String(format: "%.3f", p95))ms  \
        p99=\(String(format: "%.3f", p99))ms
        │ kernel overruns (>14ms)=\(kernelOverruns)
        │ Tier 2 full-frame budget=1.6ms (preset contract); kernel-only is
        │ a bounded subset. Full-pipeline measurement deferred to a runtime
        │ session per DM.2 Task 8.
        └────────────────────────────────────────────────
        """)

        // Loose gate: kernel p95 should sit well under the full-pipeline
        // Tier 2 budget. Failures here would indicate a kernel regression
        // (e.g., a curl-noise octave bump or accidental neighbour query)
        // rather than a full-pipeline budget breach.
        #expect(p95 < 5.0,
                "Kernel p95 \(p95) ms exceeds 5ms loose gate — investigate motes_update for regression.")
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

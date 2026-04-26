// SoakTestHarness+Reporting — JSON + Markdown report writing (Increment 7.1).

import Foundation
import os.log

@available(macOS 14.2, *)
extension SoakTestHarness {

    // MARK: - Report Building

    @MainActor
    func buildReport(
        configuration: Configuration,
        startedAt: Date,
        finishedAt: Date,
        actualDuration: TimeInterval,
        baselineMemory: MemorySnapshot?
    ) -> Report {
        var alerts: [String] = []

        // Memory growth.
        if let baseline = baselineMemory, let finalSnap = snapshots.last {
            let growth = finalSnap.residentBytes > baseline.residentBytes
                ? finalSnap.residentBytes - baseline.residentBytes : 0
            if growth > configuration.memoryGrowthAlertBytes {
                let mb = growth / (1024 * 1024)
                let threshold = configuration.memoryGrowthAlertBytes / (1024 * 1024)
                alerts.append("Memory grew \(mb) MB from baseline (threshold: \(threshold) MB)")
            }
        }

        // Dropped frames per hour.
        let finalTiming = frameTimingReporter.snapshot()
        if actualDuration > 0 {
            let dropsPerHour = UInt64(
                Double(finalTiming.cumulativeDroppedFrames) / actualDuration * 3600
            )
            if dropsPerHour > configuration.droppedFramesPerHourAlertCount {
                let dropThreshold = configuration.droppedFramesPerHourAlertCount
                alerts.append("Dropped frames: \(dropsPerHour)/h (threshold: \(dropThreshold)/h)")
            }
        }

        // Quality downshifts (transitions away from "full").
        let qualityOrder = ["full", "no-SSGI", "no-bloom", "step-0.75", "particles-0.5", "mesh-0.5"]
        let downshifts = qualityTransitions.filter { transition in
            let fromIdx = qualityOrder.firstIndex(of: transition.from) ?? 0
            let toIdx   = qualityOrder.firstIndex(of: transition.to) ?? 0
            return toIdx > fromIdx
        }.count
        if downshifts > 3 {
            alerts.append("Quality governor downshifted \(downshifts) times")
        }

        // ML force dispatches per hour.
        let forceDispatches = UInt32(mlScheduler?.forceDispatchCount ?? 0)
        if actualDuration > 0 {
            let fdPerHour = Double(forceDispatches) / actualDuration * 3600
            if fdPerHour > 10 {
                alerts.append("ML force-dispatches: \(String(format: "%.1f", fdPerHour))/h (threshold: 10/h)")
            }
        }

        // Hard failure: MemoryReporter nil too many times.
        var hardFailure = false
        if memorySnapshotFailures > 5 {
            alerts.append("HARD FAILURE: MemoryReporter returned nil \(memorySnapshotFailures) times")
            hardFailure = true
        }

        let assessment: Report.Assessment = hardFailure
            ? .hardFailure : (alerts.isEmpty ? .pass : .passWithSoftAlerts)

        return Report(
            configuration: .init(
                duration: configuration.duration,
                sampleInterval: configuration.sampleInterval,
                memoryGrowthAlertBytes: configuration.memoryGrowthAlertBytes,
                droppedFramesPerHourAlertCount: configuration.droppedFramesPerHourAlertCount
            ),
            startedAt: startedAt,
            finishedAt: finishedAt,
            actualDuration: actualDuration,
            snapshots: snapshots,
            signalTransitions: signalTransitions,
            qualityLevelTransitions: qualityTransitions,
            mlForceDispatches: forceDispatches,
            alerts: alerts,
            finalAssessment: assessment
        )
    }

    // MARK: - Report Writing

    func writeReport(_ report: Report, startedAt: Date) throws {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = isoFormatter.string(from: startedAt)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        let dir = configuration.reportBaseDirectory.appendingPathComponent(timestamp)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(report)
        try jsonData.write(to: dir.appendingPathComponent("report.json"))

        let md = buildMarkdownSummary(report)
        try md.data(using: .utf8)?.write(to: dir.appendingPathComponent("report.md"))

        logger.info("Soak: report written to \(dir.path)")
    }

    // MARK: - Markdown Summary

    func buildMarkdownSummary(_ report: Report) -> String {
        let dur = String(format: "%.1f", report.actualDuration)
        let lastSnap = report.snapshots.last
        let timing = frameTimingReporter.snapshot()

        var lines = [
            "# Phosphene Soak Test Report",
            "",
            "**Assessment:** \(report.finalAssessment.rawValue)",
            "**Duration:** \(dur)s  ",
            "**Started:** \(report.startedAt)  ",
            "**Snapshots:** \(report.snapshots.count)",
            "",
            "## Memory",
        ]

        if let snap = lastSnap {
            let mb = snap.residentBytes / (1024 * 1024)
            let purgMb = snap.purgeableBytes / (1024 * 1024)
            lines += ["Final resident: **\(mb) MB** (purgeable: \(purgMb) MB)"]
        }

        lines += [
            "",
            "## Frame Timing",
            "P50: \(String(format: "%.1f", timing.cumulativeP50Ms)) ms  ",
            "P95: \(String(format: "%.1f", timing.cumulativeP95Ms)) ms  ",
            "P99: \(String(format: "%.1f", timing.cumulativeP99Ms)) ms  ",
            "Max: \(String(format: "%.1f", timing.cumulativeMaxMs)) ms  ",
            "Dropped frames: \(timing.cumulativeDroppedFrames)",
            "",
            "## Transitions",
            "Signal: \(report.signalTransitions.count)  ",
            "Quality: \(report.qualityLevelTransitions.count)  ",
            "ML force dispatches: \(report.mlForceDispatches)",
        ]

        if !report.alerts.isEmpty {
            lines += ["", "## Alerts"]
            lines += report.alerts.map { "- ⚠️ \($0)" }
        }

        return lines.joined(separator: "\n")
    }
}

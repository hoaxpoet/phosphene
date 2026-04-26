// SoakTestHarness — Headless long-running engine exercise harness (Increment 7.1).
//
// Drives audio through AudioInputRouter (localFile mode) for a configurable duration,
// sampling memory + frame timing periodically and observing state/signal transitions.
// At the end, writes a JSON report + Markdown summary to disk.
//
// Soak tests are NOT run in the default `swift test` invocation. The 60-second and
// 5-minute smoke tests in SoakTestHarnessTests.swift are gated by SOAK_TESTS=1 env var.
// D-060(d): 2-hour runs are CLI-only via SoakRunner / run_soak_test.sh.
//
// Design: no SessionManager, no Metal render pipeline required. The harness targets
// the audio + MIR + memory path — the heaviest steady-state load. A caller with a
// RenderPipeline can wire `onFrameTimingObserved` for GPU frame metrics.

import Foundation
import QuartzCore
import os.log
import Audio
import Renderer
import Shared

let logger = Logger(subsystem: "com.phosphene.diagnostics", category: "SoakTestHarness")

// MARK: - SoakTestHarness

/// Headless soak test orchestrator.
///
/// Usage:
/// ```swift
/// let harness = SoakTestHarness(
///     configuration: .init(duration: 60),
///     audioInputRouter: router
/// )
/// // Optionally wire frame timing from a RenderPipeline:
/// renderPipeline.onFrameTimingObserved = harness.frameTimingRecorder
/// let report = try await harness.run()
/// ```
@available(macOS 14.2, *)
@MainActor
public final class SoakTestHarness {

    // MARK: - Configuration

    public struct Configuration: Sendable, Codable {
        /// Total run duration in seconds. Default 7200 (2 h). D-060(d).
        public var duration: TimeInterval
        /// How often to take a periodic snapshot. Default 60 s.
        public var sampleInterval: TimeInterval
        /// Soft-alert threshold: resident memory growth from baseline. Default 50 MB.
        public var memoryGrowthAlertBytes: UInt64
        /// Soft-alert threshold: dropped frames per hour. Default 60.
        public var droppedFramesPerHourAlertCount: UInt64
        /// Directory for report output. Defaults to `~/Documents/phosphene_soak/`.
        public var reportBaseDirectory: URL

        public init(
            duration: TimeInterval = 7200,
            sampleInterval: TimeInterval = 60,
            memoryGrowthAlertBytes: UInt64 = 50 * 1024 * 1024,
            droppedFramesPerHourAlertCount: UInt64 = 60,
            reportBaseDirectory: URL? = nil
        ) {
            self.duration = duration
            self.sampleInterval = sampleInterval
            self.memoryGrowthAlertBytes = memoryGrowthAlertBytes
            self.droppedFramesPerHourAlertCount = droppedFramesPerHourAlertCount
            let defaultDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/phosphene_soak")
            self.reportBaseDirectory = reportBaseDirectory ?? defaultDir
        }
    }

    // MARK: - Report

    public struct Report: Sendable, Codable {

        public struct ReportConfig: Sendable, Codable {
            public let duration: TimeInterval
            public let sampleInterval: TimeInterval
            public let memoryGrowthAlertBytes: UInt64
            public let droppedFramesPerHourAlertCount: UInt64
        }

        public struct PeriodicSnapshot: Sendable, Codable {
            public let elapsedSeconds: TimeInterval
            public let residentBytes: UInt64
            public let purgeableBytes: UInt64
            public let cumulativeP50Ms: Float
            public let cumulativeP95Ms: Float
            public let cumulativeP99Ms: Float
            public let cumulativeMaxMs: Float
            public let cumulativeDroppedFrames: UInt64
            public let recentP50Ms: Float
            public let recentP95Ms: Float
            public let recentMaxMs: Float
            public let recentDroppedFrames: UInt32
            public let qualityLevel: String
        }

        public struct SignalTransition: Sendable, Codable {
            public let elapsedSeconds: TimeInterval
            public let state: String
        }

        public struct QualityTransition: Sendable, Codable {
            public let elapsedSeconds: TimeInterval
            public let from: String
            public let to: String
        }

        public enum Assessment: String, Sendable, Codable {
            case pass
            case passWithSoftAlerts
            case hardFailure
        }

        public let configuration: ReportConfig
        public let startedAt: Date
        public let finishedAt: Date
        public let actualDuration: TimeInterval
        public let snapshots: [PeriodicSnapshot]
        public let signalTransitions: [SignalTransition]
        public let qualityLevelTransitions: [QualityTransition]
        public let mlForceDispatches: UInt32
        public let alerts: [String]
        public let finalAssessment: Assessment
    }

    // MARK: - State

    public let configuration: Configuration
    let audioInputRouter: AudioInputRouter
    let frameBudgetManager: FrameBudgetManager?
    let mlScheduler: MLDispatchScheduler?

    /// Exposed so the caller can wire: `renderPipeline.onFrameTimingObserved = harness.frameTimingRecorder`
    public let frameTimingReporter: FrameTimingReporter

    var cancelled = false

    // Mutable soak state — only accessed on @MainActor.
    var snapshots: [Report.PeriodicSnapshot] = []
    var signalTransitions: [Report.SignalTransition] = []
    var qualityTransitions: [Report.QualityTransition] = []
    var memorySnapshotFailures = 0
    var lastQualityLevel: String = "full"
    var runStartTime: TimeInterval = 0

    // MARK: - Init

    public init(
        configuration: Configuration = .init(),
        audioInputRouter: AudioInputRouter,
        frameBudgetManager: FrameBudgetManager? = nil,
        mlScheduler: MLDispatchScheduler? = nil
    ) {
        self.configuration = configuration
        self.audioInputRouter = audioInputRouter
        self.frameBudgetManager = frameBudgetManager
        self.mlScheduler = mlScheduler
        self.frameTimingReporter = FrameTimingReporter()
    }

    // MARK: - Cancel

    /// Signal the running `run()` to stop early and return a report.
    public func cancel() {
        cancelled = true
    }

    // MARK: - Run

    /// Execute the soak run. Blocks the caller for approximately `configuration.duration`
    /// seconds (or until `cancel()` is called), then writes a report and returns it.
    ///
    /// - Parameter audioFile: URL to a local audio file to loop during the run.
    ///   Pass `nil` to auto-generate a 10-second procedural fixture (sine sweep + noise).
    public func run(audioFile: URL? = nil) async throws -> Report {
        cancelled = false
        snapshots = []
        signalTransitions = []
        qualityTransitions = []
        memorySnapshotFailures = 0
        lastQualityLevel = frameBudgetManager?.currentLevel.displayName ?? "n/a"
        frameTimingReporter.reset()
        runStartTime = CACurrentMediaTime()
        let startDate = Date()

        let baselineMemory = MemoryReporter.snapshot()

        // Resolve audio file (generate procedurally if not provided).
        let audioURL: URL
        if let provided = audioFile {
            audioURL = provided
        } else {
            audioURL = try Self.generateSyntheticAudioFile()
        }

        // Observe audio signal transitions (callback from audio thread → hop to MainActor).
        audioInputRouter.onSignalStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.recordSignalTransition(state)
            }
        }

        // Start audio.
        try audioInputRouter.start(mode: .localFile(audioURL))
        logger.info("Soak: audio started, duration=\(Int(self.configuration.duration))s")

        // Periodic sampling task.
        let samplingTask = Task { @MainActor [weak self] in
            while let self, !self.cancelled {
                try? await Task.sleep(for: .seconds(self.configuration.sampleInterval))
                guard !Task.isCancelled, !self.cancelled else { break }
                self.takeSample()
            }
        }

        // Wait for duration or cancellation.
        var cancelledEarly = false
        do {
            var remaining = configuration.duration
            // Poll in 0.25s increments so cancel() is noticed quickly without busy-waiting.
            while remaining > 0 && !cancelled {
                let slice = min(remaining, 0.25)
                try await Task.sleep(for: .seconds(slice))
                remaining -= slice
            }
            if cancelled { cancelledEarly = true }
        } catch {
            cancelledEarly = true
        }

        samplingTask.cancel()
        audioInputRouter.stop()

        let finishDate = Date()
        let actualDuration = CACurrentMediaTime() - runStartTime

        logger.info("Soak: run finished. duration=\(String(format: "%.1f", actualDuration))s cancelled=\(cancelledEarly)")

        let report = buildReport(
            configuration: configuration,
            startedAt: startDate,
            finishedAt: finishDate,
            actualDuration: actualDuration,
            baselineMemory: baselineMemory
        )

        do {
            try writeReport(report, startedAt: startDate)
        } catch {
            logger.error("Soak: failed to write report: \(error.localizedDescription)")
        }

        return report
    }

    // MARK: - Frame Timing Recorder

    /// Closure to wire into `RenderPipeline.onFrameTimingObserved`.
    ///
    /// The returned closure feeds timings into the harness's `FrameTimingReporter`.
    public var frameTimingRecorder: (_ cpuMs: Float, _ gpuMs: Float?) -> Void {
        { [reporter = frameTimingReporter] cpu, gpu in
            reporter.record(cpuFrameMs: cpu, gpuFrameMs: gpu)
        }
    }

    // MARK: - Private Helpers

    @MainActor
    private func recordSignalTransition(_ state: AudioSignalState) {
        let elapsed = CACurrentMediaTime() - runStartTime
        signalTransitions.append(.init(elapsedSeconds: elapsed, state: state.displayName))
    }

    @MainActor
    private func takeSample() {
        let elapsed = CACurrentMediaTime() - runStartTime
        let memSnap = MemoryReporter.snapshot()
        if memSnap == nil { memorySnapshotFailures += 1 }

        let timingSnap = frameTimingReporter.snapshot()
        let currentQuality = frameBudgetManager?.currentLevel.displayName ?? "n/a"

        if currentQuality != lastQualityLevel {
            qualityTransitions.append(.init(
                elapsedSeconds: elapsed,
                from: lastQualityLevel,
                to: currentQuality
            ))
            lastQualityLevel = currentQuality
        }

        snapshots.append(.init(
            elapsedSeconds: elapsed,
            residentBytes: memSnap?.residentBytes ?? 0,
            purgeableBytes: memSnap?.purgeableBytes ?? 0,
            cumulativeP50Ms: timingSnap.cumulativeP50Ms,
            cumulativeP95Ms: timingSnap.cumulativeP95Ms,
            cumulativeP99Ms: timingSnap.cumulativeP99Ms,
            cumulativeMaxMs: timingSnap.cumulativeMaxMs,
            cumulativeDroppedFrames: timingSnap.cumulativeDroppedFrames,
            recentP50Ms: timingSnap.recentP50Ms,
            recentP95Ms: timingSnap.recentP95Ms,
            recentMaxMs: timingSnap.recentMaxMs,
            recentDroppedFrames: timingSnap.recentDroppedFrames,
            qualityLevel: currentQuality
        ))
    }
}

// MARK: - AudioSignalState display name

private extension AudioSignalState {
    var displayName: String {
        switch self {
        case .active: return "active"
        case .suspect: return "suspect"
        case .silent: return "silent"
        case .recovering: return "recovering"
        }
    }
}

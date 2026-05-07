// VisualizerEngine+Dashboard — Dashboard snapshot publisher (DASH.7).
//
// Replaces the DASH.6 Metal composer path. Each rendered frame the engine
// assembles a `DashboardSnapshot` (BeatSync + Stems + Perf) and writes it to
// `@Published var dashboardSnapshot`. SwiftUI subscribers (the dashboard
// overlay view model) throttle the stream to ~30 Hz before redrawing.

import Combine
import Foundation
import Renderer
import Shared

extension VisualizerEngine {

    /// Publish a fresh `DashboardSnapshot` from the latest engine state.
    /// Called from the per-frame `onFrameRendered` hook on `@MainActor`.
    @MainActor
    func publishDashboardSnapshot(stems: StemFeatures) {
        let beat = beatSyncLock.withLock { latestBeatSyncSnapshot }
        let perf = assemblePerfSnapshot(pipeline: pipeline)
        dashboardSnapshot = DashboardSnapshot(beat: beat, stems: stems, perf: perf)
    }

    /// Build a `PerfSnapshot` from the current `FrameBudgetManager` +
    /// `MLDispatchScheduler` state. Pure read — no side effects.
    @MainActor
    func assemblePerfSnapshot(pipeline pipe: RenderPipeline) -> PerfSnapshot {
        let mgr = pipe.frameBudgetManager
        let level = mgr?.currentLevel ?? .full
        let recentMs = mgr?.recentMaxFrameMs ?? 0
        let observed = mgr?.recentFramesObserved ?? 0
        let target = mgr?.configuration.targetFrameMs ?? 14
        let (mlCode, deferMs): (Int, Float) = {
            switch self.mlDispatchScheduler?.lastDecision {
            case .none:                          return (0, 0)
            case .dispatchNow:                   return (1, 0)
            case .defer(let ms):                 return (2, ms)
            case .forceDispatch:                 return (3, 0)
            }
        }()
        return PerfSnapshot(
            recentMaxFrameMs: recentMs,
            recentFramesObserved: observed,
            targetFrameMs: target,
            qualityLevelRawValue: level.rawValue,
            qualityLevelDisplayName: level.displayName,
            mlDecisionCode: mlCode,
            mlDeferRetryMs: deferMs
        )
    }
}

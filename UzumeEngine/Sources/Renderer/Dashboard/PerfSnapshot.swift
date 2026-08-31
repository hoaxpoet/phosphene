// PerfSnapshot — Sendable per-frame snapshot of renderer governor + ML
// dispatch state, used as the single input to `PerfCardBuilder` (DASH.5).
//
// Assembled at the call site (typically RenderPipeline / VisualizerEngine)
// from `FrameBudgetManager` and `MLDispatchScheduler`. Pure value type — no
// references to either manager. Decision/quality enums are encoded as Int +
// display string so the snapshot stays trivially `Sendable` without
// importing the manager enums (mirrors `BeatSyncSnapshot.sessionMode`,
// D-085).

import Foundation

/// Sendable per-frame snapshot of renderer governor + ML dispatch state.
public struct PerfSnapshot: Sendable, Equatable {

    /// Maximum frame time over the recent rolling window (ms).
    public var recentMaxFrameMs: Float

    /// Number of frames that have populated the rolling window so far. 0 when
    /// the manager has not yet observed any frame — FRAME row renders "—" and
    /// the bar at 0 in that case.
    public var recentFramesObserved: Int

    /// Per-tier frame budget target (ms). Used as the FRAME bar's upper
    /// bound; typical 14 ms (Tier 1) or 16 ms (Tier 2).
    public var targetFrameMs: Float

    /// Current quality level rawValue (0=full ... 5=reducedMesh). rawValue
    /// used (not the enum) so `PerfSnapshot` does not pull in
    /// `FrameBudgetManager.QualityLevel` and the snapshot stays trivially
    /// `Sendable`.
    public var qualityLevelRawValue: Int

    /// Display string for the quality level (`QualityLevel.displayName`).
    /// Caller passes through; builder does not re-derive.
    public var qualityLevelDisplayName: String

    /// ML dispatch decision encoding:
    ///   0 = no decision yet (`lastDecision == nil`)
    ///   1 = dispatchNow
    ///   2 = defer
    ///   3 = forceDispatch
    public var mlDecisionCode: Int

    /// When `mlDecisionCode == 2` (.defer), the retry-in delay in
    /// milliseconds. Zero otherwise.
    public var mlDeferRetryMs: Float

    public init(
        recentMaxFrameMs: Float,
        recentFramesObserved: Int,
        targetFrameMs: Float,
        qualityLevelRawValue: Int,
        qualityLevelDisplayName: String,
        mlDecisionCode: Int,
        mlDeferRetryMs: Float
    ) {
        self.recentMaxFrameMs = recentMaxFrameMs
        self.recentFramesObserved = recentFramesObserved
        self.targetFrameMs = targetFrameMs
        self.qualityLevelRawValue = qualityLevelRawValue
        self.qualityLevelDisplayName = qualityLevelDisplayName
        self.mlDecisionCode = mlDecisionCode
        self.mlDeferRetryMs = mlDeferRetryMs
    }

    /// Neutral snapshot — no observations, full quality, no ML decision yet.
    /// Used by tests and as a startup default.
    public static let zero = PerfSnapshot(
        recentMaxFrameMs: 0,
        recentFramesObserved: 0,
        targetFrameMs: 14.0,
        qualityLevelRawValue: 0,
        qualityLevelDisplayName: "full",
        mlDecisionCode: 0,
        mlDeferRetryMs: 0
    )
}

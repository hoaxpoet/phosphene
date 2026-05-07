// PerfCardBuilder — Maps a `PerfSnapshot` to a `DashboardCardLayout` for
// the PERF card (DASH.5 → DASH.7).
//
// Pure function: no Metal, no allocations beyond the resulting layout.
// Safe to call every frame.
//
// Display contract (DASH.7 — supersedes DASH.5):
//   FRAME   — always present. valueText shows "{recent} / {target} ms"
//             so the budget headroom is legible at a glance. Bar fill
//             ratio is clamped to [0, 1] (single source of truth — the
//             `.progressBar` row variant has no range field, asymmetric
//             with STEMS where the renderer clamps).
//             Status colour: muted (no obs yet) / green (ratio < 0.7) /
//             yellow (ratio ≥ 0.7).
//   QUALITY — present ONLY when the governor has downshifted (level > 0)
//             OR no observations have arrived yet. When the renderer is at
//             `full` and warmed up, this row is omitted entirely so the
//             card stays at a clean two-row "all healthy" surface.
//   ML      — present ONLY when the dispatch scheduler is in a non-quiet
//             state (defer or forceDispatch). Idle / dispatchNow omit the
//             row — those are the steady-state happy paths.
//
// Two design rules carry forward from DASH.5:
//   • No `statusRed` token introduced (D-085 Decision 6). Over-budget reads
//     as `statusYellow`; the governor downshifting is the correct response.
//   • Per-row palette uniform `coral` for the bar fill (D-085 Decision 7).
//     Status colour lives on value-text only.

import CoreGraphics
import Shared

#if canImport(AppKit)
import AppKit
#endif

/// Maps a `PerfSnapshot` to a `DashboardCardLayout` for the PERF card.
public struct PerfCardBuilder: Sendable {

    /// Frame-time ratio above which FRAME flips from green → yellow.
    /// Empirically a comfortable headroom above the per-tier budget.
    public static let warningRatio: Float = 0.70

    public init() {}

    public func build(
        from snapshot: PerfSnapshot,
        width: CGFloat = 280
    ) -> DashboardCardLayout {
        var rows: [DashboardCardLayout.Row] = [makeFrameRow(snapshot)]
        if let qualityRow = makeQualityRow(snapshot) {
            rows.append(qualityRow)
        }
        if let mlRow = makeMLRow(snapshot) {
            rows.append(mlRow)
        }
        return DashboardCardLayout(
            title: "PERF",
            rows: rows,
            width: width
        )
    }

    // MARK: - Row makers

    private func makeFrameRow(_ snapshot: PerfSnapshot) -> DashboardCardLayout.Row {
        let observed = snapshot.recentFramesObserved > 0
        let target = max(snapshot.targetFrameMs, 0.0001)
        let rawRatio = snapshot.recentMaxFrameMs / target
        let ratio = clamp01(rawRatio)
        let color: NSColor
        let valueText: String
        if !observed {
            color = DashboardTokens.Color.textMuted
            valueText = "—"
        } else {
            color = rawRatio < Self.warningRatio
                ? DashboardTokens.Color.statusGreen
                : DashboardTokens.Color.statusYellow
            valueText = String(format: "%.1f / %.0f ms", snapshot.recentMaxFrameMs, snapshot.targetFrameMs)
        }
        return .progressBar(
            label: "FRAME",
            value: observed ? ratio : 0,
            valueText: valueText,
            fillColor: color
        )
    }

    private func makeQualityRow(_ snapshot: PerfSnapshot) -> DashboardCardLayout.Row? {
        // Hide when the governor is fully healthy.
        if snapshot.recentFramesObserved > 0 && snapshot.qualityLevelRawValue == 0 {
            return nil
        }
        let color: NSColor = snapshot.recentFramesObserved == 0
            ? DashboardTokens.Color.textMuted
            : DashboardTokens.Color.statusYellow
        return .singleValue(
            label: "QUALITY",
            value: snapshot.qualityLevelDisplayName,
            valueColor: color
        )
    }

    private func makeMLRow(_ snapshot: PerfSnapshot) -> DashboardCardLayout.Row? {
        // Hide on idle (0) and dispatchNow / READY (1) — the happy paths.
        // Surface only when the scheduler is deferring or has force-dispatched.
        switch snapshot.mlDecisionCode {
        case 2:
            let value = snapshot.mlDeferRetryMs == 0
                ? "WAIT"
                : String(format: "WAIT %.0fms", snapshot.mlDeferRetryMs)
            return .singleValue(
                label: "ML",
                value: value,
                valueColor: DashboardTokens.Color.statusYellow
            )
        case 3:
            return .singleValue(
                label: "ML",
                value: "FORCED",
                valueColor: DashboardTokens.Color.statusYellow
            )
        default:
            return nil
        }
    }

    private func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }
}

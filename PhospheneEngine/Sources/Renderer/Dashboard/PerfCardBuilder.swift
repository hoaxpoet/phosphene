// PerfCardBuilder — Maps a `PerfSnapshot` to a `DashboardCardLayout` for
// the PERF card (DASH.5).
//
// Pure function: no Metal, no allocations beyond the resulting layout.
// Safe to call every frame. Wiring into `RenderPipeline` / `PlaybackView`
// is DASH.6 scope, not DASH.5.
//
// Three rows in display order: FRAME / QUALITY / ML.
//
// Status-colour discipline (mirrors BEAT lock-state mapping, D-083 / D-085):
//   muted  = no information yet
//   green  = healthy / READY
//   yellow = governor active / degraded / WAIT / FORCED
//
// FRAME bar value is clamped at the builder layer because `.progressBar`
// has no `range` field — the row variant cannot defend itself the way
// `.bar` (D-084 STEMS) can. Single source of truth for the clamp lives
// here. Test (e) regression-locks this asymmetry.

import CoreGraphics
import Shared

#if canImport(AppKit)
import AppKit
#endif

/// Maps a `PerfSnapshot` to a `DashboardCardLayout` for the PERF card.
public struct PerfCardBuilder: Sendable {

    public init() {}

    public func build(
        from snapshot: PerfSnapshot,
        width: CGFloat = 280
    ) -> DashboardCardLayout {
        let frameRow = makeFrameRow(snapshot)
        let qualityRow = makeQualityRow(snapshot)
        let mlRow = makeMLRow(snapshot)

        return DashboardCardLayout(
            title: "PERF",
            rows: [frameRow, qualityRow, mlRow],
            width: width
        )
    }

    // MARK: - Row makers

    private func makeFrameRow(_ snapshot: PerfSnapshot) -> DashboardCardLayout.Row {
        let observed = snapshot.recentFramesObserved > 0
        let target = max(snapshot.targetFrameMs, 0.0001)
        let ratio = clamp01(snapshot.recentMaxFrameMs / target)
        let valueText: String
        if observed {
            valueText = String(format: "%.1f ms", snapshot.recentMaxFrameMs)
        } else {
            valueText = "—"
        }
        return .progressBar(
            label: "FRAME",
            value: observed ? ratio : 0,
            valueText: valueText,
            fillColor: DashboardTokens.Color.coral
        )
    }

    private func makeQualityRow(_ snapshot: PerfSnapshot) -> DashboardCardLayout.Row {
        let color: NSColor
        if snapshot.recentFramesObserved == 0 {
            color = DashboardTokens.Color.textMuted
        } else if snapshot.qualityLevelRawValue == 0 {
            color = DashboardTokens.Color.statusGreen
        } else {
            color = DashboardTokens.Color.statusYellow
        }
        return .singleValue(
            label: "QUALITY",
            value: snapshot.qualityLevelDisplayName,
            valueColor: color
        )
    }

    private func makeMLRow(_ snapshot: PerfSnapshot) -> DashboardCardLayout.Row {
        let value: String
        let color: NSColor
        switch snapshot.mlDecisionCode {
        case 1:
            value = "READY"
            color = DashboardTokens.Color.statusGreen
        case 2:
            if snapshot.mlDeferRetryMs == 0 {
                value = "WAIT"
            } else {
                value = String(format: "WAIT %.0fms", snapshot.mlDeferRetryMs)
            }
            color = DashboardTokens.Color.statusYellow
        case 3:
            value = "FORCED"
            color = DashboardTokens.Color.statusYellow
        default:
            value = "—"
            color = DashboardTokens.Color.textMuted
        }
        return .singleValue(label: "ML", value: value, valueColor: color)
    }

    private func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }
}

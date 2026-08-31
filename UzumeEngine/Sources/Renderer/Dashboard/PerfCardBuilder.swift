// PerfCardBuilder — Maps a `PerfSnapshot` to a `DashboardCardLayout` for
// the PERF card.
//
// Pure function: no Metal, no allocations beyond the resulting layout.
// Safe to call every frame.
//
// Display contract (DASH.7 + DASH.7.1):
//   FRAME   — always present. valueText shows "{recent} / {target} ms"
//             so the budget headroom is legible at a glance. Status
//             colour: textMuted (no obs yet) / teal (data healthy) /
//             coralMuted (data stressed — nearing budget).
//   QUALITY — present ONLY when the governor has downshifted (level > 0)
//             OR no observations have arrived yet. When the renderer is at
//             `full` and warmed up, this row is omitted entirely.
//   ML      — present ONLY when the dispatch scheduler is in a non-quiet
//             state (defer or forceDispatch). Idle / dispatchNow omit the
//             row.
//
// DASH.7.1 brand-alignment: the foreign `statusGreen` / `statusYellow`
// tokens used in DASH.5-7 are replaced with `teal` / `coral` so the
// PERF card uses only the project's three brand colours (purple / coral /
// teal). See D-088 for the rationale — the alarm-coloured palette
// conflicted with the .impeccable.md "color carries meaning, never
// decorate" principle.
//
// DASH.7.2 (D-089): `coralMuted` (oklch 0.45) failed WCAG AA at 2.6:1
// against the dark dashboard surface. Promoted to full `coral` (oklch
// 0.70, 7.8:1 — AAA) so warning states stay legible on dark.

import CoreGraphics
import Shared

#if canImport(AppKit)
import AppKit
#endif

/// Maps a `PerfSnapshot` to a `DashboardCardLayout` for the PERF card.
public struct PerfCardBuilder: Sendable {

    /// Frame-time ratio above which FRAME flips from `teal` (healthy) →
    /// `coral` (stressed). Empirically a comfortable headroom above the
    /// per-tier budget.
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
                ? DashboardTokens.Color.teal
                : DashboardTokens.Color.coral
            valueText = String(format: "%.1f / %.0fms", snapshot.recentMaxFrameMs, snapshot.targetFrameMs)
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
            : DashboardTokens.Color.coral
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
                valueColor: DashboardTokens.Color.coral
            )
        case 3:
            return .singleValue(
                label: "ML",
                value: "FORCED",
                valueColor: DashboardTokens.Color.coral
            )
        default:
            return nil
        }
    }

    private func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }
}

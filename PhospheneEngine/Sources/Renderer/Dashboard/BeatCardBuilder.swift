// BeatCardBuilder — Maps a `BeatSyncSnapshot` to a `DashboardCardLayout`
// for the BEAT card (DASH.3).
//
// Pure function: no Metal, no allocations beyond the resulting layout.
// Safe to call every frame. Wiring into `RenderPipeline` / `PlaybackView`
// is DASH.6 scope, not DASH.3.
//
// Row order (per .impeccable.md Beat-panel feedback): MODE / BPM / BAR / BEAT.
//
// Lock-state colour mapping (.impeccable Color section):
//   sessionMode=0 → REACTIVE — `textMuted` (no signal yet)
//   sessionMode=1 → UNLOCKED — `textMuted` (grid present, drift unbounded)
//   sessionMode=2 → LOCKING  — `statusYellow` (acquiring)
//   sessionMode=3 → LOCKED   — `statusGreen` (precision/data signal arrived)
//
// No-grid policy: when `gridBPM <= 0`, BPM and BEAT/BAR value text show `—`
// placeholders and bar fills sit at zero. The absence of a grid is a stable
// visual state — no "loading" or "—.—" or other transient strings.
//
// `BeatSyncSnapshot` does not carry a `beatPhase01` field (full plumbing is
// a separate, future increment). DASH.3 derives an approximation:
//   `beat_phase01 ≈ fract(barPhase01 × beatsPerBar)`
// expressed as `barPhase01 × beatsPerBar − (beatInBar − 1)` and clamped to
// [0, 1] before passing to the row variant. Exact when `beatInBar` and
// `beatsPerBar` are integer-aligned; close enough for visual feedback when
// they aren't (DASH.6 will visually verify against a live cached BeatGrid).

import CoreGraphics
import Shared

#if canImport(AppKit)
import AppKit
#endif

/// Maps a `BeatSyncSnapshot` to a `DashboardCardLayout` for the BEAT card.
public struct BeatCardBuilder: Sendable {

    public init() {}

    public func build(
        from snapshot: BeatSyncSnapshot,
        width: CGFloat = 280
    ) -> DashboardCardLayout {
        let hasGrid = snapshot.gridBPM > 0
        let beatsPerBar = max(snapshot.beatsPerBar, 1)

        let modeRow = makeModeRow(sessionMode: snapshot.sessionMode)
        let bpmRow = makeBPMRow(gridBPM: snapshot.gridBPM)
        let barRow = makeBarRow(
            hasGrid: hasGrid,
            barPhase01: snapshot.barPhase01,
            beatInBar: snapshot.beatInBar,
            beatsPerBar: beatsPerBar
        )
        let beatRow = makeBeatRow(
            hasGrid: hasGrid,
            barPhase01: snapshot.barPhase01,
            beatInBar: snapshot.beatInBar,
            beatsPerBar: beatsPerBar
        )

        return DashboardCardLayout(
            title: "BEAT",
            rows: [modeRow, bpmRow, barRow, beatRow],
            width: width
        )
    }

    // MARK: - Row makers

    private func makeModeRow(sessionMode: Int) -> DashboardCardLayout.Row {
        // Status colours mapped onto the brand palette and tuned for AA-grade
        // legibility on the dark dashboard surface (DASH.7.2, D-089):
        //   REACTIVE / UNLOCKED → textBody  (real status — must be readable; muted fails AA on dark)
        //   LOCKING             → coral     (system warming — full coral reads at 7.8:1 on dark)
        //   LOCKED              → teal      (data locked in — 8.2:1 on dark, AAA)
        // The DASH.7.1 `coralMuted` (oklch 0.45) failed WCAG AA at 2.6:1 against
        // the dark surface; promoting to full `coral` (0.70) restores legibility
        // without changing brand semantics.
        let value: String
        let color: NSColor
        switch sessionMode {
        case 1:  value = "UNLOCKED"; color = DashboardTokens.Color.textBody
        case 2:  value = "LOCKING";  color = DashboardTokens.Color.coral
        case 3:  value = "LOCKED";   color = DashboardTokens.Color.teal
        default: value = "REACTIVE"; color = DashboardTokens.Color.textBody
        }
        return .singleValue(label: "MODE", value: value, valueColor: color)
    }

    private func makeBPMRow(gridBPM: Float) -> DashboardCardLayout.Row {
        if gridBPM <= 0 {
            return .singleValue(
                label: "BPM",
                value: "—",
                valueColor: DashboardTokens.Color.textMuted
            )
        }
        return .singleValue(
            label: "BPM",
            value: String(format: "%.0f", gridBPM),
            valueColor: DashboardTokens.Color.textHeading
        )
    }

    private func makeBarRow(
        hasGrid: Bool,
        barPhase01: Float,
        beatInBar: Int,
        beatsPerBar: Int
    ) -> DashboardCardLayout.Row {
        // BAR fill uses full `purple` (DASH.7.2, D-089) — `purpleGlow` (oklch
        // 0.35) failed the WCAG 3:1 non-text floor at ~2.5:1 against the dark
        // surface. Full `purple` (oklch 0.62) gives ~4.5:1, brand-aligned for
        // "ambient presence / depth" — phrase-level position.
        if !hasGrid {
            return .progressBar(
                label: "BAR",
                value: 0,
                valueText: "— / 4",
                fillColor: DashboardTokens.Color.purple
            )
        }
        return .progressBar(
            label: "BAR",
            value: clamp01(barPhase01),
            valueText: "\(beatInBar) / \(beatsPerBar)",
            fillColor: DashboardTokens.Color.purple
        )
    }

    private func makeBeatRow(
        hasGrid: Bool,
        barPhase01: Float,
        beatInBar: Int,
        beatsPerBar: Int
    ) -> DashboardCardLayout.Row {
        if !hasGrid {
            return .progressBar(
                label: "BEAT",
                value: 0,
                valueText: "—",
                fillColor: DashboardTokens.Color.coral
            )
        }
        let derived = barPhase01 * Float(beatsPerBar) - Float(beatInBar - 1)
        return .progressBar(
            label: "BEAT",
            value: clamp01(derived),
            valueText: "\(beatInBar)",
            fillColor: DashboardTokens.Color.coral
        )
    }

    private func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }
}

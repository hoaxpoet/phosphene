// DashboardCardLayout — Pure value description of one Telemetry card.
//
// Cards are the unit of visual identity for the dashboard. A `DashboardCardLayout`
// is intentionally rigid: fixed width, fixed row heights, no flex. The dashboard
// reads as a set of identical instruments — composition lives at the layout level
// (which cards exist, in what order), not inside any individual card.
//
// Rendering lives in `DashboardCardRenderer`. Layouts stay pure data so cards are
// describable from tests without a Metal device.

import CoreGraphics
import Shared

#if canImport(AppKit)
import AppKit
#endif

// MARK: - DashboardCardLayout

/// Describes one card's structure: title + ordered rows + fixed width.
public struct DashboardCardLayout: Sendable {

    /// Visible card title. Visual UPPERCASE is a convention applied at the
    /// call site — the source string flows through unchanged so tests can
    /// read it back.
    public let title: String
    public let rows: [Row]
    /// Fixed card width in points. Cards do not flex.
    public let width: CGFloat
    /// Inset for content (default `Spacing.md` = 12).
    public let padding: CGFloat
    /// Title point size (default `TypeScale.label` = 11).
    public let titleSize: CGFloat
    /// Vertical gap between rows (default `Spacing.xs` = 4). Also applied
    /// once between the title and the first row.
    public let rowSpacing: CGFloat

    public init(
        title: String,
        rows: [Row],
        width: CGFloat,
        padding: CGFloat = DashboardTokens.Spacing.md,
        titleSize: CGFloat = DashboardTokens.TypeScale.label,
        rowSpacing: CGFloat = DashboardTokens.Spacing.xs
    ) {
        self.title = title
        self.rows = rows
        self.width = width
        self.padding = padding
        self.titleSize = titleSize
        self.rowSpacing = rowSpacing
    }

    /// Total card height. `padding + title + (rowSpacing + rowHeight) × N + padding`.
    public var height: CGFloat {
        let rowsTotal = rows.reduce(CGFloat(0)) { $0 + rowSpacing + $1.height }
        return padding + titleSize + rowsTotal + padding
    }

    // MARK: - Row

    /// Vertical gap between a stacked row's label (top) and value (bottom).
    public static let labelToValueGap: CGFloat = 4

    public enum Row: Sendable {
        /// Stacked: UPPERCASE 11 pt label on top, larger numeric value below.
        /// `"BPM" \n "125"`
        case singleValue(label: String, value: String, valueColor: NSColor)
        /// Stacked: UPPERCASE 11 pt label on top, then a bar with right-aligned
        /// value text on the same line below. Bar fill is signed slice from
        /// centre — negative left, positive right — clamped to `range`.
        case bar(
            label: String, value: Float, valueText: String,
            fillColor: NSColor, range: ClosedRange<Float>
        )

        // Fixed row heights — encoded as static constants so future edits
        // surface as test failures (see `layoutHeight_matchesSumOfRows`).
        // Stacked rows: 11 pt label + 4 pt gap + (numeric 24 / bar+value 17).
        public static let singleHeight: CGFloat = 11 + labelToValueGap + 24    // = 39
        public static let barHeight: CGFloat    = 11 + labelToValueGap + 17    // = 32

        public var height: CGFloat {
            switch self {
            case .singleValue: return Row.singleHeight
            case .bar:         return Row.barHeight
            }
        }
    }
}

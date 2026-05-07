// DashboardCardRenderer+ProgressBar — `.progressBar` row helpers (DASH.3).
//
// Geometry mirrors `drawBarRow` exactly — same 56 pt right column, same 8 pt
// gap, same 6 pt bar height, same 1 pt corner radius. Only the fill geometry
// differs: a left-anchored strip from `barLeft` to
// `barLeft + clamp(value, 0, 1) × barWidth`. Kept as a separate helper rather
// than collapsing into a `signed:` Boolean parameter on `drawBarFill` because
// "fill from centre vs. fill from left" is more legible as two helpers than
// as one Boolean-branched function.
//
// Lives in its own file to keep `DashboardCardRenderer.swift` under the 400-
// line / 300-body SwiftLint gates as more row variants land in DASH.4 / DASH.5.

import CoreGraphics
import Shared

#if canImport(AppKit)
import AppKit
#endif

extension DashboardCardRenderer {

    // swiftlint:disable function_parameter_count
    internal func drawProgressBarRow(
        label: String,
        value: Float,
        valueText: String,
        fillColor: NSColor,
        rowTopY: CGFloat,
        leftX: CGFloat,
        rightX: CGFloat,
        on textLayer: DashboardTextLayer,
        cgContext: CGContext
    ) {
        textLayer.drawText(
            label,
            at: CGPoint(x: leftX, y: rowTopY),
            size: DashboardTokens.TypeScale.label,
            weight: .medium,
            font: .prose,
            color: DashboardTokens.Color.textBody,
            tracking: DashboardTokens.TypeScale.labelTracking
        )

        let valueColumnWidth: CGFloat = 56
        let valueColumnGap: CGFloat = 8
        let barRightLimit = rightX - valueColumnWidth - valueColumnGap
        let barAreaWidth = barRightLimit - leftX
        let barHeight: CGFloat = 6
        let barAreaY = rowTopY + DashboardTokens.TypeScale.label
            + DashboardCardLayout.labelToValueGap
        let barY = barAreaY + ((17 - barHeight) / 2)
        let barRect = CGRect(x: leftX, y: barY, width: barAreaWidth, height: barHeight)
        let cornerRadius: CGFloat = 1

        drawBarChrome(
            barRect: barRect,
            cornerRadius: cornerRadius,
            cgContext: cgContext
        )
        drawProgressBarFill(
            value: value,
            fillColor: fillColor,
            barLeft: leftX,
            barWidth: barAreaWidth,
            barY: barY,
            barHeight: barHeight,
            cgContext: cgContext
        )

        textLayer.drawText(
            valueText,
            at: CGPoint(x: rightX, y: barAreaY),
            size: DashboardTokens.TypeScale.body,
            weight: .regular,
            font: .mono,
            color: fillColor,
            align: .right
        )
    }
    // swiftlint:enable function_parameter_count

    // swiftlint:disable:next function_parameter_count
    private func drawProgressBarFill(
        value: Float,
        fillColor: NSColor,
        barLeft: CGFloat,
        barWidth: CGFloat,
        barY: CGFloat,
        barHeight: CGFloat,
        cgContext: CGContext
    ) {
        let clamped = min(max(value, 0), 1)
        guard clamped > 0 else { return }
        cgContext.saveGState()
        cgContext.setFillColor(fillColor.cgColor)
        let fillWidth = CGFloat(clamped) * barWidth
        cgContext.fill(CGRect(x: barLeft, y: barY, width: fillWidth, height: barHeight))
        cgContext.restoreGState()
    }
}

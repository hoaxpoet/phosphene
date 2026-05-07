// DashboardCardRenderer — Composes drawText + bar geometry onto a DashboardTextLayer.
//
// Painting order matters: chrome (rounded surfaceRaised fill + 1 px border) →
// bar geometry → text. Reversing the order causes bar fills to paint over
// text glyphs because the text layer's CGContext shares pixels with the bar
// fills.
//
// Layout philosophy (DASH.2.1, post-/impeccable redesign):
//   Rows stack their label above their value. The horizontal split layout
//   (label left / value right) was abandoned because at card widths of 280+
//   the empty space between paired data swallowed the relationship. Stacked
//   rows make label-value adjacency unmistakable. The pair row variant was
//   dropped entirely — once each cell stacks, two single rows beat any pair.
//
// Card chrome uses `Color.surfaceRaised` (oklch 0.17 / 0.018 / 278) instead
// of `Color.surface` (oklch 0.13 / 0.015 / 278) so the purple tint reads
// against any visualizer backdrop. Alpha 0.92 stays — the cards float over
// the visualizer; this is the .impeccable.md "purposeful glassmorphism"
// exception (D-082, amended in D-082.1).
//
// Label color uses `Color.textBody` (oklch 0.80) not `Color.textMuted`
// (oklch 0.50). On the surfaceRaised backdrop, textMuted gives ~3.3:1
// contrast — failing WCAG AA for body-size text. textBody gives ~10:1.

import CoreGraphics
import Shared

#if canImport(AppKit)
import AppKit
#endif

// MARK: - DashboardCardRenderer

public struct DashboardCardRenderer: Sendable {

    public init() {}

    /// Render `layout` onto `textLayer` at top-left `origin`.
    @discardableResult
    public func render(
        _ layout: DashboardCardLayout,
        at origin: CGPoint,
        on textLayer: DashboardTextLayer,
        cgContext: CGContext
    ) -> CGFloat {
        drawChrome(layout: layout, origin: origin, cgContext: cgContext)
        drawTitle(layout: layout, origin: origin, on: textLayer)

        let pad = layout.padding
        let innerWidth = layout.width - 2 * pad
        let centerX = origin.x + layout.width / 2
        let leftX = origin.x + pad
        let rightX = origin.x + layout.width - pad

        var y = origin.y + pad + (layout.title.isEmpty ? 0 : layout.titleSize)
        for row in layout.rows {
            y += layout.rowSpacing
            drawRow(
                row,
                rowTopY: y,
                leftX: leftX,
                rightX: rightX,
                centerX: centerX,
                innerWidth: innerWidth,
                on: textLayer,
                cgContext: cgContext
            )
            y += row.height
        }

        return origin.y + layout.height
    }

    // MARK: - Chrome

    private func drawChrome(
        layout: DashboardCardLayout,
        origin: CGPoint,
        cgContext: CGContext
    ) {
        let rect = CGRect(
            x: origin.x,
            y: origin.y,
            width: layout.width,
            height: layout.height
        )
        let radius = DashboardTokens.Spacing.xs
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        cgContext.saveGState()
        let surface = DashboardTokens.Color.surfaceRaised.withAlphaComponent(0.92)
        cgContext.setFillColor(surface.cgColor)
        cgContext.addPath(path)
        cgContext.fillPath()

        cgContext.setStrokeColor(DashboardTokens.Color.border.cgColor)
        cgContext.setLineWidth(1)
        cgContext.addPath(path)
        cgContext.strokePath()
        cgContext.restoreGState()
    }

    // MARK: - Title

    private func drawTitle(
        layout: DashboardCardLayout,
        origin: CGPoint,
        on textLayer: DashboardTextLayer
    ) {
        guard !layout.title.isEmpty else { return }
        textLayer.drawText(
            layout.title,
            at: CGPoint(x: origin.x + layout.padding, y: origin.y + layout.padding),
            size: layout.titleSize,
            weight: .medium,
            font: .prose,
            color: DashboardTokens.Color.textBody,
            tracking: DashboardTokens.TypeScale.labelTracking
        )
    }

    // MARK: - Rows

    // swiftlint:disable function_parameter_count
    private func drawRow(
        _ row: DashboardCardLayout.Row,
        rowTopY: CGFloat,
        leftX: CGFloat,
        rightX: CGFloat,
        centerX: CGFloat,
        innerWidth: CGFloat,
        on textLayer: DashboardTextLayer,
        cgContext: CGContext
    ) {
        switch row {
        case let .singleValue(label, value, valueColor):
            drawSingleValueRow(
                label: label,
                value: value,
                valueColor: valueColor,
                rowTopY: rowTopY,
                leftX: leftX,
                on: textLayer
            )
        case let .bar(label, value, valueText, fillColor, range):
            drawBarRow(
                label: label,
                value: value,
                valueText: valueText,
                fillColor: fillColor,
                range: range,
                rowTopY: rowTopY,
                leftX: leftX,
                rightX: rightX,
                centerX: centerX,
                innerWidth: innerWidth,
                on: textLayer,
                cgContext: cgContext
            )
        }
    }
    // swiftlint:enable function_parameter_count

    // MARK: Single-value (stacked: label on top, value below)

    // swiftlint:disable:next function_parameter_count
    private func drawSingleValueRow(
        label: String,
        value: String,
        valueColor: NSColor,
        rowTopY: CGFloat,
        leftX: CGFloat,
        on textLayer: DashboardTextLayer
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
        let valueY = rowTopY + DashboardTokens.TypeScale.label
            + DashboardCardLayout.labelToValueGap
        textLayer.drawText(
            value,
            at: CGPoint(x: leftX, y: valueY),
            size: DashboardTokens.TypeScale.hero,
            weight: .medium,
            font: .mono,
            color: valueColor
        )
    }

    // MARK: Bar (stacked: label on top, bar + value text on a single line below)

    // swiftlint:disable function_parameter_count
    private func drawBarRow(
        label: String,
        value: Float,
        valueText: String,
        fillColor: NSColor,
        range: ClosedRange<Float>,
        rowTopY: CGFloat,
        leftX: CGFloat,
        rightX: CGFloat,
        centerX: CGFloat,
        innerWidth: CGFloat,
        on textLayer: DashboardTextLayer,
        cgContext: CGContext
    ) {
        // Top: label.
        textLayer.drawText(
            label,
            at: CGPoint(x: leftX, y: rowTopY),
            size: DashboardTokens.TypeScale.label,
            weight: .medium,
            font: .prose,
            color: DashboardTokens.Color.textBody,
            tracking: DashboardTokens.TypeScale.labelTracking
        )

        // Bottom: bar (left) + value text (right) on the same line.
        // The value text is reserved a fixed-width column so the bar's
        // geometry stays predictable for tests.
        let valueColumnWidth: CGFloat = 56
        let valueColumnGap: CGFloat = 8
        let barRightLimit = rightX - valueColumnWidth - valueColumnGap
        let barAreaWidth = barRightLimit - leftX
        let barHeight: CGFloat = 6
        let barAreaY = rowTopY + DashboardTokens.TypeScale.label
            + DashboardCardLayout.labelToValueGap
        let barY = barAreaY + ((17 - barHeight) / 2)              // vertical-centre in the 17pt band
        let barRect = CGRect(x: leftX, y: barY, width: barAreaWidth, height: barHeight)
        let cornerRadius: CGFloat = 1

        drawBarChrome(
            barRect: barRect,
            cornerRadius: cornerRadius,
            cgContext: cgContext
        )
        drawBarFill(
            value: value,
            range: range,
            fillColor: fillColor,
            barLeft: leftX,
            barWidth: barAreaWidth,
            barY: barY,
            barHeight: barHeight,
            cgContext: cgContext
        )

        // Value text right-aligned in its reserved column. Vertical centre
        // matches the bar's row.
        textLayer.drawText(
            valueText,
            at: CGPoint(x: rightX, y: barAreaY),
            size: DashboardTokens.TypeScale.body,
            weight: .regular,
            font: .mono,
            color: fillColor,
            align: .right
        )
        // Suppress unused-parameter warning for centerX, innerWidth: kept on
        // the signature so signature parity with future row variants holds.
        _ = centerX
        _ = innerWidth
    }
    // swiftlint:enable function_parameter_count

    private func drawBarChrome(
        barRect: CGRect,
        cornerRadius: CGFloat,
        cgContext: CGContext
    ) {
        cgContext.saveGState()
        let bgPath = CGPath(
            roundedRect: barRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        cgContext.setFillColor(DashboardTokens.Color.border.cgColor)
        cgContext.addPath(bgPath)
        cgContext.fillPath()
        cgContext.restoreGState()
    }

    // swiftlint:disable:next function_parameter_count
    private func drawBarFill(
        value: Float,
        range: ClosedRange<Float>,
        fillColor: NSColor,
        barLeft: CGFloat,
        barWidth: CGFloat,
        barY: CGFloat,
        barHeight: CGFloat,
        cgContext: CGContext
    ) {
        let barCenterX = barLeft + barWidth / 2
        let halfBarWidth = barWidth / 2
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard clamped != 0 else { return }
        cgContext.saveGState()
        cgContext.setFillColor(fillColor.cgColor)
        if clamped > 0 {
            let extent = max(range.upperBound, .leastNonzeroMagnitude)
            let fillWidth = CGFloat(clamped / extent) * halfBarWidth
            cgContext.fill(CGRect(x: barCenterX, y: barY, width: fillWidth, height: barHeight))
        } else {
            let extent = max(-range.lowerBound, .leastNonzeroMagnitude)
            let fillWidth = CGFloat(-clamped / extent) * halfBarWidth
            cgContext.fill(CGRect(
                x: barCenterX - fillWidth,
                y: barY,
                width: fillWidth,
                height: barHeight
            ))
        }
        cgContext.restoreGState()
    }
}

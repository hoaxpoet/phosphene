// DashboardCardRenderer — Composes drawText + bar geometry onto a DashboardTextLayer.
//
// Painting order matters: chrome (rounded surface fill + 1px border) → bar
// geometry → text. Reversing the order causes bar fills to paint over text
// glyphs because the text layer's CGContext shares pixels with the bar fills.
//
// Right-edge clipping: every value column on the right of a card is rendered
// with `align: .right` so the rightmost glyph never extends past
// `origin.x + width - padding`. The bar fill is bounded by `padding` on both
// inner edges; a card's bar can never overflow its declared width.
//
// Card chrome is the one place in the dashboard where alpha < 1 is sanctioned
// (0.92 surface fill). The cards float over a moving visualizer; the slight
// transparency is the .impeccable.md "purposeful glassmorphism" exception
// (D-082).

import CoreGraphics
import Shared

#if canImport(AppKit)
import AppKit
#endif

// MARK: - DashboardCardRenderer

public struct DashboardCardRenderer: Sendable {

    public init() {}

    /// Render `layout` onto `textLayer` at top-left `origin`.
    ///
    /// - Parameter cgContext: The CGContext backing `textLayer` (obtained via
    ///   `textLayer.graphicsContext`). Passed explicitly so callers see the
    ///   shared-context contract at the call site.
    /// - Returns: The Y coordinate immediately below the card. Callers may
    ///   stack cards by adding `Spacing.sm` between successive returns.
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

        var y = origin.y + pad + layout.titleSize
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
        let surface = DashboardTokens.Color.surface.withAlphaComponent(0.92)
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
        textLayer.drawText(
            layout.title,
            at: CGPoint(x: origin.x + layout.padding, y: origin.y + layout.padding),
            size: layout.titleSize,
            weight: .medium,
            font: .prose,
            color: DashboardTokens.Color.textMuted,
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
                rightX: rightX,
                on: textLayer
            )
        case let .pair(leftLabel, leftValue, rightLabel, rightValue, valueColor):
            drawPairRow(
                leftLabel: leftLabel,
                leftValue: leftValue,
                rightLabel: rightLabel,
                rightValue: rightValue,
                valueColor: valueColor,
                rowTopY: rowTopY,
                leftX: leftX,
                rightX: rightX,
                centerX: centerX,
                on: textLayer,
                cgContext: cgContext
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

    // MARK: Single-value

    // swiftlint:disable:next function_parameter_count
    private func drawSingleValueRow(
        label: String,
        value: String,
        valueColor: NSColor,
        rowTopY: CGFloat,
        leftX: CGFloat,
        rightX: CGFloat,
        on textLayer: DashboardTextLayer
    ) {
        textLayer.drawText(
            label,
            at: CGPoint(x: leftX, y: rowTopY),
            size: DashboardTokens.TypeScale.body,
            weight: .regular,
            font: .prose,
            color: DashboardTokens.Color.textMuted
        )
        textLayer.drawText(
            value,
            at: CGPoint(x: rightX, y: rowTopY),
            size: DashboardTokens.TypeScale.numeric,
            weight: .medium,
            font: .mono,
            color: valueColor,
            align: .right
        )
    }

    // MARK: Pair

    // swiftlint:disable function_parameter_count
    private func drawPairRow(
        leftLabel: String,
        leftValue: String,
        rightLabel: String,
        rightValue: String,
        valueColor: NSColor,
        rowTopY: CGFloat,
        leftX: CGFloat,
        rightX: CGFloat,
        centerX: CGFloat,
        on textLayer: DashboardTextLayer,
        cgContext: CGContext
    ) {
        // Left half: label at leftX, value right-aligned at midpoint - a small gap.
        let dividerInset: CGFloat = 4
        let leftValueX = centerX - dividerInset
        textLayer.drawText(
            leftLabel,
            at: CGPoint(x: leftX, y: rowTopY),
            size: DashboardTokens.TypeScale.body,
            weight: .regular,
            font: .prose,
            color: DashboardTokens.Color.textMuted
        )
        textLayer.drawText(
            leftValue,
            at: CGPoint(x: leftValueX, y: rowTopY),
            size: DashboardTokens.TypeScale.numeric,
            weight: .medium,
            font: .mono,
            color: valueColor,
            align: .right
        )

        // Vertical 1px divider at midpoint.
        cgContext.saveGState()
        cgContext.setFillColor(DashboardTokens.Color.border.cgColor)
        let dividerRect = CGRect(
            x: centerX,
            y: rowTopY + 2,
            width: 1,
            height: DashboardCardLayout.Row.pairHeight - 4
        )
        cgContext.fill(dividerRect)
        cgContext.restoreGState()

        // Right half: label after divider, value right-aligned at rightX.
        let rightLabelX = centerX + dividerInset
        textLayer.drawText(
            rightLabel,
            at: CGPoint(x: rightLabelX, y: rowTopY),
            size: DashboardTokens.TypeScale.body,
            weight: .regular,
            font: .prose,
            color: DashboardTokens.Color.textMuted
        )
        textLayer.drawText(
            rightValue,
            at: CGPoint(x: rightX, y: rowTopY),
            size: DashboardTokens.TypeScale.numeric,
            weight: .medium,
            font: .mono,
            color: valueColor,
            align: .right
        )
    }
    // swiftlint:enable function_parameter_count

    // MARK: Bar

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
        // Top: label (left, muted) + value text (right, body).
        textLayer.drawText(
            label,
            at: CGPoint(x: leftX, y: rowTopY),
            size: DashboardTokens.TypeScale.label,
            weight: .medium,
            font: .prose,
            color: DashboardTokens.Color.textMuted,
            tracking: DashboardTokens.TypeScale.labelTracking
        )
        textLayer.drawText(
            valueText,
            at: CGPoint(x: rightX, y: rowTopY),
            size: DashboardTokens.TypeScale.body,
            weight: .regular,
            font: .mono,
            color: DashboardTokens.Color.textBody,
            align: .right
        )

        // Bar at the bottom of the row, full inner width, 6pt high.
        let barHeight: CGFloat = 6
        let barY = rowTopY + DashboardCardLayout.Row.barHeight - barHeight
        let barRect = CGRect(x: leftX, y: barY, width: innerWidth, height: barHeight)
        let cornerRadius: CGFloat = 1

        cgContext.saveGState()
        // Background.
        let bgPath = CGPath(
            roundedRect: barRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        cgContext.setFillColor(DashboardTokens.Color.surfaceRaised.cgColor)
        cgContext.addPath(bgPath)
        cgContext.fillPath()

        // Foreground: signed slice from centre. Clamp value to range first.
        let halfBarWidth = innerWidth / 2
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        if clamped > 0 {
            let extent = max(range.upperBound, .leastNonzeroMagnitude)
            let fillWidth = CGFloat(clamped / extent) * halfBarWidth
            let fillRect = CGRect(x: centerX, y: barY, width: fillWidth, height: barHeight)
            cgContext.setFillColor(fillColor.cgColor)
            cgContext.fill(fillRect)
        } else if clamped < 0 {
            let extent = max(-range.lowerBound, .leastNonzeroMagnitude)
            let fillWidth = CGFloat(-clamped / extent) * halfBarWidth
            let fillRect = CGRect(
                x: centerX - fillWidth,
                y: barY,
                width: fillWidth,
                height: barHeight
            )
            cgContext.setFillColor(fillColor.cgColor)
            cgContext.fill(fillRect)
        }
        cgContext.restoreGState()
    }
    // swiftlint:enable function_parameter_count
}

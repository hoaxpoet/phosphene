// DashboardRowView — Renders one `DashboardCardLayout.Row` as SwiftUI
// (DASH.7).
//
// Four row variants:
//   .singleValue   — UPPERCASE label on top, large numeric value below.
//   .bar           — UPPERCASE label, signed bar from centre + value text.
//   .progressBar   — UPPERCASE label, left-to-right unsigned ramp + value.
//   .timeseries    — UPPERCASE label, sparkline (last N samples) + value.
//
// Color tokens drawn from `DashboardTokens.Color` so the SwiftUI port matches
// the DASH.6 contract. SF Symbol status indicators decorate the .progressBar
// row when its `fillColor` reads as a status colour (PERF FRAME's primary
// signal — D-087 PERF semantic clarity).

import Renderer
import Shared
import SwiftUI

// MARK: - DashboardRowView

struct DashboardRowView: View {
    let row: DashboardCardLayout.Row

    var body: some View {
        switch row {
        case let .singleValue(label, value, valueColor):
            singleValueRow(label: label, value: value, valueColor: valueColor)
        case let .bar(label, value, valueText, fillColor, range):
            barRow(
                label: label,
                value: value,
                valueText: valueText,
                fillColor: fillColor,
                range: range
            )
        case let .progressBar(label, value, valueText, fillColor):
            progressBarRow(
                label: label,
                value: value,
                valueText: valueText,
                fillColor: fillColor
            )
        case let .timeseries(label, samples, range, valueText, fillColor):
            timeseriesRow(
                label: label,
                samples: samples,
                range: range,
                valueText: valueText,
                fillColor: fillColor
            )
        }
    }

    // MARK: - .singleValue

    private func singleValueRow(label: String, value: String, valueColor: NSColor) -> some View {
        VStack(alignment: .leading, spacing: DashboardCardLayout.labelToValueGap) {
            rowLabel(label)
            HStack(spacing: 6) {
                statusIcon(for: valueColor)
                Text(value)
                    .font(.system(size: DashboardTokens.TypeScale.hero, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(nsColor: valueColor))
            }
        }
    }

    // MARK: - .bar

    private func barRow(
        label: String,
        value: Float,
        valueText: String,
        fillColor: NSColor,
        range: ClosedRange<Float>
    ) -> some View {
        VStack(alignment: .leading, spacing: DashboardCardLayout.labelToValueGap) {
            rowLabel(label)
            HStack(spacing: 8) {
                SignedBarView(value: value, range: range, fillColor: fillColor)
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
                Text(valueText)
                    .font(.system(size: DashboardTokens.TypeScale.body, design: .monospaced))
                    .foregroundColor(Color(nsColor: fillColor))
                    .frame(width: 56, alignment: .trailing)
            }
            .frame(height: 17)
        }
    }

    // MARK: - .progressBar

    private func progressBarRow(
        label: String,
        value: Float,
        valueText: String,
        fillColor: NSColor
    ) -> some View {
        VStack(alignment: .leading, spacing: DashboardCardLayout.labelToValueGap) {
            HStack(spacing: 6) {
                rowLabel(label)
                statusIcon(for: fillColor)
            }
            HStack(spacing: 8) {
                ProgressBarView(value: value, fillColor: fillColor)
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
                Text(valueText)
                    .font(.system(size: DashboardTokens.TypeScale.body, design: .monospaced))
                    .foregroundColor(Color(nsColor: fillColor))
                    .frame(width: 86, alignment: .trailing)
            }
            .frame(height: 17)
        }
    }

    // MARK: - .timeseries

    private func timeseriesRow(
        label: String,
        samples: [Float],
        range: ClosedRange<Float>,
        valueText: String,
        fillColor: NSColor
    ) -> some View {
        VStack(alignment: .leading, spacing: DashboardCardLayout.labelToValueGap) {
            rowLabel(label)
            HStack(spacing: 8) {
                SparklineView(samples: samples, range: range, fillColor: fillColor)
                    .frame(height: 32)
                    .frame(maxWidth: .infinity)
                Text(valueText)
                    .font(.system(size: DashboardTokens.TypeScale.body, design: .monospaced))
                    .foregroundColor(Color(nsColor: fillColor))
                    .frame(width: 56, alignment: .trailing)
            }
            .frame(height: 32)
        }
    }

    // MARK: - Shared

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DashboardTokens.TypeScale.label, weight: .medium))
            .tracking(DashboardTokens.TypeScale.labelTracking)
            .foregroundColor(Color(nsColor: DashboardTokens.Color.textBody))
    }

    /// SF Symbol decorating status-coloured rows — green check, yellow
    /// warning, muted dot. Helps Matt's "is this good or bad?" question
    /// without relying on colour alone (also accessibility positive).
    @ViewBuilder
    private func statusIcon(for color: NSColor) -> some View {
        if color == DashboardTokens.Color.statusGreen {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(nsColor: color))
                .font(.system(size: 11))
        } else if color == DashboardTokens.Color.statusYellow {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(nsColor: color))
                .font(.system(size: 11))
        }
    }
}

// MARK: - SignedBarView

/// Bar fill from horizontal centre, signed by `value` against `range`.
private struct SignedBarView: View {
    let value: Float
    let range: ClosedRange<Float>
    let fillColor: NSColor

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let centerX = width / 2
            let halfWidth = width / 2
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            let extent = clamped >= 0 ? max(range.upperBound, .leastNonzeroMagnitude)
                                      : max(-range.lowerBound, .leastNonzeroMagnitude)
            let fillWidth = CGFloat(abs(clamped) / extent) * halfWidth

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(nsColor: DashboardTokens.Color.border))
                if fillWidth > 0 {
                    Rectangle()
                        .fill(Color(nsColor: fillColor))
                        .frame(width: fillWidth, height: height)
                        .offset(x: clamped >= 0 ? centerX : centerX - fillWidth)
                }
            }
        }
    }
}

// MARK: - ProgressBarView

/// Left-to-right unsigned ramp 0 ... 1.
private struct ProgressBarView: View {
    let value: Float
    let fillColor: NSColor

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let clamped = min(max(value, 0), 1)
            let fillWidth = CGFloat(clamped) * width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(nsColor: DashboardTokens.Color.border))
                if fillWidth > 0 {
                    Rectangle()
                        .fill(Color(nsColor: fillColor))
                        .frame(width: fillWidth, height: height)
                }
            }
        }
    }
}

// MARK: - SparklineView

/// Filled sparkline from horizontal centre line, sampling `samples` clamped
/// to `range`. Empty samples renders the centre baseline only.
private struct SparklineView: View {
    let samples: [Float]
    let range: ClosedRange<Float>
    let fillColor: NSColor

    var body: some View {
        Canvas { ctx, size in
            // Centre baseline — drawn even when samples are empty so the row
            // shows "absence of signal" stably (.impeccable convention).
            let baselineY = size.height / 2
            let baseline = Path { path in
                path.move(to: CGPoint(x: 0, y: baselineY))
                path.addLine(to: CGPoint(x: size.width, y: baselineY))
            }
            ctx.stroke(
                baseline,
                with: .color(Color(nsColor: DashboardTokens.Color.border)),
                lineWidth: 0.5
            )
            guard samples.count >= 2 else { return }

            let span = range.upperBound - range.lowerBound
            guard span > 0 else { return }
            let stepX = size.width / CGFloat(samples.count - 1)

            // Build the filled area path: from each sample's y back down to
            // the baseline.
            var area = Path()
            area.move(to: CGPoint(x: 0, y: baselineY))
            for (i, raw) in samples.enumerated() {
                let clamped = min(max(raw, range.lowerBound), range.upperBound)
                // Map [range] → [size.height ... 0] with centre at baselineY.
                let normalized = (clamped - (range.lowerBound + span / 2)) / (span / 2) // [-1, 1]
                let yOffset = CGFloat(normalized) * (size.height / 2)
                let pt = CGPoint(x: CGFloat(i) * stepX, y: baselineY - yOffset)
                area.addLine(to: pt)
            }
            area.addLine(to: CGPoint(x: size.width, y: baselineY))
            area.closeSubpath()

            ctx.fill(area, with: .color(Color(nsColor: fillColor).opacity(0.55)))

            // Stroke the line on top for crispness.
            var line = Path()
            for (i, raw) in samples.enumerated() {
                let clamped = min(max(raw, range.lowerBound), range.upperBound)
                let normalized = (clamped - (range.lowerBound + span / 2)) / (span / 2)
                let yOffset = CGFloat(normalized) * (size.height / 2)
                let pt = CGPoint(x: CGFloat(i) * stepX, y: baselineY - yOffset)
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            ctx.stroke(line, with: .color(Color(nsColor: fillColor)), lineWidth: 1)
        }
    }
}

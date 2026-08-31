// DashboardRowView — Renders one `DashboardCardLayout.Row` as SwiftUI
// (DASH.7 + DASH.7.1).
//
// Four row variants:
//   .singleValue   — UPPERCASE label on top, large numeric value below.
//   .bar           — UPPERCASE label, signed bar from centre + value text.
//   .progressBar   — UPPERCASE label, left-to-right unsigned ramp + value.
//   .timeseries    — UPPERCASE label, sparkline (last N samples).
//
// DASH.7.1 brand-alignment changes (D-088):
//   • Drops SF Symbol status icons (web-admin trope; Sakamoto-liner-note
//     aesthetic is text-and-form). Status reads via value-text colour.
//   • Empty `.timeseries` valueText collapses the right-side numeric column
//     entirely — the sparkline IS the readout.
//   • Labels and value text use Epilogue when registered; SF Mono retained
//     for numerics where mono alignment matters.

import Renderer
import Shared
import SwiftUI

// MARK: - DashboardRowView

struct DashboardRowView: View {
    let row: DashboardCardLayout.Row
    let fontResolution: DashboardFontLoader.FontResolution

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
    //
    // DASH.7.2 (D-089): rendered inline (label-left, value-right) so MODE /
    // BPM / QUALITY / ML rows visually align with the value text in `.bar`
    // and `.progressBar` rows. Replaces the DASH.7 stacked "label on top,
    // 24pt mono value below" layout — every row in the dashboard now reads
    // as the same horizontal scan, matching the Sakamoto-liner-note rhythm.

    private func singleValueRow(label: String, value: String, valueColor: NSColor) -> some View {
        HStack(spacing: 8) {
            rowLabel(label)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: DashboardTokens.TypeScale.body, weight: .medium, design: .monospaced))
                .foregroundColor(Color(nsColor: valueColor))
                .lineLimit(1)
        }
        .frame(height: 17)
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
                if !valueText.isEmpty {
                    Text(valueText)
                        .font(.system(size: DashboardTokens.TypeScale.body, design: .monospaced))
                        .foregroundColor(Color(nsColor: fillColor))
                        .frame(width: 56, alignment: .trailing)
                }
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
            rowLabel(label)
            HStack(spacing: 8) {
                ProgressBarView(value: value, fillColor: fillColor)
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
                if !valueText.isEmpty {
                    Text(valueText)
                        .font(.system(size: DashboardTokens.TypeScale.body, design: .monospaced))
                        .foregroundColor(Color(nsColor: fillColor))
                        .frame(width: 110, alignment: .trailing)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
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
                // valueText is intentionally empty for STEMS rows (D-088 P1.6) —
                // the sparkline IS the readout. The fallback below preserves the
                // .timeseries variant's API for any future caller that does
                // want a numeric trailer.
                if !valueText.isEmpty {
                    Text(valueText)
                        .font(.system(size: DashboardTokens.TypeScale.body, design: .monospaced))
                        .foregroundColor(Color(nsColor: fillColor))
                        .frame(width: 56, alignment: .trailing)
                }
            }
            .frame(height: 32)
        }
    }

    // MARK: - Shared

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.custom(
                fontResolution.proseMediumFontName,
                size: DashboardTokens.TypeScale.label,
                relativeTo: .caption
            ))
            .tracking(DashboardTokens.TypeScale.labelTracking)
            .foregroundColor(Color(nsColor: DashboardTokens.Color.textBody))
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

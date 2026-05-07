// StemsCardBuilderTests — Pure data assertions for `StemsCardBuilder`.
// DASH.7 rewrite: builder now consumes `StemEnergyHistory` (timeseries) rather
// than a single `StemFeatures` snapshot (DASH.4 signed-bar design retired).

import CoreGraphics
import Foundation
import Testing
@testable import Renderer
@testable import Shared

#if canImport(AppKit)
import AppKit
#endif

private func extractTimeseries(_ row: DashboardCardLayout.Row)
    -> (label: String, samples: [Float], range: ClosedRange<Float>, valueText: String, color: NSColor)? {
    if case let .timeseries(label, samples, range, valueText, color) = row {
        return (label, samples, range, valueText, color)
    }
    return nil
}

private func colorEquals(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
    let l = lhs.usingColorSpace(.sRGB) ?? lhs
    let r = rhs.usingColorSpace(.sRGB) ?? rhs
    return abs(l.redComponent - r.redComponent) < 0.001
        && abs(l.greenComponent - r.greenComponent) < 0.001
        && abs(l.blueComponent - r.blueComponent) < 0.001
}

@Suite("StemsCardBuilder")
struct StemsCardBuilderTests {

    @Test("mixed history produces 4 .timeseries rows in DRUMS/BASS/VOCALS/OTHER order")
    func mixedHistory() throws {
        let history = StemEnergyHistory(
            drums: [0.1, 0.4, 0.7, 0.5, 0.3],
            bass: [-0.2, 0.0, 0.2, 0.4, 0.5],
            vocals: [0.0, 0.1, -0.1, 0.0, 0.0],
            other: [0.05, 0.05, 0.06, 0.05, 0.04]
        )
        let layout = StemsCardBuilder().build(from: history)
        #expect(layout.title == "STEMS")
        #expect(layout.rows.count == 4)

        let labels = ["DRUMS", "BASS", "VOCALS", "OTHER"]
        for (i, expected) in labels.enumerated() {
            let row = try #require(extractTimeseries(layout.rows[i]))
            #expect(row.label == expected)
            #expect(row.range == -1.0 ... 1.0)
            #expect(colorEquals(row.color, DashboardTokens.Color.coral))
        }
    }

    @Test("most-recent sample is reflected in valueText with signed format")
    func valueText() throws {
        let history = StemEnergyHistory(
            drums: [0.1, 0.2, 0.35],
            bass: [-0.4, -0.5, -0.55],
            vocals: [],
            other: [0.05]
        )
        let layout = StemsCardBuilder().build(from: history)
        let drums = try #require(extractTimeseries(layout.rows[0]))
        #expect(drums.valueText == "+0.35")
        let bass = try #require(extractTimeseries(layout.rows[1]))
        #expect(bass.valueText == "-0.55")
        let vocals = try #require(extractTimeseries(layout.rows[2]))
        #expect(vocals.valueText == "—")
    }

    @Test("empty history yields empty samples and — placeholder per row")
    func emptyHistory() throws {
        let layout = StemsCardBuilder().build(from: .empty)
        #expect(layout.rows.count == 4)
        for row in layout.rows {
            let ts = try #require(extractTimeseries(row))
            #expect(ts.samples.isEmpty)
            #expect(ts.valueText == "—")
        }
    }

    @Test("samples pass through unchanged (no clamp at the builder layer)")
    func passThrough() throws {
        let history = StemEnergyHistory(
            drums: [-2.0, 2.0, 0.5],
            bass: [],
            vocals: [],
            other: []
        )
        let layout = StemsCardBuilder().build(from: history)
        let drums = try #require(extractTimeseries(layout.rows[0]))
        #expect(drums.samples == [-2.0, 2.0, 0.5])
    }

    @Test("uniform coral colour across all four rows (v1)")
    func uniformColour() throws {
        let history = StemEnergyHistory(drums: [0.5], bass: [0.5], vocals: [0.5], other: [0.5])
        let layout = StemsCardBuilder().build(from: history)
        for row in layout.rows {
            let ts = try #require(extractTimeseries(row))
            #expect(colorEquals(ts.color, DashboardTokens.Color.coral))
        }
    }

    @Test("width override is passed through to the layout")
    func widthOverride() {
        let layout = StemsCardBuilder().build(from: .empty, width: 360)
        #expect(layout.width == 360)
    }
}

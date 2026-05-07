// PerfCardBuilderTests — Pure data assertions for `PerfCardBuilder`.
// DASH.7 rewrite: row count is now dynamic — QUALITY hides when full,
// ML hides on idle / dispatchNow.

import CoreGraphics
import Foundation
import Testing
@testable import Renderer
@testable import Shared

#if canImport(AppKit)
import AppKit
#endif

private func extractSingleValue(_ row: DashboardCardLayout.Row) -> (label: String, value: String, color: NSColor)? {
    if case let .singleValue(label, value, color) = row {
        return (label, value, color)
    }
    return nil
}

private func extractProgressBar(_ row: DashboardCardLayout.Row) -> (label: String, value: Float, valueText: String, color: NSColor)? {
    if case let .progressBar(label, value, valueText, color) = row {
        return (label, value, valueText, color)
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

@Suite("PerfCardBuilder")
struct PerfCardBuilderTests {

    @Test("zero snapshot produces FRAME=— muted; QUALITY warming muted; ML hidden")
    func zero() throws {
        let layout = PerfCardBuilder().build(from: .zero)
        #expect(layout.title == "PERF")
        // FRAME (always present) + QUALITY (warming-up state visible) = 2 rows.
        #expect(layout.rows.count == 2)
        let frame = try #require(extractProgressBar(layout.rows[0]))
        #expect(frame.label == "FRAME")
        #expect(frame.valueText == "—")
        #expect(colorEquals(frame.color, DashboardTokens.Color.textMuted))
        let quality = try #require(extractSingleValue(layout.rows[1]))
        #expect(quality.label == "QUALITY")
        #expect(colorEquals(quality.color, DashboardTokens.Color.textMuted))
    }

    @Test("healthy snapshot produces only FRAME row (QUALITY + ML hidden) — teal status")
    func healthy() throws {
        let snap = PerfSnapshot(
            recentMaxFrameMs: 8.2,
            recentFramesObserved: 30,
            targetFrameMs: 14.0,
            qualityLevelRawValue: 0,
            qualityLevelDisplayName: "full",
            mlDecisionCode: 1, // dispatchNow / READY → hidden
            mlDeferRetryMs: 0
        )
        let layout = PerfCardBuilder().build(from: snap)
        #expect(layout.rows.count == 1)
        let frame = try #require(extractProgressBar(layout.rows[0]))
        #expect(abs(frame.value - 8.2 / 14.0) < 1e-5)
        #expect(frame.valueText == "8.2 / 14 ms")
        // Brand-aligned: healthy → teal (analytical), not statusGreen (D-088).
        #expect(colorEquals(frame.color, DashboardTokens.Color.teal))
    }

    @Test("over-warning ratio flips FRAME to coralMuted")
    func warningRatio() throws {
        let snap = PerfSnapshot(
            recentMaxFrameMs: 12.6,            // 12.6 / 14 = 0.9 > 0.7 warning threshold
            recentFramesObserved: 30,
            targetFrameMs: 14.0,
            qualityLevelRawValue: 0,
            qualityLevelDisplayName: "full",
            mlDecisionCode: 1,
            mlDeferRetryMs: 0
        )
        let layout = PerfCardBuilder().build(from: snap)
        let frame = try #require(extractProgressBar(layout.rows[0]))
        // Brand-aligned: warning → coralMuted ("warmth arriving at rest"), not statusYellow (D-088).
        #expect(colorEquals(frame.color, DashboardTokens.Color.coralMuted))
    }

    @Test("frame time above budget clamps bar at 1.0; valueText shows raw")
    func clampOverBudget() throws {
        let snap = PerfSnapshot(
            recentMaxFrameMs: 42.0,
            recentFramesObserved: 60,
            targetFrameMs: 14.0,
            qualityLevelRawValue: 0,
            qualityLevelDisplayName: "full",
            mlDecisionCode: 1,
            mlDeferRetryMs: 0
        )
        let layout = PerfCardBuilder().build(from: snap)
        let frame = try #require(extractProgressBar(layout.rows[0]))
        #expect(frame.value == 1.0)
        #expect(frame.valueText == "42.0 / 14 ms")
    }

    @Test("downshifted snapshot produces coralMuted QUALITY 'noBloom'; ML hidden if dispatchNow")
    func downshifted() throws {
        let snap = PerfSnapshot(
            recentMaxFrameMs: 11.0,
            recentFramesObserved: 30,
            targetFrameMs: 14.0,
            qualityLevelRawValue: 2,
            qualityLevelDisplayName: "noBloom",
            mlDecisionCode: 1,
            mlDeferRetryMs: 0
        )
        let layout = PerfCardBuilder().build(from: snap)
        #expect(layout.rows.count == 2)
        let quality = try #require(extractSingleValue(layout.rows[1]))
        #expect(quality.value == "noBloom")
        // Brand-aligned: downshifted → coralMuted, not statusYellow (D-088).
        #expect(colorEquals(quality.color, DashboardTokens.Color.coralMuted))
    }

    @Test("forced dispatch snapshot produces FORCED ML row (coralMuted)")
    func forcedDispatch() throws {
        let snap = PerfSnapshot(
            recentMaxFrameMs: 11.0,
            recentFramesObserved: 30,
            targetFrameMs: 14.0,
            qualityLevelRawValue: 0,
            qualityLevelDisplayName: "full",
            mlDecisionCode: 3,                 // forceDispatch
            mlDeferRetryMs: 0
        )
        let layout = PerfCardBuilder().build(from: snap)
        // FRAME (full healthy) + ML (forced) = 2 rows.
        #expect(layout.rows.count == 2)
        let ml = try #require(extractSingleValue(layout.rows[1]))
        #expect(ml.label == "ML")
        #expect(ml.value == "FORCED")
        // Brand-aligned: forced → coralMuted, not statusYellow (D-088).
        #expect(colorEquals(ml.color, DashboardTokens.Color.coralMuted))
    }

    @Test("defer ML decision shows WAIT with retry-ms text")
    func deferDecision() throws {
        let snap = PerfSnapshot(
            recentMaxFrameMs: 11.0,
            recentFramesObserved: 30,
            targetFrameMs: 14.0,
            qualityLevelRawValue: 0,
            qualityLevelDisplayName: "full",
            mlDecisionCode: 2,
            mlDeferRetryMs: 200
        )
        let layout = PerfCardBuilder().build(from: snap)
        let ml = try #require(extractSingleValue(layout.rows[1]))
        #expect(ml.value == "WAIT 200ms")
    }

    @Test("width override is passed through to the layout")
    func widthOverride() {
        let layout = PerfCardBuilder().build(from: .zero, width: 360)
        #expect(layout.width == 360)
    }
}

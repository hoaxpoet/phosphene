// PerfCardBuilderTests — 6 @Test functions covering PerfSnapshot →
// DashboardCardLayout mapping (DASH.5).
//
// Switch-pattern row extractors + sRGB-channel colour comparison mirror
// the BeatCardBuilderTests / StemsCardBuilderTests pattern (file-
// independence convention; no hoisted shared helpers).

import CoreGraphics
import Foundation
import Metal
import Testing
@testable import Renderer
@testable import Shared

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Switch-pattern row extractors

private func extractSingleValue(_ row: DashboardCardLayout.Row)
    -> (label: String, value: String, valueColor: NSColor)? {
    if case let .singleValue(label, value, valueColor) = row {
        return (label, value, valueColor)
    }
    return nil
}

private func extractProgressBar(_ row: DashboardCardLayout.Row)
    -> (label: String, value: Float, valueText: String, fillColor: NSColor)? {
    if case let .progressBar(label, value, valueText, fillColor) = row {
        return (label, value, valueText, fillColor)
    }
    return nil
}

// MARK: - Color comparison

/// `NSColor` equality is unreliable across colour spaces; compare via sRGB
/// channels with a tight tolerance.
private func colorMatches(_ lhs: NSColor, _ rhs: NSColor, tolerance: CGFloat = 0.01) -> Bool {
    guard let a = lhs.usingColorSpace(.sRGB),
          let b = rhs.usingColorSpace(.sRGB) else { return false }
    return abs(a.redComponent - b.redComponent) < tolerance
        && abs(a.greenComponent - b.greenComponent) < tolerance
        && abs(a.blueComponent - b.blueComponent) < tolerance
}

// MARK: - Tests

@Suite("PerfCardBuilder")
struct PerfCardBuilderTests {

    // MARK: a — zero snapshot → no-observations layout

    @Test("zero snapshot produces FRAME=0/—, QUALITY=full/muted, ML=—/muted")
    func build_zeroSnapshot_producesNoObservationsLayout() throws {
        let layout = PerfCardBuilder().build(from: .zero)

        #expect(layout.title == "PERF")
        #expect(layout.rows.count == 3)

        let frame = try #require(extractProgressBar(layout.rows[0]))
        #expect(frame.label == "FRAME")
        #expect(frame.value == 0)
        #expect(frame.valueText == "—")
        #expect(colorMatches(frame.fillColor, DashboardTokens.Color.coral))

        let quality = try #require(extractSingleValue(layout.rows[1]))
        #expect(quality.label == "QUALITY")
        #expect(quality.value == "full")
        #expect(colorMatches(quality.valueColor, DashboardTokens.Color.textMuted))

        let ml = try #require(extractSingleValue(layout.rows[2]))
        #expect(ml.label == "ML")
        #expect(ml.value == "—")
        #expect(colorMatches(ml.valueColor, DashboardTokens.Color.textMuted))
    }

    // MARK: b — healthy full quality

    @Test("healthy snapshot produces green QUALITY, READY ML, FRAME ratio 8.2/14")
    func build_healthyFullQuality_producesGreenQualityAndReadyML() throws {
        let snapshot = PerfSnapshot(
            recentMaxFrameMs: 8.2,
            recentFramesObserved: 30,
            targetFrameMs: 14,
            qualityLevelRawValue: 0,
            qualityLevelDisplayName: "full",
            mlDecisionCode: 1,
            mlDeferRetryMs: 0
        )
        let layout = PerfCardBuilder().build(from: snapshot)

        let frame = try #require(extractProgressBar(layout.rows[0]))
        #expect(frame.value >= 0.576 && frame.value <= 0.596,
                "Expected FRAME ≈ 0.586; got \(frame.value)")
        #expect(frame.valueText == "8.2 ms")

        let quality = try #require(extractSingleValue(layout.rows[1]))
        #expect(quality.value == "full")
        #expect(colorMatches(quality.valueColor, DashboardTokens.Color.statusGreen))

        let ml = try #require(extractSingleValue(layout.rows[2]))
        #expect(ml.value == "READY")
        #expect(colorMatches(ml.valueColor, DashboardTokens.Color.statusGreen))
    }

    // MARK: c — governor downshifted + ML defer

    @Test("downshifted snapshot produces yellow QUALITY no-bloom, WAIT 200ms ML, FRAME clamped 1.0")
    func build_governorDownshifted_producesYellowQualityAndDeferML() throws {
        let snapshot = PerfSnapshot(
            recentMaxFrameMs: 15.3,
            recentFramesObserved: 30,
            targetFrameMs: 14,
            qualityLevelRawValue: 2,
            qualityLevelDisplayName: "no-bloom",
            mlDecisionCode: 2,
            mlDeferRetryMs: 200
        )
        let layout = PerfCardBuilder().build(from: snapshot)

        let frame = try #require(extractProgressBar(layout.rows[0]))
        #expect(frame.value == 1.0, "FRAME bar value must clamp to 1.0; got \(frame.value)")
        #expect(frame.valueText == "15.3 ms")

        let quality = try #require(extractSingleValue(layout.rows[1]))
        #expect(quality.value == "no-bloom")
        #expect(colorMatches(quality.valueColor, DashboardTokens.Color.statusYellow))

        let ml = try #require(extractSingleValue(layout.rows[2]))
        #expect(ml.value == "WAIT 200ms")
        #expect(colorMatches(ml.valueColor, DashboardTokens.Color.statusYellow))
    }

    // MARK: d — forced dispatch + artifact

    @Test("forced dispatch snapshot produces green QUALITY, yellow FORCED ML + saves artifact")
    func build_forcedDispatch_producesYellowMLForced() throws {
        let snapshot = PerfSnapshot(
            recentMaxFrameMs: 11.2,
            recentFramesObserved: 30,
            targetFrameMs: 14,
            qualityLevelRawValue: 0,
            qualityLevelDisplayName: "full",
            mlDecisionCode: 3,
            mlDeferRetryMs: 0
        )
        let layout = PerfCardBuilder().build(from: snapshot)

        let frame = try #require(extractProgressBar(layout.rows[0]))
        #expect(frame.value >= 0.79 && frame.value <= 0.81,
                "Expected FRAME ≈ 0.8; got \(frame.value)")
        #expect(frame.valueText == "11.2 ms")

        let quality = try #require(extractSingleValue(layout.rows[1]))
        #expect(quality.value == "full")
        #expect(colorMatches(quality.valueColor, DashboardTokens.Color.statusGreen))

        let ml = try #require(extractSingleValue(layout.rows[2]))
        #expect(ml.value == "FORCED")
        #expect(colorMatches(ml.valueColor, DashboardTokens.Color.statusYellow))

        // Artifact: render the active PERF card onto a 320×220 layer with
        // the deep-indigo backdrop and write to
        // .build/dash1_artifacts/card_perf_active.png. Skipped silently
        // when no Metal device is present.
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            withKnownIssue("No Metal device available") {}
            return
        }
        DashboardFontLoader.resetCacheForTesting()
        let res = DashboardFontLoader.resolveFonts(
            in: Bundle(for: PerfCardBuilderTestAnchor.self) as Bundle?
        )
        guard let layer = DashboardTextLayer(
            device: device, width: 320, height: 220, fontResolution: res
        ) else {
            withKnownIssue("Failed to create DashboardTextLayer") {}
            return
        }

        layer.beginFrame()
        // Deep-indigo backdrop (oklch ≈ 0.18 0.06 285) — same value used in
        // BeatCardBuilderTests / StemsCardBuilderTests so the three card
        // artifacts compose visually under M7-style review.
        let backdrop = NSColor(srgbRed: 0.060, green: 0.058, blue: 0.135, alpha: 1.0)
        layer.graphicsContext.saveGState()
        layer.graphicsContext.setFillColor(backdrop.cgColor)
        layer.graphicsContext.fill(CGRect(x: 0, y: 0, width: 320, height: 220))
        layer.graphicsContext.restoreGState()

        let renderer = DashboardCardRenderer()
        renderer.render(
            layout,
            at: CGPoint(x: 16, y: 12),
            on: layer,
            cgContext: layer.graphicsContext
        )

        guard let cb = queue.makeCommandBuffer() else {
            withKnownIssue("Failed to make command buffer") {}
            return
        }
        layer.commit(into: cb)
        cb.commit()
        cb.waitUntilCompleted()

        savePNGArtifact(layer.texture, name: "card_perf_active")
    }

    // MARK: e — frame time above budget clamps bar value at 1.0
    //
    // FRAME clamp authority lives in the builder for `.progressBar` (no
    // `range` field on the row variant) — in contrast to STEMS where clamp
    // authority is renderer-layer (D-084).

    @Test("frame time above budget clamps bar value at 1.0; valueText shows raw value")
    func build_frameTimeAboveBudget_clampsBarValueAtOne() throws {
        let snapshot = PerfSnapshot(
            recentMaxFrameMs: 42.0,
            recentFramesObserved: 10,
            targetFrameMs: 14,
            qualityLevelRawValue: 5,
            qualityLevelDisplayName: "mesh-0.5",
            mlDecisionCode: 0,
            mlDeferRetryMs: 0
        )
        let layout = PerfCardBuilder().build(from: snapshot)

        let frame = try #require(extractProgressBar(layout.rows[0]))
        #expect(frame.value == 1.0, "FRAME bar value must clamp to 1.0; got \(frame.value)")
        #expect(frame.valueText == "42.0 ms")
    }

    // MARK: f — width override

    @Test("width override is passed through to the layout")
    func build_widthOverride_passesThrough() {
        let layout = PerfCardBuilder().build(from: .zero, width: 320)
        #expect(layout.width == 320)
    }
}

// MARK: - Artifact helper

private func savePNGArtifact(_ texture: MTLTexture, name: String) {
    let artifactDir = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".build/dash1_artifacts")
    try? FileManager.default.createDirectory(at: artifactDir,
                                              withIntermediateDirectories: true)
    let url = artifactDir.appendingPathComponent("\(name).png")
    if writeTextureToPNG(texture, url: url) != nil {
        print("PerfCardBuilderTests: artifact saved → \(url.path)")
    } else {
        print("PerfCardBuilderTests: PNG write failed for \(name)")
    }
}

// MARK: - Bundle anchor

private final class PerfCardBuilderTestAnchor {}

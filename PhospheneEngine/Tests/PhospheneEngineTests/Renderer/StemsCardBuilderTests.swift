// StemsCardBuilderTests — 6 @Test functions covering StemFeatures →
// DashboardCardLayout mapping (DASH.4).
//
// Switch-pattern row extraction + sRGB-channel colour comparison mirror
// the BeatCardBuilderTests pattern (file-independence convention; no
// hoisted shared helpers).

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

private func extractBar(_ row: DashboardCardLayout.Row)
    -> (label: String, value: Float, valueText: String,
        fillColor: NSColor, range: ClosedRange<Float>)? {
    if case let .bar(label, value, valueText, fillColor, range) = row {
        return (label, value, valueText, fillColor, range)
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

@Suite("StemsCardBuilder")
struct StemsCardBuilderTests {

    // MARK: a — zero snapshot → all-zero bars

    @Test("zero snapshot produces 4 zero-valued coral bars titled STEMS")
    func build_zeroSnapshot_producesAllZeroBars() throws {
        let layout = StemsCardBuilder().build(from: .zero)

        #expect(layout.title == "STEMS")
        #expect(layout.rows.count == 4)

        let expectedLabels = ["DRUMS", "BASS", "VOCALS", "OTHER"]
        for (idx, expectedLabel) in expectedLabels.enumerated() {
            let row = try #require(extractBar(layout.rows[idx]))
            #expect(row.label == expectedLabel)
            #expect(row.value == 0)
            #expect(row.valueText == "+0.00")
            #expect(colorMatches(row.fillColor, DashboardTokens.Color.coral))
            #expect(row.range == -1.0 ... 1.0)
        }
    }

    // MARK: b — positive drums

    @Test("positive drumsEnergyRel sets DRUMS bar value and signed valueText")
    func build_positiveDrums_setsBarValueAndText() throws {
        var stems = StemFeatures.zero
        stems.drumsEnergyRel = 0.42
        let layout = StemsCardBuilder().build(from: stems)

        let drums = try #require(extractBar(layout.rows[0]))
        #expect(drums.label == "DRUMS")
        #expect(drums.value == 0.42)
        #expect(drums.valueText == "+0.42")

        // Other rows still 0
        for idx in 1...3 {
            let row = try #require(extractBar(layout.rows[idx]))
            #expect(row.value == 0)
            #expect(row.valueText == "+0.00")
        }
    }

    // MARK: c — negative bass

    @Test("negative bassEnergyRel sets BASS bar value and signed valueText")
    func build_negativeBass_setsBarValueAndText() throws {
        var stems = StemFeatures.zero
        stems.bassEnergyRel = -0.30
        let layout = StemsCardBuilder().build(from: stems)

        let bass = try #require(extractBar(layout.rows[1]))
        #expect(bass.label == "BASS")
        #expect(bass.value == -0.30)
        #expect(bass.valueText == "-0.30")
    }

    // MARK: d — mixed snapshot → row order + payload mapping + artifact

    @Test("mixed snapshot produces correct row order DRUMS/BASS/VOCALS/OTHER + saves artifact")
    func build_mixedSnapshot_rowOrderAndPayloadsCorrect() throws {
        var stems = StemFeatures.zero
        stems.drumsEnergyRel  = 0.5
        stems.bassEnergyRel   = -0.4
        stems.vocalsEnergyRel = 0.2
        stems.otherEnergyRel  = -0.1
        let layout = StemsCardBuilder().build(from: stems)

        let drums = try #require(extractBar(layout.rows[0]))
        #expect(drums.label == "DRUMS")
        #expect(drums.value == 0.5)
        #expect(drums.valueText == "+0.50")

        let bass = try #require(extractBar(layout.rows[1]))
        #expect(bass.label == "BASS")
        #expect(bass.value == -0.4)
        #expect(bass.valueText == "-0.40")

        let vocals = try #require(extractBar(layout.rows[2]))
        #expect(vocals.label == "VOCALS")
        #expect(vocals.value == 0.2)
        #expect(vocals.valueText == "+0.20")

        let other = try #require(extractBar(layout.rows[3]))
        #expect(other.label == "OTHER")
        #expect(other.value == -0.1)
        #expect(other.valueText == "-0.10")

        // Artifact: render the active STEMS card onto a 320×220 layer with
        // the deep-indigo backdrop and write to
        // .build/dash1_artifacts/card_stems_active.png. Skipped silently
        // when no Metal device is present.
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            withKnownIssue("No Metal device available") {}
            return
        }
        DashboardFontLoader.resetCacheForTesting()
        let res = DashboardFontLoader.resolveFonts(
            in: Bundle(for: StemsCardBuilderTestAnchor.self) as Bundle?
        )
        guard let layer = DashboardTextLayer(
            device: device, width: 320, height: 220, fontResolution: res
        ) else {
            withKnownIssue("Failed to create DashboardTextLayer") {}
            return
        }

        layer.beginFrame()
        // Deep-indigo backdrop (oklch ≈ 0.18 0.06 285) — same value used in
        // BeatCardBuilderTests so artifacts compose visually.
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

        savePNGArtifact(layer.texture, name: "card_stems_active")
    }

    // MARK: e — values pass through unclamped at the builder layer

    @Test("large value passes through unclamped — clamp authority is in the renderer (drawBarFill)")
    func build_largeValue_passesThroughUnclampedAtBuilderLayer() throws {
        var stems = StemFeatures.zero
        stems.drumsEnergyRel = 1.5  // above range upper bound
        let layout = StemsCardBuilder().build(from: stems)

        let drums = try #require(extractBar(layout.rows[0]))
        // Builder is pure pass-through; renderer's drawBarFill clamps to range.
        #expect(drums.value == 1.5)
        #expect(drums.range == -1.0 ... 1.0)
    }

    // MARK: f — width override

    @Test("width override is passed through to the layout")
    func build_widthOverride_passesThrough() {
        let layout = StemsCardBuilder().build(from: .zero, width: 320)
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
        print("StemsCardBuilderTests: artifact saved → \(url.path)")
    } else {
        print("StemsCardBuilderTests: PNG write failed for \(name)")
    }
}

// MARK: - Bundle anchor

private final class StemsCardBuilderTestAnchor {}

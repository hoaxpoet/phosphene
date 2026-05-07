// DashboardCardRendererTests — 6 @Test functions covering layout math + rendering.
//
// Post-/impeccable redesign (DASH.2.1): rows stack their label above their
// value. The pair variant is gone. Bar rows render label-on-top, then bar +
// value text on a single line below.
//
// All Metal-touching tests skip with withKnownIssue("No Metal device available") {}
// when MTLCreateSystemDefaultDevice() returns nil. Silent skips would
// disappear the regression surface (CLAUDE.md "What NOT To Do").
//
// Pixel format: DashboardTextLayer uses .bgra8Unorm. getBytes() returns
// bytes in [B, G, R, A] order per pixel on Apple Silicon.

import CoreGraphics
import Foundation
import Metal
import Testing
@testable import Renderer
@testable import Shared

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Helpers

private func pixelAt(_ x: Int, _ y: Int, in bytes: [UInt8], width: Int) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
    let idx = (y * width + x) * 4
    return (bytes[idx], bytes[idx + 1], bytes[idx + 2], bytes[idx + 3])
}

private func readPixels(_ texture: MTLTexture) -> [UInt8] {
    let count = texture.width * texture.height * 4
    var bytes = [UInt8](repeating: 0, count: count)
    texture.getBytes(&bytes,
                     bytesPerRow: texture.width * 4,
                     from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                     mipmapLevel: 0)
    return bytes
}

private func makeLayerAndQueue(width: Int, height: Int)
    -> (DashboardTextLayer, MTLCommandQueue)? {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue  = device.makeCommandQueue() else { return nil }
    DashboardFontLoader.resetCacheForTesting()
    let res = DashboardFontLoader.resolveFonts(
        in: Bundle(for: DashboardCardRendererTestAnchor.self) as Bundle?
    )
    guard let layer = DashboardTextLayer(
        device: device, width: width, height: height, fontResolution: res
    ) else { return nil }
    return (layer, queue)
}

/// Paint a representative deep-indigo backdrop into the layer's CGContext
/// before the card draws. The production card floats over a moving
/// visualizer; rendering the artifact onto a transparent black canvas
/// underrepresents the card chrome's purple tint. A simulated mid-tone
/// backdrop makes the artifact accurately reflect production conditions.
private func paintVisualizerBackdrop(into ctx: CGContext, width: Int, height: Int) {
    // oklch(0.18 0.06 285) ≈ deep desaturated indigo, similar to a calm
    // ambient frame from VolumetricLithograph or Starburst at low energy.
    let backdrop = NSColor(srgbRed: 0.060, green: 0.058, blue: 0.135, alpha: 1.0)
    ctx.saveGState()
    ctx.setFillColor(backdrop.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.restoreGState()
}

private func renderFrame(
    layer: DashboardTextLayer,
    queue: MTLCommandQueue,
    drawBackdrop: Bool = false,
    draws: (DashboardTextLayer, CGContext) -> Void
) -> [UInt8]? {
    layer.beginFrame()
    if drawBackdrop {
        paintVisualizerBackdrop(into: layer.graphicsContext,
                                width: layer.texture.width,
                                height: layer.texture.height)
    }
    draws(layer, layer.graphicsContext)
    guard let cb = queue.makeCommandBuffer() else { return nil }
    layer.commit(into: cb)
    cb.commit()
    cb.waitUntilCompleted()
    return readPixels(layer.texture)
}

/// Pixel with maximum chroma in a 3-pixel column centred on `x`. Bar
/// background and foreground are both opaque, so alpha alone cannot
/// distinguish them — chroma can. Mitigates edge-pixel brittleness when the
/// fill boundary lands on the prescribed sample column.
private func maxChromaPixel(around x: Int, y: Int, in bytes: [UInt8], width: Int)
    -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
    func chroma(_ p: (b: UInt8, g: UInt8, r: UInt8, a: UInt8)) -> Int {
        Int(max(p.r, max(p.g, p.b))) - Int(min(p.r, min(p.g, p.b)))
    }
    var best = pixelAt(max(0, min(width - 1, x - 1)), y, in: bytes, width: width)
    var bestChroma = chroma(best)
    for dx in 0 ... 1 {
        let xx = max(0, min(width - 1, x + dx))
        let pix = pixelAt(xx, y, in: bytes, width: width)
        let cc = chroma(pix)
        if cc > bestChroma { best = pix; bestChroma = cc }
    }
    return best
}

/// Approximate luma (Rec. 601) for a BGRA byte tuple.
private func luma(_ pix: (b: UInt8, g: UInt8, r: UInt8, a: UInt8)) -> Int {
    (299 * Int(pix.r) + 587 * Int(pix.g) + 114 * Int(pix.b)) / 1000
}

// MARK: - Fixtures

private let kCanvasW = 360
private let kCanvasH = 280
private let kCardWidth: CGFloat = 280

/// Demo card representing the Beat panel: MODE / BPM / BAR / BASS.
/// Matches the row order requested in the DASH.2.1 redesign feedback.
private func beatCardFixture() -> DashboardCardLayout {
    DashboardCardLayout(
        title: "BEAT",
        rows: [
            .singleValue(label: "MODE", value: "LOCKED",
                         valueColor: DashboardTokens.Color.statusGreen),
            .singleValue(label: "BPM",  value: "125",
                         valueColor: DashboardTokens.Color.textHeading),
            .singleValue(label: "BAR",  value: "3 / 4",
                         valueColor: DashboardTokens.Color.textHeading),
            .bar(label: "BASS", value: 0.42, valueText: "+0.42",
                 fillColor: DashboardTokens.Color.coral, range: -1.0 ... 1.0)
        ],
        width: kCardWidth
    )
}

// MARK: - Tests

@Suite("DashboardCardRenderer")
struct DashboardCardRendererTests {

    // MARK: a — layout height matches sum

    @Test("layout.height matches padding + title + (rowSpacing + rowHeight)×N + padding")
    func layoutHeight_matchesSumOfRows() {
        let layout = beatCardFixture()
        let pad = DashboardTokens.Spacing.md
        let title = DashboardTokens.TypeScale.label
        let spacing = DashboardTokens.Spacing.xs
        let expected = pad
            + title
            + spacing + DashboardCardLayout.Row.singleHeight
            + spacing + DashboardCardLayout.Row.singleHeight
            + spacing + DashboardCardLayout.Row.singleHeight
            + spacing + DashboardCardLayout.Row.barHeight
            + pad
        #expect(layout.height == expected,
                "Expected card height \(expected), got \(layout.height)")
    }

    // MARK: b — beat-card render + artifact

    @Test("render beat card paints title, all rows, and stops at declared height")
    func render_beatCard_pixelVerifyLabelPositions() throws {
        guard let (layer, queue) = makeLayerAndQueue(width: kCanvasW, height: kCanvasH) else {
            withKnownIssue("No Metal device available") {}
            return
        }
        let layout = beatCardFixture()
        let origin = CGPoint(x: 16, y: 12)
        let renderer = DashboardCardRenderer()

        let bytes = try #require(renderFrame(
            layer: layer, queue: queue, drawBackdrop: true
        ) { textLayer, ctx in
            renderer.render(layout, at: origin, on: textLayer, cgContext: ctx)
        })

        // Title row: opaque glyphs in the title strip.
        let titleStripY = Int(origin.y + layout.padding + layout.titleSize / 2)
        var titleAlphaSeen: UInt8 = 0
        for x in Int(origin.x + layout.padding) ..< Int(origin.x + 80) {
            let pix = pixelAt(x, titleStripY, in: bytes, width: kCanvasW)
            titleAlphaSeen = max(titleAlphaSeen, pix.a)
        }
        #expect(titleAlphaSeen > 200, "Title row produced no visible glyph")

        // Below the card: only the backdrop (no card paint).
        let outsideY = Int(origin.y + layout.height + 4)
        var maxLumaOutside = 0
        for x in Int(origin.x) ..< Int(origin.x + layout.width) {
            maxLumaOutside = max(maxLumaOutside, luma(pixelAt(x, outsideY, in: bytes, width: kCanvasW)))
        }
        // Backdrop luma is ~13. Card chrome / glyphs would push >25.
        #expect(maxLumaOutside < 25,
                "Card painted past declared height; max luma at y=\(outsideY) was \(maxLumaOutside)")

        savePNGArtifact(layer.texture, name: "card_beat")
    }

    // MARK: c — right-edge clipping

    @Test("card placed near right edge does not overflow with text glyphs")
    func render_cardNearRightEdge_clipsCorrectly() throws {
        let canvasWidth = 512
        let canvasHeight = 280
        guard let (layer, queue) = makeLayerAndQueue(width: canvasWidth, height: canvasHeight) else {
            withKnownIssue("No Metal device available") {}
            return
        }
        let layout = beatCardFixture()
        let origin = CGPoint(x: CGFloat(canvasWidth) - kCardWidth, y: 12)
        let renderer = DashboardCardRenderer()

        let bytes = try #require(renderFrame(
            layer: layer, queue: queue, drawBackdrop: true
        ) { textLayer, ctx in
            renderer.render(layout, at: origin, on: textLayer, cgContext: ctx)
        })

        // Rightmost column: chrome + 1 px border at the edge are allowed
        // (low-luma surfaceRaised). A stray text glyph would push luma >60.
        let rightCol = canvasWidth - 1
        let sampleYs = [20, 40, 60, 80, 100, 120, 140]
        for y in sampleYs {
            let pix = pixelAt(rightCol, y, in: bytes, width: canvasWidth)
            #expect(luma(pix) < 60,
                    "Rightmost-column luma \(luma(pix)) at y=\(y) suggests text overflow")
        }
    }

    // MARK: d — negative bar fills left of bar centre

    @Test("bar row with negative value fills left of bar centre with the requested colour")
    func render_barRow_negativeValueFillsLeft() throws {
        guard let (layer, queue) = makeLayerAndQueue(width: kCanvasW, height: kCanvasH) else {
            withKnownIssue("No Metal device available") {}
            return
        }
        let layout = DashboardCardLayout(
            title: "STEMS",
            rows: [
                .bar(label: "BASS", value: -0.5, valueText: "-0.50",
                     fillColor: DashboardTokens.Color.coral, range: -1.0 ... 1.0)
            ],
            width: kCardWidth
        )
        let origin = CGPoint(x: 16, y: 12)
        let renderer = DashboardCardRenderer()

        let bytes = try #require(renderFrame(layer: layer, queue: queue) { textLayer, ctx in
            renderer.render(layout, at: origin, on: textLayer, cgContext: ctx)
        })

        let geometry = barGeometry(for: layout, at: origin)
        let leftSampleX  = Int(geometry.barLeft + geometry.barWidth / 4)
        let rightSampleX = Int(geometry.barLeft + 3 * geometry.barWidth / 4)
        let barCentreY   = Int(geometry.barCentreY)

        let leftPix = maxChromaPixel(around: leftSampleX, y: barCentreY,
                                     in: bytes, width: kCanvasW)
        #expect(leftPix.r > leftPix.g && leftPix.r > leftPix.b,
                "Left-half pixel does not look coral: B=\(leftPix.b) G=\(leftPix.g) R=\(leftPix.r)")

        let rightPix = maxChromaPixel(around: rightSampleX, y: barCentreY,
                                      in: bytes, width: kCanvasW)
        #expect(Int(rightPix.r) - max(Int(rightPix.g), Int(rightPix.b)) < 20,
                "Right-half pixel looks coral-tinted: B=\(rightPix.b) G=\(rightPix.g) R=\(rightPix.r)")
    }

    // MARK: e — positive bar fills right of bar centre

    @Test("bar row with positive value fills right of bar centre with the requested colour")
    func render_barRow_positiveValueFillsRight() throws {
        guard let (layer, queue) = makeLayerAndQueue(width: kCanvasW, height: kCanvasH) else {
            withKnownIssue("No Metal device available") {}
            return
        }
        let layout = DashboardCardLayout(
            title: "STEMS",
            rows: [
                .bar(label: "DRUMS", value: 0.5, valueText: "+0.50",
                     fillColor: DashboardTokens.Color.coral, range: -1.0 ... 1.0)
            ],
            width: kCardWidth
        )
        let origin = CGPoint(x: 16, y: 12)
        let renderer = DashboardCardRenderer()

        let bytes = try #require(renderFrame(layer: layer, queue: queue) { textLayer, ctx in
            renderer.render(layout, at: origin, on: textLayer, cgContext: ctx)
        })

        let geometry = barGeometry(for: layout, at: origin)
        let leftSampleX  = Int(geometry.barLeft + geometry.barWidth / 4)
        let rightSampleX = Int(geometry.barLeft + 3 * geometry.barWidth / 4)
        let barCentreY   = Int(geometry.barCentreY)

        let rightPix = maxChromaPixel(around: rightSampleX, y: barCentreY,
                                      in: bytes, width: kCanvasW)
        #expect(rightPix.r > rightPix.g && rightPix.r > rightPix.b,
                "Right-half pixel does not look coral: B=\(rightPix.b) G=\(rightPix.g) R=\(rightPix.r)")

        let leftPix = maxChromaPixel(around: leftSampleX, y: barCentreY,
                                     in: bytes, width: kCanvasW)
        #expect(Int(leftPix.r) - max(Int(leftPix.g), Int(leftPix.b)) < 20,
                "Left-half pixel looks coral-tinted: B=\(leftPix.b) G=\(leftPix.g) R=\(leftPix.r)")
    }

    // MARK: f — single-value row stacks label above value

    @Test("single-value row stacks label above value (label baseline above value baseline)")
    func render_singleValueRow_stacksLabelAboveValue() throws {
        guard let (layer, queue) = makeLayerAndQueue(width: kCanvasW, height: kCanvasH) else {
            withKnownIssue("No Metal device available") {}
            return
        }
        let layout = DashboardCardLayout(
            title: "",
            rows: [
                .singleValue(label: "BPM", value: "125",
                             valueColor: DashboardTokens.Color.textHeading)
            ],
            width: kCardWidth
        )
        let origin = CGPoint(x: 16, y: 12)
        let renderer = DashboardCardRenderer()

        let bytes = try #require(renderFrame(layer: layer, queue: queue) { textLayer, ctx in
            renderer.render(layout, at: origin, on: textLayer, cgContext: ctx)
        })

        // Find the y-row of the FIRST opaque text pixel and the LAST one
        // within the card's content band, on the left side where label and
        // value both sit.
        let scanX0 = Int(origin.x + layout.padding)
        let scanX1 = scanX0 + 80
        let yMin = Int(origin.y + layout.padding)
        let yMax = Int(origin.y + layout.height - layout.padding)

        var firstY: Int? = nil
        var lastY: Int? = nil
        for y in yMin ..< yMax {
            var rowHasGlyph = false
            for x in scanX0 ..< scanX1 {
                let pix = pixelAt(x, y, in: bytes, width: kCanvasW)
                // Glyph = high-luma (textBody / textHeading), not chrome.
                if luma(pix) > 80 { rowHasGlyph = true; break }
            }
            if rowHasGlyph {
                if firstY == nil { firstY = y }
                lastY = y
            }
        }

        let f = try #require(firstY)
        let l = try #require(lastY)
        // Stacked layout: vertical span between top of label glyphs and
        // bottom of value glyphs is at least the gap + label height.
        #expect(l - f >= 12,
                "Label and value should be vertically separated; got span \(l - f)")
    }
}

// MARK: - Bar geometry helper

private struct BarGeometry {
    let barLeft: CGFloat
    let barWidth: CGFloat
    let barCentreY: CGFloat
}

private func barGeometry(for layout: DashboardCardLayout, at origin: CGPoint) -> BarGeometry {
    let pad = layout.padding
    let titleStripBottom = origin.y + pad + (layout.title.isEmpty ? 0 : layout.titleSize)
    let rowTopY = titleStripBottom + layout.rowSpacing
    let barAreaY = rowTopY + DashboardTokens.TypeScale.label
        + DashboardCardLayout.labelToValueGap
    let barCentreY = barAreaY + 17 / 2
    let leftX = origin.x + pad
    let rightX = origin.x + layout.width - pad
    let valueColumnWidth: CGFloat = 56
    let valueColumnGap: CGFloat = 8
    let barRightLimit = rightX - valueColumnWidth - valueColumnGap
    let barAreaWidth = barRightLimit - leftX
    return BarGeometry(barLeft: leftX, barWidth: barAreaWidth, barCentreY: barCentreY)
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
        print("DashboardCardRendererTests: artifact saved → \(url.path)")
    } else {
        print("DashboardCardRendererTests: PNG write failed for \(name)")
    }
}

// MARK: - Bundle anchor

private final class DashboardCardRendererTestAnchor {}

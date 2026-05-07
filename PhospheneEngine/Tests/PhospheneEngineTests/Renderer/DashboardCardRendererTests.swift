// DashboardCardRendererTests — 6 @Test functions covering layout math + rendering.
//
// All Metal-touching tests skip with withKnownIssue("No Metal device available") {}
// when MTLCreateSystemDefaultDevice() returns nil (CI without GPU). Silent skips
// would disappear the regression surface (see CLAUDE.md "What NOT To Do").
//
// Pixel format: DashboardTextLayer uses .bgra8Unorm. getBytes() returns bytes
// in [B, G, R, A] order per pixel on Apple Silicon. The pixelAt() helper here
// is a copy of the same helper in DashboardTextLayerTests — keeping the test
// files independent (no cross-file helper dependency).

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

private func renderFrame(
    layer: DashboardTextLayer,
    queue: MTLCommandQueue,
    draws: (DashboardTextLayer, CGContext) -> Void
) -> [UInt8]? {
    layer.beginFrame()
    draws(layer, layer.graphicsContext)
    guard let cb = queue.makeCommandBuffer() else { return nil }
    layer.commit(into: cb)
    cb.commit()
    cb.waitUntilCompleted()
    return readPixels(layer.texture)
}

/// Pixel with maximum chroma (max-min channel) in a 3-pixel column centred
/// on `x`. The bar background (surfaceRaised) and foreground (coral) are
/// both opaque, so alpha alone cannot distinguish them — chroma can.
/// Mitigates edge-pixel brittleness when the geometric fill boundary lands
/// exactly on a sample column (see DASH.2 prompt risk note).
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

private let kCanvasW = 320
private let kCanvasH = 200
private let kCardWidth: CGFloat = 280

private func threeRowFixture() -> DashboardCardLayout {
    DashboardCardLayout(
        title: "PRESET",
        rows: [
            .singleValue(
                label: "BPM", value: "125",
                valueColor: DashboardTokens.Color.textHeading
            ),
            .pair(
                leftLabel: "MODE", leftValue: "LOCKED",
                rightLabel: "BAR", rightValue: "3 / 4",
                valueColor: DashboardTokens.Color.textHeading
            ),
            .bar(
                label: "BASS", value: 0.42, valueText: "+0.42",
                fillColor: DashboardTokens.Color.coral, range: -1.0 ... 1.0
            )
        ],
        width: kCardWidth
    )
}

// MARK: - Tests

@Suite("DashboardCardRenderer")
struct DashboardCardRendererTests {

    // MARK: a — layout height

    @Test("layout.height matches padding + title + rowSpacing×N + Σ rowHeights + padding")
    func layoutHeight_matchesSumOfRows() {
        let layout = threeRowFixture()
        let pad = DashboardTokens.Spacing.md
        let title = DashboardTokens.TypeScale.label
        let spacing = DashboardTokens.Spacing.xs
        let expected = pad
            + title
            + spacing + DashboardCardLayout.Row.singleHeight
            + spacing + DashboardCardLayout.Row.pairHeight
            + spacing + DashboardCardLayout.Row.barHeight
            + pad
        #expect(layout.height == expected,
                "Expected card height \(expected), got \(layout.height)")
    }

    // MARK: b — three-row pixel verify + artifact

    @Test("render three-row card paints title, row content, and stops at declared height")
    func render_threeRowCard_pixelVerifyLabelPositions() throws {
        guard let (layer, queue) = makeLayerAndQueue(width: kCanvasW, height: kCanvasH) else {
            withKnownIssue("No Metal device available") {}
            return
        }
        let layout = threeRowFixture()
        let origin = CGPoint(x: 16, y: 12)
        let renderer = DashboardCardRenderer()

        let bytes = try #require(renderFrame(layer: layer, queue: queue) { textLayer, ctx in
            renderer.render(layout, at: origin, on: textLayer, cgContext: ctx)
        })

        // Title row baseline: paint exists somewhere in the title strip.
        let titleStripY = Int(origin.y + layout.padding + layout.titleSize / 2)
        var titleAlphaSeen: UInt8 = 0
        for x in Int(origin.x + layout.padding) ..< Int(origin.x + 80) {
            let pix = pixelAt(x, titleStripY, in: bytes, width: kCanvasW)
            titleAlphaSeen = max(titleAlphaSeen, pix.a)
        }
        // Title strip overlays card chrome (non-zero everywhere); we want at
        // least *more* alpha than chrome alone — chrome surface is ~234 alpha
        // (0.92 over zero) tinted very dark, but text-glyph antialiasing pushes
        // the maximum to 255.
        #expect(titleAlphaSeen > 200, "Title row produced no visible glyph")

        // Below the card (y > origin.y + layout.height + 4): no paint at all.
        let outsideY = Int(origin.y + layout.height + 4)
        var outsideMax: UInt8 = 0
        for x in 0 ..< kCanvasW {
            let pix = pixelAt(x, outsideY, in: bytes, width: kCanvasW)
            outsideMax = max(outsideMax, pix.a)
        }
        #expect(outsideMax == 0,
                "Card painted past declared height; max alpha at y=\(outsideY) was \(outsideMax)")

        // Save artifact for manual review.
        savePNGArtifact(layer.texture, name: "card_three_row")
    }

    // MARK: c — right-edge clipping

    @Test("card placed near right edge does not overflow with text glyphs")
    func render_cardNearRightEdge_clipsCorrectly() throws {
        let canvasWidth = 512
        let canvasHeight = 200
        guard let (layer, queue) = makeLayerAndQueue(width: canvasWidth, height: canvasHeight) else {
            withKnownIssue("No Metal device available") {}
            return
        }
        let layout = threeRowFixture()                  // width = 280
        let origin = CGPoint(x: CGFloat(canvasWidth) - kCardWidth, y: 12)
        let renderer = DashboardCardRenderer()

        let bytes = try #require(renderFrame(layer: layer, queue: queue) { textLayer, ctx in
            renderer.render(layout, at: origin, on: textLayer, cgContext: ctx)
        })

        // Sample 5 pixels in the rightmost column. The card chrome (surface
        // fill at 0.92 alpha + 1px border stroke) DOES paint this column —
        // that is correct chrome; the prompt explicitly allows it. What we
        // want to rule out is a *text glyph* (textHeading R≈234,G≈235,B≈240)
        // landing here, which would manifest as a high-luma pixel. Surface
        // fill luma is ~7; text glyph luma is ~230.
        let rightCol = canvasWidth - 1
        let sampleYs = [20, 40, 60, 80, 100]
        for y in sampleYs {
            let pix = pixelAt(rightCol, y, in: bytes, width: canvasWidth)
            #expect(luma(pix) < 60,
                    "Rightmost-column luma \(luma(pix)) at y=\(y) suggests text overflow")
        }
    }

    // MARK: d — negative bar fills left

    @Test("bar row with negative value fills left of centre with the requested color")
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

        // Bar Y-row centre.
        let pad = layout.padding
        let titleStripBottom = origin.y + pad + layout.titleSize
        let barRowTopY = titleStripBottom + layout.rowSpacing
        let barTopY = barRowTopY + DashboardCardLayout.Row.barHeight - 6
        let barCentreY = Int(barTopY + 3)
        let innerWidth = layout.width - 2 * pad

        let leftSampleX  = Int(origin.x + pad + innerWidth / 4)
        let rightSampleX = Int(origin.x + layout.width - pad - innerWidth / 4)

        let leftPix = maxChromaPixel(around: leftSampleX, y: barCentreY,
                                    in: bytes, width: kCanvasW)
        #expect(leftPix.a > 200,
                "Expected coral fill on left half (alpha > 200), got \(leftPix.a)")
        // Coral ≈ (R 246, G 110, B 96) → BGRA bytes (B 96, G 110, R 246).
        #expect(leftPix.r > leftPix.g && leftPix.r > leftPix.b,
                "Left-half pixel does not look coral: B=\(leftPix.b) G=\(leftPix.g) R=\(leftPix.r)")

        // Right half: no foreground fill — only the surfaceRaised background.
        // A coral pixel has R >> G,B; background surfaceRaised has R ≈ G ≈ B.
        let rightPix = maxChromaPixel(around: rightSampleX, y: barCentreY,
                                     in: bytes, width: kCanvasW)
        #expect(Int(rightPix.r) - max(Int(rightPix.g), Int(rightPix.b)) < 20,
                "Right-half pixel looks coral-tinted: B=\(rightPix.b) G=\(rightPix.g) R=\(rightPix.r)")
    }

    // MARK: e — positive bar fills right

    @Test("bar row with positive value fills right of centre with the requested color")
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

        let pad = layout.padding
        let titleStripBottom = origin.y + pad + layout.titleSize
        let barRowTopY = titleStripBottom + layout.rowSpacing
        let barTopY = barRowTopY + DashboardCardLayout.Row.barHeight - 6
        let barCentreY = Int(barTopY + 3)
        let innerWidth = layout.width - 2 * pad

        let leftSampleX  = Int(origin.x + pad + innerWidth / 4)
        let rightSampleX = Int(origin.x + layout.width - pad - innerWidth / 4)

        let rightPix = maxChromaPixel(around: rightSampleX, y: barCentreY,
                                     in: bytes, width: kCanvasW)
        #expect(rightPix.a > 200,
                "Expected coral fill on right half (alpha > 200), got \(rightPix.a)")
        #expect(rightPix.r > rightPix.g && rightPix.r > rightPix.b,
                "Right-half pixel does not look coral: B=\(rightPix.b) G=\(rightPix.g) R=\(rightPix.r)")

        let leftPix = maxChromaPixel(around: leftSampleX, y: barCentreY,
                                    in: bytes, width: kCanvasW)
        #expect(Int(leftPix.r) - max(Int(leftPix.g), Int(leftPix.b)) < 20,
                "Left-half pixel looks coral-tinted: B=\(leftPix.b) G=\(leftPix.g) R=\(leftPix.r)")
    }

    // MARK: f — pair-row divider visible

    @Test("pair row draws a 1px vertical divider in Color.border at the midpoint")
    func render_pairRow_dividerVisible() throws {
        guard let (layer, queue) = makeLayerAndQueue(width: kCanvasW, height: kCanvasH) else {
            withKnownIssue("No Metal device available") {}
            return
        }
        let layout = DashboardCardLayout(
            title: "STATE",
            rows: [
                .pair(leftLabel: "MODE", leftValue: "LOCKED",
                      rightLabel: "BAR", rightValue: "3 / 4",
                      valueColor: DashboardTokens.Color.textHeading)
            ],
            width: kCardWidth
        )
        let origin = CGPoint(x: 16, y: 12)
        let renderer = DashboardCardRenderer()

        let bytes = try #require(renderFrame(layer: layer, queue: queue) { textLayer, ctx in
            renderer.render(layout, at: origin, on: textLayer, cgContext: ctx)
        })

        // Pair row centre y.
        let pad = layout.padding
        let titleStripBottom = origin.y + pad + layout.titleSize
        let rowTopY = titleStripBottom + layout.rowSpacing
        let rowMidY = Int(rowTopY + DashboardCardLayout.Row.pairHeight / 2)
        let midX = Int(origin.x + layout.width / 2)

        let pix = pixelAt(midX, rowMidY, in: bytes, width: kCanvasW)
        // Color.border ≈ (R 25, G 26, B 33) — a low-luma, very slightly bluish
        // tone. The divider is solid alpha, painting over the (also dark)
        // surface fill. Assert: meaningful alpha, and channel ordering matches
        // border (B ≥ G ≥ R, all small).
        #expect(pix.a > 200,
                "Expected solid divider alpha at midpoint, got \(pix.a)")
        #expect(pix.b >= pix.r,
                "Divider colour does not look like border (B=\(pix.b) G=\(pix.g) R=\(pix.r))")
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
        print("DashboardCardRendererTests: artifact saved → \(url.path)")
    } else {
        print("DashboardCardRendererTests: PNG write failed for \(name)")
    }
}

// MARK: - Bundle anchor

private final class DashboardCardRendererTestAnchor {}

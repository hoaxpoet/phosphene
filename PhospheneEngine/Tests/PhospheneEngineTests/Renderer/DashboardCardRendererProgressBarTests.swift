// DashboardCardRendererProgressBarTests — 3 @Test functions covering the
// `.progressBar` row variant (DASH.3).
//
// Helpers (pixelAt / readPixels / makeLayerAndQueue / renderFrame /
// maxChromaPixel / barGeometry) are duplicated locally rather than hoisted
// into a shared file — file-independence convention from
// DashboardCardRendererTests, see DASH.3 prompt §5.
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

// MARK: - Helpers (local copies; see file header)

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
        in: Bundle(for: DashboardCardRendererProgressBarTestAnchor.self) as Bundle?
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

private func looksCoral(_ pix: (b: UInt8, g: UInt8, r: UInt8, a: UInt8)) -> Bool {
    pix.r > pix.g && pix.r > pix.b
        && Int(pix.r) - max(Int(pix.g), Int(pix.b)) > 20
}

// MARK: - Fixtures

private let kCanvasW = 360
private let kCanvasH = 120
private let kCardWidth: CGFloat = 280

private func progressBarFixture(value: Float) -> DashboardCardLayout {
    DashboardCardLayout(
        title: "",
        rows: [
            .progressBar(label: "BEAT", value: value, valueText: "—",
                         fillColor: DashboardTokens.Color.coral)
        ],
        width: kCardWidth
    )
}

// MARK: - Tests

@Suite("DashboardCardRenderer.ProgressBar")
struct DashboardCardRendererProgressBarTests {

    // MARK: a — value 0 draws no foreground

    @Test("progressBar value=0 draws background only (no coral foreground anywhere)")
    func progressBar_value0_drawsNoForeground() throws {
        guard let (layer, queue) = makeLayerAndQueue(width: kCanvasW, height: kCanvasH) else {
            withKnownIssue("No Metal device available") {}
            return
        }
        let layout = progressBarFixture(value: 0)
        let origin = CGPoint(x: 16, y: 12)
        let renderer = DashboardCardRenderer()

        let bytes = try #require(renderFrame(layer: layer, queue: queue) { textLayer, ctx in
            renderer.render(layout, at: origin, on: textLayer, cgContext: ctx)
        })

        let geometry = barGeometry(for: layout, at: origin)
        let y = Int(geometry.barCentreY)
        for fraction in [0.25, 0.5, 0.75] {
            let x = Int(geometry.barLeft + CGFloat(fraction) * geometry.barWidth)
            let pix = maxChromaPixel(around: x, y: y, in: bytes, width: kCanvasW)
            #expect(!looksCoral(pix),
                    "Expected no coral fill at fraction=\(fraction); got B=\(pix.b) G=\(pix.g) R=\(pix.r)")
        }
    }

    // MARK: b — value 1 fills full bar width

    @Test("progressBar value=1 fills full bar width with coral")
    func progressBar_value1_fillsFullBarWidth() throws {
        guard let (layer, queue) = makeLayerAndQueue(width: kCanvasW, height: kCanvasH) else {
            withKnownIssue("No Metal device available") {}
            return
        }
        let layout = progressBarFixture(value: 1.0)
        let origin = CGPoint(x: 16, y: 12)
        let renderer = DashboardCardRenderer()

        let bytes = try #require(renderFrame(layer: layer, queue: queue) { textLayer, ctx in
            renderer.render(layout, at: origin, on: textLayer, cgContext: ctx)
        })

        let geometry = barGeometry(for: layout, at: origin)
        let y = Int(geometry.barCentreY)
        for fraction in [0.25, 0.5, 0.75] {
            let x = Int(geometry.barLeft + CGFloat(fraction) * geometry.barWidth)
            let pix = maxChromaPixel(around: x, y: y, in: bytes, width: kCanvasW)
            #expect(looksCoral(pix),
                    "Expected coral fill at fraction=\(fraction); got B=\(pix.b) G=\(pix.g) R=\(pix.r)")
        }
    }

    // MARK: c — value 0.5 fills left half only

    @Test("progressBar value=0.5 fills the left half; right half stays unfilled")
    func progressBar_valueHalf_fillsLeftHalfOnly() throws {
        guard let (layer, queue) = makeLayerAndQueue(width: kCanvasW, height: kCanvasH) else {
            withKnownIssue("No Metal device available") {}
            return
        }
        let layout = progressBarFixture(value: 0.5)
        let origin = CGPoint(x: 16, y: 12)
        let renderer = DashboardCardRenderer()

        let bytes = try #require(renderFrame(layer: layer, queue: queue) { textLayer, ctx in
            renderer.render(layout, at: origin, on: textLayer, cgContext: ctx)
        })

        let geometry = barGeometry(for: layout, at: origin)
        let y = Int(geometry.barCentreY)
        let leftX = Int(geometry.barLeft + geometry.barWidth / 3)        // ~33% — must be coral
        let rightX = Int(geometry.barLeft + 2 * geometry.barWidth / 3)   // ~67% — must NOT be coral

        let leftPix = maxChromaPixel(around: leftX, y: y, in: bytes, width: kCanvasW)
        #expect(looksCoral(leftPix),
                "Expected coral at one-third; got B=\(leftPix.b) G=\(leftPix.g) R=\(leftPix.r)")

        let rightPix = maxChromaPixel(around: rightX, y: y, in: bytes, width: kCanvasW)
        #expect(!looksCoral(rightPix),
                "Expected no coral at two-thirds; got B=\(rightPix.b) G=\(rightPix.g) R=\(rightPix.r)")
    }
}

// MARK: - Bundle anchor

private final class DashboardCardRendererProgressBarTestAnchor {}

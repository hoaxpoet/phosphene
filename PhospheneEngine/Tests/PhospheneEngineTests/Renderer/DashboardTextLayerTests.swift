// DashboardTextLayerTests — 5 @Test functions verifying rendering behaviour.
//
// All tests require MTLCreateSystemDefaultDevice(); they are skipped with
// withKnownIssue when no Metal device is available (CI without GPU).
//
// Pixel format: DashboardTextLayer uses .bgra8Unorm.
// getBytes() returns bytes in [B, G, R, A] order per pixel on Apple Silicon.
// Helper pixelAt(_:_:in:width:) returns a (b, g, r, a) tuple.

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

/// Read one pixel from a .bgra8Unorm texture. Returns (b, g, r, a) UInt8 components.
private func pixelAt(_ x: Int, _ y: Int, in bytes: [UInt8], width: Int) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
    let idx = (y * width + x) * 4
    return (bytes[idx], bytes[idx + 1], bytes[idx + 2], bytes[idx + 3])
}

/// Read all pixels from a .bgra8Unorm MTLTexture into a flat UInt8 array.
private func readPixels(_ texture: MTLTexture) -> [UInt8] {
    let count = texture.width * texture.height * 4
    var bytes = [UInt8](repeating: 0, count: count)
    texture.getBytes(&bytes,
                     bytesPerRow: texture.width * 4,
                     from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                     mipmapLevel: 0)
    return bytes
}

/// Count pixels whose alpha component exceeds `threshold`.
private func countWithAlpha(above threshold: UInt8, in bytes: [UInt8]) -> Int {
    stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > threshold }.count
}

/// Count pixels whose alpha component is below `threshold`.
private func countWithAlpha(below threshold: UInt8, in bytes: [UInt8]) -> Int {
    stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] < threshold }.count
}

// MARK: - Fixture setup

/// Width / height used by all layer tests — small enough for fast tests.
private let kTestWidth  = 512
private let kTestHeight = 256

private func makeLayerAndQueue() -> (DashboardTextLayer, MTLCommandQueue)? {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue  = device.makeCommandQueue() else { return nil }
    DashboardFontLoader.resetCacheForTesting()
    let res = DashboardFontLoader.resolveFonts(
        in: Bundle(for: DashboardTextLayerTestAnchor.self) as Bundle?
    )
    guard let layer = DashboardTextLayer(
        device: device, width: kTestWidth, height: kTestHeight, fontResolution: res
    ) else { return nil }
    return (layer, queue)
}

/// Commit one frame with the given draw block, wait, and return pixels.
private func renderFrame(
    layer: DashboardTextLayer,
    queue: MTLCommandQueue,
    draws: (DashboardTextLayer) -> Void
) -> [UInt8]? {
    layer.beginFrame()
    draws(layer)
    guard let cb = queue.makeCommandBuffer() else { return nil }
    layer.commit(into: cb)
    cb.commit()
    cb.waitUntilCompleted()
    return readPixels(layer.texture)
}

// MARK: - Tests

@Suite("DashboardTextLayer")
struct DashboardTextLayerTests {

    // MARK: Test 1 — mono text produces non-uniform texture

    @Test("drawText mono produces non-uniform texture coverage")
    func drawText_mono_producesNonUniformTexture() throws {
        guard let (layer, queue) = makeLayerAndQueue() else {
            withKnownIssue("No Metal device available") {}
            return
        }

        let bytes = try #require(renderFrame(layer: layer, queue: queue) { layer in
            layer.drawText(
                "TEMPO 125",
                at: CGPoint(x: 20, y: 20),
                size: DashboardTokens.TypeScale.display,
                weight: .medium,
                font: .mono,
                color: DashboardTokens.Color.textPrimary
            )
        })

        let totalPixels = kTestWidth * kTestHeight
        let opaqueCount = countWithAlpha(above: 127, in: bytes)
        let clearCount  = countWithAlpha(below: 25,  in: bytes)

        // At least 0.5% of pixels have meaningful alpha — text was drawn.
        // "TEMPO 125" at 36pt on a 512×256 canvas produces ~1.2% opaque pixels;
        // thin monospaced strokes + antialiasing makes this lower than naive bounding-box estimates.
        let opaqueFraction = Double(opaqueCount) / Double(totalPixels)
        #expect(opaqueFraction >= 0.005,
                "Expected ≥0.5% opaque pixels, got \(String(format: "%.2f", opaqueFraction * 100))%")

        // At least 50% of pixels are clear — canvas is not flooded.
        let clearFraction = Double(clearCount) / Double(totalPixels)
        #expect(clearFraction >= 0.50,
                "Expected ≥50% clear pixels, got \(String(format: "%.1f", clearFraction * 100))%")

        // Save artifact for manual review.
        savePNGArtifact(layer.texture, name: "text_layer_sample")
    }

    // MARK: Test 2 — prose text renders

    @Test("drawText prose renders non-uniform texture")
    func drawText_prose_renders() throws {
        guard let (layer, queue) = makeLayerAndQueue() else {
            withKnownIssue("No Metal device available") {}
            return
        }

        let bytes = try #require(renderFrame(layer: layer, queue: queue) { layer in
            layer.drawText(
                "Spectral Cartograph",
                at: CGPoint(x: 20, y: 20),
                size: DashboardTokens.TypeScale.body,
                weight: .regular,
                font: .prose,
                color: DashboardTokens.Color.textSecondary
            )
        })

        let totalPixels = kTestWidth * kTestHeight
        let opaqueCount = countWithAlpha(above: 127, in: bytes)
        let clearCount  = countWithAlpha(below: 25,  in: bytes)

        // 13pt prose on a 512×256 canvas produces ~0.15% opaque pixels.
        #expect(Double(opaqueCount) / Double(totalPixels) >= 0.001)
        #expect(Double(clearCount)  / Double(totalPixels) >= 0.50)
    }

    // MARK: Test 3 — beginFrame clears between frames

    @Test("drawText clears between frames")
    func drawText_clearsBetweenFrames() throws {
        guard let (layer, queue) = makeLayerAndQueue() else {
            withKnownIssue("No Metal device available") {}
            return
        }

        // First frame — draw something.
        _ = renderFrame(layer: layer, queue: queue) { layer in
            layer.drawText("AAA", at: .zero,
                           size: DashboardTokens.TypeScale.display,
                           weight: .regular, font: .mono,
                           color: DashboardTokens.Color.textPrimary)
        }

        // Second frame — beginFrame with no draws.
        let bytes = try #require(renderFrame(layer: layer, queue: queue) { _ in })

        // > 99% of pixels should have alpha < 13 (≈ 5%).
        let clearCount = countWithAlpha(below: 13, in: bytes)
        let totalPixels = kTestWidth * kTestHeight
        let clearFraction = Double(clearCount) / Double(totalPixels)
        #expect(clearFraction > 0.99,
                "Expected >99% clear after empty frame, got \(String(format: "%.1f", clearFraction * 100))%")
    }

    // MARK: Test 4 — alignment shifts render position

    @Test("drawText alignment shifts render position")
    func drawText_alignment() throws {
        guard let (layer, queue) = makeLayerAndQueue() else {
            withKnownIssue("No Metal device available") {}
            return
        }

        // Left-aligned at x=100: rightmost glyph column should be to the right of 100.
        let leftBytes = try #require(renderFrame(layer: layer, queue: queue) { layer in
            layer.drawText("X", at: CGPoint(x: 100, y: 50),
                           size: DashboardTokens.TypeScale.numeric,
                           weight: .regular, font: .mono,
                           color: DashboardTokens.Color.textPrimary,
                           align: .left)
        })

        // Right-aligned at x=100: rightmost glyph column should be at or before 100.
        let rightBytes = try #require(renderFrame(layer: layer, queue: queue) { layer in
            layer.drawText("X", at: CGPoint(x: 100, y: 50),
                           size: DashboardTokens.TypeScale.numeric,
                           weight: .regular, font: .mono,
                           color: DashboardTokens.Color.textPrimary,
                           align: .right)
        })

        func rightmostOpaqueColumn(_ bytes: [UInt8]) -> Int {
            var col = 0
            for x in 0 ..< kTestWidth {
                for y in 0 ..< kTestHeight {
                    let pix = pixelAt(x, y, in: bytes, width: kTestWidth)
                    if pix.a > 64 { col = max(col, x) }
                }
            }
            return col
        }

        let leftCol  = rightmostOpaqueColumn(leftBytes)
        let rightCol = rightmostOpaqueColumn(rightBytes)

        // Left-aligned text extends further right than right-aligned text at the same x.
        #expect(leftCol > rightCol + 5,
                "Expected left-aligned rightmost col (\(leftCol)) > right-aligned (\(rightCol)) + 5")
    }

    // MARK: Test 5 — color is applied to output

    @Test("drawText color applies to rendered pixels")
    func drawText_color_appliesToOutput() throws {
        guard let (layer, queue) = makeLayerAndQueue() else {
            withKnownIssue("No Metal device available") {}
            return
        }

        // Draw teal text (R≈0.18, G≈0.77, B≈0.71) in a predictable location.
        let bytes = try #require(renderFrame(layer: layer, queue: queue) { layer in
            layer.drawText(
                "████████",
                at: CGPoint(x: 20, y: 100),
                size: DashboardTokens.TypeScale.display,
                weight: .medium,
                font: .mono,
                color: DashboardTokens.Color.teal
            )
        })

        // Find a pixel with meaningful alpha and sample its BGRA channels.
        // .bgra8Unorm layout: index 0=B, 1=G, 2=R, 3=A.
        var foundTealPixel = false
        for y in 80 ..< min(160, kTestHeight) {
            for x in 20 ..< min(300, kTestWidth) {
                let pix = pixelAt(x, y, in: bytes, width: kTestWidth)
                if pix.a > 64 {
                    // G (index 1) should exceed R (index 2) and B (index 0) for teal.
                    if pix.g > pix.r && pix.g > pix.b {
                        foundTealPixel = true
                        break
                    }
                }
            }
            if foundTealPixel { break }
        }

        #expect(foundTealPixel, "No teal-colored pixel (G > R and G > B) found in expected region")
    }
}

// MARK: - Artifact helper

private func savePNGArtifact(_ texture: MTLTexture, name: String) {
    let artifactDir = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()   // Renderer/
        .deletingLastPathComponent()   // PhospheneEngineTests/
        .deletingLastPathComponent()   // Tests/
        .deletingLastPathComponent()   // PhospheneEngine/
        .appendingPathComponent(".build/dash1_artifacts")

    try? FileManager.default.createDirectory(at: artifactDir,
                                              withIntermediateDirectories: true)
    let url = artifactDir.appendingPathComponent("\(name).png")
    if writeTextureToPNG(texture, url: url) != nil {
        print("DashboardTextLayerTests: artifact saved → \(url.path)")
    } else {
        print("DashboardTextLayerTests: PNG write failed for \(name)")
    }
}

// MARK: - Bundle anchor

private final class DashboardTextLayerTestAnchor {}

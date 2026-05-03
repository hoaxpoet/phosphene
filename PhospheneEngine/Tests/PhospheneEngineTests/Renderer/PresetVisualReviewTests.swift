// PresetVisualReviewTests — On-demand visual review harness for Phosphene presets.
//
// Renders a named preset at 1920×1280 for three audio fixtures (silence, steady
// mid-energy, beat-heavy), encodes each frame to PNG, and (for Arachne only)
// composes a contact sheet alongside the four must-pass references.
//
// Gated behind RENDER_VISUAL=1 so it stays out of normal CI / `swift test` runs.
//
// Invocation:
//   RENDER_VISUAL=1 swift test --package-path PhospheneEngine \
//       --filter PresetVisualReview
//
// Output: /tmp/phosphene_visual/<ISO8601>/<preset>_{silence,mid,beat}.png
//         /tmp/phosphene_visual/<ISO8601>/<preset>_contact_sheet.png  (Arachne only)
//
// See V.7.6.1 in docs/ENGINEERING_PLAN.md and D-072 in docs/DECISIONS.md.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit
import simd
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - Suite

@Suite("PresetVisualReview")
struct PresetVisualReviewTests {

    // MARK: - Fixtures

    private var silenceFixture: FeatureVector {
        FeatureVector(time: 1.0, deltaTime: 1.0 / 60.0)
    }

    private var midFixture: FeatureVector {
        FeatureVector(bass: 0.50, mid: 0.50, treble: 0.50, time: 3.0, deltaTime: 1.0 / 60.0)
    }

    private var beatFixture: FeatureVector {
        var fv = FeatureVector(bass: 0.80, mid: 0.50, treble: 0.50,
                               beatBass: 1.0, time: 5.0, deltaTime: 1.0 / 60.0)
        fv.bassRel = 0.60
        fv.bassDev = 0.60
        return fv
    }

    // MARK: - Constants

    private static let renderWidth = 1920
    private static let renderHeight = 1280
    private static let outputRoot = "/tmp/phosphene_visual"

    private static let arachneReferenceRelPaths: [(label: String, path: String)] = [
        ("Ref 01", "docs/VISUAL_REFERENCES/arachne/01_macro_dewy_web_on_dark.jpg"),
        ("Ref 04", "docs/VISUAL_REFERENCES/arachne/04_specular_silk_fiber_highlight.jpg"),
        ("Ref 05", "docs/VISUAL_REFERENCES/arachne/05_lighting_backlit_atmosphere.jpg"),
        ("Ref 08", "docs/VISUAL_REFERENCES/arachne/08_palette_bioluminescent_organism.jpg"),
    ]

    // MARK: - Tests

    @Test("Render preset to PNGs + contact sheet (RENDER_VISUAL=1)",
          arguments: ["Arachne"])
    func renderPresetVisualReview(_ presetName: String) throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("[PresetVisualReview] RENDER_VISUAL not set, skipping \(presetName)")
            return
        }

        let ctx = try MetalContext()
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == presetName
        }) else {
            print("[PresetVisualReview] preset '\(presetName)' not found, skipping")
            return
        }
        guard !preset.descriptor.passes.contains(.meshShader) else {
            print("[PresetVisualReview] '\(presetName)' is mesh-shader, skipping")
            return
        }

        let outputDir = try makeOutputDirectory()
        print("[PresetVisualReview] output dir: \(outputDir.path)")

        // Per-preset state (currently only Arachne needs warmed buffers at 6/7).
        let arachneState: ArachneState? = {
            guard presetName == "Arachne" else { return nil }
            guard let state = ArachneState(device: ctx.device, seed: 42) else { return nil }
            let warmFV = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                       time: 1.0, deltaTime: 1.0 / 60.0)
            for _ in 0..<30 { state.tick(features: warmFV, stems: .zero) }
            return state
        }()

        let fixtures: [(name: String, fv: FeatureVector)] = [
            ("silence", silenceFixture),
            ("mid", midFixture),
            ("beat", beatFixture),
        ]

        var midPNGURL: URL?
        for index in 0..<fixtures.count {
            var fv = fixtures[index].fv
            let pixels = try renderFrame(preset: preset, context: ctx,
                                         arachneState: arachneState, features: &fv)
            let url = outputDir.appendingPathComponent(
                "\(presetName.replacingOccurrences(of: " ", with: "_"))_\(fixtures[index].name).png"
            )
            try writePNG(bgraPixels: pixels,
                         width: Self.renderWidth, height: Self.renderHeight,
                         to: url)
            print("[PresetVisualReview] wrote \(url.lastPathComponent)")
            if fixtures[index].name == "mid" { midPNGURL = url }
        }

        // Contact sheet — Arachne only (references are preset-specific).
        if presetName == "Arachne", let midURL = midPNGURL {
            let sheetURL = outputDir.appendingPathComponent("Arachne_contact_sheet.png")
            try buildArachneContactSheet(renderedMidPNG: midURL, to: sheetURL)
            print("[PresetVisualReview] wrote \(sheetURL.lastPathComponent)")
        }
    }

    // MARK: - Output directory

    private func makeOutputDirectory() throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = URL(fileURLWithPath: Self.outputRoot)
            .appendingPathComponent(stamp)
        try FileManager.default.createDirectory(at: url,
                                                withIntermediateDirectories: true)
        return url
    }

    // MARK: - Render

    private func renderFrame(
        preset: PresetLoader.LoadedPreset,
        context: MetalContext,
        arachneState: ArachneState?,
        features: inout FeatureVector
    ) throws -> [UInt8] {
        let width = Self.renderWidth
        let height = Self.renderHeight

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: texDesc) else {
            throw VisualReviewError.textureAllocationFailed
        }

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = context.makeSharedBuffer(length: 512 * floatStride),
            let wavBuf = context.makeSharedBuffer(length: 2048 * floatStride),
            let stemBuf = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let histBuf = context.makeSharedBuffer(length: 4096 * floatStride)
        else { throw VisualReviewError.bufferAllocationFailed }
        _ = stemBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                count: MemoryLayout<StemFeatures>.size)
        _ = histBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                count: 4096 * floatStride)

        var sceneBuf: MTLBuffer?
        if preset.descriptor.passes.contains(.rayMarch),
           let buf = context.makeSharedBuffer(length: MemoryLayout<SceneUniforms>.size) {
            var su = preset.descriptor.makeSceneUniforms()
            buf.contents().copyMemory(from: &su, byteCount: MemoryLayout<SceneUniforms>.size)
            sceneBuf = buf
        }

        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw VisualReviewError.commandBufferFailed
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            throw VisualReviewError.encoderCreationFailed
        }

        encoder.setRenderPipelineState(preset.pipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(fftBuf, offset: 0, index: 1)
        encoder.setFragmentBuffer(wavBuf, offset: 0, index: 2)
        encoder.setFragmentBuffer(stemBuf, offset: 0, index: 3)
        if let sceneBuf = sceneBuf {
            encoder.setFragmentBuffer(sceneBuf, offset: 0, index: 4)
        }
        encoder.setFragmentBuffer(histBuf, offset: 0, index: 5)

        if let arachneState = arachneState {
            encoder.setFragmentBuffer(arachneState.webBuffer, offset: 0, index: 6)
            encoder.setFragmentBuffer(arachneState.spiderBuffer, offset: 0, index: 7)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        guard cmdBuf.status == .completed else { throw VisualReviewError.renderFailed }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    // MARK: - PNG encoding

    private func writePNG(bgraPixels: [UInt8],
                          width: Int, height: Int,
                          to url: URL) throws {
        guard let cgImage = makeCGImage(bgraPixels: bgraPixels,
                                        width: width, height: height) else {
            throw VisualReviewError.cgImageFailed
        }
        try writeCGImage(cgImage, to: url)
    }

    private func makeCGImage(bgraPixels: [UInt8],
                             width: Int, height: Int) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgraPixels
        return copy.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> CGImage? in
            guard let base = ptr.baseAddress else { return nil }
            guard let ctx = CGContext(data: base,
                                      width: width, height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }

    private func writeCGImage(_ image: CGImage, to url: URL) throws {
        let type: CFString
        if #available(macOS 11.0, *) { type = UTType.png.identifier as CFString }
        else { type = "public.png" as CFString }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw VisualReviewError.pngWriteFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw VisualReviewError.pngWriteFailed
        }
    }

    // MARK: - Contact sheet (Arachne only)

    private func buildArachneContactSheet(renderedMidPNG: URL, to outURL: URL) throws {
        let sheetW = Self.renderWidth
        let sheetH = Self.renderHeight
        let topHalfH = sheetH / 2
        let cellW = sheetW / 4
        let cellH = sheetH / 2

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw VisualReviewError.cgImageFailed
        }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: nil,
                                  width: sheetW, height: sheetH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: sheetW * 4,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo.rawValue) else {
            throw VisualReviewError.cgImageFailed
        }

        // Black background.
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

        // Top half: rendered output letterboxed to fit (1920×640).
        if let renderedImage = loadCGImage(from: renderedMidPNG) {
            let topRect = CGRect(x: 0, y: cellH, width: sheetW, height: topHalfH)
            drawLetterboxed(image: renderedImage, in: topRect, ctx: ctx)
        }

        // Bottom half: 4 references each in a 480×640 cell.
        let projectRoot = projectRootURL()
        for (index, ref) in Self.arachneReferenceRelPaths.enumerated() {
            let url = projectRoot.appendingPathComponent(ref.path)
            let rect = CGRect(x: index * cellW, y: 0,
                              width: cellW, height: cellH)
            if let img = loadCGImage(from: url) {
                drawLetterboxed(image: img, in: rect, ctx: ctx)
            }
        }

        // Labels — render via NSGraphicsContext bridging to CGContext.
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        let labels: [(text: String, originX: Int, originY: Int)] = [
            ("Render: steady-mid", 12, sheetH - 24),
        ] + Self.arachneReferenceRelPaths.enumerated().map { index, ref in
            (ref.label, index * cellW + 12, cellH - 24)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.7),
        ]
        for label in labels {
            let attributed = NSAttributedString(string: " \(label.text) ", attributes: attrs)
            attributed.draw(at: NSPoint(x: label.originX, y: label.originY))
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else {
            throw VisualReviewError.cgImageFailed
        }
        try writeCGImage(cgImage, to: outURL)
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Draw `image` into `rect` preserving aspect ratio (letterboxed in black).
    private func drawLetterboxed(image: CGImage, in rect: CGRect, ctx: CGContext) {
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        let scale = min(rect.width / srcW, rect.height / srcH)
        let drawW = srcW * scale
        let drawH = srcH * scale
        let drawX = rect.origin.x + (rect.width - drawW) / 2
        let drawY = rect.origin.y + (rect.height - drawH) / 2
        ctx.draw(image, in: CGRect(x: drawX, y: drawY,
                                   width: drawW, height: drawH))
    }

    /// Walk up from `#filePath` to the project root (4 levels:
    /// PhospheneEngine/Tests/PhospheneEngineTests/Renderer/<file> → repo root).
    private func projectRootURL(file: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: file)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}

// MARK: - Errors

private enum VisualReviewError: Error {
    case textureAllocationFailed
    case bufferAllocationFailed
    case commandBufferFailed
    case encoderCreationFailed
    case renderFailed
    case cgImageFailed
    case pngWriteFailed
}

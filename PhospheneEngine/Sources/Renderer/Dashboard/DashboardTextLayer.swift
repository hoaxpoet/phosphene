// DashboardTextLayer — Batched CPU text rasterization for the Telemetry dashboard.
//
// Renders ~80 labels per frame (10 px axis ticks → 36 px hero numerics) into a single
// shared MTLTexture via Core Text + Core Graphics, matching the zero-copy approach
// of DynamicTextOverlay.
//
// Coordinate convention (inherits from DynamicTextOverlay, DSP.3.3):
//   A permanent CTM flip is applied in init: translateBy(0, height) + scaleBy(1, -1).
//   This makes the user coordinate space top-down (y=0 = top, y=height = bottom),
//   matching Metal UV convention. `drawText(at:)` takes a top-left origin.
//   The text matrix is pre-set to CGAffineTransform(scaleX:1, y:-1) in beginFrame()
//   to counteract Core Text mirroring in negative-determinant CTMs.
//   (Same fix as DSP.3.3 — see RELEASE_NOTES_DEV [DSP.3.3].)
//
// Pixel format:
//   The MTLBuffer uses kCGBitmapByteOrder32Little | premultipliedFirst which places
//   bytes as [B, G, R, A] on Apple Silicon (little-endian) — matching .bgra8Unorm.
//   The buffer-backed MTLTexture references the same physical pages; no blit needed
//   for the common path. commit(into:) accepts a command buffer for API compatibility
//   with future non-shared-memory backends.
//
// Thread safety:
//   All methods must be called from the render thread (same thread that encodes
//   the command buffer passed to commit(into:)).

import CoreGraphics
import CoreText
import Metal
import Shared
import os.log

#if canImport(AppKit)
import AppKit
#endif

// MARK: - LayerResources (private)

/// Internal triple allocated together for the zero-copy buffer→context→texture path.
private struct LayerResources {
    let buffer: MTLBuffer
    let context: CGContext
    let texture: MTLTexture
}

// MARK: - DashboardTextLayer

/// Batched-draw wrapper for the Telemetry dashboard text canvas.
///
/// Usage per frame:
/// ```swift
/// textLayer.beginFrame()
/// textLayer.drawText("125", at: CGPoint(x: 40, y: 20), size: .display, …)
/// textLayer.drawText("BPM",  at: CGPoint(x: 40, y: 58), size: .label,   …)
/// textLayer.commit(into: commandBuffer)
/// // bind textLayer.texture at the appropriate fragment texture slot
/// ```
public final class DashboardTextLayer: @unchecked Sendable {

    // MARK: - Public properties

    /// The Metal texture updated each frame. Bind to the appropriate fragment slot.
    /// Format: `.bgra8Unorm`, usage: `.shaderRead`, mode: `.storageModeShared`.
    public private(set) var texture: MTLTexture

    // MARK: - Private state

    private var cgContext: CGContext
    private var buffer: MTLBuffer          // Backing store shared by cgContext + texture
    private var currentWidth: Int
    private var currentHeight: Int
    private let fontResolution: DashboardFontLoader.FontResolution
    private let log = Logger(subsystem: "com.phosphene", category: "DashboardTextLayer")

    // MARK: - Init

    /// Create a text layer targeting the given drawable dimensions.
    ///
    /// - Parameters:
    ///   - device: The Metal device that will consume the texture.
    ///   - width: Canvas width in pixels.
    ///   - height: Canvas height in pixels.
    ///   - fontResolution: Result of `DashboardFontLoader.resolveFonts()`.
    public init?(device: MTLDevice, width: Int, height: Int,
                 fontResolution: DashboardFontLoader.FontResolution) {
        guard let res = DashboardTextLayer.makeResources(
            device: device, width: width, height: height
        ) else { return nil }
        self.buffer = res.buffer
        self.cgContext = res.context
        self.texture = res.texture
        self.currentWidth = width
        self.currentHeight = height
        self.fontResolution = fontResolution
        log.info("DashboardTextLayer: \(width)×\(height) bgra8 shared texture ready")
    }

    // MARK: - Public API

    /// Clear the canvas to transparent black. Call once at the start of each frame.
    public func beginFrame() {
        cgContext.clear(CGRect(x: 0, y: 0, width: currentWidth, height: currentHeight))
        // Counteract Core Text mirroring in negative-determinant CTMs.
        // The permanent CTM flip (scaleY=-1) makes det(CTM)=-1; CTLineDraw mirrors text
        // horizontally. Setting textMatrix scaleY=-1 gives det(CTM)*det(textMatrix)=+1
        // net determinant — text renders left-to-right, right-side-up.
        // Identical fix as DSP.3.3 DynamicTextOverlay — see RELEASE_NOTES_DEV [DSP.3.3].
        cgContext.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    }

    // swiftlint:disable function_parameter_count
    /// Draw a single text run at the given point.
    ///
    /// - Parameters:
    ///   - text: The string to render.
    ///   - point: Top-left origin in the top-down coordinate space (y=0 = canvas top).
    ///   - size: Point size (use a `DashboardTokens.TypeScale` constant).
    ///   - weight: `.regular` or `.medium`.
    ///   - font: `.mono` (SF Mono) or `.prose` (Epilogue / system fallback).
    ///   - color: Text color.
    ///   - align: Horizontal alignment relative to `point`.
    ///   - tracking: Additional kerning in Core Text units (0 = default).
    public func drawText(
        _ text: String,
        at point: CGPoint,
        size: CGFloat,
        weight: DashboardTokens.Weight,
        font: DashboardTokens.TextFont,
        color: NSColor,
        align: DashboardTokens.Alignment = .left,
        tracking: CGFloat = 0
    ) {
        let ctFont = resolveFont(font: font, size: size, weight: weight)
        let cgColor = color.cgColor

        var attrs: [CFString: Any] = [
            kCTFontAttributeName: ctFont,
            kCTForegroundColorAttributeName: cgColor,
        ]
        if tracking != 0 {
            attrs[kCTKernAttributeName] = tracking as CFNumber
        }

        guard let attrString = CFAttributedStringCreate(
            nil, text as CFString, attrs as CFDictionary
        ) else { return }
        let line = CTLineCreateWithAttributedString(attrString)

        // Compute x origin for alignment
        var drawX = point.x
        if align != .left {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            if align == .right {
                drawX = point.x - CGFloat(lineWidth)
            } else {
                drawX = point.x - CGFloat(lineWidth) / 2
            }
        }

        // In the flipped coordinate space y=0 is at the top. Core Text draws
        // relative to the baseline. Advance y by the ascent to place the top of
        // the glyph bounding box near `point.y`.
        var ascent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, nil, nil)
        let drawY = point.y + ascent

        cgContext.textPosition = CGPoint(x: drawX, y: drawY)
        CTLineDraw(line, cgContext)
    }
    // swiftlint:enable function_parameter_count

    /// Signal that the frame is complete.
    ///
    /// For shared-memory backends (Apple Silicon) the GPU reads the same physical
    /// pages the CPU just wrote — no transfer is required. The `commandBuffer`
    /// parameter is accepted for API compatibility with future non-shared backends.
    public func commit(into commandBuffer: MTLCommandBuffer) {
        // Shared storage mode: CPU writes are immediately visible to the GPU.
        // No blit encoder needed on Apple Silicon unified memory.
        _ = commandBuffer  // suppress unused-parameter warning
    }

    // MARK: - Internal access

    /// Internal access for renderers that need direct CGPath geometry
    /// (e.g. card chrome, bar charts). External callers must prefer
    /// `drawText`.
    internal var graphicsContext: CGContext { cgContext }

    /// Reallocate the canvas for a new drawable size.
    ///
    /// Call when the MTKView drawable size changes. Drops the existing buffer and
    /// creates fresh resources. The caller must re-bind `texture` after this call.
    public func resize(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        let device = texture.device
        guard let res = DashboardTextLayer.makeResources(
            device: device, width: width, height: height
        ) else {
            log.error("DashboardTextLayer: resize to \(width)×\(height) failed")
            return
        }
        buffer = res.buffer
        cgContext = res.context
        texture = res.texture
        currentWidth = width
        currentHeight = height
        log.info("DashboardTextLayer: resized to \(width)×\(height)")
    }

    // MARK: - Private helpers

    private func resolveFont(
        font: DashboardTokens.TextFont,
        size: CGFloat,
        weight: DashboardTokens.Weight
    ) -> CTFont {
        switch font {
        case .mono:
            let nsWeight: NSFont.Weight = weight == .medium ? .medium : .regular
            let nsFont = NSFont.monospacedSystemFont(ofSize: size, weight: nsWeight)
            return CTFontCreateWithName(nsFont.fontName as CFString, size, nil)
        case .prose:
            let name = weight == .medium
                ? fontResolution.proseMediumFontName
                : fontResolution.proseFontName
            return CTFontCreateWithName(name as CFString, size, nil)
        }
    }

    /// Allocates the shared MTLBuffer → CGContext → MTLTexture triple.
    private static func makeResources(device: MTLDevice, width: Int, height: Int) -> LayerResources? {
        let bytesPerRow = width * 4   // BGRA8 = 4 bytes per pixel

        guard let buf = device.makeBuffer(
            length: height * bytesPerRow,
            options: .storageModeShared
        ) else { return nil }

        // kCGBitmapByteOrder32Little | premultipliedFirst → BGRA byte order on
        // little-endian (Apple Silicon), matching .bgra8Unorm texture format.
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: buf.contents(),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        ctx.setShouldSmoothFonts(false)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)

        // Permanent CTM flip: user space has y=0 at the top, y=height at the bottom.
        // Core Text glyphs render right-side-up in this flipped space.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        desc.storageMode = .shared
        desc.usage = [.shaderRead]
        guard let tex = buf.makeTexture(descriptor: desc, offset: 0, bytesPerRow: bytesPerRow)
        else { return nil }

        return LayerResources(buffer: buf, context: ctx, texture: tex)
    }
}

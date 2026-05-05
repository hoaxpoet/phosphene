// DynamicTextOverlay — Per-frame CPU text rasterization into a zero-copy shared MTLTexture.
//
// Uses Core Text + Core Graphics to render real typographic text (any font family,
// size, weight) on top of Metal presets. Bound at texture(12) for presets that set
// `text_overlay: true` in their JSON descriptor.
//
// On Apple Silicon, the MTLBuffer backing the texture uses .storageModeShared — no
// CPU→GPU upload needed; the GPU reads directly from the same physical pages that
// Core Graphics wrote to.
//
// Coordinate convention:
//   A permanent CTM flip is applied in init: translateBy(0, height) + scaleBy(1, -1).
//   This makes the user coordinate space top-down (y=0 = screen top, y=height = bottom),
//   matching Metal's UV convention.  Core Text renders right-side-up in this space.
//   The Metal fragment shader samples WITHOUT Y-flip:
//       textOverlay.sample(s, float2(uv.x, uv.y))
//
// Thread safety:
//   `refresh(_:)` must be called on the render thread, before the draw command
//   buffer is encoded. GPU reads happen after command buffer commit.

import CoreGraphics
import CoreText
import Metal
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "DynamicTextOverlay")

// MARK: - DynamicTextOverlay

/// Zero-copy CPU→GPU text rendering backed by a shared MTLTexture.
///
/// Create once per preset that uses text; call `refresh(_:)` each frame;
/// the resulting texture is bound at fragment texture(12).
public final class DynamicTextOverlay: @unchecked Sendable {

    /// The Metal texture bound at fragment texture(12) in text-overlay presets.
    public let texture: MTLTexture

    /// Logical dimensions of the text canvas (equals the underlying texture size).
    public let width: Int
    public let height: Int

    private let cgContext: CGContext

    /// Create a `DynamicTextOverlay` backed by a 2 048 × 1 024 shared MTLTexture.
    ///
    /// Aspect ratio 2:1 matches the common 16:9 display aspect reasonably well;
    /// the wider canvas gives more horizontal room for panel header labels.
    public init?(device: MTLDevice, width: Int = 2048, height: Int = 1024) {
        let bytesPerRow = width * 4   // RGBA8 = 4 bytes per pixel
        guard let buf = device.makeBuffer(
            length: height * bytesPerRow,
            options: .storageModeShared
        ) else {
            logger.error("DynamicTextOverlay: failed to allocate \(height * bytesPerRow) byte buffer")
            return nil
        }

        // MTLTexture backed by the same allocation — zero-copy on Apple Silicon.
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false
        )
        desc.storageMode = .shared
        desc.usage = [.shaderRead]
        guard let tex = buf.makeTexture(descriptor: desc, offset: 0, bytesPerRow: bytesPerRow) else {
            logger.error("DynamicTextOverlay: failed to make texture from MTLBuffer")
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(
            data: buf.contents(),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            logger.error("DynamicTextOverlay: failed to create CGContext")
            return nil
        }

        // Disable antialiasing and font smoothing adjustments that can cause
        // alpha values outside [0, 1] on the premultiplied channel.
        ctx.setShouldSmoothFonts(false)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)

        // Apply a permanent Y-flip CTM so that the user coordinate system has
        // y=0 at the TOP (matching Metal UV y=0 = screen top) and y=height at
        // the BOTTOM.  Without this, CGBitmapContext's default lower-left origin
        // causes Core Text glyphs to render upside-down when viewed as a Metal
        // texture.  The Metal shader therefore samples with no Y-flip.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        self.texture = tex
        self.cgContext = ctx
        self.width = width
        self.height = height
        logger.info("DynamicTextOverlay: \(width)×\(height) rgba8 shared texture ready")
    }

    // MARK: - Public API

    /// Clear the canvas and invoke `callback` to populate it for this frame.
    ///
    /// The callback receives the `CGContext` (top-left origin, Y down — matching Metal UV
    /// convention after the permanent CTM flip applied in `init`) and the canvas size.
    /// Text drawn there appears in the Metal render when the fragment shader samples
    /// `texture(12)` with `float2(uv.x, uv.y)` (no additional Y-flip needed in the shader).
    ///
    /// The text matrix is pre-set to `CGAffineTransform(scaleX: 1, y: -1)` so that Core Text
    /// renders glyphs right-side-up and left-to-right in the flipped coordinate system.
    /// Without this, the CTM's negative determinant causes Core Text to mirror text
    /// horizontally. Callers should NOT reset the text matrix to `.identity`.
    ///
    /// Must be called on the **render thread**, before encoding the draw call.
    public func refresh(_ callback: (CGContext, CGSize) -> Void) {
        cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        // Counteract Core Text's horizontal mirroring in negative-determinant CTMs.
        // The CTM scaleY=-1 makes det(CTM)=-1; CTLineDraw detects this and renders
        // text mirrored. Setting textMatrix scaleY=-1 makes det(textMatrix)=-1, giving
        // det(CTM) * det(textMatrix) = +1 net determinant — text renders left-to-right.
        cgContext.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        callback(cgContext, CGSize(width: width, height: height))
    }
}

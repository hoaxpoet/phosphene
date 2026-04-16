// TextureToPNG — Utility to write MTLTexture contents to a PNG file.
//
// Supports `.bgra8Unorm_srgb` (BGRA→RGBA swizzle) and `.rgba16Float`
// (Float16→Float32 conversion, Reinhard tone mapping, gamma 2.2).

import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Write a Metal texture to a PNG file for visual inspection.
/// Returns the URL on success, nil on failure.
@discardableResult
func writeTextureToPNG(_ texture: MTLTexture, url: URL) -> URL? {
    let width  = texture.width
    let height = texture.height
    guard width > 0, height > 0 else { return nil }

    let rgbaBytes: [UInt8]

    switch texture.pixelFormat {
    case .bgra8Unorm_srgb, .bgra8Unorm:
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&raw,
                         bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height),
                         mipmapLevel: 0)
        // BGRA → RGBA swizzle
        for i in stride(from: 0, to: raw.count, by: 4) {
            let b = raw[i], r = raw[i + 2]
            raw[i] = r; raw[i + 2] = b
        }
        rgbaBytes = raw

    case .rgba16Float:
        var raw16 = [UInt16](repeating: 0, count: width * height * 4)
        texture.getBytes(&raw16,
                         bytesPerRow: width * 4 * MemoryLayout<UInt16>.size,
                         from: MTLRegionMake2D(0, 0, width, height),
                         mipmapLevel: 0)
        // Float16 → Float32 → Reinhard tone map → gamma 2.2 → UInt8
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0 ..< raw16.count {
            var half = raw16[i]
            var full: Float = 0
            memcpy(&full, &half, 0) // placeholder, use vImage below
            // Manual Float16 → Float32
            let sign     = (half >> 15) & 0x1
            let exponent = (half >> 10) & 0x1F
            let mantissa = half & 0x3FF
            if exponent == 0 {
                full = (sign == 1 ? -1.0 : 1.0) * Float(mantissa) / 1024.0 * pow(2.0, -14.0)
            } else if exponent == 31 {
                full = mantissa == 0 ? (sign == 1 ? -.infinity : .infinity) : .nan
            } else {
                full = (sign == 1 ? -1.0 : 1.0) * (1.0 + Float(mantissa) / 1024.0)
                     * pow(2.0, Float(exponent) - 15.0)
            }

            let comp = i % 4
            if comp == 3 {
                // Alpha: clamp to [0, 1]
                out[i] = UInt8(min(max(full, 0), 1) * 255)
            } else {
                // Reinhard tone map + gamma
                let mapped = max(full, 0) / (1.0 + max(full, 0))
                let gamma  = pow(mapped, 1.0 / 2.2)
                out[i] = UInt8(min(gamma * 255, 255))
            }
        }
        rgbaBytes = out

    default:
        return nil
    }

    // Create CGImage
    guard let provider = CGDataProvider(data: Data(rgbaBytes) as CFData) else { return nil }
    guard let cgImage = CGImage(
        width: width, height: height,
        bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil, shouldInterpolate: false,
        intent: .defaultIntent
    ) else { return nil }

    // Write PNG via ImageIO
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }

    return url
}

// ImagingPrimitives.swift — Generic image loading + per-pixel operations.
//
// Everything the visual-grading proxies need to operate on an image:
//   - Load an image from URL → RGBA8 byte buffer at a canonical analysis
//     resolution.
//   - Compute per-pixel quantities (luma, hue, value) and aggregate stats
//     (histogram, variance, centroid, region masks).
//   - Spatial-frequency analysis on 1D strips (horizontal/vertical) via DFT.
//
// SR.1 design notes:
//   - Canonical analysis resolution: 480 × 320 (CanonicalAnalysisSize). All
//     loaded images downsample to this; proxies run on identical-sized
//     buffers regardless of source. Keeps proxies aspect-stable across
//     references at different aspect ratios + the rendered output's 1.5:1.
//   - Hue is computed in degrees [0, 360); achromatic pixels (low
//     saturation) are excluded from hue histograms so they don't poison
//     "green-dominant" measurements.
//   - All public API is `Sendable`. Proxies can run in parallel if needed.

// Pixel + spatial-FFT math leans on single-letter coordinate / channel names
// (x, y, r, g, b, h) — clearer than verbose alternatives in this context.
// Same convention as Shared/AudioFeatures+Analyzed.swift +
// Renderer/Geometry/ProceduralGeometry.swift. The identifier_name lint rule
// is scoped-disabled around the math blocks below (paired with explicit
// re-enable) per project convention (blanket_disable_command rule).

import CoreImage
import Foundation
import ImageIO
import CoreGraphics

/// Canonical analysis resolution. All loaded images downsample to this.
public struct CanonicalAnalysisSize: Sendable {
    public static let width = 480
    public static let height = 320
}

// swiftlint:disable identifier_name

/// An image at canonical analysis resolution, RGBA8.
public struct RGBAImage: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]   // RGBA, row-major, top-left origin

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Pixel index (start byte) at (x, y).
    @inlinable
    public func offset(x: Int, y: Int) -> Int {
        (y * width + x) * 4
    }

    /// Rec.709 luma at (x, y), 0..1.
    @inlinable
    public func luma(x: Int, y: Int) -> Double {
        let o = offset(x: x, y: y)
        return (0.2126 * Double(pixels[o])
              + 0.7152 * Double(pixels[o + 1])
              + 0.0722 * Double(pixels[o + 2])) / 255.0
    }

    /// HSV hue at (x, y), 0..360 degrees. Returns NaN for achromatic pixels
    /// (saturation < `minSaturation`).
    @inlinable
    public func hueDegrees(x: Int, y: Int, minSaturation: Double = 0.15) -> Double {
        let o = offset(x: x, y: y)
        let r = Double(pixels[o]) / 255.0
        let g = Double(pixels[o + 1]) / 255.0
        let b = Double(pixels[o + 2]) / 255.0
        let maxc = max(r, max(g, b))
        let minc = min(r, min(g, b))
        let delta = maxc - minc
        if maxc < 0.01 || delta / max(maxc, 1e-6) < minSaturation {
            return .nan  // achromatic
        }
        var h: Double
        if maxc == r {
            h = (g - b) / delta
        } else if maxc == g {
            h = 2.0 + (b - r) / delta
        } else {
            h = 4.0 + (r - g) / delta
        }
        h *= 60.0
        if h < 0 { h += 360.0 }
        return h
    }
}

// MARK: - Loading

public enum ImageLoaderError: Error, CustomStringConvertible {
    case fileNotFound(URL)
    case imageCreateFailure(URL)
    case contextCreateFailure

    public var description: String {
        switch self {
        case .fileNotFound(let url): return "File not found: \(url.path)"
        case .imageCreateFailure(let url): return "ImageIO failed to load: \(url.path)"
        case .contextCreateFailure: return "Failed to create CGContext for downsampling"
        }
    }
}

public enum ImageLoader {

    /// Load any common image (PNG/JPEG) at `url`, downsample to canonical
    /// analysis resolution. Aspect is NOT preserved — the entire source
    /// image rescales to fill the 480×320 canvas. This keeps proxies
    /// stable across source aspect ratios.
    public static func loadCanonical(_ url: URL) throws -> RGBAImage {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageLoaderError.fileNotFound(url)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ImageLoaderError.imageCreateFailure(url)
        }
        let w = CanonicalAnalysisSize.width
        let h = CanonicalAnalysisSize.height
        let cs = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &bytes,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageLoaderError.contextCreateFailure
        }
        // CoreGraphics draws bottom-left origin; we want top-left so we flip.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return RGBAImage(width: w, height: h, pixels: bytes)
    }
}

// MARK: - Aggregate stats

public extension RGBAImage {

    /// Mean luma over the entire image.
    func meanLuma() -> Double {
        var sum = 0.0
        for y in 0..<height {
            for x in 0..<width { sum += luma(x: x, y: y) }
        }
        return sum / Double(width * height)
    }

    /// Hue histogram, `bins` equally-spaced over [0, 360). Achromatic
    /// pixels (low saturation) are excluded. Returns per-bin counts.
    func hueHistogram(bins: Int = 36, lumaThreshold: Double = 0.10) -> [Int] {
        var hist = [Int](repeating: 0, count: bins)
        let binWidth = 360.0 / Double(bins)
        for y in 0..<height {
            for x in 0..<width {
                guard luma(x: x, y: y) >= lumaThreshold else { continue }
                let h = hueDegrees(x: x, y: y)
                if h.isNaN { continue }
                let b = min(bins - 1, Int(h / binWidth))
                hist[b] += 1
            }
        }
        return hist
    }

    /// For each row, return the circular variance of hue across columns.
    /// Pixels below `lumaThreshold` or achromatic are skipped.
    /// Returns one value per row; rows with < `minSamples` valid pixels
    /// return NaN.
    func perRowCircularHueVariance(lumaThreshold: Double = 0.10, minSamples: Int = 16) -> [Double] {
        var result = [Double](repeating: .nan, count: height)
        for y in 0..<height {
            var sumCos = 0.0
            var sumSin = 0.0
            var count = 0
            for x in 0..<width {
                guard luma(x: x, y: y) >= lumaThreshold else { continue }
                let h = hueDegrees(x: x, y: y)
                if h.isNaN { continue }
                let rad = h * .pi / 180.0
                sumCos += cos(rad)
                sumSin += sin(rad)
                count += 1
            }
            if count >= minSamples {
                let r = sqrt(sumCos * sumCos + sumSin * sumSin) / Double(count)
                // Circular variance ∈ [0, 1]: 0 = perfectly aligned, 1 = uniform.
                result[y] = 1.0 - r
            }
        }
        return result
    }

    /// For each column, return the circular variance of hue across rows.
    func perColumnCircularHueVariance(lumaThreshold: Double = 0.10, minSamples: Int = 16) -> [Double] {
        var result = [Double](repeating: .nan, count: width)
        for x in 0..<width {
            var sumCos = 0.0
            var sumSin = 0.0
            var count = 0
            for y in 0..<height {
                guard luma(x: x, y: y) >= lumaThreshold else { continue }
                let h = hueDegrees(x: x, y: y)
                if h.isNaN { continue }
                let rad = h * .pi / 180.0
                sumCos += cos(rad)
                sumSin += sin(rad)
                count += 1
            }
            if count >= minSamples {
                let r = sqrt(sumCos * sumCos + sumSin * sumSin) / Double(count)
                result[x] = 1.0 - r
            }
        }
        return result
    }

    /// Per-row mean luma (length == height). Used for vertical envelope
    /// gradient + edge detection.
    func perRowMeanLuma() -> [Double] {
        var result = [Double](repeating: 0, count: height)
        for y in 0..<height {
            var sum = 0.0
            for x in 0..<width { sum += luma(x: x, y: y) }
            result[y] = sum / Double(width)
        }
        return result
    }

    /// Per-column mean luma (length == width).
    func perColumnMeanLuma() -> [Double] {
        var result = [Double](repeating: 0, count: width)
        for x in 0..<width {
            var sum = 0.0
            for y in 0..<height { sum += luma(x: x, y: y) }
            result[x] = sum / Double(height)
        }
        return result
    }

    /// Brightness centroid in normalized coordinates [0, 1] × [0, 1].
    /// Top-left origin.
    func brightnessCentroid() -> (x: Double, y: Double) {
        var sumW = 0.0
        var sumX = 0.0
        var sumY = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let w = luma(x: x, y: y)
                sumW += w
                sumX += w * Double(x)
                sumY += w * Double(y)
            }
        }
        guard sumW > 0 else { return (0.5, 0.5) }
        return (sumX / sumW / Double(width - 1),
                sumY / sumW / Double(height - 1))
    }

    /// Fraction of pixels with luma < `threshold` within the rows
    /// [yFrac × height, height).
    func darkFractionInBottomBand(fractionFromBottom: Double = 0.2, lumaThreshold: Double = 0.08) -> Double {
        let yLo = height - max(1, Int(Double(height) * fractionFromBottom))
        var dark = 0
        var total = 0
        for y in yLo..<height {
            for x in 0..<width {
                total += 1
                if luma(x: x, y: y) < lumaThreshold { dark += 1 }
            }
        }
        return total == 0 ? 0 : Double(dark) / Double(total)
    }

    /// Stddev of luma within pixels above `mask` threshold; also returns the
    /// mean and the pixel count. Used for Q8 (brightness gradient within
    /// curtain).
    struct LumaStats: Sendable {
        let mean: Double
        let stddev: Double
        let count: Int
    }

    func lumaStatsInBrightRegion(threshold: Double = 0.20) -> LumaStats {
        var sum = 0.0
        var sumSq = 0.0
        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                let L = luma(x: x, y: y)
                if L >= threshold {
                    sum += L
                    sumSq += L * L
                    count += 1
                }
            }
        }
        guard count > 0 else { return LumaStats(mean: 0, stddev: 0, count: 0) }
        let mean = sum / Double(count)
        let varc = max(0, sumSq / Double(count) - mean * mean)
        return LumaStats(mean: mean, stddev: sqrt(varc), count: count)
    }
}

// MARK: - 1D spatial-frequency analysis

public enum SpatialFFT {

    /// Magnitude of the DFT of `x` at the first `N/2 + 1` bins.
    /// Naive O(N²); fine for analysis-resolution strips (480 or 320 wide).
    public static func magnitudes(_ x: [Double]) -> [Double] {
        let n = x.count
        let half = n / 2 + 1
        var out = [Double](repeating: 0, count: half)
        let twoPi = 2.0 * Double.pi
        for k in 0..<half {
            var re = 0.0
            var im = 0.0
            for t in 0..<n {
                let a = twoPi * Double(k) * Double(t) / Double(n)
                re += x[t] * cos(a)
                im -= x[t] * sin(a)
            }
            out[k] = sqrt(re * re + im * im) / Double(n)
        }
        return out
    }

    /// Energy in DFT magnitude bins corresponding to spatial periods (in
    /// pixels) within [periodLow, periodHigh]. Normalized by total DFT
    /// magnitude energy (excluding the DC bin).
    public static func energyInPeriodBand(
        signal: [Double],
        periodLow: Double,
        periodHigh: Double
    ) -> Double {
        let mags = magnitudes(signal)
        let n = signal.count
        let totalEnergy = mags.dropFirst().reduce(0.0, +)
        guard totalEnergy > 0 else { return 0 }
        // Bin k → period n/k (pixels). Solve for k range.
        let kLo = max(1, Int(Double(n) / periodHigh))
        let kHi = min(mags.count - 1, Int(Double(n) / periodLow))
        guard kHi >= kLo else { return 0 }
        let bandEnergy = (kLo...kHi).reduce(0.0) { $0 + mags[$1] }
        return bandEnergy / totalEnergy
    }
}

// swiftlint:enable identifier_name

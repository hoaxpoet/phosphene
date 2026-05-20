// MotionBandAnalyzer.swift — Frequency-band decomposition of frame deltas.
//
// Answers the question "what timescales of motion does this session's video
// actually contain?" by:
//   1. Extracting a dense uniform grid of frames from the session video.
//   2. Computing per-frame mean luma + frame-to-frame mean absolute luma delta.
//   3. Decomposing the delta signal into frequency bands matching the aurora-
//      research §2.1 timescales:
//        - Substorm advance: minutes (0–0.02 Hz)
//        - Substrate drift:  tens of seconds (0.02–0.5 Hz)
//        - Pulsation:        2–20 s (0.05–0.5 Hz overlaps substrate; reported separately)
//        - Sub-second flicker: 0.1–0.2 s (5–10 Hz)
//        - Sub-flicker:      < 0.02 s (50+ Hz; out of range at typical sampling)
//
// The decomposition is done by binning a windowed DFT magnitude across the
// delta signal — not a perfect-reconstruction filter bank, but accurate
// enough to surface "this session has no sub-second activity" or "this
// session has unexpected high-frequency churn."
//
// SR.1 caveat: this analyzes the RENDERED video. Camera/codec compression
// affects high-frequency content; H.264 at moderate bitrate may suppress
// fine ray flicker even if the live render produces it. Report results
// alongside the codec's recorded bitrate so the reader can calibrate.
//
// SR.1 caveat #2: motion-band analysis runs on extracted frames, not the
// raw render. Sampling rate is the extracted grid's FPS, not the source's
// 60 Hz. Default grid 600 frames over 132 s = 4.5 fps → Nyquist 2.25 Hz, so
// "sub-second flicker" (5–10 Hz) is below Nyquist and aliases. Use a denser
// grid (60 fps = grid of ~8000 frames) for sub-second analysis; the default
// is the substrate/pulsation regime.

// DFT + pixel math; single-letter coordinate / channel names follow the
// same convention as ImagingPrimitives.swift (scoped disable/enable below).

import CoreImage
import Foundation
import ImageIO

// swiftlint:disable identifier_name

public struct MotionBand: Sendable {
    public let name: String
    public let lowHz: Double
    public let highHz: Double
    /// Mean magnitude of the delta signal within the band. Higher = more
    /// motion energy at that timescale.
    public let energy: Double
}

public struct MotionAnalysis: Sendable {
    public let frameCount: Int
    public let samplingHz: Double
    public let deltaSignal: [Double]   // per-pair frame-delta magnitudes
    public let bands: [MotionBand]
    public let nyquistHz: Double
}

public enum MotionBandAnalyzerError: Error, CustomStringConvertible {
    case imageLoadFailure(URL)
    case insufficientFrames(Int)

    public var description: String {
        switch self {
        case .imageLoadFailure(let url): return "Failed to load image: \(url.path)"
        case .insufficientFrames(let n): return "Need ≥ 2 frames for delta analysis (got \(n))"
        }
    }
}

public enum MotionBandAnalyzer {

    /// Analyze frame deltas across `frameURLs` (chronological order),
    /// produce a frequency-band decomposition.
    ///
    /// - Parameter samplingHz: the effective sampling rate of `frameURLs`
    ///   (frames extracted per second of source video). E.g., 600 frames
    ///   over 132 s of source = 4.54 Hz.
    public static func analyze(
        frameURLs: [URL],
        samplingHz: Double
    ) throws -> MotionAnalysis {
        guard frameURLs.count >= 2 else {
            throw MotionBandAnalyzerError.insufficientFrames(frameURLs.count)
        }
        let lumas = try frameURLs.map(meanLuma)
        let deltas = zip(lumas.dropFirst(), lumas.dropLast())
            .map { pair -> Double in abs(pair.0 - pair.1) }

        let nyquist = samplingHz / 2.0

        // Compute DFT magnitudes of the delta signal. Naive O(n²) DFT is fine
        // for the small grids SR.1 uses (~600-2000 samples); upgrade to vDSP
        // FFT if the harness scales past 10k frames.
        let mags = dftMagnitudes(deltas)
        let nMags = mags.count

        // Band definitions — research §2.1 timescales.
        struct BandSpec {
            let name: String
            let lo: Double
            let hi: Double
        }
        let bandSpecs: [BandSpec] = [
            BandSpec(name: "substorm", lo: 0.0, hi: 0.02),                // 50 s+ period
            BandSpec(name: "substrate_drift", lo: 0.02, hi: 0.2),         // 5–50 s
            BandSpec(name: "pulsation_2_20s", lo: 0.05, hi: 0.5),         // 2–20 s
            BandSpec(name: "sub_second_5_10hz", lo: 5.0, hi: 10.0),       // 0.1–0.2 s
            BandSpec(name: "aliased_high", lo: nyquist * 0.8, hi: nyquist) // upper band
        ]

        var bands: [MotionBand] = []
        for spec in bandSpecs {
            let name = spec.name
            let lo = spec.lo
            let hi = spec.hi
            // Each DFT bin k corresponds to frequency `k * samplingHz / N`.
            let nDelta = deltas.count
            let loBin = Int(lo * Double(nDelta) / samplingHz)
            let hiBin = min(nMags, Int(hi * Double(nDelta) / samplingHz) + 1)
            guard hiBin > loBin else {
                bands.append(MotionBand(name: name, lowHz: lo, highHz: hi, energy: 0))
                continue
            }
            let energy = (loBin..<hiBin).reduce(0.0) { $0 + mags[$1] } / Double(hiBin - loBin)
            bands.append(MotionBand(name: name, lowHz: lo, highHz: hi, energy: energy))
        }

        return MotionAnalysis(
            frameCount: frameURLs.count,
            samplingHz: samplingHz,
            deltaSignal: deltas,
            bands: bands,
            nyquistHz: nyquist
        )
    }

    // MARK: - Internal

    /// DFT magnitudes (real-valued). Returns the first N/2+1 bins.
    private static func dftMagnitudes(_ x: [Double]) -> [Double] {
        let n = x.count
        let half = n / 2 + 1
        var out = [Double](repeating: 0, count: half)
        let twoPi = 2.0 * Double.pi
        for k in 0..<half {
            var re = 0.0
            var im = 0.0
            for t in 0..<n {
                let angle = twoPi * Double(k) * Double(t) / Double(n)
                re += x[t] * cos(angle)
                im -= x[t] * sin(angle)
            }
            out[k] = sqrt(re * re + im * im) / Double(n)
        }
        return out
    }

    /// Mean luminance (Rec. 709) of an image at `url`. Loads via ImageIO + CG.
    private static func meanLuma(_ url: URL) throws -> Double {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw MotionBandAnalyzerError.imageLoadFailure(url)
        }
        // Downsample to 64×64 for fast luma compute — averaging across the
        // whole frame, so resolution doesn't materially affect the mean.
        let w = 64, h = 64
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
            throw MotionBandAnalyzerError.imageLoadFailure(url)
        }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = Double(bytes[i]), g = Double(bytes[i + 1]), b = Double(bytes[i + 2])
            sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        return sum / Double(w * h) / 255.0
    }
}

// swiftlint:enable identifier_name

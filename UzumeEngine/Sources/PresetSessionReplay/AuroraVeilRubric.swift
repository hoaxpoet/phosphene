// AuroraVeilRubric.swift — Image-processing proxies for the Aurora Veil 9-Q
// authenticity rubric (AURORA_VEIL_RESEARCH_2026-05-18.md §2.3).
//
// Each Q gets a numerical proxy that operates on a single canonical-
// resolution RGBAImage. The proxy returns a raw score in question-specific
// units; the calibration step (ReferenceCalibration.swift) computes per-
// question reference family mean + σ, then expresses the rendered output's
// score as σ-distance from that mean.
//
// IMPORTANT DESIGN PRINCIPLE: Each proxy is a HEURISTIC, not ground truth.
// The calibration step is load-bearing — if a proxy doesn't correlate with
// what references actually show (e.g., the "vertical-rays" proxy returns
// similar values for refs `03`/`04` and ref `09`), the proxy is broken
// and SR.1's verdict for that Q is "uncalibrated — cannot grade." This is
// honest evidence, not gate-bypass.
//
// Q4 (multi-timescale motion) is video-only — no single-frame proxy. The
// motion-band analyzer in MotionBandAnalyzer.swift handles Q4 separately
// at video-grading time.

// Per-Q proxies operate in pixel + DFT space; single-letter coordinate
// names (paired with scoped disable/enable) match the engine-wide
// convention for pixel math.

import Foundation

// swiftlint:disable identifier_name line_length

public enum AuroraVeilRubricQuestions {

    // MARK: - Q1: Vertical stratification only

    /// Q1 proxy: ratio of mean horizontal hue variance / mean vertical hue
    /// variance. Lower (closer to 0) = stronger vertical stratification —
    /// rows have uniform hue (low horizontal variance), columns have
    /// varying hue (high vertical variance).
    public static let q1VerticalStratification = RubricQuestion(
        id: "Q1",
        name: "Vertical stratification only",
        description: "Hue gradient runs vertically (green low → magenta high), not horizontally. No rainbow-across-width gradients.",
        highMeans: "Horizontal variance dominates → hues smear left-to-right (anti-pattern).",
        lowMeans: "Vertical variance dominates → hues stratify by altitude (aurora-like).",
        proxyName: "mean_row_circular_hue_variance / mean_column_circular_hue_variance"
    ) { img in
        let rowVar = img.perRowCircularHueVariance().filter { !$0.isNaN }
        let colVar = img.perColumnCircularHueVariance().filter { !$0.isNaN }
        let mRow = rowVar.isEmpty ? 0 : rowVar.reduce(0, +) / Double(rowVar.count)
        let mCol = colVar.isEmpty ? 1 : colVar.reduce(0, +) / Double(colVar.count)
        guard mCol > 1e-6 else { return Double.infinity }
        return mRow / mCol
    }

    // MARK: - Q2: Green-dominant palette

    /// Q2 proxy: green-bin count / (green-bin count + magenta-bin count)
    /// in the hue histogram, over above-luma-threshold pixels.
    /// Range [0, 1]: 1 = pure green; 0 = pure magenta; 0.5 = equal share.
    /// Aurora references should sit above 0.5; anti-ref `09` should sit
    /// near 0 (festival is pink/orange-dominated).
    public static let q2GreenDominant = RubricQuestion(
        id: "Q2",
        name: "Green-dominant palette",
        description: "Green is the substrate hue; magenta/red are accents on top.",
        highMeans: "Predominantly green (aurora-like).",
        lowMeans: "Predominantly magenta/red/cyan (anti-pattern).",
        proxyName: "green_share / (green_share + magenta_share)"
    ) { img in
        let hist = img.hueHistogram(bins: 36)
        // 36 bins = 10° each. Green = bins 9..15 (90°–150°); magenta = bins
        // 30..33 (300°–340°).
        let green = (9...15).reduce(0) { $0 + hist[$1] }
        let magenta = (30...33).reduce(0) { $0 + hist[$1] }
        let total = green + magenta
        guard total > 0 else { return 0.5 }
        return Double(green) / Double(total)
    }

    // MARK: - Q3: Vertical ray fine structure

    /// Q3 proxy: spatial-frequency energy in the horizontal-period band
    /// corresponding to visible vertical-ray spacing. Vertical rays
    /// produce columnar luma structure → high-frequency horizontal
    /// variation when each row is FFT'd. References `03`/`04` should
    /// score significantly above the rendered output's homogenized-band
    /// reading; anti-ref `09` should score moderate-low (beams aren't
    /// per-column structure either).
    ///
    /// Period band: 4–32 px at the canonical 480-px width. Empirically
    /// chosen — needs calibration validation. SR.1 reports the raw value;
    /// the calibration step decides whether the band choice was right.
    public static let q3VerticalRays = RubricQuestion(
        id: "Q3",
        name: "Vertical ray fine structure",
        description: "Visible vertical pillars / striations within the green body, ≥ 4 octaves of noise so detail exists at multiple scales.",
        highMeans: "High horizontal spatial-frequency energy in the ray-spacing band → columnar ray structure visible.",
        lowMeans: "Low horizontal high-frequency energy → smooth homogenized band (anti-pattern).",
        proxyName: "mean(horizontal_FFT_energy in period [4, 32]px) over bright rows"
    ) { img in
        // Restrict to rows where mean luma > 0.10 (the aurora region).
        let rowLumas = img.perRowMeanLuma()
        var bandEnergies: [Double] = []
        for y in 0..<img.height {
            guard rowLumas[y] > 0.10 else { continue }
            // Build the row's luma signal.
            var signal = [Double](repeating: 0, count: img.width)
            for x in 0..<img.width { signal[x] = img.luma(x: x, y: y) }
            // Subtract DC so the bias term doesn't dominate the FFT.
            let mean = signal.reduce(0, +) / Double(signal.count)
            for i in 0..<signal.count { signal[i] -= mean }
            let e = SpatialFFT.energyInPeriodBand(
                signal: signal, periodLow: 4, periodHigh: 32)
            bandEnergies.append(e)
        }
        guard !bandEnergies.isEmpty else { return 0 }
        return bandEnergies.reduce(0, +) / Double(bandEnergies.count)
    }

    // MARK: - Q5: Emissive compositing

    /// Q5 proxy: ratio of (star-class pixels found in bright-aurora region)
    /// to (star-class pixels found in dark-sky region), normalized by the
    /// region areas. A star-class pixel is a local-maximum pixel with
    /// luma >= starLumaThreshold and a 3×3 neighborhood mean
    /// >= 0.5 × pixel luma (forced contrast).
    ///
    /// If stars punch through the aurora (emissive), the ratio approaches
    /// 1.0 (pixels above bright underlay are still detected). If the
    /// aurora is opaque (mix-blend, FM #5), the ratio approaches 0.
    public static let q5EmissiveCompositing = RubricQuestion(
        id: "Q5",
        name: "Emissive compositing",
        description: "Stars + sky structure visible THROUGH the aurora; sum-blend over dark sky, not opaque overlay.",
        highMeans: "Stars present in aurora-bright regions → emissive compositing.",
        lowMeans: "Stars absent from aurora-bright regions → opaque overlay (anti-pattern, FM #5).",
        proxyName: "star_density(bright_aurora) / star_density(dark_sky)"
    ) { img in
        // Star-class detection: local maximum with luma > 0.55 and 3×3
        // neighborhood mean ≤ 0.7 × pixel luma (forced isolation).
        let starLumaThreshold = 0.55
        let isolationRatio = 0.7

        func isStar(x: Int, y: Int) -> Bool {
            guard x > 0, x < img.width - 1, y > 0, y < img.height - 1 else { return false }
            let center = img.luma(x: x, y: y)
            guard center >= starLumaThreshold else { return false }
            var sum = 0.0
            var localMaxOK = true
            for dy in -1...1 {
                for dx in -1...1 {
                    let v = img.luma(x: x + dx, y: y + dy)
                    sum += v
                    if (dx, dy) != (0, 0), v >= center { localMaxOK = false }
                }
            }
            guard localMaxOK else { return false }
            let neighborhoodMean = (sum - center) / 8.0
            return neighborhoodMean <= isolationRatio * center
        }

        // Region masks: bright aurora = luma in [0.20, 0.55) (above
        // background, below star-class). Dark sky = luma < 0.10.
        var brightStars = 0; var brightArea = 0
        var darkStars = 0; var darkArea = 0
        for y in 0..<img.height {
            for x in 0..<img.width {
                let L = img.luma(x: x, y: y)
                if L >= 0.20 && L < 0.55 {
                    brightArea += 1
                    if isStar(x: x, y: y) { brightStars += 1 }
                } else if L < 0.10 {
                    darkArea += 1
                    if isStar(x: x, y: y) { darkStars += 1 }
                }
            }
        }
        // Density-normalised: stars per pixel in each region.
        let brightDensity = brightArea > 0 ? Double(brightStars) / Double(brightArea) : 0
        let darkDensity = darkArea > 0 ? Double(darkStars) / Double(darkArea) : 0
        guard darkDensity > 0 else { return brightDensity > 0 ? 1.0 : 0.5 }
        return brightDensity / darkDensity
    }

    // MARK: - Q6: Soft top, sharp bottom

    /// Q6 proxy: gradient magnitude at the aurora's bottom edge ÷ at its
    /// top edge. > 1 = sharp bottom soft top (correct asymmetry).
    /// Computes per-row mean luma, finds the peak, then computes
    /// gradient (absolute first difference) at the row immediately
    /// above the peak (top edge) and immediately below (bottom edge).
    public static let q6SoftTopSharpBottom = RubricQuestion(
        id: "Q6",
        name: "Soft top, sharp bottom",
        description: "Lower edge has recognizable boundary; upper edge dissolves into space.",
        highMeans: "Bottom gradient significantly steeper than top (correct asymmetry).",
        lowMeans: "Edges symmetric or top sharper than bottom (anti-pattern, FM #13).",
        proxyName: "|dL/dy at bottom edge| / |dL/dy at top edge|"
    ) { img in
        let rowL = img.perRowMeanLuma()
        // Find the peak row.
        guard let peakY = rowL.enumerated().max(by: { $0.1 < $1.1 })?.offset else {
            return 1.0
        }
        // Scan downward to find where luma drops below 0.5 × peak — that's
        // the bottom edge.
        let peakL = rowL[peakY]
        let halfL = 0.5 * peakL
        let topEdge = stride(from: peakY, through: 0, by: -1)
            .first(where: { rowL[$0] < halfL }) ?? peakY
        let bottomEdge = (peakY..<img.height)
            .first(where: { rowL[$0] < halfL }) ?? peakY
        // Gradient at each edge: absolute first-difference.
        func gradAt(_ y: Int) -> Double {
            guard y > 0, y < img.height - 1 else { return 0 }
            return abs(rowL[y + 1] - rowL[y - 1]) / 2.0
        }
        let gTop = gradAt(topEdge)
        let gBot = gradAt(bottomEdge)
        guard gTop > 1e-6 else { return Double.infinity }
        return gBot / gTop
    }

    // MARK: - Q7: Off-axis composition + dark foreground

    /// Q7 proxy: average of (off-axis-ness) and (dark-fraction in bottom band).
    /// Both components in [0, 1]; result also [0, 1]. Higher = more off-axis
    /// composition with stronger silhouette foreground.
    public static let q7OffAxisDarkForeground = RubricQuestion(
        id: "Q7",
        name: "Off-axis composition + dark foreground",
        description: "Aurora occupies part of sky against near-black surroundings and silhouette foreground.",
        highMeans: "Brightness centroid off-center horizontally + dark fraction in bottom 20% high (curtains over silhouette).",
        lowMeans: "Centered horizontal band + uniform-luminance bottom (anti-pattern, FM #9 + #12).",
        proxyName: "(|centroid_x − 0.5| × 2 + dark_fraction_bottom_20) / 2"
    ) { img in
        let centroid = img.brightnessCentroid()
        let offAxis = min(1.0, abs(centroid.x - 0.5) * 2.0)
        let dark = img.darkFractionInBottomBand(fractionFromBottom: 0.20, lumaThreshold: 0.08)
        return (offAxis + dark) / 2.0
    }

    // MARK: - Q8: Brightness gradient within curtain

    /// Q8 proxy: coefficient of variation (stddev/mean) of luma within the
    /// bright-aurora region (luma >= 0.20). Higher = more brightness
    /// variation within the curtain (correct character).
    public static let q8BrightnessGradient = RubricQuestion(
        id: "Q8",
        name: "Brightness gradient within curtain",
        description: "Internal regions vary from bright (active rays) to dim (diffuse glow).",
        highMeans: "High coefficient of variation → brightness varies internally.",
        lowMeans: "Low coefficient of variation → uniformly saturated edge-to-edge (anti-pattern, FM #2).",
        proxyName: "stddev(luma) / mean(luma) within luma >= 0.20"
    ) { img in
        let stats = img.lumaStatsInBrightRegion(threshold: 0.20)
        guard stats.mean > 1e-6 else { return 0 }
        return stats.stddev / stats.mean
    }

    // MARK: - Q9: No theatrical beam

    /// Q9 proxy: variance of per-row brightness centroid x-position
    /// across rows where row mean luma > threshold.
    /// Curtains drape — their bright content shifts horizontally with
    /// altitude (centroid_x varies). Beams converge — bright content
    /// stays at one x across altitudes (centroid_x stays put).
    /// Higher variance = more curtain-like; lower = more beam-like.
    public static let q9NoTheatricalBeam = RubricQuestion(
        id: "Q9",
        name: "No theatrical beam",
        description: "No converging cones from a sky point; bright content distributed across the curtain.",
        highMeans: "Per-row brightness centroid shifts horizontally → curtain drape.",
        lowMeans: "Per-row brightness centroid locked to one x → beam-like (anti-pattern, FM #14).",
        proxyName: "variance(per_row_brightness_centroid_x) over bright rows"
    ) { img in
        let rowL = img.perRowMeanLuma()
        var centroidsX: [Double] = []
        for y in 0..<img.height {
            guard rowL[y] > 0.15 else { continue }
            var sumW = 0.0
            var sumX = 0.0
            for x in 0..<img.width {
                let w = img.luma(x: x, y: y)
                sumW += w
                sumX += w * Double(x)
            }
            guard sumW > 0 else { continue }
            centroidsX.append(sumX / sumW / Double(img.width - 1))
        }
        guard centroidsX.count >= 2 else { return 0 }
        let m = centroidsX.reduce(0, +) / Double(centroidsX.count)
        let v = centroidsX.reduce(0.0) { $0 + ($1 - m) * ($1 - m) } / Double(centroidsX.count)
        return v
    }

    // MARK: - All questions

    /// All single-frame proxies. Q4 (multi-timescale motion) is video-only
    /// and handled by MotionBandAnalyzer + the video-grading step.
    public static let all: [RubricQuestion] = [
        q1VerticalStratification,
        q2GreenDominant,
        q3VerticalRays,
        q5EmissiveCompositing,
        q6SoftTopSharpBottom,
        q7OffAxisDarkForeground,
        q8BrightnessGradient,
        q9NoTheatricalBeam
    ]
}

// swiftlint:enable identifier_name line_length

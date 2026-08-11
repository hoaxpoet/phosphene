// LoudnessProfile — DYN.1c: one track's own loud/quiet range, measured up front.
//
// WHY. DYN.1b's `spectral_surge` maps a FIXED absolute band (−24…−15 dB of total
// spectral energy) onto 0…1. A fixed band is calibrated for one song and wrong for the
// next: measured on session `2026-08-04T20-23-15Z` (Hummer) the surge reaches 1.00 at
// 31.6 s and stays pinned for **62 % of the recovered capture**, while sections LATER in
// the track are 4 dB louder than the one that saturated it. Pinned means "cannot rise
// again", so the tree had grown to full size before the full band arrived — Matt's
// complaint verbatim.
//
// For a local file the whole thing is decoded during preparation, so the track's own
// loudness distribution is measurable before a note plays. This type carries it, and the
// surge becomes "how loud is this moment FOR THIS TRACK". Streaming keeps the fixed band
// (only a 30 s preview is ever decoded) — the scope limit Matt named himself.
//
// SCALE IS THE WHOLE RISK, and it has already cost one review round (see
// `docs/ENGINE/DYN1_CALIBRATION.md` §2: a band derived from RMS dBFS applied to
// `10·log10(Σ magnitude²)`). Both scales are pinned here rather than in two places:
// `levelDB(magnitudes:count:)` is the ONE definition of the quantity, used by the live
// `SpectralAnalyzer` and by the offline `LoudnessProfile.measure`, and
// `levelSmoothingAlpha` is the ONE follower width. The remaining assumption — that the
// decoded file and the live tap present the same absolute level — holds because the LF
// tap sits on the player node PRE-MIXER, PRE-VOLUME (`LocalFilePlaybackProvider`) and
// both paths downmix stereo the same way ((L+R)·0.5).

import Foundation

// MARK: - LoudnessProfile

/// A track's own loudness DISTRIBUTION, as evenly-spaced quantiles of its smoothed level
/// in the units of `levelDB(magnitudes:count:)`.
///
/// Consumed by `SpectralAnalyzer`: the surge target becomes `rank(ofLevelDB:)` — the
/// fraction of the track quieter than this moment. Produced offline by
/// `LoudnessProfile.measure` over a fully-decoded local file.
///
/// WHY A DISTRIBUTION AND NOT TWO EDGES. The first cut of DYN.1c mapped p10→p95 onto a
/// smoothstep, and on the Hummer capture it took the pinned fraction only 63 % → 46 %.
/// The surge follower rides peaks (fast attack, slow release), so ANY two-edge band whose
/// top is a percentile saturates the moment a transient in the last couple of seconds
/// crosses it. Sweeping the edges did find a working pair — p30→p99, 13.5 % pinned — but
/// p30 is a number fitted to one track's intro length, which is the *same* mistake as the
/// fixed band it replaces, one level up. Ranking has no fitted constant: by construction
/// the loudest sections read near 1, the quietest near 0, and only the top few per cent of
/// a track can pin. Measured on the same capture: **63.3 % pinned → 0.9 %**, with the
/// surge climbing 0.07 → 0.32 → 0.61 → 0.95 across the track and the guitar arrival still
/// landing as a step.
public struct LoudnessProfile: Sendable, Equatable, Codable {

    /// Number of quantile intervals; the table holds `steps + 1` levels. 32 is fine
    /// resolution for a 0…1 output (≈ 3 % per step) and 132 bytes on disk.
    public static let steps = 32

    /// Ascending level quantiles of the track's smoothed level, from the minimum at index
    /// 0 to the maximum at index `steps`. `quantilesDB[i]` is the level below which
    /// `i / steps` of the track sits.
    public let quantilesDB: [Float]

    /// DYN.2c — the track's OWN density DISTRIBUTION: `steps + 1` ascending quantiles of
    /// the SECTION-SMOOTHED (τ20 s) density, measured over the whole decode. Empty when
    /// unmeasured.
    ///
    /// A single "normal" plus a smoothstep needed two fitted edges, and the first pair was
    /// fitted against the broken DYN.2b ratio: with a correct normal the ratio spans
    /// 0.0…8.6 and those edges clipped Hummer to a flat 1.00 for four minutes. Quantiles
    /// need no edges — `densityRank` is uniform over the track by construction, the same
    /// reason `rank(ofLevelDB:)` replaced the p10→p95 band at DYN.1c.
    ///
    /// Quantiles are of the τ20 s SMOOTHED series, not the raw fraction, because that is
    /// what the live analyzer feeds in. Quantiles of the raw series would be far wider and
    /// every live value would rank mid-scale.
    ///
    /// WHY THIS IS ON THE PROFILE. DYN.2b learned this live with a τ45 s EMA seeded to the
    /// section leg, so the ratio began at exactly 1.00 and needed 90–135 s to develop any
    /// contrast — most of a song. Measured on Matt's `2026-08-07T15-38-27Z` capture the
    /// ratio spanned 1.00…1.17 and the trunk drifted monotonically 0.38 → 0.68 with no
    /// structure. **A track's normal cannot be learned from the track while you are playing
    /// it.** For a local file the whole thing is decoded at preparation, exactly like the
    /// loudness quantiles beside it, so it is measured up front and available from frame 1.
    public let densityQuantiles: [Float]

    /// Below this INNER span the quantiles are measuring nothing — a genuinely constant
    /// source (digital silence, a test tone) would rank its own dither. Such a profile is
    /// refused and the caller keeps the fixed band.
    ///
    /// **THIS WAS 4 dB AND THE GATE POINTED THE WRONG WAY (DYN.1d, 2026-08-05).** A
    /// brickwalled master has a narrow range, which is exactly when a FIXED absolute band
    /// is most wrong — so the threshold rejected the tracks that needed ranking most, and
    /// did it silently. Measured on Matt's Cherub Rock capture `2026-08-05T21-21-03Z`:
    /// inner range **1.46 dB**, refused, surge pinned **92.7 %** of the track. Ranking the
    /// same audio gives **0.5 %** pinned and steps 0.119 → 0.548 across the guitar entry —
    /// both halves of Matt's report ("grows too much BEFORE the distorted guitar comes in
    /// and then does not jump up again when it enters") were this one threshold.
    ///
    /// 0.5 dB is safe, not merely permissive: ranked at 1.46 dB the surge lands in the same
    /// regime as the Hummer capture Matt approved as reading musical — 2.87 turns/s against
    /// Hummer's 2.41, and *less* pinning (0.5 % vs 1.4 %). Narrowness alone was never the
    /// hazard; a distribution with no shape at all is, and that is what this now catches.
    public static let minimumUsableRangeDB: Float = 0.5

    /// Fewer frames than this is not a track, it is a fragment; a distribution over it
    /// describes the fragment. 500 frames ≈ 11 s at the ~47 Hz analysis rate.
    public static let minimumFrames = 500

    /// The track's quietest and loudest smoothed level. Log only — `quietDB` is routinely
    /// −200 dB, the silent frame before the first note, which is why `isUsable` gates on
    /// `innerRangeDB` instead.
    public var quietDB: Float { quantilesDB.first ?? 0 }
    public var loudDB: Float { quantilesDB.last ?? 0 }
    public var rangeDB: Float { loudDB - quietDB }

    /// Span between the 12.5th and 87.5th quantiles — the range of the track's actual
    /// MUSIC. Immune to a silent lead-in at one end and a single limiter-defeating
    /// transient at the other, either of which makes min→max look dynamic when nothing is.
    public var innerRangeDB: Float {
        guard quantilesDB.count == Self.steps + 1 else { return 0 }
        return quantilesDB[Self.steps * 7 / 8] - quantilesDB[Self.steps / 8]
    }

    /// Whether this profile should replace the fixed band.
    public var isUsable: Bool {
        quantilesDB.count == Self.steps + 1
            && quantilesDB.allSatisfy { $0.isFinite }
            && innerRangeDB >= Self.minimumUsableRangeDB
    }

    public init(quantilesDB: [Float], densityQuantiles: [Float] = []) {
        self.quantilesDB = quantilesDB
        self.densityQuantiles = densityQuantiles
    }

    /// Fraction of the track less dense than `density`, 0…1. Same interpolated-quantile
    /// lookup as `rank(ofLevelDB:)`. Returns nil when no density distribution was measured
    /// (streaming), so the caller can fall back.
    public func densityRank(of density: Float) -> Float? {
        guard densityQuantiles.count == Self.steps + 1 else { return nil }
        return Self.rank(of: density, in: densityQuantiles)
    }

    /// Shared interpolated lookup for both quantile tables.
    static func rank(of value: Float, in table: [Float]) -> Float {
        guard let low = table.first, let high = table.last, table.count > 1 else { return 0 }
        if value <= low { return 0 }
        if value >= high { return 1 }
        var index = 0
        while index < table.count - 2 && table[index + 1] < value { index += 1 }
        let span = table[index + 1] - table[index]
        let fraction = span > 1e-9 ? (value - table[index]) / span : 0
        return (Float(index) + fraction) / Float(table.count - 1)
    }

    /// One-line description for `session.log` and `os.Logger` — the durable artifact a
    /// later diagnosis reads to see which band a track actually ran under.
    public var summary: String {
        String(format: "%.1f…%.1f dB, musicRange=%.1f dB", quietDB, loudDB, innerRangeDB)
    }

    /// Build from the per-frame SMOOTHED level series of a whole track.
    ///
    /// The series must be smoothed with `levelSmoothingAlpha` at the live analysis rate:
    /// the distribution of a raw per-frame series is wider than that of the smoothed
    /// signal the surge actually reads, which would compress every rank toward the middle.
    ///
    /// - Returns: `nil` when the series is too short to characterise a track.
    public init?(smoothedLevelsDB levels: [Float]) {
        guard levels.count >= Self.minimumFrames else { return nil }
        let sorted = levels.sorted()
        self.init(quantilesDB: (0...Self.steps).map { step in
            let index = Int((Float(sorted.count - 1) * Float(step) / Float(Self.steps)).rounded())
            return sorted[min(max(index, 0), sorted.count - 1)]
        }, densityQuantiles: [])
    }

    /// Fraction of the track quieter than `levelDB`, 0…1. Linear interpolation inside the
    /// bracketing quantile interval so the output is continuous, not a 32-step staircase.
    public func rank(ofLevelDB levelDB: Float) -> Float {
        let table = quantilesDB
        guard let low = table.first, let high = table.last, table.count > 1 else { return 0 }
        if levelDB <= low { return 0 }
        if levelDB >= high { return 1 }
        var index = 0
        while index < table.count - 2 && table[index + 1] < levelDB { index += 1 }
        let span = table[index + 1] - table[index]
        let fraction = span > 1e-6 ? (levelDB - table[index]) / span : 0
        return (Float(index) + fraction) / Float(table.count - 1)
    }

    // MARK: - The level scale (single source of truth)

    // MARK: - Smoothing time constants (DYN.4)
    //
    // **These were per-FRAME alphas and that was a defect.** An EMA written as
    // `x = α·new + (1-α)·x` with a constant α has a time constant of `1/(α·fps)` — so its
    // meaning in seconds moves with the analysis rate. The offline quantile builder hops
    // 1024 samples at 44.1 kHz (43.07 Hz) and its header claimed it "mirrors the live path
    // frame for frame"; that was true when the live path also ran at 43 Hz. Measured on
    // Matt's session `2026-08-10T01-29-10Z`, **the live path runs at 9.9 Hz**, so:
    //
    //   leg      documented   actually live (9.9 Hz)
    //   section    τ 20 s       87 s
    //   normal     τ 45 s       194 s
    //
    // The consequence is not a slightly different feel. `densityQuantiles` are built from a
    // τ20 s-smoothed series offline and the live value ranked against them is τ87 s
    // smoothed, so the two describe different distributions and every live rank is
    // compressed toward the middle. On that session `spectral_section_ratio` spanned
    // 0.534…0.614 of its 0…2 range and the Fractal Tree canopy used 0.00…0.31 of its own.
    //
    // Expressed in SECONDS and converted per frame with `emaAlpha(deltaTime:tau:)`, the
    // constants mean what they say at any rate, and offline and live agree by construction.

    /// The analysis rate the legacy per-frame alphas were calibrated at — CD rate over the
    /// offline 1024-sample hop, ≈ 43.07 Hz.
    ///
    /// A historical calibration anchor, NOT a runtime rate assumption: nothing derives a
    /// live width from it (every follower takes the real `deltaTime`), it exists so
    /// `tau(legacyAlpha:)` can state exactly what each retired coefficient meant. That is
    /// why it does not violate QR.1 / D-079 — there is no tap rate to thread here.
    public static let referenceAnalysisHz: Float = 1 / referenceFrameSeconds

    /// Duration of one analysis frame at that reference rate, in SECONDS (1024 samples at
    /// CD rate). A duration rather than a rate because a duration is what every follower
    /// actually consumes — and stating it this way means no sample-rate literal is asserted
    /// anywhere, which is the QR.1 / D-079 rule rather than an exemption from it.
    public static let referenceFrameSeconds: Float = 0.023_219_954

    /// Time constant a legacy per-frame alpha meant at `referenceAnalysisHz`. Chosen so the
    /// exponential form below reproduces the old coefficient EXACTLY at that rate — this
    /// increment fixes the rate dependence, it does not retune anything.
    public static func tau(legacyAlpha alpha: Float) -> Float {
        -referenceFrameSeconds / log(1 - alpha)
    }

    /// Frame alpha for a time constant, given this frame's duration.
    ///
    /// Falls back to the reference frame when `deltaTime` is absent or nonsensical — a
    /// zero would freeze every follower, which is a worse failure than a slightly wrong
    /// smoothing width on one frame.
    public static func emaAlpha(deltaTime: Float, tau: Float) -> Float {
        let dt = deltaTime.isFinite && deltaTime > 0 ? deltaTime : referenceFrameSeconds
        return 1 - exp(-dt / max(tau, 1e-6))
    }

    /// SECTION-scale density leg, shared by the live analyzer and the offline quantile
    /// measurement so the two rank the same signal. DYN.2b's legs collapsed because two
    /// nominally-different widths were 0.38 % apart; keeping the constant in one place is
    /// how that stops recurring — and DYN.4 is why it must be a τ, not an alpha.
    public static let densitySectionTau: Float = tau(legacyAlpha: 0.00116)   // ≈ 20.0 s

    /// Applied to `levelDB` before anything reads it, live and offline.
    public static let levelSmoothingTau: Float = tau(legacyAlpha: 0.030)     // ≈ 0.76 s

    /// Split between "low" and "high" for the density fraction. 1.5 kHz sits above the
    /// fundamental range of most rhythm-section content and below the harmonics distortion
    /// adds. MUST match `SpectralAnalyzer.densitySplitHz` — it is the same quantity.
    public static let densitySplitHz: Float = 1500

    /// Fraction of spectral energy above `densitySplitHz`, from RAW magnitudes. Energy is
    /// magnitude squared, so the ratio is scale-invariant and any upstream gain cancels.
    /// ONE definition, used by the live `SpectralAnalyzer` and by the offline `measure` —
    /// the same reason `levelDB` lives here (see the header).
    public static func densityFraction(magnitudes: [Float], count: Int, binResolution: Float) -> Float {
        guard binResolution > 0 else { return 0 }
        let splitBin = min(Int(densitySplitHz / binResolution), count)
        var low: Float = 0
        var high: Float = 0
        for index in 0..<min(count, magnitudes.count) {
            let energy = magnitudes[index] * magnitudes[index]
            if index < splitBin { low += energy } else { high += energy }
        }
        let total = low + high
        return total > 1e-10 ? high / total : 0
    }

    /// PRE-AGC LEVEL by Parseval: total spectral energy is proportional to signal power,
    /// and these magnitudes are the raw FFT — upstream of every normaliser in the pipeline.
    ///
    /// NOT RMS dBFS. Typical values on real music: ≈ −37 dB in an intro, −28…−19 before a
    /// guitar arrival, −17…−10 through a body.
    public static func levelDB(magnitudes: [Float], count: Int) -> Float {
        var energy: Float = 0
        for index in 0..<min(count, magnitudes.count) {
            energy += magnitudes[index] * magnitudes[index]
        }
        return 10 * log10f(max(energy, 1e-20))
    }
}

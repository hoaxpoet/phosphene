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

    /// Below this INNER span the quantiles are measuring noise, not dynamics — a
    /// constant-level source (test tone, heavily-limited loop) would rank its own dither.
    /// Such a profile is refused and the caller keeps the fixed band.
    public static let minimumUsableRangeDB: Float = 4

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

    public init(quantilesDB: [Float]) {
        self.quantilesDB = quantilesDB
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
        })
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

    /// EMA alpha applied to `levelDB` before anything reads it, live and offline.
    /// At the measured ~47 Hz analysis rate this is τ ≈ 0.7 s.
    public static let levelSmoothingAlpha: Float = 0.030

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

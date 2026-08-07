// TrackProfile — Pre-computed MIR features for a single track.
// Populated by SessionPreparer from the 30-second preview clip and stored
// in StemCache for instant access at playback start.

import Foundation
import Shared

// MARK: - TrackProfile

/// Pre-analyzed MIR summary for a track derived from its 30-second preview.
///
/// All fields are optional where the analysis may not converge in 30 seconds
/// (e.g., BPM estimation needs multiple beat onsets). The Orchestrator treats
/// nil fields as "unknown" and falls back to live MIR as playback progresses.
public struct TrackProfile: Sendable, Codable {

    // MARK: - Fields

    /// Estimated tempo in BPM, or nil if insufficient onset data.
    public var bpm: Float?

    /// Estimated musical key (e.g. "C major", "F# minor"), or nil if atonal/percussive.
    public var key: String?

    /// Emotional state (valence × arousal) from the mood classifier.
    public var mood: EmotionalState

    /// Average normalized spectral centroid across the preview (0–1).
    public var spectralCentroidAvg: Float

    /// Genre tags from external APIs. Empty when no pre-fetch data is available.
    public var genreTags: [String]

    /// Per-stem energy balance from the preview separation (GPU buffer(3) layout).
    public var stemEnergyBalance: StemFeatures

    /// Coarse section count estimated from 30 seconds of structural analysis.
    /// Typically 1–3 for a 30-second preview window.
    public var estimatedSectionCount: Int

    /// Does the track lack a steady, trustworthy beat? (FBS / D-154.)
    /// Computed at consumption time from the cached grids via
    /// `assessBeatIrregularity` (octave-folded full-mix-vs-drums BPM
    /// disagreement + bar confidence). `true` ⇒ the scorer hard-excludes
    /// presets declaring `requires_regular_beat`. **No production preset
    /// declares the flag since the D-154 amendment (2026-06-11): the FFO ban
    /// is retired** — Matt's pick after FFO on Pyramid Song (the gate's
    /// canonical catch, where the live tracker in fact LOCKED at 5.4 s)
    /// "looks and moves great". The signal + mechanism stay for diagnostics
    /// and future presets. `nil` = unknown — permissive, no exclusion.
    /// Optional so old persisted profiles decode unchanged.
    public var beatIrregular: Bool?

    /// WL.13 — the track's tonal centre on the circle of fifths, radians (±π), measured as
    /// the circular mean of `tonal_phase_fifths` over the whole preview clip. `nil` when the
    /// harmony is too diffuse to place a centre, or when the track was never pre-analysed.
    ///
    /// Witchlight steers on the pen's excursion FROM this centre, and used to learn it live
    /// from a 12 s running mean seeded at 0 rad — an arbitrary point with no relation to the
    /// song. That took ~30 s per track to converge, during which the excursion held one sign
    /// and the pen wound a coil; 30 s is also the trail length, so the entire visible drawing
    /// for the first half-minute of every track was the convergence rather than the music
    /// (WL.13 measurement: heading monotonicity 0.82–1.00 over the first 15 s of three real
    /// sessions, against 0.10–0.23 over the whole run).
    ///
    /// Optional so old persisted profiles decode unchanged, and because the streaming path
    /// can reach playback without a preview to analyse.
    public var tonalHomeFifths: Float?

    // MARK: - Init

    public init(
        bpm: Float? = nil,
        key: String? = nil,
        mood: EmotionalState = .neutral,
        spectralCentroidAvg: Float = 0,
        genreTags: [String] = [],
        stemEnergyBalance: StemFeatures = .zero,
        estimatedSectionCount: Int = 0,
        beatIrregular: Bool? = nil,
        tonalHomeFifths: Float? = nil
    ) {
        self.bpm = bpm
        self.key = key
        self.mood = mood
        self.spectralCentroidAvg = spectralCentroidAvg
        self.genreTags = genreTags
        self.stemEnergyBalance = stemEnergyBalance
        self.estimatedSectionCount = estimatedSectionCount
        self.beatIrregular = beatIrregular
        self.tonalHomeFifths = tonalHomeFifths
    }

    // MARK: - Defaults

    /// Empty profile — all fields at zero or nil.
    public static let empty = TrackProfile()

    // MARK: - Tonal home

    /// Circular mean of a `tonal_phase_fifths` series, or `nil` when the harmony is too
    /// diffuse to place a centre. Takes the sin/cos sums so a streaming accumulator and a
    /// batch measurement produce the SAME answer — the definition lives here, once.
    ///
    /// NEVER a mean of the raw ±π sawtooth: that averages a wrap to the opposite key.
    ///
    /// The resultant length R is the concentration of the phase around its mean. Below 0.10
    /// there is no centre worth naming (the WITCHLIGHT_DESIGN §2.1 captures measure R
    /// 0.24–0.78), and returning a mean angle for one would hand a confidently wrong home to
    /// a consumer that could otherwise have fallen back on getting `nil`.
    public static func tonalHome(sumSin: Float, sumCos: Float, count: Int) -> Float? {
        guard count > 0 else { return nil }
        let meanSin = sumSin / Float(count), meanCos = sumCos / Float(count)
        guard (meanSin * meanSin + meanCos * meanCos).squareRoot() >= 0.10 else { return nil }
        return atan2(meanSin, meanCos)
    }
}

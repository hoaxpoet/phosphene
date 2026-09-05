// BarLineEstimator+Windowed — PR.17: bar structure is LOCAL, so ask locally.
//
// `estimate` returns ONE meter and phase for a whole track. PR.15 measured what that
// costs: scored per ~80-beat window instead, money answers 7 (the odd-meter programme's
// defining hard case, wrong at every previous attempt), take_five answers 5 on 11 of 11
// windows, and billie_jean answers 4 on 6 of 7 — while tracks with no real bar structure
// stay silent. A single global answer is worse than either the windows or the old 30 s
// clip, because one number has to describe an intro, a chorus and an outro at once.
//
// Matt's product call (2026-09-05), asked as sparse-and-correct vs dense-with-fallback:
// **sparse and correct**. Bars appear only where the evidence carries them; where it does
// not, a preset gets no bar-driven motion rather than an accent on the wrong beat. So a
// declined window emits NOTHING — it is never backfilled from the model's downbeat head,
// which over-fires (78 % of beats on money, DOWNBEAT_SURVEY_2026-08-27.md).
//
// COST: the features are extracted ONCE over the whole track and then sliced per window.
// Calling `estimate` per window would resample and re-STFT the entire file per window.
// Slicing is equivalent — every feature is per-beat and local — and the standardisation
// inside `contrasts` is computed over whatever slice it is handed, which is the point.

import Foundation

extension BarLineEstimator {

    // MARK: - Windowed output

    /// Bar positions across a track, from independently-scored windows.
    public struct WindowedBarLine: Sendable, Hashable {

        /// Downbeat times from answered windows only, ascending. Empty when every window
        /// declined — the same shape a track with no detected bars already produces.
        public let downbeats: [Double]

        /// The most-answered meter across the track, or `nil` when no window answered.
        /// Only a summary: `downbeats` is the truth, and windows may legitimately differ.
        public let modalMeter: Int?

        /// Fraction of the track's beats that fall inside an answered window, 0...1.
        public let coverage: Double

        /// How many windows answered, of how many scored.
        public let windowsAnswered: Int
        public let windowCount: Int

        /// Per-window estimates in track order, answered or not. Diagnostic.
        public let estimates: [BarLineEstimate]
    }

    /// Beats per scoring window. 80 beats is ~40 s at 120 BPM — long enough for the
    /// permutation null to separate a real bar from chance (PR.16 swept the threshold at
    /// this length: 19 correct, 0 incorrect over 68 labelled windows at 1.54), short
    /// enough that a section change does not have to be averaged away.
    public static let defaultBeatsPerWindow = 80

    // MARK: - Public API

    /// Estimate bar position per window over a whole track.
    ///
    /// - Parameters:
    ///   - beats: Beat times in seconds, ascending — a whole-track grid, not a 30 s window.
    ///   - audio: Mono samples of the whole track.
    ///   - sampleRate: Sample rate of `audio`.
    ///   - beatsPerWindow: Beats per scoring window; the final window absorbs the
    ///     remainder rather than leaving the track's tail unscored.
    public static func estimateWindowed(
        beats: [Double],
        audio: [Float],
        sampleRate: Double = 22050.0,
        options: Options = .legacy,
        beatsPerWindow: Int = defaultBeatsPerWindow
    ) -> WindowedBarLine {
        guard let smallest = meters.min(), beats.count > smallest * 2 else {
            return WindowedBarLine(
                downbeats: [],
                modalMeter: nil,
                coverage: 0,
                windowsAnswered: 0,
                windowCount: 0,
                estimates: [.declined(.tooFewBeats)]
            )
        }
        var workingAudio = audio
        var workingRate = sampleRate
        if options.resampleToReferenceRate, sampleRate != referenceSampleRate {
            workingAudio = BeatThisPreprocessor.resample(
                audio, from: sampleRate, to: referenceSampleRate)
            workingRate = referenceSampleRate
        }
        let features = beatFeatures(
            audio: workingAudio,
            beats: beats,
            sampleRate: workingRate,
            fullBeatWindow: options.fullBeatWindow,
            chromaOnly: options.beatAveragedChromaOnly
        )

        var downbeats: [Double] = []
        var estimates: [BarLineEstimate] = []
        var meterCounts: [Int: Int] = [:]
        var coveredBeats = 0

        for range in windowRanges(beatCount: beats.count, beatsPerWindow: beatsPerWindow) {
            let sliced = features.map { Array($0[range]) }
            let estimate = score(features: sliced)
            estimates.append(estimate)
            guard let meter = estimate.beatsPerBar, let phase = estimate.barLinePhase else {
                continue
            }
            meterCounts[meter, default: 0] += 1
            coveredBeats += range.count
            // `phase` is relative to the window's own first beat, so offset it back.
            for (offset, index) in range.enumerated() where offset % meter == phase {
                downbeats.append(beats[index])
            }
        }

        let answered = estimates.count { $0.isConfident }
        return WindowedBarLine(
            downbeats: downbeats,
            // Most-answered meter; ties break toward the SMALLER one, deterministically.
            modalMeter: meterCounts.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }?.key,
            coverage: Double(coveredBeats) / Double(beats.count),
            windowsAnswered: answered,
            windowCount: estimates.count,
            estimates: estimates
        )
    }

    /// Contiguous window boundaries covering every beat. The last window absorbs a
    /// remainder shorter than `beatsPerWindow` rather than dropping the track's tail —
    /// PR.15's probe dropped it, which is fine for a measurement and not for playback.
    static func windowRanges(beatCount: Int, beatsPerWindow: Int) -> [Range<Int>] {
        guard beatsPerWindow > 0, beatCount > 0 else { return [] }
        let full = max(1, beatCount / beatsPerWindow)
        var ranges: [Range<Int>] = []
        for index in 0..<full {
            let start = index * beatsPerWindow
            let end = index == full - 1 ? beatCount : start + beatsPerWindow
            ranges.append(start..<end)
        }
        return ranges
    }
}

// BarLineEstimator — FT.3: which beat is the bar line, from the audio at the beat times.
//
// Four independent levers failed to get bar position out of Beat This!'s downbeat
// activation stream (D-208 + its FT.1 amendment): a different onset source (TRK.2), an
// unbiased decoder (DBN.2), a 10x larger model (MDL.1), and 13-25x more context (FT.1).
// The premise this file changes is that beats are already good (suite-1 F 0.97), so on a
// local file the question is not "find the metrical structure" but "given 400-1000
// reliable beat times, which of them are bar lines" — a periodicity-and-phase search over
// a tiny integer space that never touches the downbeat stream.
//
// METHOD (ported from `tools/barline_probe.py` + `tools/barline_combine.py`; the evidence
// is `docs/diagnostics/BARLINE_PROBE_2026-07-31.md` and
// `docs/diagnostics/FT3_BARLINE_TASKS_1_3_2026-07-31.md`).
//
// Four beat-synchronous accent features, one value per beat, from a 2048-sample window
// starting at each beat: low-band energy (<200 Hz — the kick lands on 1), broadband RMS,
// spectral flux (change lands on bar lines), and harmonic change (chords change on bar
// lines). For each meter B in D-207's fixed set {3,4,5,7} and each phase p,
//
//     d(B,p) = (mean feature at bar-line beats - mean elsewhere) / sd(all beats)
//
// whose expectation is 0 under the null for ANY B — deliberately, because DBN.2 was
// derailed twice by a statistic whose bias scaled with B. That is not sufficient on its
// own: a larger B maximises over more phases with fewer samples each, so its
// max-over-phase is more chance-inflated. Every score is therefore reported against a
// PERMUTATION NULL and only the margin over that null counts.
//
// COMBINATION RULE: `sum_margin` — sum the four features' null-corrected margins per
// meter, take the argmax. FT.3 task 3 tested three candidate rules against a
// no-bar-information control and this was the only one that is both unbiased under the
// strict control and retains the probe's accuracy. The probe's own max-over-features rule
// FAILS that control, skewing its no-information picks toward meter 7 — the DBN.2 bias,
// present in this method's first published number.
//
// DETERMINISM: the permutation null uses a seeded SplitMix64 rather than a system RNG, so
// the same track always yields the same estimate, and so the Python reference and this
// port compute the *same* null rather than two Monte-Carlo samples of it (see
// `tools/barline_parity.py`). A Monte-Carlo null cannot be reproduced across languages to
// the 1e-3 the FT.3 spec's parity gate asks for; a shared PRNG can.
//
// SCOPE: offline / local-file only. It needs the whole track, and streaming exposes a 30 s
// preview before playback (D-170's scope limit, stated again here so it is not rediscovered).
// FT.3 delivers the estimator and its evidence — nothing calls it from the playback path.

import Accelerate
import Foundation

// MARK: - BarLineEstimate

/// The bar position of a track: a meter and a bar-line phase, **or** no confident bar.
///
/// D-207 fixed the output contract as "a meter **or** no confident bar" — `beatsPerBar`
/// alone cannot express the decline, so `decline` is part of the contract rather than a
/// diagnostic. D-210 adds a second decline reason (the grid at the wrong metrical level);
/// detecting that is FT.3.1's territory and is not decided here.
public struct BarLineEstimate: Sendable, Hashable, Codable {

    /// Why no bar was returned. `.none` means `beatsPerBar` and `barLinePhase` are set.
    public enum Decline: String, Sendable, Hashable, Codable {
        /// A bar was found with a margin at or above the decline threshold.
        case none
        /// Fewer beats than the shortest meter can score — nothing to search.
        case tooFewBeats
        /// The winning meter's margin did not clear `declineThreshold`. Silence and
        /// structureless audio land here: every meter scores ~0, so none clears the bar.
        case marginBelowThreshold
    }

    /// Beats per bar from D-207's set {3, 4, 5, 7}, or `nil` when declined.
    public let beatsPerBar: Int?

    /// Which beat of each bar is the bar line, as `beatIndex % beatsPerBar`.
    /// `nil` when declined. A correct meter on the wrong phase puts the accent on the
    /// wrong beat of every bar, so this is the load-bearing half of the output.
    public let barLinePhase: Int?

    /// The winning meter's summed null-corrected margin. Reported even when declined,
    /// because the decline threshold is set from this distribution.
    public let margin: Double

    /// Margin of the winner over the runner-up meter — the confidence signal.
    public let gapToRunnerUp: Double

    /// Per-meter summed margins for every hypothesis in D-207's set. Diagnostic.
    public let marginsByMeter: [Int: Double]

    /// Why this estimate declined, or `.none`.
    public let decline: Decline

    /// `true` when a meter and phase were returned.
    public var isConfident: Bool { decline == .none }

    /// A declined estimate carrying whatever evidence was gathered.
    static func declined(
        _ reason: Decline,
        margin: Double = 0,
        gap: Double = 0,
        marginsByMeter: [Int: Double] = [:]
    ) -> BarLineEstimate {
        BarLineEstimate(
            beatsPerBar: nil,
            barLinePhase: nil,
            margin: margin,
            gapToRunnerUp: gap,
            marginsByMeter: marginsByMeter,
            decline: reason
        )
    }
}

// MARK: - BarLineEstimator

/// Estimates bar position from beat-synchronous accent features. Offline, pure, and
/// deterministic: the same `(beats, audio)` always produces the same estimate.
public enum BarLineEstimator {

    // MARK: - Constants

    /// D-207 fixed the hypothesis set at {3,4,5,7} — every ground-truth meter plus waltz.
    /// 2 and 6 are excluded for the reason 6/9/12 were: they are sub- or super-multiples
    /// of a real bar, not candidate bars. Including 2 let kick-on-alternate-beats — a
    /// genuine periodicity that is *not* the bar — win the argmax on three tracks.
    public static let meters: [Int] = [3, 4, 5, 7]

    /// Analysis window per beat, in samples, and the FFT size. 2048 at 22050 Hz is 93 ms.
    static let nFFT = 2048
    static let log2n = vDSP_Length(11)

    /// Permutation draws for the null. Matches the Python reference.
    static let permutationDraws = 200

    /// Fixed seed for the null's PRNG. Any value works; it must match `barline_parity.py`.
    static let nullSeed: UInt64 = 20_260_731

    /// Minimum summed margin to return a bar rather than decline.
    ///
    /// Set from the measured margin distribution in FT.3 task 5, not from taste (D-207:
    /// "a threshold set from the margin's measured distribution"). See
    /// `docs/diagnostics/FT3_BARLINE_PORT_2026-08-19.md` for the distribution and the
    /// correct/incorrect overlap this operating point sits in.
    public static let declineThreshold: Double = 1.24

    // MARK: - Public API

    /// Estimate bar position for a whole track.
    ///
    /// - Parameters:
    ///   - beats: Beat times in seconds, ascending. Typically `BeatGrid.beats` from a
    ///     full-track decode (`BeatThisTiledInference`), not a 30 s window.
    ///   - audio: Mono samples of the whole track.
    ///   - sampleRate: Sample rate of `audio`. The reference measurement used 22050 Hz.
    /// - Returns: A meter and bar-line phase, or a declined estimate (D-207).
    public static func estimate(
        beats: [Double],
        audio: [Float],
        sampleRate: Double = 22050.0
    ) -> BarLineEstimate {
        guard let smallest = meters.min(), beats.count > smallest * 2 else {
            return .declined(.tooFewBeats)
        }
        let features = beatFeatures(audio: audio, beats: beats, sampleRate: sampleRate)
        return score(features: features)
    }

    /// The scoring half of `estimate`, split out so tests can drive it with synthetic
    /// features — including the no-bar-information control that rejected the probe's own
    /// combination rule (FT.3 task 3).
    static func score(features: [[Double]], draws: Int = permutationDraws) -> BarLineEstimate {
        var marginsByMeter: [Int: Double] = [:]
        var phaseByMeter: [Int: Int] = [:]

        for meter in meters {
            var total = 0.0
            var votes = [Double](repeating: 0, count: meter)
            for (index, feature) in features.enumerated() {
                let observed = contrasts(feature, meter: meter)
                let seed = nullSeed &+ UInt64(index) &* 1_000 &+ UInt64(meter)
                total += (observed.max() ?? 0) - nullMax(feature, meter: meter, seed: seed, draws: draws)
                for phase in 0..<meter { votes[phase] += observed[phase] }
            }
            marginsByMeter[meter] = total
            phaseByMeter[meter] = argmax(votes)
        }

        let winner = bestMeter(marginsByMeter)
        let margin = marginsByMeter[winner] ?? 0
        let runnerUp = meters.filter { $0 != winner }.compactMap { marginsByMeter[$0] }.max() ?? 0
        let gap = margin - runnerUp
        guard margin >= declineThreshold else {
            return .declined(
                .marginBelowThreshold,
                margin: margin,
                gap: gap,
                marginsByMeter: marginsByMeter
            )
        }
        return BarLineEstimate(
            beatsPerBar: winner,
            barLinePhase: phaseByMeter[winner],
            margin: margin,
            gapToRunnerUp: gap,
            marginsByMeter: marginsByMeter,
            decline: .none
        )
    }

    // MARK: - Statistic

    /// `d(meter, p)` for every phase at once: the standardised difference between the mean
    /// feature at beats whose index is `p` mod `meter` and the mean everywhere else.
    /// Expectation 0 under the null for **any** meter, which is the whole point.
    static func contrasts(_ feature: [Double], meter: Int) -> [Double] {
        let zeros = [Double](repeating: 0, count: meter)
        let count = feature.count
        guard count > meter else { return zeros }

        var sums = zeros
        var counts = zeros
        for (index, value) in feature.enumerated() {
            sums[index % meter] += value
            counts[index % meter] += 1
        }
        let total = sums.reduce(0, +)
        let mean = total / Double(count)
        var sumSquares = 0.0
        for value in feature { sumSquares += (value - mean) * (value - mean) }
        let sd = (sumSquares / Double(count)).squareRoot()
        guard sd >= 1e-12 else { return zeros }

        return (0..<meter).map { phase in
            let on = counts[phase]
            let off = Double(count) - on
            guard on >= 2, off >= 2 else { return 0 }
            return (sums[phase] / on - (total - sums[phase]) / off) / sd
        }
    }

    /// Mean max-over-phase contrast on shuffled features — the chance baseline for this
    /// meter. Only the margin over this counts; a raw `d` says nothing on its own because
    /// a larger meter maximises over more phases with fewer samples each.
    static func nullMax(
        _ feature: [Double], meter: Int, seed: UInt64, draws: Int = permutationDraws
    ) -> Double {
        guard draws > 0 else { return 0 }
        var rng = SplitMix64(seed: seed)
        var shuffled = feature
        var accumulated = 0.0
        for _ in 0..<draws {
            rng.shuffle(&shuffled)
            accumulated += contrasts(shuffled, meter: meter).max() ?? 0
        }
        return accumulated / Double(draws)
    }

    // MARK: - Selection helpers

    /// First index of the maximum, matching `numpy.argmax` tie-breaking.
    static func argmax(_ values: [Double]) -> Int {
        var best = 0
        for index in 1..<max(values.count, 1) where values[index] > values[best] { best = index }
        return best
    }

    /// Highest-margin meter, ties going to the earlier entry in `meters`. `margins` always
    /// holds every hypothesis, so there is always a winner — it may still be declined.
    private static func bestMeter(_ margins: [Int: Double]) -> Int {
        var winner = meters.first ?? 4
        var bestMargin = -Double.infinity
        for meter in meters {
            guard let margin = margins[meter], margin > bestMargin else { continue }
            bestMargin = margin
            winner = meter
        }
        return winner
    }
}

// MARK: - SplitMix64

/// A tiny fixed-spec PRNG, reimplemented identically in `tools/barline_parity.py`.
///
/// The null has to be *the same null* on both sides, not two samples of it — otherwise the
/// FT.3 parity gate is comparing Monte-Carlo noise. Reproducing numpy's PCG64 stream and
/// its exact call ordering is not worth the code; specifying our own generator is 15 lines
/// and also makes the estimator deterministic, which an engine component should be anyway.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// In-place Fisher-Yates. Applied repeatedly to the same buffer, matching the reference.
    mutating func shuffle(_ values: inout [Double]) {
        guard values.count > 1 else { return }
        for index in stride(from: values.count - 1, to: 0, by: -1) {
            let pick = Int(next() % UInt64(index + 1))
            values.swapAt(index, pick)
        }
    }
}

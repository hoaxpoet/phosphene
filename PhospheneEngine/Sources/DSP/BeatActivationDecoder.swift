// BeatActivationDecoder — bar-pointer decoding over Beat This! activations (DBN.2).
//
// Replaces `BeatGridResolver`'s independent per-frame peak-picking with a jointly
// decoded metrical path, so that "where is the bar line" is answered globally
// rather than locally. The spec, with every constant sourced, is
// `docs/design/DBN_DECODER_SPEC.md`; read it before changing a number here.
//
// Why this exists (spec §2): Beat This!'s own authors measured a DBN on this model
// and it LOWERED F1 (beat 89.1→88.1, downbeat 78.3→77.4). Its one measured benefit
// was continuity — "correcting some of the (wrongly) non-periodic outputs" — and
// DBN.1 established that is exactly our failure mode: on odd-meter tracks the model
// emits a confident downbeat on 69–90 % of beats, so peak-picking has no way to pick
// which subset is the bar line. This decoder imposes periodicity; it does not, and
// cannot, add signal that is not in the activations.
//
// Model: the bar pointer of Krebs, Böck & Widmer, "An Efficient State-Space Model for
// Joint Tempo and Meter Tracking", ISMIR 2015 (CC BY 4.0), with the observation model
// of Böck, Krebs & Widmer, ISMIR 2014 Eq. 3. Clean-room from the papers — no madmom
// code (D-077, `reference-port` §1).
//
// Thread safety: stateless value type; `decode` is pure.

import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "BeatActivationDecoder")

// MARK: - BeatActivationDecoder

/// Decodes beat/downbeat activation streams into a metrical path (beats, downbeats, meter).
public struct BeatActivationDecoder: Sendable {

    // MARK: - Tunables

    /// Every value is sourced to a paper equation or marked as a Phosphene tunable.
    /// See `docs/design/DBN_DECODER_SPEC.md` §3–§5 for the rationale behind each.
    public struct Tunables: Sendable {
        /// Meter hypotheses to decode. **Fixed at {3,4,5,7} by D-207** — widening this
        /// is a product decision, not an implementation one. Covers every meter in the
        /// ground-truth catalogue (4, 5, 7) plus waltz.
        public var meterHypotheses: [Int] = [3, 4, 5, 7]

        /// Half-width of the tempo search band as a fraction of the tempo hint.
        /// Phosphene tunable (spec §3.1) — we condition on the incumbent BPM estimate
        /// because tempo is not the broken axis; meter is.
        public var tempoBandFraction: Double = 0.10

        /// Number of tempo states, log-spaced across the band to mimic auditory JNDs
        /// (Krebs §2.3.2). Phosphene tunable; the spec's cost table sizes this.
        public var tempoStateCount: Int = 11

        /// λ in Krebs Eq. 10 — the tempo-change penalty, and **the category-3 lever**.
        /// Default 125 is Krebs §4.1's measured optimum for the RNN-activation tracker.
        /// Low → visuals chase tempo drift; high → visuals hold a steady pulse.
        /// Validation deferred: D-205 marked suite 3 (tempo changes) not measurable offline.
        public var tempoChangePenalty: Double = 125

        /// λ_o in Böck Eq. 3 — the proportion of each beat interval treated as "beat".
        /// Default 16 is the value the Böck-family implementations expose; adopted by
        /// convention rather than derived, because the paper states the admissible range
        /// but not a tuned value.
        public var observationLambda: Double = 16

        /// Weight on downbeat evidence relative to beat evidence (spec §5.1 — our
        /// derivation, not a ported equation). The direct control on the failure mode
        /// DBN.1 measured.
        ///
        /// **Swept at DBN.2 against the degenerate-downbeat fixture** (downbeats on
        /// every beat at 0.80, true bar line at 0.95). At the spec's initial 1.0 the
        /// decoder picks the WRONG meter — the beat/non-beat terms of Böck Eq. 3 swamp
        /// the downbeat evidence, and the per-frame margin is 0.0012, i.e. the meters
        /// are indistinguishable. Meter becomes correct from 2.0 up, and the margin
        /// grows monotonically: 3.0 → 0.0039, 5.0 → 0.0090, 8.0 → 0.0166, 20 → 0.047.
        ///
        /// 5.0 is chosen as mid-range: clear of the failure, without weighting downbeat
        /// evidence so heavily that a confidently-wrong downbeat stream overrides the
        /// beat evidence (the risk Beat This!'s own DBN A/B flags on clean 4/4).
        /// **Calibrated on synthetic fixtures — DBN.3's BeatBench A/B is what confirms
        /// it on real audio.**
        public var downbeatWeight: Double = 5.0

        /// Per-frame log-likelihood margin below which the decoder declines to name a
        /// meter (D-207: "decline when unsure").
        ///
        /// **Set from data, per D-207.** `DecoderMarginCalibrationTests` measured the
        /// margin on all 9 ground-truthed tracks with the incumbent BPM as the hint:
        ///
        /// | outcome | n | min | median | max |
        /// |---|---|---|---|---|
        /// | meter correct | 3 | 0.1439 | 0.1461 | 0.9150 |
        /// | meter wrong | 3 | 0.0110 | 0.0173 | 0.2677 |
        /// | no stable truth meter | 3 | 0.0068 | 0.0575 | 0.1208 |
        ///
        /// **The correct and wrong distributions OVERLAP** — correct bottoms out at
        /// 0.1439 while wrong reaches 0.2677 (take_five). No threshold separates them, so
        /// the margin is a **necessary but not sufficient** discriminator and this value
        /// is a tradeoff, not a decision boundary.
        ///
        /// 0.10 is chosen to lose nothing correct while declining as much as possible:
        /// it keeps all 3 real correct answers (0.1439+) and a clean synthetic 4/4
        /// (0.1158), and declines money (0.0110), solsbury_hill (0.0173), pyramid_song
        /// (0.0068) and yyz (0.0575). take_five (wrong, 0.2677) and clair_de_lune
        /// (no stable meter, 0.1208) still survive — those are the residual, and they are
        /// why DBN.3 must report decline-rate alongside meter accuracy.
        ///
        /// **n = 3 per class.** An operating point from nine tracks, not a calibrated
        /// statistic. Re-derive at DBN.3 against the full A/B and widen the ground-truth
        /// catalogue before trusting it further.
        public var meterMarginThreshold: Double = 0.10

        public init() {}
    }

    // MARK: - Result

    public struct Result: Sendable {
        /// Decoded beat times in seconds.
        public let beats: [Double]
        /// Decoded downbeat times in seconds (bar position 1 — Krebs Eq. 3).
        public let downbeats: [Double]
        /// Winning meter, or **nil when the decoder declined** (D-207). `nil` is a real
        /// outcome, not an error: consumers must handle "no confident bar".
        public let beatsPerBar: Int?
        /// Median tempo along the decoded path.
        public let bpm: Double
        /// Per-frame log-likelihood gap between the best and runner-up meter. Length
        /// normalised so it is comparable across tracks.
        public let meterMargin: Double
        /// True when `meterMargin` fell below the threshold.
        public let declined: Bool
        /// Total path log-likelihood per meter hypothesis, for diagnostics.
        public let perMeterLogLikelihood: [Int: Double]
    }

    // MARK: - Init

    public var tunables: Tunables

    public init(tunables: Tunables = Tunables()) {
        self.tunables = tunables
    }

    // MARK: - Decode

    /// Decode activation streams into a metrical path.
    ///
    /// - Parameters:
    ///   - beatProbs: per-frame beat probabilities, sigmoid-applied, [0,1].
    ///   - downbeatProbs: per-frame downbeat probabilities, same length.
    ///   - frameRate: activation frames per second (Beat This! = 50).
    ///   - tempoHintBPM: centre of the tempo search band — the incumbent
    ///     trimmed-mean-IOI estimate. Must be > 0.
    public func decode(
        beatProbs: [Float],
        downbeatProbs: [Float],
        frameRate: Double,
        tempoHintBPM: Double
    ) -> Result {
        let frames = min(beatProbs.count, downbeatProbs.count)
        guard frames > 1, frameRate > 0, tempoHintBPM > 0 else {
            return Self.emptyResult()
        }
        var best: (meter: Int, decode: MeterDecode)?
        var runnerUpLL = -Double.infinity
        var perMeter: [Int: Double] = [:]

        let input = DecodeInput(
            beatProbs: beatProbs,
            downbeatProbs: downbeatProbs,
            frames: frames,
            frameRate: frameRate,
            tempoHintBPM: tempoHintBPM
        )
        for meter in tunables.meterHypotheses where meter > 0 {
            guard let decoded = decodeMeter(meter: meter, input: input) else { continue }
            perMeter[meter] = decoded.logLikelihood
            if let previous = best, previous.decode.logLikelihood >= decoded.logLikelihood {
                runnerUpLL = max(runnerUpLL, decoded.logLikelihood)
            } else {
                if let previous = best { runnerUpLL = max(runnerUpLL, previous.decode.logLikelihood) }
                best = (meter, decoded)
            }
        }
        guard let winner = best else { return Self.emptyResult() }

        // Length-normalise so the margin is comparable across tracks of different length.
        let margin = runnerUpLL.isFinite
            ? (winner.decode.logLikelihood - runnerUpLL) / Double(frames)
            : Double.infinity
        let declined = margin < tunables.meterMarginThreshold

        return Result(
            beats: winner.decode.beats,
            downbeats: declined ? [] : winner.decode.downbeats,
            beatsPerBar: declined ? nil : winner.meter,
            bpm: winner.decode.bpm,
            meterMargin: margin,
            declined: declined,
            perMeterLogLikelihood: perMeter
        )
    }

    // MARK: - Per-meter Viterbi

    struct MeterDecode {
        let beats: [Double]
        let downbeats: [Double]
        let bpm: Double
        let logLikelihood: Double
    }

    /// Viterbi over the bar-pointer state space for one meter hypothesis.
    ///
    /// State space (Krebs §2.3.1): exactly one bar-position state per audio frame, so
    /// the pointer advances one position per frame and *tempo is encoded by how many
    /// positions the bar has* — `M(T) = round(B × 60 / (T × Δ))`, Krebs Eq. 7.
    /// Everything a per-meter decode needs, so the entry point stays inside the
    /// parameter-count limit and the tables below are built from one value.
    struct DecodeInput {
        let beatProbs: [Float]
        let downbeatProbs: [Float]
        let frames: Int
        let frameRate: Double
        let tempoHintBPM: Double
    }

    private func decodeMeter(meter: Int, input: DecodeInput) -> MeterDecode? {
        var space = StateSpace(
            meter: meter,
            tempoHintBPM: input.tempoHintBPM,
            frameRate: input.frameRate,
            bandFraction: tunables.tempoBandFraction,
            tempoStates: tunables.tempoStateCount
        )
        guard space.stateCount > 0, !space.tempi.isEmpty else { return nil }
        space.precomputeObservationClasses(lambda: tunables.observationLambda)
        let tables = ViterbiTables(space: space, input: input, tunables: tunables)
        guard let run = tables.run(frames: input.frames) else { return nil }
        return space.readOut(
            path: run.path, frameRate: input.frameRate, logLikelihood: run.logLikelihood
        )
    }

    /// Pick the precomputed per-frame term for a state's observation class.
    private static func term(
        _ terms: ObservationModel.FrameTerms,
        _ observationClass: StateSpace.ObservationClass
    ) -> Double {
        switch observationClass {
        case .downbeat: return terms.downbeat
        case .beat:     return terms.beat
        case .nonBeat:  return terms.nonBeat
        }
    }

    static func backtrace(back: [Int32], stateCount: Int, frames: Int, endState: Int) -> [Int] {
        var path = [Int](repeating: 0, count: frames)
        path[frames - 1] = endState
        var state = endState
        var k = frames - 1
        while k > 0 {
            let pred = back[k * stateCount + state]
            if pred < 0 { break }
            state = Int(pred)
            k -= 1
            path[k] = state
        }
        return path
    }

    private static func emptyResult() -> Result {
        Result(
            beats: [],
            downbeats: [],
            beatsPerBar: nil,
            bpm: 0,
            meterMargin: 0,
            declined: true,
            perMeterLogLikelihood: [:]
        )
    }
}

// BeatActivationDecoder+StateSpace — bar-pointer state space and observation model.
//
// Split from `BeatActivationDecoder.swift` to keep both files inside the SwiftLint
// file-length budget. Spec: `docs/design/DBN_DECODER_SPEC.md` §3 (state space),
// §4 (transitions), §5 (observation model).

import Foundation

// MARK: - State Space

extension BeatActivationDecoder {

    /// Discretised (bar position × tempo) space for one meter hypothesis.
    ///
    /// Krebs §2.3.1's "efficient" discretisation: exactly one bar-position state per
    /// audio frame. The pointer therefore advances one position per frame and the tempo
    /// is encoded by *how many positions the bar has* — `M(T)` from Krebs Eq. 7. Two
    /// nearby tempi that round to the same `M` are the same state chain, so they are
    /// deduplicated rather than decoded twice.
    struct StateSpace {
        let meter: Int
        /// Tempi in BPM, ascending, one per distinct position count.
        let tempi: [Double]
        /// `M(T)` per tempo — bar positions for that tempo.
        let positionCounts: [Int]
        /// Flat-index offset of each tempo's position block.
        let offsets: [Int]
        let stateCount: Int

        init(meter: Int, tempoHintBPM: Double, frameRate: Double,
             bandFraction: Double, tempoStates: Int) {
            self.meter = meter
            let delta = 1.0 / frameRate
            let lo = tempoHintBPM * (1 - bandFraction)
            let hi = tempoHintBPM * (1 + bandFraction)
            let count = max(1, tempoStates)

            // Log-spaced across the band, mimicking auditory JNDs (Krebs §2.3.2).
            var seen = Set<Int>()
            var tempi: [Double] = []
            var counts: [Int] = []
            for i in 0..<count {
                let tempoBPM: Double
                if count == 1 || hi <= lo {
                    tempoBPM = tempoHintBPM
                } else {
                    let frac = Double(i) / Double(count - 1)
                    tempoBPM = Foundation.exp(Foundation.log(lo) + (Foundation.log(hi) - Foundation.log(lo)) * frac)
                }
                // Krebs Eq. 7, generalised from the paper's 4-beat bar to `meter` beats.
                let positions = Int((Double(meter) * 60.0 / (tempoBPM * delta)).rounded())
                // Need at least one position per beat, or beat indices collide.
                guard positions >= meter, !seen.contains(positions) else { continue }
                seen.insert(positions)
                tempi.append(tempoBPM)
                counts.append(positions)
            }
            self.tempi = tempi
            self.positionCounts = counts
            var offsets: [Int] = []
            var running = 0
            for count in counts { offsets.append(running); running += count }
            self.offsets = offsets
            self.stateCount = running
        }

        /// Observation class of every state, precomputed once.
        ///
        /// The inner Viterbi loop runs `stateCount × frames × meters` times, so anything
        /// evaluated there must be a table lookup. Computing beat positions per state per
        /// frame (and calling `log` per state) measured **17 s** for a 30 s window against
        /// a 50 ms budget; the observation term depends only on (state) and (frame)
        /// separately, so both sides are precomputed and the inner loop is an index + add.
        enum ObservationClass: UInt8 { case downbeat, beat, nonBeat }

        /// `observationClass[state]` — parallel to the flat state index.
        private(set) var observationClasses: [ObservationClass] = []

        func positionCount(tempo: Int) -> Int { positionCounts[tempo] }

        func index(tempo: Int, position: Int) -> Int { offsets[tempo] + position }

        /// Fill `observationClasses`. Separate from `init` so the beat-window width,
        /// which depends on the observation model's λ_o, can be supplied by the caller.
        mutating func precomputeObservationClasses(lambda: Double) {
            var classes = [ObservationClass](repeating: .nonBeat, count: stateCount)
            for tempo in tempi.indices {
                let positions = positionCounts[tempo]
                let beatInterval = Double(positions) / Double(meter)
                let window = max(1.0, beatInterval / lambda)
                // Beat position of every beat, once.
                var beatPositions = [Int](repeating: 0, count: meter)
                for beat in 0..<meter { beatPositions[beat] = beatPosition(beat: beat, tempo: tempo) }
                for position in 0..<positions {
                    var sinceBeat = Double.infinity
                    var currentBeat = -1
                    for beat in 0..<meter {
                        var diff = Double(position - beatPositions[beat])
                        if diff < 0 { diff += Double(positions) }
                        if diff < sinceBeat { sinceBeat = diff; currentBeat = beat }
                    }
                    guard sinceBeat < window else { continue }
                    classes[offsets[tempo] + position] = currentBeat == 0 ? .downbeat : .beat
                }
            }
            self.observationClasses = classes
        }

        /// `beatIndex` for every position, precomputed — used by the transition step.
        /// −1 means "not a beat position".
        func precomputedBeatIndices() -> [Int32] {
            var out = [Int32](repeating: -1, count: stateCount)
            for tempo in tempi.indices {
                for beat in 0..<meter {
                    let position = beatPosition(beat: beat, tempo: tempo)
                    out[offsets[tempo] + position] = Int32(beat)
                }
            }
            return out
        }

        /// Bar position (0-based) of beat `b` in this tempo's grid.
        func beatPosition(beat: Int, tempo: Int) -> Int {
            let positions = positionCounts[tempo]
            return Int((Double(beat) * Double(positions) / Double(meter)).rounded()) % positions
        }

        /// Which beat this position starts, or nil when it is not a beat position.
        func beatIndex(tempo: Int, position: Int) -> Int? {
            for beat in 0..<meter where beatPosition(beat: beat, tempo: tempo) == position {
                return beat
            }
            return nil
        }

        /// The position one frame *before* beat `beat` in `tempo`'s grid, wrapping.
        func positionBefore(beat: Int, tempo: Int) -> Int {
            let position = beatPosition(beat: beat, tempo: tempo)
            return position == 0 ? positionCounts[tempo] - 1 : position - 1
        }

        /// Row-normalised log tempo-transition matrix.
        ///
        /// `f(Φ̇_k, Φ̇_{k−1}) = exp(−λ × |Φ̇_k/Φ̇_{k−1} − 1|)` (Krebs Eq. 10), normalised
        /// over destinations so that total path log-likelihoods stay comparable when
        /// different meter hypotheses have different state counts.
        func logTempoTransitions(penalty: Double) -> [[Double]] {
            let count = tempi.count
            var out = [[Double]](repeating: [Double](repeating: -.infinity, count: count), count: count)
            for i in 0..<count {
                var weights = [Double](repeating: 0, count: count)
                var total = 0.0
                for j in 0..<count {
                    let ratio = tempi[j] / tempi[i]
                    let weight = Foundation.exp(-penalty * abs(ratio - 1))
                    weights[j] = weight
                    total += weight
                }
                for j in 0..<count {
                    out[i][j] = total > 0 ? Foundation.log(weights[j] / total) : -.infinity
                }
            }
            return out
        }

        /// Convert a decoded state path into beat / downbeat times and a tempo.
        func readOut(path: [Int], frameRate: Double, logLikelihood: Double) -> MeterDecode {
            var beats: [Double] = []
            var downbeats: [Double] = []
            var tempoSamples: [Double] = []
            var previousBeat: Int?
            for (frame, state) in path.enumerated() {
                guard let tempo = tempoIndex(forState: state) else { continue }
                let position = state - offsets[tempo]
                tempoSamples.append(tempi[tempo])
                guard let beat = beatIndex(tempo: tempo, position: position) else {
                    previousBeat = nil
                    continue
                }
                // A beat position spans one frame here, but guard against emitting the
                // same beat twice if two adjacent frames map to the same beat index.
                if previousBeat == beat { continue }
                previousBeat = beat
                let time = Double(frame) / frameRate
                beats.append(time)
                if beat == 0 { downbeats.append(time) }
            }
            let bpm = tempoSamples.isEmpty ? 0 : Self.median(tempoSamples)
            return MeterDecode(
                beats: beats,
                downbeats: downbeats,
                bpm: bpm,
                logLikelihood: logLikelihood
            )
        }

        private func tempoIndex(forState state: Int) -> Int? {
            guard state >= 0, state < stateCount else { return nil }
            var lo = 0
            var hi = offsets.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if offsets[mid] <= state { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }

        private static func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
    }
}

// MARK: - Observation Model

extension BeatActivationDecoder {

    /// Böck et al. ISMIR 2014 Eq. 3, extended to Beat This!'s two activation streams.
    ///
    /// Eq. 3 as published, for a single activation `a_k`:
    /// ```
    /// P(a_k | φ_k) = a_k                    for 1 ≤ φ_k ≤ Φ/λ_o
    ///              = (1 − a_k)/(λ_o − 1)    otherwise
    /// ```
    /// Beat This! gives beat *and* downbeat streams and neither paper specifies how to
    /// combine them for a bar-pointer space, so the split below is **our derivation**
    /// (spec §5.1) and is the least-supported part of the model:
    ///   * bar position 1 — beat branch on `a_k`, plus downbeat evidence `d_k`
    ///   * other beat positions — beat branch on `a_k`, plus `(1 − d_k)` penalising a
    ///     downbeat firing off the bar line
    ///   * non-beat positions — non-beat branch on both
    struct ObservationModel {
        let lambda: Double
        let downbeatWeight: Double
        /// Keeps `log` finite when an activation saturates at 0 or 1.
        private static let epsilon = 1e-6

        /// Per-frame log-likelihood for each of the three observation classes.
        ///
        /// The class depends only on the state and the frame's activations only on the
        /// frame, so both are precomputed and the Viterbi inner loop does a lookup. This
        /// is what brings a 30 s decode from 17 s down into the 50 ms budget.
        struct FrameTerms {
            var downbeat: Double
            var beat: Double
            var nonBeat: Double
        }

        /// Three logs per frame instead of three per state per frame.
        func frameTerms(beatProbs: [Float], downbeatProbs: [Float], frames: Int) -> [FrameTerms] {
            var out = [FrameTerms](repeating: FrameTerms(downbeat: 0, beat: 0, nonBeat: 0),
                                   count: frames)
            let denominator = max(lambda - 1, 1)
            for k in 0..<frames {
                let beatProb = Self.clamp(Double(beatProbs[k]))
                let downbeatProb = Self.clamp(Double(downbeatProbs[k]))
                let logBeat = Foundation.log(beatProb)
                let logNotBeat = Foundation.log((1 - beatProb) / denominator)
                let logDown = Foundation.log(downbeatProb)
                let logNotDown = Foundation.log(1 - downbeatProb)
                out[k] = FrameTerms(
                    downbeat: logBeat + downbeatWeight * logDown,
                    beat: logBeat + downbeatWeight * logNotDown,
                    nonBeat: logNotBeat + downbeatWeight * logNotDown
                )
            }
            return out
        }

        private static func clamp(_ value: Double) -> Double {
            min(max(value, epsilon), 1 - epsilon)
        }
    }
}

extension BeatActivationDecoder.StateSpace {
    /// Internal accessor for the observation model (mirrors the private binary search).
    func tempoIndexForObservation(state: Int) -> Int? {
        guard state >= 0, state < stateCount else { return nil }
        var lo = 0
        var hi = offsets.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if offsets[mid] <= state { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}

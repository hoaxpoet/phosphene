// BeatActivationDecoder+Viterbi — the forward recursion and its flat tables.
//
// Split from `BeatActivationDecoder.swift` for the SwiftLint file-length budget.
// Everything the inner loop touches is precomputed and flattened: nested arrays cost a
// second indirection and a bounds check on each of ~8 M iterations, and recomputing beat
// positions or calling `log` per state per frame measured 17 s for a 30 s window against
// a 50 ms budget. Spec: `docs/design/DBN_DECODER_SPEC.md` §3–§5.

import Foundation

extension BeatActivationDecoder {

    // MARK: - Viterbi

    /// Flat, pointer-friendly tables plus the decode loop.
    ///
    /// Everything the inner loop touches is precomputed and flattened: nested arrays cost
    /// a second indirection and a bounds check on each of ~8 M iterations, and recomputing
    /// beat positions or calling `log` per state per frame measured 17 s for a 30 s window.
    struct ViterbiTables {
        let stateCount: Int
        let tempoCount: Int
        let meter: Int
        let offsets: [Int]
        let positionCounts: [Int]
        /// `[src * tempoCount + dst]` — Krebs Eq. 10, row-normalised.
        let transitions: [Double]
        /// Observation class per state, as a raw byte.
        let classes: [UInt8]
        /// `[frame * 3 + class]` — Böck Eq. 3 evaluated once per frame.
        let terms: [Double]
        /// Beat index per state, or −1 when the state is not a beat position.
        let beatOfState: [Int32]
        /// `[beat * tempoCount + src]` — predecessor state of each beat position.
        let beatPredecessors: [Int32]

        init(space: StateSpace, input: DecodeInput, tunables: Tunables) {
            self.stateCount = space.stateCount
            self.tempoCount = space.tempi.count
            self.meter = space.meter
            self.offsets = space.offsets
            self.positionCounts = space.positionCounts
            self.classes = space.observationClasses.map { $0.rawValue }
            self.beatOfState = space.precomputedBeatIndices()

            let logTrans = space.logTempoTransitions(penalty: tunables.tempoChangePenalty)
            var flatTrans = [Double](repeating: 0, count: tempoCount * tempoCount)
            for src in 0..<tempoCount {
                for dst in 0..<tempoCount {
                    flatTrans[src * tempoCount + dst] = logTrans[src][dst]
                }
            }
            self.transitions = flatTrans

            let observation = ObservationModel(
                lambda: tunables.observationLambda, downbeatWeight: tunables.downbeatWeight
            )
            let frameTerms = observation.frameTerms(
                beatProbs: input.beatProbs,
                downbeatProbs: input.downbeatProbs,
                frames: input.frames
            )
            var flatTerms = [Double](repeating: 0, count: input.frames * 3)
            for k in 0..<input.frames {
                flatTerms[k * 3] = frameTerms[k].downbeat
                flatTerms[k * 3 + 1] = frameTerms[k].beat
                flatTerms[k * 3 + 2] = frameTerms[k].nonBeat
            }
            self.terms = flatTerms

            var predecessors = [Int32](repeating: 0, count: space.meter * tempoCount)
            for beat in 0..<space.meter {
                for src in 0..<tempoCount {
                    let position = space.positionBefore(beat: beat, tempo: src)
                    predecessors[beat * tempoCount + src] =
                        Int32(space.index(tempo: src, position: position))
                }
            }
            self.beatPredecessors = predecessors
        }

        func run(frames: Int) -> (path: [Int], logLikelihood: Double)? {
            var delta = [Double](repeating: -.infinity, count: stateCount)
            var next = delta
            var back = [Int32](repeating: -1, count: stateCount * frames)
            let logUniform = -Foundation.log(Double(stateCount))   // Krebs §2.1.1

            transitions.withUnsafeBufferPointer { trans in
                classes.withUnsafeBufferPointer { cls in
                    terms.withUnsafeBufferPointer { termBuf in
                        beatOfState.withUnsafeBufferPointer { beatOf in
                            beatPredecessors.withUnsafeBufferPointer { beatPred in
                                back.withUnsafeMutableBufferPointer { backBuf in
                                    forward(
                                        frames: frames,
                                        logUniform: logUniform,
                                        delta: &delta,
                                        next: &next,
                                        buffers: Buffers(
                                            trans: trans,
                                            cls: cls,
                                            termBuf: termBuf,
                                            beatOf: beatOf,
                                            beatPred: beatPred,
                                            backBuf: backBuf
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            }
            guard let endState = delta.indices.max(by: { delta[$0] < delta[$1] }),
                  delta[endState].isFinite else { return nil }
            let path = BeatActivationDecoder.backtrace(
                back: back, stateCount: stateCount, frames: frames, endState: endState
            )
            return (path, delta[endState])
        }

        /// The six flat buffers the forward recursion indexes. A struct of
        /// `UnsafeBufferPointer`s is a value type holding raw pointers, so passing it adds
        /// no indirection — it just keeps the signatures inside the parameter-count limit.
        struct Buffers {
            let trans: UnsafeBufferPointer<Double>
            let cls: UnsafeBufferPointer<UInt8>
            let termBuf: UnsafeBufferPointer<Double>
            let beatOf: UnsafeBufferPointer<Int32>
            let beatPred: UnsafeBufferPointer<Int32>
            let backBuf: UnsafeMutableBufferPointer<Int32>
        }

        /// The forward pass.
        private func forward(
            frames: Int,
            logUniform: Double,
            delta: inout [Double],
            next: inout [Double],
            buffers: Buffers
        ) {
            delta.withUnsafeMutableBufferPointer { first in
                for state in 0..<stateCount {
                    first[state] = logUniform + buffers.termBuf[Int(buffers.cls[state])]
                }
            }
            for k in 1..<frames {
                let termBase = k * 3
                let backBase = k * stateCount
                delta.withUnsafeBufferPointer { prev in
                    next.withUnsafeMutableBufferPointer { cur in
                        step(
                            prev: prev,
                            cur: cur,
                            termBase: termBase,
                            backBase: backBase,
                            buffers: buffers
                        )
                    }
                }
                swap(&delta, &next)
            }
        }

        /// One frame of the forward recursion.
        private func step(
            prev: UnsafeBufferPointer<Double>,
            cur: UnsafeMutableBufferPointer<Double>,
            termBase: Int,
            backBase: Int,
            buffers: Buffers
        ) {
            for tempo in 0..<tempoCount {
                let base = offsets[tempo]
                let positions = positionCounts[tempo]
                for position in 0..<positions {
                    let state = base + position
                    var bestScore: Double
                    var bestPred: Int32
                    let beat = buffers.beatOf[state]
                    if beat >= 0 {
                        // Tempo may change only at a beat position (Krebs Eq. 9).
                        bestScore = -.infinity
                        bestPred = -1
                        let row = Int(beat) * tempoCount
                        for src in 0..<tempoCount {
                            let pred = buffers.beatPred[row + src]
                            let score = prev[Int(pred)] + buffers.trans[src * tempoCount + tempo]
                            if score > bestScore { bestScore = score; bestPred = pred }
                        }
                    } else {
                        // Deterministic advance within a tempo (Krebs Eq. 5).
                        bestPred = Int32(state - 1)
                        bestScore = prev[state - 1]
                    }
                    if bestScore > -.infinity {
                        cur[state] = bestScore + buffers.termBuf[termBase + Int(buffers.cls[state])]
                        buffers.backBuf[backBase + state] = bestPred
                    } else {
                        cur[state] = -.infinity
                    }
                }
            }
        }
    }
}

// BeatActivationDecoderTests — DBN.2 unit suite over synthetic activations.
//
// Cases are the ones pre-specified in `docs/design/DBN_DECODER_SPEC.md` §8, written
// before the decoder existed. Synthetic streams keep these deterministic: real audio
// scoring is DBN.3's BeatBench A/B, not this suite's job.
//
// The load-bearing case is `degenerateDownbeatStream` — it reduces DBN.1's measured
// failure mode (the model emitting a confident downbeat on 69–90 % of beats) to a
// fixture. If that one regresses, the decoder has stopped doing the only thing Beat
// This!'s own A/B says a DBN is good for.

import Testing
import Foundation
@testable import DSP

@Suite("BeatActivationDecoder")
struct BeatActivationDecoderTests {

    static let frameRate = 50.0

    // MARK: - Synthetic activations

    /// Beat/downbeat streams with Gaussian bumps on the grid.
    /// `downbeatOnEveryBeat` reproduces the degenerate stream DBN.1 measured.
    static func synth(
        bpm: Double, meter: Int, seconds: Double,
        downbeatOnEveryBeat: Bool = false,
        offBeatDownbeatLevel: Float = 0.0,
        bpmAt: ((Double) -> Double)? = nil
    ) -> (beats: [Float], downbeats: [Float]) {
        let frames = Int(seconds * frameRate)
        var beatProbs = [Float](repeating: 0.02, count: frames)
        var downbeatProbs = [Float](repeating: 0.02, count: frames)
        var time = 0.0
        var beatIndex = 0
        while time < seconds {
            let frame = Int(time * frameRate)
            if frame < frames {
                beatProbs[frame] = 0.95
                let isDownbeat = beatIndex % meter == 0
                if isDownbeat {
                    downbeatProbs[frame] = 0.95
                } else if downbeatOnEveryBeat {
                    downbeatProbs[frame] = offBeatDownbeatLevel
                }
            }
            let localBPM = bpmAt?(time) ?? bpm
            time += 60.0 / localBPM
            beatIndex += 1
        }
        return (beatProbs, downbeatProbs)
    }

    /// Uses the PRODUCTION defaults unless a value is explicitly overridden. Defaulting
    /// this parameter to a literal would silently mask the shipped tunable and make the
    /// suite green against a configuration nothing runs (FA #66, test/production divergence).
    static func decoder(downbeatWeight: Double? = nil) -> BeatActivationDecoder {
        var t = BeatActivationDecoder.Tunables()
        if let downbeatWeight { t.downbeatWeight = downbeatWeight }
        return BeatActivationDecoder(tunables: t)
    }

    // MARK: - Meter recovery

    @Test("clean 4/4 recovers meter 4")
    func test_clean44() {
        let (b, d) = Self.synth(bpm: 120, meter: 4, seconds: 20)
        let r = Self.decoder().decode(beatProbs: b, downbeatProbs: d,
                                      frameRate: Self.frameRate, tempoHintBPM: 120)
        #expect(r.beatsPerBar == 4, "expected meter 4, got \(String(describing: r.beatsPerBar))")
        #expect(!r.declined)
        #expect(abs(r.bpm - 120) < 12, "bpm \(r.bpm) far from 120")
    }

    @Test("clean 7/4 recovers meter 7 — the money / solsbury_hill case in isolation")
    func test_clean74() {
        let (b, d) = Self.synth(bpm: 120, meter: 7, seconds: 24)
        let r = Self.decoder().decode(beatProbs: b, downbeatProbs: d,
                                      frameRate: Self.frameRate, tempoHintBPM: 120)
        #expect(r.beatsPerBar == 7, "expected meter 7, got \(String(describing: r.beatsPerBar))")
    }

    @Test("clean 5/4 recovers meter 5 — the take_five case")
    func test_clean54() {
        let (b, d) = Self.synth(bpm: 150, meter: 5, seconds: 24)
        let r = Self.decoder().decode(beatProbs: b, downbeatProbs: d,
                                      frameRate: Self.frameRate, tempoHintBPM: 150)
        #expect(r.beatsPerBar == 5, "expected meter 5, got \(String(describing: r.beatsPerBar))")
    }

    // MARK: - The load-bearing case

    @Test("degenerate downbeat stream: picks a periodic subset where peak-picking cannot")
    func test_degenerateDownbeatStream() {
        // Downbeats fire on EVERY beat, only slightly stronger on the true bar line —
        // DBN.1 measured mean peak prob 0.805 on money with a 0.90 downbeat:beat ratio.
        let (b, d) = Self.synth(bpm: 120, meter: 4, seconds: 24,
                                downbeatOnEveryBeat: true, offBeatDownbeatLevel: 0.80)
        // Two separate properties, because D-207's decline policy landed AFTER this case
        // was specified and the two must not be conflated:
        //
        //   1. the MECHANISM — with declining disabled, does the decoder recover the bar
        //      line from a stream peak-picking cannot resolve?
        //   2. the POLICY — under production defaults it must never confidently name a
        //      WRONG meter. Declining here is a correct outcome, not a failure.
        var noDecline = BeatActivationDecoder.Tunables()
        noDecline.meterMarginThreshold = 0
        let mechanism = BeatActivationDecoder(tunables: noDecline).decode(
            beatProbs: b, downbeatProbs: d, frameRate: Self.frameRate, tempoHintBPM: 120
        )
        let ll = mechanism.perMeterLogLikelihood.sorted { $0.key < $1.key }
            .map { "\($0.key):\(String(format: "%.1f", $0.value))" }.joined(separator: "  ")
        print("[DBN.2 degenerate] per-meter logLik  \(ll)   margin \(mechanism.meterMargin)")
        #expect(mechanism.beatsPerBar == 4, """
            meter \(String(describing: mechanism.beatsPerBar)) with declining disabled — the \
            decoder failed the one job the Beat This! A/B says a DBN is for: imposing \
            periodicity on a non-periodic stream
            """)
        // Downbeats must be periodic — the property peak-picking cannot deliver.
        if mechanism.downbeats.count >= 3 {
            let gaps = zip(mechanism.downbeats.dropFirst(), mechanism.downbeats).map(-)
            let mean = gaps.reduce(0, +) / Double(gaps.count)
            let spread = gaps.map { abs($0 - mean) }.max() ?? 0
            #expect(spread < 0.15, "downbeat gaps not periodic: spread \(spread)s around \(mean)s")
        }

        let shipped = Self.decoder().decode(beatProbs: b, downbeatProbs: d,
                                            frameRate: Self.frameRate, tempoHintBPM: 120)
        #expect(shipped.beatsPerBar == 4 || shipped.beatsPerBar == nil, """
            production defaults named meter \(String(describing: shipped.beatsPerBar)) on an \
            ambiguous stream. Naming a WRONG meter confidently is the one outcome D-207 rules out
            """)
    }

    // MARK: - Tempo behaviour

    @Test("tempo ramp is followed without dropping beats")
    func test_tempoRamp() {
        let (b, d) = Self.synth(bpm: 120, meter: 4, seconds: 24,
                                bpmAt: { t in 120 * (1 + 0.05 * t / 24) })
        let r = Self.decoder().decode(beatProbs: b, downbeatProbs: d,
                                      frameRate: Self.frameRate, tempoHintBPM: 123)
        #expect(r.beatsPerBar == 4)
        #expect(r.beats.count > 30, "only \(r.beats.count) beats recovered from a ~48-beat ramp")
    }

    @Test("tempo step re-locks")
    func test_tempoStep() {
        let (b, d) = Self.synth(bpm: 120, meter: 4, seconds: 24,
                                bpmAt: { t in t < 12 ? 118 : 126 })
        let r = Self.decoder().decode(beatProbs: b, downbeatProbs: d,
                                      frameRate: Self.frameRate, tempoHintBPM: 122)
        #expect(r.beatsPerBar == 4)
        #expect(r.beats.count > 30, "only \(r.beats.count) beats across a tempo step")
    }

    // MARK: - Degenerate input

    @Test("silence does not crash and produces no confident meter")
    func test_silence() {
        let frames = Int(10 * Self.frameRate)
        let flat = [Float](repeating: 0.001, count: frames)
        let r = Self.decoder().decode(beatProbs: flat, downbeatProbs: flat,
                                      frameRate: Self.frameRate, tempoHintBPM: 120)
        #expect(r.downbeats.isEmpty || r.beatsPerBar != nil)   // must not trap
        _ = r.meterMargin
    }

    @Test("noise floor does not crash")
    func test_noiseFloor() {
        var rng = SystemRandomNumberGenerator()
        let frames = Int(10 * Self.frameRate)
        let noise = (0..<frames).map { _ in Float.random(in: 0.0...0.4, using: &rng) }
        let r = Self.decoder().decode(beatProbs: noise, downbeatProbs: noise,
                                      frameRate: Self.frameRate, tempoHintBPM: 120)
        _ = r.beatsPerBar
    }

    @Test("input shorter than one bar does not crash")
    func test_shorterThanOneBar() {
        let (b, d) = Self.synth(bpm: 120, meter: 4, seconds: 1.0)
        let r = Self.decoder().decode(beatProbs: b, downbeatProbs: d,
                                      frameRate: Self.frameRate, tempoHintBPM: 120)
        _ = r.beatsPerBar
    }

    @Test("empty and mismatched input is handled")
    func test_emptyInput() {
        let r = Self.decoder().decode(beatProbs: [], downbeatProbs: [],
                                      frameRate: Self.frameRate, tempoHintBPM: 120)
        #expect(r.beatsPerBar == nil)
        #expect(r.declined)
    }

    @Test("zero tempo hint is rejected rather than dividing by zero")
    func test_zeroTempoHint() {
        let (b, d) = Self.synth(bpm: 120, meter: 4, seconds: 5)
        let r = Self.decoder().decode(beatProbs: b, downbeatProbs: d,
                                      frameRate: Self.frameRate, tempoHintBPM: 0)
        #expect(r.beatsPerBar == nil)
    }

    // MARK: - Decline path (D-207)

    @Test("D-207: a high margin threshold forces a decline, and declining clears the bar")
    func test_declineWhenUnsure() {
        let (b, d) = Self.synth(bpm: 120, meter: 4, seconds: 20)
        var t = BeatActivationDecoder.Tunables()
        t.meterMarginThreshold = .greatestFiniteMagnitude   // nothing can clear this
        let r = BeatActivationDecoder(tunables: t).decode(
            beatProbs: b, downbeatProbs: d, frameRate: Self.frameRate, tempoHintBPM: 120
        )
        #expect(r.declined)
        #expect(r.beatsPerBar == nil, "declining must clear the meter, not report a guess")
        #expect(r.downbeats.isEmpty, "declining must withhold downbeats — presets gate on them")
        #expect(!r.beats.isEmpty, "declining the BAR must not throw away the beats")
    }

    @Test("DBN.2 sweep: downbeatWeight vs the degenerate stream")
    func test_downbeatWeightSweep() {
        guard ProcessInfo.processInfo.environment["PHOSPHENE_DBN2_SWEEP"] == "1" else { return }
        let (b, d) = Self.synth(bpm: 120, meter: 4, seconds: 24,
                                downbeatOnEveryBeat: true, offBeatDownbeatLevel: 0.80)
        for weight in [1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0] {
            let r = Self.decoder(downbeatWeight: weight).decode(
                beatProbs: b, downbeatProbs: d, frameRate: Self.frameRate, tempoHintBPM: 120
            )
            let ll = r.perMeterLogLikelihood.sorted { $0.key < $1.key }
                .map { "\($0.key):\(String(format: "%.1f", $0.value))" }.joined(separator: " ")
            print(String(format: "  w=%5.1f  meter=%@  margin=%.5f   %@",
                         weight, String(describing: r.beatsPerBar), r.meterMargin, ll))
        }
    }

    @Test("D-207: meter set is fixed at {3,4,5,7}")
    func test_meterHypothesisSetIsFixed() {
        #expect(BeatActivationDecoder.Tunables().meterHypotheses == [3, 4, 5, 7])
    }
}

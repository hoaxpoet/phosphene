// StaveTraceModel — Stave's motion model: pure CPU, no Metal.
//
// The `WitchlightPath` / `WitchlightStroke` split, applied to Stave: this file is the whole
// simulation (two history rings, the band trackers, the beat-rule times and the D-216 field
// tint), and `StaveTrace` is the Metal seam that uploads and draws it.
//
// The split is not cosmetic. It is what lets the QG.5 response-band gate measure the
// preset's visual response at all: `ResponseBandTests` constructs a runtime and replays real
// fixtures through it with no GPU, so a model welded to `MTLBuffer`s could not be gated
// (`AudioResponseMetrics` is declared on this type for exactly that reason). It also makes
// the trace geometry unit-testable without a device.

import Foundation
import Shared

// MARK: - StaveTraceModel

public final class StaveTraceModel: AudioResponseMetrics, @unchecked Sendable {

    // MARK: Gains

    /// **Per-trace gain is a precondition, not a tuning knob.** Melodic std is 4.4–17.5×
    /// below rhythm across the corpus (CHR.2 §2.1); at a shared gain the melodic trace is a
    /// flat line. Set so the corpus-median p95 excursion lands at ~0.30 NDC — measured
    /// p95|R| ≈ 0.65, p95|M| ≈ 0.094 across 15 tracks.
    public static let rhythmGain: Float = 0.30 / 0.65
    public static let melodicGain: Float = 0.30 / 0.094

    /// Soft saturation ceiling, tuned against p99 rather than 1.0 — deviation primitives
    /// spike to ~3× on real music (FA #73). `limit · tanh(x / limit)` is linear to within
    /// 4 % at the corpus median and compresses the 3.7× excursion span between Bleed and
    /// Dance Yrself Clean instead of clipping it off frame (CHR.2 qualification 2).
    /// **Decided over a running normaliser** (STAVE_DESIGN §6): a normaliser makes loud and
    /// quiet passages look identical, and "the music got louder" is half of what a plot is for.
    public static let saturationLimit: Float = 0.85

    /// The traces' band sits across the lower-middle of the frame, per reference
    /// `01_macro_dotted_traces_on_grid.png` — hazy atmosphere above, near-black beneath.
    public static let bandCentre: Float = -0.10

    /// `limit · tanh(x / limit)` — see `saturationLimit`.
    public static func softSaturate(_ value: Float) -> Float {
        saturationLimit * tanhf(value / saturationLimit)
    }

    // MARK: State

    public struct Sample {
        public var time: Float
        public var rhythm: Float
        public var melodic: Float
    }

    public private(set) var samples: [Sample] = []
    /// Times of beat-phase wraps — the vertical rules.
    public private(set) var beatTimes: [Float] = []
    public private(set) var clock: Float = 0

    public let configuration: StaveConfiguration

    private var subBass = StaveBandTracker(), lowBass = StaveBandTracker()
    private var midHigh = StaveBandTracker(), highMid = StaveBandTracker(), high = StaveBandTracker()
    private var tintDriver = StaveFieldTintDriver()
    private var lastBeatPhase: Float = 0

    /// Every drawn excursion of each trace, kept for the QG.5 metrics below. Bounded by the
    /// fixture length, which is ~1300 frames — no need for a reservoir.
    private var rhythmExcursions: [Float] = []
    private var melodicExcursions: [Float] = []

    public var fieldTint: Float { tintDriver.tint }
    public var tintMultiplyColour: SIMD3<Float> { tintDriver.multiplyColour }
    public var ruleDensity: Float { Float(beatTimes.count) }

    public init(configuration: StaveConfiguration = .init()) {
        self.configuration = configuration
    }

    // MARK: Tick

    public func advance(features: FeatureVector, stems: StemFeatures) {
        // The RENDER clock, never `accumulatedAudioTime`. The latter is energy-weighted by
        // definition, so it advances at a music-dependent rate — ~12× slower than wall-clock
        // on the CHR.2 captures. That makes it an animation phase, not a clock, and a
        // time-series plot needs a uniform axis or the whole window is warped.
        clock = features.time

        // POSITION — each band EMA-centred SEPARATELY and then summed, so a loud band cannot
        // drag its partner's pivot (FA #31).
        let rhythm = subBass.rel(features.subBass) + lowBass.rel(features.lowBass)
        let melodic = midHigh.rel(features.midHigh) + highMid.rel(features.highMid)
            + high.rel(features.high)

        tintDriver.advance(stems: stems, deltaTime: features.deltaTime)

        let interval = 1.0 / max(configuration.plotHz, 1)
        if samples.last.map({ clock - $0.time >= interval }) ?? true {
            samples.append(Sample(time: clock, rhythm: rhythm, melodic: melodic))
            // Recorded as DRAWN — after gain and soft saturation — so the QG.5 band is a
            // statement about what a viewer sees on screen, not about the raw primitive.
            // `RouteCoverageTests` already gates the primitive; this gates the picture.
            rhythmExcursions.append(abs(Self.softSaturate(rhythm * Self.rhythmGain)))
            melodicExcursions.append(abs(Self.softSaturate(melodic * Self.melodicGain)))
        }

        // Vertical rules from the beat-phase wrap. `beatsPerBar` is NOT stable within a track
        // (Billie Jean reads 4 in one segment and 3 in another), so every beat gets an
        // identical plain rule — no downbeat weighting, which would need a bar length the
        // capture cannot reliably supply. Density is handled meter-free (§5 decision (c)).
        if features.beatPhase01 < lastBeatPhase - 0.3 { beatTimes.append(clock) }
        lastBeatPhase = features.beatPhase01

        let cutoff = clock - configuration.window
        samples.removeAll { $0.time < cutoff }
        beatTimes.removeAll { $0 < cutoff }
    }

    /// Return to the cold-start state. Needed whenever one model instance is driven over
    /// more than one recording — the QG.5 gate replays three fixtures through one runtime.
    ///
    /// ⚠ It must clear the SAMPLE RING, not just the metric pools. The ring admits a new
    /// sample only when `clock - samples.last.time >= interval`, so a ring still holding the
    /// previous fixture's timestamps rejects every frame of the next one whose clock starts
    /// lower — the model then records nothing at all and `responseMetric` returns nil. That
    /// is what a metrics-only reset produced here, and it reads as "the route is dead"
    /// rather than as "the harness reused a runtime".
    public func reset() {
        samples.removeAll(keepingCapacity: true)
        beatTimes.removeAll(keepingCapacity: true)
        rhythmExcursions.removeAll(keepingCapacity: true)
        melodicExcursions.removeAll(keepingCapacity: true)
        subBass = StaveBandTracker()
        lowBass = StaveBandTracker()
        midHigh = StaveBandTracker()
        highMid = StaveBandTracker()
        high = StaveBandTracker()
        tintDriver = StaveFieldTintDriver()
        lastBeatPhase = 0
        clock = 0
    }

    // MARK: AudioResponseMetrics (QG.5)

    /// p95 of the DRAWN excursion, in NDC half-heights. An amplitude, so it is independent of
    /// how long the fixture happens to be — the protocol's "never a raw total" rule.
    public func responseMetric(_ name: String) -> Double? {
        switch name {
        case "rhythmTraceExcursion":  return Self.percentile(rhythmExcursions, 95).map(Double.init)
        case "melodicTraceExcursion": return Self.percentile(melodicExcursions, 95).map(Double.init)
        default: return nil
        }
    }

    private static func percentile(_ values: [Float], _ pct: Int) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, pct * (sorted.count - 1) / 100))
        return sorted[index]
    }
}

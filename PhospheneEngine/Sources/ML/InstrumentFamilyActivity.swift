// InstrumentFamilyActivity — per-family instrument activity from PANNs probs (IFC.3 / D-177).
//
// Turns PANNsMobileNetV1's 527-class AudioSet output into a small per-family
// activity vector (strings / brass / woodwinds / percussion) with temporal
// smoothing and per-family deviation normalization (D-026), so a faint-but-
// present family still produces a clean trigger. Recognition, not separation:
// trust the 4 families, not individual instruments (scoping doc §3).
//
// This is the IFC.3 interpretation layer; it does NOT touch FeatureVector /
// StemFeatures (that is IFC.4) — it consumes PANNs probs and emits a per-window
// activity vector the pre-analysis pipeline will later collect.
//
// The deviation tracker mirrors BandDeviationTracker (D-146): per-family EMA
// running average, seed-from-first-non-zero, additive `rel = (x − avg)·gain`,
// `dev = max(0, rel)`, reset on track change. The class→family taxonomy is the
// single source of truth shared with tools/panns_reference.py (cross-checked
// against the reference fixtures in tests).

import Foundation

// MARK: - InstrumentFamily

/// The four orchestral instrument families PANNs can reliably discriminate.
public enum InstrumentFamily: String, CaseIterable, Sendable {
    case strings
    case brass
    case woodwinds
    case percussion

    /// AudioSet (527-class) indices contributing to this family. Mirrors
    /// `tools/panns_reference.py` FAMILIES. woodwinds includes the
    /// "Wind instrument, woodwind instrument" catch-all (195) since oboe/bassoon
    /// have no dedicated AudioSet class; percussion is the orchestral set
    /// anchored on Timpani; brass excludes the vehicle/air/train/foghorn classes.
    public var audioSetClasses: [Int] {
        switch self {
        case .strings:    return [189, 190, 191, 192, 193, 194, 199]
        case .brass:      return [185, 186, 187, 188]
        case .woodwinds:  return [195, 196, 197, 198]
        case .percussion: return [161, 164, 168, 169, 171, 179, 180, 181, 182]
        }
    }

    /// Stable index into the `allCases`-aligned activity arrays.
    public var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Raw activity for one family = max class probability over its AudioSet
    /// classes. Pure (no state) — the reductions the tracker smooths over.
    public static func rawActivity(probs: [Float]) -> [Float] {
        allCases.map { family in
            family.audioSetClasses.reduce(Float(0)) { max($0, probs[$1]) }
        }
    }
}

// MARK: - InstrumentFamilyActivity

/// One family's values within a window.
public struct FamilyReading: Sendable {
    public let raw: Float
    public let smoothed: Float
    public let rel: Float
    public let dev: Float
}

/// Per-family activity for one analysis window. Arrays are aligned to
/// `InstrumentFamily.allCases` order (strings, brass, woodwinds, percussion).
public struct InstrumentFamilyActivity: Sendable {
    /// Max class probability per family (un-smoothed).
    public let raw: [Float]
    /// Raw, temporally smoothed by the tracker's short EMA.
    public let smoothed: [Float]
    /// Signed deviation of `smoothed` from the family's own running mean (D-026).
    public let rel: [Float]
    /// Positive deviation only — the clean trigger: `max(0, rel)`.
    public let dev: [Float]

    public subscript(_ family: InstrumentFamily) -> FamilyReading {
        let i = family.index
        return FamilyReading(raw: raw[i], smoothed: smoothed[i], rel: rel[i], dev: dev[i])
    }

    /// Smoothed activity packed for the GPU StemFeatures setter, in
    /// `InstrumentFamily.allCases` order (strings, brass, woodwinds, percussion).
    public var smoothedSIMD4: SIMD4<Float> {
        SIMD4(smoothed[0], smoothed[1], smoothed[2], smoothed[3])
    }
    /// Positive deviation packed for the GPU StemFeatures setter (same order).
    public var devSIMD4: SIMD4<Float> { SIMD4(dev[0], dev[1], dev[2], dev[3]) }

    /// All-zero activity (no family information available). Used as the live-frame
    /// fallback when no cached series is installed (track has no preview activity).
    public static let zero = InstrumentFamilyActivity(
        raw: [Float](repeating: 0, count: InstrumentFamily.allCases.count),
        smoothed: [Float](repeating: 0, count: InstrumentFamily.allCases.count),
        rel: [Float](repeating: 0, count: InstrumentFamily.allCases.count),
        dev: [Float](repeating: 0, count: InstrumentFamily.allCases.count))

    /// Sample a per-window activity `series` (Layer 5a) by live playback
    /// position. The series is at `hopSeconds` spacing; `playbackSeconds` is
    /// nearest-window-clamped into `[0, series.count)`.
    ///
    /// IFC.4 alignment caveat (scoping §4): the preview clip may not be the
    /// section currently playing, and tracks run longer than the ~30 s preview —
    /// past the series end this clamps to the last window. A small phase error
    /// reads as a small offset; section-accurate alignment is IFC.6 work.
    /// Returns `.zero` for an empty series.
    public static func sample(
        _ series: [InstrumentFamilyActivity],
        atPlaybackSeconds playbackSeconds: Double,
        hopSeconds: Double = 1.0
    ) -> InstrumentFamilyActivity {
        guard !series.isEmpty else { return .zero }
        let hop = max(hopSeconds, 1e-6)
        let idx = Int((max(0, playbackSeconds) / hop).rounded())
        return series[min(idx, series.count - 1)]
    }
}

// MARK: - InstrumentFamilyTracker

/// Streams PANNs per-window probs → per-family activity with smoothing +
/// deviation. Stateful across the windows of one preview clip; `reset()` on
/// track change. Mirrors `BandDeviationTracker` (D-146 / D-026).
public struct InstrumentFamilyTracker: Sendable {

    /// Short EMA on raw activity to suppress single-window cross-family confusion
    /// (a legato wind read as "strings" for one window). At the 1 s analysis hop
    /// this is a ~1.4-window time constant.
    public static let smoothingDecay: Float = 0.5
    /// Slower EMA for the deviation pivot (the family's own running mean) — ~10 s
    /// at the 1 s hop, so a sustained family still surfaces as deviation when it
    /// first enters.
    public static let devDecay: Float = 0.9
    /// Additive deviation gain (the band-primitive convention; tune against the
    /// real per-family p99 in IFC.6, per project_deviation_primitive_real_range).
    public static let devGain: Float = 2.0

    private var smoothEMA: [Float]
    /// Per-family running mean (deviation pivot). Sentinel 0 = unseeded.
    private var runningAvg: [Float]

    public init() {
        let count = InstrumentFamily.allCases.count
        smoothEMA = [Float](repeating: 0, count: count)
        runningAvg = [Float](repeating: 0, count: count)
    }

    /// Clear all state. Call on track change so the next clip's deviations are
    /// measured against its own audio.
    public mutating func reset() {
        for i in smoothEMA.indices { smoothEMA[i] = 0 }
        for i in runningAvg.indices { runningAvg[i] = 0 }
    }

    /// Derive per-family activity from one window's 527-class PANNs probabilities.
    public mutating func derive(probs: [Float]) -> InstrumentFamilyActivity {
        precondition(probs.count == PANNsMobileNetV1.classCount,
                     "probs.count \(probs.count) != \(PANNsMobileNetV1.classCount)")
        let raw = InstrumentFamily.rawActivity(probs: probs)
        let count = raw.count
        var smoothed = [Float](repeating: 0, count: count)
        var rel = [Float](repeating: 0, count: count)
        var dev = [Float](repeating: 0, count: count)
        for i in 0..<count {
            // Smoothing EMA (seed from the first value).
            smoothEMA[i] = smoothEMA[i] == 0 ? raw[i]
                : smoothEMA[i] * Self.smoothingDecay + raw[i] * (1 - Self.smoothingDecay)
            let value = smoothEMA[i]
            // Deviation pivot EMA (seed from the first non-zero so dev starts at 0).
            if runningAvg[i] == 0 && value > 0 { runningAvg[i] = value }
            runningAvg[i] = runningAvg[i] * Self.devDecay + value * (1 - Self.devDecay)
            let signed = (value - runningAvg[i]) * Self.devGain
            smoothed[i] = value
            rel[i] = signed
            dev[i] = max(0, signed)
        }
        return InstrumentFamilyActivity(raw: raw, smoothed: smoothed, rel: rel, dev: dev)
    }
}

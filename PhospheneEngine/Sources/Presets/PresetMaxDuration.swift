// PresetMaxDuration — Computed `maxDuration(forSection:)` framework (V.7.6.2 §5).
//
// Formula source: docs/ARACHNE_V8_DESIGN.md §5.2. Coefficients live in code so
// tuning passes (V.7.6.C calibration) are reviewed via test, not data files.
//
// `maxDuration` is a *hard ceiling* on segment length. `PresetDescriptor.duration`
// becomes a preference hint (V.7.6.2 migration); the SessionPlanner uses this
// computed property to constrain segments.
//
// JSON contract: only `natural_cycle_seconds` (optional Float) is added to the
// preset sidecar schema. Everything else is derived from existing V.4 fields.

import Foundation

// MARK: - PresetDescriptor + maxDuration

public extension PresetDescriptor {

    // MARK: - Tunable coefficients (V.7.6.2 §5.2)
    //
    // These values come from ARACHNE_V8_DESIGN.md §5.2 verbatim. Calibration pass
    // (V.7.6.C) may tune them; current values are the §5.2 defaults.

    /// Base maxDuration ceiling (seconds) before motion / fatigue / density adjustments.
    private static let baseDurationSeconds: Double = 90.0

    /// Multiplier applied to `(motionIntensity - 0.5)`. Negative coefficient: high-motion
    /// presets shorten faster than low-motion ones.
    private static let motionPenalty: Double = -50.0

    /// Multiplier applied to `fatigueRisk.score` (low=0, medium=1, high=2). Negative:
    /// fatiguing presets shorten.
    private static let fatiguePenalty: Double = -30.0

    /// Multiplier applied to `(visualDensity - 0.5)`. Negative: dense presets shorten.
    private static let densityPenalty: Double = -15.0

    /// Section-adjustment shape: `out = baseMax × (sectionBase + sectionDynamicRange × dynamicRange)`.
    /// `sectionBase = 0.7`, range coefficient = `0.6` per §5.2.
    private static let sectionAdjustBase: Double = 0.7
    private static let sectionAdjustDynamicRangeCoef: Double = 0.6

    /// Synthetic dynamic range used when `currentSection` is nil (no section context).
    private static let defaultSectionDynamicRange: Double = 0.5

    // MARK: - SongSection -> dynamic range

    /// Default `sectionDynamicRange` per `SongSection`. Empirical defaults per §5.2 —
    /// peak/buildup are the most varied, ambient/comedown the least. V.7.6.C may
    /// calibrate these; current values are the §5.2 spec defaults.
    private static func defaultDynamicRange(for section: SongSection?) -> Double {
        guard let section else { return defaultSectionDynamicRange }
        switch section {
        case .ambient:  return 0.30
        case .buildup:  return 0.65
        case .peak:     return 0.80
        case .bridge:   return 0.50
        case .comedown: return 0.35
        }
    }

    // MARK: - FatigueRisk score helper

    private var fatigueRiskScore: Double {
        switch fatigueRisk {
        case .low:    return 0
        case .medium: return 1
        case .high:   return 2
        }
    }

    // MARK: - Public API

    /// Computed maximum segment length for this preset paired with `section`
    /// (V.7.6.2 §5).
    ///
    /// Formula (§5.2):
    /// ```
    /// baseMax = 90 + (-50) * (motionIntensity - 0.5)
    ///             + (-30) * fatigueRisk.score
    ///             + (-15) * (visualDensity - 0.5)
    /// out     = baseMax * (0.7 + 0.6 * sectionDynamicRange)
    /// if naturalCycleSeconds is set: return min(naturalCycleSeconds, out)
    /// ```
    ///
    /// Returns seconds; never negative (clamped at 0).
    func maxDuration(forSection section: SongSection?) -> TimeInterval {
        let baseMax = Self.baseDurationSeconds
            + Self.motionPenalty   * (Double(motionIntensity) - 0.5)
            + Self.fatiguePenalty  * fatigueRiskScore
            + Self.densityPenalty  * (Double(visualDensity) - 0.5)

        let dynamicRange = Self.defaultDynamicRange(for: section)
        let adjusted = baseMax
            * (Self.sectionAdjustBase + Self.sectionAdjustDynamicRangeCoef * dynamicRange)

        let computed = max(0, adjusted)
        if let cycle = naturalCycleSeconds {
            return min(TimeInterval(cycle), computed)
        }
        return computed
    }

    /// Convenience: max duration ignoring section context (uses 0.5 default).
    var defaultMaxDuration: TimeInterval { maxDuration(forSection: nil) }
}

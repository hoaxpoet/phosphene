// PresetMaxDuration — Computed `maxDuration(forSection:)` framework (V.7.6.2 §5).
//
// Formula source: docs/ARACHNE_V8_DESIGN.md §5.2. Coefficients live in code so
// tuning passes (V.7.6.C calibration) are reviewed via test, not data files.
//
// `maxDuration` is a *hard ceiling* on segment length. `PresetDescriptor.duration`
// becomes a preference hint (V.7.6.2 migration); the SessionPlanner uses this
// computed property to constrain segments.
//
// JSON contract: `natural_cycle_seconds` (Float?) and `is_diagnostic` (Bool, default
// false) are the additions to the preset sidecar schema. Everything else is derived
// from existing V.4 fields.

import Foundation

// MARK: - PresetDescriptor + maxDuration

public extension PresetDescriptor {

    // MARK: - Tunable coefficients (V.7.6.C calibrated)
    //
    // These values were calibrated in V.7.6.C against the §5.3 reference table.
    // Section linger factors implement Option B from V.7.6.C review: ambient/peak
    // linger (slow + climactic moments hold the viewer), buildup/bridge are
    // transitional (preset change feels natural).

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

    /// Section-adjustment shape: `out = baseMax × (sectionBase + sectionLingerWeight × lingerFactor)`.
    /// `sectionBase = 0.7`, `sectionLingerWeight = 0.6` per §5.2.
    private static let sectionAdjustBase: Double = 0.7
    private static let sectionLingerWeight: Double = 0.6

    /// Synthetic linger factor used when `currentSection` is nil (no section context).
    /// 0.5 is the neutral midpoint of the per-section table.
    private static let defaultSectionLingerFactor: Double = 0.5

    // MARK: - SongSection -> linger factor

    /// Per-section linger factor — higher values extend `maxDuration`, lower values shorten it.
    /// V.7.6.C Option B: ambient and peak linger (meditative + emotional core), buildup
    /// and bridge are transitional moments where preset changes feel natural.
    private static func defaultLingerFactor(for section: SongSection?) -> Double {
        guard let section else { return defaultSectionLingerFactor }
        switch section {
        case .ambient:  return 0.80
        case .peak:     return 0.75
        case .comedown: return 0.65
        case .buildup:  return 0.40
        case .bridge:   return 0.35
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
    /// Diagnostic presets (`isDiagnostic == true`) are exempt from the framework and
    /// return `.infinity` — they remain in place until manually switched.
    ///
    /// Formula (§5.2, V.7.6.C calibrated):
    /// ```
    /// if isDiagnostic: return .infinity
    /// baseMax = 90 + (-50) * (motionIntensity - 0.5)
    ///             + (-30) * fatigueRisk.score
    ///             + (-15) * (visualDensity - 0.5)
    /// out     = baseMax * (0.7 + 0.6 * lingerFactor(section))
    /// if naturalCycleSeconds is set: return min(naturalCycleSeconds, out)
    /// ```
    ///
    /// Returns seconds; never negative (clamped at 0).
    func maxDuration(forSection section: SongSection?) -> TimeInterval {
        if isDiagnostic { return .infinity }

        let baseMax = Self.baseDurationSeconds
            + Self.motionPenalty * (Double(motionIntensity) - 0.5)
            + Self.fatiguePenalty * fatigueRiskScore
            + Self.densityPenalty * (Double(visualDensity) - 0.5)

        let lingerFactor = Self.defaultLingerFactor(for: section)
        let adjusted = baseMax
            * (Self.sectionAdjustBase + Self.sectionLingerWeight * lingerFactor)

        let computed = max(0, adjusted)
        if let cycle = naturalCycleSeconds {
            return min(TimeInterval(cycle), computed)
        }
        return computed
    }

    /// Convenience: max duration ignoring section context (uses 0.5 default).
    var defaultMaxDuration: TimeInterval { maxDuration(forSection: nil) }
}

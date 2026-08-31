// QualityCeiling — User-controlled visual quality preset.
//
// Affects how DefaultPresetScorer applies complexity-cost exclusion gates:
//   .performance  — lowers the exclusion threshold to ~12 ms (power-save mode)
//   .auto         — standard behaviour, same gate as .balanced
//   .balanced     — default frame-budget governor applies
//   .ultra        — disables complexity-cost exclusion entirely (for recording sessions)
//
// Actual renderer-side enforcement (SSGI off, step-count reduction) is Inc 6.2 scope.
// U.8 plumbs the value through SettingsStore → PresetScoringContext.

import Foundation
import Shared

// MARK: - QualityCeiling

/// Controls how aggressively the preset scorer filters complex presets.
public enum QualityCeiling: String, Codable, CaseIterable, Sendable {
    /// Matches `.balanced` behaviour; distinct label for user clarity.
    case auto
    /// Lowers complexity-cost exclusion to ~12 ms. Favours lighter presets.
    case performance
    /// Standard behaviour — frame-budget governor applies. Default.
    case balanced
    /// Disables complexity-cost exclusion. For recording or M3/M4 capture sessions.
    case ultra

    // MARK: - Thresholds

    /// Complexity-cost threshold (ms) above which presets are excluded.
    ///
    /// Returns `nil` when the ceiling is `.ultra` (no exclusion gate).
    public func complexityThresholdMs(for tier: DeviceTier) -> Float? {
        switch self {
        case .performance: return 12.0
        case .auto, .balanced: return tier.frameBudgetMs
        case .ultra: return nil
        }
    }
}

// PresetCategory — Visual aesthetic families for preset classification.
// Mirrors the cream-of-crop Milkdrop pack's 10 theme directories + 1 transition slot.
// See docs/DECISIONS.md D-123 for the cream-of-crop alignment rationale.

import Foundation

// MARK: - PresetCategory

/// Visual aesthetic family for classifying presets.
///
/// The 10 aesthetic values mirror the cream-of-crop Milkdrop pack's theme
/// directories — a 20+ year curated taxonomy battle-tested against ~9,800
/// presets. Phase MD inspired-by uplifts ingest cleanly into this set;
/// Phosphene-originals are filed to whichever theme their visual register
/// best matches. The `transition` slot is reserved for the small set of
/// transition-style presets cream-of-crop also keeps separate.
///
/// Diagnostic presets (Spectral Cartograph, Staged Sandbox) carry no
/// `family` — they are identified by `is_diagnostic: true` and are not
/// aesthetic content (D-123).
public enum PresetCategory: String, Sendable, CaseIterable, Codable {
    case waveform
    case fractal
    case geometric
    case particles
    case hypnotic
    case supernova
    case reaction
    case drawing
    case dancer
    case sparkle
    case transition
}

// MARK: - Display

public extension PresetCategory {
    /// Human-readable label for user-facing toasts and UI (U.6b).
    var displayName: String {
        switch self {
        case .waveform:    return "Waveform"
        case .fractal:     return "Fractal"
        case .geometric:   return "Geometric"
        case .particles:   return "Particles"
        case .hypnotic:    return "Hypnotic"
        case .supernova:   return "Supernova"
        case .reaction:    return "Reaction"
        case .drawing:     return "Drawing"
        case .dancer:      return "Dancer"
        case .sparkle:     return "Sparkle"
        case .transition:  return "Transition"
        }
    }
}

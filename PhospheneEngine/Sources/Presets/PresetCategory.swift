// PresetCategory — Visual aesthetic families for preset classification.
// Used by the Orchestrator to avoid repeating the same category in succession.

import Foundation

// MARK: - PresetCategory

/// Visual aesthetic family for classifying presets.
///
/// The Orchestrator uses categories to ensure visual variety — it avoids
/// selecting presets from the same category in consecutive transitions.
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
    case transition
    case abstract
    case fluid
    /// Real-time diagnostic instrument for MIR pipeline observability.
    case instrument
    /// Organic, natural-world motion: bioluminescent strands, mycelium, arachnid geometry.
    case organic
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
        case .transition:  return "Transition"
        case .abstract:    return "Abstract"
        case .fluid:       return "Fluid"
        case .instrument:  return "Instrument"
        case .organic:     return "Organic"
        }
    }
}

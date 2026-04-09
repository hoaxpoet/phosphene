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
}

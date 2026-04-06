// PresetCategory — Visual aesthetic families for preset classification.
// Used by the Orchestrator to avoid repeating the same category in succession.

import Foundation

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
}

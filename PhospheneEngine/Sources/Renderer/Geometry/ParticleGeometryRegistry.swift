// ParticleGeometryRegistry — Catalog of preset names with a registered
// `ParticleGeometry` conformer.
//
// Mirrors the dispatch table in `VisualizerEngine.resolveParticleGeometry`
// (app layer). Adding a new particle preset means adding the name here,
// the factory call in `VisualizerEngine.init`, and the case in
// `resolveParticleGeometry`.
//
// Lives in a separate file from `ParticleGeometry.swift` so the protocol
// surface stays byte-identical across DM.1 (D-097 carry-forward — the
// DM.1 verification checklist requires `git diff` against
// `ParticleGeometry.swift` to return zero).
//
// `ParticleDispatchRegistryTests` walks the production preset catalog and
// asserts every preset whose `passes` contains `.particles` is listed
// here, closing the silent-fall-through hole where a JSON-side typo in
// the preset name would render an audio-driven backdrop with no
// particles.

import Foundation

// MARK: - ParticleGeometryRegistry

public enum ParticleGeometryRegistry {

    /// All preset names with a registered `ParticleGeometry` conformer.
    /// "Murmuration" is a literal because `ProceduralGeometry` is part of
    /// DM.0's frozen surface (D-097) and cannot host a static identifier.
    public static let knownPresetNames: Set<String> = [
        "Murmuration"
    ]
}

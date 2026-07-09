// AudioRoutePrimitives — the canonical map from an `audio_routes` primitive name
// (Swift FeatureVector/StemFeatures field) to the session-CSV column that records
// it. Single source for two consumers (QG.1):
//
//   • AudioRouteSchemaTests — an `audio_routes.primitive` not in this map fails
//     the schema gate (catches typos / fields with no recordable column).
//   • RouteCoverageTests — resolves each declared primitive to its per-frame
//     series from a replayed session directory to assert per-kind activity.
//
// Only primitives that a preset can legitimately route AND that the session
// recorder writes belong here. Diagnostic/perf columns (frame_cpu_ms, …) and
// non-audio fields (time, deltaTime, aspect) are deliberately absent — they are
// not routes. CPU-derived StemFeatures fields the offline fixture cannot populate
// (cachedBassProportion, totalEnergySmoothed, auroraPalettePhase,
// auroraOrbitAzimuth, drumsEnergyDevSmoothed) are also absent: they exist on the
// type but the route-coverage fixture mechanism can't exercise them, so they are
// documented as a coverage gap rather than declared (see QG1_REPLAY_AUDIT.md).

import Foundation

/// Where a route primitive is recorded, and how to read it back.
public struct RoutePrimitiveColumn: Sendable {
    /// Which session CSV holds the column.
    public enum File: Sendable { case features, stems }
    public let file: File
    /// Exact CSV column name (the header is column-inconsistent — some camelCase,
    /// some snake_case — so this is explicit, never derived).
    public let column: String
    /// Multiplier applied to the raw cell (e.g. `barPhase01` is stored as an
    /// integer permille → 0.001 to recover 0…1). Default 1.
    public let scale: Float

    public init(_ file: File, _ column: String, scale: Float = 1) {
        self.file = file
        self.column = column
        self.scale = scale
    }
}

public enum AudioRoutePrimitives {

    /// The allowlist: every routable primitive → its recorded column.
    public static let map: [String: RoutePrimitiveColumn] = {
        var out: [String: RoutePrimitiveColumn] = [:]
        // FeatureVector — three-band + 6-band energies.
        for name in ["bass", "mid", "treble", "subBass", "lowBass", "lowMid",
                     "midHigh", "highMid", "high"] {
            out[name] = RoutePrimitiveColumn(.features, name)
        }
        // Attenuated bands (QG.1 appended, snake in CSV).
        out["bassAtt"]  = RoutePrimitiveColumn(.features, "bass_att")
        out["midAtt"]   = RoutePrimitiveColumn(.features, "mid_att")
        out["trebleAtt"] = RoutePrimitiveColumn(.features, "treble_att")
        // Beat accents + spectral features (camelCase in CSV).
        for name in ["beatBass", "beatMid", "beatTreble", "beatComposite",
                     "spectralCentroid", "spectralFlux", "valence", "arousal",
                     "beatPhase01", "bassRel", "bassDev", "bassAttRel",
                     "accumulatedAudioTime", "beatsPerBar"] {
            out[name] = RoutePrimitiveColumn(.features, name)
        }
        // Deviation family for mid/treb (QG.1 appended, snake in CSV).
        out["midRel"]    = RoutePrimitiveColumn(.features, "mid_rel")
        out["midDev"]    = RoutePrimitiveColumn(.features, "mid_dev")
        out["trebRel"]   = RoutePrimitiveColumn(.features, "treb_rel")
        out["trebDev"]   = RoutePrimitiveColumn(.features, "treb_dev")
        out["midAttRel"] = RoutePrimitiveColumn(.features, "mid_att_rel")
        out["trebAttRel"] = RoutePrimitiveColumn(.features, "treb_att_rel")
        out["beatsUntilNext"] = RoutePrimitiveColumn(.features, "beats_until_next")
        out["trackElapsedS"] = RoutePrimitiveColumn(.features, "track_elapsed_s")
        // Bar phase — permille integer → 0…1.
        out["barPhase01"] = RoutePrimitiveColumn(.features, "barPhase01_permille", scale: 0.001)
        // Pulse block (snake in CSV).
        out["pulsePhase01"] = RoutePrimitiveColumn(.features, "pulse_phase01")
        out["pulseAmp01"]   = RoutePrimitiveColumn(.features, "pulse_amp01")
        out["pulseBeatIndex"] = RoutePrimitiveColumn(.features, "pulse_beat_index")
        out["pulseRegionalBlend01"] = RoutePrimitiveColumn(.features, "pulse_regional_blend01")
        // Structural + tonal (snake in CSV).
        out["sectionIndex"] = RoutePrimitiveColumn(.features, "section_index")
        out["tonalPhaseFifths"] = RoutePrimitiveColumn(.features, "tonal_phase_fifths")
        out["tonalPhaseThirds"] = RoutePrimitiveColumn(.features, "tonal_phase_thirds")
        out["tonalConsonance"] = RoutePrimitiveColumn(.features, "tonal_consonance")
        out["tonalTension"]    = RoutePrimitiveColumn(.features, "tonal_tension")
        out["harmonicFlux"]    = RoutePrimitiveColumn(.features, "harmonic_flux")
        // StemFeatures — stems.csv columns are uniformly camelCase = the Swift name.
        for stem in ["vocals", "drums", "bass", "other"] {
            for suffix in ["Energy", "Beat", "Band0", "Band1",
                           "EnergyRel", "EnergyDev",
                           "OnsetRate", "Centroid", "AttackRatio", "EnergySlope"] {
                let name = stem + suffix
                out[name] = RoutePrimitiveColumn(.stems, name)
            }
        }
        out["vocalsPitchHz"] = RoutePrimitiveColumn(.stems, "vocalsPitchHz")
        out["vocalsPitchConfidence"] = RoutePrimitiveColumn(.stems, "vocalsPitchConfidence")
        for fam in ["strings", "brass", "woodwinds", "percussion"] {
            out[fam + "Activity"] = RoutePrimitiveColumn(.stems, fam + "Activity")
            out[fam + "ActivityDev"] = RoutePrimitiveColumn(.stems, fam + "ActivityDev")
        }
        return out
    }()

    /// True when `primitive` is a known routable, session-recorded field.
    public static func isValid(_ primitive: String) -> Bool { map[primitive] != nil }
}

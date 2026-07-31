// WitchlightFixtureDrive — real-music drive for every Witchlight harness.
//
// FA #27: hand-authored FeatureVector envelopes do not reproduce real-music pipeline
// noise, cross-band correlation or MIR-derived structure, so every Witchlight temporal
// claim is measured on the committed `route_coverage` fixtures — the same three real
// preview clips `RouteCoverageTests` replays.
//
// It carries EVERY primitive Witchlight declares in its sidecar. That is the whole point
// of this file existing separately from `SessionReplayHarness`: that harness's row struct
// has no `tonal_phase_fifths` column, so replaying Witchlight through it would feed the
// preset's hero driver a constant ZERO and the pen would draw a straight line — the
// route would read as broken when it is fine (memory: "harness must carry every route";
// the Faraday r = −0.019 → +0.868 case).
//
// If a Witchlight route is ever added to the sidecar, add its column here in the same
// commit or the harnesses silently stop testing it.

import Foundation
import Testing
@testable import PresetSessionReplay
@testable import Renderer
@testable import Shared

// MARK: - WitchlightFixtureDrive

enum WitchlightFixtureDrive {

    /// The committed real-music fixture set — modal jazz with no backbeat, alt-rock with a
    /// tom-driven kit, soul/pop with a strong backbeat. Three different characters, which
    /// is what makes the ~10× cross-track harmonic-rate spread (WITCHLIGHT_DESIGN §2.3
    /// item 3) actually appear in the measurement.
    static let tracks = ["so_what", "there_there", "love_rehab"]

    struct Drive {
        let name: String
        let features: [FeatureVector]
        let stems: [StemFeatures]
        /// `section_index` per frame — delivered separately because `StructuralPrediction`
        /// is CPU-only and never reaches the `ParticleGeometry.update` signature.
        let sectionIndex: [UInt32]
    }

    static func load(_ track: String, aspect: Float = 16.0 / 9.0) throws -> Drive {
        let base = try #require(
            Bundle.module.url(forResource: "route_coverage", withExtension: nil),
            "route_coverage fixtures not bundled — check Package.swift resources")
        let series = try SessionColumnSeries.load(directory: base.appendingPathComponent(track))
        let count = series.frameCount

        func column(_ name: String) -> [Float] {
            guard let raw = series.floatSeries(name) else { return [Float](repeating: 0, count: count) }
            return raw.map { $0 ?? 0 }
        }

        // FeatureVector columns — one per declared route, plus what the sky fragment and
        // the silence gate read.
        let time = column("time"), delta = column("deltaTime")
        let bass = column("bass"), mid = column("mid"), treble = column("treble")
        let centroid = column("spectralCentroid"), flux = column("spectralFlux")
        let valence = column("valence"), arousal = column("arousal")
        let bassRel = column("bassRel"), bassDev = column("bassDev")
        let barPermille = column("barPhase01_permille")
        let beatPhase = column("beatPhase01")
        let fifths = column("tonal_phase_fifths"), thirds = column("tonal_phase_thirds")
        let consonance = column("tonal_consonance"), tension = column("tonal_tension")
        let flow = column("harmonic_flux")
        let sections = column("section_index")

        var features: [FeatureVector] = []
        features.reserveCapacity(count)
        for i in 0..<count {
            var f = FeatureVector()
            f.time = time[i]
            f.deltaTime = delta[i] > 0 ? delta[i] : 1.0 / 60.0
            f.bass = bass[i]; f.mid = mid[i]; f.treble = treble[i]
            f.spectralCentroid = centroid[i]; f.spectralFlux = flux[i]
            f.valence = valence[i]; f.arousal = arousal[i]
            f.bassRel = bassRel[i]; f.bassDev = bassDev[i]
            f.barPhase01 = barPermille[i] * 0.001
            f.beatPhase01 = beatPhase[i]
            f.tonalPhaseFifths = fifths[i]; f.tonalPhaseThirds = thirds[i]
            f.tonalConsonance = consonance[i]; f.tonalTension = tension[i]
            f.harmonicFlux = flow[i]
            f.aspectRatio = aspect
            features.append(f)
        }

        // StemFeatures — the warmup blend and the silence gate read the four energies.
        let drumsEnergy = column("drumsEnergy"), bassEnergy = column("bassEnergy")
        let vocalsEnergy = column("vocalsEnergy"), otherEnergy = column("otherEnergy")
        let drumsDev = column("drumsEnergyDev"), bassDevStem = column("bassEnergyDev")
        var stems: [StemFeatures] = []
        stems.reserveCapacity(count)
        for i in 0..<count {
            var s = StemFeatures()
            s.drumsEnergy = drumsEnergy[i]; s.bassEnergy = bassEnergy[i]
            s.vocalsEnergy = vocalsEnergy[i]; s.otherEnergy = otherEnergy[i]
            s.drumsEnergyDev = drumsDev[i]; s.bassEnergyDev = bassDevStem[i]
            stems.append(s)
        }

        return Drive(name: track, features: features, stems: stems,
                     sectionIndex: sections.map { UInt32(max(0, $0)) })
    }

    /// Drive a `WitchlightPath` over a whole fixture, feeding the section index through
    /// the same `ingestStructure` bridge the app layer uses.
    static func run(_ path: WitchlightPath, over drive: Drive) {
        var structure = StructuralPrediction()
        for i in 0..<drive.features.count {
            structure.sectionIndex = drive.sectionIndex[i]
            path.ingestStructure(structure)
            path.advance(deltaTime: drive.features[i].deltaTime,
                         features: drive.features[i], stems: drive.stems[i])
        }
    }
}

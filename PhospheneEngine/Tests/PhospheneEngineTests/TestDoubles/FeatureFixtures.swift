// FeatureFixtures — shared builders for the two most-duplicated test value types
// (CLEAN.7.2b). FeatureVector is inline-constructed at ~119 sites across 41 files and
// StemFeatures at ~55 sites across 22 files; both have an `init` that takes only the
// CORE fields and zeroes the deviation primitives, so tests construct-then-mutate:
//
//     var fv = FeatureVector(bass: 0.5)
//     fv.bassDev = 0.4; fv.beatPhase01 = 0.2          // the verbose, duplicated part
//
// These builders collapse that to one call — `makeFeatureVector(bass: 0.5, bassDev: 0.4,
// beatPhase01: 0.2)` — defaulting every field a test doesn't care about. They're a strict
// superset of each struct's `init` (same defaults), so migrating a call site is a pure
// readability change with identical bytes. The deviation primitives (D-026) and beat-phase
// fields — the load-bearing drivers tests most often set — are first-class params here even
// though the struct `init` omits them.
//
// ponytail: only the COMMONLY-set fields are params. The rare ones (FeatureVector pads;
// StemFeatures rich metadata / pitch / aurora) are still set post-construction at the few
// sites that need them — adding 40 more never-used params would be the bloat this replaces.
//
// Param order = core → deviation primitives → beat/bar → pulse (Swift requires call-site
// args in declaration order), so a call setting both passes e.g. `bassDev:` before
// `beatPhase01:`. Migration value is real only for ONE-SHOT construct-then-mutate sites;
// a `var fv` reused/mutated across a loop or successive appends gains nothing (CLEAN.7.2b).

import Foundation
@testable import Shared

enum FeatureFixtures {

    // MARK: - FeatureVector

    /// A `FeatureVector` with every field defaulted to the struct's own `init` defaults,
    /// overriding only what's passed. Includes the deviation primitives + beat/bar/pulse
    /// fields the `init` zeroes (so a test can set them without a follow-up mutation).
    static func makeFeatureVector(
        // Core (mirrors FeatureVector.init defaults exactly)
        bass: Float = 0, mid: Float = 0, treble: Float = 0,
        bassAtt: Float = 0, midAtt: Float = 0, trebleAtt: Float = 0,
        subBass: Float = 0, lowBass: Float = 0, lowMid: Float = 0,
        midHigh: Float = 0, highMid: Float = 0, high: Float = 0,
        beatBass: Float = 0, beatMid: Float = 0, beatTreble: Float = 0,
        beatComposite: Float = 0,
        spectralCentroid: Float = 0, spectralFlux: Float = 0,
        valence: Float = 0, arousal: Float = 0,
        time: Float = 0, deltaTime: Float = 0,
        aspectRatio: Float = 1.777,
        accumulatedAudioTime: Float = 0,
        // Deviation primitives (D-026 / MV-1) — zeroed by init; the usual test drivers.
        bassRel: Float = 0, bassDev: Float = 0,
        midRel: Float = 0, midDev: Float = 0,
        trebRel: Float = 0, trebDev: Float = 0,
        bassAttRel: Float = 0, midAttRel: Float = 0, trebAttRel: Float = 0,
        // Beat / bar phase (MV-3b) — beatsPerBar defaults to 4, matching init.
        beatPhase01: Float = 0, beatsUntilNext: Float = 0,
        barPhase01: Float = 0, beatsPerBar: Float = 4,
        trackElapsedS: Float = 0,
        // FBS pulse (D-153).
        pulsePhase01: Float = 0, pulseAmp01: Float = 0,
        pulseBeatIndex: Float = 0, pulseRegionalBlend01: Float = 0
    ) -> FeatureVector {
        var fv = FeatureVector(
            bass: bass, mid: mid, treble: treble,
            bassAtt: bassAtt, midAtt: midAtt, trebleAtt: trebleAtt,
            subBass: subBass, lowBass: lowBass, lowMid: lowMid,
            midHigh: midHigh, highMid: highMid, high: high,
            beatBass: beatBass, beatMid: beatMid, beatTreble: beatTreble,
            beatComposite: beatComposite,
            spectralCentroid: spectralCentroid, spectralFlux: spectralFlux,
            valence: valence, arousal: arousal,
            time: time, deltaTime: deltaTime,
            aspectRatio: aspectRatio,
            accumulatedAudioTime: accumulatedAudioTime
        )
        fv.bassRel = bassRel; fv.bassDev = bassDev
        fv.midRel = midRel; fv.midDev = midDev
        fv.trebRel = trebRel; fv.trebDev = trebDev
        fv.bassAttRel = bassAttRel; fv.midAttRel = midAttRel; fv.trebAttRel = trebAttRel
        fv.beatPhase01 = beatPhase01; fv.beatsUntilNext = beatsUntilNext
        fv.barPhase01 = barPhase01; fv.beatsPerBar = beatsPerBar
        fv.trackElapsedS = trackElapsedS
        fv.pulsePhase01 = pulsePhase01; fv.pulseAmp01 = pulseAmp01
        fv.pulseBeatIndex = pulseBeatIndex; fv.pulseRegionalBlend01 = pulseRegionalBlend01
        return fv
    }

    // MARK: - StemFeatures

    /// A `StemFeatures` defaulted to its `init` defaults, plus the per-stem energy
    /// deviation primitives (`…EnergyRel` / `…EnergyDev`) and `drumsEnergyDevSmoothed`
    /// the `init` omits — the routing signals tests most often set (D-026 / D-127).
    static func makeStemFeatures(
        // Core (mirrors StemFeatures.init)
        vocalsEnergy: Float = 0, vocalsBand0: Float = 0, vocalsBand1: Float = 0, vocalsBeat: Float = 0,
        drumsEnergy: Float = 0, drumsBand0: Float = 0, drumsBand1: Float = 0, drumsBeat: Float = 0,
        bassEnergy: Float = 0, bassBand0: Float = 0, bassBand1: Float = 0, bassBeat: Float = 0,
        otherEnergy: Float = 0, otherBand0: Float = 0, otherBand1: Float = 0, otherBeat: Float = 0,
        // Deviation primitives (zeroed by init; the load-bearing stem-routing drivers).
        vocalsEnergyRel: Float = 0, vocalsEnergyDev: Float = 0,
        drumsEnergyRel: Float = 0, drumsEnergyDev: Float = 0,
        bassEnergyRel: Float = 0, bassEnergyDev: Float = 0,
        otherEnergyRel: Float = 0, otherEnergyDev: Float = 0,
        drumsEnergyDevSmoothed: Float = 0
    ) -> StemFeatures {
        var s = StemFeatures(
            vocalsEnergy: vocalsEnergy, vocalsBand0: vocalsBand0, vocalsBand1: vocalsBand1, vocalsBeat: vocalsBeat,
            drumsEnergy: drumsEnergy, drumsBand0: drumsBand0, drumsBand1: drumsBand1, drumsBeat: drumsBeat,
            bassEnergy: bassEnergy, bassBand0: bassBand0, bassBand1: bassBand1, bassBeat: bassBeat,
            otherEnergy: otherEnergy, otherBand0: otherBand0, otherBand1: otherBand1, otherBeat: otherBeat
        )
        s.vocalsEnergyRel = vocalsEnergyRel; s.vocalsEnergyDev = vocalsEnergyDev
        s.drumsEnergyRel = drumsEnergyRel; s.drumsEnergyDev = drumsEnergyDev
        s.bassEnergyRel = bassEnergyRel; s.bassEnergyDev = bassEnergyDev
        s.otherEnergyRel = otherEnergyRel; s.otherEnergyDev = otherEnergyDev
        s.drumsEnergyDevSmoothed = drumsEnergyDevSmoothed
        return s
    }
}

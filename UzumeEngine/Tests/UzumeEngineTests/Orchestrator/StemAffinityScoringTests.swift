// StemAffinityScoringTests — QR.2 (D-080): validates the rewritten stemAffinitySubScore
// that uses deviation primitives (D-026/MV-1) and mean-of-dev formula.
//
// Rules under test:
//   1. Zero-profile guard: StemFeatures.zero → neutral 0.5 for all presets.
//   2. Single dev field active → score = devValue (up to 1.0).
//   3. Multi-affinity mean: score = sum(devs) / count.
//   4. No declared affinities → neutral 0.5 always.
//   5. High energy but zero dev → score = 0 (below neutral).

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared
import simd

@Suite("StemAffinityScoring")
struct StemAffinityScoringTests {

    private let scorer = DefaultPresetScorer()

    // MARK: — Helpers

    private func makePreset(affinities: [String: String]) -> PresetDescriptor {
        let stms = affinities.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",")
        let json = """
        {"name":"Test","family":"geometric","visual_density":0.5,"motion_intensity":0.5,
         "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
         "stem_affinity":{\(stms)},"certified":true}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    private func makeProfile(stems: StemFeatures) -> TrackProfile {
        TrackProfile(bpm: nil, mood: EmotionalState(valence: 0, arousal: 0),
                     stemEnergyBalance: stems)
    }

    private func makeContext() -> PresetScoringContext {
        PresetScoringContext(deviceTier: .tier1, recentHistory: [], currentPreset: nil,
                             elapsedSessionTime: 0, currentSection: nil)
    }

    // MARK: — Test 1: zero-profile guard

    // Zero stems (unconverged EMA) → neutral 0.5 regardless of affinities.
    @Test("Zero StemFeatures balance → stemAffinity neutral 0.5 for any affinities (QR.2 zero-profile guard)")
    func zeroProfileReturnsNeutral() {
        let drumPreset = makePreset(affinities: ["drums": "beat_pulse"])
        let track = makeProfile(stems: .zero)
        let bd = scorer.breakdown(preset: drumPreset, track: track, context: makeContext())
        #expect(bd.stemAffinity == 0.5,
                "Zero balance (unconverged EMA) must return 0.5 — avoids adversarial penalty (D-080)")
    }

    // MARK: — Test 2: single dev field active

    // Drums dev = 0.45 → drumPreset scores 0.45; vocalPreset scores 0.
    @Test("Single active dev field: score equals that stem's dev value (QR.2)")
    func singleDevFieldActiveMapsToScore() {
        let drumPreset  = makePreset(affinities: ["drums": "beat_pulse"])
        let vocalPreset = makePreset(affinities: ["vocals": "hue_shift"])

        var snap = StemFeatures(drumsEnergy: 0.8)
        snap.drumsEnergyDev  = 0.45
        snap.vocalsEnergyDev = 0.0

        let track   = makeProfile(stems: snap)
        let context = makeContext()

        let drumBD  = scorer.breakdown(preset: drumPreset,  track: track, context: context)
        let vocalBD = scorer.breakdown(preset: vocalPreset, track: track, context: context)

        #expect(abs(drumBD.stemAffinity  - 0.45) < 0.001,
                "Drum preset should score drumEnergyDev directly when single affinity")
        #expect(abs(vocalBD.stemAffinity - 0.0)  < 0.001,
                "Vocal preset should score 0 when vocalsEnergyDev = 0")
        #expect(drumBD.stemAffinity - vocalBD.stemAffinity >= 0.3,
                "Disjoint-affinity presets must produce score gap ≥ 0.3 (D-080)")
    }

    // MARK: — Test 3: multi-affinity mean

    // Preset declares drums + bass; devs = 0.40 and 0.20 → score = mean = 0.30.
    @Test("Multi-affinity mean: score = (drumsEnergyDev + bassEnergyDev) / 2 (QR.2)")
    func multiAffinityComputesMean() {
        let preset = makePreset(affinities: ["drums": "beat_pulse", "bass": "zoom_breath"])

        var snap = StemFeatures(drumsEnergy: 0.8, bassEnergy: 0.6)
        snap.drumsEnergyDev = 0.40
        snap.bassEnergyDev  = 0.20

        let bd = scorer.breakdown(preset: preset, track: makeProfile(stems: snap), context: makeContext())
        #expect(abs(bd.stemAffinity - 0.30) < 0.001,
                "Two-affinity score should equal mean of both dev fields")
    }

    // MARK: — Test 4: empty affinities → neutral 0.5

    @Test("Empty stem_affinity dictionary always returns neutral 0.5 (QR.2)")
    func emptyAffinityIsAlwaysNeutral() {
        let preset = makePreset(affinities: [:])

        var activeSnap = StemFeatures(drumsEnergy: 0.9)
        activeSnap.drumsEnergyDev = 0.6

        let bd = scorer.breakdown(preset: preset, track: makeProfile(stems: activeSnap),
                                  context: makeContext())
        #expect(bd.stemAffinity == 0.5,
                "No declared affinities → always neutral regardless of stem activity")
    }

    // MARK: — Test 5: high energy but zero dev → score below neutral

    // This captures the QR.2 invariant: affinity presets are NOT rewarded just for
    // non-zero energy in the declared stems — only above-average DEVIATION counts.
    @Test("High energy with zero dev → stemAffinity = 0.0, below neutral (QR.2)")
    func highEnergyZeroDevScoresZero() {
        let drumPreset = makePreset(affinities: ["drums": "beat_pulse"])

        // drums energy high but EMA has converged → dev = 0 (pre-analyzed TrackProfile).
        let flatSnap = StemFeatures(drumsEnergy: 0.9)  // drumsEnergyDev defaults to 0

        let bd = scorer.breakdown(preset: drumPreset, track: makeProfile(stems: flatSnap),
                                  context: makeContext())
        #expect(bd.stemAffinity < 0.5,
                "Zero dev means no above-average transient — affinity score must be < neutral")
        #expect(bd.stemAffinity == 0.0,
                "Exactly zero dev → mean = 0 (D-080 mean-of-max(0,dev))")
    }
}

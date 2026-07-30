// ReplayHarnessRouteCoverageTests — the replay harness must CARRY every route it replays.
//
// WHY THIS EXISTS. `SessionReplayHarness` builds its `FeatureVector` / `StemFeatures`
// from a hand-written CSV→field mapping. Any field it does not map is silently ZERO, so
// a preset route driven by that field renders as if it were dead — and the resulting
// measurement "proves" the route is broken while actually testing nothing. There is no
// error, no warning, and the render looks plausible.
//
// This failed three separate ways in one session before being mechanized:
//
//   1. Faraday's beat-locked subharmonic measured r = -0.019 (apparently no lock at
//      all). The harness never mapped `barPhase01`. Once mapped, the SAME shader code
//      measured r = +0.868.
//   2. The fix for (1) mapped the CSV column as `pulseAmp01`, but the session logs
//      snake_case `pulse_amp01` — so the repair itself still read zero. A typo in a
//      string literal is indistinguishable from a dead route.
//   3. `stemFeatures: .zero` was passed for EVERY frame, so all stem-driven routes in
//      all ray-march presets replayed against silence — including Volumetric
//      Lithograph, which is CERTIFIED on per-stem coupling.
//
// So: assert that every primitive any replayable preset DECLARES in its sidecar is a
// primitive the harness actually carries. A new route on an uncarried primitive fails
// here instead of silently producing a dead render months later.

import Testing
import Foundation
@testable import Presets
import Shared

@Suite("Replay harness route coverage")
struct ReplayHarnessRouteCoverageTests {

    /// Primitives the harness populates from a session. Keep in lockstep with
    /// `SessionReplayHarness.loadRows` / `feature(from:)` / `loadStems`.
    ///
    /// Adding a name here without also mapping it in the harness re-opens exactly the
    /// silent-zero hole this suite exists to close — map it first, then list it.
    static let carriedPrimitives: Set<String> = [
        // FeatureVector — bands + spectral + mood
        "bass", "mid", "treble", "subBass", "lowBass",
        "spectralCentroid", "spectralFlux", "valence", "arousal",
        // beat + grid
        "beatBass", "beatMid", "beatComposite", "beatPhase01", "barPhase01",
        "pulseAmp01", "pulsePhase01", "pulseBeatIndex", "pulseRegionalBlend01",
        // deviation primitives (D-026)
        "bassAttRel", "bassDev",
        // StemFeatures — energies, beats, deviations, spectral shape
        "drumsEnergy", "bassEnergy", "vocalsEnergy", "otherEnergy",
        "drumsBeat", "bassBeat", "vocalsBeat", "otherBeat",
        "drumsEnergyRel", "bassEnergyRel", "vocalsEnergyRel", "otherEnergyRel",
        "drumsEnergyDev", "bassEnergyDev", "vocalsEnergyDev", "otherEnergyDev",
        "drumsOnsetRate", "bassOnsetRate", "vocalsOnsetRate", "otherOnsetRate",
        "drumsAttackRatio", "bassAttackRatio", "vocalsAttackRatio", "otherAttackRatio",
        "vocalsPitchHz", "vocalsPitchConfidence"
    ]

    @Test("every route a replayable preset declares is carried by SessionReplayHarness")
    func test_harnessCarriesEveryReplayableRoute() throws {
        let shadersURL = try #require(PresetLoader.bundledShadersURL,
            "Shaders resource not found via PresetLoader.bundledShadersURL")
        let jsonFiles = try FileManager.default.contentsOfDirectory(
            at: shadersURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }

        let decoder = JSONDecoder()
        var uncarried: [String: [String]] = [:]
        for jsonURL in jsonFiles {
            let descriptor = try decoder.decode(PresetDescriptor.self,
                                                from: try Data(contentsOf: jsonURL))
            // The harness replays ray-march presets (it drives RayMarchPipeline.render).
            guard descriptor.passes.contains(.rayMarch) else { continue }
            let missing = descriptor.audioRoutes
                .map(\.primitive)
                .filter { !Self.carriedPrimitives.contains($0) }
            if !missing.isEmpty {
                uncarried[descriptor.name] = Array(Set(missing)).sorted()
            }
        }

        #expect(uncarried.isEmpty, """
            SessionReplayHarness does not carry these declared routes, so replaying \
            these presets measures them against ZERO and any look/coupling conclusion \
            drawn from those frames is invalid: \(uncarried.sorted { $0.key < $1.key }). \
            Map the field in the harness AND add it to `carriedPrimitives`.
            """)
    }
}

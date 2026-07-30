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
// RE-VALIDATION (2026-07-27, after the fix). Rendering each replayable preset twice —
// real stems vs the old silence — quantifies what the broken instrument was hiding:
//
//   Volumetric Lithograph   image differs by 11.86/255 (its own frame-to-frame motion is
//                           4.93) — the stem coupling is LIVE and DOMINANT, and every
//                           past replay judgement was made on an image missing it.
//   Ferrofluid Ocean        17.88/255 — LIVE.
//   Lumen Mosaic            stem sensitivity 0 at FULL resolution (max pixel delta 0),
//                           though it does animate on its own (max 10/255 across ~9 % of
//                           pixels) from a non-stem driver.
//
// ⚠ CORRECTION: an earlier pass reported Lumen as "0.00 — dead static". That was a
// MEASUREMENT ARTIFACT, not a finding — the comparison downscaled to 160x90 and took a
// median, averaging a real max-10/255 change over ~9 % of pixels down to zero. The
// instrument built to catch silent zeros produced one of its own. Compare at full
// resolution, and always report max / percent-changed alongside any mean.
//
// The FOURTH gap class is real regardless: Lumen's per-cell state lives in slot 8
// (LumenPatternEngine, D-LM-buffer-slot-8) and the harness never supplied it. Nothing
// about that appears in the sidecar's declared routes, so the route-coverage test below
// cannot see it — hence the second test in this suite.
//
// OPEN, and deliberately not asserted either way: with slot 8 now driven, it changes
// Lumen's output by exactly zero, and so do the stems. That is consistent EITHER with
// dead coupling in production OR with the harness still lacking setup the app performs at
// preset activation (Lumen's per-track palette load). Verify against a live capture before
// concluding — do not infer a production defect from harness evidence alone.
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

    /// Presets whose slot-8 state the harness actually drives. A preset that reads
    /// `lumen.<field>` needs its `LumenPatternState` produced by a CPU engine every frame;
    /// with nothing driving it the shader reads a placeholder and the preset replays frozen
    /// at a default. This is a different gap class from an unmapped feature field — nothing
    /// about it appears in the sidecar's routes, so `test_harnessCarriesEveryReplayableRoute`
    /// is blind to it.
    static let harnessDrivenStatePresets: Set<String> = ["Lumen Mosaic"]

    @Test("every replayable preset that reads slot-8 state has that state driven")
    func test_harnessDrivesSlot8StateWhereNeeded() throws {
        let shadersURL = try #require(PresetLoader.bundledShadersURL,
            "Shaders resource not found via PresetLoader.bundledShadersURL")
        let metalFiles = try FileManager.default.contentsOfDirectory(
            at: shadersURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "metal" }

        var undriven: [String] = []
        for metalURL in metalFiles {
            let source = try String(contentsOf: metalURL, encoding: .utf8)
            guard source.contains("sceneMaterial") else { continue }
            // Presets that ignore slot 8 write `(void)lumen;`. Reading a field off `lumen`
            // without that opt-out means the preset depends on CPU-driven state.
            let readsState = source.range(of: "lumen\\.[a-zA-Z]",
                                          options: .regularExpression) != nil
            guard readsState, !source.contains("(void)lumen;") else { continue }
            let jsonURL = metalURL.deletingPathExtension().appendingPathExtension("json")
            guard let data = try? Data(contentsOf: jsonURL),
                  let descriptor = try? JSONDecoder().decode(PresetDescriptor.self, from: data),
                  descriptor.passes.contains(.rayMarch) else { continue }
            if !Self.harnessDrivenStatePresets.contains(descriptor.name) {
                undriven.append(descriptor.name)
            }
        }

        #expect(undriven.isEmpty, """
            These replayable presets read per-preset slot-8 state that SessionReplayHarness \
            does not drive, so they replay frozen at a placeholder default and any look or \
            coupling conclusion drawn from those frames is invalid: \(undriven.sorted()). \
            Drive the preset's CPU state engine in the harness AND list it in \
            `harnessDrivenStatePresets`.
            """)
    }

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

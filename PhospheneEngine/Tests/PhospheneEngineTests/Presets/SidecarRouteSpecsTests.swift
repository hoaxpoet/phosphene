// SidecarRouteSpecsTests — the SR.2 / RECON.21 claim, asserted.
//
// The claim replacing the hand-written route registry: every preset that ships an
// `audio_routes` sidecar manifest is replayable with no new Swift. These tests
// hold that claim to the tree rather than to a comment.

import Testing
import Foundation
@testable import PresetSessionReplay
@testable import Presets

@Suite("Sidecar-driven replay routes (SR.2)")
struct SidecarRouteSpecsTests {

    /// The coverage claim. Before SR.2 exactly three presets were replayable
    /// (aurora_veil, murmuration, skein) because each needed a hand-written spec
    /// file; the sidecar manifests already covered far more.
    @Test("every preset declaring audio_routes resolves to replay specs")
    func allDeclaringPresetsResolve() throws {
        let names = SidecarLocator.allPresetNames()
        #expect(!names.isEmpty, "no sidecars found — bundle lookup broken")

        var resolved: [String] = []
        var declaredButUnresolved: [String] = []
        for name in names {
            guard let d = SidecarLocator.descriptor(forPresetNamed: name) else { continue }
            guard !d.audioRoutes.isEmpty else { continue }
            let (inputs, _) = SidecarRouteSpecs.resolve(descriptor: d)
            if inputs.isEmpty { declaredButUnresolved.append(name) } else { resolved.append(name) }
        }

        #expect(declaredButUnresolved.isEmpty,
                "presets declare audio_routes but resolve to zero replay inputs: \(declaredButUnresolved)")
        #expect(resolved.count >= 20,
                "expected the sidecar path to cover the declaring corpus (~21); got \(resolved.count)")
    }

    /// Name matching must accept what the old registry accepted, so existing
    /// invocations keep working after the registry is gone.
    @Test("preset lookup tolerates spacing, case and separators")
    func lookupNormalisesNames() throws {
        // A preset whose name contains a space, so the normalisation actually matters.
        guard SidecarLocator.descriptor(forPresetNamed: "Volumetric Lithograph") != nil else {
            Issue.record("Volumetric Lithograph sidecar not found — corpus changed?")
            return
        }
        for spelling in ["volumetric lithograph", "Volumetric_Lithograph",
                         "volumetric-lithograph", "VOLUMETRICLITHOGRAPH"] {
            #expect(SidecarLocator.descriptor(forPresetNamed: spelling) != nil,
                    "spelling '\(spelling)' should resolve")
        }
        #expect(SidecarLocator.descriptor(forPresetNamed: "no such preset") == nil)
    }

    /// Gate thresholds come from the QG.1 per-kind floors, and the spec says so —
    /// these are coverage gates, not the shader's own edges.
    @Test("kind selects the QG.1 coverage gate")
    func kindSelectsGate() throws {
        guard let skein = SidecarLocator.descriptor(forPresetNamed: "Skein") else {
            Issue.record("Skein sidecar not found"); return
        }
        let (inputs, _) = SidecarRouteSpecs.resolve(descriptor: skein)
        for (route, input) in zip(skein.audioRoutes, inputs) {
            switch route.kind {
            case .accent:
                #expect(input.spec.gateThreshold == SidecarRouteSpecs.KindGate.accent)
            case .continuous, .structural:
                #expect(input.spec.gateThreshold == SidecarRouteSpecs.KindGate.continuousFloor)
            }
        }
    }

    /// Aurora Veil is the reason the stale hand-written file went: its specs
    /// described the pre-AV.7 shader. The sidecar path must report its REAL routes.
    @Test("Aurora Veil resolves to its post-AV.7 sidecar routes, not the retired ones")
    func auroraVeilUsesRealRoutes() throws {
        guard let av = SidecarLocator.descriptor(forPresetNamed: "Aurora Veil") else {
            Issue.record("Aurora Veil sidecar not found"); return
        }
        let (inputs, unmapped) = SidecarRouteSpecs.resolve(descriptor: av)
        #expect(unmapped.isEmpty, "unmapped AV primitives: \(unmapped)")
        #expect(!inputs.isEmpty, "Aurora Veil should resolve replay inputs from its sidecar")
        let routeNames = Set(av.audioRoutes.map(\.route))
        // The retired AV.2.h.1 routes must NOT reappear.
        #expect(!routeNames.contains("curtain_kink"))
        #expect(!routeNames.contains("ribbon_hue"))
    }
}

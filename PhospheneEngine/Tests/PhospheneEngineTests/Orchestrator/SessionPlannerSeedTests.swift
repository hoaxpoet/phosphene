// SessionPlannerSeedTests — Unit tests for DefaultSessionPlanner seed support (Increment U.5 Part D, D-047).

import Foundation
import Orchestrator
import Presets
import Session
import Shared
import Testing

// MARK: - Helpers

private func makeIdentity(title: String = "T", duration: TimeInterval = 180) -> TrackIdentity {
    TrackIdentity(title: title, artist: "A", duration: duration)
}

private func makeProfile() -> TrackProfile { TrackProfile.empty }

private func makePreset(name: String) throws -> PresetDescriptor {
    let json = """
    {"name":"\(name)","family":"geometric","motion_intensity":0.5,
     "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
     "complexity_cost":{"tier1":1.0,"tier2":1.0},
     "transition_affordances":["crossfade"],"certified":true}
    """
    return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

// MARK: - Suite

@Suite("DefaultSessionPlanner seed")
struct SessionPlannerSeedTests {

    private let planner = DefaultSessionPlanner()

    @Test("zero seed: plan is byte-identical across two calls (D-034 preserved)")
    func zeroSeed_isDeterministic() throws {
        let tracks = [(makeIdentity(title: "A"), makeProfile()),
                      (makeIdentity(title: "B"), makeProfile())]
        let catalog = [try makePreset(name: "P1"), try makePreset(name: "P2")]

        let s1 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: 0)
        let s2 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: 0)

        // Same preset sequence.
        let ids1 = s1.tracks.map { $0.preset.id }
        let ids2 = s2.tracks.map { $0.preset.id }
        #expect(ids1 == ids2)
    }

    @Test("same nonzero seed twice: output is identical (reproducible randomisation)")
    func sameSeedTwice_isDeterministic() throws {
        let tracks = (0..<5).map { i in (makeIdentity(title: "Track\(i)"), makeProfile()) }
        let catalog = try (0..<4).map { i in try makePreset(name: "P\(i)") }

        let seed: UInt64 = 42_000_000_000
        let s1 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: seed)
        let s2 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: seed)

        let ids1 = s1.tracks.map { $0.preset.id }
        let ids2 = s2.tracks.map { $0.preset.id }
        #expect(ids1 == ids2)
    }

    @Test("nonzero seed no-op when catalog has only one eligible preset")
    func nonzeroSeed_singlePreset_noChange() throws {
        let tracks = [(makeIdentity(title: "Only"), makeProfile())]
        let catalog = [try makePreset(name: "Solo")]

        let s0 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: 0)
        let s1 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: 99)

        #expect(s0.tracks.first?.preset.id == s1.tracks.first?.preset.id)
    }

    @Test("applying(overrides:) preserves locked track picks")
    func applyingOverrides_preservesLocks() throws {
        let tracks = [(makeIdentity(title: "A"), makeProfile()),
                      (makeIdentity(title: "B"), makeProfile())]
        let p1 = try makePreset(name: "P1")
        let p2 = try makePreset(name: "P2")
        let locked = try makePreset(name: "LockedPreset")

        let plan = try planner.plan(tracks: tracks, catalog: [p1, p2], deviceTier: .tier1)
        let firstTrackID = plan.tracks[0].track
        let patched = plan.applying(overrides: [firstTrackID: locked])

        #expect(patched.tracks[0].preset.id == locked.id)
        // Second track unchanged.
        #expect(patched.tracks[1].preset.id == plan.tracks[1].preset.id)
    }

    @Test("applying(overrides:) with empty dict returns self-equivalent plan")
    func applyingOverrides_empty_unchanged() throws {
        let tracks = [(makeIdentity(), makeProfile())]
        let catalog = [try makePreset(name: "P1")]
        let plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)
        let patched = plan.applying(overrides: [:])

        #expect(patched.tracks[0].preset.id == plan.tracks[0].preset.id)
        #expect(patched.tracks.count == plan.tracks.count)
    }
}

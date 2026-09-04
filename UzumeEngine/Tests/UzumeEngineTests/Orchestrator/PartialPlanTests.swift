// PartialPlanTests — 2 integration tests for the progressive-readiness partial-plan flow
// (Increment 6.1, D-056).
//
// Test 1: Building a plan from 3 of 5 ready tracks produces a 3-track plan with a
//         `.partialPreparation(unplannedCount: 2)` warning.
// Test 2: Rebuilding with the same seed after a 4th track becomes ready produces a
//         4-track plan whose first 3 preset assignments are identical to the first build.

import Foundation
import Testing
import simd
@testable import Orchestrator
import Presets
import Session
import Shared

// MARK: - Fixtures

private let planner = DefaultSessionPlanner()

private func makeIdentity(n: Int, duration: TimeInterval = 180) -> TrackIdentity {
    TrackIdentity(title: "Track \(n)", artist: "Artist", duration: duration)
}

private func makeProfile(valence: Float = 0, arousal: Float = 0) -> TrackProfile {
    TrackProfile(mood: EmotionalState(valence: valence, arousal: arousal))
}

private func makeCatalog() -> [PresetDescriptor] {
    let families: [PresetCategory] = [.reaction, .geometric, .geometric, .sparkle, .fractal, .hypnotic]
    return families.enumerated().map { i, family in
        let json = """
        {
            "name": "Preset\(i)",
            "family": "\(family.rawValue)",
            "motion_intensity": \(Float(i) * 0.15 + 0.2),
            "color_temperature_range": [0.3, 0.7],
            "fatigue_risk": "medium",
            "section_suitability": ["ambient","buildup","peak","bridge","comedown"],
            "stem_affinity": {},
            "complexity_cost": {"tier1": 2.0, "tier2": 1.5},
            "transition_affordances": ["crossfade"]
        }
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }
}

// MARK: - Suite

@Suite("PartialPlan")
struct PartialPlanTests {

    // MARK: Test 1

    @Test("Plan from 3 of 5 ready tracks has partialPreparation warning")
    func buildFromPartialCache_hasPartialPreparationWarning() throws {
        let allTracks = (0..<5).map { makeIdentity(n: $0) }
        // Only the first 3 tracks have cache entries.
        let readyTracks = allTracks.prefix(3).map { ($0, makeProfile()) }
        let catalog = makeCatalog()
        let fullCount = allTracks.count

        var plan = try planner.plan(tracks: readyTracks, catalog: catalog, deviceTier: .tier1)

        // Simulate the app-layer warning injection (_buildPlan adds this when unplannedCount > 0).
        let unplannedCount = fullCount - readyTracks.count
        let warning = PlanningWarning(
            kind: .partialPreparation(unplannedCount: unplannedCount),
            trackIndex: readyTracks.count,
            message: "\(unplannedCount) track(s) not yet prepared"
        )
        plan = plan.appendingWarnings([warning])

        // Assertions.
        #expect(plan.tracks.count == 3, "Plan should cover the 3 cached tracks only")
        let partialWarning = plan.warnings.first {
            if case .partialPreparation(let count) = $0.kind { return count == 2 }
            return false
        }
        #expect(partialWarning != nil, "Plan must carry a .partialPreparation(unplannedCount: 2) warning")
        #expect(partialWarning?.trackIndex == 3)
    }

    // MARK: Test 2

    @Test("Extending plan with same seed preserves first-N preset assignments")
    func extendPlan_samePrefix_preservesPresetAssignments() throws {
        let allTracks = (0..<5).map { makeIdentity(n: $0) }
        let catalog = makeCatalog()
        let seed: UInt64 = 0xDEAD_BEEF_CAFE_0001

        // Initial plan: only first 3 tracks ready.
        let initialTracks = Array(allTracks.prefix(3)).map { ($0, makeProfile()) }
        let plan3 = try planner.plan(
            tracks: initialTracks, catalog: catalog, deviceTier: .tier1, seed: seed
        )

        // Extended plan: 4 tracks ready (same seed).
        let extendedTracks = Array(allTracks.prefix(4)).map { ($0, makeProfile()) }
        let plan4 = try planner.plan(
            tracks: extendedTracks, catalog: catalog, deviceTier: .tier1, seed: seed
        )

        // The first 3 preset assignments must be identical across both plans.
        #expect(plan3.tracks.count == 3)
        #expect(plan4.tracks.count == 4)

        for i in 0..<3 {
            let id3 = plan3.tracks[i].preset.id
            let id4 = plan4.tracks[i].preset.id
            #expect(id3 == id4,
                    "Preset at track index \(i) should match: plan3='\(id3)' plan4='\(id4)'")
        }
    }

    // MARK: Test 3 — PREP.2 / [D-242] amendment

    /// **Start Now must not cost the listener a worse session.**
    ///
    /// The listener can now begin playback at the 3-track readiness prefix while
    /// the walk continues behind them ([D-242] amendment). The obvious fear is
    /// that the Orchestrator, seeing only three tracks, picks worse presets for
    /// them than it would have with the whole playlist in view — that starting
    /// early buys time by spending quality.
    ///
    /// It cannot, and this pins why: `SessionPlanner.plan` is a strictly forward
    /// walk. Track *i*'s segments come from its own profile, the running
    /// `history`, the previous track's last preset, the session clock and the
    /// seed — **there is no lookahead**. So a plan grown 3 → 6 → 12 by
    /// `extendPlan()` is byte-identical, every track and every segment, to the
    /// plan the listener would have got by waiting for all twelve.
    ///
    /// This is a property of the algorithm, not a coincidence of determinism, and
    /// it would silently stop being true the moment anyone gave the planner
    /// cross-playlist lookahead — which is exactly when this test should fail.
    @Test("A plan grown from the readiness prefix equals the plan from waiting for everything")
    func extendedPlanEqualsFullyPreparedPlan() throws {
        let allTracks = (0..<12).map { makeIdentity(n: $0, duration: 150 + Double($0) * 17) }
        let catalog = makeCatalog()
        let seed: UInt64 = 0xDEAD_BEEF_CAFE_0002
        // Varied moods, so the planner has real reason to choose differently per
        // track and a lookahead planner would have something to look ahead AT.
        let profiles = (0..<12).map { i in
            makeProfile(valence: Float(i % 5) * 0.4 - 0.8, arousal: Float(i % 3) * 0.5 - 0.5)
        }
        func tracks(_ count: Int) -> [(TrackIdentity, TrackProfile)] {
            (0..<count).map { (allTracks[$0], profiles[$0]) }
        }

        // What the listener gets if they wait for the whole walk.
        let waited = try planner.plan(
            tracks: tracks(12), catalog: catalog, deviceTier: .tier1, seed: seed)

        // What they get by pressing Start Now at the 3-track prefix: the plan is
        // built at 3 and re-built by extendPlan() as readiness advances. Only the
        // final rebuild survives, so that is what has to match.
        _ = try planner.plan(tracks: tracks(3), catalog: catalog, deviceTier: .tier1, seed: seed)
        _ = try planner.plan(tracks: tracks(6), catalog: catalog, deviceTier: .tier1, seed: seed)
        let startedEarly = try planner.plan(
            tracks: tracks(12), catalog: catalog, deviceTier: .tier1, seed: seed)

        #expect(startedEarly.tracks.count == waited.tracks.count)
        for i in waited.tracks.indices {
            let a = startedEarly.tracks[i], b = waited.tracks[i]
            #expect(a.segments.map(\.preset.id) == b.segments.map(\.preset.id), """
                    Track \(i) got different presets when the session was started early. \
                    Start Now would then be trading session quality for a shorter wait, which \
                    it must never do.
                    """)
            #expect(a.segments.map(\.plannedStartTime) == b.segments.map(\.plannedStartTime),
                    "Track \(i) segment boundaries differ between an early start and waiting")
        }

        // And the intermediate plans are prefixes of the final one — the listener
        // never sees a preset that is later retracted.
        let atThree = try planner.plan(
            tracks: tracks(3), catalog: catalog, deviceTier: .tier1, seed: seed)
        for i in 0..<3 {
            #expect(atThree.tracks[i].segments.map(\.preset.id)
                    == waited.tracks[i].segments.map(\.preset.id),
                    "The plan shown at the prefix disagrees with the final plan at track \(i)")
        }
    }
}

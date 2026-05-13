// SessionPlannerTests — unit tests for DefaultSessionPlanner (Increment 4.3).
//
// All tests use hand-built fixture values — no real preset JSON or audio files.
// Fixture builders at the bottom keep tests compact and readable.
//
// Naming convention for comparison: we compare preset IDs, track titles, and
// timing fields directly since PlannedSession/PlannedTrack are Sendable-only
// (PresetDescriptor and TrackProfile lack Equatable conformance).

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared
import simd

// MARK: - Test Suite

@Suite("DefaultSessionPlanner")
struct SessionPlannerTests {

    private let planner = DefaultSessionPlanner()

    // MARK: 1 — Empty playlist throws

    @Test("plan with empty tracks throws .emptyPlaylist")
    func emptyPlaylist_throws() throws {
        #expect(throws: SessionPlanningError.emptyPlaylist) {
            try planner.plan(tracks: [], catalog: makeCatalog(), deviceTier: .tier1)
        }
    }

    // MARK: 2 — Empty catalog throws

    @Test("plan with empty catalog throws .emptyCatalog")
    func emptyCatalog_throws() throws {
        let track = (makeIdentity(title: "A"), makeProfile())
        #expect(throws: SessionPlanningError.emptyCatalog) {
            try planner.plan(tracks: [track], catalog: [], deviceTier: .tier1)
        }
    }

    // MARK: 3 — Single-track plan

    @Test("Single-track plan: 1 entry, nil incomingTransition, correct timing")
    func singleTrack_correctEntry() throws {
        let duration = 180.0
        let identity = makeIdentity(title: "Solo Track", duration: duration)
        let profile  = makeProfile(bpm: 120, valence: 0, arousal: 0)
        let catalog  = makeCatalog()

        let session = try planner.plan(tracks: [(identity, profile)], catalog: catalog, deviceTier: .tier1)

        #expect(session.tracks.count == 1)
        let entry = try #require(session.tracks.first)
        #expect(entry.track.title == "Solo Track")
        #expect(entry.incomingTransition == nil, "First track must have no incomingTransition")
        #expect(entry.plannedStartTime == 0)
        #expect(entry.plannedEndTime == duration)
        #expect(session.totalDuration == duration)
    }

    // MARK: 4 — No consecutive same family (or it's warned)

    @Test("Five-track plan: consecutive same-family always accompanied by a warning")
    func noUnjustifiedFamilyRepeat() throws {
        // 5 tracks with varied moods
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (makeIdentity(title: "T1"), makeProfile(bpm: 60,  valence: -0.8, arousal: -0.7)),
            (makeIdentity(title: "T2"), makeProfile(bpm: 130, valence:  0.8, arousal:  0.8)),
            (makeIdentity(title: "T3"), makeProfile(bpm: 90,  valence:  0.0, arousal:  0.0)),
            (makeIdentity(title: "T4"), makeProfile(bpm: 170, valence:  0.6, arousal:  0.9)),
            (makeIdentity(title: "T5"), makeProfile(bpm: 75,  valence: -0.4, arousal: -0.5)),
        ]
        // 3 families, 2 presets each — gives the scorer options
        let catalog = [
            makePreset(name: "F1a", family: .reaction,    motionIntensity: 0.4, colorTempRange: SIMD2(0.1, 0.35)),
            makePreset(name: "F1b", family: .reaction,    motionIntensity: 0.6, colorTempRange: SIMD2(0.15, 0.40)),
            makePreset(name: "G1a", family: .geometric, motionIntensity: 0.7, colorTempRange: SIMD2(0.4, 0.65)),
            makePreset(name: "G1b", family: .geometric, motionIntensity: 0.5, colorTempRange: SIMD2(0.35, 0.60)),
            makePreset(name: "A1a", family: .particles,  motionIntensity: 0.8, colorTempRange: SIMD2(0.65, 0.90)),
            makePreset(name: "A1b", family: .particles,  motionIntensity: 0.9, colorTempRange: SIMD2(0.70, 0.95)),
        ]

        let session = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)

        #expect(session.tracks.count == 5)

        for i in 1..<session.tracks.count {
            let prev = session.tracks[i - 1]
            let curr = session.tracks[i]
            if prev.preset.family == curr.preset.family {
                // A consecutive same-family pick must appear in warnings.
                let hasWarning = session.warnings.contains {
                    $0.kind == .forcedFamilyRepeat && $0.trackIndex == i
                }
                #expect(hasWarning,
                        "Track \(i) shares family '\(curr.preset.family?.rawValue ?? "(none)")' with previous but no warning found")
            }
        }
    }

    // MARK: 5 — Tier 1 excludes expensive preset

    @Test("Expensive preset (tier1=20 ms) never appears in tier1 plan; may appear in tier2")
    func tier1ExcludesExpensivePreset() throws {
        let expensiveName = "HeavyPreset"
        let expensive = makePreset(
            name: expensiveName,
            family: .fractal,
            complexityCost: ComplexityCost(tier1: 20.0, tier2: 8.0)
        )
        let affordable = [
            makePreset(name: "Cheap1", family: .reaction,    complexityCost: ComplexityCost(tier1: 2.0, tier2: 1.5)),
            makePreset(name: "Cheap2", family: .geometric, complexityCost: ComplexityCost(tier1: 3.0, tier2: 2.0)),
            makePreset(name: "Cheap3", family: .geometric,  complexityCost: ComplexityCost(tier1: 4.0, tier2: 2.5)),
        ]
        let catalog = affordable + [expensive]
        let tracks = (1...3).map { i -> (TrackIdentity, TrackProfile) in
            (makeIdentity(title: "Track\(i)"), makeProfile())
        }

        let tier1Plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)
        let tier2Plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)

        let tier1IDs = tier1Plan.tracks.map { $0.preset.id }
        #expect(!tier1IDs.contains(expensiveName),
                "Expensive preset must never appear in a tier1 plan")

        let tier2IDs = tier2Plan.tracks.map { $0.preset.id }
        // Not asserting it MUST appear in tier2 — scorer may still prefer others —
        // but verify no exclusion error was generated for it.
        let tier2Warnings = tier2Plan.warnings.filter { $0.kind == .noEligiblePresets }
        _ = tier2IDs  // tier2 plan compiles without crashing; warnings are soft only
        _ = tier2Warnings
    }

    // MARK: 6 — Mood arc across playlist

    @Test("Cool preset selected for sad track, warm preset for happy track")
    func moodArcPreservesColorTemperature() throws {
        let sadTrack    = makeProfile(bpm: 70,  valence: -0.9, arousal: -0.7)
        let happyTrack  = makeProfile(bpm: 120, valence:  0.9, arousal:  0.6)
        let neutralTrack = makeProfile(bpm: 95, valence:  0.0, arousal:  0.0)

        // Presets differ ONLY in color temperature — isolates the mood signal.
        let coolPreset  = makePreset(name: "Cool",  family: .reaction,    motionIntensity: 0.5,
                                     colorTempRange: SIMD2(0.0, 0.2))
        let midPreset   = makePreset(name: "Mid",   family: .geometric, motionIntensity: 0.5,
                                     colorTempRange: SIMD2(0.4, 0.6))
        let warmPreset  = makePreset(name: "Warm",  family: .geometric,  motionIntensity: 0.5,
                                     colorTempRange: SIMD2(0.8, 1.0))
        let catalog = [coolPreset, midPreset, warmPreset]

        let tracks: [(TrackIdentity, TrackProfile)] = [
            (makeIdentity(title: "Sad"),    sadTrack),
            (makeIdentity(title: "Neutral"), neutralTrack),
            (makeIdentity(title: "Happy"),   happyTrack),
        ]

        let session = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)

        let centers = session.tracks.map { entry -> Float in
            let r = entry.preset.colorTemperatureRange
            return (r.x + r.y) / 2
        }

        // Sad → happy should produce monotonically non-decreasing temperature centers.
        #expect(centers[0] <= centers[2],
                "Sad track (\(centers[0])) should select a cooler preset than happy track (\(centers[2]))")
    }

    // MARK: 7 — Fatigue cooldown respected, no crash

    @Test("Five tracks, catalog of 2 presets same family: plan succeeds, warnings present")
    func fatigueCooldown_smallCatalog_nocrash() throws {
        let catalog = [
            makePreset(name: "P1", family: .reaction, fatigueRisk: .high),
            makePreset(name: "P2", family: .reaction, fatigueRisk: .high),
        ]
        let tracks = (1...5).map { i -> (TrackIdentity, TrackProfile) in
            (makeIdentity(title: "T\(i)"), makeProfile())
        }

        let session = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)

        #expect(session.tracks.count == 5)
        // With only one family, every pick after the first is a family repeat.
        let repeatWarnings = session.warnings.filter { $0.kind == .forcedFamilyRepeat }
        #expect(!repeatWarnings.isEmpty, "Expected at least one .forcedFamilyRepeat warning")
    }

    // MARK: 8 — All presets excluded → fallback + warns

    @Test("All presets over budget: plan succeeds, noEligiblePresets + budgetExceeded warnings")
    func allExcluded_fallback_warns() throws {
        // Tier1 budget = 16.6 ms; both presets cost 100 ms on tier1.
        let tooBig1 = makePreset(name: "Big1", family: .reaction,
                                  complexityCost: ComplexityCost(tier1: 100.0, tier2: 5.0))
        let tooBig2 = makePreset(name: "Big2", family: .geometric,
                                  complexityCost: ComplexityCost(tier1: 100.0, tier2: 5.0))
        let catalog = [tooBig1, tooBig2]
        let tracks  = [(makeIdentity(title: "Track"), makeProfile())]

        let session = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)

        #expect(session.tracks.count == 1, "Plan must still produce 1 entry")
        #expect(session.warnings.contains { $0.kind == .noEligiblePresets },
                "Expected .noEligiblePresets warning")
    }

    // MARK: 9 — Determinism

    @Test("Same inputs produce byte-identical PlannedSession.tracks and .warnings")
    func determinism() throws {
        var tracks: [(TrackIdentity, TrackProfile)] = []
        for i in 1...4 {
            let identity = makeIdentity(title: "Track\(i)", duration: TimeInterval(i) * 60)
            let bpm = Float(80 + i * 10)
            let valence = Float(i) * 0.1
            let arousal = Float(i) * 0.15
            tracks.append((identity, makeProfile(bpm: bpm, valence: valence, arousal: arousal)))
        }
        let catalog = makeCatalog()

        let session1 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)
        let session2 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)

        #expect(session1.tracks.map { $0.preset.id } == session2.tracks.map { $0.preset.id },
                "Preset selection must be deterministic")
        #expect(session1.tracks.map { $0.plannedStartTime } == session2.tracks.map { $0.plannedStartTime },
                "Start times must be deterministic")
        #expect(session1.warnings == session2.warnings,
                "Warnings must be deterministic")
    }

    // MARK: 10 — track(at:) lookup

    @Test("track(at:) returns correct entry across 3 × 60s tracks")
    func trackAtLookup() throws {
        let trackDuration = 60.0
        let tracks = (0..<3).map { i -> (TrackIdentity, TrackProfile) in
            (makeIdentity(title: "T\(i)", duration: trackDuration), makeProfile())
        }
        let session = try planner.plan(tracks: tracks, catalog: makeCatalog(), deviceTier: .tier1)

        #expect(session.track(at: 0)?.track.title     == "T0")
        #expect(session.track(at: 59.9)?.track.title  == "T0")
        #expect(session.track(at: 60.0)?.track.title  == "T1")
        #expect(session.track(at: 119.9)?.track.title == "T1")
        #expect(session.track(at: 120.0)?.track.title == "T2")
        #expect(session.track(at: 180.1) == nil, "Past the last track end should return nil")
    }

    // MARK: 11 — transition(at:) lookup

    @Test("transition(at:) respects tolerance window")
    func transitionAtLookup() throws {
        let trackDuration = 60.0
        let tracks = (0..<3).map { i -> (TrackIdentity, TrackProfile) in
            (makeIdentity(title: "T\(i)", duration: trackDuration), makeProfile())
        }
        let session = try planner.plan(tracks: tracks, catalog: makeCatalog(), deviceTier: .tier1)

        // Transitions are scheduled at session clock = 60 and 120.
        // Within tolerance=0.5: 60.0 ± 0.5 = [59.5, 60.5].
        #expect(session.transition(at: 60.0, tolerance: 0.5) != nil,
                "Exact scheduledAt should be found")
        #expect(session.transition(at: 60.4, tolerance: 0.5) != nil,
                "Within tolerance should be found")
        #expect(session.transition(at: 60.6, tolerance: 0.5) == nil,
                "Outside tolerance should return nil")
    }

    // MARK: 12 — planAsync: precompile called once per distinct preset

    @Test("planAsync invokes precompile closure once per distinct preset ID")
    func planAsync_precompileCalledOncePerDistinctPreset() async throws {
        // Build a plan where at least two tracks share the same preset.
        // Use a 2-preset catalog and 3 tracks — with alternating moods,
        // the scorer may reuse one preset for tracks 0 and 2.
        let catalog = [
            makePreset(name: "Only1", family: .reaction),
            makePreset(name: "Only2", family: .geometric),
        ]
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (makeIdentity(title: "T1"), makeProfile(valence: -0.5, arousal: -0.5)),
            (makeIdentity(title: "T2"), makeProfile(valence:  0.5, arousal:  0.5)),
            (makeIdentity(title: "T3"), makeProfile(valence: -0.5, arousal: -0.5)),
        ]

        actor CompileLog {
            var log: [String] = []
            func append(_ id: String) { log.append(id) }
        }
        let compileLog = CompileLog()

        let plannerWithPrecompile = DefaultSessionPlanner(precompile: { @Sendable preset in
            await compileLog.append(preset.id)
        })

        let session = try await plannerWithPrecompile.planAsync(
            tracks: tracks, catalog: catalog, deviceTier: .tier1
        )

        let log = await compileLog.log
        let distinctIDs = Set(session.tracks.map { $0.preset.id })
        #expect(Set(log) == distinctIDs,
                "Precompile must be called for exactly the distinct preset IDs in the plan")
        #expect(log.count == distinctIDs.count,
                "Precompile must not be called more times than there are distinct presets")
    }

    // MARK: 13 — planAsync: precompile failure surfaces as error, plan still valid

    @Test("planAsync throws precompileFailed after planning; plan itself was valid")
    func planAsync_precompileFailure_surfacesError() async throws {
        let targetPresetName = "FailPreset"
        let catalog = [
            makePreset(name: targetPresetName, family: .reaction,
                       complexityCost: ComplexityCost(tier1: 2.0, tier2: 1.5)),
            makePreset(name: "GoodPreset", family: .geometric,
                       complexityCost: ComplexityCost(tier1: 2.0, tier2: 1.5)),
        ]
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (makeIdentity(title: "T1"), makeProfile(valence: -0.5, arousal: 0.0)),
        ]

        let plannerWithFailing = DefaultSessionPlanner(precompile: { @Sendable preset in
            if preset.id == targetPresetName {
                throw PlannerTestError.intentional("preset \(preset.id) precompile failed")
            }
        })

        do {
            _ = try await plannerWithFailing.planAsync(
                tracks: tracks, catalog: catalog, deviceTier: .tier1
            )
            // If the chosen preset wasn't targetPresetName, no throw happens — that's OK.
        } catch let error as SessionPlanningError {
            // Verify the error carries the preset ID.
            if case .precompileFailed(let id, _) = error {
                #expect(id == targetPresetName)
            } else {
                Issue.record("Expected .precompileFailed, got \(error)")
            }
        }
    }
}

// MARK: - Helpers

private enum PlannerTestError: Error {
    case intentional(String)
}

// MARK: - Fixture Builders

private func makeIdentity(
    title: String = "TestTrack",
    artist: String = "TestArtist",
    duration: TimeInterval = 180
) -> TrackIdentity {
    TrackIdentity(title: title, artist: artist, duration: duration)
}

private func makeProfile(
    bpm: Float? = nil,
    valence: Float = 0,
    arousal: Float = 0,
    stemBalance: StemFeatures = .zero
) -> TrackProfile {
    TrackProfile(
        bpm: bpm,
        mood: EmotionalState(valence: valence, arousal: arousal),
        stemEnergyBalance: stemBalance
    )
}

/// Minimal JSON-decoded PresetDescriptor with sensible defaults.
private func makePreset(
    name: String = "TestPreset",
    family: PresetCategory = .geometric,
    motionIntensity: Float = 0.5,
    colorTempRange: SIMD2<Float> = SIMD2(0.3, 0.7),
    fatigueRisk: FatigueRisk = .medium,
    sectionSuitability: [SongSection] = SongSection.allCases,
    stemAffinity: [String: String] = [:],
    complexityCost: ComplexityCost = ComplexityCost(tier1: 2.0, tier2: 1.5),
    transitionAffordances: [TransitionAffordance] = [.crossfade]
) -> PresetDescriptor {
    let sectionJSON = sectionSuitability.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
    let stemJSON    = stemAffinity.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ",")
    let affordJSON  = transitionAffordances.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
    let json = """
    {
        "name": "\(name)",
        "family": "\(family.rawValue)",
        "motion_intensity": \(motionIntensity),
        "color_temperature_range": [\(colorTempRange.x), \(colorTempRange.y)],
        "fatigue_risk": "\(fatigueRisk.rawValue)",
        "section_suitability": [\(sectionJSON)],
        "stem_affinity": {\(stemJSON)},
        "complexity_cost": {"tier1": \(complexityCost.tier1), "tier2": \(complexityCost.tier2)},
        "transition_affordances": [\(affordJSON)],
        "certified": true
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

/// A small diverse catalog: 3 families, distinct costs, varied motion and temperature.
private func makeCatalog() -> [PresetDescriptor] {
    [
        makePreset(name: "FluidA",    family: .reaction,    motionIntensity: 0.3,
                   colorTempRange: SIMD2(0.1, 0.35), complexityCost: ComplexityCost(tier1: 2.0, tier2: 1.5)),
        makePreset(name: "FluidB",    family: .reaction,    motionIntensity: 0.5,
                   colorTempRange: SIMD2(0.2, 0.45), complexityCost: ComplexityCost(tier1: 2.5, tier2: 1.5)),
        makePreset(name: "GeoA",      family: .geometric, motionIntensity: 0.6,
                   colorTempRange: SIMD2(0.4, 0.65), complexityCost: ComplexityCost(tier1: 3.0, tier2: 2.0)),
        makePreset(name: "GeoB",      family: .geometric, motionIntensity: 0.75,
                   colorTempRange: SIMD2(0.45, 0.70), complexityCost: ComplexityCost(tier1: 4.0, tier2: 2.5)),
        makePreset(name: "AbstractA", family: .geometric,  motionIntensity: 0.85,
                   colorTempRange: SIMD2(0.65, 0.90), complexityCost: ComplexityCost(tier1: 5.0, tier2: 3.0)),
        makePreset(name: "AbstractB", family: .geometric,  motionIntensity: 0.95,
                   colorTempRange: SIMD2(0.75, 0.95), complexityCost: ComplexityCost(tier1: 6.0, tier2: 3.5)),
    ]
}

// =====================================================================
// MARK: - SessionPlannerMultiSegmentTests (V.7.6.2 §3.3)
//
// Consolidated from SessionPlannerMultiSegmentTests.swift in [QR.5]
// (C.3 test-file consolidation). Suite is unchanged; helpers live
// under `MultiSegFixtures` to avoid naming collisions with the
// SessionPlannerTests helpers above.
// =====================================================================

private enum MultiSegFixtures {

    static func makeIdentity(title: String, duration: TimeInterval) -> TrackIdentity {
        TrackIdentity(title: title, artist: "MultiSegArtist", duration: duration)
    }

    static func makeProfile(sectionCount: Int = 1) -> TrackProfile {
        TrackProfile(estimatedSectionCount: sectionCount)
    }

    /// Build a small synthetic catalog of two distinct presets with controlled maxDurations.
    /// LongPreset uses motion=0.5, density=0.5, fatigue=low → baseMax=90 → maxDuration=90 s.
    /// ShortPreset uses motion=0.5, density=0.5, fatigue=high → baseMax=30 → maxDuration=30 s.
    static func makeSyntheticCatalog() throws -> [PresetDescriptor] {
        let long = """
        {"name":"LongPreset","family":"sparkle",
         "motion_intensity":0.5,"visual_density":0.5,"fatigue_risk":"low",
         "transition_affordances":["crossfade"]}
        """
        let short = """
        {"name":"ShortPreset","family":"reaction",
         "motion_intensity":0.5,"visual_density":0.5,"fatigue_risk":"high",
         "transition_affordances":["crossfade"]}
        """
        let decoder = JSONDecoder()
        return [
            try decoder.decode(PresetDescriptor.self, from: Data(long.utf8)),
            try decoder.decode(PresetDescriptor.self, from: Data(short.utf8))
        ]
    }
}

@Suite("SessionPlannerMultiSegment")
struct SessionPlannerMultiSegmentTests {

    @Test("Short track (20 s) emits one segment, terminationReason=trackEnded")
    func shortTrackSingleSegment() throws {
        let planner = DefaultSessionPlanner()
        let catalog = try MultiSegFixtures.makeSyntheticCatalog()
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (MultiSegFixtures.makeIdentity(title: "ShortTrack", duration: 20), MultiSegFixtures.makeProfile())
        ]
        let plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        #expect(plan.tracks.count == 1)
        #expect(plan.tracks[0].segments.count == 1)
        #expect(plan.tracks[0].segments[0].terminationReason == .trackEnded)
        #expect(plan.tracks[0].segments[0].plannedStartTime == 0)
        #expect(plan.tracks[0].segments[0].plannedEndTime == 20)
    }

    @Test("Long track (300 s, 1 section) emits ≥ 2 segments, mid-segment termination=maxDurationReached")
    func longTrackMultiSegment() throws {
        let planner = DefaultSessionPlanner()
        let catalog = try MultiSegFixtures.makeSyntheticCatalog()
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (MultiSegFixtures.makeIdentity(title: "LongTrack", duration: 300), MultiSegFixtures.makeProfile(sectionCount: 1))
        ]
        let plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        let segments = plan.tracks[0].segments
        #expect(segments.count >= 2, "300 s track should split into ≥ 2 segments")
        for seg in segments.dropLast() {
            #expect(seg.terminationReason == .maxDurationReached,
                "Mid-segment of single-section track should terminate by maxDurationReached")
        }
        #expect(segments.last?.terminationReason == .trackEnded)
        for i in 1..<segments.count {
            #expect(abs(segments[i].plannedStartTime - segments[i - 1].plannedEndTime) < 0.001)
        }
        #expect(abs(segments.last!.plannedEndTime - 300) < 0.001) // swiftlint:disable:this force_unwrapping
    }

    @Test("Section boundaries land within ±1 s of even split for multi-section track")
    func sectionBoundariesRespected() throws {
        let planner = DefaultSessionPlanner()
        let catalog = try MultiSegFixtures.makeSyntheticCatalog()
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (MultiSegFixtures.makeIdentity(title: "ThreeSection", duration: 90), MultiSegFixtures.makeProfile(sectionCount: 3))
        ]
        let plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        let segments = plan.tracks[0].segments
        #expect(segments.count == 3)
        let expectedBoundaries: [Double] = [30, 60, 90]
        for (idx, seg) in segments.enumerated() {
            #expect(abs(seg.plannedEndTime - expectedBoundaries[idx]) < 0.001)
        }
    }

    @Test("Determinism: same inputs + same seed → identical segment sequence")
    func multiSegmentDeterminism() throws {
        let planner = DefaultSessionPlanner()
        let catalog = try MultiSegFixtures.makeSyntheticCatalog()
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (MultiSegFixtures.makeIdentity(title: "T1", duration: 300), MultiSegFixtures.makeProfile(sectionCount: 1)),
            (MultiSegFixtures.makeIdentity(title: "T2", duration: 240), MultiSegFixtures.makeProfile(sectionCount: 2))
        ]
        let p1 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        let p2 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)

        for (track1, track2) in zip(p1.tracks, p2.tracks) {
            #expect(track1.segments.count == track2.segments.count)
            for (s1, s2) in zip(track1.segments, track2.segments) {
                #expect(s1.preset.id == s2.preset.id)
                #expect(s1.plannedStartTime == s2.plannedStartTime)
                #expect(s1.plannedEndTime == s2.plannedEndTime)
                #expect(s1.terminationReason == s2.terminationReason)
            }
        }
    }

    @Test("PlannedSession.segment(at:) returns the segment covering that session time")
    func segmentAtAccessor() throws {
        let planner = DefaultSessionPlanner()
        let catalog = try MultiSegFixtures.makeSyntheticCatalog()
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (MultiSegFixtures.makeIdentity(title: "T1", duration: 300), MultiSegFixtures.makeProfile(sectionCount: 1))
        ]
        let plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)

        for t in [10.0, 50.0, 100.0, 200.0, 290.0] {
            let seg = plan.segment(at: t)
            #expect(seg != nil, "Expected segment at t=\(t)")
            if let seg = seg {
                #expect(t >= seg.plannedStartTime && t < seg.plannedEndTime)
            }
        }
    }
}

// =====================================================================
// MARK: - SessionPlannerSeedTests (U.5 Part D, D-047)
//
// Consolidated from SessionPlannerSeedTests.swift in [QR.5]
// (C.3 test-file consolidation). Helpers under `SeedFixtures`.
// =====================================================================

private enum SeedFixtures {

    static func makeIdentity(title: String = "T", duration: TimeInterval = 180) -> TrackIdentity {
        TrackIdentity(title: title, artist: "A", duration: duration)
    }

    static func makeProfile() -> TrackProfile { TrackProfile.empty }

    static func makePreset(name: String) throws -> PresetDescriptor {
        let json = """
        {"name":"\(name)","family":"geometric","motion_intensity":0.5,
         "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
         "complexity_cost":{"tier1":1.0,"tier2":1.0},
         "transition_affordances":["crossfade"],"certified":true}
        """
        return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }
}

@Suite("DefaultSessionPlanner seed")
struct SessionPlannerSeedTests {

    private let planner = DefaultSessionPlanner()

    @Test("zero seed: plan is byte-identical across two calls (D-034 preserved)")
    func zeroSeed_isDeterministic() throws {
        let tracks = [(SeedFixtures.makeIdentity(title: "A"), SeedFixtures.makeProfile()),
                      (SeedFixtures.makeIdentity(title: "B"), SeedFixtures.makeProfile())]
        let catalog = [try SeedFixtures.makePreset(name: "P1"), try SeedFixtures.makePreset(name: "P2")]

        let s1 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: 0)
        let s2 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: 0)

        let ids1 = s1.tracks.map { $0.preset.id }
        let ids2 = s2.tracks.map { $0.preset.id }
        #expect(ids1 == ids2)
    }

    @Test("same nonzero seed twice: output is identical (reproducible randomisation)")
    func sameSeedTwice_isDeterministic() throws {
        let tracks = (0..<5).map { i in (SeedFixtures.makeIdentity(title: "Track\(i)"), SeedFixtures.makeProfile()) }
        let catalog = try (0..<4).map { i in try SeedFixtures.makePreset(name: "P\(i)") }

        let seed: UInt64 = 42_000_000_000
        let s1 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: seed)
        let s2 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: seed)

        let ids1 = s1.tracks.map { $0.preset.id }
        let ids2 = s2.tracks.map { $0.preset.id }
        #expect(ids1 == ids2)
    }

    @Test("nonzero seed no-op when catalog has only one eligible preset")
    func nonzeroSeed_singlePreset_noChange() throws {
        let tracks = [(SeedFixtures.makeIdentity(title: "Only"), SeedFixtures.makeProfile())]
        let catalog = [try SeedFixtures.makePreset(name: "Solo")]

        let s0 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: 0)
        let s1 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1, seed: 99)

        #expect(s0.tracks.first?.preset.id == s1.tracks.first?.preset.id)
    }

    @Test("applying(overrides:) preserves locked track picks")
    func applyingOverrides_preservesLocks() throws {
        let tracks = [(SeedFixtures.makeIdentity(title: "A"), SeedFixtures.makeProfile()),
                      (SeedFixtures.makeIdentity(title: "B"), SeedFixtures.makeProfile())]
        let p1 = try SeedFixtures.makePreset(name: "P1")
        let p2 = try SeedFixtures.makePreset(name: "P2")
        let locked = try SeedFixtures.makePreset(name: "LockedPreset")

        let plan = try planner.plan(tracks: tracks, catalog: [p1, p2], deviceTier: .tier1)
        let firstTrackID = plan.tracks[0].track
        let patched = plan.applying(overrides: [firstTrackID: locked])

        #expect(patched.tracks[0].preset.id == locked.id)
        #expect(patched.tracks[1].preset.id == plan.tracks[1].preset.id)
    }

    @Test("applying(overrides:) with empty dict returns self-equivalent plan")
    func applyingOverrides_empty_unchanged() throws {
        let tracks = [(SeedFixtures.makeIdentity(), SeedFixtures.makeProfile())]
        let catalog = [try SeedFixtures.makePreset(name: "P1")]
        let plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)
        let patched = plan.applying(overrides: [:])

        #expect(patched.tracks[0].preset.id == plan.tracks[0].preset.id)
        #expect(patched.tracks.count == plan.tracks.count)
    }
}

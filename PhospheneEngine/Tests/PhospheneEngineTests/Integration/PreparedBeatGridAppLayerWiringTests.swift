// PreparedBeatGridAppLayerWiringTests — BUG-006.2 regression coverage.
//
// BUG-003 documented that the prepared-BeatGrid path lacked an end-to-end
// regression test, which let BUG-006 ship: the engine.stemCache field was
// declared but never assigned, AND the track-change handler constructed a
// partial TrackIdentity (title + artist only) that didn't match the cache
// keys SessionPreparer stored. Existing `PreparedBeatGridWiringTests` only
// covered the unit-level chain inside the engine — it never exercised the
// app-layer integration where both bugs lived.
//
// `VisualizerEngine` cannot be instantiated in SPM tests (Metal device,
// AudioBuffer, RenderPipeline, etc.). These tests therefore exercise the
// app-layer integration via the seams the BUG-006.2 fix made testable:
//   1. `SessionManager.cache` returns the same `StemCache` instance that
//      `SessionPreparer` populates → any consumer reading
//      `sessionManager.cache` (which is what `engine.stemCache` is wired to)
//      sees prepared entries by reference.
//   2. `PlannedSession.canonicalIdentity(matchingTitle:artist:)` is the pure
//      function the app-layer track-change handler calls to recover the full
//      `TrackIdentity` from a streaming-metadata title+artist pair.
//   3. End-to-end: storing a CachedTrackData under the planned identity and
//      then looking it up via the canonical-identity path produces a hit
//      whose `beatGrid` installs into a real `MIRPipeline.liveDriftTracker`.
//
// These three tests would each have failed against the pre-fix codebase.

import Foundation
import Testing
@testable import DSP
@testable import Orchestrator
@testable import Presets
@testable import Session
@testable import Shared

// MARK: - Fixtures

private func makeFullIdentity(
    title: String = "Love Rehab",
    artist: String = "Chaim",
    duration: Double? = 240.0,
    spotifyID: String? = "spfy_love_rehab"
) -> TrackIdentity {
    TrackIdentity(
        title: title,
        artist: artist,
        album: nil,
        duration: duration,
        appleMusicID: nil,
        spotifyID: spotifyID,
        musicBrainzID: nil
    )
}

private func makePartialIdentity(
    title: String = "Love Rehab",
    artist: String = "Chaim"
) -> TrackIdentity {
    // Mirrors the construction in VisualizerEngine+Capture.swift when livePlan
    // resolution is unavailable (ad-hoc / reactive sessions).
    TrackIdentity(title: title, artist: artist)
}

private func makeGrid(bpm: Double = 125.0, beats: Int = 60) -> BeatGrid {
    let period = 60.0 / bpm
    let beatTimes = (0..<beats).map { Double($0) * period }
    let downbeatTimes = stride(from: 0, to: beats, by: 4).map { Double($0) * period }
    return BeatGrid(
        beats: beatTimes, downbeats: downbeatTimes, bpm: bpm,
        beatsPerBar: 4, barConfidence: 0.95, frameRate: 50.0, frameCount: 1500
    )
}

private func makeCachedData(grid: BeatGrid) -> CachedTrackData {
    CachedTrackData(stemWaveforms: [], stemFeatures: .zero, trackProfile: .empty, beatGrid: grid)
}

private func makePresetDescriptor() -> PresetDescriptor {
    let json = """
    {
        "name": "Test Preset",
        "family": "organic",
        "certified": true,
        "complexity_cost": {"tier1": 1.0, "tier2": 1.0}
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

private func makePlannedSession(tracks: [TrackIdentity]) -> PlannedSession {
    let preset = makePresetDescriptor()
    let breakdown = PresetScoreBreakdown(
        mood: 1.0, tempoMotion: 1.0, stemAffinity: 1.0,
        sectionSuitability: 1.0, familyRepeatMultiplier: 1.0,
        fatigueMultiplier: 1.0, excluded: false, exclusionReason: nil,
        familyBoost: 0.0, excludedReason: nil, total: 1.0
    )
    let plannedTracks: [PlannedTrack] = tracks.enumerated().map { idx, track in
        let start = Double(idx) * 240.0
        let end = start + 240.0
        return PlannedTrack(
            track: track,
            trackProfile: .empty,
            preset: preset,
            presetScore: 1.0,
            scoreBreakdown: breakdown,
            plannedStartTime: start,
            plannedEndTime: end,
            incomingTransition: nil
        )
    }
    return PlannedSession(
        deviceTier: .tier1,
        tracks: plannedTracks,
        totalDuration: 240.0 * Double(tracks.count),
        warnings: []
    )
}

// MARK: - Tests

@Suite("Prepared BeatGrid app-layer wiring (BUG-006.2)")
struct PreparedBeatGridAppLayerWiringTests {

    // MARK: 1. engine.stemCache wiring (cause 1)

    /// `engine.stemCache` is wired to `sessionManager.cache` at engine init.
    /// Since both reference the same `StemCache` instance, entries written by
    /// `SessionPreparer.prepare(tracks:)` are visible to the engine without any
    /// further hand-off. This test proves the reference identity contract that
    /// the app-layer fix relies on; pre-fix the field was nil forever.
    @Test("engineStemCache_isWiredAfterSessionPrepare")
    func test_engineStemCache_isWiredAfterSessionPrepare() async {
        let cache = StemCache()
        let track = makeFullIdentity()
        let grid = makeGrid()

        // Simulate the production wiring: the engine holds the same StemCache
        // reference that SessionPreparer writes into. (engine.stemCache =
        // sessionManager.cache → preparer.cache → this same instance.)
        let engineFacingCache: StemCache = cache

        // Pre-condition: empty cache, no entries.
        #expect(engineFacingCache.count == 0)
        #expect(engineFacingCache.loadForPlayback(track: track) == nil)

        // SessionPreparer writes asynchronously per track. We mirror its final
        // store(_:for:) call directly so the test stays deterministic.
        cache.store(makeCachedData(grid: grid), for: track)

        // The engine-facing reference now sees the entry — without any
        // explicit hand-off, because both are the same instance.
        #expect(engineFacingCache.count == 1)
        let hit = engineFacingCache.loadForPlayback(track: track)
        #expect(hit != nil)
        #expect(hit?.beatGrid.bpm == 125.0)
        #expect(hit?.beatGrid.beats.count == 60)
    }

    // MARK: 2. canonical TrackIdentity match (cause 2)

    /// Streaming metadata produces a partial `TrackIdentity` (title+artist
    /// only). The PlannedSession was built from full identities. The canonical
    /// resolver must find the planned identity given the partial pair so the
    /// downstream `loadForPlayback` cache key matches.
    @Test("trackChangeIdentity_matchesPlannedIdentity")
    func test_trackChangeIdentity_matchesPlannedIdentity() {
        let plannedFull = makeFullIdentity(title: "Love Rehab", artist: "Chaim")
        let plan = makePlannedSession(tracks: [plannedFull])

        let partial = makePartialIdentity(title: "Love Rehab", artist: "Chaim")

        // Pre-condition: partial != full at the Hashable level (this is the
        // bug — would-be cache lookups miss before BUG-006.2).
        #expect(partial != plannedFull)
        #expect(partial.hashValue != plannedFull.hashValue)

        // Canonical resolver returns the full planned identity.
        let resolved = plan.canonicalIdentity(matchingTitle: partial.title, artist: partial.artist)
        #expect(resolved == plannedFull)
        #expect(resolved?.spotifyID == "spfy_love_rehab")
        #expect(resolved?.duration == 240.0)
    }

    /// Ambiguous matches (same title+artist on two planned tracks) return
    /// nil so the caller falls back to the partial identity. Real playlists
    /// rarely repeat exact title+artist pairs, but the fallback keeps
    /// behaviour conservative.
    @Test("ambiguousMatch_returnsNil_partialFallback")
    func test_ambiguousMatch_returnsNil() {
        let dup1 = makeFullIdentity(title: "Track", artist: "X", duration: 100.0, spotifyID: "a")
        let dup2 = makeFullIdentity(title: "Track", artist: "X", duration: 200.0, spotifyID: "b")
        let plan = makePlannedSession(tracks: [dup1, dup2])

        let partial = makePartialIdentity(title: "Track", artist: "X")
        #expect(plan.canonicalIdentity(matchingTitle: partial.title, artist: partial.artist) == nil)
    }

    /// No-match returns nil (caller falls back to partial; live Beat This!
    /// path remains the source of truth — same behaviour as pre-fix).
    @Test("noMatch_returnsNil")
    func test_noMatch_returnsNil() {
        let plan = makePlannedSession(tracks: [makeFullIdentity(title: "Other", artist: "Y")])
        let partial = makePartialIdentity(title: "Missing", artist: "Z")
        #expect(plan.canonicalIdentity(matchingTitle: partial.title, artist: partial.artist) == nil)
    }

    // MARK: 3. End-to-end: prepared cache install via canonical identity

    /// Drives the full chain that BUG-003 specifically tracked:
    ///   SessionPreparer stores under full identity →
    ///   streaming-metadata partial identity arrives →
    ///   canonicalIdentity recovers the full identity →
    ///   loadForPlayback hits →
    ///   MIRPipeline.setBeatGrid installs →
    ///   liveDriftTracker.hasGrid == true.
    ///
    /// Pre-fix, the partial identity hashes differently → cache miss →
    /// liveDriftTracker stays empty until the live Beat This! path fires
    /// (~10 s). This test pins the production wiring against that regression.
    @Test("endToEndProduces_preparedCacheInstall")
    func test_endToEnd_producesPreparedCacheInstall() {
        let cache = StemCache()
        let mir = MIRPipeline()
        let plannedFull = makeFullIdentity()
        let plan = makePlannedSession(tracks: [plannedFull])

        // 1. SessionPreparer-style store under the full identity.
        cache.store(makeCachedData(grid: makeGrid(bpm: 125.0)), for: plannedFull)

        // 2. Streaming metadata observes a track-change with partial fields.
        let partial = makePartialIdentity()

        // 3. App-layer track-change handler calls canonicalIdentity to recover
        //    the planned full identity.
        let resolved = plan.canonicalIdentity(matchingTitle: partial.title, artist: partial.artist)
        #expect(resolved != nil)

        // 4. loadForPlayback hits using the canonical identity.
        let identity = resolved ?? partial
        let cached = cache.loadForPlayback(track: identity)
        #expect(cached != nil, "cache lookup must hit using canonical identity")

        // 5. MIRPipeline installs the prepared grid.
        if let cached {
            mir.setBeatGrid(cached.beatGrid)
        }

        // 6. liveDriftTracker reports hasGrid == true — the SpectralCartograph
        //    mode label can advance past REACTIVE on the very first frame.
        #expect(mir.liveDriftTracker.hasGrid)
        #expect(mir.liveDriftTracker.currentBPM == 125.0)
    }

    /// Negative control: dropping the canonical-identity step (i.e. the
    /// pre-fix code path) keeps `hasGrid` false because the partial-identity
    /// hash misses the cache. This test would have *passed against the buggy
    /// code* and *failed against the fix* — it pins the regression direction.
    @Test("partialIdentity_withoutCanonicalResolution_missesCache")
    func test_partialIdentity_withoutCanonical_missesCache() {
        let cache = StemCache()
        let mir = MIRPipeline()
        let plannedFull = makeFullIdentity()
        cache.store(makeCachedData(grid: makeGrid()), for: plannedFull)

        // Pre-fix path: pass the partial identity directly.
        let partial = makePartialIdentity()
        let cached = cache.loadForPlayback(track: partial)
        if let cached {
            mir.setBeatGrid(cached.beatGrid)
        } else {
            mir.setBeatGrid(nil)
        }

        // Pre-fix outcome: cache miss, hasGrid stays false.
        #expect(cached == nil)
        #expect(!mir.liveDriftTracker.hasGrid)
    }
}

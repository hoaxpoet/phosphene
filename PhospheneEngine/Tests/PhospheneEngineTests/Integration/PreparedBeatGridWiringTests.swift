// PreparedBeatGridWiringTests — DSP.3.6
//
// Verifies the prepared-cache BeatGrid wiring path:
//   StemCache → resetStemPipeline(for:) → MIRPipeline.setBeatGrid → liveDriftTracker.hasGrid
//
// `resetStemPipeline(for:)` lives in the app layer (VisualizerEngine+Stems.swift) and
// requires a full Metal/audio stack that cannot be spun up in SPM tests.  These tests
// therefore exercise the critical chain components directly, mirroring the production
// code path exactly:
//
//   App layer (resetStemPipeline):
//     if let cached = stemCache?.loadForPlayback(track: identity) {
//         mirPipeline.setBeatGrid(cached.beatGrid)          ← identical here
//     } else {
//         mirPipeline.setBeatGrid(nil)                       ← identical here
//     }
//
// Five invariants proven:
//   1. Prepared non-empty BeatGrid stored in StemCache → MIRPipeline receives it →
//      liveDriftTracker.hasGrid == true, currentBPM matches (prepared path wins).
//   2. liveDriftTracker.hasGrid == true → the `runLiveBeatAnalysisIfNeeded` guard
//      fires → live inference is blocked (prepared grid protected).
//   3. No cache entry → setBeatGrid(nil) → hasGrid == false → live inference allowed.
//   4. Cache entry with .empty BeatGrid → setBeatGrid(.empty) → hasGrid == false →
//      live inference still allowed (empty prepared grid doesn't block live fallback).
//   5. Track change to uncached track → grid cleared → hasGrid == false → live allowed.

import Foundation
import Testing
@testable import DSP
@testable import Session
@testable import Shared

// MARK: - Fixtures

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

private func makeTrack(_ title: String = "Test Track") -> TrackIdentity {
    TrackIdentity(title: title, artist: "Test Artist")
}

// MARK: - Tests

@Suite("PreparedBeatGrid wiring chain (DSP.3.6)")
struct PreparedBeatGridWiringTests {

    // MARK: 1. Prepared non-empty grid → hasGrid == true

    /// Storing a non-empty BeatGrid in StemCache and loading it via
    /// `loadForPlayback` + `setBeatGrid` (the production `resetStemPipeline`
    /// pattern) must result in `liveDriftTracker.hasGrid == true`.
    @Test("preparedGrid_viaStemCache_hasGrid")
    func test_preparedGrid_viaStemCache_hasGrid() {
        let cache = StemCache()
        let mir = MIRPipeline()
        let track = makeTrack("Love Rehab")
        let grid = makeGrid(bpm: 125.0, beats: 60)

        // Simulate SessionPreparer storing the offline analysis result.
        cache.store(makeCachedData(grid: grid), for: track)

        // Simulate resetStemPipeline(for:) loading and installing.
        if let cached = cache.loadForPlayback(track: track) {
            mir.setBeatGrid(cached.beatGrid)
        } else {
            mir.setBeatGrid(nil)
        }

        #expect(mir.liveDriftTracker.hasGrid,
                "Prepared-cache BeatGrid must be visible to liveDriftTracker after install")
        #expect(mir.liveDriftTracker.currentBPM == 125.0,
                "liveDriftTracker must reflect the cached BPM")
    }

    // MARK: 2. Prepared grid blocks live inference guard

    /// After the prepared BeatGrid is installed, `liveDriftTracker.hasGrid == true`
    /// is the exact guard condition checked by `runLiveBeatAnalysisIfNeeded`:
    ///   `guard !mirPipeline.liveDriftTracker.hasGrid else { … return }`
    /// This test proves that condition holds, meaning live inference is skipped.
    @Test("preparedGrid_guardCondition_blocksLiveInference")
    func test_preparedGrid_guardCondition_blocksLiveInference() {
        let cache = StemCache()
        let mir = MIRPipeline()
        let track = makeTrack("Money")
        let grid = makeGrid(bpm: 123.4, beats: 63)  // Money 7/4 offline reference

        cache.store(makeCachedData(grid: grid), for: track)

        // Reproduce resetStemPipeline installation.
        if let cached = cache.loadForPlayback(track: track) {
            mir.setBeatGrid(cached.beatGrid)
        } else {
            mir.setBeatGrid(nil)
        }

        // This is the exact guard test from runLiveBeatAnalysisIfNeeded.
        // If !hasGrid is false the live path returns early, preserving the prepared grid.
        let liveShouldSkip = mir.liveDriftTracker.hasGrid
        #expect(liveShouldSkip,
                "runLiveBeatAnalysisIfNeeded guard '!hasGrid' must be false — live inference should be skipped when prepared grid is present")
    }

    // MARK: 3. No cache entry → live inference allowed

    /// When StemCache has no entry for a track, `loadForPlayback` returns nil,
    /// `setBeatGrid(nil)` is called, and `hasGrid` remains false.
    /// This is the ad-hoc / reactive-mode path; live Beat This! must be allowed.
    @Test("noCacheEntry_liveInferenceAllowed")
    func test_noCacheEntry_liveInferenceAllowed() {
        let cache = StemCache()        // empty — no tracks stored
        let mir = MIRPipeline()
        let track = makeTrack("Unknown Ad-Hoc Track")

        // Reproduce resetStemPipeline with no cache hit.
        if let cached = cache.loadForPlayback(track: track) {
            mir.setBeatGrid(cached.beatGrid)
        } else {
            mir.setBeatGrid(nil)
        }

        #expect(!mir.liveDriftTracker.hasGrid,
                "No cache entry → setBeatGrid(nil) → hasGrid must be false")
        // Live inference guard (!hasGrid) is true → live path proceeds.
        let liveShouldProceed = !mir.liveDriftTracker.hasGrid
        #expect(liveShouldProceed,
                "Live inference must be permitted when no prepared grid exists")
    }

    // MARK: 4. Empty grid in cache → live inference still allowed

    /// `SessionPreparer` may produce an empty BeatGrid when no beat-grid analyzer
    /// is wired (nil default, backward-compat) or when the track is too short.
    /// An empty cached grid must not block live inference — it is not a usable grid.
    @Test("emptyGridInCache_liveInferenceAllowed")
    func test_emptyGridInCache_liveInferenceAllowed() {
        let cache = StemCache()
        let mir = MIRPipeline()
        let track = makeTrack("Silent Track")

        // SessionPreparer default: beatGrid = .empty when no analyzer is injected.
        cache.store(makeCachedData(grid: .empty), for: track)

        // Reproduce resetStemPipeline — cache hit, but grid is .empty.
        if let cached = cache.loadForPlayback(track: track) {
            mir.setBeatGrid(cached.beatGrid)
        } else {
            mir.setBeatGrid(nil)
        }

        #expect(!mir.liveDriftTracker.hasGrid,
                "Empty cached BeatGrid must not register as hasGrid — live inference fallback must remain available")
    }

    // MARK: 5. Track change resets grid and allows live inference again

    /// When resetStemPipeline is called for a second track that has no cache entry,
    /// any grid from the first track must be cleared. This proves track isolation.
    @Test("trackChange_clearsGrid_allowsLiveInference")
    func test_trackChange_clearsGrid_allowsLiveInference() {
        let cache = StemCache()
        let mir = MIRPipeline()
        let trackA = makeTrack("Track A — prepared")
        let trackB = makeTrack("Track B — ad hoc")

        // Track A: prepared with a real grid.
        cache.store(makeCachedData(grid: makeGrid(bpm: 120.0)), for: trackA)
        if let cached = cache.loadForPlayback(track: trackA) {
            mir.setBeatGrid(cached.beatGrid)
        } else {
            mir.setBeatGrid(nil)
        }
        #expect(mir.liveDriftTracker.hasGrid, "Track A should have a grid after install")

        // Track B: no cache entry — simulates track change to an ad-hoc track.
        if let cached = cache.loadForPlayback(track: trackB) {
            mir.setBeatGrid(cached.beatGrid)
        } else {
            mir.setBeatGrid(nil)
        }
        #expect(!mir.liveDriftTracker.hasGrid,
                "After track change to uncached track, grid must be cleared")
    }
}

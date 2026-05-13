// ProgressiveReadinessTests — 10 tests covering `ProgressiveReadinessLevel` computation
// and `SessionManager.startNow()` behavior.
//
// Tests 1–7 exercise `SessionManager.computeReadiness(statuses:trackList:cache:)` directly
// as a pure static function — no async, no Metal device required.
// Tests 8–10 exercise the full `SessionManager` lifecycle with inline stubs
// (stubs from SessionManagerTests.swift are file-private, so they are re-declared here).

import Combine
import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Shared
@testable import Session

// MARK: - Stubs (file-private, mirrored from SessionManagerTests)

private final class PRConnector: PlaylistConnecting, @unchecked Sendable {
    var tracksToReturn: [TrackIdentity]
    var errorToThrow: Error?
    init(tracks: [TrackIdentity] = []) { self.tracksToReturn = tracks }
    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        if let error = errorToThrow { throw error }
        return tracksToReturn
    }
}

private final class PRFailingConnector: PlaylistConnecting, @unchecked Sendable {
    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        throw PlaylistConnectorError.networkFailure("no connection")
    }
}

private final class PRStemSeparator: StemSeparating, @unchecked Sendable {
    let stemLabels: [String] = ["vocals", "drums", "bass", "other"]
    let stemBuffers: [UMABuffer<Float>]

    init(device: MTLDevice) throws {
        stemBuffers = try (0..<4).map { _ in
            try UMABuffer<Float>(device: device, capacity: 4096)
        }
        for buf in stemBuffers {
            let samples = (0..<4096).map { i in Float(i) * 0.0001 }
            buf.write(samples)
        }
    }

    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        let frame = AudioFrame(sampleRate: sampleRate, sampleCount: 4096, channelCount: 1)
        return StemSeparationResult(
            stemData: StemData(vocals: frame, drums: frame, bass: frame, other: frame),
            sampleCount: 4096
        )
    }
}

private final class PRStemAnalyzer: StemAnalyzing, @unchecked Sendable {
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures {
        StemFeatures(
            vocalsEnergy: 0.3, vocalsBand0: 0.2, vocalsBand1: 0.1, vocalsBeat: 0,
            drumsEnergy: 0.5, drumsBand0: 0.4, drumsBand1: 0.3, drumsBeat: 0.1,
            bassEnergy: 0.4, bassBand0: 0.3, bassBand1: 0.2, bassBeat: 0,
            otherEnergy: 0.2, otherBand0: 0.1, otherBand1: 0.05, otherBeat: 0
        )
    }
    func reset() {}
}

private final class PRResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        URL(string: "https://example.com/\(track.title).m4a")
    }
}

private final class PRDownloader: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        let sampleRate = 44100
        let samples = (0..<sampleRate).map { i in 0.05 * sin(Float(i) * 0.01) }
        return PreviewAudio(trackIdentity: track, pcmSamples: samples, sampleRate: sampleRate, duration: 1.0)
    }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] {
        await withTaskGroup(of: PreviewAudio?.self) { group in
            for (t, u) in tracks { group.addTask { await self.download(track: t, from: u) } }
            var results: [PreviewAudio] = []
            for await r in group { if let r { results.append(r) } }
            return results
        }
    }
}

@MainActor
private func makeSessionManager(
    connector: any PlaylistConnecting,
    device: MTLDevice
) throws -> SessionManager {
    let sep = try PRStemSeparator(device: device)
    let preparer = SessionPreparer(
        resolver: PRResolver(),
        downloader: PRDownloader(),
        stemSeparator: sep,
        stemAnalyzer: PRStemAnalyzer(),
        moodClassifier: MockMoodClassifier()
    )
    return SessionManager(connector: connector, preparer: preparer)
}

@MainActor
private func waitUntilNotPreparing(_ manager: SessionManager) async {
    let deadline = Date().addingTimeInterval(3)
    while manager.state == .preparing && Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

// MARK: - Helpers for static tests

private func makeTrack(_ title: String) -> TrackIdentity {
    TrackIdentity(title: title, artist: "Artist")
}

private func cacheWithProfile(
    for track: TrackIdentity,
    bpm: Float?,
    genreTags: [String]
) -> StemCache {
    let cache = StemCache()
    let profile = TrackProfile(bpm: bpm, genreTags: genreTags)
    let data = CachedTrackData(stemWaveforms: [[], [], [], []], stemFeatures: .zero, trackProfile: profile)
    cache.store(data, for: track)
    return cache
}

// MARK: - Suite

@Suite("ProgressiveReadiness")
@MainActor
struct ProgressiveReadinessTests {

    // MARK: - Static computeReadiness (tests 1–7)

    @Test func thresholdNotMet_twoReady_returns_preparing() {
        let tracks = (0..<5).map { makeTrack("T\($0)") }
        var statuses: [TrackIdentity: TrackPreparationStatus] = [:]
        statuses[tracks[0]] = .ready
        statuses[tracks[1]] = .ready
        // tracks[2...4] are .queued (missing key → defaults to queued in computeReadiness)

        let result = SessionManager.computeReadiness(
            statuses: statuses, trackList: tracks, cache: StemCache()
        )
        #expect(result == .preparing)
    }

    @Test func thresholdMet_below50Pct_returns_readyForFirstTracks() {
        let tracks = (0..<7).map { makeTrack("T\($0)") }
        var statuses: [TrackIdentity: TrackPreparationStatus] = [:]
        // First 3 ready = threshold. Total ready = 3/7 ≈ 43%.
        statuses[tracks[0]] = .ready
        statuses[tracks[1]] = .ready
        statuses[tracks[2]] = .ready

        let result = SessionManager.computeReadiness(
            statuses: statuses, trackList: tracks, cache: StemCache()
        )
        #expect(result == .readyForFirstTracks)
    }

    @Test func failedAtPosition1_breaks_prefix_returns_preparing() {
        let tracks = (0..<5).map { makeTrack("T\($0)") }
        let statuses: [TrackIdentity: TrackPreparationStatus] = [
            tracks[0]: .ready,
            tracks[1]: .failed(reason: "no preview"),
            tracks[2]: .ready,
            // tracks[3] and [4] remain .queued (non-terminal) so allTerminal=false,
            // which means the prefix guard applies.
        ]
        // prefix = 1 (fails at index 1) < threshold(3); not all terminal.
        let result = SessionManager.computeReadiness(
            statuses: statuses, trackList: tracks, cache: StemCache()
        )
        #expect(result == .preparing)
    }

    @Test func partial_withBPMAndGenre_countsForPrefix() {
        let tracks = (0..<5).map { makeTrack("T\($0)") }
        // index 1 is .partial with metadata → counts for prefix.
        let cache = cacheWithProfile(for: tracks[1], bpm: 120.0, genreTags: ["electronic"])
        let statuses: [TrackIdentity: TrackPreparationStatus] = [
            tracks[0]: .ready,
            tracks[1]: .partial(reason: "stem failure"),
            tracks[2]: .ready,
            tracks[3]: .queued,
            tracks[4]: .queued,
        ]
        // prefix = 3 ≥ threshold; readyCount = 3 (ready+partial); 3/5 = 60% ≥ 50%.
        // allTerminal = false (tracks[3,4] are queued).
        let result = SessionManager.computeReadiness(
            statuses: statuses, trackList: tracks, cache: cache
        )
        #expect(result == .partiallyPlanned)
    }

    @Test func partial_withoutMetadata_blocks_prefix() {
        let tracks = (0..<5).map { makeTrack("T\($0)") }
        // index 1 is .partial but has NO metadata in cache → blocks prefix.
        // tracks[3] and [4] are .queued so allTerminal=false and prefix guard applies.
        let statuses: [TrackIdentity: TrackPreparationStatus] = [
            tracks[0]: .ready,
            tracks[1]: .partial(reason: "stem failure"),
            tracks[2]: .ready,
            // tracks[3], tracks[4] not in statuses → default .queued
        ]
        let result = SessionManager.computeReadiness(
            statuses: statuses, trackList: tracks, cache: StemCache()
        )
        // prefix = 1 (breaks at .partial with no metadata) < threshold(3).
        #expect(result == .preparing)
    }

    @Test func fiftyPctOrMore_notAllTerminal_returns_partiallyPlanned() {
        let tracks = (0..<4).map { makeTrack("T\($0)") }
        let statuses: [TrackIdentity: TrackPreparationStatus] = [
            tracks[0]: .ready,
            tracks[1]: .ready,
            tracks[2]: .ready,
            tracks[3]: .queued,
        ]
        // 3/4 = 75% ≥ 50%, not all terminal.
        let result = SessionManager.computeReadiness(
            statuses: statuses, trackList: tracks, cache: StemCache()
        )
        #expect(result == .partiallyPlanned)
    }

    @Test func allReady_allTerminal_returns_fullyPrepared() {
        let tracks = (0..<3).map { makeTrack("T\($0)") }
        let statuses: [TrackIdentity: TrackPreparationStatus] = [
            tracks[0]: .ready,
            tracks[1]: .ready,
            tracks[2]: .ready,
        ]
        let result = SessionManager.computeReadiness(
            statuses: statuses, trackList: tracks, cache: StemCache()
        )
        #expect(result == .fullyPrepared)
    }

    // MARK: - SessionManager Lifecycle Tests (tests 8–10)

    @Test func connectionFailure_progressiveReadiness_is_reactiveFallback() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let manager = try makeSessionManager(connector: PRFailingConnector(), device: device)

        await manager.startSession(source: .appleMusicCurrentPlaylist)

        #expect(manager.state == .ready)
        #expect(manager.progressiveReadinessLevel == .reactiveFallback)
    }

    @Test func startNow_belowThreshold_isNoOp() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        // Single track — threshold is 3, so readiness won't reach .readyForFirstTracks.
        let connector = PRConnector(tracks: [TrackIdentity(title: "Solo", artist: "A")])
        let manager = try makeSessionManager(connector: connector, device: device)

        await manager.startSession(source: .appleMusicCurrentPlaylist)

        // If still preparing (task running), readiness should be < readyForFirstTracks (only 1 track).
        if manager.state == .preparing {
            // Level should be .preparing — calling startNow must be a no-op.
            #expect(manager.progressiveReadinessLevel < .readyForFirstTracks)
            manager.startNow()
            #expect(manager.state == .preparing)
        }
        // Regardless, let natural completion finish cleanly.
        await waitUntilNotPreparing(manager)
        #expect(manager.state == .ready)
    }

    @Test func startNow_atThreshold_transitions_to_ready() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        // Five tracks — enough to satisfy the ≥3 threshold.
        let tracks = (0..<5).map { TrackIdentity(title: "Track \($0)", artist: "Art") }
        let connector = PRConnector(tracks: tracks)
        let manager = try makeSessionManager(connector: connector, device: device)

        var states: [SessionState] = []
        let cancellable = manager.$state.sink { states.append($0) }
        defer { cancellable.cancel() }

        await manager.startSession(source: .appleMusicCurrentPlaylist)

        // Either startNow() wins the race or natural completion does.
        if manager.state == .preparing && manager.progressiveReadinessLevel >= .readyForFirstTracks {
            manager.startNow()
            #expect(manager.state == .ready)
        } else {
            await waitUntilNotPreparing(manager)
            #expect(manager.state == .ready)
        }
    }
}

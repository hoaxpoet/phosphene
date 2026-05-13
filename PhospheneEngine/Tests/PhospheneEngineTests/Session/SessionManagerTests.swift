// SessionManagerTests — 10 tests covering the session lifecycle state machine,
// degradation behavior, and cache-aware track-change behavior.
// All external dependencies are injected via protocol stubs.

import Combine
import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Shared
@testable import Session

// MARK: - Stubs

/// Playlist connector stub: returns a configurable list or throws.
private final class StubConnector: PlaylistConnecting, @unchecked Sendable {
    var tracksToReturn: [TrackIdentity] = [
        TrackIdentity(title: "Track A", artist: "Artist A"),
        TrackIdentity(title: "Track B", artist: "Artist B"),
    ]
    var errorToThrow: Error?

    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        if let error = errorToThrow { throw error }
        return tracksToReturn
    }
}

/// Playlist connector stub that always throws a connection error.
private final class FailingConnector: PlaylistConnecting, @unchecked Sendable {
    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        throw PlaylistConnectorError.networkFailure("no connection")
    }
}

/// Stem separator stub: fills buffers with a small signal and returns quickly.
private final class InstantStemSeparator: StemSeparating, @unchecked Sendable {
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

/// Stem analyzer stub: returns fixed non-zero StemFeatures instantly.
private final class InstantStemAnalyzer: StemAnalyzing, @unchecked Sendable {
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

/// Preview resolver stub: returns a stable preview URL for any track.
private final class InstantResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        URL(string: "https://example.com/\(track.title).m4a")
    }
}

/// Preview resolver stub: always returns nil (no preview available).
private final class NoPreviewResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? { nil }
}

/// Preview downloader stub: returns synthetic 1-second PCM for every request.
private final class InstantDownloader: PreviewDownloading, @unchecked Sendable {
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

// MARK: - Helpers

@MainActor
private func makeManager(
    connector: any PlaylistConnecting = StubConnector(),
    resolver: any PreviewResolving = InstantResolver(),
    downloader: any PreviewDownloading = InstantDownloader(),
    separator: any StemSeparating,
    analyzer: any StemAnalyzing = InstantStemAnalyzer(),
    classifier: any MoodClassifying = MockMoodClassifier()
) -> SessionManager {
    let preparer = SessionPreparer(
        resolver: resolver,
        downloader: downloader,
        stemSeparator: separator,
        stemAnalyzer: analyzer,
        moodClassifier: classifier
    )
    return SessionManager(connector: connector, preparer: preparer)
}

/// Poll until the manager leaves `.preparing` (or 3 seconds elapse).
///
/// Required because `startSession()` now returns while still in `.preparing` — the
/// background preparation Task completes asynchronously on the main actor.
@MainActor
private func waitForReady(_ manager: SessionManager) async {
    let deadline = Date().addingTimeInterval(3)
    while manager.state == .preparing && Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

// MARK: - Suite

@Suite("SessionManager")
@MainActor
struct SessionManagerTests {

    // MARK: - Initial State

    @Test func init_stateIsIdle() throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let sep = try InstantStemSeparator(device: device)
        let manager = makeManager(separator: sep)
        #expect(manager.state == .idle)
        #expect(manager.currentPlan == nil)
    }

    // MARK: - State Transitions

    @Test func startSession_transitionsToConnecting() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let sep = try InstantStemSeparator(device: device)
        let manager = makeManager(separator: sep)

        // Observe all state transitions via the @Published publisher.
        var observedStates: [SessionState] = []
        let cancellable = manager.$state.sink { observedStates.append($0) }
        defer { cancellable.cancel() }

        await manager.startSession(source: .appleMusicCurrentPlaylist)

        #expect(observedStates.contains(.connecting), "Expected .connecting in \(observedStates)")
    }

    @Test func afterPlaylistRead_transitionsToPreparing() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let sep = try InstantStemSeparator(device: device)
        let manager = makeManager(separator: sep)

        var observedStates: [SessionState] = []
        let cancellable = manager.$state.sink { observedStates.append($0) }
        defer { cancellable.cancel() }

        await manager.startSession(source: .appleMusicCurrentPlaylist)

        // The sequence must pass through .preparing after .connecting.
        #expect(observedStates.contains(.preparing), "Expected .preparing in \(observedStates)")
        let connectingIdx = observedStates.firstIndex(of: .connecting) ?? -1
        let preparingIdx  = observedStates.firstIndex(of: .preparing)  ?? -1
        #expect(connectingIdx < preparingIdx, ".connecting must precede .preparing")
    }

    @Test func afterPreparation_transitionsToReady() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let sep = try InstantStemSeparator(device: device)
        let manager = makeManager(separator: sep)

        await manager.startSession(source: .appleMusicCurrentPlaylist)
        await waitForReady(manager)

        #expect(manager.state == .ready)
        #expect(manager.currentPlan != nil)
    }

    @Test func playbackStarts_transitionsToPlaying() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let sep = try InstantStemSeparator(device: device)
        let manager = makeManager(separator: sep)

        await manager.startSession(source: .appleMusicCurrentPlaylist)
        await waitForReady(manager)
        #expect(manager.state == .ready)

        manager.beginPlayback()
        #expect(manager.state == .playing)
    }

    @Test func sessionEnds_transitionsToEnded() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let sep = try InstantStemSeparator(device: device)
        let manager = makeManager(separator: sep)

        await manager.startSession(source: .appleMusicCurrentPlaylist)
        await waitForReady(manager)
        manager.beginPlayback()
        manager.endSession()

        #expect(manager.state == .ended)
    }

    // MARK: - Degradation

    @Test func preparationFailure_transitionsToReady_withPartialData() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let sep = try InstantStemSeparator(device: device)

        // Two tracks, no previews → both fail individually; session still reaches .ready.
        let manager = makeManager(
            connector: StubConnector(),
            resolver: NoPreviewResolver(),
            separator: sep
        )

        await manager.startSession(source: .appleMusicCurrentPlaylist)
        await waitForReady(manager)

        #expect(manager.state == .ready)
        // Plan exists but cache is empty (all tracks failed to pre-analyze).
        #expect(manager.currentPlan != nil)
        #expect(manager.cache.count == 0)
    }

    @Test func adHocMode_skipsPreparation() throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let sep = try InstantStemSeparator(device: device)
        let manager = makeManager(separator: sep)

        manager.startAdHocSession()

        // Jumps directly to .playing — no connecting or preparing phase.
        #expect(manager.state == .playing)
        #expect(manager.currentPlan == nil)
    }

    @Test func connectionFailure_transitionsToReady_withEmptyPlan() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let sep = try InstantStemSeparator(device: device)
        let manager = makeManager(connector: FailingConnector(), separator: sep)

        await manager.startSession(source: .appleMusicCurrentPlaylist)

        // Connection failed → ready with empty plan; engine falls back to reactive mode.
        #expect(manager.state == .ready)
        #expect(manager.currentPlan?.tracks.isEmpty == true)
    }

    // MARK: - Cache-Aware Track Change

    @Test func trackChange_loadsFromCache() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let sep = try InstantStemSeparator(device: device)
        let connector = StubConnector()
        let manager = makeManager(connector: connector, separator: sep)

        await manager.startSession(source: .appleMusicCurrentPlaylist)
        await waitForReady(manager)
        #expect(manager.state == .ready)

        // Every track in the playlist should be cached after preparation.
        for track in connector.tracksToReturn {
            let hit = manager.cache.loadForPlayback(track: track)
            #expect(hit != nil, "Expected cache hit for '\(track.title)' after session preparation")
            if let hit {
                // Pre-separated stems should carry non-trivial energy values.
                #expect(hit.stemFeatures.vocalsEnergy > 0 || hit.stemFeatures.drumsEnergy > 0)
            }
        }
    }

    @Test func trackChange_cacheMiss_fallsBackToRealTime() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let sep = try InstantStemSeparator(device: device)
        let manager = makeManager(separator: sep)

        await manager.startSession(source: .appleMusicCurrentPlaylist)
        await waitForReady(manager)
        #expect(manager.state == .ready)

        // A track not in the playlist produces a cache miss; the engine falls back
        // to real-time stem separation (the existing ~10-second cadence).
        let unknownTrack = TrackIdentity(title: "Unknown Song", artist: "Unknown Artist")
        let miss = manager.cache.loadForPlayback(track: unknownTrack)
        #expect(miss == nil, "Expected cache miss for an unprepared track")
    }
}

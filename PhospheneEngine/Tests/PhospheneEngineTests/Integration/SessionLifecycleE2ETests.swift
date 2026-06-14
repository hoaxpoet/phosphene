// SessionLifecycleE2ETests — CLEAN.1.7 / GAP-8.
//
// End-to-end integration test that drives a real `SessionManager` + real
// `SessionPreparer` (with fast fakes for the network/ML edges) through the full
// session lifecycle: connect → prepare → ready → play → track-change → end →
// restart. Before this, only per-VM unit tests and beat-grid wiring tests
// existed — nothing exercised the whole cycle, which is exactly the path the
// BUG-032 orphan-hijack class lives on. The restart-with-a-different-playlist
// leg structurally catches that class: a prep task orphaned by `endSession()`
// must not survive into the next session's plan.
//
// Fast fakes (no GPU / no network) — this validates lifecycle wiring + state
// transitions, not analysis quality (that is SessionPreparationIntegrationTests).

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Shared
@testable import Session

// MARK: - Fakes

/// Hands out a different track list per `connect()` so a restart is a genuinely
/// different playlist.
private final class E2EConnector: PlaylistConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var callIndex = 0
    private let lists: [[TrackIdentity]]
    init(_ lists: [[TrackIdentity]]) { self.lists = lists }
    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        lock.withLock {
            let list = lists[min(callIndex, lists.count - 1)]
            callIndex += 1
            return list
        }
    }
}

private final class E2EResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        URL(string: "https://example.com/\(track.title).m4a")
    }
}

private final class E2EDownloader: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        let samples = (0..<44_100).map { i in 0.05 * sin(Float(i) * 0.01) }
        return PreviewAudio(trackIdentity: track, pcmSamples: samples, sampleRate: 44_100, duration: 1.0)
    }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}

private final class E2ESeparator: StemSeparating, @unchecked Sendable {
    let stemLabels = ["vocals", "drums", "bass", "other"]
    let stemBuffers: [UMABuffer<Float>]
    init(device: MTLDevice) throws {
        stemBuffers = try (0..<4).map { _ in try UMABuffer<Float>(device: device, capacity: 4096) }
        for buf in stemBuffers { buf.write([Float](repeating: 0.1, count: 4096)) }
    }
    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        let frame = AudioFrame(sampleRate: sampleRate, sampleCount: 4096, channelCount: 1)
        return StemSeparationResult(
            stemData: StemData(vocals: frame, drums: frame, bass: frame, other: frame),
            sampleCount: 4096,
            stemWaveforms: stemBuffers.map { Array($0.pointer.prefix(4096)) }
        )
    }
}

private final class E2EAnalyzer: StemAnalyzing, @unchecked Sendable {
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures { .zero }
    func reset() {}
}

@MainActor
private func makeE2EManager(connector: any PlaylistConnecting, device: MTLDevice) throws -> SessionManager {
    let preparer = SessionPreparer(
        resolver: E2EResolver(),
        downloader: E2EDownloader(),
        stemSeparator: try E2ESeparator(device: device),
        stemAnalyzer: E2EAnalyzer(),
        moodClassifier: MockMoodClassifier()
    )
    return SessionManager(connector: connector, preparer: preparer)
}

@MainActor
private func waitUntil(timeoutSeconds: Double = 20, _ predicate: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while !predicate() && Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

// MARK: - Suite

@Suite("Session lifecycle E2E (CLEAN.1.7 / GAP-8)", .serialized)
@MainActor
struct SessionLifecycleE2ETests {

    @Test func fullCycle_connect_prepare_ready_play_trackChange_end_restart() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")

        let a1 = TrackIdentity(title: "A1", artist: "Artist")
        let a2 = TrackIdentity(title: "A2", artist: "Artist")
        let b1 = TrackIdentity(title: "B1", artist: "Artist")
        let manager = try makeE2EManager(connector: E2EConnector([[a1, a2], [b1]]), device: device)

        // 1. CONNECT — the full playlist plan is installed immediately.
        #expect(manager.state == .idle)
        await manager.startSession(source: .appleMusicCurrentPlaylist)
        #expect(manager.currentPlan?.tracks.count == 2, "connect installed session A's plan")

        // 2–3. PREPARE → READY (background prep completes; fast fakes).
        await waitUntil { manager.state == .ready }
        #expect(manager.state == .ready, "preparation completed")
        #expect(manager.cache.loadForPlayback(track: a1) != nil, "A1 prepared + cached")

        // 4. PLAY.
        manager.beginPlayback()
        #expect(manager.state == .playing)

        // 5. TRACK-CHANGE — the engine reads the next track's prepared data from
        //    the cache on a track boundary. That data must be present + complete.
        let nextTrack = manager.cache.loadForPlayback(track: a2)
        #expect(nextTrack != nil, "A2's prepared data available on track change")
        #expect(nextTrack?.stemWaveforms.count == 4, "A2 carries four stem waveforms by value")

        // 6. END — must not leave an orphaned prep task behind.
        manager.endSession()
        #expect(manager.state == .ended)

        // 7. RESTART with a DIFFERENT playlist. The orphan class (BUG-032) would
        //    have A's stale prep overwrite B's plan/state; the generation guard
        //    prevents it.
        await manager.startSession(source: .appleMusicPlaylistURL("B"))
        await waitUntil { manager.state == .ready }
        #expect(manager.state == .ready, "session B reached ready")
        #expect(manager.currentPlan?.tracks.count == 1, "restart installed session B's plan")
        #expect(
            Set((manager.currentPlan?.tracks ?? []).map(\.title)) == ["B1"],
            "no orphaned session-A prep overwrote session B's plan"
        )
        #expect(manager.cache.loadForPlayback(track: b1) != nil, "B1 prepared + cached")

        manager.endSession()
        #expect(manager.state == .ended)
    }

    /// Cancel mid-prepare returns to .idle and a fresh start still works — the
    /// other terminal path through the lifecycle (cancel vs end).
    @Test func cancelMidPrepare_thenRestart_isClean() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let a1 = TrackIdentity(title: "C1", artist: "Artist")
        let b1 = TrackIdentity(title: "D1", artist: "Artist")
        let manager = try makeE2EManager(connector: E2EConnector([[a1], [b1]]), device: device)

        await manager.startSession(source: .appleMusicCurrentPlaylist)
        manager.cancel()
        #expect(manager.state == .idle, "cancel returns to idle")

        await manager.startSession(source: .appleMusicPlaylistURL("D"))
        await waitUntil { manager.state == .ready }
        #expect(manager.state == .ready)
        #expect(Set((manager.currentPlan?.tracks ?? []).map(\.title)) == ["D1"])

        manager.endSession()
    }
}

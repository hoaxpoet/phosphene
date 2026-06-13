// SessionLifecycleGenerationTests — CLEAN.1.3 / BUG-032 regression coverage.
//
// Three lifecycle defects, one streaming-path root cause (no session-generation
// guard, the LF path had `localFileSessionGen`):
//   1. A prep task orphaned by endSession() must not mutate the next session's
//      plan/state  → streaming-generation guard + endSession cancels the task.
//   2. Recovery during active prep must not spawn a second `_runPreparation`
//      loop over the shared StemSeparator → single-flight (await the in-flight loop).
//   3. A rejected startSession must not rewrite the published source → source
//      mutation moved after the state guard.
//
// #1/#3 assert instance-local published state (parallel-safe → swift-testing).
// #2 asserts the process-global `ConcurrencyAuditProbe` single-flight counter, so
// it runs as XCTest (serial phase) with a reset — the same isolation rationale as
// BUG012ConcurrencyTest / ConcurrencyAuditProbeTests.

import Combine
import Testing
import XCTest
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Shared
@testable import Session

// MARK: - Shared test doubles

/// Connector that hands out a different track list on each `connect()` so a
/// second `startSession` represents a genuinely different playlist.
private final class SwitchingConnector: PlaylistConnecting, @unchecked Sendable {
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

private final class FixedConnector: PlaylistConnecting, @unchecked Sendable {
    let tracks: [TrackIdentity]
    init(_ tracks: [TrackIdentity]) { self.tracks = tracks }
    func connect(source: PlaylistSource) async throws -> [TrackIdentity] { tracks }
}

/// Resolver that sleeps before returning a URL — keeps preparation in `.preparing`.
private final class GenBlockingResolver: PreviewResolving, @unchecked Sendable {
    let delayNs: UInt64
    init(delayMs: UInt64 = 600) { self.delayNs = delayMs * 1_000_000 }
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        try await Task.sleep(nanoseconds: delayNs)
        return URL(string: "https://example.com/\(track.title).m4a")
    }
}

private final class GenInstantResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        URL(string: "https://example.com/\(track.title).m4a")
    }
}

/// Returns nil for the named titles (→ network-class `.failed`), a URL otherwise.
private final class GenNilForTitleResolver: PreviewResolving, @unchecked Sendable {
    let nilTitles: Set<String>
    init(nilTitles: Set<String>) { self.nilTitles = nilTitles }
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        nilTitles.contains(track.title) ? nil : URL(string: "https://example.com/\(track.title).m4a")
    }
}

private final class GenInstantDownloader: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        let samples = (0..<44_100).map { i in 0.05 * sin(Float(i) * 0.01) }
        return PreviewAudio(trackIdentity: track, pcmSamples: samples, sampleRate: 44_100, duration: 1.0)
    }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}

/// Sleeps per download — keeps the original prep loop in flight long enough for a
/// recovery call to overlap it (pre-fix).
private final class GenSlowDownloader: PreviewDownloading, @unchecked Sendable {
    let delayNs: UInt64
    init(delayMs: UInt64 = 300) { self.delayNs = delayMs * 1_000_000 }
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        try? await Task.sleep(nanoseconds: delayNs)
        let samples = (0..<44_100).map { i in 0.05 * sin(Float(i) * 0.01) }
        return PreviewAudio(trackIdentity: track, pcmSamples: samples, sampleRate: 44_100, duration: 1.0)
    }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}

private final class GenSeparator: StemSeparating, @unchecked Sendable {
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

private final class GenAnalyzer: StemAnalyzing, @unchecked Sendable {
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures { .zero }
    func reset() {}
}

@MainActor
private func makeGenManager(
    connector: any PlaylistConnecting,
    resolver: any PreviewResolving,
    downloader: any PreviewDownloading,
    separator: any StemSeparating
) -> SessionManager {
    let preparer = SessionPreparer(
        resolver: resolver,
        downloader: downloader,
        stemSeparator: separator,
        stemAnalyzer: GenAnalyzer(),
        moodClassifier: MockMoodClassifier()
    )
    return SessionManager(connector: connector, preparer: preparer)
}

@MainActor
private func waitUntil(
    timeoutSeconds: Double = 10,
    _ predicate: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while !predicate() && Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

// MARK: - #1 + #3: generation guard + source ordering (swift-testing)

@Suite("SessionManager streaming-generation guard (CLEAN.1.3 / BUG-032)")
@MainActor
struct SessionLifecycleGenerationTests {

    /// #1: end a streaming session mid-preparation, immediately start a new one
    /// with a different playlist — the orphaned prep must NOT overwrite the new
    /// session's plan/state.
    @Test func endThenRestart_staleOrphanDoesNotMutateNewSession() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let tracksA = [
            TrackIdentity(title: "A1", artist: "Artist"),
            TrackIdentity(title: "A2", artist: "Artist"),
            TrackIdentity(title: "A3", artist: "Artist"),
        ]
        let tracksB = [
            TrackIdentity(title: "B1", artist: "Artist"),
            TrackIdentity(title: "B2", artist: "Artist"),
        ]
        let manager = makeGenManager(
            connector: SwitchingConnector([tracksA, tracksB]),
            resolver: GenBlockingResolver(delayMs: 600),   // keeps prep in flight
            downloader: GenInstantDownloader(),
            separator: try GenSeparator(device: device)
        )

        // Session A: start and let it reach .preparing (prep in flight on A1).
        let taskA = Task { @MainActor in await manager.startSession(source: .appleMusicCurrentPlaylist) }
        await waitUntil { manager.state == .preparing }
        #expect(manager.state == .preparing)
        #expect(manager.currentPlan?.tracks.count == 3, "session A plan has 3 tracks")

        // End A mid-preparation, then immediately start B with a different playlist.
        manager.endSession()
        #expect(manager.state == .ended)
        await taskA.value

        let taskB = Task { @MainActor in await manager.startSession(source: .appleMusicPlaylistURL("B")) }
        await waitUntil { manager.currentPlan?.tracks.count == 2 }
        #expect(manager.currentPlan?.tracks.count == 2, "session B plan installed (2 tracks)")

        // Wait well past session A's full slow-prep duration (3 × 600 ms): a
        // pre-fix orphan would fire here and overwrite the plan back to A's 3.
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        let titles = Set((manager.currentPlan?.tracks ?? []).map(\.title))
        #expect(manager.currentPlan?.tracks.count == 2, "orphaned A prep must not overwrite B's plan")
        #expect(titles == ["B1", "B2"], "plan must be session B's tracks, got \(titles)")
        #expect(manager.state != .idle, "stale orphan must not have cancelled/reset the new session")

        manager.endSession()
        await taskB.value
    }

    /// #3: a startSession rejected by the state guard (session already active —
    /// here `.preparing`, which the guard also rejects) must not rewrite the
    /// published source. Tested from `.preparing` (reached promptly) rather than
    /// `.playing` to avoid depending on full prep completion under suite load.
    @Test func rejectedStartSession_leavesPublishedSourceUntouched() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let manager = makeGenManager(
            connector: FixedConnector([
                TrackIdentity(title: "T1", artist: "Artist"),
                TrackIdentity(title: "T2", artist: "Artist"),
            ]),
            resolver: GenBlockingResolver(delayMs: 600),   // holds the session in .preparing
            downloader: GenInstantDownloader(),
            separator: try GenSeparator(device: device)
        )

        let task = Task { @MainActor in await manager.startSession(source: .appleMusicCurrentPlaylist) }
        await waitUntil { manager.state == .preparing }
        #expect(manager.state == .preparing)

        let sourceBefore = manager.currentSource

        // Rejected (state == .preparing) — must be a no-op for state AND source.
        await manager.startSession(source: .appleMusicPlaylistURL("rejected"))

        #expect(manager.state == .preparing, "rejected startSession must not change state")
        #expect(manager.currentSource == sourceBefore, "rejected startSession must not rewrite currentSource")

        manager.endSession()
        await task.value
    }
}

// MARK: - #2: recovery single-flight (XCTest — serial phase for the global probe)

final class SessionRecoverySingleFlightTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ConcurrencyAuditProbe.resetForTesting()
    }
    override func tearDown() {
        ConcurrencyAuditProbe.resetForTesting()
        super.tearDown()
    }

    /// Triggering network recovery while the original preparation loop is still
    /// running must NOT start a second `_runPreparation` loop over the shared
    /// StemSeparator. The probe's max in-flight stays 1 (single-flight).
    @MainActor
    func test_recoveryDuringActivePrep_isSingleFlight() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let fail = TrackIdentity(title: "FAIL", artist: "Artist")
        let good1 = TrackIdentity(title: "GOOD1", artist: "Artist")
        let good2 = TrackIdentity(title: "GOOD2", artist: "Artist")

        let preparer = SessionPreparer(
            resolver: GenNilForTitleResolver(nilTitles: ["FAIL"]),  // FAIL → network-failed
            downloader: GenSlowDownloader(delayMs: 300),            // keeps the loop in flight
            stemSeparator: try GenSeparator(device: device),
            stemAnalyzer: GenAnalyzer(),
            moodClassifier: MockMoodClassifier()
        )

        // Start the original preparation loop (FAIL fails fast; GOOD1/2 are slow).
        let prepTask = Task { @MainActor in await preparer.prepare(tracks: [fail, good1, good2]) }

        // Wait until FAIL has network-failed but the loop is still working GOOD1/2.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if case .failed = preparer.trackStatuses[fail] { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        if case .failed = preparer.trackStatuses[fail] {} else {
            XCTFail("FAIL track never reached .failed")
        }

        // Recovery while the original loop is still in flight.
        await preparer.resumeFailedNetworkTracks()
        _ = await prepTask.value

        let snap = ConcurrencyAuditProbe.snapshot()
        XCTAssertEqual(
            snap.maxRunPreparationInFlight, 1,
            "recovery must not overlap the original loop (two _runPreparation over one StemSeparator)"
        )
        XCTAssertEqual(snap.concurrentRunPreparationCount, 0, "no concurrent _runPreparation events expected")
    }
}

// SessionManagerLocalFileTests — LF.4 single-file + LF.5 multi-file
// lifecycle for SessionManager.
//
// Exercises `startLocalFile(at:)` and `startLocalFiles(at:origin:)` and their
// interaction with the existing state machine (idle/preparing/ready/playing
// transitions, replace-on-open, progressive-readiness short-circuit,
// no-preparer degradation, mid-queue cancellation, per-origin source
// discrimination).
//
// External ML deps are injected via a `LocalFilePreparing` stub so these
// tests stay engine-only and don't need Metal weights / real audio.

import Combine
import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Shared
@testable import Session

// MARK: - Stub Preparer

/// `LocalFilePreparing` stub that returns a canned `LocalFilePrepResult`
/// after a configurable async hop, or `nil` to exercise the no-cache
/// fallthrough.
private final class StubLocalFilePreparer: LocalFilePreparing, @unchecked Sendable {

    let resultToReturn: LocalFilePrepResult?
    let preparationDelayMs: UInt64
    private(set) var callCount = 0
    private(set) var lastURL: URL?

    init(result: LocalFilePrepResult?, preparationDelayMs: UInt64 = 0) {
        self.resultToReturn = result
        self.preparationDelayMs = preparationDelayMs
    }

    func prepareLocalFile(url: URL) async -> LocalFilePrepResult? {
        callCount += 1
        lastURL = url
        if preparationDelayMs > 0 {
            try? await Task.sleep(nanoseconds: preparationDelayMs * 1_000_000)
        }
        return resultToReturn
    }
}

/// Stub that mirrors the production VisualizerEngine.prepareLocalFile shape —
/// wraps the per-file work in `Task.detached(...).value`. Detached tasks
/// don't inherit parent-task cancellation, so the delegate's per-file sleep
/// completes its full duration even after the outer prep task is cancelled.
/// Used by LF.5.fix.3-A's regression test to deterministically sequence A's
/// .SLF resume AFTER B's `.ready` transition (so the test can prove A's
/// continuation does NOT overwrite B's state).
private final class UninterruptibleDelayLocalFilePreparer: LocalFilePreparing, @unchecked Sendable {

    let result: LocalFilePrepResult?
    let delayMs: UInt64
    private(set) var callCount = 0

    init(result: LocalFilePrepResult?, delayMs: UInt64) {
        self.result = result
        self.delayMs = delayMs
    }

    func prepareLocalFile(url: URL) async -> LocalFilePrepResult? {
        callCount += 1
        let delayMs = self.delayMs
        let result = self.result
        return await Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            return result
        }.value
    }
}

/// Multi-URL variant of `StubLocalFilePreparer`: returns a different canned
/// result per URL keyed by `url.lastPathComponent`. Falls back to `nil` for
/// unknown URLs (exercises the LF.1 no-cache fallthrough per-track). Records
/// `callOrder` so multi-file tests can assert sequential delegation.
private final class MultiStubLocalFilePreparer: LocalFilePreparing, @unchecked Sendable {

    let resultsByFilename: [String: LocalFilePrepResult]
    let preparationDelayMs: UInt64
    private(set) var callCount = 0
    private(set) var callOrder: [URL] = []

    init(results: [String: LocalFilePrepResult], preparationDelayMs: UInt64 = 0) {
        self.resultsByFilename = results
        self.preparationDelayMs = preparationDelayMs
    }

    func prepareLocalFile(url: URL) async -> LocalFilePrepResult? {
        callCount += 1
        callOrder.append(url)
        if preparationDelayMs > 0 {
            try? await Task.sleep(nanoseconds: preparationDelayMs * 1_000_000)
        }
        return resultsByFilename[url.lastPathComponent]
    }
}

// MARK: - Helpers

@MainActor
private func makeLFManager() throws -> SessionManager {
    let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
    let stemSeparator = try InstantStemSeparatorLF(device: device)
    let preparer = SessionPreparer(
        resolver: InstantResolverLF(),
        downloader: InstantDownloaderLF(),
        stemSeparator: stemSeparator,
        stemAnalyzer: InstantStemAnalyzerLF(),
        moodClassifier: MockMoodClassifier()
    )
    return SessionManager(connector: StubConnectorLF(), preparer: preparer)
}

/// Synthesise a `LocalFilePrepResult` with the LF.3 `local:sha256:` identity form.
private func makeStubPrepResult(
    url: URL,
    hash: String = "deadbeefcafebabe0000000000000000000000000000000000000000000000ff",
    source: LocalFilePrepResult.Source = .freshAnalysis
) -> LocalFilePrepResult {
    let identity = TrackIdentity(
        title: url.lastPathComponent,
        artist: "local file",
        duration: 12.5,
        spotifyID: "local:sha256:" + hash
    )
    let cached = CachedTrackData(
        stemWaveforms: [
            [Float](repeating: 0.01, count: 4096),
            [Float](repeating: 0.02, count: 4096),
            [Float](repeating: 0.03, count: 4096),
            [Float](repeating: 0.04, count: 4096)
        ],
        stemFeatures: StemFeatures(
            vocalsEnergy: 0.3, vocalsBand0: 0.2, vocalsBand1: 0.1, vocalsBeat: 0,
            drumsEnergy: 0.5, drumsBand0: 0.4, drumsBand1: 0.3, drumsBeat: 0.1,
            bassEnergy: 0.4, bassBand0: 0.3, bassBand1: 0.2, bassBeat: 0,
            otherEnergy: 0.2, otherBand0: 0.1, otherBand1: 0.05, otherBeat: 0
        ),
        trackProfile: TrackProfile(),
        beatGrid: .empty,
        drumsBeatGrid: .empty,
        gridOnsetOffsetMs: 0
    )
    return LocalFilePrepResult(
        identity: identity,
        cached: cached,
        decodedDuration: 12.5,
        source: source
    )
}

// MARK: - Stubs (LF-suite-private copies; kept private to avoid clashing
// with the existing SessionManagerTests fixtures that already live in the
// same test target's parent suite.)

private final class StubConnectorLF: PlaylistConnecting, @unchecked Sendable {
    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        [TrackIdentity(title: "T", artist: "A")]
    }
}

private final class InstantResolverLF: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        URL(string: "https://example.com/\(track.title).m4a")
    }
}

private final class InstantDownloaderLF: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        PreviewAudio(
            trackIdentity: track,
            pcmSamples: [Float](repeating: 0, count: 44100),
            sampleRate: 44100,
            duration: 1.0
        )
    }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}

private final class InstantStemSeparatorLF: StemSeparating, @unchecked Sendable {
    let stemLabels: [String] = ["vocals", "drums", "bass", "other"]
    let stemBuffers: [UMABuffer<Float>]

    init(device: MTLDevice) throws {
        stemBuffers = try (0..<4).map { _ in
            try UMABuffer<Float>(device: device, capacity: 1024)
        }
    }

    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        let frame = AudioFrame(sampleRate: sampleRate, sampleCount: 1024, channelCount: 1)
        return StemSeparationResult(
            stemData: StemData(vocals: frame, drums: frame, bass: frame, other: frame),
            sampleCount: 1024
        )
    }
}

private final class InstantStemAnalyzerLF: StemAnalyzing, @unchecked Sendable {
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures {
        StemFeatures(
            vocalsEnergy: 0.1, vocalsBand0: 0, vocalsBand1: 0, vocalsBeat: 0,
            drumsEnergy: 0.1, drumsBand0: 0, drumsBand1: 0, drumsBeat: 0,
            bassEnergy: 0.1, bassBand0: 0, bassBand1: 0, bassBeat: 0,
            otherEnergy: 0.1, otherBand0: 0, otherBand1: 0, otherBeat: 0
        )
    }
    func reset() {}
}

// MARK: - Suite

@Suite("SessionManager + local file (LF.4)")
@MainActor
struct SessionManagerLocalFileTests {

    private var fileURL: URL {
        // Synthetic URL — no file actually opened in tests; the stub preparer
        // returns its canned result regardless of the URL's reachability.
        URL(fileURLWithPath: "/private/var/tmp/love_rehab.m4a")
    }

    // MARK: - State machine

    @Test func startLocalFile_idle_transitionsThroughPreparingToReady() async throws {
        let manager = try makeLFManager()
        let result = makeStubPrepResult(url: fileURL)
        let stub = StubLocalFilePreparer(result: result, preparationDelayMs: 50)
        manager.localFilePreparer = stub

        var observed: [SessionState] = []
        let cancellable = manager.$state.sink { observed.append($0) }
        defer { cancellable.cancel() }

        await manager.startLocalFile(at: fileURL)

        #expect(manager.state == .ready)
        #expect(observed.contains(.preparing), "Expected .preparing in \(observed)")
        #expect(observed.contains(.ready), "Expected .ready in \(observed)")
        let preparingIdx = observed.firstIndex(of: .preparing) ?? -1
        let readyIdx = observed.firstIndex(of: .ready) ?? -1
        #expect(preparingIdx < readyIdx, ".preparing must precede .ready")
    }

    @Test func startLocalFile_storesCachedDataUnderSyntheticIdentity() async throws {
        let manager = try makeLFManager()
        let result = makeStubPrepResult(url: fileURL)
        let stub = StubLocalFilePreparer(result: result)
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)

        // Cached entry is reachable via `loadForPlayback` against the result
        // identity — the same lookup VisualizerEngine.resetStemPipeline uses.
        let loaded = manager.cache.loadForPlayback(track: result.identity)
        #expect(loaded != nil)
    }

    @Test func startLocalFile_planContainsOneTrack() async throws {
        let manager = try makeLFManager()
        let result = makeStubPrepResult(url: fileURL)
        let stub = StubLocalFilePreparer(result: result)
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)

        #expect(manager.currentPlan?.tracks.count == 1)
        #expect(manager.currentPlan?.tracks.first?.spotifyID?.hasPrefix("local:sha256:") == true)
    }

    @Test func startLocalFile_setsCurrentSourceToLocalFile() async throws {
        let manager = try makeLFManager()
        let stub = StubLocalFilePreparer(result: makeStubPrepResult(url: fileURL))
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)

        #expect(manager.currentSource?.isLocalFile == true)
        #expect(manager.currentSource?.localFileURL == fileURL)
        #expect(manager.sessionSource == nil)
    }

    @Test func startLocalFile_progressiveReadinessJumpsToFullyPrepared() async throws {
        let manager = try makeLFManager()
        let stub = StubLocalFilePreparer(result: makeStubPrepResult(url: fileURL))
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)

        #expect(manager.progressiveReadinessLevel == .fullyPrepared)
    }

    @Test func startLocalFile_beginPlayback_transitionsToPlaying() async throws {
        let manager = try makeLFManager()
        let stub = StubLocalFilePreparer(result: makeStubPrepResult(url: fileURL))
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)
        manager.beginPlayback()

        #expect(manager.state == .playing)
    }

    // MARK: - Replace-on-open

    @Test func startLocalFile_replacesActiveStreamingSession() async throws {
        let manager = try makeLFManager()
        await manager.startSession(source: .appleMusicCurrentPlaylist)
        // Sometimes preparation completes synchronously due to stub instantaneous returns.
        // We don't depend on its final state here — only that startLocalFile takes over.

        let stub = StubLocalFilePreparer(result: makeStubPrepResult(url: fileURL))
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)

        #expect(manager.currentSource?.isLocalFile == true)
        #expect(manager.state == .ready)
        #expect(stub.callCount == 1)
    }

    @Test func startLocalFile_sameURL_isNoOp() async throws {
        let manager = try makeLFManager()
        let stub = StubLocalFilePreparer(result: makeStubPrepResult(url: fileURL))
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)
        manager.beginPlayback()                  // .ready → .playing

        await manager.startLocalFile(at: fileURL) // second call — should no-op

        #expect(stub.callCount == 1, "Second startLocalFile on same URL should not re-prepare")
        #expect(manager.state == .playing)
    }

    @Test func startLocalFile_differentURL_replacesSession() async throws {
        let manager = try makeLFManager()
        let stub = StubLocalFilePreparer(result: makeStubPrepResult(url: fileURL))
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)

        let otherURL = URL(fileURLWithPath: "/private/var/tmp/other.m4a")
        let otherResult = makeStubPrepResult(
            url: otherURL,
            hash: "00000000000000000000000000000000000000000000000000000000000000aa"
        )
        let stub2 = StubLocalFilePreparer(result: otherResult)
        manager.localFilePreparer = stub2

        await manager.startLocalFile(at: otherURL)

        #expect(manager.currentSource?.localFileURL == otherURL)
        #expect(stub2.callCount == 1)
    }

    // MARK: - Degradation

    @Test func startLocalFile_noPreparerWired_stillTransitionsToReady() async throws {
        let manager = try makeLFManager()
        // No localFilePreparer set; the no-cache fallthrough still produces .ready.

        await manager.startLocalFile(at: fileURL)

        #expect(manager.state == .ready)
        #expect(manager.currentSource?.isLocalFile == true)
        #expect(manager.currentPlan?.tracks.count == 1)
    }

    @Test func startLocalFile_preparerReturnsNil_stillTransitionsToReady() async throws {
        let manager = try makeLFManager()
        let stub = StubLocalFilePreparer(result: nil)
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)

        #expect(manager.state == .ready)
        // No cache entry — the LF.1 fallthrough still gets the user playback.
        #expect(manager.cache.count == 0)
    }

    // MARK: - Cancel + end

    @Test func cancel_duringLocalFile_returnsToIdle() async throws {
        let manager = try makeLFManager()
        let stub = StubLocalFilePreparer(result: makeStubPrepResult(url: fileURL))
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)
        manager.cancel()

        #expect(manager.state == .idle)
        #expect(manager.currentSource == nil)
        #expect(manager.currentPlan == nil)
    }

    @Test func endSession_clearsLocalFileSource() async throws {
        let manager = try makeLFManager()
        let stub = StubLocalFilePreparer(result: makeStubPrepResult(url: fileURL))
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)
        manager.beginPlayback()
        manager.endSession()

        #expect(manager.state == .ended)
        #expect(manager.currentSource == nil)
    }

    // MARK: - Source semantics

    @Test func cancel_thenStartSession_setsPlaylistSource() async throws {
        let manager = try makeLFManager()
        let stub = StubLocalFilePreparer(result: makeStubPrepResult(url: fileURL))
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)
        manager.cancel()

        // Now flip to a streaming session from the clean .idle state.
        await manager.startSession(source: .appleMusicCurrentPlaylist)

        // startSession sets sessionSource and currentSource = .playlist
        if case .playlist = manager.currentSource {
            // expected
        } else {
            Issue.record("Expected currentSource == .playlist(…), got \(String(describing: manager.currentSource))")
        }
        if case .appleMusicCurrentPlaylist = manager.sessionSource {
            // expected
        } else {
            Issue.record("Expected sessionSource == .appleMusicCurrentPlaylist")
        }
    }

    // MARK: - LF.5 multi-file lifecycle

    private var threeURLs: [URL] {
        [
            URL(fileURLWithPath: "/private/var/tmp/love_rehab.m4a"),
            URL(fileURLWithPath: "/private/var/tmp/so_what.m4a"),
            URL(fileURLWithPath: "/private/var/tmp/there_there.m4a")
        ]
    }

    private func makeMultiStub(_ urls: [URL]) -> MultiStubLocalFilePreparer {
        var results: [String: LocalFilePrepResult] = [:]
        for (index, url) in urls.enumerated() {
            // Distinct synthetic hashes so each cache entry resolves separately.
            let hash = String(format: "%064x", index + 1)
            results[url.lastPathComponent] = makeStubPrepResult(url: url, hash: hash)
        }
        return MultiStubLocalFilePreparer(results: results)
    }

    @Test func startLocalFiles_threeURLs_preparesEachInOrder() async throws {
        let manager = try makeLFManager()
        let urls = threeURLs
        let stub = makeMultiStub(urls)
        manager.localFilePreparer = stub

        await manager.startLocalFiles(at: urls, origin: .localFiles(urls))

        #expect(manager.state == .ready)
        #expect(stub.callCount == 3)
        #expect(stub.callOrder == urls, "Preparer must be called sequentially in URL order")
        #expect(manager.currentPlan?.tracks.count == 3)
    }

    @Test func startLocalFiles_storesEveryCachedEntry() async throws {
        let manager = try makeLFManager()
        let urls = threeURLs
        let stub = makeMultiStub(urls)
        manager.localFilePreparer = stub

        await manager.startLocalFiles(at: urls, origin: .localFiles(urls))

        // Every track in the resulting plan should resolve to a cache entry.
        for track in manager.currentPlan?.tracks ?? [] {
            #expect(manager.cache.loadForPlayback(track: track) != nil,
                    "Cache miss for prepared track \(track.title)")
        }
        #expect(manager.cache.count == 3)
    }

    @Test func startLocalFiles_setsCurrentSource_toLocalFiles() async throws {
        let manager = try makeLFManager()
        let urls = threeURLs
        let stub = makeMultiStub(urls)
        manager.localFilePreparer = stub

        await manager.startLocalFiles(at: urls, origin: .localFiles(urls))

        #expect(manager.currentSource?.isLocalFile == true)
        #expect(manager.currentSource?.localFileURL == urls.first)
        #expect(manager.currentSource?.allLocalFileURLs == urls)
        #expect(manager.sessionSource == nil)
    }

    @Test func startLocalFiles_setsCurrentSource_toLocalFolder() async throws {
        let manager = try makeLFManager()
        let urls = threeURLs
        let folder = URL(fileURLWithPath: "/private/var/tmp/Music")
        let stub = makeMultiStub(urls)
        manager.localFilePreparer = stub

        await manager.startLocalFiles(at: urls, origin: .localFolder(folder, expanded: urls))

        if case .localFolder(let observedFolder, let observedExpanded) = manager.currentSource {
            #expect(observedFolder == folder)
            #expect(observedExpanded == urls)
        } else {
            Issue.record(
                "Expected currentSource == .localFolder(…), got \(String(describing: manager.currentSource))"
            )
        }
    }

    @Test func startLocalFiles_setsCurrentSource_toLocalPlaylist() async throws {
        let manager = try makeLFManager()
        let urls = threeURLs
        let playlist = URL(fileURLWithPath: "/private/var/tmp/mix.m3u")
        let stub = makeMultiStub(urls)
        manager.localFilePreparer = stub

        await manager.startLocalFiles(at: urls, origin: .localPlaylist(playlist, expanded: urls))

        if case .localPlaylist(let observedPlaylist, let observedExpanded) = manager.currentSource {
            #expect(observedPlaylist == playlist)
            #expect(observedExpanded == urls)
        } else {
            Issue.record(
                "Expected currentSource == .localPlaylist(…), got \(String(describing: manager.currentSource))"
            )
        }
    }

    @Test func startLocalFiles_progressiveReadinessJumpsToFullyPrepared() async throws {
        let manager = try makeLFManager()
        let urls = threeURLs
        let stub = makeMultiStub(urls)
        manager.localFilePreparer = stub

        await manager.startLocalFiles(at: urls, origin: .localFiles(urls))

        #expect(manager.progressiveReadinessLevel == .fullyPrepared)
    }

    @Test func startLocalFiles_emptyList_isNoOp() async throws {
        let manager = try makeLFManager()
        let stub = makeMultiStub(threeURLs)
        manager.localFilePreparer = stub

        await manager.startLocalFiles(at: [], origin: .localFiles([]))

        #expect(manager.state == .idle)
        #expect(stub.callCount == 0)
        #expect(manager.currentSource == nil)
    }

    @Test func startLocalFiles_sameOrigin_isNoOp() async throws {
        let manager = try makeLFManager()
        let urls = threeURLs
        let stub = makeMultiStub(urls)
        manager.localFilePreparer = stub

        await manager.startLocalFiles(at: urls, origin: .localFiles(urls))
        manager.beginPlayback()                                            // .ready → .playing

        await manager.startLocalFiles(at: urls, origin: .localFiles(urls)) // second call
        #expect(stub.callCount == 3, "Second startLocalFiles on same origin should not re-prepare")
        #expect(manager.state == .playing)
    }

    @Test func startLocalFiles_differentURLList_replacesSession() async throws {
        let manager = try makeLFManager()
        let firstURLs = threeURLs
        let stub1 = makeMultiStub(firstURLs)
        manager.localFilePreparer = stub1

        await manager.startLocalFiles(at: firstURLs, origin: .localFiles(firstURLs))

        let secondURLs = [
            URL(fileURLWithPath: "/private/var/tmp/money.m4a"),
            URL(fileURLWithPath: "/private/var/tmp/pyramid_song.m4a")
        ]
        let stub2 = makeMultiStub(secondURLs)
        manager.localFilePreparer = stub2

        await manager.startLocalFiles(at: secondURLs, origin: .localFiles(secondURLs))

        #expect(manager.currentSource?.allLocalFileURLs == secondURLs)
        #expect(stub2.callCount == 2)
        #expect(manager.currentPlan?.tracks.count == 2)
    }

    @Test func startLocalFiles_singleURLAsWrapper_matchesStartLocalFile() async throws {
        // Regression gate for the LF.5 consolidation: startLocalFile(at:) is now
        // a thin wrapper around startLocalFiles(at: [url], origin: .localFile(url)).
        // Asserts the wrapper sets the LF.4-shaped source + plan + state.
        let manager = try makeLFManager()
        let stub = StubLocalFilePreparer(result: makeStubPrepResult(url: fileURL))
        manager.localFilePreparer = stub

        await manager.startLocalFile(at: fileURL)

        if case .localFile(let observedURL) = manager.currentSource {
            #expect(observedURL == fileURL)
        } else {
            Issue.record(
                "startLocalFile wrapper must yield .localFile origin, got \(String(describing: manager.currentSource))"
            )
        }
        #expect(manager.state == .ready)
        #expect(manager.currentPlan?.tracks.count == 1)
        #expect(manager.progressiveReadinessLevel == .fullyPrepared)
    }

    @Test func startLocalFiles_replacesActiveStreamingSession() async throws {
        let manager = try makeLFManager()
        await manager.startSession(source: .appleMusicCurrentPlaylist)

        let urls = threeURLs
        let stub = makeMultiStub(urls)
        manager.localFilePreparer = stub

        await manager.startLocalFiles(at: urls, origin: .localFiles(urls))

        #expect(manager.currentSource?.isLocalFile == true)
        #expect(manager.state == .ready)
        #expect(stub.callCount == 3)
        #expect(manager.sessionSource == nil)
    }

    @Test func startLocalFiles_noPreparerWired_stillTransitionsToReady() async throws {
        let manager = try makeLFManager()
        // No localFilePreparer set; placeholder identities populate the plan
        // and the LF.1 fallthrough still produces .ready.
        let urls = threeURLs

        await manager.startLocalFiles(at: urls, origin: .localFiles(urls))

        #expect(manager.state == .ready)
        #expect(manager.currentSource?.isLocalFile == true)
        #expect(manager.currentPlan?.tracks.count == 3)
        // No preparer wired → no cache entries.
        #expect(manager.cache.count == 0)
    }

    @Test func startLocalFiles_publishesPerTrackStatus() async throws {
        // LF.5 Task 2: SessionPreparer.prepareLocalFiles drives trackStatuses
        // transitions through the same publisher streaming uses. The placeholder
        // identities (keyed on URL.path) must observe at least one
        // .analyzing(.stemSeparation) and one .ready snapshot per file.
        let manager = try makeLFManager()
        let urls = threeURLs
        let stub = makeMultiStub(urls)
        // 30 ms per-file delay so the test can observe intermediate statuses.
        let delayedStub = MultiStubLocalFilePreparer(
            results: stub.resultsByFilename,
            preparationDelayMs: 30
        )
        manager.localFilePreparer = delayedStub

        // Capture every trackStatuses snapshot emitted during the run.
        var snapshots: [[TrackIdentity: TrackPreparationStatus]] = []
        let cancellable = manager.preparationProgress?
            .trackStatusesPublisher
            .sink { snapshots.append($0) }
        defer { cancellable?.cancel() }

        await manager.startLocalFiles(at: urls, origin: .localFiles(urls))

        #expect(manager.state == .ready)
        #expect(snapshots.count >= urls.count * 2,
                "Expected ≥ \(urls.count * 2) status snapshots (analyzing + ready per file), got \(snapshots.count)")

        // Each placeholder must have hit `.analyzing(.stemSeparation)` AND
        // ended on `.ready` somewhere in the captured timeline.
        for index in 0..<urls.count {
            let placeholder = TrackIdentity(
                title: urls[index].lastPathComponent,
                artist: "local file",
                duration: 0,
                spotifyID: "local:" + urls[index].path
            )
            let analyzingSeen = snapshots.contains { $0[placeholder] == .analyzing(stage: .stemSeparation) }
            let readySeen = snapshots.contains { $0[placeholder] == .ready }
            #expect(analyzingSeen, "Placeholder #\(index) never observed .analyzing(.stemSeparation)")
            #expect(readySeen, "Placeholder #\(index) never observed .ready")
        }
    }

    @Test func startLocalFiles_preparerReturnsNil_emitsPartialStatus() async throws {
        // LF.5 Task 2: when the delegate returns nil for a file (LF.1 fallthrough),
        // SessionPreparer publishes `.partial` for that placeholder and routes the
        // identity into the SessionPreparationResult's failedTracks list.
        let manager = try makeLFManager()
        let urls = threeURLs
        // Stub returns nothing — every file falls through.
        let stub = MultiStubLocalFilePreparer(results: [:])
        manager.localFilePreparer = stub

        var snapshots: [[TrackIdentity: TrackPreparationStatus]] = []
        let cancellable = manager.preparationProgress?
            .trackStatusesPublisher
            .sink { snapshots.append($0) }
        defer { cancellable?.cancel() }

        await manager.startLocalFiles(at: urls, origin: .localFiles(urls))

        #expect(manager.state == .ready)
        #expect(manager.cache.count == 0, "No delegate result → no cache entries")
        for index in 0..<urls.count {
            let placeholder = TrackIdentity(
                title: urls[index].lastPathComponent,
                artist: "local file",
                duration: 0,
                spotifyID: "local:" + urls[index].path
            )
            let partialSeen = snapshots.contains {
                if case .partial = $0[placeholder] { return true }
                return false
            }
            #expect(partialSeen, "Placeholder #\(index) never observed .partial after nil prep result")
        }
    }

    @Test func cancel_midQueue_returnsToIdleWithPartialCache() async throws {
        let manager = try makeLFManager()
        let urls = threeURLs
        // 80 ms per-file delay — plenty of headroom for the cancel to land
        // after the first file's prep returns but before the second begins.
        var results: [String: LocalFilePrepResult] = [:]
        for (index, url) in urls.enumerated() {
            let hash = String(format: "%064x", index + 1)
            results[url.lastPathComponent] = makeStubPrepResult(url: url, hash: hash)
        }
        let stub = MultiStubLocalFilePreparer(results: results, preparationDelayMs: 80)
        manager.localFilePreparer = stub

        async let preparation: Void = manager.startLocalFiles(at: urls, origin: .localFiles(urls))
        try await Task.sleep(nanoseconds: 30_000_000)                        // let the first file get started
        manager.cancel()
        await preparation

        #expect(manager.state == .idle)
        #expect(manager.currentSource == nil)
        #expect(manager.currentPlan == nil)
        // The first file's preparer call may have completed before cancel landed;
        // subsequent files must NOT have been called.
        #expect(stub.callCount < urls.count, "Cancel must short-circuit before all files prepared")
    }

    // MARK: - LF.5.fix.3-A — superseded call must not transition to .ready

    @Test func startLocalFiles_supersededCall_doesNotTransitionToReady() async throws {
        // LF.5.fix.3-A regression gate. After a newer `startLocalFiles` call
        // takes over, the older suspended call must NOT proceed to
        // `_completeLocalFilesReady` — even though `cancellationRequested`
        // was reset to false by the newer call's `_beginMultiFileTransition`.
        // The generation counter is the authoritative supersession signal.
        //
        // The captured failure (session 2026-05-28T20-57-46Z line 19):
        // folder A's prep was cancelled at 2/200 files, B took over, but A's
        // `await preparer.prepareLocalFiles` resumed and wrote a 2-track
        // currentPlan + .ready state — the engine then played folder A's
        // tracks against folder B's URL queue.
        //
        // Sequencing trick: A's delegate uses Task.detached so its 200 ms
        // delay does not honor parent cancellation. That guarantees A's
        // continuation resumes AFTER B has finished and transitioned to
        // .ready, so the assertion below would fail pre-fix.
        let manager = try makeLFManager()
        let urlsA = (0..<3).map { URL(fileURLWithPath: "/private/var/tmp/supersA\($0).m4a") }
        let urlsB = [URL(fileURLWithPath: "/private/var/tmp/supersB.m4a")]

        let resultA0 = makeStubPrepResult(url: urlsA[0], hash: String(format: "%064x", 0xA0))
        let stubA = UninterruptibleDelayLocalFilePreparer(result: resultA0, delayMs: 200)
        manager.localFilePreparer = stubA

        async let prepA: Void = manager.startLocalFiles(at: urlsA, origin: .localFiles(urlsA))
        try await Task.sleep(nanoseconds: 20_000_000)                       // A is in file-0's uninterruptible 200 ms wait

        let resultB = makeStubPrepResult(url: urlsB[0], hash: String(format: "%064x", 0xB0))
        let stubB = StubLocalFilePreparer(result: resultB)
        manager.localFilePreparer = stubB

        await manager.startLocalFiles(at: urlsB, origin: .localFiles(urlsB))

        // Snapshot B's outcome BEFORE A's continuation resumes (A is still
        // waiting on its uninterruptible delegate).
        let stateAfterB = manager.state
        let planIDAfterB = manager.currentPlan?.tracks.first?.spotifyID
        let sourceURLAfterB = manager.currentSource?.localFileURL

        // Now A's delegate completes, A's continuation runs the
        // post-await gates. With the fix, gen mismatch → bail. Without
        // the fix, A would write its (cancelled, 0-track) result over B's.
        await prepA

        #expect(manager.state == stateAfterB,
                "Superseded A.continuation must not have changed state")
        #expect(manager.currentPlan?.tracks.first?.spotifyID == planIDAfterB,
                "Superseded A.continuation must not have overwritten currentPlan")
        #expect(manager.currentSource?.localFileURL == sourceURLAfterB,
                "Superseded A.continuation must not have changed currentSource")
    }

    // MARK: - LF.5.fix.3-B — cancellation race on second startLocalFiles

    @Test func startLocalFiles_secondCall_cancelsFirstInFlight_evenAfterEndSession() async throws {
        // LF.5.fix.3-B regression gate. Reproduces the cluster from session
        // 2026-05-28T20-57-46Z: first folder pick → user Stop (state .ended)
        // → second folder pick. SessionManager.startLocalFiles guards cancel()
        // on `state != .idle && state != .ended`, so .ended bypasses the
        // SessionManager-side cancellation entirely. SessionPreparer must
        // cancel any in-flight prep task at the start of every prepareLocalFiles
        // call so the previous folder's preparation doesn't keep running.
        let manager = try makeLFManager()
        let urlsA = (0..<5).map { URL(fileURLWithPath: "/private/var/tmp/raceA\($0).m4a") }
        let urlsB = [URL(fileURLWithPath: "/private/var/tmp/raceB.m4a")]

        var resultsA: [String: LocalFilePrepResult] = [:]
        for (index, url) in urlsA.enumerated() {
            let hash = String(format: "%064x", index + 0x10)
            resultsA[url.lastPathComponent] = makeStubPrepResult(url: url, hash: hash)
        }
        // 120 ms per file — enough headroom for the cancel to land between
        // file 0's return and file 1's start.
        let stubA = MultiStubLocalFilePreparer(results: resultsA, preparationDelayMs: 120)
        manager.localFilePreparer = stubA

        async let prepA: Void = manager.startLocalFiles(at: urlsA, origin: .localFiles(urlsA))
        try await Task.sleep(nanoseconds: 50_000_000)                       // 50 ms — A is mid-file-0

        // Simulate the user pressing Stop on the (mis-)playing session
        // (matches the 20:59:05 provider.teardown in the captured log).
        manager.endSession()

        let resultsB = [
            urlsB[0].lastPathComponent: makeStubPrepResult(
                url: urlsB[0],
                hash: String(format: "%064x", 0xB0)
            )
        ]
        let stubB = MultiStubLocalFilePreparer(results: resultsB)
        manager.localFilePreparer = stubB

        await manager.startLocalFiles(at: urlsB, origin: .localFiles(urlsB))
        await prepA

        // The load-bearing Bug B assertion: A's preparer must NOT have
        // processed all 5 files. Pre-fix, A would run to completion in
        // parallel with B, leaving stubA.callCount == 5.
        let aCount = stubA.callCount
        let aTotal = urlsA.count
        #expect(
            aCount < aTotal,
            "A's prep should have been cancelled when B started (got \(aCount)/\(aTotal) delegate calls)"
        )

        // B should have prepared its one file normally.
        #expect(stubB.callCount == 1)
    }
}

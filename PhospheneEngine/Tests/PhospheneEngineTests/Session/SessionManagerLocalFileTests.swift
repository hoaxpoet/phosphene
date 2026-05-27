// SessionManagerLocalFileTests — LF.4 single-file lifecycle for SessionManager.
//
// Exercises `startLocalFile(at:)` and its interaction with the existing
// state machine (idle/preparing/ready/playing transitions, replace-on-open,
// progressive-readiness short-circuit, no-preparer degradation).
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
}

// SessionManagerCancelTests — Verifies SessionManager.cancel() behaviour.
// Covers the .preparing → .idle cancel path and the .idle no-op guard.

import Combine
import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Shared
@testable import Session

// MARK: - Stubs

private final class SlowConnector: PlaylistConnecting, @unchecked Sendable {
    var tracks: [TrackIdentity] = [
        TrackIdentity(title: "A", artist: "Artist A"),
        TrackIdentity(title: "B", artist: "Artist B"),
        TrackIdentity(title: "C", artist: "Artist C"),
    ]
    func connect(source: PlaylistSource) async throws -> [TrackIdentity] { tracks }
}

private final class BlockingResolver: PreviewResolving, @unchecked Sendable {
    // 600ms per track — long enough that cancel fires before any track finishes.
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        try await Task.sleep(nanoseconds: 600_000_000)
        return URL(string: "https://example.com/preview.m4a")
    }
}

private final class InstantResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        URL(string: "https://example.com/preview.m4a")
    }
}

private final class InstantDownloader: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        let samples = (0..<44100).map { i in 0.05 * sin(Float(i) * 0.01) }
        return PreviewAudio(trackIdentity: track, pcmSamples: samples, sampleRate: 44100, duration: 1.0)
    }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}

private final class InstantSeparator: StemSeparating, @unchecked Sendable {
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
            sampleCount: 4096
        )
    }
}

private final class InstantAnalyzer: StemAnalyzing, @unchecked Sendable {
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures { .zero }
    func reset() {}
}

// MARK: - Helpers

@MainActor
private func makeManager(
    connector: any PlaylistConnecting = SlowConnector(),
    resolver: any PreviewResolving = InstantResolver(),
    separator: any StemSeparating
) -> SessionManager {
    let preparer = SessionPreparer(
        resolver: resolver,
        downloader: InstantDownloader(),
        stemSeparator: separator,
        stemAnalyzer: InstantAnalyzer(),
        moodClassifier: MockMoodClassifier()
    )
    return SessionManager(connector: connector, preparer: preparer)
}

// MARK: - Suite

@Suite("SessionManager.Cancel")
@MainActor
struct SessionManagerCancelTests {

    @Test func cancel_fromPreparing_callsCancelPreparation_transitionsToIdle() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sep = try InstantSeparator(device: device)
        // Slow resolver ensures we're still in .preparing when cancel fires.
        let manager = makeManager(connector: SlowConnector(), resolver: BlockingResolver(), separator: sep)

        var observedStates: [SessionState] = []
        let stateCancellable = manager.$state.sink { observedStates.append($0) }
        defer { stateCancellable.cancel() }

        // Start session in a background task.
        let sessionTask = Task { @MainActor in
            await manager.startSession(source: .appleMusicCurrentPlaylist)
        }

        // Wait until .preparing state is reached.
        var waitCount = 0
        while manager.state != .preparing && waitCount < 100 {
            try await Task.sleep(nanoseconds: 10_000_000)
            waitCount += 1
        }
        #expect(manager.state == .preparing, "Expected .preparing before cancel")

        // Cancel mid-preparation.
        manager.cancel()

        // State should be .idle immediately.
        #expect(manager.state == .idle)

        // Wait for startSession to return.
        await sessionTask.value

        // Must remain .idle — NOT transition to .ready after cancel.
        #expect(manager.state == .idle)
        #expect(observedStates.contains(.preparing))
        #expect(observedStates.last == .idle)
    }

    @Test func cancel_fromIdle_isNoOp() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sep = try InstantSeparator(device: device)
        let manager = makeManager(separator: sep)

        #expect(manager.state == .idle)
        manager.cancel()  // Must not throw or crash
        #expect(manager.state == .idle, "cancel() from .idle must be a no-op")
    }

    @Test func cancel_fromReady_transitionsToIdle() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sep = try InstantSeparator(device: device)
        let manager = makeManager(separator: sep)

        await manager.startSession(source: .appleMusicCurrentPlaylist)
        // startSession returns early while .preparing; wait for natural completion.
        let deadline = Date().addingTimeInterval(3)
        while manager.state == .preparing && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(manager.state == .ready)

        manager.cancel()
        #expect(manager.state == .idle)
    }
}

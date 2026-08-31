// SessionPreparerProgressTests — Per-track status tracking and cancellation behaviour.
// Verifies that SessionPreparer emits correct TrackPreparationStatus transitions
// and that cancelPreparation() tears down cleanly without orphan cache entries.

import Combine
import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Shared
@testable import Session

// MARK: - Private Stubs

private final class SlowResolver: PreviewResolving, @unchecked Sendable {
    var delayNanoseconds: UInt64
    var urlToReturn: URL? = URL(string: "https://example.com/preview.m4a")

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        return urlToReturn
    }
}

private final class FailingResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? { nil }
}

private final class FailingDownloader: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? { nil }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}

private final class SuccessDownloader: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        let samples = (0..<44100).map { i in 0.05 * sin(Float(i) * 0.01) }
        return PreviewAudio(trackIdentity: track, pcmSamples: samples, sampleRate: 44100, duration: 1.0)
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

private final class ThrowingSeparator: StemSeparating, @unchecked Sendable {
    let stemLabels: [String] = ["vocals", "drums", "bass", "other"]
    let stemBuffers: [UMABuffer<Float>]
    init(device: MTLDevice) throws {
        stemBuffers = try (0..<4).map { _ in try UMABuffer<Float>(device: device, capacity: 4096) }
    }
    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        throw StemSeparationError.predictionFailed("stub error")
    }
}

private final class FastSeparator: StemSeparating, @unchecked Sendable {
    let stemLabels: [String] = ["vocals", "drums", "bass", "other"]
    let stemBuffers: [UMABuffer<Float>]
    init(device: MTLDevice) throws {
        stemBuffers = try (0..<4).map { _ in try UMABuffer<Float>(device: device, capacity: 4096) }
        for buf in stemBuffers {
            buf.write([Float](repeating: 0.1, count: 4096))
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

private final class FastAnalyzer: StemAnalyzing, @unchecked Sendable {
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

// MARK: - Helpers

private func makeTrack(_ title: String) -> TrackIdentity {
    TrackIdentity(title: title, artist: "Test Artist")
}

// MARK: - Suite

@Suite("SessionPreparer.Progress")
@MainActor
struct SessionPreparerProgressTests {

    // MARK: - Initial State

    @Test func prepare_initializesAllTracksToQueued() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sep = try FastSeparator(device: device)
        let tracks = (0..<3).map { makeTrack("T\($0)") }

        let preparer = SessionPreparer(
            resolver: SlowResolver(),
            downloader: SuccessDownloader(),
            stemSeparator: sep,
            stemAnalyzer: FastAnalyzer(),
            moodClassifier: MockMoodClassifier()
        )

        // Collect all snapshots; find the first one where all three tracks are .queued.
        // @Published emits the current value on subscription ([:]); we skip that and look
        // for the snapshot where prepare() bulk-initialises all tracks.
        var snapshots: [[TrackIdentity: TrackPreparationStatus]] = []
        let cancellable = preparer.trackStatusesPublisher.sink { snapshots.append($0) }
        defer { cancellable.cancel() }

        _ = await preparer.prepare(tracks: tracks)

        let allQueuedSnapshot = snapshots.first { snapshot in
            tracks.allSatisfy { snapshot[$0] == .queued }
        }
        #expect(allQueuedSnapshot != nil, "No snapshot found with all tracks at .queued")
    }

    // MARK: - Stage Progression

    @Test func prepare_advancesThroughExpectedStages() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sep = try FastSeparator(device: device)
        let track = makeTrack("So What")

        let preparer = SessionPreparer(
            resolver: SlowResolver(),
            downloader: SuccessDownloader(),
            stemSeparator: sep,
            stemAnalyzer: FastAnalyzer(),
            moodClassifier: MockMoodClassifier()
        )

        var snapshots: [[TrackIdentity: TrackPreparationStatus]] = []
        let cancellable = preparer.trackStatusesPublisher.sink { snapshots.append($0) }
        defer { cancellable.cancel() }

        _ = await preparer.prepare(tracks: [track])

        let statuses = snapshots.compactMap { $0[track] }
        // First snapshot must have .queued.
        #expect(statuses.first == .queued)
        // Must pass through resolving, downloading, and analyzing.
        #expect(statuses.contains(.resolving))
        #expect(statuses.contains(.downloading(progress: -1)))
        #expect(statuses.contains(.analyzing(stage: .stemSeparation)))
        #expect(statuses.contains(.analyzing(stage: .caching)))
        // Terminal status must be .ready.
        #expect(statuses.last == .ready)
    }

    // MARK: - Failure Paths

    @Test func prepare_previewResolutionFailure_setsFailed() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sep = try FastSeparator(device: device)
        let track = makeTrack("No Preview Track")

        let preparer = SessionPreparer(
            resolver: FailingResolver(),
            downloader: SuccessDownloader(),
            stemSeparator: sep,
            stemAnalyzer: FastAnalyzer(),
            moodClassifier: MockMoodClassifier()
        )

        _ = await preparer.prepare(tracks: [track])

        if case .failed = preparer.trackStatuses[track] {
            // Pass — correct terminal status.
        } else {
            #expect(Bool(false), "Expected .failed for no-preview track, got \(String(describing: preparer.trackStatuses[track]))")
        }
    }

    @Test func prepare_downloadFailure_setsFailed() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sep = try FastSeparator(device: device)
        let track = makeTrack("Download Fail Track")

        let preparer = SessionPreparer(
            resolver: SlowResolver(),
            downloader: FailingDownloader(),
            stemSeparator: sep,
            stemAnalyzer: FastAnalyzer(),
            moodClassifier: MockMoodClassifier()
        )

        _ = await preparer.prepare(tracks: [track])

        if case .failed = preparer.trackStatuses[track] {
            // Pass.
        } else {
            #expect(Bool(false), "Expected .failed for download failure, got \(String(describing: preparer.trackStatuses[track]))")
        }
    }

    @Test func prepare_stemSeparationFailureAfterDownload_setsPartial() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let throwingSep = try ThrowingSeparator(device: device)
        let track = makeTrack("Analysis Fail Track")

        let preparer = SessionPreparer(
            resolver: SlowResolver(),
            downloader: SuccessDownloader(),
            stemSeparator: throwingSep,
            stemAnalyzer: FastAnalyzer(),
            moodClassifier: MockMoodClassifier()
        )

        _ = await preparer.prepare(tracks: [track])

        if case .partial = preparer.trackStatuses[track] {
            // Pass — download succeeded, stems failed → playable in reactive mode.
        } else {
            #expect(Bool(false), "Expected .partial for stem separation failure, got \(String(describing: preparer.trackStatuses[track]))")
        }
    }

    // MARK: - Cancellation

    @Test func cancelPreparation_remainingTracksStayQueued() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sep = try FastSeparator(device: device)
        // 400ms per resolver call — enough that 5 tracks are still queued after cancel.
        let resolver = SlowResolver(delayNanoseconds: 400_000_000)
        let tracks = (0..<5).map { makeTrack("Slow T\($0)") }

        let preparer = SessionPreparer(
            resolver: resolver,
            downloader: SuccessDownloader(),
            stemSeparator: sep,
            stemAnalyzer: FastAnalyzer(),
            moodClassifier: MockMoodClassifier()
        )

        let prepTask = Task { @MainActor in
            await preparer.prepare(tracks: tracks)
        }

        // Cancel after 50ms — first track is in .resolving, rest are .queued.
        try await Task.sleep(nanoseconds: 50_000_000)
        preparer.cancelPreparation()

        _ = await prepTask.value

        // Tracks that never started must remain .queued (not .failed).
        let queuedCount = tracks.filter { preparer.trackStatuses[$0] == .queued }.count
        #expect(queuedCount > 0, "At least one track should remain .queued after cancel")
    }

    @Test func cancelPreparation_tearsDownInFlight_noOrphanCacheEntries() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sep = try FastSeparator(device: device)
        let resolver = SlowResolver(delayNanoseconds: 400_000_000)
        let tracks = (0..<5).map { makeTrack("Cache T\($0)") }

        let preparer = SessionPreparer(
            resolver: resolver,
            downloader: SuccessDownloader(),
            stemSeparator: sep,
            stemAnalyzer: FastAnalyzer(),
            moodClassifier: MockMoodClassifier()
        )

        let prepTask = Task { @MainActor in
            await preparer.prepare(tracks: tracks)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        preparer.cancelPreparation()
        let result = await prepTask.value

        // Cache should contain only the tracks that completed before cancel.
        for track in tracks {
            if preparer.trackStatuses[track] == .queued {
                // This track never started — must not appear in cache.
                #expect(result.cache.loadForPlayback(track: track) == nil,
                        "Queued track \(track.title) must not have a cache entry")
            }
        }
    }
}

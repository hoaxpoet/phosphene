// SessionPreparerTests — Unit tests for SessionPreparer and StemCache.
// All external dependencies are injected via protocol stubs.
// No real network, no real Metal device needed for StemCache tests.
// StemSeparator tests use a Metal-backed stub (MTLCreateSystemDefaultDevice).

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Shared
@testable import Session

// MARK: - Stubs

/// Stem separator stub: writes constant 0.1 signal into buffers, returns quickly.
private final class StubStemSeparator: StemSeparating, @unchecked Sendable {
    let stemLabels: [String] = ["vocals", "drums", "bass", "other"]
    let stemBuffers: [UMABuffer<Float>]
    private(set) var separateCallCount = 0
    var shouldThrow = false
    let sampleCount = 4096  // Enough for StemAnalyzer warmup

    init(device: MTLDevice) throws {
        stemBuffers = try (0..<4).map { _ in
            try UMABuffer<Float>(device: device, capacity: 44100)
        }
        // Pre-fill each buffer with a low-level sine-like signal so StemAnalyzer
        // produces non-zero energy values.
        for buf in stemBuffers {
            var samples = [Float](repeating: 0, count: 4096)
            for i in 0..<4096 {
                samples[i] = 0.1 * sin(Float(i) * 0.01)
            }
            buf.write(samples)
        }
    }

    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        separateCallCount += 1
        if shouldThrow { throw StemSeparationError.predictionFailed("stub error") }
        let frame = AudioFrame(
            sampleRate: sampleRate,
            sampleCount: UInt32(sampleCount),
            channelCount: 1
        )
        return StemSeparationResult(
            stemData: StemData(vocals: frame, drums: frame, bass: frame, other: frame),
            sampleCount: sampleCount
        )
    }
}

/// StemAnalyzer stub: returns fixed non-zero StemFeatures.
private final class StubStemAnalyzer: StemAnalyzing, @unchecked Sendable {
    var fixedFeatures = StemFeatures(
        vocalsEnergy: 0.3, vocalsBand0: 0.2, vocalsBand1: 0.1, vocalsBeat: 0,
        drumsEnergy: 0.5, drumsBand0: 0.4, drumsBand1: 0.3, drumsBeat: 0.1,
        bassEnergy: 0.4, bassBand0: 0.3, bassBand1: 0.2, bassBeat: 0,
        otherEnergy: 0.2, otherBand0: 0.1, otherBand1: 0.05, otherBeat: 0
    )
    private(set) var analyzeCallCount = 0
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures {
        analyzeCallCount += 1
        return fixedFeatures
    }
    func reset() {}
}

/// Preview resolver stub: returns a configurable URL or nil.
private final class StubPreviewResolver: PreviewResolving, @unchecked Sendable {
    var urlToReturn: URL? = URL(string: "https://example.com/preview.m4a")
    var shouldThrow = false
    var delayNanoseconds: UInt64 = 0

    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return urlToReturn
    }
}

/// Preview downloader stub: returns a configurable PreviewAudio or nil.
private final class StubPreviewDownloader: PreviewDownloading, @unchecked Sendable {
    var audioToReturn: PreviewAudio?
    var shouldReturnNil = false

    init(sampleRate: Int = 44100, durationSeconds: Double = 1.0) {
        let count = Int(Double(sampleRate) * durationSeconds)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = 0.05 * sin(2.0 * .pi * 440.0 * Float(i) / Float(sampleRate))
        }
        audioToReturn = PreviewAudio(
            trackIdentity: TrackIdentity(title: "Stub", artist: "Artist"),
            pcmSamples: samples,
            sampleRate: sampleRate,
            duration: durationSeconds
        )
    }

    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        guard !shouldReturnNil, var audio = audioToReturn else { return nil }
        audio = PreviewAudio(
            trackIdentity: track,
            pcmSamples: audio.pcmSamples,
            sampleRate: audio.sampleRate,
            duration: audio.duration
        )
        return audio
    }

    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] {
        await withTaskGroup(of: PreviewAudio?.self) { group in
            for (track, url) in tracks {
                group.addTask { await self.download(track: track, from: url) }
            }
            var results: [PreviewAudio] = []
            for await r in group { if let r { results.append(r) } }
            return results
        }
    }
}

// MARK: - Helpers

private func makeTrack(_ title: String, artist: String = "Test Artist") -> TrackIdentity {
    TrackIdentity(title: title, artist: artist)
}

@MainActor
private func makePreparer(
    resolver: StubPreviewResolver = StubPreviewResolver(),
    downloader: StubPreviewDownloader = StubPreviewDownloader(),
    separator: StubStemSeparator,
    analyzer: StubStemAnalyzer = StubStemAnalyzer(),
    classifier: MockMoodClassifier = MockMoodClassifier()
) -> SessionPreparer {
    SessionPreparer(
        resolver: resolver,
        downloader: downloader,
        stemSeparator: separator,
        stemAnalyzer: analyzer,
        moodClassifier: classifier
    )
}

// MARK: - Suite

@Suite("SessionPreparer")
@MainActor
struct SessionPreparerTests {

    // MARK: - Cache Population

    @Test func prepare_singleTrack_populatesCache() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let separator = try StubStemSeparator(device: device)
        let preparer = makePreparer(separator: separator)
        let track = makeTrack("So What")

        let result = await preparer.prepare(tracks: [track])

        #expect(result.cachedTracks.count == 1)
        #expect(result.failedTracks.isEmpty)
        #expect(result.cachedTracks.first == track)

        let cached = result.cache.loadForPlayback(track: track)
        #expect(cached != nil)
        #expect(cached?.stemWaveforms.count == 4)
        #expect(cached?.stemFeatures != .zero)
        #expect(cached?.trackProfile != nil)
    }

    @Test func prepare_multipleTracks_allCached() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let separator = try StubStemSeparator(device: device)
        let preparer = makePreparer(separator: separator)
        let tracks = (0..<3).map { makeTrack("Track \($0)") }

        let result = await preparer.prepare(tracks: tracks)

        #expect(result.cachedTracks.count == 3)
        #expect(result.failedTracks.isEmpty)
        for track in tracks {
            #expect(result.cache.loadForPlayback(track: track) != nil)
        }
    }

    // MARK: - Failure Handling

    @Test func prepare_missingPreview_skipsThatTrack() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let separator = try StubStemSeparator(device: device)
        let resolver = StubPreviewResolver()
        resolver.urlToReturn = nil  // No preview for this track

        let preparer = makePreparer(resolver: resolver, separator: separator)
        let track = makeTrack("No Preview Track")

        let result = await preparer.prepare(tracks: [track])

        #expect(result.cachedTracks.isEmpty)
        #expect(result.failedTracks.count == 1)
        #expect(result.failedTracks.first == track)
        #expect(result.cache.loadForPlayback(track: track) == nil)
    }

    // MARK: - Progress

    @Test func prepare_publishesProgress() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let separator = try StubStemSeparator(device: device)
        let preparer = makePreparer(separator: separator)
        let tracks = [makeTrack("A"), makeTrack("B")]

        #expect(preparer.progress == (0, 0))
        _ = await preparer.prepare(tracks: tracks)

        // After completion, progress reflects all tracks processed.
        #expect(preparer.progress.0 == tracks.count)
        #expect(preparer.progress.1 == tracks.count)
    }

    // MARK: - Cancellation

    @Test func prepare_cancellation_stopsCleanly() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let separator = try StubStemSeparator(device: device)
        let resolver = StubPreviewResolver()
        // 500ms per resolution — long enough that cancellation fires first.
        resolver.delayNanoseconds = 500_000_000

        let preparer = makePreparer(resolver: resolver, separator: separator)
        let tracks = (0..<5).map { makeTrack("Slow Track \($0)") }

        let task = Task { @MainActor in
            await preparer.prepare(tracks: tracks)
        }

        // Cancel after 50ms — before the first resolution completes.
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let result = await task.value
        // Must not crash. At most 0 tracks cached (cancelled before any complete).
        let processed = result.cachedTracks.count + result.failedTracks.count
        #expect(processed < tracks.count)
    }
}

// MARK: - StemCache Tests (non-MainActor, stand-alone)

@Suite("StemCache")
struct StemCacheTests {

    private func makeCachedData() -> CachedTrackData {
        let waveforms: [[Float]] = (0..<4).map { _ in
            [Float](repeating: 0.1, count: 1024)
        }
        return CachedTrackData(
            stemWaveforms: waveforms,
            stemFeatures: StemFeatures(
                vocalsEnergy: 0.3, vocalsBand0: 0.2, vocalsBand1: 0.1, vocalsBeat: 0,
                drumsEnergy: 0.5, drumsBand0: 0.4, drumsBand1: 0.3, drumsBeat: 0.1,
                bassEnergy: 0.4, bassBand0: 0.3, bassBand1: 0.2, bassBeat: 0,
                otherEnergy: 0.2, otherBand0: 0.1, otherBand1: 0.05, otherBeat: 0
            ),
            trackProfile: TrackProfile(bpm: 120, key: "C major", mood: .neutral)
        )
    }

    @Test func loadForPlayback_returnsCorrectTrack() {
        let cache = StemCache()
        let track = TrackIdentity(title: "So What", artist: "Miles Davis")
        let data = makeCachedData()

        cache.store(data, for: track)

        let loaded = cache.loadForPlayback(track: track)
        #expect(loaded != nil)
        #expect(loaded?.trackProfile.bpm == 120)
        #expect(loaded?.trackProfile.key == "C major")
        #expect(loaded?.stemWaveforms.count == 4)
    }

    @Test func unknownTrack_returnsNil() {
        let cache = StemCache()
        let track = TrackIdentity(title: "Unknown", artist: "Nobody")

        #expect(cache.loadForPlayback(track: track) == nil)
        #expect(cache.stemFeatures(for: track) == nil)
        #expect(cache.trackProfile(for: track) == nil)
    }

    @Test func threadSafety_concurrentAccess() async {
        let cache = StemCache()
        let data = makeCachedData()

        // 50 concurrent writers + 50 concurrent readers — no crash = pass.
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                let track = TrackIdentity(title: "Track \(i)", artist: "Artist")
                group.addTask { cache.store(data, for: track) }
                group.addTask { _ = cache.loadForPlayback(track: track) }
            }
        }

        // Some entries should be present.
        #expect(cache.count > 0)
    }
}

// BeatGridIntegrationTests — DSP.2 S6 SessionPreparer integration.
//
// Exercises the wiring between SessionPreparer, BeatGridAnalyzing, and
// CachedTrackData.beatGrid. Algorithm correctness is covered by the S5
// BeatGridResolver golden fixture suite; these tests prove the pipeline
// glue (nil-default, cache hit short-circuit, real-analyzer roundtrip,
// new StemCache.beatGrid(for:) accessor).

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import ML
@testable import Shared
@testable import Session

// MARK: - Helpers

private func makeSinePreview(
    track: TrackIdentity,
    sampleRate: Int = 44100,
    durationSeconds: Double = 5.0
) -> PreviewAudio {
    let count = Int(Double(sampleRate) * durationSeconds)
    var samples = [Float](repeating: 0, count: count)
    for i in 0..<count {
        samples[i] = 0.25 * sin(2.0 * .pi * 440.0 * Float(i) / Float(sampleRate))
    }
    return PreviewAudio(
        trackIdentity: track,
        pcmSamples: samples,
        sampleRate: sampleRate,
        duration: durationSeconds
    )
}

private final class FixedURLResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        URL(string: "https://example.com/preview.m4a")
    }
}

private final class SinePreviewDownloader: PreviewDownloading, @unchecked Sendable {
    let sampleRate: Int
    let duration: Double
    init(sampleRate: Int = 44100, duration: Double = 5.0) {
        self.sampleRate = sampleRate
        self.duration = duration
    }
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        makeSinePreview(track: track, sampleRate: sampleRate, durationSeconds: duration)
    }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] {
        tracks.map { (track, _) in
            makeSinePreview(track: track, sampleRate: sampleRate, durationSeconds: duration)
        }
    }
}

private final class StubSeparator: StemSeparating, @unchecked Sendable {
    let stemLabels: [String] = ["vocals", "drums", "bass", "other"]
    let stemBuffers: [UMABuffer<Float>]
    let sampleCount = 4096
    init(device: MTLDevice) throws {
        stemBuffers = try (0..<4).map { _ in
            try UMABuffer<Float>(device: device, capacity: 44100)
        }
        for buf in stemBuffers {
            var samples = [Float](repeating: 0, count: 4096)
            for i in 0..<4096 {
                samples[i] = 0.1 * sin(Float(i) * 0.01)
            }
            buf.write(samples)
        }
    }
    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
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

private final class StubAnalyzer: StemAnalyzing, @unchecked Sendable {
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

private final class CountingBeatGridAnalyzer: BeatGridAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int { lock.withLock { _callCount } }
    func analyzeBeatGrid(samples: [Float], sampleRate: Double) -> BeatGrid {
        lock.withLock { _callCount += 1 }
        return .empty
    }
}

private enum BeatGridIntegrationTestError: Error {
    case noMetalDevice
}

// MARK: - Tests

/// With no analyzer wired (default `nil`), CachedTrackData.beatGrid is `.empty`.
@Test
@MainActor
func nilAnalyzer_producesEmptyBeatGrid() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
    let separator = try StubSeparator(device: device)

    let preparer = SessionPreparer(
        resolver: FixedURLResolver(),
        downloader: SinePreviewDownloader(),
        stemSeparator: separator,
        stemAnalyzer: StubAnalyzer(),
        moodClassifier: MoodClassifier()
    )

    let track = TrackIdentity(title: "Nil Analyzer", artist: "Test")
    let result = await preparer.prepare(tracks: [track])

    let cached = result.cache.loadForPlayback(track: track)
    #expect(cached != nil)
    #expect(cached?.beatGrid == .empty)
}

/// A second `prepare(tracks:)` call on the same preparer + cache must not
/// re-invoke the analyzer — the cache-hit short-circuit guards expensive work.
@Test
@MainActor
func cacheHit_skipsAnalyzer() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
    let separator = try StubSeparator(device: device)
    let counting = CountingBeatGridAnalyzer()

    let preparer = SessionPreparer(
        resolver: FixedURLResolver(),
        downloader: SinePreviewDownloader(),
        stemSeparator: separator,
        stemAnalyzer: StubAnalyzer(),
        moodClassifier: MoodClassifier(),
        beatGridAnalyzer: counting
    )

    let track = TrackIdentity(title: "Cache Hit", artist: "Test")

    _ = await preparer.prepare(tracks: [track])
    #expect(counting.callCount == 1, "First prepare should call analyzer once")

    _ = await preparer.prepare(tracks: [track])
    #expect(counting.callCount == 1, "Second prepare should short-circuit on cache hit")
}

/// Full pipeline with real DefaultBeatGridAnalyzer must produce a non-empty
/// BeatGrid (frameCount > 0). A 440 Hz sine has no realistic beats so we
/// don't assert beat counts — only that the pipeline ran.
@Test
@MainActor
func fullPipeline_withRealAnalyzer_beatGridNonEmpty() async throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw BeatGridIntegrationTestError.noMetalDevice
    }

    let track = TrackIdentity(title: "Real Analyzer", artist: "Test")
    let resolver = FixedURLResolver()
    let downloader = SinePreviewDownloader(sampleRate: 44100, duration: 10.0)

    let separator = try StemSeparator(device: device)
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let classifier = MoodClassifier()
    let gridAnalyzer = try DefaultBeatGridAnalyzer(device: device)

    let preparer = SessionPreparer(
        resolver: resolver,
        downloader: downloader,
        stemSeparator: separator,
        stemAnalyzer: analyzer,
        moodClassifier: classifier,
        beatGridAnalyzer: gridAnalyzer
    )

    let result = await preparer.prepare(tracks: [track])

    let cached = try #require(result.cache.loadForPlayback(track: track))
    #expect(cached.beatGrid != .empty, "BeatGrid should not be the empty sentinel")
    #expect(cached.beatGrid.frameCount > 0, "BeatGrid should have a non-zero frame count")
    #expect(cached.beatGrid.frameRate == 50.0, "Beat This! frame rate is fixed at 50.0 fps")
}

/// `StemCache.beatGrid(for:)` returns the BeatGrid stored on `CachedTrackData`.
@Test
func cacheAccessor_beatGrid_matchesCachedTrackData() {
    let cache = StemCache()
    let track = TrackIdentity(title: "Accessor Test", artist: "Test")
    let grid = BeatGrid(
        beats: [0.5, 1.0, 1.5, 2.0],
        downbeats: [0.5, 2.0],
        bpm: 120.0,
        beatsPerBar: 3,
        barConfidence: 1.0,
        frameRate: 50.0,
        frameCount: 100
    )
    let data = CachedTrackData(
        stemWaveforms: [],
        stemFeatures: .zero,
        trackProfile: .empty,
        beatGrid: grid
    )
    cache.store(data, for: track)

    let recalled = cache.beatGrid(for: track)
    #expect(recalled == grid)
}

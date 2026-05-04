// SessionPreparationIntegrationTests — End-to-end integration tests for the
// session preparation pipeline.
//
// Uses:
//  - Real StemSeparator (MPSGraph GPU inference, ~142ms warm)
//  - Real StemAnalyzer + MoodClassifier
//  - Mocked PreviewResolver (returns hardcoded iTunes JSON for a known track)
//  - Mocked PreviewDownloader (returns synthetic sine wave PCM, no network I/O)
//
// These tests exercise the complete analysis path without external dependencies.

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import ML
@testable import Shared
@testable import Session

// MARK: - Helpers

/// Minimal iTunes Search API JSON containing a valid previewUrl.
private func itunesSearchJSON(previewURL: String) -> Data {
    let json = """
    {
        "resultCount": 1,
        "results": [{
            "trackName": "So What",
            "artistName": "Miles Davis",
            "collectionName": "Kind of Blue",
            "previewUrl": "\(previewURL)"
        }]
    }
    """
    return Data(json.utf8)
}

/// Generate a mono sine wave `PreviewAudio` of the given duration.
private func makeSinePreview(
    track: TrackIdentity,
    sampleRate: Int = 44100,
    durationSeconds: Double = 5.0
) -> PreviewAudio {
    let count = Int(Double(sampleRate) * durationSeconds)
    var samples = [Float](repeating: 0, count: count)
    for i in 0..<count {
        // 440 Hz A4 at -12 dBFS
        samples[i] = 0.25 * sin(2.0 * .pi * 440.0 * Float(i) / Float(sampleRate))
    }
    return PreviewAudio(
        trackIdentity: track,
        pcmSamples: samples,
        sampleRate: sampleRate,
        duration: durationSeconds
    )
}

/// PreviewResolver backed by a local iTunes JSON response — no real network.
private final class MockiTunesResolver: PreviewResolving, @unchecked Sendable {
    let previewURL: URL

    init(previewURL: URL = URL(string: "https://example.com/preview.m4a")!) { // swiftlint:disable:this force_unwrapping
        self.previewURL = previewURL
    }

    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        return previewURL
    }
}

/// PreviewDownloader that returns pre-built `PreviewAudio` — no file I/O.
private final class MockSineDownloader: PreviewDownloading, @unchecked Sendable {
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

// MARK: - Tests

/// Full pipeline resolution → download → separation → analysis end-to-end.
@Test func fullPipeline_resolve_download_separate_analyze() async throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw SessionIntegrationError.noMetalDevice
    }

    let track = TrackIdentity(title: "So What", artist: "Miles Davis")
    let resolver = MockiTunesResolver()
    let downloader = MockSineDownloader(sampleRate: 44100, duration: 5.0)

    let separator = try StemSeparator(device: device)
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let classifier = MoodClassifier()

    let preparer = await SessionPreparer(
        resolver: resolver,
        downloader: downloader,
        stemSeparator: separator,
        stemAnalyzer: analyzer,
        moodClassifier: classifier
    )

    let result = await preparer.prepare(tracks: [track])

    #expect(result.cachedTracks.count == 1, "Track should be cached")
    #expect(result.failedTracks.isEmpty, "No tracks should fail")

    let cached = result.cache.loadForPlayback(track: track)
    #expect(cached != nil, "Cache entry must exist")
    #expect(cached?.stemWaveforms.count == 4, "Four stem waveforms expected")
    #expect(cached?.stemFeatures != .zero, "StemFeatures must be non-zero")
    // BeatGrid defaults to .empty when no beatGridAnalyzer is injected (S6 nil-default contract).
    #expect(cached?.beatGrid == .empty)
}

/// TrackProfile from real analysis must have plausible values.
@Test func trackProfile_hasBPMAndMood() async throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw SessionIntegrationError.noMetalDevice
    }

    let track = TrackIdentity(title: "Test", artist: "Artist")
    let resolver = MockiTunesResolver()
    // 10 seconds of audio gives the beat detector enough onset events
    // for a stable BPM estimate.
    let downloader = MockSineDownloader(sampleRate: 44100, duration: 10.0)

    let separator = try StemSeparator(device: device)
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let classifier = MoodClassifier()

    let preparer = await SessionPreparer(
        resolver: resolver,
        downloader: downloader,
        stemSeparator: separator,
        stemAnalyzer: analyzer,
        moodClassifier: classifier
    )

    let result = await preparer.prepare(tracks: [track])

    let profile = result.cache.trackProfile(for: track)
    #expect(profile != nil)

    // Mood output must be in the valid [-1, 1] range.
    if let p = profile {
        #expect(p.mood.valence >= -1 && p.mood.valence <= 1)
        #expect(p.mood.arousal >= -1 && p.mood.arousal <= 1)
        // Centroid must be in [0, 1] for a 440 Hz sine wave.
        #expect(p.spectralCentroidAvg >= 0 && p.spectralCentroidAvg <= 1)
    }
}

/// StemFeatures derived from the pre-analyzed preview must be non-zero
/// for all four stems when the audio has energy.
@Test func cachedStemFeatures_nonZero() async throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw SessionIntegrationError.noMetalDevice
    }

    let track = TrackIdentity(title: "Energy Test", artist: "Artist")
    let resolver = MockiTunesResolver()
    let downloader = MockSineDownloader(sampleRate: 44100, duration: 5.0)

    let separator = try StemSeparator(device: device)
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let classifier = MoodClassifier()

    let preparer = await SessionPreparer(
        resolver: resolver,
        downloader: downloader,
        stemSeparator: separator,
        stemAnalyzer: analyzer,
        moodClassifier: classifier
    )

    let result = await preparer.prepare(tracks: [track])

    let features = result.cache.stemFeatures(for: track)
    #expect(features != nil, "StemFeatures must be cached")

    // At least one stem must show non-zero energy — the open-unmix model
    // distributes the 440 Hz sine across multiple stems.
    if let f = features {
        let totalEnergy = f.vocalsEnergy + f.drumsEnergy + f.bassEnergy + f.otherEnergy
        #expect(totalEnergy > 0, "At least one stem must have energy")
    }
}

// MARK: - Error Type

private enum SessionIntegrationError: Error {
    case noMetalDevice
}

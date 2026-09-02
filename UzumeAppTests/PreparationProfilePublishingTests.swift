// PreparationProfilePublishingTests — the App layer can see what Uzume heard. (DS.4 task 3)
//
// `TrackPreparationStatus` carries only the stage; `TrackProfile` reaches the App layer
// through `PreparationProgressPublishing.trackProfilesPublisher`. This drives the
// production `SessionPreparer` through the protocol the views consume, and checks that
// a track reaching `.ready` arrives with its bpm, mood and stem balance attached.

import Audio
import Combine
import DSP
import Foundation
import ML
import Session
import Shared
import Testing
@testable import UzumeApp

// MARK: - Stubs (no network, no ML — the cache-hit path is enough to reach .ready)

private final class NoPreviewResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? { nil }
}

private final class NoDownloader: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? { nil }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}

private final class NoSeparator: StemSeparating, @unchecked Sendable {
    let stemLabels = ["vocals", "drums", "bass", "other"]
    var stemBuffers: [UMABuffer<Float>] { [] }
    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        throw StemSeparationError.modelNotFound
    }
}

private final class NoAnalyzer: StemAnalyzing, @unchecked Sendable {
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures { .zero }
    func reset() {}
}

private final class NoClassifier: MoodClassifying, @unchecked Sendable {
    var currentState: EmotionalState = .neutral
    func classify(features: [Float], deltaTime: Float) throws -> EmotionalState { .neutral }
}

// MARK: - Suite

@Suite("Preparation profile publishing")
@MainActor
struct PreparationProfilePublishingTests {

    @Test("a track that reaches .ready publishes bpm, mood and stem balance")
    func readyTrack_publishesProfile() async throws {
        let heard = TrackIdentity(title: "Heartbeats", artist: "The Knife")
        let missing = TrackIdentity(title: "No Preview", artist: "Nobody")

        var balance = StemFeatures.zero
        balance.drumsEnergy = 0.7
        balance.vocalsEnergy = 0.2
        let profile = TrackProfile(
            bpm: 124,
            key: "F# minor",
            mood: EmotionalState(valence: -0.3, arousal: 0.8),
            spectralCentroidAvg: 0.61,
            stemEnergyBalance: balance
        )
        let cache = StemCache()
        cache.store(
            CachedTrackData(stemWaveforms: [[], [], [], []], stemFeatures: balance, trackProfile: profile),
            for: heard
        )

        let preparer = SessionPreparer(
            resolver: NoPreviewResolver(),
            downloader: NoDownloader(),
            stemSeparator: NoSeparator(),
            stemAnalyzer: NoAnalyzer(),
            moodClassifier: NoClassifier(),
            cache: cache,
            prewarmModels: false
        )
        let publishing: any PreparationProgressPublishing = preparer

        // Observe through the protocol, as the view model does.
        var seenAtReady: TrackProfile?
        let watch = publishing.trackStatusesPublisher.sink { statuses in
            if statuses[heard] == .ready, seenAtReady == nil {
                seenAtReady = publishing.trackProfiles[heard]
            }
        }
        defer { watch.cancel() }

        _ = await preparer.prepare(tracks: [heard, missing])

        let seen = try #require(seenAtReady, "profile must be readable the moment the status is .ready")
        #expect(seen.bpm == 124)
        #expect(seen.mood.quadrant == .tense)
        #expect(seen.stemEnergyBalance.drumsEnergy == 0.7)
        #expect(publishing.trackProfiles[missing] == nil, "a failed track has nothing heard")
    }
}

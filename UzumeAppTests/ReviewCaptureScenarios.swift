// ReviewCaptureScenarios — the preparation states the review harness renders. (DS.4)
//
// Split from ReviewCaptureHarness.swift for the file-length gate. Scenarios are the
// same before and after DS.4; the build-specific half (appearances, declared row
// labels) is ReviewCaptureHarness+Preparation.swift.

import Combine
import Session
import Shared
import SwiftUI
@testable import UzumeApp

// MARK: - Preparation scenarios (DS.4)

/// A scripted set of per-track statuses and the readiness level `SessionManager`
/// would derive from them — the two inputs `PreparationProgressView` is driven by.
struct PreparationScenario {
    let name: String
    let tracks: [TrackIdentity]
    let statuses: [TrackPreparationStatus]
    let readiness: ProgressiveReadinessLevel
    /// What the scenario's `.ready` tracks were heard to be (DS.4). Ignored by a
    /// build whose publisher carries no profiles.
    let profiles: [TrackProfile?]

    /// A playlist with enough character to make the two views differ.
    static let playlist: [TrackIdentity] = [
        TrackIdentity(title: "Hum Of Maybe", artist: "Apparat"),
        TrackIdentity(title: "God Is Lonelier", artist: "Felsmann + Tiley"),
        TrackIdentity(title: "Single Cell", artist: "Glückskind"),
        TrackIdentity(title: "Ride", artist: "Klangkarussell"),
        TrackIdentity(title: "Lens of Wisdom", artist: "Icare Sandilas"),
        TrackIdentity(title: "Discussion with a Giant", artist: "Thylacine"),
        TrackIdentity(title: "What I Can Do", artist: "CØNTRA"),
        TrackIdentity(title: "Heartbeats", artist: "The Knife"),
    ]

    static let heard: [TrackProfile] = [
        profile(118, "A minor", EmotionalState(valence: 0.2, arousal: -0.3), centroid: 0.38, drums: 0.35, vocals: 0.55),
        profile(124, "F# minor", EmotionalState(valence: -0.4, arousal: 0.6), centroid: 0.52, drums: 0.6, vocals: 0.3),
        profile(96, "D major", EmotionalState(valence: 0.5, arousal: -0.5), centroid: 0.3, drums: 0.25, vocals: 0.2),
        profile(126, "G minor", EmotionalState(valence: 0.6, arousal: 0.7), centroid: 0.66, drums: 0.7, vocals: 0.4),
        profile(88, "C major", EmotionalState(valence: 0.3, arousal: -0.6), centroid: 0.28, drums: 0.2, vocals: 0.5),
        profile(122, "E minor", EmotionalState(valence: -0.2, arousal: 0.4), centroid: 0.48, drums: 0.55, vocals: 0.35),
        profile(110, "B minor", EmotionalState(valence: -0.5, arousal: -0.2), centroid: 0.35, drums: 0.3, vocals: 0.6),
        profile(124, "F# minor", EmotionalState(valence: -0.3, arousal: 0.8), centroid: 0.61, drums: 0.7, vocals: 0.2),
    ]

    // swiftlint:disable:next function_parameter_count
    static func profile(_ bpm: Float, _ key: String, _ mood: EmotionalState,
                        centroid: Float, drums: Float, vocals: Float) -> TrackProfile {
        var balance = StemFeatures.zero
        balance.drumsEnergy = drums
        balance.vocalsEnergy = vocals
        balance.bassEnergy = 0.4
        balance.otherEnergy = 0.3
        return TrackProfile(
            bpm: bpm,
            key: key,
            mood: mood,
            spectralCentroidAvg: centroid,
            stemEnergyBalance: balance
        )
    }

    private static func make(
        _ name: String,
        _ statuses: [TrackPreparationStatus],
        _ readiness: ProgressiveReadinessLevel
    ) -> PreparationScenario {
        let profiles: [TrackProfile?] = statuses.enumerated().map { index, status in
            status == .ready ? heard[index] : nil
        }
        return PreparationScenario(
            name: name,
            tracks: playlist,
            statuses: statuses,
            readiness: readiness,
            profiles: profiles
        )
    }

    static let all: [PreparationScenario] = [
        make("preparation-early",
             [.resolving, .downloading(progress: -1), .downloading(progress: 0.4),
              .queued, .queued, .queued, .queued, .queued],
             .preparing),
        make("preparation-mid",
             [.ready, .ready, .analyzing(stage: .stemSeparation), .downloading(progress: 0.6),
              .downloading(progress: -1), .resolving, .queued, .queued],
             .preparing),
        make("preparation-threeReady",
             [.ready, .ready, .ready, .analyzing(stage: .caching),
              .downloading(progress: 0.2), .resolving, .queued, .queued],
             .readyForFirstTracks),
        make("preparation-halfway",
             [.ready, .ready, .ready, .ready, .ready,
              .analyzing(stage: .stemSeparation), .downloading(progress: -1), .queued],
             .partiallyPlanned),
        make("preparation-previewNotFound",
             [.ready, .failed(reason: "Preview not available"), .ready, .ready,
              .analyzing(stage: .stemSeparation), .queued, .queued, .queued],
             .preparing),
        make("preparation-stemSeparationFailed",
             [.ready, .ready, .partial(reason: "Stems unavailable"), .ready,
              .downloading(progress: 0.7), .queued, .queued, .queued],
             .preparing),
        // The banner: PreparationErrorViewModel raises .previewRateLimited on a .partial
        // whose reason mentions "rate". No production path emits one — recorded in
        // CAPTURES.md; rendered so the slot is evidenced in place.
        make("preparation-banner",
             [.ready, .partial(reason: "Rate limited"), .downloading(progress: -1),
              .queued, .queued, .queued, .queued, .queued],
             .preparing),
        make("preparation-recovery",
             Array(repeating: .failed(reason: "Preview not available"), count: 8),
             .reactiveFallback),
    ]

    // MARK: View

    @MainActor
    func makeView() -> AnyView {
        let publisher = ScriptedPreparationPublisher(tracks: tracks, statuses: statuses, profiles: profiles)
        let view = PreparationProgressView(
            publisher: publisher,
            tracks: tracks,
            progressiveReadinessPublisher: Just(readiness).eraseToAnyPublisher(),
            reachability: AlwaysOnlineReachability(),
            onCancel: {},
            onStartNow: {}
        )
        return AnyView(view.frame(width: 900, height: 600))
    }

    // MARK: Accessibility rows

    /// What each preparation element DECLARES to VoiceOver, per status. Read off the
    /// components so a copy change shows up here as well as on screen.
    @MainActor
    static func accessibilityRows() -> [String] {
        var rows = ["element\tdeclared VoiceOver label\tdeclared value\taccessibility identifier"]
        rows.append("preparing view (container)\t(no explicit label)\t\t\(PreparationProgressView.accessibilityID)")
        rows.append("cancel button\tCancel\t\t\(PreparationProgressView.cancelButtonID)")
        let startNow = String(format: String(localized: "preparation.start_now_button_with_count"), 3)
        rows.append("start now button\t\(startNow)\t\t\(PreparationProgressView.startNowButtonID)")
        rows.append(contentsOf: PreparationRowAccessibility.rows(tracks: playlist, heard: heard))
        rows.append(contentsOf: PreparationScreenAccessibility.rows())
        return rows
    }
}

// MARK: - Capture variants

/// How the preparation view is wrapped for a capture. The pre-DS.4 build has one
/// appearance; DS.4 renders each scenario once per preference.
struct PreparationCaptureVariant {
    let suffix: String
    let preference: PreparationViewPreference?

    static let all: [PreparationCaptureVariant] = PreparationCaptureVariants.all

    func filename(for scenario: String) -> String {
        suffix.isEmpty ? scenario : "\(scenario)-\(suffix)"
    }

    @MainActor
    func wrap(_ view: AnyView) -> AnyView {
        PreparationCaptureVariants.wrap(view, preference: preference)
    }
}

// MARK: - Test doubles

/// Plays back a fixed status (and profile) dictionary through the protocol
/// `SessionPreparer` implements.
@MainActor
final class ScriptedPreparationPublisher: PreparationProgressPublishing {
    let trackStatuses: [TrackIdentity: TrackPreparationStatus]
    let trackProfiles: [TrackIdentity: TrackProfile]

    init(tracks: [TrackIdentity], statuses: [TrackPreparationStatus], profiles: [TrackProfile?]) {
        trackStatuses = Dictionary(uniqueKeysWithValues: zip(tracks, statuses))
        var heard: [TrackIdentity: TrackProfile] = [:]
        for (track, profile) in zip(tracks, profiles) {
            if let profile { heard[track] = profile }
        }
        trackProfiles = heard
    }

    var trackStatusesPublisher: AnyPublisher<[TrackIdentity: TrackPreparationStatus], Never> {
        Just(trackStatuses).eraseToAnyPublisher()
    }

    var trackProfilesPublisher: AnyPublisher<[TrackIdentity: TrackProfile], Never> {
        Just(trackProfiles).eraseToAnyPublisher()
    }

    func cancelPreparation() {}
}

final class AlwaysOnlineReachability: ReachabilityPublishing {
    var isOnlinePublisher: AnyPublisher<Bool, Never> { Just(true).eraseToAnyPublisher() }
    var isOnline: Bool { true }
}

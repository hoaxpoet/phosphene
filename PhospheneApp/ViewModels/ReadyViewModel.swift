// ReadyViewModel — Observable state for ReadyView (Increment U.5).
//
// Responsibilities:
//   1. Surface source-aware headline copy (Apple Music / Spotify / fallback).
//   2. Own FirstAudioDetector and emit shouldAdvanceToPlaying when sustained
//      audio is confirmed (>.250 ms in .active state).
//   3. Run a 90-second timeout; surface isTimedOut for the overlay card.
//   4. Forward retry() and endSession() to the appropriate subsystems.
//   5. Publish trackCount and estimatedDuration (updated when the plan arrives
//      via planPublisher).
//
// Pre-flight audit finding (U.5): livePlannedSession is set synchronously in
// buildPlan(), which fires from the sessionManager.$state .ready sink before
// SwiftUI re-renders ReadyView. Initial track/duration values come from the
// plan publisher; ReadyViewModel subscribes to update them if the plan changes
// (e.g., after regeneratePlan() in Part D).

import Audio
import Combine
import Foundation
import Orchestrator
import Session
import SwiftUI

// MARK: - ReadyViewModel

/// ViewModel for `ReadyView`.
///
/// Inject dependencies via `init`; all properties drive the view declaratively.
@MainActor
final class ReadyViewModel: ObservableObject {

    // MARK: - Published State

    /// Display name for the music source ("Apple Music", "Spotify", or "your music app").
    @Published private(set) var sourceName: String

    /// Number of tracks in the planned session. Updates if the plan is regenerated.
    @Published private(set) var trackCount: Int

    /// Total planned duration in seconds. Updates if the plan is regenerated.
    @Published private(set) var estimatedDuration: TimeInterval

    /// True once sustained audio has been confirmed (≥250 ms in `.active`).
    @Published private(set) var hasDetectedAudio: Bool = false

    /// True after 90 seconds with no audio detected. Surfaces the timeout card.
    @Published private(set) var isTimedOut: Bool = false

    /// False until Part B lands; gates the "Preview the plan" CTA.
    /// TODO(U.5.B): flip to true once PlanPreviewView is wired.
    @Published var planPreviewEnabled: Bool = true

    /// Honours the system reduced-motion preference. Forwarded to pulsing border.
    @Published private(set) var reduceMotion: Bool

    // MARK: - Signals

    /// Emits once when first-audio is confirmed. `ReadyView` observes this to
    /// call `sessionManager.beginPlayback()`.
    let shouldAdvanceToPlaying = PassthroughSubject<Void, Never>()

    // MARK: - Private

    private let firstAudioDetector: FirstAudioDetector
    private let sessionManager: SessionManager
    private var timeoutTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    /// Create the ViewModel.
    ///
    /// - Parameters:
    ///   - sessionSource: The `PlaylistSource` that originated this session.
    ///   - sessionManager: The lifecycle manager; used for `beginPlayback` / `endSession`.
    ///   - audioSignalStatePublisher: Publishes `AudioSignalState` transitions from the engine.
    ///   - planPublisher: Publishes updated `PlannedSession` values (nil = no plan/reactive mode).
    ///   - reduceMotion: Initial reduced-motion state; not live-updated (U.9 wires the full path).
    init(
        sessionSource: PlaylistSource?,
        sessionManager: SessionManager,
        audioSignalStatePublisher: AnyPublisher<AudioSignalState, Never>,
        planPublisher: AnyPublisher<PlannedSession?, Never>,
        reduceMotion: Bool
    ) {
        self.sourceName = sessionSource?.displayName ?? "your music app"
        self.sessionManager = sessionManager
        self.reduceMotion = reduceMotion
        self.firstAudioDetector = FirstAudioDetector(
            audioSignalStatePublisher: audioSignalStatePublisher
        )

        // Seed initial track count / duration from plan if already available.
        // The plan is typically built before ReadyView appears, so the publisher
        // fires its current value synchronously on subscription.
        self.trackCount = 0
        self.estimatedDuration = 0

        subscribeToPlan(planPublisher)
        subscribeToAudioDetector()
        scheduleTimeout()
    }

    // MARK: - Actions

    /// Reset the detector and 90-second timer; dismiss the timeout overlay.
    func retry() {
        firstAudioDetector.reset()
        hasDetectedAudio = false
        isTimedOut = false
        subscribeToAudioDetector()
        scheduleTimeout()
    }

    /// End the session and transition state to `.ended`.
    func endSession() {
        sessionManager.endSession()
    }

    // MARK: - Private

    private func subscribeToPlan(_ publisher: AnyPublisher<PlannedSession?, Never>) {
        publisher
            .compactMap { $0 }
            .sink { [weak self] plan in
                self?.trackCount = plan.tracks.count
                self?.estimatedDuration = plan.totalDuration
            }
            .store(in: &cancellables)
    }

    private func subscribeToAudioDetector() {
        firstAudioDetector.$hasDetectedAudio
            .first(where: { $0 })
            .sink { [weak self] _ in
                guard let self else { return }
                hasDetectedAudio = true
                timeoutTask?.cancel()
                shouldAdvanceToPlaying.send()
            }
            .store(in: &cancellables)
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            self?.isTimedOut = true
        }
    }
}

// MARK: - Formatting Helpers

extension ReadyViewModel {

    /// e.g. "about 24 minutes" or "about 1 hour 12 minutes"
    var formattedDuration: String {
        guard estimatedDuration > 0 else { return "" }
        let total = Int(estimatedDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "about \(hours) hr \(minutes) min"
        }
        return "about \(max(1, minutes)) min"
    }
}

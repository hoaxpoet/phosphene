// ReadyViewModel — Observable state for ReadyView (Increment U.5; DS.5 / D-240).
//
// Responsibilities:
//   1. Surface source-aware headline copy (Apple Music / Spotify / fallback) from the
//      session's `SessionOrigin` — not just its `PlaylistSource`, which is nil for
//      every local-file origin and used to leave local sessions reading
//      "press play in your music app" (DS.5 fixed the routing; this type now knows).
//   2. Own FirstAudioDetector and emit shouldAdvanceToPlaying when sustained
//      audio is confirmed (>.250 ms in .active state), or when the listener asks
//      to begin now.
//   3. Run a 90-second timeout; surface isTimedOut for the overlay card.
//   4. Forward retry() and endSession() to the appropriate subsystems.
//   5. Publish trackCount and estimatedDuration (updated when the plan arrives
//      via planPublisher).

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

    /// True for any local-file origin. `ContentView` routes those to
    /// `LocalFileCountdownView` before this type is ever built for them; kept so the
    /// view model is correct on its own, whoever constructs it.
    let isLocalFile: Bool

    /// Number of tracks in the planned session. Updates if the plan is regenerated.
    @Published private(set) var trackCount: Int

    /// Total planned duration in seconds. Updates if the plan is regenerated.
    @Published private(set) var estimatedDuration: TimeInterval

    /// True once sustained audio has been confirmed (≥250 ms in `.active`).
    @Published private(set) var hasDetectedAudio: Bool = false

    /// True after 90 seconds with no audio detected. Surfaces the timeout card.
    @Published private(set) var isTimedOut: Bool = false

    /// Honours the system reduced-motion preference.
    @Published private(set) var reduceMotion: Bool

    // MARK: - Signals

    /// Emits once when playback should start — first audio confirmed, or "Begin now".
    /// `ReadyView` observes this to call `sessionManager.beginPlayback()`.
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
    ///   - origin: The `SessionOrigin` of this session; a `.playlist` names the app to press play in.
    ///   - sessionManager: The lifecycle manager; used for `endSession`.
    ///   - audioSignalStatePublisher: Publishes `AudioSignalState` transitions from the engine.
    ///   - planPublisher: Publishes updated `PlannedSession` values (nil = no plan/reactive mode).
    ///   - reduceMotion: Initial reduced-motion state; not live-updated (U.9 wires the full path).
    init(
        origin: SessionOrigin?,
        sessionManager: SessionManager,
        audioSignalStatePublisher: AnyPublisher<AudioSignalState, Never>,
        planPublisher: AnyPublisher<PlannedSession?, Never>,
        reduceMotion: Bool,
        delayProvider: any DelayProviding = RealDelay()
    ) {
        if case .playlist(let source) = origin {
            self.sourceName = source.displayName
        } else {
            self.sourceName = String(localized: "ready.source.fallback")
        }
        self.isLocalFile = origin?.isLocalFile ?? false
        self.sessionManager = sessionManager
        self.reduceMotion = reduceMotion
        self.firstAudioDetector = FirstAudioDetector(
            audioSignalStatePublisher: audioSignalStatePublisher,
            delayProvider: delayProvider
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

    /// "Begin now": start without waiting for audio. The visuals run at their silent
    /// baseline until the music actually arrives, which the app already handles.
    func beginNow() {
        timeoutTask?.cancel()
        isTimedOut = false
        shouldAdvanceToPlaying.send()
    }

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
            return String(format: String(localized: "ready.duration.hours_minutes"), hours, minutes)
        }
        return String(format: String(localized: "ready.duration.minutes"), max(1, minutes))
    }
}

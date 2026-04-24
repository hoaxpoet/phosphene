// PlaybackErrorBridge — Observes audio-signal state and routes §9.4 playback
// errors to the toast queue via condition-ID semantics.
//
// Replaces SilenceToastBridge (which fired at 30s with no condition-ID).
// Per UX_SPEC §9.4:
//   >3s silent   → log only; the ListeningBadgeView in chrome shows the badge.
//   >15s silent  → .silenceExtended degradation toast (conditionID: "silence.extended").
//   On recovery  → dismissByCondition("silence.extended") auto-clears the toast.
//
// Implements injectable publishers for unit-testable silence timing.

import Audio
import Combine
import Foundation
import os.log
import Shared

private let logger = Logger(subsystem: "com.phosphene.app", category: "PlaybackErrorBridge")

// MARK: - PlaybackErrorBridge

/// Routes §9.4 audio-signal errors to `ToastManager` with condition-ID semantics.
@MainActor
final class PlaybackErrorBridge {

    // MARK: - Constants

    /// Seconds of sustained silence before the degradation toast fires.
    static let silenceToastThresholdSeconds: TimeInterval = 15

    // MARK: - Private

    private let toastManager: ToastManager
    private let tracker: PlaybackErrorConditionTracker
    private var cancellables = Set<AnyCancellable>()

    private var silenceTask: Task<Void, Never>?

    // MARK: - Init

    init(
        audioSignalStatePublisher: AnyPublisher<AudioSignalState, Never>,
        toastManager: ToastManager,
        tracker: PlaybackErrorConditionTracker = PlaybackErrorConditionTracker()
    ) {
        self.toastManager = toastManager
        self.tracker = tracker

        audioSignalStatePublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] state in self?.handle(state: state) }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private func handle(state: AudioSignalState) {
        switch state {
        case .silent:
            beginSilenceTracking()
        case .suspect:
            // Brief interruption — keep tracking but do not start fresh.
            break
        case .active, .recovering:
            clearSilence()
        }
    }

    private func beginSilenceTracking() {
        guard silenceTask == nil else { return }
        let threshold = Self.silenceToastThresholdSeconds
        logger.debug("PlaybackErrorBridge: silence started — waiting \(threshold, format: .fixed(precision: 0))s")

        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.silenceToastThresholdSeconds))
            guard !Task.isCancelled, let self else { return }
            self.showSilenceExtendedToast()
        }
    }

    private func clearSilence() {
        silenceTask?.cancel()
        silenceTask = nil

        let conditionID = UserFacingError.silenceExtended.conditionID ?? "silence.extended"
        if tracker.isAsserted(conditionID) {
            toastManager.dismissByCondition(conditionID)
            tracker.clear(conditionID)
            logger.info("PlaybackErrorBridge: audio recovered — silence toast dismissed")
        }
    }

    private func showSilenceExtendedToast() {
        let error = UserFacingError.silenceExtended
        guard let conditionID = error.conditionID else { return }
        guard !tracker.isAsserted(conditionID) else { return }

        let toast = PhospheneToast(
            severity: .degradation,
            copy: LocalizedCopy.string(for: error),
            duration: .infinity,
            source: .signalState,
            conditionID: conditionID
        )
        toastManager.enqueue(toast)
        tracker.assert(conditionID)
        let threshold = Self.silenceToastThresholdSeconds
        logger.info("PlaybackErrorBridge: \(threshold, format: .fixed(precision: 0))s silence — toast shown")
    }
}

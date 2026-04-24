// FirstAudioDetector — Watches AudioSignalState transitions and fires once
// the signal is sustainably `.active` for ≥250 ms. Used by ReadyViewModel
// to auto-advance `.ready → .playing` when the user presses play.
//
// State survival rules (per UX_SPEC §6.3):
//  - `.suspect` does NOT cancel the confirmation timer — brief wobble is tolerated.
//  - `.silent` or `.recovering` DO cancel the timer — the signal dropped.
//  - A second `.active` while the timer is running does NOT restart it.
//  - Cold-start: initial `.active` (before any silence) triggers detection too.

import Audio
import Combine
import Foundation

// MARK: - FirstAudioDetector

/// Monitors `AudioSignalState` and fires `hasDetectedAudio` once audio is
/// sustained for ≥250 ms. Designed for injection into `ReadyViewModel`.
@MainActor
final class FirstAudioDetector: ObservableObject {

    // MARK: - Published State

    /// True once sustained audio has been confirmed. Latches — never goes false
    /// except via `reset()`.
    @Published private(set) var hasDetectedAudio: Bool = false

    // MARK: - Private

    private var subscription: AnyCancellable?
    private var confirmationTask: Task<Void, Never>?

    // MARK: - Init

    /// Create the detector, subscribing immediately to the given publisher.
    ///
    /// - Parameter audioSignalStatePublisher: Publishes the current
    ///   `AudioSignalState` whenever it changes. Typically
    ///   `engine.$audioSignalState.eraseToAnyPublisher()`.
    init(audioSignalStatePublisher: AnyPublisher<AudioSignalState, Never>) {
        subscription = audioSignalStatePublisher
            .removeDuplicates()
            .sink { [weak self] state in
                self?.handle(state: state)
            }
    }

    // MARK: - Actions

    /// Reset the detector so it can fire again after a `retry()`.
    func reset() {
        hasDetectedAudio = false
        cancelConfirmation()
    }

    // MARK: - Private

    private func handle(state: AudioSignalState) {
        guard !hasDetectedAudio else { return }
        switch state {
        case .active:
            startConfirmationTimer()
        case .silent, .recovering:
            cancelConfirmation()
        case .suspect:
            break
        }
    }

    private func startConfirmationTimer() {
        guard confirmationTask == nil else { return }
        confirmationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.hasDetectedAudio = true
        }
    }

    private func cancelConfirmation() {
        confirmationTask?.cancel()
        confirmationTask = nil
    }
}

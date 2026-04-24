// LiveAdaptationToastBridge — Emits ack toasts for engine adaptation events + user actions.
//
// Two observation sources:
//   1. Engine: VisualizerEngine live adaptation events (boundary reschedule / mood override).
//      Only emits toasts when UserDefaults flag is on.
//   2. User: via PlaybackActionRouter — wired in U.6b when the router publishes events.
//
// The flag "phosphene.showLiveAdaptationToasts" defaults to false until U.8 Settings
// panel ships. Coalescing: 3 adaptations within 2 s → single toast.
//
// Silence handling (previously SilenceToastBridge) was moved to PlaybackErrorBridge
// in U.7 Part C — now uses condition-ID semantics and the correct 15s threshold.

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "LiveAdaptationToastBridge")

// MARK: - LiveAdaptationToastBridge

/// Bridges orchestrator adaptation events to the toast queue.
///
/// Currently only wires the Settings flag check and coalescing logic.
/// Actual event subscriptions land in U.6b when PlaybackActionRouter publishes events.
@MainActor
final class LiveAdaptationToastBridge {

    // MARK: - Settings flag

    static let userDefaultsKey = "phosphene.showLiveAdaptationToasts"
    private var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.userDefaultsKey) }

    // MARK: - Coalescing

    private var pendingMessages: [String] = []
    private var coalesceTask: Task<Void, Never>?

    // MARK: - Private

    private let toastManager: ToastManager

    // MARK: - Init

    init(toastManager: ToastManager) {
        self.toastManager = toastManager
    }

    // MARK: - API

    /// Emit a live-adaptation acknowledgement toast (if the flag is on).
    ///
    /// Messages arriving within 2 s are coalesced into one toast.
    func emitAck(_ message: String) {
        guard isEnabled else {
            logger.debug("LiveAdaptationToastBridge: flag off — suppressing '\(message)'")
            return
        }
        pendingMessages.append(message)
        coalesceTask?.cancel()
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            let msgs = self.pendingMessages
            self.pendingMessages = []
            let copy = msgs.count == 1 ? msgs[0] : "Plan updated (\(msgs.count) changes)"
            let toast = PhospheneToast(severity: .info, copy: copy, source: .liveAdaptationAck)
            self.toastManager.enqueue(toast)
            logger.info("LiveAdaptationToastBridge: ack toast '\(copy)'")
        }
    }
}

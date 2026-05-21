// LiveAdaptationToastBridge — Emits acknowledgement toasts for user-initiated
// playback-action adaptations (more-like-this, less-like-this, reshuffle, preset
// nudge, re-plan, undo, mood-lock). All emission flows through `emitAck(_:)`
// invoked by `DefaultPlaybackActionRouter` (per D-050 / U.6b).
//
// Engine-driven adaptations (`VisualizerEngine.applyLiveUpdate(...)` boundary
// rescheduling / mood overrides) intentionally do NOT toast — the visual change
// itself is the user-visible feedback per UX_SPEC §7.4 ("on keystroke") and the
// CA.5-FU-2 product decision (2026-05-21).
//
// The flag "phosphene.settings.visuals.showLiveAdaptationToasts" gates emission.
// Default true for fresh installs (U.6b); existing users keep their explicit choice.
// Coalescing: messages within 2 s → single toast ("Plan updated (N changes)").
//
// Silence handling (previously SilenceToastBridge) moved to PlaybackErrorBridge
// in U.7 Part C — uses condition-ID semantics + 15 s threshold.

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "LiveAdaptationToastBridge")

// MARK: - LiveAdaptationToastBridge

/// Bridges user-initiated playback-action adaptations to the toast queue.
///
/// Consumed exclusively by `DefaultPlaybackActionRouter` (11 `emitAck(_:)` call sites
/// covering moreLikeThis / lessLikeThis / reshuffleUpcoming / presetNudge / rePlanSession
/// / undoLastAdaptation / toggleMoodLock plus the ambient `lessLikeThis` hint).
/// Engine-driven adaptations intentionally do NOT reach this bridge per UX_SPEC §7.4
/// and the CA.5-FU-2 product decision (Matt 2026-05-21).
@MainActor
final class LiveAdaptationToastBridge {

    // MARK: - Settings flag

    static let userDefaultsKey = "phosphene.settings.visuals.showLiveAdaptationToasts"

    // U.6b: default flipped to true for fresh installs.
    // Existing users who explicitly set the key (either way) keep their choice.
    private var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: Self.userDefaultsKey) != nil else {
            return true  // Key not set → new install → default on.
        }
        return UserDefaults.standard.bool(forKey: Self.userDefaultsKey)
    }

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

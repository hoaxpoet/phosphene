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
//
// Silent-tap detector (BUG-057 / BUG-055 / BUG-058 fix increment).
// On top of the silence toast, the bridge raises a prominent overlay card when
// NO FRESH audio is reaching the visualizer while we should be playing. This
// catches the whole silent-tap family — which all present identically to the
// user (the app shows "playing" but the visualizer is silent or frozen):
//   • Mode A — RMS ≈ 0 (wedged coreaudiod feeding zeros [BUG-057]; stale
//     Screen-Recording grant after a rebuild [BUG-055]). `audioSignalState`
//     goes `.silent`.
//   • Mode B — a device-swap freezes the tap IO-proc [BUG-058]; the render loop
//     coasts on the last buffer, so RMS stays NON-zero and `.silent` never
//     fires. The tell is that tap callbacks stop advancing.
// Both reduce to "no fresh audio": a ~1 Hz poll samples whether the tap frame
// count is still advancing AND the signal isn't confirmed silent. `dwell`
// consecutive not-fresh samples raise the card; it auto-clears when fresh audio
// resumes and supersedes the 15 s silence toast while up (no double-surface).
// The gate (playing && !paused, with a freshness baseline reset on entry) is the
// whole point — it must NOT fire pre-play, in the `.ready` wait, on a deliberate
// local-file pause, or during quiet musical passages.

import Audio
import Combine
import Foundation
import os.log
import Session
import Shared

private let logger = Logger(subsystem: "com.phosphene.app", category: "PlaybackErrorBridge")

// MARK: - PlaybackErrorBridge

/// Routes §9.4 audio-signal errors to `ToastManager` with condition-ID semantics.
@MainActor
final class PlaybackErrorBridge {

    // MARK: - Constants

    /// Seconds of sustained silence before the degradation toast fires.
    static let silenceToastThresholdSeconds: TimeInterval = 15

    /// Consecutive not-fresh poll samples before the stall card is raised.
    /// At the production 1 Hz poll cadence this is ~10 s — the approved dwell.
    static let defaultStallDwellTicks: Int = 10

    // MARK: - Private

    private let toastManager: ToastManager
    private let tracker: PlaybackErrorConditionTracker
    private var cancellables = Set<AnyCancellable>()

    private var silenceTask: Task<Void, Never>?

    // MARK: - Signal-health toast state (ASH.2)

    /// Reads whether the active session source is Spotify — picks the Spotify
    /// "Normalize Volume" remediation copy over the generic one. nil → generic.
    private let isSpotifySourceProvider: (@MainActor () -> Bool)?

    /// One-per-session latch: the low-level toast fires at most once, on the first
    /// sustained `band=low` window, and never re-fires (DECISION-NEEDED opt 1 —
    /// a single unobtrusive nudge, never repeated). Dead-tap is intentionally NOT
    /// surfaced here: the `AudioStallOverlayView` card already covers it earlier
    /// and more prominently (Matt's call, ASH.2).
    private var audioLevelsLowShown = false

    /// Seconds the low-level nudge stays up before auto-dismiss — long enough to
    /// read the remediation, short enough to stay unobtrusive.
    static let audioLevelsLowToastDuration: TimeInterval = 10

    // MARK: - Silent-tap detector state

    /// Reads the monotonic tap-callback frame count (Mode-B freshness signal).
    /// `nil` disables the frame-count axis — the card then keys on `.silent`
    /// alone (Mode A only). Production wires this to the engine's InputLevelMonitor.
    private let frameCountProvider: (@MainActor () -> Int)?

    /// Reads the engine's "session has had real audio" latch (BUG-057). When the
    /// tap is silent-but-alive (callbacks still advancing) AND this is true, the
    /// silence is a user pause → the card is suppressed (the fix-ladder doesn't
    /// apply, and it auto-clears on resume). `nil` disables pause-suppression.
    private let hasEverDetectedSignalProvider: (@MainActor () -> Bool)?

    /// Pushes the card's visibility to the view layer. The truth is
    /// `audioStallActive`; this is the side-channel that drives SwiftUI.
    private let onStallChanged: (@MainActor (Bool) -> Void)?

    private let stallDwellTicks: Int

    /// True while the prominent audio-stall overlay card should be shown.
    /// Source of truth for the card; exposed for unit tests of the gate.
    private(set) var audioStallActive = false

    private var currentSignalState: AudioSignalState = .active
    private var isPlaying = false
    private var isPaused = false
    /// `isPlaying && !isPaused` — "we should be hearing audio right now".
    private var stallGateActive = false
    private var lastFrameCount = 0
    private var nonFreshTicks = 0

    // MARK: - Init

    init(
        audioSignalStatePublisher: AnyPublisher<AudioSignalState, Never>,
        toastManager: ToastManager,
        tracker: PlaybackErrorConditionTracker = PlaybackErrorConditionTracker(),
        sessionStatePublisher: AnyPublisher<SessionState, Never> =
            Just(SessionState.playing).eraseToAnyPublisher(),
        isPausedPublisher: AnyPublisher<Bool, Never> =
            Just(false).eraseToAnyPublisher(),
        frameCountProvider: (@MainActor () -> Int)? = nil,
        hasEverDetectedSignalProvider: (@MainActor () -> Bool)? = nil,
        stallTickPublisher: AnyPublisher<Void, Never> =
            Timer.publish(every: 1.0, on: .main, in: .common)
                .autoconnect()
                .map { _ in () }
                .eraseToAnyPublisher(),
        stallDwellTicks: Int = PlaybackErrorBridge.defaultStallDwellTicks,
        onStallChanged: (@MainActor (Bool) -> Void)? = nil,
        signalHealthPublisher: AnyPublisher<SignalHealth, Never> =
            Empty().eraseToAnyPublisher(),
        isSpotifySourceProvider: (@MainActor () -> Bool)? = nil
    ) {
        self.toastManager = toastManager
        self.tracker = tracker
        self.frameCountProvider = frameCountProvider
        self.hasEverDetectedSignalProvider = hasEverDetectedSignalProvider
        self.onStallChanged = onStallChanged
        self.stallDwellTicks = stallDwellTicks
        self.isSpotifySourceProvider = isSpotifySourceProvider

        audioSignalStatePublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] state in self?.handle(state: state) }
            .store(in: &cancellables)

        sessionStatePublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] state in self?.updatePlaying(state == .playing) }
            .store(in: &cancellables)

        isPausedPublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] paused in self?.updatePaused(paused) }
            .store(in: &cancellables)

        stallTickPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.evaluateStall() }
            .store(in: &cancellables)

        signalHealthPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] health in self?.handle(health: health) }
            .store(in: &cancellables)
    }

    // MARK: - Signal-health toast (ASH.2)

    /// Surface a one-per-session low-level nudge on the first sustained `band=low`
    /// window. The monitor only publishes after a full 5 s window closes and only
    /// on change, so a single `.low` reading already means one sustained window.
    private func handle(health: SignalHealth) {
        guard health.peakBand == .low, !audioLevelsLowShown else { return }
        audioLevelsLowShown = true
        let isSpotify = isSpotifySourceProvider?() ?? false
        toastManager.enqueue(PhospheneToast(
            severity: .warning,
            copy: LocalizedCopy.string(for: .audioLevelsLow(isSpotifySource: isSpotify)),
            duration: Self.audioLevelsLowToastDuration,
            source: .signalState,
            conditionID: UserFacingError.audioLevelsLow(isSpotifySource: isSpotify).conditionID))
        logger.info("PlaybackErrorBridge: band=low — audio-levels-low nudge shown (spotify=\(isSpotify))")
    }

    // MARK: - Private

    private func handle(state: AudioSignalState) {
        currentSignalState = state
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
            try? await Task.sleep(for: .seconds(threshold))
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
        // The stall card supersedes the toast while playing — never both.
        guard !audioStallActive else { return }
        let error = UserFacingError.silenceExtended
        guard let conditionID = error.conditionID else { return }
        guard !tracker.isAsserted(conditionID) else { return }

        toastManager.enqueue(toast(for: error, severity: .degradation, source: .signalState))
        tracker.assert(conditionID)
        let threshold = Self.silenceToastThresholdSeconds
        logger.info("PlaybackErrorBridge: \(threshold, format: .fixed(precision: 0))s silence — toast shown")
    }

    // MARK: - Silent-tap detector

    private func updatePlaying(_ playing: Bool) {
        isPlaying = playing
        recomputeStallGate()
    }

    private func updatePaused(_ paused: Bool) {
        isPaused = paused
        recomputeStallGate()
    }

    /// Recompute `stallGateActive` (= playing && !paused). On any transition,
    /// reset the freshness baseline so we get a full dwell of grace after
    /// play/resume (never fire during audio ramp-up); leaving the gate (pause,
    /// end-of-session) clears any shown card immediately.
    private func recomputeStallGate() {
        let active = isPlaying && !isPaused
        guard active != stallGateActive else { return }
        stallGateActive = active
        nonFreshTicks = 0
        lastFrameCount = frameCountProvider?() ?? 0
        if !active { hideStallCard() }
    }

    /// One freshness sample, driven by `stallTickPublisher` (~1 Hz in production).
    /// "Fresh" = tap callbacks are still advancing AND the signal isn't confirmed
    /// silent. Mode A (RMS ≈ 0 → `.silent`) and Mode B (frozen IO-proc → frame
    /// count stops advancing) both read not-fresh; `stallDwellTicks` consecutive
    /// not-fresh samples raise the card.
    private func evaluateStall() {
        guard stallGateActive else { return }

        let advanced: Bool
        if let frameCountProvider {
            let count = frameCountProvider()
            advanced = count > lastFrameCount
            if advanced { lastFrameCount = count }
        } else {
            advanced = true   // Mode-B signal not wired — key on `.silent` alone
        }

        let fresh = advanced && currentSignalState != .silent
        // Suppress the card on a likely PAUSE: the tap is alive (callbacks still
        // advancing) but silent, AND the session has already had real audio — so
        // the source is paused, not broken (the fix-ladder doesn't apply, and the
        // card would auto-clear on resume anyway). A genuinely broken tap (never
        // delivered → provider false) or a frozen IO-proc (Mode B → !advanced)
        // still raises the card.
        let isLikelyPause = advanced
            && currentSignalState == .silent
            && (hasEverDetectedSignalProvider?() ?? false)
        if fresh || isLikelyPause {
            nonFreshTicks = 0
            hideStallCard()
        } else {
            nonFreshTicks += 1
            if nonFreshTicks >= stallDwellTicks { showStallCard() }
        }
    }

    private func showStallCard() {
        guard !audioStallActive else { return }
        audioStallActive = true
        onStallChanged?(true)
        // Supersede the 15 s silence toast — drop any pending/visible one so the
        // card is the single surface for total audio loss while playing.
        silenceTask?.cancel()
        silenceTask = nil
        let conditionID = UserFacingError.silenceExtended.conditionID ?? "silence.extended"
        if tracker.isAsserted(conditionID) {
            toastManager.dismissByCondition(conditionID)
            tracker.clear(conditionID)
        }
        let dwell = stallDwellTicks
        logger.info("PlaybackErrorBridge: audio stall (no fresh audio for \(dwell) ticks) — overlay card shown")
    }

    private func hideStallCard() {
        guard audioStallActive else { return }
        audioStallActive = false
        onStallChanged?(false)
        logger.info("PlaybackErrorBridge: fresh audio resumed — overlay card cleared")
    }

    /// Build a `PhospheneToast` for a `UserFacingError`, gating `duration` and
    /// `conditionID` on `error.isConditionBound` per CA-Shared-FU-1.
    ///
    /// Condition-bound errors (silence brief/extended, audio levels low) keep
    /// their toast visible until the underlying condition clears — duration is
    /// `.infinity` and the toast carries the error's `conditionID` so
    /// `ToastManager.dismissByCondition(_:)` can auto-clear it on recovery.
    /// Non-condition-bound errors use the default 4 s auto-dismiss.
    private func toast(
        for error: UserFacingError,
        severity: PhospheneToast.Severity,
        source: PhospheneToast.Source
    ) -> PhospheneToast {
        let bound = error.isConditionBound
        return PhospheneToast(
            severity: severity,
            copy: LocalizedCopy.string(for: error),
            duration: bound ? .infinity : 4,
            source: source,
            conditionID: bound ? error.conditionID : nil
        )
    }
}

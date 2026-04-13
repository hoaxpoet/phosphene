// SilenceDetector — Monitors RMS energy from the audio IO proc to detect
// DRM-triggered tap silencing.
//
// Core Audio process taps (`AudioHardwareCreateProcessTap`) succeed even when
// playing DRM-protected content, but macOS silently zeros the audio buffer.
// This produces sustained zero-energy frames with no error or callback —
// the tap appears healthy while delivering silence.
//
// `SilenceDetector` implements a hysteresis state machine to distinguish
// brief audio dropouts (< `suspectDuration`) from confirmed DRM silence
// (`silenceDuration`), and requires sustained signal return (`recoveryDuration`)
// before declaring the tap healthy again.

import CoreFoundation
import Foundation

// MARK: - SilenceDetector

/// Hysteresis state machine that distinguishes DRM-triggered tap silence from
/// ordinary audio dropouts.
///
/// State transitions:
/// ```
///   .active → .suspect   (silence for suspectDuration  = silenceDuration / 2)
///   .suspect → .silent   (silence for silenceDuration  total from start)
///   .suspect → .active   (signal returns before silenceDuration)
///   .silent  → .recovering (signal returns — any non-silent frame)
///   .recovering → .active  (signal sustained for recoveryDuration)
///   .recovering → .silent  (silence returns before recoveryDuration)
/// ```
///
/// Brief dropouts shorter than `suspectDuration` never leave `.active`.
///
/// Thread safety: `update(rms:)` is safe to call on the real-time audio thread.
/// `onStateChanged` is invoked synchronously after the lock is released.
final class SilenceDetector: @unchecked Sendable {

    // MARK: - Configuration

    /// RMS level below which audio is considered silent.
    let silenceRMSThreshold: Float

    /// Total silence duration required to confirm `.silent` state.
    let silenceDuration: TimeInterval

    /// Silence duration at which state transitions to `.suspect` (= `silenceDuration / 2`).
    let suspectDuration: TimeInterval

    /// Signal duration required to confirm recovery from `.silent` back to `.active`.
    let recoveryDuration: TimeInterval

    // MARK: - Callbacks

    /// Called on every state transition. Invoked on the thread that drove `update(rms:)`.
    var onStateChanged: ((AudioSignalState) -> Void)?

    // MARK: - Private State

    private var _state: AudioSignalState = .active
    /// Absolute time when silence first began (cleared when signal returns in `.active`/`.suspect`).
    private var silenceStartTime: CFAbsoluteTime?
    /// Absolute time when signal first returned from `.silent` (cleared if silence resumes).
    private var signalReturnTime: CFAbsoluteTime?
    private let lock = NSLock()

    // MARK: - Time Source

    /// Replaceable time source — injected in tests to avoid real sleeping.
    private let timeProvider: () -> CFAbsoluteTime

    // MARK: - Init

    /// Create a `SilenceDetector` with configurable thresholds.
    ///
    /// - Parameters:
    ///   - silenceRMSThreshold: RMS below which frames are considered silent. Default `1e-6`.
    ///   - silenceDuration: Total silence time before confirming `.silent`. Default `3.0s`.
    ///   - recoveryDuration: Signal time required to confirm `.active` from `.recovering`. Default `0.5s`.
    ///   - timeProvider: Time source for state machine — injectable for testing. Default `CFAbsoluteTimeGetCurrent`.
    init(
        silenceRMSThreshold: Float = 1e-6,
        silenceDuration: TimeInterval = 3.0,
        recoveryDuration: TimeInterval = 0.5,
        timeProvider: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent
    ) {
        self.silenceRMSThreshold = silenceRMSThreshold
        self.silenceDuration = silenceDuration
        self.suspectDuration = silenceDuration / 2.0
        self.recoveryDuration = recoveryDuration
        self.timeProvider = timeProvider
    }

    // MARK: - Current State

    /// The current audio signal state. Thread-safe.
    var state: AudioSignalState {
        lock.withLock { _state }
    }

    // MARK: - Update

    /// Process a chunk of interleaved PCM samples. Computes RMS and advances the state machine.
    ///
    /// Safe to call on the real-time audio IO proc thread. Critical section is O(N) for RMS
    /// but the lock is held only for the short state-machine branch, not the RMS loop.
    func update(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var sumSq: Float = 0
        for i in 0..<count {
            let s = samples[i]
            sumSq += s * s
        }
        let rms = (sumSq / Float(count)).squareRoot()
        update(rms: rms)
    }

    /// Process a pre-computed RMS value and advance the state machine.
    ///
    /// This overload is exposed for testing. Production code calls `update(samples:count:)`.
    func update(rms: Float) {
        let now = timeProvider()
        let isSilent = rms < silenceRMSThreshold

        // Compute next state outside the lock for the logic, then update atomically.
        var newState: AudioSignalState?

        lock.withLock {
            switch _state {

            case .active:
                if isSilent {
                    // Track when silence first began.
                    let start = silenceStartTime ?? now
                    silenceStartTime = start
                    let elapsed = now - start
                    if elapsed >= suspectDuration {
                        _state = .suspect
                        newState = .suspect
                    }
                } else {
                    // Signal present — clear silence window.
                    silenceStartTime = nil
                }

            case .suspect:
                if isSilent {
                    // silenceStartTime was set in .active; continue measuring total elapsed.
                    let start = silenceStartTime ?? now
                    let elapsed = now - start
                    if elapsed >= silenceDuration {
                        _state = .silent
                        newState = .silent
                    }
                } else {
                    // Signal returned before confirmation — brief dropout, recover to .active.
                    silenceStartTime = nil
                    _state = .active
                    newState = .active
                }

            case .silent:
                if !isSilent {
                    // Signal returned — enter recovery hold immediately.
                    signalReturnTime = now
                    _state = .recovering
                    newState = .recovering
                }
                // If still silent: remain in .silent, no transition.

            case .recovering:
                if isSilent {
                    // Silence returned before recovery confirmed — back to .silent.
                    signalReturnTime = nil
                    _state = .silent
                    newState = .silent
                } else {
                    let start = signalReturnTime ?? now
                    let elapsed = now - start
                    if elapsed >= recoveryDuration {
                        // Recovery confirmed.
                        signalReturnTime = nil
                        _state = .active
                        newState = .active
                    }
                }
            }
        }

        // Invoke callback outside the lock to avoid deadlock if the callback
        // calls back into the detector.
        if let transition = newState {
            onStateChanged?(transition)
        }
    }

    // MARK: - Reset

    /// Reset state machine to `.active`. Useful when the audio source changes.
    func reset() {
        var changed = false
        lock.withLock {
            if _state != .active {
                changed = true
            }
            _state = .active
            silenceStartTime = nil
            signalReturnTime = nil
        }
        if changed {
            onStateChanged?(.active)
        }
    }
}

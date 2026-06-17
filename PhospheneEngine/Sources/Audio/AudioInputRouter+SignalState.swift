import Foundation
import Shared
import os.log

private let signalStateLogger = Logger(subsystem: "com.phosphene.audio", category: "AudioInputRouter")

@available(macOS 14.2, *)
extension AudioInputRouter {

    // MARK: - BUG-057 Instrumentation

    /// Mirror a reinstall-scheduler line to os_log AND the
    /// `onAudioCaptureDiagnostic` sink, so the `.silent → reinstall` recovery
    /// timeline survives in session.log (os_log rolls off). The sink is nil in
    /// headless/test contexts that don't opt in, so this is a no-op there.
    func logReinstall(_ message: String, isError: Bool = false) {
        if isError {
            signalStateLogger.error("\(message)")
        } else {
            signalStateLogger.info("\(message)")
        }
        onAudioCaptureDiagnostic?(message)
    }

    // MARK: - Signal-State Handling + Tap Reinstall

    /// True once this session's tap has delivered any non-silent audio (BUG-057).
    /// Lets the UI distinguish a genuinely broken tap (never delivered → show the
    /// silent-tap card) from a user pause (was delivering, now silent → suppress
    /// the card). Reset per session in `start(mode:)` via `resetSignalHistory()`.
    public var hasEverDetectedSignal: Bool {
        silenceDetector.hasEverDetectedSignal
    }

    /// Forward signal state to subscribers and drive the tap-reinstall state
    /// machine. `AudioHardwareCreateProcessTap` does not gracefully handle
    /// the source process tearing down its audio session (e.g. during a
    /// streaming-app scrub) — the tap stays alive but delivers permanent
    /// silence. The recovery is to destroy and recreate the tap.
    ///
    /// State transitions:
    ///   .silent  → schedule tap reinstall after `reinstallDelays[attempt]`
    ///   .active  → cancel any pending reinstall + reset attempt counter
    ///   .recovering / .suspect → no action (let the detector confirm first)
    func handleSignalStateChange(_ state: AudioSignalState) {
        onSignalStateChanged?(state)
        switch state {
        case .silent:
            scheduleNextReinstall()
        case .active:
            cancelPendingReinstall()
        case .recovering, .suspect:
            break
        }
    }

    /// Schedule the next tap-reinstall attempt with exponential backoff.
    /// No-op if we've exhausted `reinstallDelays` (treats prolonged silence
    /// as a real pause rather than a stuck tap).
    ///
    /// **Mode gate (LF.1):** the reinstall scheduler only applies to process-
    /// tap modes (`.systemAudio`, `.application`). In `.localFile` (offline
    /// PCM injection) and `.localFilePlayback` (AVAudioEngine playback)
    /// there is no tap to reinstall — silence in a played file is real
    /// musical silence, not a teardown. Skipping the schedule here keeps
    /// the "Tap reinstall scheduled" log line out of `session.log` for
    /// non-tap modes, which the LF.1 verification grep depends on.
    func scheduleNextReinstall() {
        let mode = lock.withLock { currentMode }
        switch mode {
        case .localFile, .localFilePlayback, nil:
            return
        case .systemAudio, .application:
            break
        }

        // BUG-057 fix (step 3): only auto-reinstall a tap that NEVER delivered
        // audio (a genuinely broken cold install — stale Screen-Recording grant
        // / wedged coreaudiod). If the session HAS had real audio, this silence
        // is almost certainly a user pause: the working tap reads silence because
        // the source is paused, and resumes on its own when audio returns.
        // Reinstalling it is pointless churn that intermittently lands a
        // created-but-dead tap (the 2026-06-17T16-59-43Z freeze; diagnosis in
        // KNOWN_ISSUES BUG-057 §Reinstall fix step 2). Tradeoff: a tap that
        // delivered then died for real mid-session is treated as a pause and not
        // auto-recovered — rare, the reinstall was unreliable for it anyway, and
        // the silent-tap detector card surfaces it.
        if silenceDetector.hasEverDetectedSignal {
            logReinstall(
                "Tap reinstall SKIPPED — session has had audio; treating this silence as a user "
                + "pause (working tap resumes on play), not a broken tap")
            return
        }

        let attempt: Int
        let delay: TimeInterval
        let shouldSchedule: Bool
        let workItem: DispatchWorkItem
        let lockHandle = self.lock
        attempt = lockHandle.withLock { reinstallAttempts }
        guard attempt < reinstallDelays.count else {
            logReinstall(
                "Tap reinstall: backoff exhausted (\(attempt) attempts) — treating silence as real pause")
            return
        }
        delay = reinstallDelays[attempt]
        shouldSchedule = lockHandle.withLock {
            guard reinstallWorkItem == nil else { return false }
            reinstallAttempts = attempt + 1
            return true
        }
        guard shouldSchedule else { return }
        workItem = DispatchWorkItem { [weak self] in
            self?.attemptTapReinstall(attemptNumber: attempt + 1)
        }
        lockHandle.withLock { reinstallWorkItem = workItem }
        tapMgmtQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
        logReinstall("Tap reinstall scheduled in \(delay)s (attempt #\(attempt + 1))")
    }

    /// Cancel any pending reinstall and reset the attempt counter.
    /// Called when audio resumes naturally on the existing tap.
    func cancelPendingReinstall() {
        lock.withLock {
            reinstallWorkItem?.cancel()
            reinstallWorkItem = nil
            reinstallAttempts = 0
        }
    }

    /// Run on `tapMgmtQueue`. Re-checks signal state, then destroys and
    /// recreates the tap for the current mode.
    func attemptTapReinstall(attemptNumber: Int) {
        lock.withLock { reinstallWorkItem = nil }
        let state = silenceDetector.state
        guard state == .silent else {
            logReinstall(
                "Tap reinstall #\(attemptNumber) skipped — state is \(String(describing: state))")
            cancelPendingReinstall()
            return
        }
        let mode = lock.withLock { currentMode }
        guard let mode = mode else { return }
        switch mode {
        case .systemAudio:
            performTapReinstall(captureMode: .systemAudio, attemptNumber: attemptNumber)
        case .application(let bundleID):
            performTapReinstall(captureMode: .application(bundleIdentifier: bundleID),
                                attemptNumber: attemptNumber)
        case .localFile, .localFilePlayback:
            // Defensive: scheduleNextReinstall() already gates these modes
            // out, so this branch is unreachable in practice. Kept exhaustive
            // so future enum additions trigger a compile error here too.
            break
        }
    }

    func performTapReinstall(captureMode: CaptureMode, attemptNumber: Int) {
        logReinstall(
            "Tap reinstall #\(attemptNumber) starting (mode: \(String(describing: captureMode)))")
        systemCapture.stopCapture()
        do {
            try systemCapture.startCapture(mode: captureMode)
            logReinstall(
                "Tap reinstall #\(attemptNumber) succeeded — fresh tap installed; waiting to see if audio flows on it")
        } catch {
            logReinstall(
                "Tap reinstall #\(attemptNumber) failed: \(error.localizedDescription)", isError: true)
        }
        scheduleNextReinstall()
    }
}

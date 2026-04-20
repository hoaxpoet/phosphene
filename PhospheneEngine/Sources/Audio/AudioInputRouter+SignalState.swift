import Foundation
import Shared
import os.log

private let signalStateLogger = Logger(subsystem: "com.phosphene.audio", category: "AudioInputRouter")

@available(macOS 14.2, *)
extension AudioInputRouter {

    // MARK: - Signal-State Handling + Tap Reinstall

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
    func scheduleNextReinstall() {
        let attempt: Int
        let delay: TimeInterval
        let shouldSchedule: Bool
        let workItem: DispatchWorkItem
        let lockHandle = self.lock
        attempt = lockHandle.withLock { reinstallAttempts }
        guard attempt < reinstallDelays.count else {
            signalStateLogger.info(
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
        signalStateLogger.info("Tap reinstall scheduled in \(delay)s (attempt #\(attempt + 1))")
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
            signalStateLogger.info(
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
        case .localFile:
            break
        }
    }

    func performTapReinstall(captureMode: CaptureMode, attemptNumber: Int) {
        signalStateLogger.info(
            "Tap reinstall #\(attemptNumber) starting (mode: \(String(describing: captureMode)))")
        systemCapture.stopCapture()
        do {
            try systemCapture.startCapture(mode: captureMode)
            signalStateLogger.info(
                "Tap reinstall #\(attemptNumber) succeeded — fresh tap installed; waiting to see if audio flows on it")
        } catch {
            signalStateLogger.error(
                "Tap reinstall #\(attemptNumber) failed: \(error.localizedDescription)")
        }
        scheduleNextReinstall()
    }
}

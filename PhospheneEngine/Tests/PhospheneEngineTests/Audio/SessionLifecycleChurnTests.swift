// SessionLifecycleChurnTests — REVIEW.2 (2026-06-11).
//
// Regression net for the session-lifecycle hang class measured as the
// dominant correction cost in the REVIEW.1 transcript audit: BUG-021
// (AVAudioPlayerNode.stop ABBA deadlock against the provider NSLock),
// the LF.5 Next-button freeze loop, and the LF.6.streaming quit hang.
//
// Every test drives the REAL AVFoundation dispatch path (AVAudioEngine +
// AVAudioPlayerNode + scheduleFile completion callbacks) through the same
// entry points the live app uses — `AudioInputRouter.start(mode:
// .localFilePlayback)` / `.stop()` for the queue-advance shape, and
// `LocalFilePlaybackProvider` directly for the completion-callback races.
// No mocks on the audio objects: the deadlock class lives in the interplay
// between the provider's lock and AVFoundation's render/completion threads,
// which doubles cannot reproduce.
//
// Watchdog discipline: a hang here historically blocked the MainActor
// forever (spinning beachball). Each lifecycle step runs on a detached
// thread under a deadline; on timeout the test FAILS with the step name
// instead of hanging the suite. The stuck thread is leaked deliberately —
// the process is ending anyway, and the leaked thread IS the regression
// evidence (sample the test process to read its stack). Issues are never
// recorded from the detached thread (Swift Testing associates issues via
// task-locals, which raw threads lose) — failures travel back through the
// lock-guarded `StepError` box and are recorded on the test thread.
//
// Audio fixture: a ~0.25 s excerpt cut from the real love_rehab.m4a tempo
// fixture (real music per the no-synthetic-audio rule; the short length
// makes scheduleFile completions fire ~4×/s so the completion-vs-stop race
// window is exercised many times per run, where the 30 s fixture would
// exercise it once). Fixtures are .gitignore'd — absence records an Issue
// per the no-silent-skip rule (see Scripts/fetch_tempo_fixtures.sh).
//
// Audibility note: these tests briefly play real audio through the default
// output device (the analysis tap is pre-volume; the output mixer is not).
// Total audible exposure is a few seconds of 0.25 s blips per suite run.

import AVFoundation
import Foundation
import Testing
@testable import Audio

// MARK: - Watchdog plumbing

/// Lock-guarded message box: detached threads write failure text here; the
/// test thread reads it after the wait and records the Issue with proper
/// test association.
private final class StepError: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    func set(_ message: String) { lock.withLock { stored = stored ?? message } }
    var message: String? { lock.withLock { stored } }
}

/// Runs `body` on a detached thread and fails the test if it does not
/// return within `timeout` (hang class) or if it reported an error via the
/// box. Returns `true` when the step completed cleanly.
private func watchdogged(
    _ stepName: String,
    timeout: TimeInterval = 5.0,
    _ body: @escaping @Sendable (StepError) -> Void
) -> Bool {
    let errorBox = StepError()
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        body(errorBox)
        done.signal()
    }
    if done.wait(timeout: .now() + timeout) == .timedOut {
        let message = "Lifecycle step '\(stepName)' exceeded the \(timeout) s watchdog — "
            + "main-thread-hang class (BUG-021 family). The stuck thread is leaked; "
            + "sample the test process to read its stack if reproducible."
        Issue.record(Comment(rawValue: message))
        return false
    }
    if let message = errorBox.message {
        Issue.record("Lifecycle step '\(stepName)' failed: \(message)")
        return false
    }
    return true
}

// MARK: - Fixture

/// Cuts a short excerpt from the real tempo fixture into a temp CAF file.
/// Real music content (no synthetic envelopes); short enough that the
/// scheduleFile completion callback fires continuously during churn.
private enum ChurnFixture {

    static func shortExcerptURL() throws -> URL? {
        let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
        let source = testDir
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
        guard FileManager.default.fileExists(atPath: source.path) else {
            let message = "Churn fixture absent at \(source.path) — run "
                + "Scripts/fetch_tempo_fixtures.sh. (No silent skip per CLAUDE.md.)"
            Issue.record(Comment(rawValue: message))
            return nil
        }

        let file = try AVAudioFile(forReading: source)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(format.sampleRate * 0.25)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            Issue.record("Churn fixture: could not allocate excerpt buffer")
            return nil
        }
        try file.read(into: buffer, frameCount: frames)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("churn_excerpt_\(ProcessInfo.processInfo.processIdentifier).caf")
        try? FileManager.default.removeItem(at: dest)
        let writer = try AVAudioFile(forWriting: dest, settings: format.settings)
        try writer.write(from: buffer)
        return dest
    }
}

// MARK: - Suite

/// Serialized: each test owns real AVAudioEngine instances and threads;
/// parallel execution would stack engines and squeeze the watchdog margins
/// (same rationale as the CLAUDE.md @MainActor timing-margin note).
@Suite("Session lifecycle churn (REVIEW.2)", .serialized)
struct SessionLifecycleChurnTests {

    // MARK: - Router-level churn (the live queue-advance call shape)

    /// `advanceLocalFileQueue` calls `audioRouter.stop()` then
    /// `audioRouter.start(mode: .localFilePlayback(next))` on the MainActor.
    /// This is the exact call pair that froze the app in BUG-021 and the
    /// LF.5 Next-button loop. 12 cycles with varied dwell so stop lands in
    /// different playback phases (engine spin-up, mid-play, completion
    /// callback in flight).
    @Test func routerChurn_startStopLocalFilePlayback_neverHangs() throws {
        // LocalFilePlaybackProvider is @available(macOS 14.2, *); deployment
        // floor is 14.0. Never expected to skip on dev/CI hardware.
        guard #available(macOS 14.2, *) else { return }
        guard let url = try ChurnFixture.shortExcerptURL() else { return }
        let router = AudioInputRouter()
        // Varied dwell times (ms): hit spin-up, steady-state, and the
        // ~250 ms completion-callback boundary of the short excerpt.
        let dwells: [UInt32] = [5, 20, 60, 120, 240, 260, 300, 15, 250, 80, 255, 40]
        for (cycle, dwellMs) in dwells.enumerated() {
            let started = watchdogged("router.start cycle \(cycle)") { box in
                do {
                    try router.start(mode: .localFilePlayback(url))
                } catch {
                    box.set("router.start threw: \(error)")
                }
            }
            guard started else { return }
            usleep(dwellMs * 1_000)
            let stopped = watchdogged("router.stop cycle \(cycle)") { _ in
                router.stop()
            }
            guard stopped else { return }
        }
    }

    // MARK: - Completion-callback vs stop (the BUG-021 ABBA shape)

    /// With `onFileEnded == nil` the 0.25 s excerpt loops via repeated
    /// `scheduleFile` completion callbacks (~4/s). Churning `stop()` /
    /// `start()` against that loop reproduces the exact race BUG-021
    /// deadlocked on: the completion callback takes the provider lock to
    /// check `playerNode === player` while `stop()` is mid-teardown.
    @Test func completionCallbackVsStop_abbaShape_neverDeadlocks() throws {
        // LocalFilePlaybackProvider is @available(macOS 14.2, *); deployment
        // floor is 14.0. Never expected to skip on dev/CI hardware.
        guard #available(macOS 14.2, *) else { return }
        guard let url = try ChurnFixture.shortExcerptURL() else { return }
        let provider = LocalFilePlaybackProvider(url: url)
        for cycle in 0..<10 {
            let started = watchdogged("provider.start cycle \(cycle)") { box in
                do { try provider.start() } catch {
                    box.set("provider.start threw: \(error)")
                }
            }
            guard started else { return }
            // Dwell past at least one loop boundary every other cycle so the
            // stop below races a live completion callback, not just playback.
            usleep(cycle % 2 == 0 ? 300_000 : 30_000)
            let stopped = watchdogged("provider.stop cycle \(cycle)") { _ in
                provider.stop()
            }
            guard stopped else { return }
        }
    }

    // MARK: - Queue-advance churn driven from onFileEnded (Next-button shape)

    /// The LF.5 multi-file path: `onFileEnded` fires on AVFoundation's
    /// completion thread; the app then stops the old provider and starts the
    /// next track. Simulates 8 consecutive track advances, each stop + new
    /// provider + start triggered by a real end-of-file callback.
    @Test func onFileEnded_queueAdvanceChurn_neverHangs() throws {
        // LocalFilePlaybackProvider is @available(macOS 14.2, *); deployment
        // floor is 14.0. Never expected to skip on dev/CI hardware.
        guard #available(macOS 14.2, *) else { return }
        guard let url = try ChurnFixture.shortExcerptURL() else { return }
        var provider: LocalFilePlaybackProvider?

        for advance in 0..<8 {
            let ended = DispatchSemaphore(value: 0)
            let next = LocalFilePlaybackProvider(url: url)
            next.onFileEnded = { ended.signal() }

            let oldProvider = provider
            let swapped = watchdogged("advance \(advance) stop-old + start-new") { box in
                oldProvider?.stop()
                do { try next.start() } catch {
                    box.set("start threw: \(error)")
                }
            }
            guard swapped else { return }
            provider = next

            // The 0.25 s excerpt must reach EOF and fire the callback well
            // within the watchdog window — a missing callback is its own
            // hang class (the queue would stall on this track forever).
            if ended.wait(timeout: .now() + 5.0) == .timedOut {
                let message = "advance \(advance): onFileEnded never fired within 5 s — "
                    + "queue-advance stall class"
                Issue.record(Comment(rawValue: message))
                return
            }
        }
        let finalProvider = provider
        _ = watchdogged("final stop") { _ in finalProvider?.stop() }
    }

    // MARK: - Transport churn (pause/resume/isPaused vs stop)

    /// D-LF5-3 transport controls hammer `pause()` / `resume()` /
    /// `isPaused` from UI code while track advances stop/start the
    /// provider. Three hammer threads + a foreground stop/start churn; the
    /// watchdog catches any lock-ordering regression between the transport
    /// surface and teardown.
    @Test func transportChurn_concurrentWithStopStart_neverDeadlocks() throws {
        // LocalFilePlaybackProvider is @available(macOS 14.2, *); deployment
        // floor is 14.0. Never expected to skip on dev/CI hardware.
        guard #available(macOS 14.2, *) else { return }
        guard let url = try ChurnFixture.shortExcerptURL() else { return }
        let provider = LocalFilePlaybackProvider(url: url)
        try provider.start()

        let hammerDone = DispatchSemaphore(value: 0)
        for _ in 0..<3 {
            Thread.detachNewThread {
                for _ in 0..<200 {
                    provider.pause()
                    _ = provider.isPaused
                    provider.resume()
                }
                hammerDone.signal()
            }
        }

        for cycle in 0..<5 {
            let cycled = watchdogged("transport-churn stop/start cycle \(cycle)") { box in
                provider.stop()
                do { try provider.start() } catch {
                    box.set("start threw: \(error)")
                }
            }
            guard cycled else { return }
            usleep(20_000)
        }

        for hammer in 0..<3 where hammerDone.wait(timeout: .now() + 5.0) == .timedOut {
            Issue.record("transport hammer thread \(hammer) did not finish — deadlock class")
            return
        }
        _ = watchdogged("transport-churn final stop") { _ in provider.stop() }
    }

    // MARK: - Teardown-by-release (the quit shape)

    /// The LF.6.streaming quit hang: app teardown releases the engine
    /// adapter while playback is live, so the provider deinit runs the
    /// AVFoundation teardown. Five create→start→release cycles under the
    /// watchdog.
    @Test func deinitWhilePlaying_quitShape_neverHangs() throws {
        // LocalFilePlaybackProvider is @available(macOS 14.2, *); deployment
        // floor is 14.0. Never expected to skip on dev/CI hardware.
        guard #available(macOS 14.2, *) else { return }
        guard let url = try ChurnFixture.shortExcerptURL() else { return }
        for cycle in 0..<5 {
            let dwellMicros: UInt32 = cycle % 2 == 0 ? 120_000 : 280_000
            let released = watchdogged("deinit cycle \(cycle)") { box in
                do {
                    let provider = LocalFilePlaybackProvider(url: url)
                    try provider.start()
                    usleep(dwellMicros)
                    // provider goes out of scope here → deinit teardown path
                } catch {
                    box.set("start threw: \(error)")
                }
            }
            guard released else { return }
        }
    }

    // MARK: - Concurrent double-start (double-open race shape)

    /// The LF.5 "second Open Local Folder while the first is starting"
    /// family at the provider layer: two threads race `start()`; the lock
    /// must serialize them without deadlocking, and the final `stop()` must
    /// complete.
    @Test func concurrentDoubleStart_serializesWithoutDeadlock() throws {
        // LocalFilePlaybackProvider is @available(macOS 14.2, *); deployment
        // floor is 14.0. Never expected to skip on dev/CI hardware.
        guard #available(macOS 14.2, *) else { return }
        guard let url = try ChurnFixture.shortExcerptURL() else { return }
        let provider = LocalFilePlaybackProvider(url: url)
        for round in 0..<8 {
            let raced = watchdogged("double-start round \(round)", timeout: 8.0) { _ in
                let both = DispatchSemaphore(value: 0)
                for _ in 0..<2 {
                    Thread.detachNewThread {
                        // A racing start may legitimately throw (device mid-
                        // reconfiguration); the hang is the defect under
                        // test, not the throw.
                        try? provider.start()
                        both.signal()
                    }
                }
                both.wait()
                both.wait()
                provider.stop()
            }
            guard raced else { return }
        }
    }
}

// swiftlint:disable file_length
// LocalFilePlaybackProvider — Plays a local audio file through the default
// output device and exposes the analysis-tap signal via a callback that
// matches `SystemAudioCapture.onAudioBuffer`'s contract.
//
// LF.1 spike (2026-05-27). Unlike the offline `.localFile(URL)` mode (which
// only feeds PCM into the analysis pipeline at near-real-time without
// playing audio), this provider plays the file via `AVAudioEngine` +
// `AVAudioPlayerNode` and installs a tap on the player node's output bus
// (pre-mixer, pre-volume). Phosphene owns the playhead. Core Audio process
// taps are bypassed entirely — no screen-capture permission required.

@preconcurrency import AVFoundation
import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.audio", category: "LocalFilePlaybackProvider")

// MARK: - LocalFilePlaybackProvider

/// Plays an audio file via `AVAudioEngine` and forwards analysis-bus PCM
/// to a callback. Loops indefinitely at EOF — matches the existing
/// `.localFile(URL)` mode's behavior so the spike's verification window
/// is not bounded by the fixture's duration.
///
/// Threading: the tap callback fires on an AVAudioEngine-owned background
/// thread. `onAudioSamples` is invoked from that thread; consumers must
/// handle off-main-thread delivery identically to the process-tap path.
///
/// Lifecycle: `start()` opens the file, starts the engine, installs the
/// tap, and begins playback. `stop()` reverses everything. Both are
/// idempotent and safe to call concurrently (NSLock-serialized).
///
/// `AVAudioEngineConfigurationChange` notifications are observed and
/// trigger a stop → start cycle (best-effort restart from beginning).
@available(macOS 14.2, *)
public final class LocalFilePlaybackProvider: @unchecked Sendable {

    // MARK: - State

    /// The file being played. Captured at init; immutable for the
    /// provider's lifetime. A different file requires a new provider.
    private let url: URL

    /// Guards `engine` / `playerNode` / `audioFile` / `interleavedScratch` /
    /// `configChangeObserver` across `start()` / `stop()` / configuration-
    /// change restart paths. NOT taken inside the tap callback — the
    /// callback is real-time-ish (AVAudioEngine background thread) and
    /// reads `interleavedScratch` only.
    private let lock = NSLock()

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?

    /// Scratch buffer used to interleave AVAudioPCMBuffer's planar L/R
    /// channels into the interleaved float32 layout the downstream
    /// `onAudioSamples` callback expects. Sized to the largest tap buffer
    /// seen so far; grown lazily inside the callback if a larger frame
    /// count arrives.
    private var interleavedScratch: [Float] = []

    /// Retained so `removeObserver` can be called during teardown.
    private var configChangeObserver: NSObjectProtocol?

    // MARK: - Callback

    /// Receives interleaved float32 PCM samples from the player-node tap.
    /// Parameters: (samples pointer, total floats = frames × channels, sample rate, channel count).
    ///
    /// Matches the `SystemAudioCapture.onAudioBuffer` contract exactly so
    /// the downstream pipeline (`AudioInputRouter.onAudioSamples` consumers)
    /// is source-agnostic. Set before calling `start()`; subsequent changes
    /// take effect only after the next `start()`.
    public var onAudioSamples: ((_ samples: UnsafePointer<Float>, _ sampleCount: Int,
                                 _ sampleRate: Float, _ channelCount: UInt32) -> Void)?

    /// LF.5 — Fires when the audio file reaches end-of-stream. When set,
    /// `scheduleFileLoop` invokes this callback INSTEAD of re-scheduling the
    /// file — the caller is then responsible for advancing the queue (LF.5
    /// multi-file path) or stopping playback. When nil (LF.1 / LF.4 single-
    /// file default), the LF.1 behavior preserves: the file loops forever.
    ///
    /// Set before calling `start()`; subsequent changes take effect on the
    /// NEXT scheduleFile callback, not retroactively.
    ///
    /// Sendable callback type so it can be invoked from the AVAudioEngine
    /// scheduleFile completion thread without a Swift-6 concurrency warning.
    public var onFileEnded: (@Sendable () -> Void)?

    /// BUG-021 (2026-05-28) — synchronous diagnostic hook. When set, the
    /// `teardownAVFoundation` static helper (called from `stop()` and
    /// `start()`) emits a breadcrumb at each sub-step (remove observer,
    /// player.stop, player.removeTap, engine.stop). App-layer wires this
    /// to `SessionRecorder.log` so the breadcrumbs land in session.log
    /// on the call thread.
    public var onDiagnosticEvent: ((String) -> Void)?

    // MARK: - Init

    /// Create a provider that will play the file at `url` when `start()` is called.
    public init(url: URL) {
        self.url = url
    }

    deinit {
        // deinit can't acquire `lock` safely (the owning actor may be torn
        // down). Snapshot + tear down without locking. The provider is
        // being destroyed, so no other thread can race against us.
        let oldRefs = TeardownRefs(
            player: playerNode,
            engine: engine,
            observer: configChangeObserver
        )
        playerNode = nil
        engine = nil
        audioFile = nil
        configChangeObserver = nil
        Self.teardownAVFoundation(refs: oldRefs, diagnostic: nil)
    }

    // MARK: - Public API

    /// Open the file, start the engine, install the tap, and begin playback.
    ///
    /// Throws on file decode or engine-start failure. Calling `start()`
    /// when the provider is already running first tears the previous
    /// instance down.
    public func start() throws {
        // BUG-021 fix (2026-05-28): tear down any previous instance BEFORE
        // taking the lock to set up the new one — same reason as `stop()`
        // below (avoids the AVAudioPlayerNode.stop() / scheduleFile-callback
        // ABBA deadlock against the provider's NSLock).
        stop()
        try lock.withLock { try _startLocked() }
    }

    /// Stop playback and tear down the engine. Safe to call multiple times
    /// or when the provider has never been started.
    ///
    /// BUG-021 fix (2026-05-28): snapshots the AVFoundation refs + nil-outs
    /// the fields under the lock, then releases the lock and does the
    /// AVFoundation teardown (player.stop / removeTap / engine.stop) outside
    /// it. Session `2026-05-28T19-35-13Z` hit a hang at `player.stop()`
    /// because:
    ///
    ///   1. MainActor held `lock` via the original `lock.withLock {
    ///      _stopLocked() }` wrapper.
    ///   2. `player.stop()` blocked waiting for AVFoundation's render thread
    ///      to drain.
    ///   3. The render thread was running a `scheduleFile` completion
    ///      callback that tries `lock.withLock { … }` to check whether the
    ///      player it captured is still the active one.
    ///   4. Step 3 blocked on lock → step 2 blocked on render → MainActor
    ///      blocked indefinitely. Classic ABBA.
    ///
    /// With this change, by the time `player.stop()` waits for the callback,
    /// the callback finds `playerNode == nil` (we nil-ed it under the lock
    /// already), bails out, and returns. No deadlock.
    public func stop() {
        let oldRefs: TeardownRefs = lock.withLock {
            let refs = TeardownRefs(
                player: playerNode,
                engine: engine,
                observer: configChangeObserver
            )
            // Nil out under the lock so the scheduleFile completion callback
            // (which acquires the lock to check `playerNode === player`)
            // sees the post-teardown state when it next runs.
            playerNode = nil
            engine = nil
            audioFile = nil
            configChangeObserver = nil
            return refs
        }
        // LF.5.fix.2-FU1: skip the teardown helper entirely when the snapshot
        // is all-nil. `start()` calls `stop()` unconditionally to clear any
        // previous instance lock-free; on the first call (and on subsequent
        // start→stop→start cycles where the prior teardown already ran), the
        // snapshot has nothing to release. Emitting the breadcrumb pair
        // anyway clutters session.log with paired ENTER/EXIT lines that
        // bracket zero work.
        if oldRefs.player == nil && oldRefs.engine == nil && oldRefs.observer == nil {
            return
        }
        Self.teardownAVFoundation(refs: oldRefs, diagnostic: onDiagnosticEvent)
    }

    /// Pause playback without tearing down the engine. The player retains its
    /// position; `resume()` continues from the same frame. Safe to call when
    /// already paused or before `start()`.
    ///
    /// LF.5.fix D-LF5-3: transport controls (hover-revealed Stop / Prev /
    /// Play-Pause / Next) drive into this method.
    public func pause() {
        lock.withLock { playerNode?.pause() }
    }

    /// Resume playback after `pause()`. Safe to call when already playing or
    /// before `start()`.
    public func resume() {
        lock.withLock { playerNode?.play() }
    }

    /// `true` while the engine + player exist and the player is not currently
    /// playing (paused state). `false` when stopped or actively playing.
    /// Used by the transport controls view model to render the right glyph
    /// (▶ vs ⏸).
    public var isPaused: Bool {
        lock.withLock {
            guard let player = playerNode, engine != nil else { return false }
            return !player.isPlaying
        }
    }

    // MARK: - Private — assume `lock` held

    private func _startLocked() throws {
        // BUG-021 fix (2026-05-28): the leading `_stopLocked()` call here
        // was the deadlock origin — it acquired the lock indirectly via
        // `_stopLocked`'s synchronous AVFoundation teardown while the
        // scheduleFile completion callback also tried to take the lock.
        // The new `start()` public method calls `stop()` (which now
        // tears down outside the lock) BEFORE invoking `_startLocked`,
        // so by the time we reach this point any previous instance is
        // already gone and the fields below are guaranteed nil.

        let file = try AVAudioFile(forReading: url)
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)

        // The tap sees the player's OUTPUT (post-attach, pre-mixer). After
        // `connect(... format: file.processingFormat)`, that output format
        // is the file's native processing format — typically Float32 planar
        // at the file's sample rate (44100 Hz for love_rehab.m4a). The
        // mixer downstream handles any sample-rate conversion to the
        // output device's format (often 48 kHz on macOS). The tap is
        // pre-volume, so the user's mainMixerNode.outputVolume does not
        // affect the analysis signal.
        let tapFormat = player.outputFormat(forBus: 0)
        let sampleRate = Float(tapFormat.sampleRate)
        let channelCount = tapFormat.channelCount

        interleavedScratch = [Float](repeating: 0, count: 1024 * Int(channelCount))

        // Capture `onAudioSamples` at install time — the spike contract is
        // "set the callback, then call start()." This matches the existing
        // `.localFile` mode pattern in `AudioInputRouter.startFilePlayback`.
        let callback = onAudioSamples
        player.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            self?.handleTapBuffer(buffer,
                                  sampleRate: sampleRate,
                                  channelCount: channelCount,
                                  callback: callback)
        }

        // Test hygiene (BUG-052): under XCTest / `swift test`, mute the device
        // output so the suite never plays (churned, choppy) fixture audio through
        // the developer's output device. The analysis tap is on the PLAYER node
        // (pre-mixer, above), so zeroing the mixer's output volume silences the
        // hardware without touching the captured signal or the start/stop/cancel
        // lifecycle — SessionLifecycleChurnTests drives this provider for real.
        if NSClassFromString("XCTestCase") != nil {
            engine.mainMixerNode.outputVolume = 0
        }

        try engine.start()
        scheduleFileLoop(player: player, file: file)
        player.play()

        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        self.engine = engine
        self.playerNode = player
        self.audioFile = file
        self.configChangeObserver = observer

        let lastComponent = self.url.lastPathComponent
        let rate = Int(sampleRate)
        logger.info(
            "[LF.1] start: \(lastComponent, privacy: .public) \(rate) Hz \(channelCount) ch")
    }

    /// BUG-021 (2026-05-28): tear-down ref bundle. Snapshotted under the
    /// provider's `lock` in `stop()`, then passed to
    /// `teardownAVFoundation(...)` outside the lock so AVFoundation calls
    /// don't deadlock against the scheduleFile completion callback that
    /// itself acquires the lock.
    private struct TeardownRefs {
        let player: AVAudioPlayerNode?
        let engine: AVAudioEngine?
        let observer: NSObjectProtocol?
    }

    /// Tear down the AVFoundation objects held in `refs`. Safe to call from
    /// any thread; takes no locks. Diagnostic breadcrumbs (BUG-021) land
    /// here so we can confirm in `session.log` that the deadlock pattern is
    /// no longer reachable — each sub-step now runs lock-free.
    nonisolated private static func teardownAVFoundation(
        refs: TeardownRefs,
        diagnostic: ((String) -> Void)?
    ) {
        diagnostic?("provider.teardown ENTER")
        if let observer = refs.observer {
            diagnostic?("provider.teardown removeObserver BEGIN")
            NotificationCenter.default.removeObserver(observer)
            diagnostic?("provider.teardown removeObserver COMPLETE")
        }
        if let player = refs.player {
            diagnostic?("provider.teardown player.stop BEGIN")
            player.stop()
            diagnostic?("provider.teardown player.stop COMPLETE")
            diagnostic?("provider.teardown player.removeTap BEGIN")
            player.removeTap(onBus: 0)
            diagnostic?("provider.teardown player.removeTap COMPLETE")
        }
        if let engine = refs.engine {
            diagnostic?("provider.teardown engine.stop BEGIN")
            engine.stop()
            diagnostic?("provider.teardown engine.stop COMPLETE")
        }
        diagnostic?("provider.teardown EXIT")
    }

    /// Re-schedule the file each time the player drains its scheduled
    /// content — AVAudioPlayerNode has no native loop mode for
    /// `scheduleFile`. Uses the public `lock` to confirm the (player, file)
    /// pair is still the active one before re-scheduling, so concurrent
    /// `stop()` calls cancel cleanly.
    ///
    /// LF.5: when `onFileEnded` is non-nil, the callback fires INSTEAD of
    /// re-scheduling. The caller drives queue advance from there. When
    /// `onFileEnded` is nil, the LF.1 behavior preserves and the file
    /// loops forever.
    private func scheduleFileLoop(player: AVAudioPlayerNode, file: AVAudioFile) {
        player.scheduleFile(file, at: nil) { [weak self, weak player, weak file] in
            guard let self, let player, let file else { return }
            let stillActive: Bool = self.lock.withLock {
                self.playerNode === player && self.audioFile === file
            }
            guard stillActive else { return }
            if let onFileEnded = self.onFileEnded {
                onFileEnded()
                return                                              // LF.5 advance — caller takes over
            }
            self.scheduleFileLoop(player: player, file: file)       // LF.1 single-file loop default
        }
    }

    private func handleTapBuffer(
        _ buffer: AVAudioPCMBuffer,
        sampleRate: Float,
        channelCount: AVAudioChannelCount,
        callback: ((UnsafePointer<Float>, Int, Float, UInt32) -> Void)?
    ) {
        guard let callback else { return }
        guard let floatData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        let totalSamples = frames * Int(channelCount)

        if interleavedScratch.count < totalSamples {
            interleavedScratch = [Float](repeating: 0, count: totalSamples)
        }

        // Process-tap path delivers interleaved float32 stereo (L/R/L/R…).
        // AVAudioPCMBuffer with the processing format gives planar channels.
        // Interleave here so the downstream contract matches exactly.
        if channelCount >= 2 {
            let left = floatData[0]
            let right = floatData[1]
            interleavedScratch.withUnsafeMutableBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                for i in 0..<frames {
                    base[i * 2] = left[i]
                    base[i * 2 + 1] = right[i]
                }
            }
        } else {
            let src = floatData[0]
            interleavedScratch.withUnsafeMutableBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                for i in 0..<frames {
                    base[i] = src[i]
                }
            }
        }

        interleavedScratch.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            callback(base, totalSamples, sampleRate, UInt32(channelCount))
        }
    }

    /// AVAudioEngine fires this when the audio configuration changes
    /// (device switch, sample-rate change). Restart from the beginning —
    /// mid-track resumption requires tracking the play head's frame
    /// position and is out of scope for the LF.1 spike.
    private func handleConfigurationChange() {
        logger.info("[LF.1] AVAudioEngine config change — restarting engine")
        // Dispatch off the notification thread so we don't block it while
        // we tear down + restart. The public `start()` / `stop()` take the
        // lock, so concurrent calls serialize naturally.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.stop()
            do {
                try self.start()
            } catch {
                let msg = error.localizedDescription
                logger.error("[LF.1] Failed to restart engine after config change: \(msg, privacy: .public)")
            }
        }
    }
}

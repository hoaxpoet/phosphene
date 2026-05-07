// swiftlint:disable file_length
// VisualizerEngine+Stems — Background stem separation pipeline.
// Runs StemSeparator on a utility-QoS queue at 5-second cadence,
// feeds per-stem analysis to the render pipeline via buffer(3).
//
// Increment 6.3: dispatch is gated by MLDispatchScheduler. When recent render
// frames are over budget, the 5s separation timer defers the actual MPSGraph call
// to a lighter render moment. Deferral is bounded by maxDeferralMs (2000 ms on
// Tier 1, 1500 ms on Tier 2) to prevent stems from going stale.

import DSP
import Foundation
import Metal
import ML
import os.log
import QuartzCore
import Renderer
import Session
import Shared

private let logger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

// MARK: - Stem Pipeline

extension VisualizerEngine {

    /// Load the optional stem separator; return nil and log on failure.
    static func loadStemSeparator(device: MTLDevice) -> StemSeparator? {
        do {
            let separator = try StemSeparator(device: device)
            logger.info("StemSeparator loaded")
            return separator
        } catch {
            logger.error("StemSeparator failed to load: \(error)")
            return nil
        }
    }

    /// Start the background stem separation timer (5-second cadence).
    func startStemPipeline() {
        guard stemSeparator != nil else {
            logger.info("Stem pipeline skipped — separator not available")
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: stemQueue)
        timer.schedule(deadline: .now() + 10, repeating: 5.0)
        timer.setEventHandler { [weak self] in
            self?.runStemSeparation()
        }
        timer.resume()
        stemTimer = timer
        logger.info("Stem pipeline started (5s cadence, 10s warmup)")
    }

    /// Stop the background stem separation timer.
    func stopStemPipeline() {
        stemTimer?.cancel()
        stemTimer = nil
    }

    /// RMS silence floor — below this the stem pipeline skips CoreML inference.
    private static let silenceRMSThreshold: Float = 1e-6

    // MARK: - Scheduler Gate (Increment 6.3)

    /// Entry point fired by the 5s DispatchSourceTimer on stemQueue.
    ///
    /// Hops to @MainActor to consult `MLDispatchScheduler` using the latest
    /// frame timing from `FrameBudgetManager`. If recent frames are over budget,
    /// the dispatch is deferred and retried after 100 ms. Once the frame window
    /// is clean (or the 2s deferral ceiling is hit), the actual MPSGraph call
    /// is dispatched back to stemQueue via `performStemSeparation()`.
    func runStemSeparation() {
        let now = CACurrentMediaTime()

        // Record the start of the pending window on first entry (not on retries).
        if pendingDispatchStartTime == nil {
            pendingDispatchStartTime = now
            logger.debug("ML: stem dispatch requested, starting pending window")
        }
        let start = pendingDispatchStartTime ?? now
        let pendingForMs = Float((now - start) * 1000)

        Task { @MainActor [weak self] in
            guard let self else { return }

            guard let scheduler = self.mlDispatchScheduler else {
                // No scheduler wired (tests / headless) — dispatch immediately.
                self.stemQueue.async { [weak self] in
                    self?.performStemSeparation()
                }
                return
            }

            let budgetMs: Float = self.deviceTier == .tier1 ? 14.0 : 16.0
            let context = MLDispatchScheduler.DispatchContext(
                recentMaxFrameMs: self.pipeline.frameBudgetManager?.recentMaxFrameMs ?? 0,
                recentFramesObserved: self.pipeline.frameBudgetManager?.recentFramesObserved ?? 0,
                currentTierBudgetMs: budgetMs,
                pendingForMs: pendingForMs
            )

            switch scheduler.decide(context: context) {
            case .dispatchNow, .forceDispatch:
                let elapsed = String(format: "%.0f", pendingForMs)
                logger.debug("ML: dispatch after \(elapsed, privacy: .public)ms pending")
                self.pendingDispatchStartTime = nil
                // Return to stemQueue for the actual 142ms MPSGraph call.
                self.stemQueue.async { [weak self] in
                    self?.performStemSeparation()
                }

            case .defer(let retryInMs):
                // Keep pendingDispatchStartTime intact to preserve the elapsed duration.
                let deadline: DispatchTime = .now() + .milliseconds(Int(retryInMs))
                self.stemQueue.asyncAfter(deadline: deadline) { [weak self] in
                    self?.runStemSeparation()
                }
            }
        }
    }

    // MARK: - Separation Work

    /// Perform the actual stem separation + waveform handoff.
    ///
    /// Extracted from the pre-6.3 `runStemSeparation`. Runs on stemQueue after the
    /// scheduler gate in `runStemSeparation` clears the frame timing check.
    func performStemSeparation() {
        guard let separator = stemSeparator else { return }

        // Snapshot ~10s using the actual tap rate (D-079, QR.1).
        let actualRate = tapSampleRate
        let samples = stemSampleBuffer.snapshotLatest(seconds: 10, sampleRate: actualRate)
        let requiredStereo = Int(actualRate) * 10 * 2
        guard samples.count >= requiredStereo else {
            logger.debug("Stem pipeline: warmup (\(samples.count)/\(requiredStereo) samples)")
            return
        }

        // Idle suppression: skip CoreML inference when the buffer is silence.
        let rms = stemSampleBuffer.rms(seconds: 10, sampleRate: actualRate)
        guard rms > Self.silenceRMSThreshold else {
            logger.debug("Stem pipeline: skipping — silence (RMS=\(rms))")
            return
        }

        do {
            // Pass the actual tap rate; the separator resamples internally
            // to its model rate (D-079, QR.1).
            let result = try separator.separate(
                audio: samples, channelCount: 2, sampleRate: Float(actualRate)
            )

            // Extract mono waveforms from each stem buffer.
            let sampleCount = result.sampleCount
            var stemWaveforms: [[Float]] = []
            for buffer in separator.stemBuffers {
                let count = min(sampleCount, buffer.capacity)
                let waveform = Array(buffer.pointer.prefix(count))
                stemWaveforms.append(waveform)
            }

            // Hand off to the per-frame analyzer on analysisQueue.
            // runPerFrameStemAnalysis slides a 1024-sample window at ~94 Hz
            // so StemFeatures update continuously rather than once per 5s.
            let sepTime = CFAbsoluteTimeGetCurrent()
            stemsStateLock.withLock {
                self.latestSeparatedStems = stemWaveforms
                self.latestSeparationTimestamp = sepTime
            }

            logger.debug("Stem separation complete: \(sampleCount) samples per stem")

            // Diagnostic capture: dump the four separated stem waveforms as WAV
            // files so we can listen to separation quality against real audio.
            // Stem waveforms are at the model rate, not the tap rate (D-079).
            sessionRecorder?.recordStemSeparation(
                stemWaveforms: stemWaveforms,
                sampleRate: Int(StemSeparator.modelSampleRate),
                trackTitle: currentTrack?.title
            )
        } catch {
            logger.error("Stem separation failed: \(error)")
        }
    }

    // MARK: - Live Beat This! Analysis

    /// Minimum buffered audio before the first live Beat This! attempt.
    private static let liveBeatMinSeconds: Double = 10.0

    /// Seconds at which a second attempt is made when the first returns empty.
    /// Gives tracks with quiet intros (Pyramid Song) or complex meters (Money 7/4)
    /// a second shot with more accumulated audio.
    private static let liveBeatRetrySeconds: Double = 20.0

    /// Maximum Beat This! attempts per track. One at 10 s; one retry at 20 s.
    private static let liveBeatMaxAttempts: Int = 2

    /// Drift slope (ms/s) above which the live grid BPM is considered wrong
    /// and a wider-window retry is justified (BUG-007.3). Empirical: reactive
    /// Everlong post-QR.2 showed −4.8 ms/s on a 4 %-low BPM estimate; tracks
    /// with correct BPM stayed under ±2 ms/s.
    private static let liveBeatSlopeMsThreshold: Double = 5.0

    /// Sustained-high-slope duration required to trigger the wider retry
    /// (BUG-007.3). Avoids reacting to transient onset jitter.
    private static let liveBeatSlopeSustainSeconds: Double = 10.0

    /// Minimum gap between live Beat This! attempts of any kind (BUG-007.3).
    /// Prevents thrashing when the wider-window retry also lands wrong.
    private static let liveBeatRetryCooldownSeconds: Double = 30.0

    /// Cap on slope-driven wider-window retries per track (BUG-007.3). After one
    /// 20 s retry we hold the existing grid and log "live BPM unstable".
    private static let liveBeatMaxSlopeRetries: Int = 1

    /// Audio window length (seconds) for slope-driven wider retries (BUG-007.3).
    /// Twice the standard 10 s window — gives Beat This! more onsets to disambiguate
    /// busy mid-frequency content (rock, power chords) where 10 s is insufficient.
    private static let liveBeatWideWindowSeconds: Double = 20.0

    /// Run Beat This! on the live tap audio buffer, triggering once at 10 s and
    /// retrying once at 20 s if the first attempt returns an empty grid.
    ///
    /// Called from `VisualizerEngine+Audio.processAnalysisFrame` at audio-callback
    /// rate. Guards cap at `liveBeatMaxAttempts` per track and skip when a grid is
    /// already installed (Spotify-prepared tracks).
    ///
    /// Beat times from the analyzer are buffer-relative; they are shifted by
    /// `elapsedSeconds − liveBeatMinSeconds` to produce track-relative times for
    /// `LiveBeatDriftTracker`. Raw grids with BPM > 160 are halving-octave-corrected
    /// (double-time artefact from short audio windows) before installing.
    func runLiveBeatAnalysisIfNeeded() {
        let elapsed = mirPipeline.elapsedSeconds   // Double since QR.1 / D-079

        // Path A — no grid: initial-attempts path (10 s, 20 s if first empty).
        if !mirPipeline.liveDriftTracker.hasGrid {
            tryInitialLiveBeatAttempt(elapsed: elapsed)
            return
        }

        // Path B — prepared-cache grid present: skip live inference entirely.
        // Slope-driven retry on prepared grids is BUG-008 territory, out of scope here.
        if liveBeatGridSource == .preparedCache {
            if liveBeatAnalysisAttempts < Self.liveBeatMaxAttempts {
                let bpmStr = String(format: "%.1f", mirPipeline.liveDriftTracker.currentBPM)
                let trackTitle = currentTrack?.title ?? "unknown"
                logger_liveBeat(
                    "LiveBeat: prepared grid present (\(bpmStr) BPM) — " +
                    "skipping live inference for '\(trackTitle)'"
                )
                liveBeatAnalysisAttempts = Self.liveBeatMaxAttempts
            }
            return
        }

        // Path C — live grid installed: slope-driven wider retry (BUG-007.3).
        maybeTriggerSlopeRetry(elapsed: elapsed)
    }

    /// Path A — initial attempts at 10 s and (if first returns empty) 20 s.
    /// Pre-BUG-007.3 behaviour, extracted to keep `runLiveBeatAnalysisIfNeeded` short.
    private func tryInitialLiveBeatAttempt(elapsed: Double) {
        guard liveBeatAnalysisAttempts < Self.liveBeatMaxAttempts else { return }
        let nextTrigger = liveBeatAnalysisAttempts == 0
            ? Self.liveBeatMinSeconds
            : Self.liveBeatRetrySeconds
        guard elapsed >= nextTrigger else { return }

        liveBeatAnalysisAttempts += 1
        liveBeatLastAttemptElapsed = elapsed
        let attemptNum = liveBeatAnalysisAttempts
        dispatchLiveBeatInference(
            elapsed: elapsed,
            windowSeconds: Self.liveBeatMinSeconds,
            attemptLabel: "\(attemptNum)/\(Self.liveBeatMaxAttempts)"
        )
    }

    /// Path C — slope-driven wider retry (BUG-007.3). Capped at one fire per track;
    /// replaces the existing live grid only if Beat This! returns a non-empty 20 s grid.
    /// On a second high-slope event after the retry, logs an unstable-grid warning
    /// and retains the previous grid (no third attempt).
    private func maybeTriggerSlopeRetry(elapsed: Double) {
        guard let slope = mirPipeline.liveDriftTracker.currentDriftSlope() else {
            liveBeatHighSlopeStartElapsed = nil
            return
        }
        guard abs(slope) > Self.liveBeatSlopeMsThreshold else {
            liveBeatHighSlopeStartElapsed = nil
            return
        }
        if liveBeatHighSlopeStartElapsed == nil {
            liveBeatHighSlopeStartElapsed = elapsed
        }
        let sustained = elapsed - (liveBeatHighSlopeStartElapsed ?? elapsed)
        guard sustained >= Self.liveBeatSlopeSustainSeconds else { return }

        if liveBeatSlopeRetryCount >= Self.liveBeatMaxSlopeRetries {
            let slopeStr = String(format: "%+.1f", slope)
            logger_liveBeat(
                "LiveBeat: WARN live BPM unstable on this track (slope=\(slopeStr) ms/s " +
                "after wider-window retry) — retaining previous grid"
            )
            liveBeatHighSlopeStartElapsed = nil
            return
        }
        guard elapsed - liveBeatLastAttemptElapsed >= Self.liveBeatRetryCooldownSeconds else { return }

        liveBeatSlopeRetryCount += 1
        liveBeatHighSlopeStartElapsed = nil
        liveBeatLastAttemptElapsed = elapsed
        let slopeStr = String(format: "%+.1f", slope)
        logger_liveBeat(
            "LiveBeat: WARN live BPM credibility low (slope=\(slopeStr) ms/s sustained " +
            "\(Int(Self.liveBeatSlopeSustainSeconds))s) — retrying with " +
            "\(Int(Self.liveBeatWideWindowSeconds))s window"
        )
        dispatchLiveBeatInference(
            elapsed: elapsed,
            windowSeconds: Self.liveBeatWideWindowSeconds,
            attemptLabel: "slope-retry"
        )
    }

    /// Snapshot audio at `windowSeconds`, fold to mono, dispatch Beat This! on stemQueue.
    /// Shared by Path A (10 s) and Path C (20 s).
    private func dispatchLiveBeatInference(
        elapsed: Double,
        windowSeconds: Double,
        attemptLabel: String
    ) {
        let actualRate = tapSampleRate
        let interleaved = stemSampleBuffer.snapshotLatest(
            seconds: windowSeconds, sampleRate: actualRate
        )
        guard interleaved.count >= 2 else { return }
        var monoMutable = [Float](repeating: 0, count: interleaved.count / 2)
        for i in 0..<monoMutable.count {
            monoMutable[i] = (interleaved[i * 2] + interleaved[i * 2 + 1]) * 0.5
        }
        let mono = monoMutable
        let bufferStartTime = elapsed - windowSeconds
        let elapsedStr = String(format: "%.1f", elapsed)
        let rateStr = String(format: "%.0f", actualRate)
        let sampleCountStr = "\(mono.count)"
        logger_liveBeat(
            "LiveBeat: attempt \(attemptLabel) on " +
            "\(sampleCountStr) samples @ \(rateStr) Hz (t=\(elapsedStr)s)"
        )
        stemQueue.async { [weak self] in
            self?.performLiveBeatInference(
                mono: mono,
                sampleRate: actualRate,
                bufferStartTime: bufferStartTime,
                attemptLabel: attemptLabel
            )
        }
    }

    /// Run the actual Beat This! inference and install the resulting grid.
    ///
    /// Extracted from `runLiveBeatAnalysisIfNeeded` to keep that function within
    /// the 60-line SwiftLint gate. Always called on `stemQueue`.
    private func performLiveBeatInference(
        mono: [Float], sampleRate: Double,
        bufferStartTime: Double, attemptLabel: String
    ) {
        // Lazy-load the analyzer on first use (weight loading is heavy).
        if liveBeatGridAnalyzer == nil {
            let device = context.device
            do {
                liveBeatGridAnalyzer = try DefaultBeatGridAnalyzer(device: device)
            } catch {
                logger_liveBeat("LiveBeat: analyzer init failed: \(error)")
                return
            }
        }

        guard let analyzer = liveBeatGridAnalyzer else { return }
        // Use the actual tap rate (typically 48000 Hz) so the Beat This!
        // mel spectrogram covers the correct duration and BPM is accurate.
        let rawGrid = analyzer.analyzeBeatGrid(samples: mono, sampleRate: sampleRate)
        guard !rawGrid.beats.isEmpty else {
            logger_liveBeat("LiveBeat: attempt \(attemptLabel) returned empty grid")
            return
        }

        // Apply halving octave-correction (BPM > 160 → double-time artefact
        // common in 10-second windows). BPM < 80 is intentionally left alone —
        // some tracks genuinely have slow tempos (Pyramid Song ~68 BPM).
        let correctedGrid = rawGrid.halvingOctaveCorrected()

        // Shift beat times from buffer-relative to track-relative.
        let grid = correctedGrid.offsetBy(bufferStartTime)
        let bpmStr = String(format: "%.1f", grid.bpm)
        let beatCount = grid.beats.count
        let meter = grid.beatsPerBar
        let firstBeat = grid.beats.first.map { String(format: "%.3f", $0) } ?? "none"
        logger_liveBeat(
            "LiveBeat: grid ready (attempt \(attemptLabel)) — " +
            "\(beatCount) beats, \(bpmStr) BPM, \(meter)/X meter, firstBeat=\(firstBeat)s"
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            let replacedExisting = self.mirPipeline.liveDriftTracker.hasGrid
            let trackTitle = self.currentTrack?.title ?? "unknown"
            self.mirPipeline.setBeatGrid(grid)
            self.liveBeatGridSource = .liveAnalysis   // BUG-007.3: source-track for slope retry path
            let replaceNote = replacedExisting ? " (replaced existing grid)" : ""
            self.logger_liveBeat(
                "BEAT_GRID_INSTALL: source=liveAnalysis, track='\(trackTitle)', " +
                "bpm=\(bpmStr), beats=\(beatCount), meter=\(meter)/X, " +
                "firstBeat=\(firstBeat)s\(replaceNote)"
            )
            self.sessionRecorder?.log(
                "BeatGrid installed: source=liveAnalysis, track='\(trackTitle)', " +
                "bpm=\(bpmStr), beats=\(beatCount), meter=\(meter)/X"
            )
        }
    }

    private func logger_liveBeat(_ msg: String) {
        logger.info("\(msg, privacy: .public)")
    }

    /// Reset the stem pipeline on track change, loading pre-analyzed data from cache
    /// when available. `caller` (BUG-006.1) identifies which code path invoked us.
    func resetStemPipeline(
        for identity: TrackIdentity? = nil,
        caller: ResetStemPipelineCaller = .trackChange
    ) {
        logWiringResetStemPipelineEnter(title: identity?.title ?? "<nil>", caller: caller)   // BUG-006.1

        stemAnalyzer.reset()

        // Clear the per-frame analyzer's source waveforms so stems don't
        // leak across tracks. Next separation will repopulate them.
        stemsStateLock.withLock {
            self.latestSeparatedStems = []
            self.latestSeparationTimestamp = 0
        }

        // A deferred dispatch from the previous track is irrelevant on the new track.
        pendingDispatchStartTime = nil

        // Allow live Beat This! to re-fire (up to liveBeatMaxAttempts) for the new track.
        liveBeatAnalysisAttempts = 0

        // BUG-007.3: per-track slope-retry bookkeeping resets on every track change.
        liveBeatSlopeRetryCount = 0
        liveBeatHighSlopeStartElapsed = nil
        liveBeatLastAttemptElapsed = -.infinity
        liveBeatGridSource = .none

        pipeline.spectralHistory.reset()

        // BUG-006.1 instrumentation: cache-lookup log (see WiringLogs helpers).
        if let identity { logWiringStemCacheLookup(identity: identity) }

        if let identity, let cached = stemCache?.loadForPlayback(track: identity) {
            let replacedExisting = mirPipeline.liveDriftTracker.hasGrid
            pipeline.setStemFeatures(cached.stemFeatures)
            mirPipeline.setBeatGrid(cached.beatGrid.offsetBy(0))
            let grid = cached.beatGrid
            let title = identity.title
            if !grid.beats.isEmpty {
                liveBeatGridSource = .preparedCache   // BUG-007.3: tag for slope-retry routing
                let bpmStr = String(format: "%.1f", grid.bpm)
                let firstBeat = grid.beats.first.map { String(format: "%.3f", $0) } ?? "none"
                let replaceNote = replacedExisting ? " (replaced existing grid)" : ""
                let beatCount = grid.beats.count
                let meter = grid.beatsPerBar
                // swiftlint:disable:next line_length
                logger.info("BEAT_GRID_INSTALL: source=preparedCache, track='\(title)', bpm=\(bpmStr), beats=\(beatCount), meter=\(meter)/X, firstBeat=\(firstBeat)s\(replaceNote)")
                // swiftlint:disable:next line_length
                sessionRecorder?.log("BeatGrid installed: source=preparedCache, track='\(title)', bpm=\(bpmStr), beats=\(beatCount), meter=\(meter)/X")
            } else {
                // swiftlint:disable:next line_length
                logger.info("BEAT_GRID_INSTALL: source=preparedCache, track='\(title)' — empty grid, live inference will be allowed")
            }
        } else {
            pipeline.setStemFeatures(.zero)
            mirPipeline.setBeatGrid(nil)
            let trackDesc = identity.map { "'\($0.title)'" } ?? "unknown"
            logger.info(
                "BEAT_GRID_INSTALL: source=none, track=\(trackDesc) — no cache entry, live inference will be allowed"
            )
        }
        // StemSampleBuffer intentionally not reset — continues accumulating for live separation.
    }
}

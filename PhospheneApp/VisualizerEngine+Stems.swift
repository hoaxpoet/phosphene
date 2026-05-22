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
import Presets
import QuartzCore
import Renderer
import Session
import Shared
import simd

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

    /// RMS silence floor — below this the stem pipeline skips MPSGraph inference.
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
        let isFirstEntry = pendingDispatchStartTime == nil
        if isFirstEntry {
            pendingDispatchStartTime = now
            logger.debug("ML: stem dispatch requested, starting pending window")
        }
        let start = pendingDispatchStartTime ?? now
        let pendingForMs = Float((now - start) * 1000)

        // BUG-012 instrumentation
        BUG012Probe.log(
            "runStemSeparation timer/retry",
            detail: "firstEntry=\(isFirstEntry) pending=\(String(format: "%.0f", pendingForMs))ms"
        )

        Task { @MainActor [weak self] in
            guard let self else {
                BUG012Probe.notice("runStemSeparation MainActor self=nil — engine deallocated")
                return
            }

            guard let scheduler = self.mlDispatchScheduler else {
                // No scheduler wired (tests / headless) — dispatch immediately.
                BUG012Probe.log("runStemSeparation no-scheduler → queue performStemSeparation")
                self.stemQueue.async { [weak self] in
                    if self == nil {
                        BUG012Probe.notice("stemQueue.async self=nil before performStemSeparation (no-scheduler path)")
                        return
                    }
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
                    if self == nil {
                        BUG012Probe.notice("stemQueue.async self=nil before performStemSeparation")
                        return
                    }
                    self?.performStemSeparation()
                }

            case .defer(let retryInMs):
                // Keep pendingDispatchStartTime intact to preserve the elapsed duration.
                let deadline: DispatchTime = .now() + .milliseconds(Int(retryInMs))
                self.stemQueue.asyncAfter(deadline: deadline) { [weak self] in
                    if self == nil {
                        BUG012Probe.notice("stemQueue.asyncAfter self=nil before runStemSeparation retry")
                        return
                    }
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
        let dispatchID = BUG012Probe.nextDispatchID()
        BUG012Probe.enterStemDispatch(dispatchID: dispatchID)

        guard let separator = stemSeparator else {
            BUG012Probe.exitStemDispatch(dispatchID: dispatchID, outcome: "no-separator")
            return
        }

        // Snapshot ~10s using the actual tap rate (D-079, QR.1).
        let actualRate = tapSampleRate
        let samples = stemSampleBuffer.snapshotLatest(seconds: 10, sampleRate: actualRate)
        let requiredStereo = Int(actualRate) * 10 * 2
        guard samples.count >= requiredStereo else {
            logger.debug("Stem pipeline: warmup (\(samples.count)/\(requiredStereo) samples)")
            BUG012Probe.exitStemDispatch(dispatchID: dispatchID, outcome: "warmup-skip")
            return
        }

        // Idle suppression: skip MPSGraph inference when the buffer is silence.
        let rms = stemSampleBuffer.rms(seconds: 10, sampleRate: actualRate)
        guard rms > Self.silenceRMSThreshold else {
            logger.debug("Stem pipeline: skipping — silence (RMS=\(rms))")
            BUG012Probe.exitStemDispatch(dispatchID: dispatchID, outcome: "silence-skip")
            return
        }

        do {
            // Pass the actual tap rate; the separator resamples internally
            // to its model rate (D-079, QR.1).
            BUG012Probe.notice(
                "separator.separate CALL",
                dispatchID: dispatchID,
                detail: "samples=\(samples.count) sr=\(actualRate)"
            )
            let result = try separator.separate(
                audio: samples, channelCount: 2, sampleRate: Float(actualRate)
            )
            BUG012Probe.notice("separator.separate RETURN", dispatchID: dispatchID)

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
            BUG012Probe.exitStemDispatch(dispatchID: dispatchID, outcome: "ok")
        } catch {
            logger.error("Stem separation failed: \(error)")
            BUG012Probe.exitStemDispatch(dispatchID: dispatchID, outcome: "threw")
        }

        // BUG-007.9: hybrid runtime recalibration. After stem separation succeeds
        // (i.e. we have ≥10 s of buffered tap audio AND lock has stabilised),
        // re-run GridOnsetCalibrator against the *tap* audio to override the
        // prep-time bias. Closes the preview-vs-tap encoding mismatch.
        runtimeRecalibrationIfDue()
    }

    // MARK: - CS.1.y.2-redo: Cold-Start Phase Correction (BUG-017)

    /// Beat This! window snapshotted for the cold-start phase correction.
    /// 15 s established by the CS.1.y.2-redo Step 1 measurement (2026-05-22):
    /// reproduces full-window phase within ≤ 8 ms across both reference
    /// captures, on every test track including HUMBLE and Money.
    private static let coldStartPhaseWindowSeconds: Double = 15.0

    /// Minimum elapsed playback time before the cold-start correction fires.
    /// Matches the window length — the buffer-coverage guard inside
    /// `computeColdStartLiveGrid` requires at least `window − 0.5 s` of real
    /// audio, so a sub-15 s elapsed value cannot satisfy it anyway.
    private static let coldStartPhaseMinElapsedSeconds: Double = 15.0

    /// CS.1.y.2-redo cold-start phase correction (replaces BUG-007.9's
    /// onset-based recalibration, Failed Approach #68). Snapshot ~15 s of
    /// tap audio, run Beat This!, compare its phase against the installed
    /// cached grid, and — when the loose confidence gate clears — re-seed
    /// `drift` so the visual beat aligns with the audible beats. One-shot
    /// per track. Runs on `stemQueue` (from `performStemSeparation`).
    /// The prep-time `gridOnsetOffsetMs` seed via `GridOnsetCalibrator` is
    /// unaffected — only the runtime correction is reworked.
    private func runtimeRecalibrationIfDue() {
        guard !runtimeRecalibrationDone else { return }
        let tracker = mirPipeline.liveDriftTracker
        guard tracker.hasGrid else { return }
        let elapsed = mirPipeline.elapsedSeconds
        guard elapsed >= Self.coldStartPhaseMinElapsedSeconds else { return }
        guard let analyzer = ensureLiveBeatGridAnalyzer() else {
            runtimeRecalibrationDone = true   // latch on init failure too
            return
        }
        guard let liveGrid = computeColdStartLiveGrid(
            elapsed: elapsed, analyzer: analyzer
        ) else { return }
        runtimeRecalibrationDone = true   // one-shot regardless of outcome
        let trackTitle = currentTrack?.title ?? "unknown"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = self.mirPipeline.liveDriftTracker
                .applyColdStartPhaseCorrection(liveGrid: liveGrid)
            self.logColdStartPhaseOutcome(outcome, trackTitle: trackTitle)
        }
    }

    /// Lazy-load `liveBeatGridAnalyzer` (shared with the reactive-mode live
    /// Beat This! path). Returns nil on init failure.
    private func ensureLiveBeatGridAnalyzer() -> DefaultBeatGridAnalyzer? {
        if let existing = liveBeatGridAnalyzer { return existing }
        do {
            let analyzer = try DefaultBeatGridAnalyzer(device: context.device)
            liveBeatGridAnalyzer = analyzer
            return analyzer
        } catch {
            logger.error("CS.1.y.2-redo: DefaultBeatGridAnalyzer init failed: \(error)")
            return nil
        }
    }

    /// Snapshot the latest tap audio, run Beat This! on it, and shift the
    /// resulting beat times into track-relative playback time. Returns nil
    /// when the buffer is too short or Beat This! returned an empty grid —
    /// the caller retries on the next stem-separation cycle.
    private func computeColdStartLiveGrid(
        elapsed: Double, analyzer: DefaultBeatGridAnalyzer
    ) -> BeatGrid? {
        let actualRate = tapSampleRate
        let interleaved = stemSampleBuffer.snapshotLatest(
            seconds: Self.coldStartPhaseWindowSeconds, sampleRate: actualRate
        )
        guard interleaved.count >= 2 else { return nil }
        let monoCount = interleaved.count / 2
        let bufferedSeconds = Double(monoCount) / actualRate
        // Require the snapshot to cover at least the target window minus a
        // small slack; otherwise wait for the next stem-separation cycle.
        guard bufferedSeconds >= Self.coldStartPhaseWindowSeconds - 0.5 else { return nil }
        var mono = [Float](repeating: 0, count: monoCount)
        for i in 0..<monoCount {
            mono[i] = (interleaved[i * 2] + interleaved[i * 2 + 1]) * 0.5
        }
        let rawGrid = analyzer.analyzeBeatGrid(samples: mono, sampleRate: actualRate)
        guard !rawGrid.beats.isEmpty else { return nil }
        // No halving-octave correction at 15 s — Beat This! is reliable on
        // this window (per redo.1 measurement). The BPM tolerance gate in
        // `applyColdStartPhaseCorrection` catches any real disagreement.
        let bufferStartTime = elapsed - bufferedSeconds
        return rawGrid.offsetBy(bufferStartTime)
    }

    /// Single per-track log line summarising the cold-start phase correction
    /// outcome. Called on MainActor after `applyColdStartPhaseCorrection`.
    @MainActor
    private func logColdStartPhaseOutcome(
        _ outcome: LiveBeatDriftTracker.ColdStartPhaseCorrectionOutcome,
        trackTitle: String
    ) {
        let prefix = "CS.1.y.2-redo cold-start phase correction"
        let detail = describeColdStartOutcome(outcome)
        logger_liveBeat("\(prefix): track='\(trackTitle)' \(detail)")
        sessionRecorder?.log("\(prefix): track='\(trackTitle)' \(detail)")
    }

    /// Format a one-line description of an outcome. Pure — extracted so
    /// `logColdStartPhaseOutcome` stays under the function-body length cap.
    private func describeColdStartOutcome(
        _ outcome: LiveBeatDriftTracker.ColdStartPhaseCorrectionOutcome
    ) -> String {
        switch outcome {
        case .applied(let driftMs, let matched, let resultant):
            let driftStr = String(format: "%+.1f", driftMs)
            let rStr = String(format: "%.2f", resultant)
            return "applied — drift=\(driftStr) ms, R=\(rStr), matched=\(matched)"
        case .skippedNoGrid:
            return "skipped — no cached grid"
        case .skippedLiveGridDegenerate(let beats):
            return "skipped — live grid degenerate (\(beats) beats)"
        case .skippedTempoDisagreement(let live, let cached):
            let liveStr = String(format: "%.1f", live)
            let cachedStr = String(format: "%.1f", cached)
            return "skipped — BPM disagreement live=\(liveStr) vs cached=\(cachedStr)"
        case .skippedNoMatches:
            return "skipped — no matched beat pairs"
        case .skippedLowConfidence(let resultant):
            let rStr = String(format: "%.2f", resultant)
            return "skipped — low confidence (R=\(rStr))"
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
        guard liveBeatAnalysisAttempts < Self.liveBeatMaxAttempts else { return }
        guard !mirPipeline.liveDriftTracker.hasGrid else {
            // Prepared-cache grid already installed — live inference must not overwrite it.
            // The offline 30-second path is more reliable than the live 10-second window,
            // especially for complex-meter tracks (Money 7/4, Pyramid Song 16/8).
            let bpmStr = String(format: "%.1f", mirPipeline.liveDriftTracker.currentBPM)
            let trackTitle = currentTrack?.title ?? "unknown"
            logger_liveBeat(
                "LiveBeat: prepared grid present (\(bpmStr) BPM) — " +
                "skipping live inference for '\(trackTitle)'"
            )
            liveBeatAnalysisAttempts = Self.liveBeatMaxAttempts
            return
        }
        let elapsed = mirPipeline.elapsedSeconds   // Double since QR.1 / D-079
        let nextTrigger = liveBeatAnalysisAttempts == 0
            ? Self.liveBeatMinSeconds
            : Self.liveBeatRetrySeconds
        guard elapsed >= nextTrigger else { return }

        liveBeatAnalysisAttempts += 1   // prevent concurrent/duplicate calls

        // Snapshot interleaved stereo PCM using the actual tap sample rate.
        // The buffer was initialized at 44100 Hz but the tap typically runs at
        // 48000 Hz. Passing the real rate ensures we retrieve a full 10 seconds
        // of audio instead of ~9.2 seconds (882000 vs 960000 samples). (D-079)
        let actualRate = tapSampleRate
        let interleaved = stemSampleBuffer.snapshotLatest(
            seconds: Self.liveBeatMinSeconds, sampleRate: actualRate
        )
        guard interleaved.count >= 2 else { return }

        var monoMutable = [Float](repeating: 0, count: interleaved.count / 2)
        for i in 0..<monoMutable.count {
            monoMutable[i] = (interleaved[i * 2] + interleaved[i * 2 + 1]) * 0.5
        }
        let mono = monoMutable

        let bufferStartTime = elapsed - Self.liveBeatMinSeconds
        let attemptNum = liveBeatAnalysisAttempts   // capture before async
        let elapsedStr = String(format: "%.1f", elapsed)
        let rateStr = String(format: "%.0f", actualRate)
        let sampleCountStr = "\(mono.count)"
        logger_liveBeat(
            "LiveBeat: attempt \(attemptNum)/\(Self.liveBeatMaxAttempts) on " +
            "\(sampleCountStr) samples @ \(rateStr) Hz (t=\(elapsedStr)s)"
        )

        stemQueue.async { [weak self] in
            self?.performLiveBeatInference(
                mono: mono,
                sampleRate: actualRate,
                bufferStartTime: bufferStartTime,
                attemptNum: attemptNum
            )
        }
    }

    /// Run the actual Beat This! inference and install the resulting grid.
    ///
    /// Extracted from `runLiveBeatAnalysisIfNeeded` to keep that function within
    /// the 60-line SwiftLint gate. Always called on `stemQueue`.
    private func performLiveBeatInference(
        mono: [Float], sampleRate: Double,
        bufferStartTime: Double, attemptNum: Int
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
            let retryNote = attemptNum < Self.liveBeatMaxAttempts
                ? "will retry at \(Int(Self.liveBeatRetrySeconds))s"
                : "no more retries"
            logger_liveBeat("LiveBeat: attempt \(attemptNum) returned empty grid — \(retryNote)")
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
            "LiveBeat: grid ready (attempt \(attemptNum)) — " +
            "\(beatCount) beats, \(bpmStr) BPM, \(meter)/X meter, firstBeat=\(firstBeat)s"
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            let replacedExisting = self.mirPipeline.liveDriftTracker.hasGrid
            let trackTitle = self.currentTrack?.title ?? "unknown"
            self.mirPipeline.setBeatGrid(grid)
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

        // BUG-007.9: hybrid runtime recalibration is one-shot per track.
        runtimeRecalibrationDone = false

        pipeline.spectralHistory.reset()

        // BUG-006.1 instrumentation: cache-lookup log (see WiringLogs helpers).
        if let identity { logWiringStemCacheLookup(identity: identity) }

        if let identity, let cached = stemCache?.loadForPlayback(track: identity) {
            let replacedExisting = mirPipeline.liveDriftTracker.hasGrid
            pipeline.setStemFeatures(cached.stemFeatures)
            // BUG-007.8: pass per-track grid-vs-onset offset as initial drift bias.
            mirPipeline.setBeatGrid(
                cached.beatGrid.offsetBy(0),
                initialDriftMs: cached.gridOnsetOffsetMs
            )
            let grid = cached.beatGrid
            let title = identity.title
            if !grid.beats.isEmpty {
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

        // LM.3 (D-LM-e3) + LM.4.7 (D-LM-palette-library): refresh Lumen
        // Mosaic's per-track palette seed AND draw a fresh per-song
        // palette from the 18-palette library. No-op when Lumen Mosaic
        // is not the active preset.
        if let identity, let lumenEngine = lumenPatternEngine {
            refreshLumenPaletteForTrack(identity: identity, lumenEngine: lumenEngine)
        }
    }

    /// LM.4.7 per-track palette refresh — extracted into a helper to keep
    /// `resetStemPipeline(...)` under SwiftLint's function_body_length cap.
    /// Sets the track seed, draws a mood-biased palette from the 18-palette
    /// library (excluding the last `kAntiRepeatWindow` drawn indices), and
    /// pushes the result through the slot-8 GPU payload.
    ///
    /// The FNV-1a track seed is reused both as the deterministic PRNG seed
    /// for the palette draw and as a sampling-order perturbation inside
    /// the palette (the `lm_track_seed_hash` MSL path).
    ///
    /// Mood comes from the prepared `TrackProfile` if cached; falls back
    /// to mood-space centre `(0, 0)` in live reactive mode pre-convergence
    /// — biases toward Autumnal / Art Deco (the neutral-quadrant anchors)
    /// without crashing. Documented per D-LM-palette-library.
    private func refreshLumenPaletteForTrack(
        identity: TrackIdentity,
        lumenEngine: LumenPatternEngine
    ) {
        let hash = Self.lumenTrackSeedHash(for: identity)
        lumenEngine.setTrackSeed(fromHash: hash)

        let mood: SIMD2<Float>
        if let profile = stemCache?.trackProfile(for: identity) {
            mood = SIMD2<Float>(profile.mood.valence, profile.mood.arousal)
        } else {
            mood = SIMD2<Float>(0, 0)
        }
        let chosen = LumenMosaicPaletteLibrary.selectPalette(
            mood: mood,
            recentPaletteIndices: lumenEngine.recentPaletteIndices,
            trackSeed: hash
        )
        lumenEngine.setPalette(LumenMosaicPaletteLibrary.all[chosen])

        // FIFO append + trim to the window size. With 18 palettes and
        // window=3, even after a long session 15 candidates remain
        // mood-weighted per draw.
        var window = lumenEngine.recentPaletteIndices
        window.append(chosen)
        let cap = LumenMosaicPaletteLibrary.kAntiRepeatWindow
        if window.count > cap {
            window.removeFirst(window.count - cap)
        }
        lumenEngine.recentPaletteIndices = window
    }

    /// Derive a deterministic 64-bit seed from a track identity. Uses the
    /// title + artist string (lowercased so cover-vs-original variants of
    /// the same track on different services land on the same seed when
    /// they differ only in casing). FNV-1a 64-bit — fast, collision rate
    /// acceptable for a 4-component perturbation.
    private static func lumenTrackSeedHash(for identity: TrackIdentity) -> UInt64 {
        let key = (identity.title.lowercased() + "|" + identity.artist.lowercased())
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

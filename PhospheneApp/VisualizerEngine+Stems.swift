// swiftlint:disable file_length
// VisualizerEngine+Stems — Background stem separation pipeline.
// Runs StemSeparator on a utility-QoS queue at `stemSeparationPeriodSeconds`
// cadence (2 s since BUG-086; the period is the floor on stem latency),
// feeds per-stem analysis to the render pipeline via buffer(3).
//
// Increment 6.3: dispatch is gated by MLDispatchScheduler. When recent render
// frames are over budget, the separation timer defers the actual MPSGraph call
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

    /// Start the background stem separation timer at `stemSeparationPeriodSeconds`.
    func startStemPipeline() {
        guard stemSeparator != nil else {
            logger.info("Stem pipeline skipped — separator not available")
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: stemQueue)
        timer.schedule(deadline: .now() + 10, repeating: Self.stemSeparationPeriodSeconds)
        timer.setEventHandler { [weak self] in
            self?.runStemSeparation()
        }
        timer.resume()
        stemTimer = timer
        let summary = String(
            format: "%.1fs cadence, 10s warmup, %.1fs nominal feature latency",
            Self.stemSeparationPeriodSeconds,
            Self.stemNominalLatencySeconds
        )
        logger.info("Stem pipeline started (\(summary, privacy: .public))")
    }

    /// Stop the background stem separation timer.
    func stopStemPipeline() {
        stemTimer?.cancel()
        stemTimer = nil
    }

    /// RMS silence floor — below this the stem pipeline skips MPSGraph inference.
    private static let silenceRMSThreshold: Float = 1e-6

    // MARK: - Separation cadence and read alignment (BUG-086)

    // These four values are one interlocking set. They were three independent
    // literals across two files until BUG-086, which is precisely why a ~5.4 s
    // preset-facing stem latency sat unnoticed under every stem-driven preset
    // (Aurora Veil's `other_energy_dev` route included) — no single line was
    // wrong, and nothing named the relationship between them.

    /// Length of the tap-audio chunk handed to the separator.
    ///
    /// **Not a free parameter.** `StemSeparator.modelFrameCount` (431) is fixed by
    /// the exported Open-Unmix model, requiring `requiredMonoSamples` = 440320
    /// mono samples ≈ 10 s at the model rate. Shortening the chunk to cut latency
    /// would need a re-exported model, so it is not a lever here.
    static let stemChunkSeconds: Double = 10.0

    /// How often separation runs — and therefore the floor on stem latency.
    ///
    /// The chunk's newest sample is "now", so reading at `stemReadStartSeconds`
    /// into it yields audio `stemChunkSeconds − stemReadStartSeconds` old. The
    /// read window then advances in real time and can only do so for that same
    /// span before clamping at the chunk's end, and that span has to cover one
    /// separation period. Hence **latency ≥ period**, and the period is the only
    /// lever once the chunk is fixed.
    ///
    /// Cost is one full MPSGraph inference per period whatever the period is (the
    /// model always consumes the whole 10 s), so halving the period doubles
    /// inference duty. `MLDispatchScheduler` (D-059) absorbs the pressure by
    /// deferring when frames run over budget.
    ///
    /// Was `5.0` through 2026-08-11, measured at ≈5.4 s of preset-facing latency
    /// against ≈0.3 s for the real-time band features (BUG-086).
    static let stemSeparationPeriodSeconds: Double = 2.0

    /// Slack beyond one period before the read window can clamp.
    ///
    /// Absorbs inference time and `MLDispatchScheduler` deferral so the window
    /// does not run off the chunk's end between separations. Clamping is not a
    /// stale freeze — the window pins to the chunk's *newest* audio, so latency
    /// momentarily collapses toward zero and then jumps back when the next chunk
    /// lands. That discontinuity reads as a glitch, which is why this is > 0.
    static let stemReadMarginSeconds: Double = 0.5

    /// Where the per-frame read window starts inside the chunk. **Derived, never a
    /// literal** — see the note above this block.
    static var stemReadStartSeconds: Double {
        max(0, stemChunkSeconds - stemSeparationPeriodSeconds - stemReadMarginSeconds)
    }

    /// Nominal age of the audio the stem features describe.
    static var stemNominalLatencySeconds: Double {
        stemChunkSeconds - stemReadStartSeconds
    }

    /// Record separation cost to `session.log` (BUG-086).
    ///
    /// The duty-cycle estimate that justified dropping the period to 2 s rested on
    /// a 142 ms inference figure that existed only in a code comment — no session
    /// artifact carried it, so the estimate could not be checked against a real
    /// capture. This line makes the cadence decision falsifiable: grep
    /// `STEM_SEPARATION` in any session and the measured duty is right there.
    func logSeparationCost(inferenceSeconds: Double) {
        let inferenceMs = inferenceSeconds * 1000.0
        sessionRecorder?.log(String(
            format: "STEM_SEPARATION: inference=%.1fms period=%.1fs duty=%.1f%% "
                + "nominal_latency=%.1fs",
            inferenceMs,
            Self.stemSeparationPeriodSeconds,
            100.0 * inferenceSeconds / Self.stemSeparationPeriodSeconds,
            Self.stemNominalLatencySeconds
        ))
    }

    // MARK: - Scheduler Gate (Increment 6.3)

    /// Entry point fired by the cadence DispatchSourceTimer on stemQueue.
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

        // Snapshot the model's fixed chunk length using the actual tap rate
        // (D-079, QR.1). Length is pinned by the model, not chosen — see
        // `stemChunkSeconds` (BUG-086).
        let actualRate = tapSampleRate
        let chunkSeconds = Self.stemChunkSeconds
        let samples = stemSampleBuffer.snapshotLatest(
            seconds: chunkSeconds, sampleRate: actualRate
        )
        let requiredStereo = Int(actualRate * chunkSeconds) * 2
        guard samples.count >= requiredStereo else {
            logger.debug("Stem pipeline: warmup (\(samples.count)/\(requiredStereo) samples)")
            BUG012Probe.exitStemDispatch(dispatchID: dispatchID, outcome: "warmup-skip")
            return
        }

        // Idle suppression: skip MPSGraph inference when the buffer is silence.
        let rms = stemSampleBuffer.rms(seconds: chunkSeconds, sampleRate: actualRate)
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
            let inferenceT0 = CFAbsoluteTimeGetCurrent()
            let result = try separator.separate(
                audio: samples, channelCount: 2, sampleRate: Float(actualRate)
            )
            BUG012Probe.notice("separator.separate RETURN", dispatchID: dispatchID)

            // CLEAN.1.2 (BUG-031): read the stems BY VALUE from the result — never
            // from the shared `separator.stemBuffers`, which the session-prep path
            // races over. `result.stemWaveforms` is this call's own data.
            let sampleCount = result.sampleCount
            let stemWaveforms = result.stemWaveforms

            // Hand off to the per-frame analyzer on analysisQueue.
            // runPerFrameStemAnalysis slides a 1024-sample window at ~94 Hz
            // so StemFeatures update continuously rather than once per period.
            let sepTime = CFAbsoluteTimeGetCurrent()
            stemsStateLock.withLock {
                self.latestSeparatedStems = stemWaveforms
                self.latestSeparationTimestamp = sepTime
            }

            logger.debug("Stem separation complete: \(sampleCount) samples per stem")

            logSeparationCost(inferenceSeconds: sepTime - inferenceT0)

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

    // MARK: - BUG-007.9: hybrid runtime recalibration

    /// Minimum tap-audio duration (seconds) to snapshot for runtime recalibration.
    /// Sized to fit comfortably within `stemSampleBuffer.maxSeconds` (~13 s).
    private static let runtimeRecalibrationWindowSeconds: Double = 12.0

    /// Minimum `matchedOnsetCount` before runtime recalibration fires. After
    /// this many tight matches, the EMA has settled enough that overriding
    /// the bias won't introduce transient mid-track jumps.
    private static let runtimeRecalibrationMinMatchedOnsets: Int = 8

    /// Replay the latest 12 s of tap audio through GridOnsetCalibrator and
    /// override the drift EMA with the runtime-derived offset. One-shot per
    /// track. Runs on `stemQueue` (already on it from `performStemSeparation`).
    /// Skips when:
    ///   - already done for this track
    ///   - no grid is installed (reactive mode)
    ///   - lock hasn't stabilised yet (matchedOnsets < 8)
    ///   - insufficient tap-audio buffered
    ///   - calibrator returns 0 (no signal — keep prep-time bias)
    private func runtimeRecalibrationIfDue() {
        guard !runtimeRecalibrationDone else { return }
        let tracker = mirPipeline.liveDriftTracker
        guard tracker.hasGrid else { return }
        guard tracker.matchedOnsetCount >= Self.runtimeRecalibrationMinMatchedOnsets else { return }
        let actualRate = tapSampleRate
        let interleaved = stemSampleBuffer.snapshotLatest(
            seconds: Self.runtimeRecalibrationWindowSeconds, sampleRate: actualRate
        )
        guard interleaved.count >= 2 else { return }
        var mono = [Float](repeating: 0, count: interleaved.count / 2)
        for i in 0..<mono.count {
            mono[i] = (interleaved[i * 2] + interleaved[i * 2 + 1]) * 0.5
        }
        let grid = tracker.currentGrid
        let calibrator = GridOnsetCalibrator()
        let runtimeOffsetMs = calibrator.calibrate(
            samples: mono, sampleRate: actualRate, grid: grid
        )
        // Skip apply if calibrator couldn't compute a result (no onsets in
        // window, etc.) — keep the prep-time bias rather than zeroing out.
        guard runtimeOffsetMs != 0 else {
            runtimeRecalibrationDone = true
            logger_liveBeat(
                "BUG-007.9: runtime recalibration skipped — calibrator returned 0 (insufficient signal)"
            )
            return
        }
        let priorMs = tracker.currentDriftMs
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.mirPipeline.liveDriftTracker.applyCalibration(driftMs: runtimeOffsetMs)
            self.runtimeRecalibrationDone = true
            let priorStr = String(format: "%+.1f", priorMs)
            let newStr = String(format: "%+.1f", runtimeOffsetMs)
            self.logger_liveBeat(
                "BUG-007.9: runtime recalibration fired — drift \(priorStr) → \(newStr) ms (12 s tap audio)"
            )
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

        // FBS / D-154: resolve the new track's beat regularity once, while the
        // cache is reachable (MainActor). Consumed by the reactive evaluate off
        // the analysis path. nil (uncached / no identity) = permissive.
        currentTrackBeatIrregular = identity.flatMap { stemCache?.beatIrregular(for: $0) }

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

        // IFC.4 (D-177) — clear instrument-family activity unconditionally on
        // every track-change path so a prior track's series can't leak. The
        // cache-hit branch below reinstalls; the next analysis frame samples it.
        currentFamilySeries = []
        pipeline.setInstrumentFamilyActivity(smoothed: .zero, dev: .zero)

        // BUG-006.1 instrumentation: cache-lookup log (see WiringLogs helpers).
        if let identity { logWiringStemCacheLookup(identity: identity) }

        if let identity, let cached = stemCache?.loadForPlayback(track: identity) {
            let replacedExisting = mirPipeline.liveDriftTracker.hasGrid
            // BUG-064 light warmup: the cached preview snapshot is static — mark it
            // not-live so Lumen's lights drive from live continuous-energy until the
            // per-frame analyzer converges, instead of freezing on it for ~10 s.
            pipeline.setStemFeatures(cached.stemFeatures, live: false)
            // CSP.3 (2026-05-27) — install the cached bass proportion for
            // the track. When the ffoColdStartFixEnabled toggle is ON,
            // compute proportion = bassEnergy / total from the preview
            // snapshot. When OFF, install 0.15 (the formula pivot per
            // CSP.3.1) so the FFO shader's one-sided baseline contribution
            // collapses to 0, restoring pre-CSP.3 behaviour for the
            // A/B off-arm. Sentinel value MUST match
            // `FO_SPIKE_BASELINE_PIVOT` in `FerrofluidOcean.metal`.
            let proportionForFFO: Float
            if mirPipeline.ffoColdStartFixEnabled {
                let stems = cached.stemFeatures
                let totalStemEnergy = stems.vocalsEnergy + stems.drumsEnergy
                    + stems.bassEnergy + stems.otherEnergy
                proportionForFFO = totalStemEnergy > 0
                    ? stems.bassEnergy / totalStemEnergy
                    : 0.15
            } else {
                proportionForFFO = 0.15  // pivot — collapses baseline to 0
            }
            pipeline.setCachedBassProportion(proportionForFFO)
            // IFC.4 (D-177) — install the cached preview instrument-family
            // activity series (Layer 5a). Sampled by playback position each
            // analysis frame (see processAnalysisFrame).
            currentFamilySeries = cached.instrumentFamilySeries
            // DYN.1c: this track's own loudness distribution as the surge source. Non-nil
            // only for a local file (the only path that decodes the whole thing); nil
            // everywhere else keeps the fixed band. Deliberately survives the
            // `mirPipeline.reset()` that `handleLocalFileReady` runs after this call.
            mirPipeline.setLoudnessProfile(cached.loudnessProfile)
            // BUG-007.8: pass per-track grid-vs-onset offset as initial drift bias.
            mirPipeline.setBeatGrid(
                cached.beatGrid.offsetBy(0),
                initialDriftMs: cached.gridOnsetOffsetMs
            )
            logCachedInstall(cached: cached, title: identity.title, replacedExisting: replacedExisting)
        } else {
            pipeline.setStemFeatures(.zero, live: false)   // BUG-064: not-live until convergence
            // CSP.3.1 — no cached preview available (live reactive mode /
            // ad-hoc playback / cache miss). Install the formula pivot
            // (0.15) so the FFO baseline contribution is 0; the Layer-2
            // cold-start crossfade still operates with f.bass during
            // early playback. Sentinel value MUST match
            // `FO_SPIKE_BASELINE_PIVOT` in `FerrofluidOcean.metal`.
            pipeline.setCachedBassProportion(0.15)
            mirPipeline.setLoudnessProfile(nil)   // DYN.1c: no cache entry → fixed surge band
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

    /// BEAT_GRID_INSTALL + LOUDNESS_PROFILE breadcrumbs for a prepared-cache install.
    /// Extracted from `resetStemPipeline(...)` to keep it under SwiftLint's
    /// function_body_length cap — same reason as `refreshLumenPaletteForTrack` below.
    private func logCachedInstall(cached: CachedTrackData, title: String, replacedExisting: Bool) {
        let grid = cached.beatGrid
        // DYN.1d: say "none" out loud. A local track running unprofiled is the DYN.1c
        // defect in disguise, and an absent suffix looked identical to a line that simply
        // predated the field — which is why Cherub Rock ran pinned for a whole session
        // before anyone noticed.
        let loudness = ", loudness=" + (cached.loudnessProfile?.summary ?? "none (fixed band)")
        guard !grid.beats.isEmpty else {
            let empty = "BEAT_GRID_INSTALL: source=preparedCache, track='\(title)' — "
                + "empty grid, live inference will be allowed\(loudness)"
            logger.info("\(empty, privacy: .public)")
            return
        }
        let detail = "bpm=" + String(format: "%.1f", grid.bpm)
            + ", beats=\(grid.beats.count), meter=\(grid.beatsPerBar)/X"
        let firstBeat = grid.beats.first.map { String(format: "%.3f", $0) } ?? "none"
        let replaceNote = replacedExisting ? " (replaced existing grid)" : ""
        let installed = "source=preparedCache, track='\(title)', \(detail)"
        let full = "\(installed), firstBeat=\(firstBeat)s\(replaceNote)\(loudness)"
        logger.info("BEAT_GRID_INSTALL: \(full, privacy: .public)")
        sessionRecorder?.log("BeatGrid installed: \(installed)\(loudness)")
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
    ///
    /// `internal` (not `private`) so `applyPreset` in
    /// `VisualizerEngine+Presets.swift` can call it at preset-activation
    /// time — required by the BUG-016 fix so the palette is loaded when
    /// the user switches to Lumen Mosaic mid-track.
    func refreshLumenPaletteForTrack(
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
    ///
    /// Shared (not `private`) so `VisualizerEngine+Presets` can derive the
    /// SkeinState per-track painter seed from the same hash (Skein.3 §5.7
    /// determinism — same track → same painting).
    static func lumenTrackSeedHash(for identity: TrackIdentity) -> UInt64 {
        let key = (identity.title.lowercased() + "|" + identity.artist.lowercased())
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

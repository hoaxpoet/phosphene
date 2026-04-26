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

    /// RMS threshold below which the stem pipeline skips CoreML inference.
    /// Interleaved stereo silence from Core Audio taps reads as true zero;
    /// 1e-6 catches near-zero noise floors without false-positive skips.
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

        // Snapshot ~10s of interleaved stereo audio.
        let samples = stemSampleBuffer.snapshotLatest(seconds: 10)
        let requiredStereo = StemSeparator.requiredMonoSamples * 2
        guard samples.count >= requiredStereo else {
            logger.debug("Stem pipeline: warmup (\(samples.count)/\(requiredStereo) samples)")
            return
        }

        // Idle suppression: skip CoreML inference when the buffer is silence.
        let rms = stemSampleBuffer.rms(seconds: 10)
        guard rms > Self.silenceRMSThreshold else {
            logger.debug("Stem pipeline: skipping — silence (RMS=\(rms))")
            return
        }

        do {
            let result = try separator.separate(
                audio: samples, channelCount: 2, sampleRate: 44100
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
            // runPerFrameStemAnalysis (VisualizerEngine+Audio) slides a
            // 1024-sample window through these waveforms at real-time rate
            // so StemFeatures values in GPU buffer(3) update continuously
            // (at ~audio-callback rate, ~94 Hz) instead of once per 5s.
            // Eliminates the piecewise-constant-for-5s behaviour that
            // produced visible terrain freeze-and-jump artefacts in
            // session 2026-04-16T20-56-46Z.
            let sepTime = CFAbsoluteTimeGetCurrent()
            stemsStateLock.withLock {
                self.latestSeparatedStems = stemWaveforms
                self.latestSeparationTimestamp = sepTime
            }

            logger.debug("Stem separation complete: \(sampleCount) samples per stem")

            // Diagnostic capture: dump the four separated stem waveforms as WAV
            // files so we can listen to separation quality against real audio.
            sessionRecorder?.recordStemSeparation(
                stemWaveforms: stemWaveforms,
                sampleRate: 44100,
                trackTitle: currentTrack?.title
            )
        } catch {
            logger.error("Stem separation failed: \(error)")
        }
    }

    /// Reset the stem pipeline on track change, loading pre-analyzed data from cache
    /// when available.
    ///
    /// Per the session preparation architecture:
    /// - `StemSampleBuffer` is NOT cleared — real-time audio keeps accumulating so
    ///   live separation can begin immediately.
    /// - If `stemCache` has data for the given identity, `StemFeatures` is seeded
    ///   from the pre-separated preview; otherwise it resets to `.zero`.
    ///
    /// - Parameter identity: The newly playing track. Pass nil when the identity is
    ///   unknown (falls back to `.zero` stems).
    func resetStemPipeline(for identity: TrackIdentity? = nil) {
        stemAnalyzer.reset()

        // Clear the per-frame analyzer's source waveforms so stems don't
        // leak across tracks. Next separation will repopulate them.
        stemsStateLock.withLock {
            self.latestSeparatedStems = []
            self.latestSeparationTimestamp = 0
        }

        // A deferred dispatch from the previous track is irrelevant on the new track.
        pendingDispatchStartTime = nil

        pipeline.spectralHistory.reset()

        if let identity, let cached = stemCache?.loadForPlayback(track: identity) {
            pipeline.setStemFeatures(cached.stemFeatures)
            logger.info("Stem pipeline loaded from cache: \(identity.title) by \(identity.artist)")
        } else {
            pipeline.setStemFeatures(.zero)
            logger.info("Stem pipeline reset (track change, no cache entry)")
        }
        // StemSampleBuffer intentionally not reset — continues accumulating for live separation.
    }
}

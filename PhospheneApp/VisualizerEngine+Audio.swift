// VisualizerEngine+Audio — Audio routing, MIR analysis, mood classification,
// and metadata pre-fetching setup.
// swiftlint:disable file_length

import Audio
import DSP
import Foundation
import ML
import os.log
import Session
import Shared

private let logger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

// MARK: - Audio Routing Setup

extension VisualizerEngine {

    /// Set up audio routing, MIR analysis, mood classification, and pre-fetching.
    @available(macOS 14.2, *)
    func setupAudioRouting(
        audioBuffer buf: AudioBuffer,
        fftProcessor fft: FFTProcessor
    ) -> AudioInputRouter {
        let metadata = StreamingMetadata()
        let audioRouter = AudioInputRouter(metadata: metadata)
        // CLEAN.3.5: close any prior handle before reopening so a re-setup can't leak
        // an FD (the file is truncated + reopened each call). Also closed in deinit.
        diagLog?.closeFile()
        diagLog = Self.openDiagnosticLog()
        lastAnalysisTime = CFAbsoluteTimeGetCurrent()

        audioRouter.onAudioSamples = makeAudioSampleCallback(buf: buf, fft: fft)
        audioRouter.onSignalStateChanged = makeSignalStateCallback()

        // BUG-057: persist tap-install lifecycle + first-seconds RMS + the
        // `.silent → reinstall` scheduler timeline to session.log so the
        // cold-install-vs-reinstall divergence is diagnosable from one session
        // artifact (os_log rolls off). Instrumentation only — no behaviour change.
        let recorder = sessionRecorder
        audioRouter.onAudioCaptureDiagnostic = { [weak recorder] msg in
            recorder?.log("TAP: \(msg)")
        }

        // ASH.1: fresh session → clear stale silence timing / prior health, and
        // log + publish each health state CHANGE (not per-window). The overlay
        // reads `signalHealth`; the log line mirrors the RUNBOOK triage catalog.
        signalHealthMonitor.reset()
        signalHealthMonitor.onHealthChanged = { [weak self, weak recorder] health in
            recorder?.log(
                "SIGNAL_HEALTH: peak=\(String(format: "%.1f", health.peakDBFS))dBFS "
                + "band=\(health.peakBand.rawValue) deadTap=\(health.deadTap) "
                + "rate=\(Int(health.outputSampleRateHz))")
            Task { @MainActor [weak self] in self?.signalHealth = health }
        }

        // Round 26 (2026-05-15): `preFetcher` is now constructed early in
        // `VisualizerEngine.init` so SessionPreparer can share the same
        // cache + fetcher list. Reuse it here for the track-change
        // callback rather than constructing a duplicate.
        let fetcher = preFetcher ?? MetadataPreFetcher(fetchers: Self.buildFetcherList())
        preFetcher = fetcher
        audioRouter.onTrackChange = makeTrackChangeCallback(fetcher: fetcher)

        return audioRouter
    }

    // MARK: - Routing Helpers

    /// Open the analysis diagnostic log file in the user's home directory.
    static func openDiagnosticLog() -> FileHandle? {
        let path = NSHomeDirectory() + "/phosphene_diag.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }

    /// Build the metadata fetcher list — MusicBrainz + iTunes Search are always
    /// active (free); Soundcharts enables when its env var is set.
    static func buildFetcherList() -> [any MetadataFetching] {
        var fetchers: [any MetadataFetching] = [
            ITunesSearchFetcher(),
            MusicBrainzFetcher()
        ]
        if let soundcharts = SoundchartsFetcher.fromEnvironment() {
            fetchers.append(soundcharts)
            logger.info("Soundcharts fetcher enabled (audio features)")
        }
        return fetchers
    }

    /// Build the real-time onAudioSamples callback. Runs on the audio thread —
    /// writes the buffer + FFT, dispatches heavy MIR work to the analysis queue,
    /// and feeds StemSampleBuffer for background stem separation.
    func makeAudioSampleCallback(
        buf: AudioBuffer,
        fft: FFTProcessor
    ) -> (UnsafePointer<Float>, Int, Float, UInt32) -> Void {
        // BUG-036: pre-allocated interleaved scratch, reused across callbacks so
        // the FFT input is filled allocation-free. Captured by (and only ever
        // touched on) the single real-time audio thread — no cross-thread share,
        // so no lock is needed (unlike tapSampleRate, D-079).
        var interleavedScratch = [Float](repeating: 0, count: FFTProcessor.fftSize * 2)
        return { [weak self, weak buf, weak fft] samples, count, rate, channels in
            guard let buf, let fft else { return }
            buf.write(from: samples, count: count)

            // Stage-4 diagnostic: dump the raw tap samples (first 30s) to
            // raw_tap.wav in the session directory.  Ground truth for
            // spectrum-vs-stem comparisons — whatever band-limiting or
            // attenuation shows up here is upstream of Phosphene.
            self?.sessionRecorder?.recordRawTapSamples(
                pointer: samples,
                count: count,
                sampleRate: rate,
                channelCount: channels
            )

            // Signal-quality monitor: peak + RMS directly on the tap samples,
            // before any processing.  Cheap enough for the real-time thread
            // (two vDSP reductions).  Spectral balance is filled in on the
            // analysis queue from the FFT magnitudes already computed below.
            self?.inputLevelMonitor.submitSamples(pointer: samples, count: count)

            // ASH.1: input-chain health (peak band / dead tap / rate mismatch).
            // Realtime-safe; classification + publish happen off this thread.
            self?.signalHealthMonitor.ingest(samples: samples, count: count)

            // Capture the actual tap sample rate so Beat This! and the
            // snapshot helper use the correct frame count. The setter is
            // NSLock-guarded for cross-core visibility (D-079, QR.1) — the
            // value is stable for the lifetime of a tap install, but the
            // audio thread and the stem/analysis queues run on different
            // cores, and an unsynchronized 8-byte write is not guaranteed
            // visible without a barrier.
            self?.updateTapSampleRate(Double(rate))

            // Feed stem sample buffer (interleaved stereo, lightweight write).
            self?.stemSampleBuffer.write(samples: samples, count: count)

            // BUG-036: fill the reused scratch + run the zero-alloc stereo FFT
            // path instead of allocating a fresh [Float] per callback.
            let frameSampleCount = interleavedScratch.withUnsafeMutableBufferPointer {
                buf.latestSamples(into: $0)
            }
            guard frameSampleCount > 0 else { return }

            let fftResult = interleavedScratch.withUnsafeBufferPointer {
                fft.processStereo(
                    interleaved: UnsafeBufferPointer(rebasing: $0[0..<frameSampleCount]),
                    sampleRate: rate
                )
            }

            // Copy magnitudes off the real-time thread for analysis.
            // BUG-036 NOTE: this snapshot copy + the `analysisQueue.async` closure
            // below (and the raw-tap `Data()`/`queue.async` in recordRawTapSamples)
            // are the remaining IO-proc allocations. Removing them safely needs a
            // pre-allocated ring drained by a persistent consumer — a hand-off
            // redesign coupled to BUG-043's analysis cadence, deferred to that work.
            let binCount = Int(fftResult.binCount)
            let magnitudes = Array(fft.magnitudeBuffer.pointer.prefix(binCount))

            // Capture the tap sample rate so the spectral-balance pass
            // in the monitor knows the band-to-bin mapping.
            let sr = rate

            self?.analysisQueue.async { [weak self] in
                self?.inputLevelMonitor.submitMagnitudes(magnitudes, sampleRate: sr)
                self?.processAnalysisFrame(magnitudes: magnitudes)
            }
        }
    }

    // MARK: - Analysis Pipeline

    /// Run MIR analysis + mood classification on a single FFT magnitude frame.
    /// Called on the serial analysis queue.
    func processAnalysisFrame(magnitudes: [Float]) {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = max(Float(now - lastAnalysisTime), 0.001)
        lastAnalysisTime = now
        let effectiveFps = 1.0 / dt

        // PERF.1 — BUG-019 instrumentation. Wrap the per-subsystem hot paths
        // with DispatchTime.now() snapshots so the cost-by-component can be
        // attributed from features.csv. No allocations on the hot path; cost
        // of the measurement itself is sub-microsecond.
        let mir = mirPipeline
        // BUG-053: the live MIR is constructed at app init, before the tap
        // installs and its rate is known, so it starts at the 48 kHz default.
        // Adopt the actual tap rate here — on the analysis queue, off the RT
        // thread — so every bin→Hz stage (chroma/key, bands, centroid) reads
        // the real rate. No-op once matched; recomputes the bin→Hz tables on a
        // device-swap rate change (couples to G1/CLEAN.1.5).
        mir.setSampleRate(Float(tapSampleRate))
        // BUG-053 observability: persist the analysis rate to session.log the
        // first frame it's established and on any change (device swap), so the
        // session artifact self-documents the rate the live MIR actually ran at
        // — the verification signal for this fix (key estimation is unreliable;
        // the `os_log` MIR_RATE line isn't kept in the artifact). `log()`
        // dispatches to its own queue, so it's safe from the analysis queue.
        if mir.sampleRate != lastLoggedAnalysisRate {
            lastLoggedAnalysisRate = mir.sampleRate
            sessionRecorder?.log("MIR analysis rate → \(Int(mir.sampleRate)) Hz (tap \(Int(tapSampleRate)) Hz)")
        }
        let mirT0 = DispatchTime.now().uptimeNanoseconds
        let fv = mir.process(
            magnitudes: magnitudes,
            fps: effectiveFps,
            time: 0,
            deltaTime: dt
        )
        let mirPipelineMs = Float(DispatchTime.now().uptimeNanoseconds - mirT0) / 1_000_000.0

        // Feed live MIR features to the render pipeline.
        pipeline.setFeatures(fv)
        pipeline.updateFeedbackBeatValue(from: fv)

        // Skein.ENGINE.3 (D-151): publish the live structural-section prediction to the render
        // pipeline's gated CPU-only bridge, alongside the per-frame MIR features publish. `mir.process`
        // (above) just refreshed `mir.latestStructuralPrediction`; route it through `RenderPipeline`
        // (never read `mirPipeline` on the render thread directly — cross-thread race) so the Skein
        // tick closure can consume it. Inert for every other preset (the store defaults to `.none`
        // and only `SkeinState` reads it) ⇒ byte-identical. Co-located with `setFeatures`, not
        // `setMood`: structure is a per-frame MIR output (not an accumulated mood-classifier result),
        // and this site is UNCONDITIONAL — the `setMood` path early-returns when the mood classifier
        // is absent or `classify` throws, which would intermittently stall the section signal.
        pipeline.setStructuralPrediction(mir.latestStructuralPrediction)
        // IFC.4 (D-177): sample the cached preview instrument-family activity
        // series (Layer 5a) by live playback position and write it into the
        // live StemFeatures (floats 48–55). Empty series → `.zero` (cleared on
        // track change), so this is inert for every non-orchestral track.
        let family = InstrumentFamilyActivity.sample(
            currentFamilySeries,
            atPlaybackSeconds: mir.elapsedSeconds,
            hopSeconds: InstrumentFamilyAnalyzer.hopSeconds)
        pipeline.setInstrumentFamilyActivity(smoothed: family.smoothedSIMD4, dev: family.devSIMD4)
        // Skein.5.2: mirror the same prediction into the session recorder so features.csv carries
        // `section_index` / `section_start_s` / `section_confidence` — the artifact that makes the
        // Skein.5 structural bias (and BUG-035-class corruption) verifiable from a session.
        sessionRecorder?.recordStructuralPrediction(mir.latestStructuralPrediction)

        // Update SpectralCartograph beat-grid overlay (diagnostic preset).
        updateSpectralCartographBeatGrid(mir: mir, fv: fv)

        analysisFrameCount += 1

        accumulateMoodFeatures(fv: fv, mir: mir)

        // Per-frame stem analysis. Slides a 1024-sample window through the
        // most recent separated stem waveforms at real-time rate so
        // StemFeatures update continuously. Before this, stems updated
        // once per 5s separation cycle (piecewise-constant values hit the
        // GPU for 5s at a time — see session 2026-04-16T20-56-46Z where
        // only 25 unique drumsBeat values appeared across 8,987 frames).
        let stemT0 = DispatchTime.now().uptimeNanoseconds
        runPerFrameStemAnalysis(fps: effectiveFps)
        let stemAnalyzerMs = Float(DispatchTime.now().uptimeNanoseconds - stemT0) / 1_000_000.0
        // Inner timings surfaced by StemAnalyzer (drums beat detector +
        // vocals YIN pitch). Reads are safe — same serial analysis queue.
        let beatDetectorMs = stemAnalyzer.lastBeatDetectorMs
        let pitchTrackerMs = stemAnalyzer.lastPitchTrackerMs

        // Live Beat This! trigger — fires once per track after 10s of buffered
        // audio, installing a BeatGrid for ad-hoc/reactive sessions. Spotify-
        // prepared tracks are skipped because they already have a grid from
        // the offline pre-analysis path.
        runLiveBeatAnalysisIfNeeded()

        var moodClassifierMs: Float = 0
        if let mood = moodClassifier {
            let moodT0 = DispatchTime.now().uptimeNanoseconds
            runMoodClassifier(mood: mood, fv: fv, mir: mir, magnitudes: magnitudes)
            moodClassifierMs = Float(DispatchTime.now().uptimeNanoseconds - moodT0) / 1_000_000.0
        }

        // BUG-015: tick the orchestrator live-adaptation pipeline at ~3 Hz
        // (every 30th analysis frame). Runs regardless of whether the mood
        // classifier fired this frame — boundary rescheduling and the
        // reactive-mode path do not strictly require a fresh mood value
        // (the cached `lastClassifiedMood` defaults to `.neutral` until
        // the first classification lands ~3 s into a session).
        runOrchestratorLiveUpdate(mir: mir)

        // Push the breakdown to the session recorder. The next features.csv
        // row to be written (on the render-loop completion handler, ~60 Hz)
        // reads these and emits the per-subsystem columns. Lag is bounded
        // by the analysis-vs-render frame rate gap (analysis ~94 Hz,
        // render ~60 Hz), same pattern as frame_cpu_ms.
        sessionRecorder?.recordSubsystemTimings(
            mirPipelineMs: mirPipelineMs,
            stemAnalyzerMs: stemAnalyzerMs,
            beatDetectorMs: beatDetectorMs,
            pitchTrackerMs: pitchTrackerMs,
            moodClassifierMs: moodClassifierMs
        )
    }

    /// Slide a 1024-sample window through the most recent separated stem
    /// waveforms and run `StemAnalyzer` on it. Produces continuously-varying
    /// `StemFeatures` between 5-second separation cycles.
    ///
    /// Strategy: each separation produces a 10-second chunk of audio that's
    /// already been heard by the user. Starting at the chunk's 5-second mark,
    /// we scan forward at real-time rate over the ~5 seconds until the next
    /// separation completes. This ties the sliding window to wall-clock time
    /// (not audio energy) so the window advances smoothly regardless of audio
    /// dynamics. Features carry ~5-10s of latency (we're always analyzing
    /// audio that's already been heard), which is acceptable because musical
    /// sections persist longer than that.
    func runPerFrameStemAnalysis(fps: Float) {
        var stems: [[Float]] = []
        var sepTime: CFAbsoluteTime = 0
        stemsStateLock.withLock {
            stems = self.latestSeparatedStems
            sepTime = self.latestSeparationTimestamp
        }

        // No separation yet → stems stay at zero (warmup behaviour unchanged).
        guard stems.count == 4, stems[0].count >= 1024 else { return }

        let chunkSampleCount = stems[0].count
        // Stem waveforms are at the model rate, not the tap rate — the
        // separator resamples internally before iSTFT. Use the canonical
        // constant rather than a literal. (D-079, QR.1)
        let sampleRate: Float = StemSeparator.modelSampleRate
        let windowSize = 1024

        // Start scanning from the 5-second mark into the 10-second chunk.
        // The last 5 seconds of the chunk represents audio heard 0-5 seconds
        // ago at the moment of separation; as wall-clock time advances past
        // the separation, we slide toward the chunk's end.
        let startSample = Int(5.0 * sampleRate)
        let elapsed = max(0.0, CFAbsoluteTimeGetCurrent() - sepTime)
        let advanceSamples = Int(Float(elapsed) * sampleRate)
        let maxOffset = max(0, chunkSampleCount - windowSize)
        let rawOffset = startSample + advanceSamples
        let offset = min(rawOffset, maxOffset)

        // Slice the per-stem 1024-sample window.
        var window: [[Float]] = []
        window.reserveCapacity(4)
        for stem in stems {
            let end = min(offset + windowSize, stem.count)
            if offset < end {
                window.append(Array(stem[offset..<end]))
            } else {
                window.append([Float](repeating: 0, count: windowSize))
            }
        }

        let features = stemAnalyzer.analyze(stemWaveforms: window, fps: fps)
        pipeline.setStemFeatures(features)
        latestBassAttackRatio = features.bassAttackRatio
    }

    /// EMA-accumulate the 10 features that the mood classifier consumes.
    func accumulateMoodFeatures(fv: FeatureVector, mir: MIRPipeline) {
        // BUG-053: normalize by the live Nyquist (tap rate / 2), not a hardcoded
        // 24 kHz. With the rate-aware SpectralAnalyzer, `rawSmoothedCentroid` is
        // now true Hz; a fixed 24 kHz divisor would mis-scale the mood centroid
        // feature on any tap ≠ 48 kHz (previously the over-count and the fixed
        // divisor cancelled — fixing one without the other reintroduces error).
        let nyquist = mir.sampleRate / 2.0
        let centroidNorm = mir.rawSmoothedCentroid / nyquist
        let frameFeatures: [Float] = [
            fv.subBass, fv.lowBass, fv.lowMid,
            fv.midHigh, fv.highMid, fv.high,
            centroidNorm, mir.rawSmoothedFlux,
            mir.latestMajorKeyCorrelation,
            mir.latestMinorKeyCorrelation
        ]

        if !featureAccumInitialized {
            accumulatedFeatures = frameFeatures
            featureAccumInitialized = true
            return
        }

        let alpha = Self.featureEmaAlpha
        for idx in 0..<10 {
            accumulatedFeatures[idx] = alpha * frameFeatures[idx]
                + (1 - alpha) * accumulatedFeatures[idx]
        }
    }

    // MARK: - Mood Classification

    /// Run the mood classifier on accumulated features and publish results to MainActor.
    func runMoodClassifier(
        mood: MoodClassifier,
        fv: FeatureVector,
        mir: MIRPipeline,
        magnitudes: [Float]
    ) {
        let features = accumulatedFeatures

        // Write capture row (~every 10th frame to avoid huge files).
        if analysisFrameCount % 10 == 0 {
            writeCaptureRow(
                features: features,
                fv: fv,
                magMax: magnitudes.max() ?? 0,
                key: mir.estimatedKey
            )
        }

        guard let state = try? mood.classify(features: features) else { return }

        if analysisFrameCount % 60 == 0 {
            writeDiagnosticLine(state: state, mir: mir)
        }

        let diag = makeDiagnostics(fv: fv, mir: mir, magnitudes: magnitudes)
        let stability = mir.featureStability
        publishMoodResult(state: state, diag: diag, stability: stability, mir: mir)
    }

    /// MIR diagnostics snapshot for the debug overlay.
    func makeDiagnostics(
        fv: FeatureVector,
        mir: MIRPipeline,
        magnitudes: [Float]
    ) -> MIRDiagnostics {
        let totalEnergy = fv.subBass + fv.lowBass + fv.lowMid
            + fv.midHigh + fv.highMid + fv.high
        return MIRDiagnostics(
            magMax: magnitudes.max() ?? 0,
            bass: fv.bass,
            mid: fv.mid,
            centroid: fv.spectralCentroid,
            flux: fv.spectralFlux,
            majorCorr: mir.latestMajorKeyCorrelation,
            minorCorr: mir.latestMinorKeyCorrelation,
            callbackCount: analysisFrameCount,
            onsetsPerSec: mir.onsetsPerSecond,
            totalEnergy: totalEnergy,
            subBass: fv.subBass,
            bassAttackRatio: latestBassAttackRatio
        )
    }

    /// Updates the SpectralCartograph beat-grid overlay data in the spectral history buffer.
    /// Called from the analysis queue after each MIR frame. No-op when the drift tracker
    /// has no grid installed (reactive mode) — ticks are suppressed by the `Float.infinity`
    /// sentinel already written by `reset()`.
    func updateSpectralCartographBeatGrid(mir: MIRPipeline, fv: FeatureVector) {
        let tracker = mir.liveDriftTracker
        let bpm = Float(tracker.currentBPM)
        let lockStateInt: Int
        switch tracker.currentLockState {
        case .unlocked: lockStateInt = 0
        case .locking:  lockStateInt = 1
        case .locked:   lockStateInt = 2
        }

        // Session mode distinguishes "reactive session (no grid)" from "planned
        // session awaiting drift-tracker lock" so Spectral Cartograph can show
        // informative labels rather than collapsing both into "REACTIVE". DSP.3.1.
        let sessionMode: Int
        if tracker.hasGrid {
            switch tracker.currentLockState {
            case .unlocked: sessionMode = 1
            case .locking:  sessionMode = 2
            case .locked:   sessionMode = 3
            }
        } else {
            sessionMode = 0
        }

        let pt = mir.elapsedSeconds   // Double since QR.1 / D-079
        let relTimes = tracker.relativeBeatTimes(
            playbackTime: pt,
            count: SpectralHistoryBuffer.beatTimesCount
        )
        let relDownbeats = tracker.relativeDownbeatTimes(
            playbackTime: pt,
            count: SpectralHistoryBuffer.downbeatTimesCount
        )
        let driftMs = Float(tracker.currentDriftMs)
        pipeline.spectralHistory.updateBeatGridData(
            relativeBeatTimes: relTimes,
            relativeDownbeatTimes: relDownbeats,
            bpm: bpm,
            lockState: lockStateInt,
            sessionMode: sessionMode,
            driftMs: driftMs
        )

        // Build per-frame BeatSyncSnapshot for SessionRecorder CSV.
        let bpb = max(1, Int(fv.beatsPerBar.rounded()))
        let rawBeatIndex = Int(fv.barPhase01 * Float(bpb)) + 1
        let beatInBar = max(1, min(rawBeatIndex, bpb))
        let snapshot = BeatSyncSnapshot(
            barPhase01: fv.barPhase01,
            beatsPerBar: bpb,
            beatInBar: beatInBar,
            isDownbeat: beatInBar == 1,
            sessionMode: sessionMode,
            lockState: lockStateInt,
            gridBPM: bpm,
            // BeatSyncSnapshot.playbackTimeS is Float for compact CSV output;
            // resolution loss at 30 min ≈ 240 µs is irrelevant for diagnostic
            // viewing. The Double accumulator prevents long-session drift.
            playbackTimeS: Float(mir.elapsedSeconds),
            driftMs: driftMs
        )
        beatSyncLock.withLock { latestBeatSyncSnapshot = snapshot }
    }

    /// Once-per-second textual diagnostic line written to ~/phosphene_diag.log.
    func writeDiagnosticLine(state: EmotionalState, mir: MIRPipeline) {
        let line = String(
            format: "bassTs=%d iBPM=%.0f sBPM=%.0f td=%@"
            + " key=%@ mood=(%.2f,%.2f) quad=%@\n",
            mir.bassOnsetCount,
            mir.instantBPM ?? 0,
            mir.stableBPM ?? 0,
            mir.tempoDebug,
            mir.stableKey ?? mir.estimatedKey ?? "nil",
            state.valence,
            state.arousal,
            state.quadrant.rawValue
        )
        diagLog?.write(Data(line.utf8))
    }

    /// Publish mood + diagnostic state to the main actor for SwiftUI consumption.
    func publishMoodResult(
        state: EmotionalState,
        diag: MIRDiagnostics,
        stability: Float,
        mir: MIRPipeline
    ) {
        // Inject mood into the renderer's FeatureVector so audio-reactive
        // shaders (e.g. Glass Brutalist's light-colour shift on valence,
        // fog density on arousal) actually receive these values. Without
        // this, the renderer reads valence=0/arousal=0 every frame and
        // mood-driven modulations are dead.
        var attenuated = state
        attenuated.valence *= stability
        attenuated.arousal *= stability
        pipeline.setMood(valence: attenuated.valence, arousal: attenuated.arousal)

        // BUG-015: cache the post-stability-attenuated mood for the
        // analysis-queue orchestrator wire. Same lock that guards `livePlan`
        // and `liveTrackPlanIndex` so a single acquisition snapshots the
        // full call-input set for `applyLiveUpdate(...)`.
        orchestratorLock.withLock { lastClassifiedMood = attenuated }

        // Publish signal-quality changes to session.log on transitions (not
        // every frame).  Read the snapshot here on the analysis queue so the
        // logging side-effect happens off the main actor.
        let snap = inputLevelMonitor.currentSnapshot()

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentMood = attenuated
            // Prefer pre-fetched metadata over self-computed.
            if self.preFetchedProfile?.key == nil {
                self.estimatedKey = mir.stableKey ?? mir.estimatedKey
            }
            if self.preFetchedProfile?.bpm == nil {
                self.estimatedTempo = mir.stableBPM ?? mir.estimatedTempo
            }
            self.mirDiag = diag

            // Log quality transitions once per change (green ↔ yellow ↔ red),
            // plus the first non-warmup classification.
            if snap.quality != self.lastLoggedQuality && snap.quality != .unknown {
                self.sessionRecorder?.log(
                    "signal quality → \(snap.quality.rawValue): \(snap.reason)")
                self.lastLoggedQuality = snap.quality
            }
        }
    }
}

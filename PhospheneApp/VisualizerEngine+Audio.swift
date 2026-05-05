// VisualizerEngine+Audio — Audio routing, MIR analysis, mood classification,
// and metadata pre-fetching setup.

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
        diagLog = Self.openDiagnosticLog()
        lastAnalysisTime = CFAbsoluteTimeGetCurrent()

        audioRouter.onAudioSamples = makeAudioSampleCallback(buf: buf, fft: fft)
        audioRouter.onSignalStateChanged = makeSignalStateCallback()

        let fetcher = MetadataPreFetcher(fetchers: Self.buildFetcherList())
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
    /// active (free), Soundcharts and Spotify enable when env vars are set.
    static func buildFetcherList() -> [any MetadataFetching] {
        var fetchers: [any MetadataFetching] = [
            ITunesSearchFetcher(),
            MusicBrainzFetcher()
        ]
        if let soundcharts = SoundchartsFetcher.fromEnvironment() {
            fetchers.append(soundcharts)
            logger.info("Soundcharts fetcher enabled (audio features)")
        }
        if let spotify = SpotifyFetcher.fromEnvironment() {
            fetchers.append(spotify)
            logger.info("Spotify fetcher enabled (search only)")
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

            // Feed stem sample buffer (interleaved stereo, lightweight write).
            self?.stemSampleBuffer.write(samples: samples, count: count)

            let latest = buf.latestSamples(count: FFTProcessor.fftSize * 2)
            guard !latest.isEmpty else { return }

            let fftResult = fft.processStereo(interleavedSamples: latest, sampleRate: rate)

            // Copy magnitudes off the real-time thread for analysis.
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

        let mir = mirPipeline
        let fv = mir.process(
            magnitudes: magnitudes,
            fps: effectiveFps,
            time: 0,
            deltaTime: dt
        )

        // Feed live MIR features to the render pipeline.
        pipeline.setFeatures(fv)
        pipeline.updateFeedbackBeatValue(from: fv)

        // Update SpectralCartograph beat-grid overlay (diagnostic preset).
        updateSpectralCartographBeatGrid(mir: mir)

        analysisFrameCount += 1

        accumulateMoodFeatures(fv: fv, mir: mir)

        // Per-frame stem analysis. Slides a 1024-sample window through the
        // most recent separated stem waveforms at real-time rate so
        // StemFeatures update continuously. Before this, stems updated
        // once per 5s separation cycle (piecewise-constant values hit the
        // GPU for 5s at a time — see session 2026-04-16T20-56-46Z where
        // only 25 unique drumsBeat values appeared across 8,987 frames).
        runPerFrameStemAnalysis(fps: effectiveFps)

        // Live Beat This! trigger — fires once per track after 10s of buffered
        // audio, installing a BeatGrid for ad-hoc/reactive sessions. Spotify-
        // prepared tracks are skipped because they already have a grid from
        // the offline pre-analysis path.
        runLiveBeatAnalysisIfNeeded()

        guard let mood = moodClassifier else { return }
        runMoodClassifier(mood: mood, fv: fv, mir: mir, magnitudes: magnitudes)
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
        let sampleRate: Float = 44100
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
        let nyquist: Float = 24000.0
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
    func updateSpectralCartographBeatGrid(mir: MIRPipeline) {
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

        let relTimes = tracker.relativeBeatTimes(
            playbackTime: Double(mir.elapsedSeconds),
            count: SpectralHistoryBuffer.beatTimesCount
        )
        pipeline.spectralHistory.updateBeatGridData(
            relativeBeatTimes: relTimes,
            bpm: bpm,
            lockState: lockStateInt,
            sessionMode: sessionMode
        )
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

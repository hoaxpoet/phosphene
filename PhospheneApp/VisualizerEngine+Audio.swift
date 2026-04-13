// VisualizerEngine+Audio — Audio routing, MIR analysis, mood classification,
// and metadata pre-fetching setup.

import Audio
import DSP
import Foundation
import ML
import os.log
import Shared

private let logger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

// MARK: - Audio Routing Setup

extension VisualizerEngine {

    /// Set up audio routing, MIR analysis, mood classification, and metadata pre-fetching.
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

    /// Build the real-time onAudioSamples callback. Runs on the audio thread:
    /// must do only the buffer write + FFT, then dispatch heavy MIR work
    /// onto the analysis queue. Also feeds StemSampleBuffer for background
    /// stem separation.
    func makeAudioSampleCallback(
        buf: AudioBuffer,
        fft: FFTProcessor
    ) -> (UnsafePointer<Float>, Int, Float, UInt32) -> Void {
        return { [weak self, weak buf, weak fft] samples, count, rate, _ in
            guard let buf, let fft else { return }
            buf.write(from: samples, count: count)

            // Feed stem sample buffer (interleaved stereo, lightweight write).
            self?.stemSampleBuffer.write(samples: samples, count: count)

            let latest = buf.latestSamples(count: FFTProcessor.fftSize * 2)
            guard !latest.isEmpty else { return }

            let fftResult = fft.processStereo(interleavedSamples: latest, sampleRate: rate)

            // Copy magnitudes off the real-time thread for analysis.
            let binCount = Int(fftResult.binCount)
            let magnitudes = Array(fft.magnitudeBuffer.pointer.prefix(binCount))

            self?.analysisQueue.async { [weak self] in
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
        // RenderPipeline.draw(in:) overlays timing fields each frame.
        pipeline.setFeatures(fv)
        pipeline.updateFeedbackBeatValue(from: fv)

        analysisFrameCount += 1

        accumulateMoodFeatures(fv: fv, mir: mir)

        guard let mood = moodClassifier else { return }
        runMoodClassifier(mood: mood, fv: fv, mir: mir, magnitudes: magnitudes)
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

    /// Build a snapshot of MIR diagnostics for the debug overlay.
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
            totalEnergy: totalEnergy
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
        Task { @MainActor [weak self] in
            // Attenuate mood toward neutral during ramp-up.
            var attenuated = state
            attenuated.valence *= stability
            attenuated.arousal *= stability
            self?.currentMood = attenuated
            // Prefer pre-fetched metadata over self-computed.
            if self?.preFetchedProfile?.key == nil {
                self?.estimatedKey = mir.stableKey ?? mir.estimatedKey
            }
            if self?.preFetchedProfile?.bpm == nil {
                self?.estimatedTempo = mir.stableBPM ?? mir.estimatedTempo
            }
            self?.mirDiag = diag
        }
    }

    // MARK: - Recording and Capture

    /// Toggle MIR feature recording to ~/phosphene_features.csv.
    func toggleRecording() {
        if mirPipeline.isRecording {
            mirPipeline.stopRecording()
        } else {
            mirPipeline.startRecording()
        }
    }

    /// Toggle feature vector capture to CSV file.
    func toggleCapture() {
        if isCapturing {
            stopCapture()
        } else {
            startCapture()
        }
    }

    func startCapture() {
        let dir = FileManager.default.temporaryDirectory
        let name = "phosphene_features_\(Int(Date().timeIntervalSince1970)).csv"
        let url = dir.appendingPathComponent(name)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            logger.error("Failed to create capture file: \(url.path)")
            return
        }

        let header = "timestamp,track,artist,genre,subBass,lowBass,lowMid,midHigh,highMid,high,"
            + "centroid,flux,majorCorr,minorCorr,bass3,mid3,treble3,magMax,key\n"
        handle.write(Data(header.utf8))

        captureHandle = handle
        captureFilePath = url.path
        isCapturing = true
        logger.info("Feature capture started: \(url.path, privacy: .public)")
    }

    func stopCapture() {
        captureHandle?.closeFile()
        captureHandle = nil
        isCapturing = false
        if let path = captureFilePath {
            logger.info("Feature capture stopped: \(path, privacy: .public)")
        }
    }

    /// Write a feature row to the capture file (called from analysis queue).
    func writeCaptureRow(
        features: [Float],
        fv: Shared.FeatureVector,
        magMax: Float,
        key: String?
    ) {
        guard let handle = captureHandle else { return }
        let track = currentTrack?.title ?? ""
        let artist = currentTrack?.artist ?? ""
        let genre = preFetchedProfile?.genreTags.joined(separator: "|") ?? ""
        let row = String(
            format: "%.3f,%@,%@,%@,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
            + "%.5f,%.5f,%.5f,%.5f,%.4f,%.4f,%.4f,%.5f,%@\n",
            Date().timeIntervalSince1970,
            track.replacingOccurrences(of: ",", with: ";"),
            artist.replacingOccurrences(of: ",", with: ";"),
            genre.replacingOccurrences(of: ",", with: "|"),
            features[0],
            features[1],
            features[2],
            features[3],
            features[4],
            features[5],
            features[6],
            features[7],
            features[8],
            features[9],
            fv.bass,
            fv.mid,
            fv.treble,
            magMax,
            key ?? "nil"
        )
        handle.write(Data(row.utf8))
    }

    // MARK: - Track Change

    /// Build the onTrackChange callback that resets MIR state and kicks off
    /// async metadata pre-fetching.
    func makeTrackChangeCallback(
        fetcher: MetadataPreFetcher
    ) -> (TrackChangeEvent) -> Void {
        let mir = mirPipeline
        return { [weak self] event in
            guard let self else { return }
            mir.currentTrackName = event.current.title ?? ""
            mir.currentArtistName = event.current.artist ?? ""
            Task { @MainActor in
                self.currentTrack = event.current
                self.preFetchedProfile = nil
                logger.info("Track: \(event.current.title ?? "?") — \(event.current.artist ?? "?")")
            }
            // Reset MIR accumulators on track change.
            mir.reset()
            // Reset accumulated audio time — prevents previous track's phase from bleeding.
            self.pipeline.resetAccumulatedAudioTime()
            // Reset stem pipeline — prevents previous track's stems from bleeding.
            self.resetStemPipeline()
            self.kickoffPreFetch(for: event.current, fetcher: fetcher)
        }
    }

    /// Run the metadata pre-fetcher for a new track and apply BPM/key on the main actor.
    func kickoffPreFetch(for track: TrackMetadata, fetcher: MetadataPreFetcher) {
        Task {
            let profile = await fetcher.prefetch(for: track)
            await MainActor.run {
                self.preFetchedProfile = profile
                if let bpm = profile?.bpm {
                    self.estimatedTempo = bpm
                    logger.info("Using pre-fetched BPM: \(bpm)")
                }
                if let key = profile?.key {
                    self.estimatedKey = key
                    logger.info("Using pre-fetched key: \(key)")
                }
            }
        }
    }
}

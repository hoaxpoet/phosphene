// SessionPreparer+Analysis — Static analysis helpers for offline preview processing.
// All functions are static (no self) so they can run inside Task.detached without
// capturing the @MainActor-isolated SessionPreparer.

import Accelerate
import Audio
import DSP
import Foundation
import ML
import Shared

// MARK: - Internal Types

/// Result of `analyzeMIR` — avoids a large tuple return type.
private struct MIRAnalysisResult {
    var bpm: Float?
    var key: String?
    var mood: EmotionalState
    var centroidAvg: Float
    var sectionCount: Int
}

// MARK: - Analysis Pipeline

extension SessionPreparer {

    // MARK: - analyzePreview
    //
    // `analyzePreview` runs sequential pipeline stages (stem separation →
    // analyzer warmup → MIR → beat grid → drums beat grid → grid-onset
    // calibration) — kept inline so the sequential structure stays readable.

    /// Run the full analysis pipeline on a decoded preview clip.
    ///
    /// Executes stem separation → StemAnalyzer warmup → MIR analysis in sequence.
    /// Called from a `Task.detached` block inside `prepareTrack(_:)` (streaming
    /// path) and from `VisualizerEngine.prepareAndStartLocalFilePlayback(url:)`
    /// (LF.2 path, 2026-05-27) to pre-warm local-file playback.
    ///
    /// `public` so the App-layer LF.2 entry point can drive pre-analysis
    /// directly without going through the full `SessionManager` /
    /// `SessionPreparer.prepare(tracks:)` orchestration (LF.2 is single-file
    /// + ad-hoc, no playlist).
    ///
    /// - Parameters:
    ///   - preview: Mono Float32 PCM from PreviewDownloader or local-file decode.
    ///   - separator: Stem separator to use (injected for testing).
    ///   - analyzer: Stem energy analyzer (injected for testing).
    ///   - classifier: Mood classifier (injected for testing).
    ///   - beatGridAnalyzer: Optional Beat This! analyzer. When `nil`, the
    ///     returned `CachedTrackData.beatGrid` is `.empty`.
    ///   - prefetchedProfile: Optional pre-fetched track metadata. When
    ///     `prefetchedProfile.timeSignature` is non-nil, the ML-detected
    ///     `BeatGrid.beatsPerBar` is overridden before caching.
    /// - Returns: Fully populated `CachedTrackData`.
    nonisolated public static func analyzePreview(
        _ preview: PreviewAudio,
        separator: any StemSeparating,
        analyzer: any StemAnalyzing,
        classifier: any MoodClassifying,
        beatGridAnalyzer: (any BeatGridAnalyzing)? = nil,
        familyAnalyzer: (any InstrumentFamilyAnalyzing)? = nil,
        prefetchedProfile: PreFetchedTrackProfile? = nil
    ) throws -> CachedTrackData {

        // Step 1: Separate stems from preview PCM.
        let result = try separator.separate(
            audio: preview.pcmSamples,
            channelCount: 1,
            sampleRate: Float(preview.sampleRate)
        )

        // Step 2: Read the separated stems BY VALUE (CLEAN.1.2 / BUG-031) — never
        // from the shared `separator.stemBuffers`, which the live + prep paths
        // race over. `result.stemWaveforms` is this call's own data.
        let stemWaveforms = result.stemWaveforms

        // Step 3: Multi-frame AGC warmup → StemFeatures snapshot.
        let stemFeatures = warmUpAndAnalyze(
            stemWaveforms: stemWaveforms,
            sampleRate: Float(preview.sampleRate),
            analyzer: analyzer
        )

        // Step 4: Offline MIR analysis (BPM, key, mood, centroid).
        let mir = analyzeMIR(
            samples: preview.pcmSamples,
            sampleRate: preview.sampleRate,
            classifier: classifier
        )

        // Steps 5 + 6: offline beat grids (full mix + drums stem), with metadata meter override.
        let (beatGrid, drumsBeatGrid) = computeBeatGrids(
            preview: preview,
            stemWaveforms: stemWaveforms,
            beatGridAnalyzer: beatGridAnalyzer,
            prefetchedProfile: prefetchedProfile
        )

        // Step 7 (BUG-007.8): per-track grid-vs-onset offset calibration.
        let gridOnsetOffsetMs = Self.computeGridOnsetOffsetMs(preview: preview, grid: beatGrid)

        // Step 8 (IFC.4 / D-177): PANNs family-activity sweep over the preview clip (Tier-1; nil → empty).
        // The PREPPERF.2 TIMING scaffolding (clock/stageStart/durationMs) was removed on main; the family
        // analysis itself is unchanged.
        let familySeries = familyAnalyzer?.analyzeFamilyActivity(
            samples: preview.pcmSamples, sampleRate: Double(preview.sampleRate)) ?? []

        let profile = TrackProfile(
            bpm: mir.bpm,
            key: mir.key,
            mood: mir.mood,
            spectralCentroidAvg: mir.centroidAvg,
            genreTags: [],
            stemEnergyBalance: stemFeatures,
            estimatedSectionCount: mir.sectionCount
        )

        return CachedTrackData(
            stemWaveforms: stemWaveforms,
            stemFeatures: stemFeatures,
            trackProfile: profile,
            beatGrid: beatGrid,
            drumsBeatGrid: drumsBeatGrid,
            gridOnsetOffsetMs: gridOnsetOffsetMs,
            instrumentFamilySeries: familySeries
        )
    }

    /// Compute the full-mix and drums-stem offline beat grids (Steps 5 + 6).
    ///
    /// Full-mix grid gets the metadata-driven meter override (Round 26,
    /// 2026-05-15): the ML detector sometimes guesses the meter wrong on odd
    /// time-signature tracks (Money's 7/4 → detected as 2/X). When the external
    /// metadata source returns a `time_signature`, override the auto-detected
    /// meter before caching so the cached value is correct on disk and the live
    /// drift tracker installs the corrected meter from the moment playback
    /// begins (no runtime-correction race window). Drums grid is the DSP.4
    /// diagnostic on stem index 1 (StemSeparator.stemLabels: vocals, drums,
    /// bass, other) — same analyzer instance (the MPSGraph graph is reusable
    /// across calls, no re-init). `nil` analyzer → both `.empty`.
    nonisolated private static func computeBeatGrids(
        preview: PreviewAudio,
        stemWaveforms: [[Float]],
        beatGridAnalyzer: (any BeatGridAnalyzing)?,
        prefetchedProfile: PreFetchedTrackProfile?
    ) -> (beatGrid: BeatGrid, drumsBeatGrid: BeatGrid) {
        let beatGridRaw: BeatGrid
        if let gridAnalyzer = beatGridAnalyzer {
            beatGridRaw = gridAnalyzer.analyzeBeatGrid(
                samples: preview.pcmSamples,
                sampleRate: Double(preview.sampleRate)
            )
        } else {
            beatGridRaw = .empty
        }

        let beatGrid: BeatGrid
        if let timeSignature = prefetchedProfile?.timeSignature,
           !beatGridRaw.beats.isEmpty {
            beatGrid = beatGridRaw.overridingBeatsPerBar(timeSignature)
        } else {
            beatGrid = beatGridRaw
        }

        let drumsBeatGrid: BeatGrid
        if let gridAnalyzer = beatGridAnalyzer, stemWaveforms.count > 1 {
            drumsBeatGrid = gridAnalyzer.analyzeBeatGrid(
                samples: stemWaveforms[1],
                sampleRate: Double(preview.sampleRate)
            )
        } else {
            drumsBeatGrid = .empty
        }

        return (beatGrid, drumsBeatGrid)
    }

    /// Replay the preview audio through the live BeatDetector offline and
    /// return the median (gridBeat − onsetTime) offset in milliseconds
    /// (BUG-007.8). Stored on `CachedTrackData` and applied at playback time
    /// as the drift EMA's initial bias — eliminates the per-track drift
    /// wandering observed in session 2026-05-07T22-00-00Z (drift averages
    /// spanned −95 to +96 ms across a single playlist). Returns 0 when the
    /// grid is empty or there's insufficient data.
    nonisolated private static func computeGridOnsetOffsetMs(
        preview: PreviewAudio, grid: BeatGrid
    ) -> Double {
        GridOnsetCalibrator().calibrate(
            samples: preview.pcmSamples,
            sampleRate: Double(preview.sampleRate),
            grid: grid
        )
    }

    // MARK: - StemAnalyzer Warmup

    /// Iterate through stem waveforms in 1024-sample hops, warming up the
    /// BandEnergyProcessor AGC before returning the final `StemFeatures` snapshot.
    ///
    /// Mirrors the multi-frame warmup in `VisualizerEngine+Stems.runStemSeparation()`.
    nonisolated private static func warmUpAndAnalyze(
        stemWaveforms: [[Float]],
        sampleRate: Float,
        analyzer: any StemAnalyzing
    ) -> StemFeatures {
        let hopSize = 1024
        let fps = sampleRate / Float(hopSize)
        let sampleCount = stemWaveforms.first?.count ?? 0
        guard sampleCount >= hopSize else { return .zero }

        var lastFeatures = StemFeatures.zero
        var offset = 0
        while offset + hopSize <= sampleCount {
            var frameWaveforms: [[Float]] = []
            for stem in stemWaveforms {
                if offset < stem.count {
                    let end = min(offset + hopSize, stem.count)
                    frameWaveforms.append(Array(stem[offset..<end]))
                } else {
                    frameWaveforms.append([Float](repeating: 0, count: hopSize))
                }
            }
            lastFeatures = analyzer.analyze(stemWaveforms: frameWaveforms, fps: fps)
            offset += hopSize
        }
        return lastFeatures
    }

    // MARK: - MIR Analysis

    /// Process the preview audio frame-by-frame through a fresh `MIRPipeline`
    /// to extract BPM, key, mood, and spectral centroid average.
    ///
    /// Uses a 1024-point non-overlapping vDSP FFT at the preview's native sample
    /// rate (~43 frames/second at 44100 Hz). At 30 seconds this yields ~1290 frames,
    /// enough for `BeatDetector` and `ChromaExtractor` to converge on stable values.
    nonisolated private static func analyzeMIR(
        samples: [Float],
        sampleRate: Int,
        classifier: any MoodClassifying
    ) -> MIRAnalysisResult {
        let fftSize = 1024
        let binCount = fftSize / 2   // 512

        // The window→magnitude formula (Hann → |FFT| × 2/fftSize) lives in the shared
        // FFTMagnitudeKernel — byte-identical to the live FFTProcessor (BUG-066 / MOOD-FLUX.3).
        guard let fft = try? FFTMagnitudeKernel(fftSize: fftSize) else {
            return MIRAnalysisResult(
                bpm: nil, key: nil, mood: .neutral, centroidAvg: 0, sectionCount: 0
            )
        }

        let mir = MIRPipeline(binCount: binCount, sampleRate: Float(sampleRate), fftSize: fftSize)
        let fps = Float(sampleRate) / Float(fftSize)
        let dt = 1.0 / fps

        var centroidSum: Float = 0
        var frameCount = 0
        var offset = 0

        while offset + fftSize <= samples.count {
            // Copy this frame's window into the kernel scratch, then run the shared formula.
            samples.withUnsafeBufferPointer { srcBuf in
                fft.windowed.withUnsafeMutableBufferPointer { dstBuf in
                    guard let srcBase = srcBuf.baseAddress,
                          let dstBase = dstBuf.baseAddress else { return }
                    dstBase.update(from: srcBase.advanced(by: offset), count: fftSize)
                }
            }
            fft.computeMagnitudes()

            let time = Float(frameCount) * dt
            let fv = mir.process(magnitudes: fft.magnitudes, fps: fps, time: time, deltaTime: dt)
            centroidSum += fv.spectralCentroid
            frameCount += 1

            // Run mood classifier every 30 frames to capture evolving mood.
            if frameCount % 30 == 0 {
                let moodInput: [Float] = [
                    fv.subBass, fv.lowBass, fv.lowMid, fv.midHigh, fv.highMid, fv.high,
                    fv.spectralCentroid,
                    mir.rawSmoothedFlux,
                    mir.latestMajorKeyCorrelation, mir.latestMinorKeyCorrelation
                ]
                _ = try? classifier.classify(features: moodInput)
            }

            offset += fftSize
        }

        let centroidAvg = frameCount > 0 ? centroidSum / Float(frameCount) : 0
        let sectionCount = frameCount > 0
            ? Int(mir.latestStructuralPrediction.sectionIndex) + 1
            : 0
        // SECDET.3b (C.4), updated at D-170: the live StructuralAnalyzer keeps
        // its count role (sectionIndex → estimatedSectionCount) ONLY. Boundary
        // detection was REMOVED at D-170 (SectionDetector deleted; below the
        // perceptual bar + streaming has no full-track audio — do not
        // reintroduce); the planner segments with equal slices.
        // (`boundaryTimestamps` / `boundaryNoveltyScores` remain on
        // StructuralAnalyzer for diagnostics, unread.)

        return MIRAnalysisResult(
            bpm: mir.stableBPM,
            key: mir.stableKey,
            mood: classifier.currentState,
            centroidAvg: centroidAvg,
            sectionCount: sectionCount
        )
    }
}

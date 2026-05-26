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

/// Working buffers for the per-frame vDSP FFT computation.
/// Allocated once per `analyzeMIR` call to avoid per-frame heap pressure.
private struct FFTContext {
    var hannWindow: [Float]
    var windowed: [Float]
    var realPart: [Float]
    var imagPart: [Float]
    var magnitudes: [Float]
    let log2n: vDSP_Length
    let fftSetup: FFTSetup
    let fftSize: Int
    let binCount: Int
}

// MARK: - Analysis Pipeline

extension SessionPreparer {

    // MARK: - analyzePreview
    //
    // `analyzePreview` runs sequential pipeline stages (stem separation →
    // analyzer warmup → MIR → beat grid → drums beat grid → grid-onset
    // calibration). Body length exceeds SwiftLint's default cap because
    // each stage is a few lines; splitting into helpers would obscure the
    // sequential pipeline structure that's the point of this function.
    // swiftlint:disable function_body_length

    /// Run the full analysis pipeline on a decoded preview clip.
    ///
    /// Executes stem separation → StemAnalyzer warmup → MIR analysis in sequence.
    /// Called from a `Task.detached` block inside `prepareTrack(_:)`.
    ///
    /// - Parameters:
    ///   - preview: Mono Float32 PCM from PreviewDownloader.
    ///   - separator: Stem separator to use (injected for testing).
    ///   - analyzer: Stem energy analyzer (injected for testing).
    ///   - classifier: Mood classifier (injected for testing).
    ///   - beatGridAnalyzer: Optional Beat This! analyzer. When `nil`, the
    ///     returned `CachedTrackData.beatGrid` is `.empty`.
    ///   - prefetchedProfile: Optional pre-fetched track metadata. When
    ///     `prefetchedProfile.timeSignature` is non-nil, the ML-detected
    ///     `BeatGrid.beatsPerBar` is overridden before caching.
    /// - Returns: Fully populated `CachedTrackData`.
    nonisolated static func analyzePreview(
        _ preview: PreviewAudio,
        separator: any StemSeparating,
        analyzer: any StemAnalyzing,
        classifier: any MoodClassifying,
        beatGridAnalyzer: (any BeatGridAnalyzing)? = nil,
        prefetchedProfile: PreFetchedTrackProfile? = nil
    ) throws -> CachedTrackData {

        // Step 1: Separate stems from preview PCM.
        let result = try separator.separate(
            audio: preview.pcmSamples,
            channelCount: 1,
            sampleRate: Float(preview.sampleRate)
        )

        // Step 2: Extract mono waveforms from UMA output buffers.
        let sampleCount = result.sampleCount
        var stemWaveforms: [[Float]] = []
        for buffer in separator.stemBuffers {
            let count = min(sampleCount, buffer.capacity)
            stemWaveforms.append(Array(buffer.pointer.prefix(count)))
        }

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

        let profile = TrackProfile(
            bpm: mir.bpm,
            key: mir.key,
            mood: mir.mood,
            spectralCentroidAvg: mir.centroidAvg,
            genreTags: [],
            stemEnergyBalance: stemFeatures,
            estimatedSectionCount: mir.sectionCount
        )

        // Step 5: Beat This! offline beat grid on full mix (nil analyzer → BeatGrid.empty).
        let beatGridRaw: BeatGrid
        if let gridAnalyzer = beatGridAnalyzer {
            beatGridRaw = gridAnalyzer.analyzeBeatGrid(
                samples: preview.pcmSamples,
                sampleRate: Double(preview.sampleRate)
            )
        } else {
            beatGridRaw = .empty
        }

        // Round 26 (2026-05-15): metadata-driven meter override. The ML
        // detector sometimes guesses the meter wrong on odd
        // time-signature tracks (Money's 7/4 → detected as 2/X). When
        // the external metadata source returns a `time_signature`,
        // override the auto-detected meter before caching the grid so
        // the cached value is correct on disk and the live drift
        // tracker installs the corrected meter from the moment
        // playback begins (no runtime-correction race window).
        let beatGrid: BeatGrid
        if let timeSignature = prefetchedProfile?.timeSignature,
           !beatGridRaw.beats.isEmpty {
            beatGrid = beatGridRaw.overridingBeatsPerBar(timeSignature)
        } else {
            beatGrid = beatGridRaw
        }

        // Step 6: Beat This! offline beat grid on drums stem only (DSP.4 diagnostic).
        // Drums stem is at index 1 per StemSeparator.stemLabels: ["vocals","drums","bass","other"].
        // Same analyzer instance — the MPSGraph graph is reusable across calls (no re-init).
        let drumsBeatGrid: BeatGrid
        if let gridAnalyzer = beatGridAnalyzer, stemWaveforms.count > 1 {
            drumsBeatGrid = gridAnalyzer.analyzeBeatGrid(
                samples: stemWaveforms[1],
                sampleRate: Double(preview.sampleRate)
            )
        } else {
            drumsBeatGrid = .empty
        }

        // Step 7 (BUG-007.8): per-track grid-vs-onset offset calibration.
        let gridOnsetOffsetMs = Self.computeGridOnsetOffsetMs(preview: preview, grid: beatGrid)

        return CachedTrackData(
            stemWaveforms: stemWaveforms,
            stemFeatures: stemFeatures,
            trackProfile: profile,
            beatGrid: beatGrid,
            drumsBeatGrid: drumsBeatGrid,
            gridOnsetOffsetMs: gridOnsetOffsetMs
        )
    }

    // swiftlint:enable function_body_length

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

        let log2n = vDSP_Length(log2(Double(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return MIRAnalysisResult(bpm: nil, key: nil, mood: .neutral, centroidAvg: 0, sectionCount: 0)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var hannWindow = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var ctx = FFTContext(
            hannWindow: hannWindow,
            windowed: [Float](repeating: 0, count: fftSize),
            realPart: [Float](repeating: 0, count: binCount),
            imagPart: [Float](repeating: 0, count: binCount),
            magnitudes: [Float](repeating: 0, count: binCount),
            log2n: log2n,
            fftSetup: fftSetup,
            fftSize: fftSize,
            binCount: binCount
        )

        let mir = MIRPipeline(binCount: binCount, sampleRate: Float(sampleRate), fftSize: fftSize)
        let fps = Float(sampleRate) / Float(fftSize)
        let dt = 1.0 / fps

        var centroidSum: Float = 0
        var frameCount = 0
        var offset = 0

        while offset + fftSize <= samples.count {
            computeFFTMagnitudes(samples: samples, offset: offset, ctx: &ctx)

            let time = Float(frameCount) * dt
            let fv = mir.process(magnitudes: ctx.magnitudes, fps: fps, time: time, deltaTime: dt)
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

        return MIRAnalysisResult(
            bpm: mir.stableBPM,
            key: mir.stableKey,
            mood: classifier.currentState,
            centroidAvg: centroidAvg,
            sectionCount: sectionCount
        )
    }

    // MARK: - FFT Helper

    /// Compute magnitude bins from a sample window using vDSP FFT.
    /// Writes results into `ctx.magnitudes` in-place.
    nonisolated private static func computeFFTMagnitudes(
        samples: [Float],
        offset: Int,
        ctx: inout FFTContext
    ) {
        let fftSize = ctx.fftSize
        let binCount = ctx.binCount

        // Copy window from input.
        samples.withUnsafeBufferPointer { srcBuf in
            ctx.windowed.withUnsafeMutableBufferPointer { dstBuf in
                guard let srcBase = srcBuf.baseAddress,
                      let dstBase = dstBuf.baseAddress else { return }
                dstBase.update(from: srcBase.advanced(by: offset), count: fftSize)
            }
        }

        // Apply Hann window.
        vDSP_vmul(ctx.windowed, 1, ctx.hannWindow, 1, &ctx.windowed, 1, vDSP_Length(fftSize))

        // Forward FFT → squared magnitudes.
        ctx.realPart.withUnsafeMutableBufferPointer { realBuf in
            ctx.imagPart.withUnsafeMutableBufferPointer { imagBuf in
                guard let rBase = realBuf.baseAddress, let iBase = imagBuf.baseAddress else { return }
                var split = DSPSplitComplex(realp: rBase, imagp: iBase)

                ctx.windowed.withUnsafeBufferPointer { input in
                    guard let inp = input.baseAddress else { return }
                    inp.withMemoryRebound(to: DSPComplex.self, capacity: binCount) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(binCount))
                    }
                }

                vDSP_fft_zrip(ctx.fftSetup, &split, 1, ctx.log2n, FFTDirection(kFFTDirection_Forward))

                ctx.magnitudes.withUnsafeMutableBufferPointer { magBuf in
                    guard let mBase = magBuf.baseAddress else { return }
                    vDSP_zvmags(&split, 1, mBase, 1, vDSP_Length(binCount))
                }
            }
        }

        // Scale: divide by fftSize, then square-root for magnitude (not power).
        var scale = Float(fftSize)
        vDSP_vsdiv(ctx.magnitudes, 1, &scale, &ctx.magnitudes, 1, vDSP_Length(binCount))
        var cnt = Int32(binCount)
        vvsqrtf(&ctx.magnitudes, ctx.magnitudes, &cnt)
    }
}

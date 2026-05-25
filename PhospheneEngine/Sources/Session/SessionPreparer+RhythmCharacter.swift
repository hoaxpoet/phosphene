// SessionPreparer+RhythmCharacter — Per-track rhythm-character computation
// (BSAudit.3 design §7).
//
// Replays the 30 s Spotify preview audio offline through `SpectralAnalyzer`,
// `BeatDetector`, and `BroadbandPeakDetector` to derive five rhythm-character
// fields that scale runtime phase-acquisition tunables in
// `LiveBeatDriftTracker.installBPMPrior(bpm:character:)`.
//
// All inputs are already-computed (preview PCM samples + the `BeatGrid` from
// `DefaultBeatGridAnalyzer`). No new ML inference. The marginal cost is
// the one-pass FFT loop over ~30 s of preview audio (~50-100 ms per track
// per design §9.8 — well inside Matt's 3-minute rehearsal budget).

import Accelerate
import DSP
import Foundation
import Shared

// MARK: - Rhythm Character Computation

extension SessionPreparer {

    // MARK: - Internal Types

    /// Per-frame signals collected during the offline replay. Stored once per
    /// FFT hop and then post-processed against the `BeatGrid` to produce the
    /// final `RhythmCharacter`.
    private struct RhythmFrameSignals {
        /// Sub-bass onset timestamps in seconds (BeatDetector band 0).
        var subBassOnsetTimes: [Double] = []
        /// Broadband-flux peak timestamps in seconds.
        var broadbandPeakTimes: [Double] = []
        /// Per-frame `smoothedFlux` (one entry per FFT hop). Indexed by frame.
        var fluxPerFrame: [Float] = []
        /// Frame rate in Hz (samples per second / hop).
        var frameRate: Double = 0
    }

    /// Bundle of pre-allocated FFT scaffolding for one `replayPreview` pass.
    /// Mirrors the `FFTContext` pattern in `SessionPreparer+Analysis.swift`.
    private struct PreviewFFTContext {
        let fftSetup: FFTSetup
        let hannWindow: [Float]
        let fftSize: Int
        let binCount: Int
        let log2n: vDSP_Length
    }

    // MARK: - Public Entry Point (package-internal)

    /// Compute `RhythmCharacter` for one track given the prep-time preview
    /// audio and the resolved `BeatGrid`. Returns `nil` when the grid is
    /// empty (no rhythm structure to characterise) or when the preview is
    /// shorter than two FFT windows.
    ///
    /// - Parameters:
    ///   - preview: Mono Float32 PCM from `PreviewDownloader`.
    ///   - grid: The `BeatGrid` resolved by Beat This! on the same preview.
    /// - Returns: Populated `RhythmCharacter`, or nil on insufficient data.
    nonisolated static func computeRhythmCharacter(
        preview: PreviewAudio,
        grid: BeatGrid
    ) -> RhythmCharacter? {
        guard !grid.beats.isEmpty else { return nil }
        guard let signals = replayPreview(preview: preview) else { return nil }
        return derive(signals: signals, grid: grid)
    }

    // MARK: - Stage 1: Offline Replay

    /// Walk the preview audio in non-overlapping 1024-sample FFT windows
    /// (matching the live pipeline cadence and the
    /// `GridOnsetCalibrator`/`analyzeMIR` paths). For each frame, populate:
    ///   - sub-bass onset timestamps via `BeatDetector` band 0
    ///   - broadband-peak timestamps via `BroadbandPeakDetector` over
    ///     `SpectralAnalyzer.smoothedFlux`
    ///   - per-frame smoothed flux (for the beat-strength profile)
    nonisolated private static func replayPreview(
        preview: PreviewAudio
    ) -> RhythmFrameSignals? {
        let fftSize = 1024
        let binCount = fftSize / 2
        let sampleRate = Float(preview.sampleRate)
        let log2n = vDSP_Length(10)

        guard preview.pcmSamples.count >= fftSize else { return nil }
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let ctx = PreviewFFTContext(
            fftSetup: fftSetup,
            hannWindow: makeHannWindow(size: fftSize),
            fftSize: fftSize,
            binCount: binCount,
            log2n: log2n
        )
        let spectral = SpectralAnalyzer(
            binCount: binCount, sampleRate: sampleRate, fftSize: fftSize
        )
        let beat = BeatDetector(
            binCount: binCount, sampleRate: sampleRate, fftSize: fftSize
        )
        let peaks = BroadbandPeakDetector()
        let hop = fftSize
        let frameRate = Double(preview.sampleRate) / Double(hop)
        let dt = Float(1.0 / frameRate)

        var signals = RhythmFrameSignals()
        signals.frameRate = frameRate
        signals.fluxPerFrame.reserveCapacity(preview.pcmSamples.count / hop + 1)

        var frameIdx = 0
        var start = 0
        while start + fftSize <= preview.pcmSamples.count {
            let mags = computeMagnitudes(
                samples: preview.pcmSamples,
                start: start,
                ctx: ctx
            )
            let spec = spectral.process(magnitudes: mags)
            let beatResult = beat.process(
                magnitudes: mags, fps: Float(frameRate), deltaTime: dt
            )
            let isPeak = peaks.process(smoothedFlux: spec.smoothedFlux, deltaTime: dt)

            let frameTime = Double(frameIdx) * Double(hop) / Double(preview.sampleRate)
            signals.fluxPerFrame.append(spec.smoothedFlux)
            if !beatResult.onsets.isEmpty && beatResult.onsets[0] {
                signals.subBassOnsetTimes.append(frameTime)
            }
            if isPeak {
                signals.broadbandPeakTimes.append(frameTime)
            }
            frameIdx += 1
            start += hop
        }
        return signals
    }

    // MARK: - Stage 2: Derive RhythmCharacter

    /// Project the per-frame signals onto the `BeatGrid` to produce the
    /// final `RhythmCharacter`. All fields per BSAudit.3 design §7.
    nonisolated private static func derive(
        signals: RhythmFrameSignals,
        grid: BeatGrid
    ) -> RhythmCharacter {
        let bpb = max(grid.beatsPerBar, 1)
        let beatCount = grid.beats.count
        let period = grid.medianBeatPeriod > 0 ? grid.medianBeatPeriod : 0.5

        // ----- beatStrengthProfile -----
        // Sample smoothed flux at the frame nearest each beat; average by
        // raw bar-slot index; normalise so the max slot reads 1.0.
        let beatStrengthProfile = computeBeatStrengthProfile(
            signals: signals, grid: grid, beatsPerBar: bpb
        )

        // ----- onsetsPerBeat -----
        // Sub-bass onsets observed across the preview / number of beats.
        let onsetsPerBeat: Float = beatCount > 0
            ? Float(Double(signals.subBassOnsetTimes.count) / Double(beatCount))
            : 0

        // ----- syncopationIndex -----
        // Fraction of sub-bass onsets that fall > ¼ beat from the nearest beat.
        let syncopationIndex = computeSyncopationIndex(
            onsets: signals.subBassOnsetTimes, beats: grid.beats, period: period
        )

        // ----- octaveRisk -----
        // Compare broadband-peak rate per beat to 1 (one peak per beat) and 2
        // (two peaks per beat = double-time mis-detection). Linearly ramps
        // octaveRisk from 0 (rate ≤ 1.4) to 1 (rate ≥ 1.7).
        let octaveRisk = computeOctaveRisk(
            peakCount: signals.broadbandPeakTimes.count, beatCount: beatCount
        )

        // ----- phaseAcquisitionDifficulty -----
        // §14: Use the §7 composition (onsetsPerBeat, syncopationIndex,
        // meter regularity from barConfidence). Default formula — calibrate
        // empirically in BSAudit.3.validate.
        let phaseAcquisitionDifficulty = computeDifficulty(
            onsetsPerBeat: onsetsPerBeat,
            syncopationIndex: syncopationIndex,
            barConfidence: grid.barConfidence
        )

        return RhythmCharacter(
            beatStrengthProfile: beatStrengthProfile,
            onsetsPerBeat: onsetsPerBeat,
            octaveRisk: octaveRisk,
            phaseAcquisitionDifficulty: phaseAcquisitionDifficulty,
            syncopationIndex: syncopationIndex
        )
    }

    // MARK: - Derivation Helpers

    nonisolated private static func computeBeatStrengthProfile(
        signals: RhythmFrameSignals,
        grid: BeatGrid,
        beatsPerBar: Int
    ) -> [Float] {
        guard signals.frameRate > 0, !signals.fluxPerFrame.isEmpty else {
            return [Float](repeating: 0, count: beatsPerBar)
        }
        var slotSum = [Float](repeating: 0, count: beatsPerBar)
        var slotCount = [Int](repeating: 0, count: beatsPerBar)
        let frameRate = signals.frameRate
        let frameTotal = signals.fluxPerFrame.count

        for (i, beatTime) in grid.beats.enumerated() {
            let frame = Int((beatTime * frameRate).rounded())
            guard frame >= 0, frame < frameTotal else { continue }
            let slot = ((i % beatsPerBar) + beatsPerBar) % beatsPerBar
            slotSum[slot] += signals.fluxPerFrame[frame]
            slotCount[slot] += 1
        }
        var profile = [Float](repeating: 0, count: beatsPerBar)
        for slot in 0..<beatsPerBar where slotCount[slot] > 0 {
            profile[slot] = slotSum[slot] / Float(slotCount[slot])
        }
        let peak = profile.max() ?? 0
        if peak > 1e-6 {
            for slot in 0..<beatsPerBar { profile[slot] /= peak }
        }
        return profile
    }

    nonisolated private static func computeSyncopationIndex(
        onsets: [Double], beats: [Double], period: Double
    ) -> Float {
        guard !onsets.isEmpty, !beats.isEmpty, period > 0 else { return 0 }
        let threshold = period * 0.25
        var offBeatCount = 0
        for onset in onsets {
            let dist = nearestBeatDistance(to: onset, in: beats)
            if dist > threshold { offBeatCount += 1 }
        }
        return Float(Double(offBeatCount) / Double(onsets.count))
    }

    nonisolated private static func computeOctaveRisk(
        peakCount: Int, beatCount: Int
    ) -> Float {
        guard beatCount > 0 else { return 0 }
        let ratePerBeat = Double(peakCount) / Double(beatCount)
        // Linear ramp 1.4 → 1.7 mapping to 0 → 1; clamp outside.
        let normalized = (ratePerBeat - 1.4) / (1.7 - 1.4)
        return Float(max(0, min(1, normalized)))
    }

    nonisolated private static func computeDifficulty(
        onsetsPerBeat: Float,
        syncopationIndex: Float,
        barConfidence: Float
    ) -> Float {
        // Sparseness: onsetsPerBeat in [0, 2] → [1, 0]. Above 2, no
        // additional credit (dense tracks are easy).
        let sparseness = max(0, min(1, 1.0 - onsetsPerBeat / 2.0))
        let irregularity = max(0, min(1, 1.0 - barConfidence))
        // Weighted sum per design §14 (default formula, validate empirically):
        //   sparse + syncopated + irregular meter all push difficulty up.
        let weighted = sparseness * 0.5 + syncopationIndex * 0.3 + irregularity * 0.2
        return max(0, min(1, weighted))
    }

    nonisolated private static func nearestBeatDistance(
        to time: Double, in beats: [Double]
    ) -> Double {
        guard !beats.isEmpty else { return .infinity }
        var lo = 0
        var hi = beats.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if beats[mid] < time { lo = mid + 1 } else { hi = mid }
        }
        let upper = beats[lo]
        if lo == 0 { return abs(upper - time) }
        let lower = beats[lo - 1]
        return min(abs(upper - time), abs(lower - time))
    }

    // MARK: - FFT Helpers

    nonisolated private static func makeHannWindow(size: Int) -> [Float] {
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        return window
    }

    nonisolated private static func computeMagnitudes(
        samples: [Float],
        start: Int,
        ctx: PreviewFFTContext
    ) -> [Float] {
        let fftSize = ctx.fftSize
        let binCount = ctx.binCount
        var windowed = [Float](repeating: 0, count: fftSize)
        let endIdx = min(start + fftSize, samples.count)
        for i in start..<endIdx { windowed[i - start] = samples[i] }
        vDSP_vmul(windowed, 1, ctx.hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

        var realPart = [Float](repeating: 0, count: binCount)
        var imagPart = [Float](repeating: 0, count: binCount)
        var magnitudes = [Float](repeating: 0, count: binCount)

        windowed.withUnsafeBufferPointer { srcPtr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    guard let realBase = realPtr.baseAddress,
                          let imagBase = imagPtr.baseAddress,
                          let srcBase = srcPtr.baseAddress else { return }
                    var splitComplex = DSPSplitComplex(
                        realp: realBase,
                        imagp: imagBase
                    )
                    srcBase.withMemoryRebound(
                        to: DSPComplex.self, capacity: binCount
                    ) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(binCount))
                    }
                    vDSP_fft_zrip(ctx.fftSetup, &splitComplex, 1, ctx.log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(binCount))
                    var scale = 2.0 / Float(fftSize)
                    vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(binCount))
                }
            }
        }
        return magnitudes
    }
}

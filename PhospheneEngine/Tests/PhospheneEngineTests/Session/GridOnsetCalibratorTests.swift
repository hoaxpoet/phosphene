// GridOnsetCalibratorTests — BUG-007.8 contract tests for the per-track
// grid-vs-onset calibrator that runs at preparation time.

import Foundation
import Testing
@testable import DSP
@testable import Session

@Suite("GridOnsetCalibrator")
struct GridOnsetCalibratorTests {

    // MARK: 1. Empty grid → 0

    @Test("emptyGrid_returnsZero")
    func test_emptyGridReturnsZero() {
        let calibrator = GridOnsetCalibrator()
        let samples = [Float](repeating: 0, count: 4096)
        let offset = calibrator.calibrate(samples: samples, sampleRate: 22050, grid: .empty)
        #expect(offset == 0)
    }

    // MARK: 2. Insufficient samples → 0

    @Test("insufficientSamples_returnsZero")
    func test_insufficientSamplesReturnsZero() {
        let calibrator = GridOnsetCalibrator()
        // Less than fftSize=1024 samples → can't compute a single FFT.
        let samples = [Float](repeating: 0, count: 512)
        let grid = makeUniformGrid(bpm: 120, beats: 8)
        let offset = calibrator.calibrate(samples: samples, sampleRate: 22050, grid: grid)
        #expect(offset == 0)
    }

    // MARK: 3. Pure silence → 0 (no onsets to match)

    @Test("silentInput_returnsZero")
    func test_silentInputReturnsZero() {
        let calibrator = GridOnsetCalibrator()
        // 5 seconds of silence at 22050 Hz.
        let samples = [Float](repeating: 0, count: 5 * 22050)
        let grid = makeUniformGrid(bpm: 120, beats: 16)
        let offset = calibrator.calibrate(samples: samples, sampleRate: 22050, grid: grid)
        #expect(offset == 0,
                "Pure silence has no onsets — calibrator must return 0 (no signal)")
    }

    // MARK: 4. Synthetic kicks aligned with grid → near-zero offset

    /// Generate 60 Hz tone bursts at exactly the grid beat times. The BeatDetector
    /// should fire on the spectral flux peak at each burst onset. With aligned
    /// inputs, the calibrator's median offset should be small (within ±50 ms,
    /// allowing for FFT-frame quantisation at the 1024-sample hop).
    @Test("alignedKicks_returnsSmallOffset")
    func test_alignedKicksReturnsSmallOffset() {
        let sampleRate: Double = 22050
        let durationSeconds: Double = 4.0
        let beatTimes = stride(from: 0.5, to: durationSeconds, by: 0.5).map { $0 }   // 120 BPM
        let samples = synthesizeKickPattern(
            sampleRate: sampleRate,
            durationSeconds: durationSeconds,
            kickTimes: beatTimes
        )
        let grid = BeatGrid(
            beats: beatTimes,
            downbeats: stride(from: 0, to: beatTimes.count, by: 4).map { beatTimes[$0] },
            bpm: 120,
            beatsPerBar: 4,
            barConfidence: 1.0,
            frameRate: 50.0,
            frameCount: 200
        )
        let calibrator = GridOnsetCalibrator()
        let offset = calibrator.calibrate(samples: samples, sampleRate: sampleRate, grid: grid)
        // FFT hop is 1024 samples = 46.4 ms at 22050 Hz. Median offset should
        // sit within ±50 ms of zero for aligned input.
        #expect(abs(offset) < 50.0,
                "Aligned kicks should produce |offset| < 50 ms; got \(offset)")
    }

    // MARK: 5. Offset kicks → recovered offset

    /// Same kick pattern, but kicks shifted +30 ms relative to the grid. Calibrator
    /// should report grid − onset ≈ −30 ms (grid earlier than detected onsets).
    @Test("offsetKicks_recoversNegativeOffset")
    func test_offsetKicksRecoversNegativeOffset() {
        let sampleRate: Double = 22050
        let durationSeconds: Double = 4.0
        let gridTimes = stride(from: 0.5, to: durationSeconds, by: 0.5).map { $0 }
        let kickShiftS = 0.030   // kicks fire 30 ms LATER than grid
        let kickTimes = gridTimes.map { $0 + kickShiftS }
        let samples = synthesizeKickPattern(
            sampleRate: sampleRate,
            durationSeconds: durationSeconds,
            kickTimes: kickTimes
        )
        let grid = BeatGrid(
            beats: gridTimes,
            downbeats: stride(from: 0, to: gridTimes.count, by: 4).map { gridTimes[$0] },
            bpm: 120,
            beatsPerBar: 4,
            barConfidence: 1.0,
            frameRate: 50.0,
            frameCount: 200
        )
        let calibrator = GridOnsetCalibrator()
        let offset = calibrator.calibrate(samples: samples, sampleRate: sampleRate, grid: grid)
        // Expected: grid − onset ≈ −30 ms (onsets fire later → drift converges
        // toward this in the live tracker). FFT-hop quantisation: ±50 ms.
        #expect(offset < 0,
                "Onsets shifted +30 ms should produce negative offset; got \(offset)")
        #expect(abs(offset - (-kickShiftS * 1000.0)) < 50.0,
                "Recovered offset should be near -30 ms (±50 ms); got \(offset)")
    }

    // MARK: - Helpers

    /// Synthesize a 60 Hz tone burst at each `kickTime`, padded with silence.
    /// Each burst is 50 ms long with an exponential decay envelope. The 60 Hz
    /// fundamental + envelope shape produces enough spectral flux in the
    /// sub-bass band to reliably trigger BeatDetector's onset detection.
    private func synthesizeKickPattern(
        sampleRate: Double,
        durationSeconds: Double,
        kickTimes: [Double]
    ) -> [Float] {
        let totalSamples = Int(durationSeconds * sampleRate)
        var samples = [Float](repeating: 0, count: totalSamples)
        let burstDurationS = 0.050
        let burstSamples = Int(burstDurationS * sampleRate)
        let freq: Double = 60   // sub-bass kick
        let twoPiFreq = 2.0 * .pi * freq
        for kickTime in kickTimes {
            let startSample = Int(kickTime * sampleRate)
            for i in 0..<burstSamples {
                let idx = startSample + i
                guard idx < totalSamples else { break }
                let t = Double(i) / sampleRate
                let envelope = exp(-t * 30.0)   // ~30 ms decay
                let signal = sin(twoPiFreq * t) * envelope * 0.8
                samples[idx] += Float(signal)
            }
        }
        return samples
    }

    private func makeUniformGrid(bpm: Double, beats: Int, beatsPerBar: Int = 4) -> BeatGrid {
        let period = 60.0 / bpm
        let beatTimes = (0..<beats).map { Double($0) * period }
        let downbeatTimes = stride(from: 0, to: beats, by: beatsPerBar).map { Double($0) * period }
        return BeatGrid(
            beats: beatTimes, downbeats: downbeatTimes, bpm: bpm,
            beatsPerBar: beatsPerBar, barConfidence: 1.0,
            frameRate: 50.0, frameCount: 200
        )
    }
}

// BroadbandPeakDetectorTests — BSAudit.3.impl.1 contract tests for the
// broadband spectral-flux peak detector. Verifies the rising-edge + adaptive-
// median trigger, the BPM-aware refractory period, and the warmup gate.

import Foundation
import Testing
@testable import DSP

@Suite("BroadbandPeakDetector")
struct BroadbandPeakDetectorTests {

    // MARK: - Helpers

    /// Drive `detector` with a flat baseline followed by `pulses` (flux value
    /// at specific frame indices). All other frames carry `baselineFlux`.
    /// Returns the frame indices on which a peak fired.
    private func drivePulses(
        detector: BroadbandPeakDetector,
        frames: Int,
        fps: Double,
        baselineFlux: Float,
        pulses: [Int: Float]
    ) -> [Int] {
        let dt = Float(1.0 / fps)
        var peakFrames: [Int] = []
        for i in 0..<frames {
            let flux = pulses[i] ?? baselineFlux
            if detector.process(smoothedFlux: flux, deltaTime: dt) {
                peakFrames.append(i)
            }
        }
        return peakFrames
    }

    // MARK: - Warmup Gate

    @Test("No peaks fire before the median has warmup samples")
    func warmupSuppresses_earlyPeaks() {
        let detector = BroadbandPeakDetector()
        // Frame 0: huge spike — no median samples yet, must be suppressed.
        let dt: Float = 1.0 / 60
        let earlyPeak = detector.process(smoothedFlux: 5.0, deltaTime: dt)
        #expect(earlyPeak == false)
        // Frames 1-3 also under warmup.
        _ = detector.process(smoothedFlux: 5.0, deltaTime: dt)
        _ = detector.process(smoothedFlux: 5.0, deltaTime: dt)
        let stillWarming = detector.process(smoothedFlux: 5.0, deltaTime: dt)
        #expect(stillWarming == false)
    }

    // MARK: - Rising-Edge + Threshold

    @Test("A clear pulse above 1.8× median fires exactly one peak per refractory window")
    func clearPulse_firesOncePerRefractory() {
        let detector = BroadbandPeakDetector()
        detector.setBPM(120)   // refractory = 0.4 × 0.5 = 0.2 s = 12 frames at 60 fps
        let fps = 60.0
        // Warmup baseline for ≥ 5 frames, then one clear pulse at frame 12.
        // After the pulse, the refractory window suppresses any further pulses
        // until ~ frame 24.
        var pulses: [Int: Float] = [:]
        pulses[12] = 5.0
        pulses[24] = 5.0   // outside refractory — should also fire
        let peaks = drivePulses(
            detector: detector,
            frames: 40,
            fps: fps,
            baselineFlux: 0.1,
            pulses: pulses
        )
        #expect(peaks.count == 2)
        // Both peaks at their respective frame indices.
        if peaks.count == 2 {
            #expect(peaks[0] == 12)
            #expect(peaks[1] == 24)
        }
    }

    @Test("Rising-edge gate suppresses peaks at the trailing edge of a pulse")
    func fallingEdge_doesNotFire() {
        let detector = BroadbandPeakDetector()
        detector.setBPM(60)   // refractory = 0.4 s
        let fps = 60.0
        let dt = Float(1.0 / fps)
        // Warm up the median.
        for _ in 0..<10 { _ = detector.process(smoothedFlux: 0.1, deltaTime: dt) }
        // One rising-edge pulse (should fire).
        let firstRising = detector.process(smoothedFlux: 5.0, deltaTime: dt)
        #expect(firstRising == true)
        // Now feed a *falling* sequence above threshold but below previous frame.
        // Rising-edge gate must reject these even though they exceed threshold.
        let stillAbove = detector.process(smoothedFlux: 4.0, deltaTime: dt)
        #expect(stillAbove == false)
        let stillAbove2 = detector.process(smoothedFlux: 3.0, deltaTime: dt)
        #expect(stillAbove2 == false)
    }

    @Test("Sub-threshold flux does not fire a peak")
    func subThresholdFlux_doesNotFire() {
        let detector = BroadbandPeakDetector()
        detector.setBPM(120)
        let fps = 60.0
        let dt = Float(1.0 / fps)
        // Warm up with baseline 1.0.
        for _ in 0..<20 { _ = detector.process(smoothedFlux: 1.0, deltaTime: dt) }
        // 1.5× median = below 1.8× threshold, should not fire.
        let belowThreshold = detector.process(smoothedFlux: 1.5, deltaTime: dt)
        #expect(belowThreshold == false)
    }

    // MARK: - Refractory

    @Test("Refractory period is 0.4 × beat period at the installed BPM")
    func refractoryPeriod_scalesWithBPM() {
        let detector = BroadbandPeakDetector()
        detector.setBPM(120)
        // 60 / 120 = 0.5 s beat period, × 0.4 = 0.2 s.
        #expect(abs(detector.currentRefractorySeconds - 0.2) < 1e-9)
        detector.setBPM(76)
        // 60 / 76 ≈ 0.789 s, × 0.4 ≈ 0.316 s.
        #expect(abs(detector.currentRefractorySeconds - 0.4 * 60.0 / 76.0) < 1e-9)
    }

    @Test("Zero or negative BPM falls back to the default refractory period")
    func zeroBPM_usesDefaultRefractory() {
        let detector = BroadbandPeakDetector()
        detector.setBPM(120)
        detector.setBPM(0)
        #expect(detector.currentRefractorySeconds == BroadbandPeakDetector.defaultRefractorySeconds)
    }

    @Test("Two pulses inside the refractory window collapse to one peak")
    func doubleHit_inRefractory_collapsesToOne() {
        let detector = BroadbandPeakDetector()
        detector.setBPM(120)   // 0.2 s refractory ≈ 12 frames at 60 fps
        let fps = 60.0
        var pulses: [Int: Float] = [:]
        pulses[12] = 5.0
        pulses[16] = 5.0   // 4 frames after the first — inside refractory
        let peaks = drivePulses(
            detector: detector,
            frames: 30,
            fps: fps,
            baselineFlux: 0.1,
            pulses: pulses
        )
        #expect(peaks.count == 1)
        #expect(peaks.first == 12)
    }

    // MARK: - Reset

    @Test("reset() clears median history and refractory state")
    func reset_clearsAllState() {
        let detector = BroadbandPeakDetector()
        detector.setBPM(120)
        let fps = 60.0
        let dt = Float(1.0 / fps)
        for _ in 0..<10 { _ = detector.process(smoothedFlux: 0.1, deltaTime: dt) }
        _ = detector.process(smoothedFlux: 5.0, deltaTime: dt)
        detector.reset()
        // Post-reset, the first frame is back to warmup — no peak even with
        // a huge value.
        let postReset = detector.process(smoothedFlux: 10.0, deltaTime: dt)
        #expect(postReset == false)
        // refractorySeconds is preserved by reset (per-track property,
        // set at installBPMPrior time).
        #expect(abs(detector.currentRefractorySeconds - 0.2) < 1e-9)
    }
}

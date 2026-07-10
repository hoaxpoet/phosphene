// SignalHealthMonitorTests — Unit tests for the input-chain health classifier.
//
// Uses an injected clock, a stub output-rate provider, and a dedicated serial
// evaluation queue drained synchronously between drives. Peak-band inputs are a
// real 440 Hz sine waveform at synthetically attenuated gain levels — this is
// measurement-path testing of the peak reduction, not FA #27 audio synthesis.

import Testing
import Foundation
@testable import Audio

// MARK: - Helpers

private final class Harness: @unchecked Sendable {
    var t: CFAbsoluteTime = 0
    var outputRate: Double = 48_000
    private let queue = DispatchQueue(label: "test.signalHealth.eval")
    private let lock = NSLock()
    private var _emissions: [SignalHealth] = []
    private let windowSeconds: TimeInterval
    private let deadTapConfirmSeconds: TimeInterval

    init(windowSeconds: TimeInterval = 1.0, deadTapConfirmSeconds: TimeInterval = 45.0) {
        self.windowSeconds = windowSeconds
        self.deadTapConfirmSeconds = deadTapConfirmSeconds
    }

    lazy var monitor: SignalHealthMonitor = {
        let m = SignalHealthMonitor(
            windowSeconds: windowSeconds,
            deadTapConfirmSeconds: deadTapConfirmSeconds,
            timeProvider: { [weak self] in self?.t ?? 0 },
            outputSampleRateProvider: { [weak self] in self?.outputRate ?? 0 },
            evaluationQueue: queue)
        m.onHealthChanged = { [weak self] h in
            self?.lock.withLock { self?._emissions.append(h) }
        }
        return m
    }()

    /// Drain pending async evaluations, then return the emission log.
    func emissions() -> [SignalHealth] {
        queue.sync {}
        return lock.withLock { _emissions }
    }

    var last: SignalHealth? { emissions().last }
}

/// A real 440 Hz sine waveform scaled to a target peak amplitude.
private func sine(amplitude: Float, count: Int = 512, sampleRate: Float = 48_000) -> [Float] {
    (0..<count).map { amplitude * sinf(2 * .pi * 440 * Float($0) / sampleRate) }
}

private func ingest(_ h: Harness, _ buffer: [Float]) {
    buffer.withUnsafeBufferPointer { h.monitor.ingest(samples: $0.baseAddress!, count: $0.count) }
}

// MARK: - Peak-band classification

@Test func test_healthyPeak_classifiesHealthy() {
    let h = Harness()
    let buf = sine(amplitude: 0.6)  // ≈ −4.4 dBFS
    h.t = 0; ingest(h, buf)
    h.t = 1; ingest(h, buf)  // closes the first window
    #expect(h.last?.peakBand == .healthy)
}

@Test func test_normalizedPeak_classifiesLow() {
    let h = Harness()
    let buf = sine(amplitude: 0.2)  // ≈ −14 dBFS (Spotify Normalize territory)
    h.t = 0; ingest(h, buf)
    h.t = 1; ingest(h, buf)
    #expect(h.last?.peakBand == .low)
}

@Test func test_attenuatedPeak_classifiesCritical() {
    let h = Harness()
    let buf = sine(amplitude: 0.1)  // ≈ −20 dBFS
    h.t = 0; ingest(h, buf)
    h.t = 1; ingest(h, buf)
    #expect(h.last?.peakBand == .critical)
}

@Test func test_noEmission_beforeFirstWindowCloses() {
    let h = Harness(windowSeconds: 5.0)
    let buf = sine(amplitude: 0.6)
    h.t = 0; ingest(h, buf)
    h.t = 2; ingest(h, buf)  // still inside the first window
    #expect(h.emissions().isEmpty)
}

// MARK: - Dead-tap detection

@Test func test_deadTap_firesAfterSustainedSilence() {
    let h = Harness(deadTapConfirmSeconds: 45)
    let silence = [Float](repeating: 0, count: 512)
    h.t = 0; ingest(h, silence)
    h.monitor.updateContext(signalState: .silent, tapModeActive: true)  // silentSince = 0
    h.t = 1; ingest(h, silence)   // window closes → dead not yet confirmed
    #expect(h.last?.deadTap == false)
    h.t = 46; h.monitor.updateContext(signalState: .silent, tapModeActive: true)
    #expect(h.last?.deadTap == true)
}

@Test func test_shortSilence_isNotDeadTap() {
    let h = Harness(deadTapConfirmSeconds: 45)
    let silence = [Float](repeating: 0, count: 512)
    h.t = 0; ingest(h, silence)
    h.monitor.updateContext(signalState: .silent, tapModeActive: true)
    h.t = 1; ingest(h, silence)
    h.t = 4; h.monitor.updateContext(signalState: .active, tapModeActive: true)  // audio resumes
    #expect(h.emissions().allSatisfy { !$0.deadTap })
}

@Test func test_deadTap_gatedOffForNonTapMode() {
    let h = Harness(deadTapConfirmSeconds: 45)
    let silence = [Float](repeating: 0, count: 512)
    h.t = 0; ingest(h, silence)
    h.monitor.updateContext(signalState: .silent, tapModeActive: false)  // local-file playback
    h.t = 1; ingest(h, silence)
    h.t = 60; h.monitor.updateContext(signalState: .silent, tapModeActive: false)
    #expect(h.last?.deadTap == false)
}

// MARK: - Sample-rate mismatch

@Test func test_sampleRateMismatch_firesOutsideExpectedFamily() {
    let h = Harness()
    h.outputRate = 96_000
    let buf = sine(amplitude: 0.6)
    h.t = 0; ingest(h, buf)
    h.t = 1; ingest(h, buf)
    #expect(h.last?.sampleRateMismatch == true)
    #expect(h.last?.outputSampleRateHz == 96_000)
}

@Test func test_expectedRate_noMismatch() {
    let h = Harness()
    h.outputRate = 44_100
    let buf = sine(amplitude: 0.6)
    h.t = 0; ingest(h, buf)
    h.t = 1; ingest(h, buf)
    #expect(h.last?.sampleRateMismatch == false)
}

@Test func test_unreadableRate_noMismatch() {
    let h = Harness()
    h.outputRate = 0  // query failed
    let buf = sine(amplitude: 0.6)
    h.t = 0; ingest(h, buf)
    h.t = 1; ingest(h, buf)
    #expect(h.last?.sampleRateMismatch == false)
}

// MARK: - Dedup + reset

@Test func test_unchangedHealth_doesNotReemit() {
    let h = Harness()
    let buf = sine(amplitude: 0.6)
    h.t = 0; ingest(h, buf)
    h.t = 1; ingest(h, buf)   // emit #1
    h.t = 2; ingest(h, buf)   // same health → no re-emit
    h.t = 3; ingest(h, buf)
    #expect(h.emissions().count == 1)
}

@Test func test_reset_clearsSilenceTiming() {
    let h = Harness(deadTapConfirmSeconds: 45)
    let silence = [Float](repeating: 0, count: 512)
    h.t = 0; ingest(h, silence)
    h.monitor.updateContext(signalState: .silent, tapModeActive: true)
    h.monitor.reset()
    h.t = 1; ingest(h, silence)
    h.t = 2; ingest(h, silence)  // close a window so evaluate runs
    h.t = 60; h.monitor.updateContext(signalState: .silent, tapModeActive: true)
    // silentSince was cleared by reset, then re-armed at t=60 → not yet dead.
    #expect(h.last?.deadTap == false)
}

// StemSeparatorConcurrencyTests — CLEAN.1.2 / BUG-031 regression coverage.
//
// Verifies the fix for the shared-`StemSeparator` race: with the full
// input→predict→output critical section under one lock AND stems returned BY
// VALUE, concurrent `separate()` calls on a single shared instance never
// cross-contaminate — each caller gets back its OWN stems. Before the fix (or
// if the lock is reverted) a silence caller could receive a loud caller's stems
// because both share the model's input/output buffers around the locked predict.
//
// Ground truth is instance-specific and threshold-free: silence stems carry far
// less energy than loud-sine stems, so with no contamination EVERY silence
// caller's energy is below EVERY sine caller's. The global `ConcurrencyAuditProbe`
// is intentionally NOT asserted here — its counters are process-global and would
// cross-contaminate across the parallel suite's many separator instances;
// per-caller returned-stem energy is the reliable, instance-local signal.
//
// Red/green: GREEN with the lock + return-by-value in place; A/B-demonstrated
// RED by temporarily removing the `lock.withLock` wrapper in
// `StemSeparator.separate()` (the BUG-034 temporary-revert precedent).

import Testing
import Foundation
import Metal
@testable import ML
@testable import Audio
@testable import Shared

/// Thread-safe accumulator for the concurrent-separation results. A reference
/// type captured by `let` keeps Swift 6 strict-concurrency happy (the NSLock is
/// the external synchronization the `@unchecked Sendable` asserts).
private final class EnergyCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var silence: [Float] = []
    private var sine: [Float] = []
    private var failures: [String] = []
    func addSilence(_ energy: Float) { lock.withLock { silence.append(energy) } }
    func addSine(_ energy: Float) { lock.withLock { sine.append(energy) } }
    func addFailure(_ message: String) { lock.withLock { failures.append(message) } }
    func snapshot() -> (silence: [Float], sine: [Float], failures: [String]) {
        lock.withLock { (silence, sine, failures) }
    }
}

@Suite("StemSeparator concurrency (CLEAN.1.2 / BUG-031)")
struct StemSeparatorConcurrencyTests {

    private static func totalEnergy(_ stems: [[Float]]) -> Float {
        var sum: Float = 0
        for waveform in stems {
            for sample in waveform { sum += sample * sample }
        }
        return sum
    }

    @Test func concurrentSeparations_returnPerCallerOwnStems() throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let separator = try StemSeparator(device: device)

        let silence = AudioFixtures.silence(sampleCount: 44_100 * 2)
        let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 44_100, duration: 1.0)
        let sine = AudioFixtures.mixStereo(left: mono, right: mono)

        // Sanity: the two inputs are distinguishable single-threaded — a loud sine
        // carries materially more stem energy than silence. Otherwise the
        // contamination discriminator below would be vacuous.
        let silenceBaseline = Self.totalEnergy(
            try separator.separate(audio: silence, channelCount: 2, sampleRate: 44_100).stemWaveforms
        )
        let sineBaseline = Self.totalEnergy(
            try separator.separate(audio: sine, channelCount: 2, sampleRate: 44_100).stemWaveforms
        )
        try #require(
            sineBaseline > silenceBaseline * 4 + 1e-3,
            "inputs not distinguishable: silence=\(silenceBaseline) sine=\(sineBaseline)"
        )

        // Fire many overlapping separations (alternating silence / loud sine) at
        // the ONE shared instance.
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stemsep.concurrency", attributes: .concurrent)
        let collector = EnergyCollector()

        let perKind = 6
        for i in 0..<(perKind * 2) {
            let isSilence = (i % 2 == 0)
            group.enter()
            queue.async {
                do {
                    let result = try separator.separate(
                        audio: isSilence ? silence : sine, channelCount: 2, sampleRate: 44_100
                    )
                    let energy = Self.totalEnergy(result.stemWaveforms)
                    if isSilence { collector.addSilence(energy) } else { collector.addSine(energy) }
                } catch {
                    collector.addFailure("\(error)")
                }
                group.leave()
            }
        }

        #expect(group.wait(timeout: .now() + 180) == .success, "concurrent separations timed out")
        let (silenceEnergies, sineEnergies, failures) = collector.snapshot()
        #expect(failures.isEmpty, "separations threw: \(failures)")
        #expect(silenceEnergies.count == perKind && sineEnergies.count == perKind)

        // The race-free contract: every silence caller's stems carry less energy
        // than every sine caller's. Cross-caller contamination (BUG-031) hands a
        // silence caller a sine caller's stems, lifting it above a sine minimum.
        let silenceMax = silenceEnergies.max() ?? .greatestFiniteMagnitude
        let sineMin = sineEnergies.min() ?? 0
        #expect(
            silenceMax < sineMin,
            "BUG-031 cross-caller contamination: silence-call energy \(silenceMax) ≥ sine-call energy \(sineMin)"
        )
    }
}

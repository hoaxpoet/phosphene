// InputLevelMonitorTests — Regression tests for InputLevelMonitor's signal-quality
// classification, EMA peak decay, band-energy bookkeeping, and hysteresis state
// machine.
//
// Filed as CA-Audio-FU-5 (capability-registry doc-only finding from the
// CA-Audio audit on 2026-05-21): InputLevelMonitor (322 LoC, production-active
// consumer at VisualizerEngine.swift:415) had ZERO dedicated tests prior to
// this file. The class implements a non-trivial state machine — 0.9995/update
// peak decay (~21 s time constant at the 94 Hz analysis rate), 30-frame grade
// hysteresis (gradeSwitchFrames=30), warmup gate (warmupFrames=60), and a
// peak-only classifier (treble-fraction gating removed post-2026-04-17T21-05-47Z
// after the Oxytocin false-positive). Without tests, a refactor or tuning
// change could silently regress any of these and the failure mode would be
// "the diagnostic overlay shows the wrong grade on real music."
//
// Test approach: drive the monitor through its public surface — submitSamples
// for peak/totalFrames updates, submitMagnitudes for band-EMA + snapshot
// publish, currentSnapshot for assertion. No injectable dependencies needed:
// the monitor consumes raw Float buffers, not protocol-bridged services. Float
// assertions use absolute tolerance because Float multiplication over 100
// iterations drifts in the 5th decimal. Each test instantiates a fresh
// monitor — no shared state, parallel-safe.

import Testing
import Foundation
@testable import Audio

// MARK: - Helpers

/// Submit a Float array as samples to InputLevelMonitor, avoiding the
/// `force_unwrapping` lint rule on the buffer baseAddress.
private func submitSamples(_ monitor: InputLevelMonitor, _ samples: [Float]) {
    samples.withUnsafeBufferPointer { buf in
        guard let ptr = buf.baseAddress else { return }
        monitor.submitSamples(pointer: ptr, count: buf.count)
    }
}

// MARK: - Peak Envelope Decay

/// Audit recommendation #1: submitSamples_peakDecaysAt0_9995.
/// The peak envelope rises instantly on the max-abs of the incoming sample
/// and decays at 0.9995 per call thereafter. Drive a known peak, then drive
/// N silent submissions; assert the published peakDBFS matches the analytical
/// 0.9995^N decay within Float tolerance. A regression that changed the
/// decay rate (e.g. to 0.999 for a faster window, or 0.9999 for slower) would
/// fail this test long before any visible diagnostic-overlay regression.
@Test func test_submitSamples_peakDecaysAt0_9995() {
    let monitor = InputLevelMonitor(sampleRate: 48_000)

    // Set the peak.
    submitSamples(monitor, [0.5])  // peakEnvelope = 0.5

    // 100 silent submissions decay peakEnvelope by 0.9995^100.
    let silent: [Float] = [0.0]
    for _ in 0..<100 {
        submitSamples(monitor, silent)
    }

    // Trigger snapshot publish — submitMagnitudes is the only path that
    // recomputes; submitSamples updates state without publishing.
    let mags = [Float](repeating: 0.1, count: 128)
    monitor.submitMagnitudes(mags, sampleRate: 48_000)

    // Expected: 0.5 * 0.9995^100 ≈ 0.4756 → -6.46 dBFS. Compute with the
    // same accumulation pattern as the implementation for tightest agreement.
    var expectedEnvelope: Float = 0.5
    for _ in 0..<100 { expectedEnvelope *= 0.9995 }
    let expectedDB = 20 * log10f(expectedEnvelope)

    let snapshot = monitor.currentSnapshot()
    #expect(abs(snapshot.peakDBFS - expectedDB) < 0.01)
}

// MARK: - Band Energy EMAs

/// Audit recommendation #2: submitMagnitudes_bandEnergyEMA — adapted to
/// "dominant band" routing. The band-energy EMAs accumulate squared
/// magnitudes per band (sub 20-250 Hz, mid 250-4000 Hz, treble 4000-20000 Hz)
/// and the published snapshot reports the normalised ratio of each band's
/// energy to total. Verify each band by constructing a magnitude spectrum
/// that concentrates energy in that band alone and asserting the
/// corresponding ratio dominates. A regression that swapped band indices
/// (e.g. confused sub with treble in the bin-bound math) would flip the
/// asserted ratios and fail this test.
@Test func test_submitMagnitudes_bandEnergyDominantBand() {
    // sampleRate=48000, 128 bins → binWidth = 24000/128 = 187.5 Hz.
    // sub: Int(20/187.5)=0..Int(250/187.5)=1  → bin 0 only
    // mid: Int(250/187.5)=1..Int(4000/187.5)=21
    // treble: Int(4000/187.5)=21..Int(20000/187.5)=106

    // Sub-only spectrum.
    let monitorSub = InputLevelMonitor(sampleRate: 48_000)
    var subMags = [Float](repeating: 0, count: 128)
    subMags[0] = 1.0
    monitorSub.submitMagnitudes(subMags, sampleRate: 48_000)
    let snapSub = monitorSub.currentSnapshot()
    #expect(snapSub.subRatio > 0.99)
    #expect(snapSub.midRatio < 0.01)
    #expect(snapSub.trebleRatio < 0.01)

    // Treble-only spectrum.
    let monitorTreble = InputLevelMonitor(sampleRate: 48_000)
    var trebleMags = [Float](repeating: 0, count: 128)
    for i in 21..<106 { trebleMags[i] = 1.0 }
    monitorTreble.submitMagnitudes(trebleMags, sampleRate: 48_000)
    let snapTreble = monitorTreble.currentSnapshot()
    #expect(snapTreble.trebleRatio > 0.99)
    #expect(snapTreble.subRatio < 0.01)
    #expect(snapTreble.midRatio < 0.01)
}

// MARK: - Warmup

/// Audit recommendation #3: recompute_warmupReturnsUnknown.
/// Before warmupFrames (60) sample submissions accumulate via submitSamples,
/// the published quality is .unknown with reason "warming up", regardless of
/// what magnitudes are submitted. Once warmup completes, the next magnitudes
/// call publishes a real classification (.green here, since the warmup peak
/// of 0.5 is well above the -9 dBFS warning threshold). A regression that
/// dropped the warmup gate would publish a real grade on the very first
/// frame — fine on a stable signal, but flappy at every capture restart.
@Test func test_recompute_warmupReturnsUnknown() {
    let monitor = InputLevelMonitor(sampleRate: 48_000)

    // Pre-warmup magnitudes call — quality is .unknown.
    let mags = [Float](repeating: 0.1, count: 128)
    monitor.submitMagnitudes(mags, sampleRate: 48_000)
    #expect(monitor.currentSnapshot().quality == .unknown)
    #expect(monitor.currentSnapshot().reason == "warming up")

    // Drive 60 sample submissions to satisfy warmupFrames.
    let highPeak: [Float] = [0.5]
    for _ in 0..<60 {
        submitSamples(monitor, highPeak)
    }

    // Post-warmup magnitudes call — quality leaves .unknown.
    monitor.submitMagnitudes(mags, sampleRate: 48_000)
    #expect(monitor.currentSnapshot().quality == .green)
}

// MARK: - Green low-treble hint (FL.11 follow-up)

/// A GREEN-level signal (peak well above the warning floor) with essentially no treble energy —
/// a dark/vintage recording (Beethoven/Walter ≈ 0.58%) or a bass-heavy modern mix — stays GREEN but
/// appends a neutral "high-register visuals will read faint" note, so the quiet high/cyan family isn't
/// mistaken for a bug. A bright signal must NOT flag it. The grade itself never changes (treble never
/// gates the grade — the 2026-04-17 lesson).
@Test func test_greenLowTreble_appendsFaintHint() {
    let low = InputLevelMonitor(sampleRate: 48_000)
    for _ in 0..<60 { submitSamples(low, [0.5]) }        // warmup + green peak (−6 dBFS)
    var bassMags = [Float](repeating: 0, count: 128)
    for i in 0..<20 { bassMags[i] = 1.0 }                // sub band only → treble ratio ≈ 0
    low.submitMagnitudes(bassMags, sampleRate: 48_000)
    let lowSnap = low.currentSnapshot()
    #expect(lowSnap.quality == .green)
    #expect(lowSnap.reason.contains("low treble"),
            "green + near-zero treble should append the faint-highs note (got: \(lowSnap.reason))")

    let bright = InputLevelMonitor(sampleRate: 48_000)
    for _ in 0..<60 { submitSamples(bright, [0.5]) }
    var trebMags = [Float](repeating: 0, count: 128)
    for i in 21..<106 { trebMags[i] = 1.0 }              // treble band → healthy treble ratio
    bright.submitMagnitudes(trebMags, sampleRate: 48_000)
    let brightSnap = bright.currentSnapshot()
    #expect(brightSnap.quality == .green)
    #expect(!brightSnap.reason.contains("low treble"),
            "a bright signal must not flag low treble (got: \(brightSnap.reason))")
}

// MARK: - Below-Critical Classification

/// Audit recommendation #4: recompute_belowCriticalReturnsRed.
/// A sustained peak below peakCriticalDBFS (-15 dBFS = 0.1778 abs) classifies
/// as .red with a reason string that names the actual peak in dBFS. Drive a
/// peak of 0.1 (-20 dBFS) through warmup and assert. A regression of the
/// critical threshold (e.g. shifting to -12 dBFS) would mis-classify the
/// chronic-low-peak case and the operator would lose the BlackHole /
/// Multi-Output / normalisation-on diagnostic.
@Test func test_recompute_belowCriticalReturnsRed() {
    let monitor = InputLevelMonitor(sampleRate: 48_000)
    let lowPeak: [Float] = [0.1]  // -20 dBFS, below -15 critical

    // 60 submissions satisfy warmup and pin peakEnvelope at 0.1.
    for _ in 0..<60 {
        submitSamples(monitor, lowPeak)
    }

    let mags = [Float](repeating: 0.05, count: 128)
    monitor.submitMagnitudes(mags, sampleRate: 48_000)

    let snapshot = monitor.currentSnapshot()
    #expect(snapshot.quality == .red)
    #expect(snapshot.reason.contains("dBFS"))
}

// MARK: - Hysteresis

/// Audit recommendation #5: recompute_hysteresisRequires30Frames.
/// Once a stable grade is published, switching to a different candidate
/// requires gradeSwitchFrames (30) consecutive recomputes before the new
/// grade is published. Drive .red, then spike to a .green candidate; assert
/// the 29th post-spike recompute still publishes .red, and the 30th flips
/// to .green. The 30-frame literal is regression-locked at the observation
/// level: a future tuning change (e.g. to 60 for stricter smoothing) would
/// fail this test, forcing the author to either update the test in the same
/// increment with the rationale or revert the tuning. Same shape as
/// AudioInputRouterSignalStateTests.test_reinstallDelays_matchDesignSpec.
@Test func test_recompute_hysteresisRequires30Frames() {
    let monitor = InputLevelMonitor(sampleRate: 48_000)

    // Warmup with low peak (-20 dBFS, .red candidate).
    let lowPeak: [Float] = [0.1]
    for _ in 0..<60 {
        submitSamples(monitor, lowPeak)
    }

    // First magnitudes call publishes .red (warmup-bypass).
    let mags = [Float](repeating: 0.05, count: 128)
    monitor.submitMagnitudes(mags, sampleRate: 48_000)
    #expect(monitor.currentSnapshot().quality == .red)

    // Spike peak to high (-6 dBFS, .green candidate). peakEnvelope jumps to
    // 0.5 instantly via max() — slow decay does not delay this.
    submitSamples(monitor, [0.5])

    // 29 recomputes — published grade stays .red (hysteresis pending).
    for _ in 0..<29 {
        monitor.submitMagnitudes(mags, sampleRate: 48_000)
    }
    #expect(monitor.currentSnapshot().quality == .red)

    // 30th recompute — pendingCount hits gradeSwitchFrames; grade flips.
    monitor.submitMagnitudes(mags, sampleRate: 48_000)
    #expect(monitor.currentSnapshot().quality == .green)
}

// MARK: - Reset

/// Audit recommendation #6: reset_clearsAllEnvelopes.
/// reset() zeroes every envelope, the frame counter, AND replaces the
/// snapshot with the default InputLevelSnapshot() (quality .unknown, all
/// dBFS at -120, all ratios at 0). Required when the audio tap reinstalls
/// (so stale envelopes from the previous capture session don't bleed in).
/// A regression that forgot to reset the snapshot field would leave a stale
/// .green / .red reading visible until the next post-warmup magnitudes call,
/// confusing the operator during a reinstall sequence.
@Test func test_reset_clearsAllEnvelopes() {
    let monitor = InputLevelMonitor(sampleRate: 48_000)

    // Drive arbitrary state.
    for _ in 0..<10 {
        submitSamples(monitor, [0.3])
    }
    let mags = [Float](repeating: 0.05, count: 64)
    monitor.submitMagnitudes(mags, sampleRate: 48_000)
    let preReset = monitor.currentSnapshot()
    #expect(preReset.peakDBFS > -120)
    #expect(preReset.frameCount == 10)

    // Reset.
    monitor.reset()

    // No new submission needed — reset() also overwrites snapshot to default.
    let postReset = monitor.currentSnapshot()
    #expect(postReset.peakDBFS == -120)
    #expect(postReset.rmsDBFS == -120)
    #expect(postReset.subRatio == 0)
    #expect(postReset.midRatio == 0)
    #expect(postReset.trebleRatio == 0)
    #expect(postReset.quality == .unknown)
    #expect(postReset.reason == "warming up")
    #expect(postReset.frameCount == 0)
}

// MARK: - Peak-Only Classification (Oxytocin Defence)

/// Productivity test: regression-locks the post-2026-04-17T21-05-47Z change
/// to peak-only classification. The pre-fix monitor consumed treble fraction
/// as a Bluetooth/AirPlay codec discriminator and falsely fired warnings on
/// bass-heavy modern productions (Oxytocin: clean stereo chain, 0.1 % treble).
/// The fix removed treble thresholds; treble ratio remains in the snapshot
/// for diagnostic display only.
///
/// Test: drive a high peak (.green-classifying) with a bass-only spectrum,
/// then flood the EMAs with treble-only spectra. The grade must remain
/// .green at all times — spectrum balance does NOT influence classification.
/// A regression that re-introduced treble-balance gating would flip this to
/// .yellow or .red and the Oxytocin false-positive would be back.
@Test func test_classification_isPeakOnlyNotTrebleSensitive() {
    let monitor = InputLevelMonitor(sampleRate: 48_000)

    // Warmup with high peak (.green candidate).
    for _ in 0..<60 {
        submitSamples(monitor, [0.5])
    }

    // Bass-only spectrum (Oxytocin-shaped: all energy in sub band).
    var bassOnly = [Float](repeating: 0, count: 128)
    bassOnly[0] = 1.0
    monitor.submitMagnitudes(bassOnly, sampleRate: 48_000)
    #expect(monitor.currentSnapshot().quality == .green)
    #expect(monitor.currentSnapshot().trebleRatio < 0.01)

    // Flood with treble-rich spectrum — 35 calls > gradeSwitchFrames.
    // EMAs converge to fully-treble; grade must remain .green throughout.
    var trebleRich = [Float](repeating: 0, count: 128)
    for i in 21..<106 { trebleRich[i] = 1.0 }
    for _ in 0..<35 {
        monitor.submitMagnitudes(trebleRich, sampleRate: 48_000)
    }
    let final = monitor.currentSnapshot()
    #expect(final.quality == .green)
    #expect(final.trebleRatio > 0.99)
}

// MARK: - Threshold-Constant Regression-Lock

/// Productivity test: the three public thresholds drive the entire
/// classifier — peakWarningDBFS (-9, yellow/green border), peakCriticalDBFS
/// (-15, red/yellow border), and warmupFrames (60, .unknown gate). Locking
/// the literal values here prevents a silent "let's nudge these by 1 dB"
/// PR from changing observable diagnostic behaviour without discussion.
/// Same shape as AudioInputRouterSignalStateTests.test_reinstallDelays_matchDesignSpec.
/// If a real tuning change ships, this test must be updated in the same
/// increment with the rationale in the commit message.
@Test func test_thresholdConstants_matchDesignSpec() {
    #expect(InputLevelMonitor.peakWarningDBFS == -9)
    #expect(InputLevelMonitor.peakCriticalDBFS == -15)
    #expect(InputLevelMonitor.warmupFrames == 60)
}

// MIRSampleRateReconfigureTests — BUG-053 / CLEAN.3.7-fix regression gate.
//
// Locks the rate-awareness of the LIVE MIR path: the pipeline is constructed
// before the tap installs (at the 48 kHz default) and must adopt the actual
// tap rate via `setSampleRate(_:)` so every bin→Hz stage (centroid, bands,
// chroma/key) interprets the FFT magnitudes at the real rate — the FFT
// magnitude array itself is rate-independent, so this is the only place the
// live analysis learns the true rate.
//
// GPU-free (pure DSP, no Metal / MPSGraph) → joins the CI fast-gate allow-list.
// The live wiring (VisualizerEngine calls setSampleRate on the analysis queue)
// can't be unit-tested under SPM (Metal + tap) — same documented limit as
// TapSampleRateRegressionTests; that leg is the manual 44.1 kHz device check.

import Testing
import Foundation
@testable import DSP

@Suite("MIR sample-rate reconfigure (BUG-053)")
struct MIRSampleRateReconfigureTests {

    /// Energy-weighted centroid of a single-bin spike is exactly that bin's
    /// frequency, so a spike at bin `b` makes the raw (Hz) centroid a clean
    /// probe of the bin→Hz mapping.
    private static let spikeBin = 100
    private static let fftSize: Float = 1024

    private func spikeMagnitudes(bin: Int = spikeBin, count: Int = 512) -> [Float] {
        var m = [Float](repeating: 0, count: count)
        m[bin] = 1.0
        return m
    }

    private func argmax(_ v: [Float]) -> Int {
        var best = 0
        for i in 1..<v.count where v[i] > v[best] { best = i }
        return best
    }

    private func settle(_ mir: MIRPipeline, _ mags: [Float], frames: Int = 120) {
        for _ in 0..<frames {
            _ = mir.process(magnitudes: mags, fps: 60, time: 0, deltaTime: 1.0 / 60.0)
        }
    }

    // MARK: - Construction default + switch

    @Test("live pipeline defaults to 48 kHz and switches on setSampleRate")
    func test_defaultRate_thenSwitch() {
        let mir = MIRPipeline()
        #expect(mir.sampleRate == 48000)   // the live construction default (VisualizerEngine.swift:740)
        mir.setSampleRate(44100)
        #expect(mir.sampleRate == 44100)
        // No-op when unchanged (cheap per-frame guard).
        mir.setSampleRate(44100)
        #expect(mir.sampleRate == 44100)
        // Defensive: a zero/negative rate is ignored.
        mir.setSampleRate(0)
        #expect(mir.sampleRate == 44100)
    }

    // MARK: - End-to-end: centroid (Hz) tracks the rate

    @Test("raw centroid scales with the configured rate (48k/44.1k ratio)")
    func test_rawCentroid_tracksRate() {
        let mags = spikeMagnitudes()

        let mir = MIRPipeline()                 // 48 kHz
        settle(mir, mags)
        let centroid48 = mir.rawSmoothedCentroid

        mir.setSampleRate(44100)
        settle(mir, mags)
        let centroid44 = mir.rawSmoothedCentroid

        // Lower rate → fewer Hz per bin → lower centroid for the same spike bin.
        #expect(centroid48 > centroid44)
        // The ratio is exactly the rate ratio — proves the centroid is computed
        // from the configured rate, not a hardcoded one.
        let expected = 48000.0 / 44100.0
        #expect(abs(centroid48 / centroid44 - Float(expected)) < 0.01)
        // Sanity: bin 100 at 48 kHz is 100 * 48000/1024 ≈ 4687.5 Hz.
        #expect(abs(centroid48 - Float(Self.spikeBin) * 48000.0 / Self.fftSize) < 1.0)
    }

    // MARK: - End-to-end: chroma/key pitch mapping is rate-aware

    @Test("a fixed spike maps to a different pitch class at 48k vs 44.1k")
    func test_chromaPitchClass_tracksRate() {
        let mags = spikeMagnitudes()   // bin 100 → D(2) at 48k, C(0) at 44.1k (~1.5 semitone shift)

        let mir = MIRPipeline()        // 48 kHz
        _ = mir.process(magnitudes: mags, fps: 60, time: 0, deltaTime: 1.0 / 60.0)
        let pc48 = argmax(mir.latestChroma)

        mir.setSampleRate(44100)
        _ = mir.process(magnitudes: mags, fps: 60, time: 0, deltaTime: 1.0 / 60.0)
        let pc44 = argmax(mir.latestChroma)

        #expect(pc48 != pc44)   // wrong rate ⇒ wrong key; the mapping must track the rate
    }

    // MARK: - Sub-analyzer unit: bin→Hz table + the kickoff's "different bin" check

    @Test("SpectralAnalyzer recomputes binResolution + frequency table on reconfigure")
    func test_spectralAnalyzer_reconfigure() {
        let sa = SpectralAnalyzer()
        #expect(abs(sa.binResolution - 48000.0 / Self.fftSize) < 0.001)
        sa.setSampleRate(44100)
        #expect(abs(sa.binResolution - 44100.0 / Self.fftSize) < 0.001)
        sa.setSampleRate(0)   // ignored
        #expect(abs(sa.binResolution - 44100.0 / Self.fftSize) < 0.001)
    }

    @Test("a band cutoff lands on a different bin index at 48k vs 44.1k")
    func test_bandCutoff_differentBin() {
        // The CLEAN.3.7c assertion: prove no stage hardcodes the rate by showing
        // a cutoff maps to a different bin index across rates.
        let sa = SpectralAnalyzer()
        let cutoffHz: Float = 4000   // 3-band mid/treble boundary
        let bin48 = Int(cutoffHz / sa.binResolution)
        sa.setSampleRate(44100)
        let bin44 = Int(cutoffHz / sa.binResolution)
        #expect(bin48 != bin44)      // 85 (48k) vs 92 (44.1k)
        #expect(bin48 < bin44)       // lower rate → finer bins → higher index for a fixed Hz
    }

    @Test("BandEnergyProcessor reassigns a near-boundary spike across bands on reconfigure")
    func test_bandEnergy_reconfigure() {
        // Bin 92 ≈ 4312 Hz at 48 kHz (treble, >4000) but ≈ 3962 Hz at 44.1 kHz
        // (mid, <4000) — so the same spike lands in different 3-bands.
        let be = BandEnergyProcessor()
        let mags = spikeMagnitudes(bin: 92)
        var last = BandEnergyProcessor.Result.zero
        for _ in 0..<90 { last = be.process(magnitudes: mags, fps: 60) }
        #expect(last.treble > last.mid)   // 48 kHz: spike is in treble

        be.setSampleRate(44100)
        for _ in 0..<90 { last = be.process(magnitudes: mags, fps: 60) }
        #expect(last.mid > last.treble)   // 44.1 kHz: same spike is now in mid
    }
}
